# ADR 0006: Keep venue and event data separately owned with explicit collaboration

- **Status:** Proposed — awaiting product-owner confirmation
- **Date:** 2026-11-10
- **Related:** ADR 0004, [Issue #12](https://github.com/TeraflopsBH/eventor/issues/12)
- **Design proposal:** [Cross-Organization Collaboration v0.3](../implementation-design/v0.3/CROSS_ORGANIZATION_COLLABORATION_DESIGN_v0.3.md)

## Context

ADR 0004 makes venue-provider and event-organizer responsibilities distinct. They may be different organizations. The v0.2 schema does not fully support this case because many composite foreign keys assume the booking, venue and operational event all share one organization_id. In particular, booking-to-event links, event-session-to-space links and guest-allocation-to-resource links are same-organization relationships.

A common real-world case is GHB owning a venue and booking record while an independent conference organizer owns the event, guest list, invitations, RSVP, seating decisions and attendance.

## Proposed decision

1. Keep venue master data, venue-space revisions, booking aggregates and venue-service fulfilment under the venue provider organization.
2. Keep event, guest registry, invitations, RSVP, seating decisions, attendance and organizer-side event operations under the organization assigned to operate the event/module.
3. External customers do not automatically become Eventor tenants or users. A booking-only workflow requires no operational-event data.
4. When both parties use the same Eventor deployment, create explicit collaboration grants and booking-event association records with distinct owner organization IDs.
5. Share approved venue geometry and resource inventory through immutable, purpose-limited event-owned snapshots that preserve source provider/revision/hash/grant provenance. Do not grant direct write access to provider master venue data.
6. Assign task/module accountability and performing parties explicitly. A task grant exposes only the minimum data needed to perform it.
7. No broad tenant membership or guest-data visibility is implied by booking, venue ownership or a collaboration link.

## Consequences

- The v0.2 same-organization foreign-key assumptions must be revised in a successor schema.
- A scoped collaboration grant and grant lifecycle are required.
- Booking-event linking must support separate owner organizations.
- Event sessions and allocations must reference event-owned shared venue snapshots/resources.
- RLS and authorization must remain tenant-isolated; collaboration uses explicit scoped projections.
- Historical venue snapshots and operational records remain auditable after grant expiry/revocation; new access is blocked.
- This proposal must be confirmed before schema implementation; it is not accepted architecture yet.
