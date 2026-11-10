# Implementation Design v0.3 — domain design addenda

**Status:** proposed detailed domain/API designs; successor migrations, API contract validation and implementation remain open.

This directory contains successor design addenda that refine the historical v0.2 design snapshot. They do not modify or replace the v0.2 SQL/OpenAPI artifacts.

## Contents

- [RSVP and Invitation Design v0.3](RSVP_AND_INVITATION_DESIGN_v0.3.md) — state separation, event policy, secure links, guest self-service, staff capture, proposed data model, API routes, access control, operating scope and acceptance scenarios.
- [Cross-Organization Collaboration Design v0.3](CROSS_ORGANIZATION_COLLABORATION_DESIGN_v0.3.md) — venue-provider/organizer ownership, booking-event links, scoped collaboration grants and immutable venue-plan snapshots.
- [OpenAPI v0.3 contract](../../api/openapi.v0.3.yaml) — concrete contract draft aligned to the API design and the v0.3 domain addenda.
- [Cancellation and Event Disruption Design v0.3](CANCELLATION_AND_EVENT_DISRUPTION_DESIGN_v0.3.md) — booking cancellation by customer or venue provider, event cancellation/postponement by organizer, notification audiences, cross-organization boundaries, audit and acceptance scenarios.

## Parent documents and decisions

- [Technical Blueprint v1.2](../../blueprint/v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md)
- [Implementation Design v0.2](../v0.2/Event_Operations_Implementation_Design_v0.2.md) — historical design snapshot
- [Operating Model](../../OPERATING_MODEL.md)
- [ADR 0004: Optional event operations scope](../../decisions/0004-optional-event-operations-scope.md)
- [ADR 0005: Separate invitations, RSVP and attendance](../../decisions/0005-separate-invitations-rsvp-attendance.md)
- [ADR 0006: Cross-organization collaboration](../../decisions/0006-cross-organization-collaboration.md) — accepted architectural decision.

## Implementation handoff

- RSVP schema/API implementation and test coverage: [Issue #10](https://github.com/TeraflopsBH/eventor/issues/10).
- Database integrity and reservation design: [Issue #13](https://github.com/TeraflopsBH/eventor/issues/13).
- OpenAPI v0.3 coverage: [Issue #17](https://github.com/TeraflopsBH/eventor/issues/17).
- Booking cancellation and event-disruption design/contract alignment: [Issue #21](https://github.com/TeraflopsBH/eventor/issues/21).

Do not alter the v0.2 SQL/OpenAPI snapshots to implement these designs. The successor schema and API contracts must be reviewed together and validated against PostgreSQL/OpenAPI tooling before application implementation.
