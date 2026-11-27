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

## Approved AGIS scope and source integrity — 2026-11-27

- [Admission, Guest Information and Station Management v1.0](ADMISSION_GUEST_INFORMATION_AND_STATION_MANAGEMENT_DESIGN_v1.0.md) — approved AGIS-01–20, AGIS-M0–M6, AGIS-AC-01–40; six station modes, configurable station layouts, admission QR, verified Info Pult, hardware, printing, device authorization, offline validation/reconciliation, live Cockpit and acceptance. Primary issue [#107](https://github.com/TeraflopsBH/eventor/issues/107), dependencies [#105](https://github.com/TeraflopsBH/eventor/issues/105), [#106](https://github.com/TeraflopsBH/eventor/issues/106), [#111](https://github.com/TeraflopsBH/eventor/issues/111).

The owner approved integration of the full AGIS source on 2026-11-27. Its original review-status language remains verbatim; this approval record establishes scope status, not approval of exact API/DDL/library/hardware/security choices or completion of any test. Original source size: 136,735 bytes. SHA-256: `7db8e410c879e74790f08180698a0d430b297ee0b857677a51c27bae05c3efd1`. Git blob: `e3c5d4c3340fe7f1de21b7cd67386f0e1e6c9e29`.

The earlier OAC/UX/OLA checksum table above records the original reviewed bytes preserved at [PR #234 merge revision](https://github.com/TeraflopsBH/eventor/tree/a5cfcf0ad9d86dbf06ebb7599cc97e2070f64b01/docs/implementation-design/v0.3). This AGIS integration appends dated cross-references to those documents without changing any of their original text; their complete current file digests therefore differ from the historical originals. This is an approved scope clarification, not a runtime implementation claim or instruction to interrupt the existing #104/#112 → #105–107 sequence. Preserve accepted ADRs, historical Blueprint v1.2, existing domain commands and issue criteria; final integrated acceptance remains Phase 9.

## Approved CID scope and source integrity — 2026-11-27

- [Communication, Invitation Distribution and Multi-Channel Delivery v1.0](COMMUNICATION_INVITATION_DISTRIBUTION_AND_MULTI_CHANNEL_DELIVERY_DESIGN_v1.0.md) — approved CID-01–24, CID-M0–M7, CID-AC-01–48, covering all outbound communication purposes, pluggable provider adapters, organization-owned and optional platform-managed services, channel-independent invitation issuance, campaign review/scheduling, consent, costs, manual distribution and verified delivery evidence. Primary [#111](https://github.com/TeraflopsBH/eventor/issues/111), coordinated with #104–108/#110/#112 as mapped in §26.

Owner approved integration of the full reviewed CID source on 2026-11-27. Its original proposed-status and inspection-baseline wording remain verbatim; this approval record governs integration status, not exact engineering choices or implementation completion. Source size: 136,376 bytes. SHA-256: `f2395009b9a3300d04fefa1539eca0b340f159cf9b46826dddcd695a72f14782`. Git blob: `80be0d0c3ecf943d1316524f7fe930f09dd41da5`.

AGIS PR #235 was separately squash-merged at [21021138b2d07e780bccec7bbbb539a75d3cebfc](https://github.com/TeraflopsBH/eventor/commit/21021138b2d07e780bccec7bbbb539a75d3cebfc). The historical AGIS checksum/blob record above refers to that original reviewed source; CID appends a dated cross-reference without altering the original AGIS text. Earlier OAC/UX/OLA original checksum references at PR #234 remain valid for those immutable revisions. This is an approved scope clarification, not a runtime or acceptance claim. Preserve all existing requirements, accepted ADRs, historical Blueprint v1.2, current #104/#112 → #105–107 sequence and established #110/#111/#108 roadmap; no immediate implementation or environment republication. Final integrated acceptance remains Phase 9.
