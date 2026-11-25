# ADR 0021 — Authorized booking/event association commands

- Status: accepted.
- Date: 2026-11-25.
- Related: #104/#112, ADR 0004/0006, Cross-Organization Collaboration v0.3.

## Decision

Expose the existing `booking_event_links` aggregate through explicit create/list commands. The event organization owns the association. An active actor needs `event.manage` for that exact event. A same-organization association additionally requires `booking.manage` for the booking and carries no collaboration grant. A cross-organization association requires an active, accepted, unexpired booking-scoped grant from the booking owner to the event owner with `booking.event.link` and the exact booking ID. Existing grant/creator/audit triggers remain authoritative.

An association records a relationship between existing booking and event identities. It reserves no capacity and changes no booking/event status, commercial terms, guest data or snapshots. Existing record statuses are not reinterpreted as availability. The API accepts a null/omitted grant for same-organization links, reconciling the historical external-only request schema with the existing relational model.

An identical active association returns its original ID. Different relationship kinds/grants and ended/revoked associations require separate correction; create never silently repurposes or reactivates them. The event row serializes duplicate creation before the existing audited BEFORE INSERT trigger. This avoids phantom duplicate audit entries from an INSERT/ON CONFLICT path. Current event, booking or collaboration authority is checked again before an idempotent cached response is returned.

## Projection and boundary

Event managers can page their own event's association metadata, including terminal records, after a source grant is revoked. This preserves event-owned provenance, not future provider access. The allowlisted projection contains IDs, relationship kind, association status and creation time; provider commercial data, contact details and organizer guest records are excluded. It does not enumerate the provider's other bookings or the organizer's other events. Read access is audited in the event owner's tenant.

Migration 194 revokes direct application-role access to the association table and grants runtime execution only on the scoped commands. It introduces no parallel aggregate, backfill or new permissions. Existing owner-level maintenance and append-only attribution remain. No tenant context is switched to bypass RLS. Invalid/stale authority or conflicting association meaning refuses the whole command.

## Delivery scope

This is an API/command foundation with explicit OpenAPI/shared client types. The staff booking/event selector, association correction/lifecycle UI, disruption delivery, acknowledgement and event resolution remain separate work under #112. Creating an association sends no message and grants no guest-directory access. This does not complete collaboration or production acceptance.


## Staff selector and display extension — migration 195

The staff Events panel explicitly confirms selection from the selected organization's permitted booking references. Users never supply organization identifiers in this flow. The existing booking metadata lookup is exposed through a generic reference-search alias, retaining its server scope filtering. Same-organization reference labels require current booking management; external/restricted links remain generic. Membership in a second tenant does not grant cross-tenant reference access. The event-history projection index changes no lifecycle facts.

The selector supports existing relationship kinds and paginated read-only history. It does not add partner discovery, association correction/reactivation, notice publication or event resolution. Failed authority clears private panel results; a multi-request reload publishes results only when both requests succeed. English/Bosnian controls, explicit confirmation, labeled inputs, keyboard-scrollable history and browser checks cover the user-visible boundary.

## Attributed ending extension — migration 197

An exact event manager may explicitly end the event-owned association, including a restricted local reference or a partner link whose source grant has since been revoked. Ending changes only the link's one-way status/actor fields under the existing audit trigger. It does not require source booking authority because it mutates no provider record or collaboration grant. The fixed `event_manager_ended` audit reason identifies the chosen command; it does not invent an operational/business explanation or require a user to type a code.

Ended links retain their original actor/reason and audit on retries. Revoked links cannot be relabelled, and create never reactivates either terminal status. Event-row locking follows creation/publication lock order: a concurrent notice publication commits wholly before ending or is rejected after ending. Previously published event receipts remain readable/acknowledgeable under their own event authority. API cached replies recheck exact event scope.

The bilingual staff action requires confirmation explaining the retained history and separate booking/event decisions. Booking status, reservations, event modules, grants, snapshots and prior notices remain unchanged. This supplies retirement only; changing relationship meaning, reactivation and partner setup remain separate work.
