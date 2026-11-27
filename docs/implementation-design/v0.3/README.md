# Implementation Design v0.3 — domain design addenda

**Status:** proposed detailed domain/API designs; successor migrations, API contract validation and implementation remain open.

This directory contains successor design addenda that refine the historical v0.2 design snapshot. They do not modify or replace the v0.2 SQL/OpenAPI artifacts.

## Contents

- [RSVP and Invitation Design v0.3](RSVP_AND_INVITATION_DESIGN_v0.3.md) — state separation, event policy, secure links, guest self-service, staff capture, proposed data model, API routes, access control, operating scope and acceptance scenarios.
- [Cross-Organization Collaboration Design v0.3](CROSS_ORGANIZATION_COLLABORATION_DESIGN_v0.3.md) — venue-provider/organizer ownership, booking-event links, scoped collaboration grants and immutable venue-plan snapshots.
- [OpenAPI v0.3 contract](../../api/openapi.v0.3.yaml) — concrete contract draft aligned to the API design and the v0.3 domain addenda.
- [Cancellation and Event Disruption Design v0.3](CANCELLATION_AND_EVENT_DISRUPTION_DESIGN_v0.3.md) — booking cancellation by customer or venue provider, event cancellation/postponement by organizer, notification audiences, cross-organization boundaries, audit and acceptance scenarios.

- [Template Design Studio v1.0](TEMPLATE_DESIGN_STUDIO_DESIGN_v1.0.md) — approved Phase 7 scope for rich-text WYSIWYG, responsive block email and graphical invitation/card design; implementation/library decisions deferred to #111. No change to current coding priorities.

- [Platform Administration Center v1.0](PLATFORM_ADMINISTRATION_CENTER_DESIGN_v1.0.md) — approved owner/Superadmin control-plane scope; global governance, platform identity, support and host operations. Successor authority decisions and implementation remain pending; coordinates #104/#108/#111 and TDS, without changing current priorities.

- [Organization Administration Center v1.0](ORGANIZATION_ADMINISTRATION_CENTER_DESIGN_v1.0.md) — approved organization self-service, onboarding and administration scope.
- [Eventor User Experience and Navigation v1.0](EVENTOR_USER_EXPERIENCE_AND_NAVIGATION_v1.0.md) — approved shared experience contract for PAC/OAC/EOC and specialist surfaces.
- [Organization Lifecycle Acceptance Scenarios v1.0](ORGANIZATION_LIFECYCLE_ACCEPTANCE_SCENARIOS_v1.0.md) — approved future verification contract (not executed tests).

**Approval record — 2026-11-27:** Owner approved the three v1.0 scopes for documentation integration on 2026-11-27. The three reviewed source files are preserved verbatim, including their historical proposed-status text; this approval record governs their integration status, not approval of exact engineering decisions or immediate implementation. Existing accepted ADRs, historical Blueprint v1.2/v0.2 snapshots, issue obligations and current #104/#112 → #105–107 priorities remain unchanged. No runtime implementation or acceptance results are implied.

| Reviewed source file | SHA-256 (original bytes) |
|---|---|
| ORGANIZATION_ADMINISTRATION_CENTER_DESIGN_v1.0.md | `3b6155e76b6b848d044a991220b9d669b35b8b620f192fac6decfd741788d5e7` |
| EVENTOR_USER_EXPERIENCE_AND_NAVIGATION_v1.0.md | `0c9f3c469e92815f2a8794391906382ff09d5b952d775b212f2e9fc977100b5a` |
| ORGANIZATION_LIFECYCLE_ACCEPTANCE_SCENARIOS_v1.0.md | `1db1625cb44196eed5f25e0dd77df0f1cdc859cbc309f23b0f6ac6c9adc8c260` |

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
