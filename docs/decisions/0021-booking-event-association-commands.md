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
