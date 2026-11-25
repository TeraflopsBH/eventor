# ADR 0022 — Explicit event disruption publication and acknowledgement

- Status: accepted.
- Date: 2026-11-25.
- Related: #112, ADR 0004/0006/0021, Cancellation and Event Disruption Design v0.3.

## Context

Provider notices are append-only source facts. Recording one neither informs a linked event manager nor authorizes disclosure of internal booking data. An event-owned receipt aggregate already exists, but its original mandatory collaboration grant excluded same-organization operations. Treating a booking link as broad read permission would cross field and role boundaries.

## Decision

Reuse `event_disruption_resolutions` for explicitly published receipts. The initial command supports same-organization source bookings only. A sender needs current exact `event.manage` and `booking.manage`, an active local booking/event association, and a source notice belonging to that booking. The sender deliberately publishes an allowlisted version-1 snapshot: notice code, reason category, public summary, affected times and issuance time. No operational summary, commercial/booking reference, contact, guest data or resolution notes enter the projection. This is explicit internal inbox publication, not email delivery or automatic fan-out.

The event manager can subsequently read and acknowledge the event-owned public snapshot without booking management. Losing source authority blocks new publication and cached publication retries; it does not erase an intentionally published historical receipt. Losing event authority blocks reads, acknowledgements and cached acknowledgement replies. Tenant context is never switched. Cross-organization publication is deferred until accepted grant capabilities and partner controls are implemented; cross-organization historical receipt provenance remains supported.

One event/source/provider tuple identifies a receipt. Event-row locking serializes publication before insertion/audit. A duplicate returns the original receipt; no duplicate publication audit is emitted. Acknowledgement locks that receipt, changes only `received` to `acknowledged`, and preserves the first actor/time. Retrying against an advanced resolution state returns it unchanged. `noticeId` in the acknowledgement API identifies the event receipt, not the provider's source notice.

Migration 196 allows local null-grant receipts while retaining mandatory matching provider grants for external receipts. It adds uniqueness and immutable provenance/first-acknowledgement guards, revokes direct application-role access, and grants only scoped command execution. Existing duplicate or incompatible legacy rows stop migration for explicit reconciliation; no history is silently consolidated or deleted. Legacy snapshots of unsupported versions project no source payload; resolution ciphertext is never projected.

## Consequences and limits

Publication and acknowledgement are audited and leave booking/event status, schedules, reservations, guest modules, invitations and RSVP unchanged. Acknowledgement means receipt was seen; it is neither resolution nor acceptance of a booking amendment. No cancellation, postponement, relocation, notification campaign, outbox delivery or commercial decision is inferred. Those commands and partner delivery remain subsequent #112 slices. The API foundation does not by itself expose staff action controls.

SQL/API tests cover scope, revocation, safe snapshots, immutable provenance, unchanged aggregates, pagination and retry identity. Real PostgreSQL concurrent publication and acknowledgement tests require one receipt, one audit per transition and the original acknowledgement timestamp. Live SMTP/HTTPS and production installation acceptance are separate.
