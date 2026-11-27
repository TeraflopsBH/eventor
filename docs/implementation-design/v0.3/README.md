# Implementation Design v0.3 — domain design addenda

> **Document status navigation — 2026-11-27:** [Authority register](../../DOCUMENTATION_AUTHORITY.md) and [ADR index](../../decisions/README.md) distinguish current approved successor designs and historical source editions. Use TDS/PAC v1.1 and R1–R9 in the existing approval notice; all original v1.0 requirements and acceptance evidence remain retained.

> **Owner-approved design resolution — 2026-11-27 (PR #239):** [ADR 0025](../../decisions/0025-platform-governance-tenant-authority.md) is accepted for future least-privilege platform governance, and [R1–R9 and the cumulative clause dispositions](../../blueprint/v1.3/TDS_PAC_CLAUSE_DISPOSITIONS_v1.0.md) plus [TDS v1.1](TEMPLATE_DESIGN_STUDIO_DESIGN_v1.1.md) and [PAC v1.1](PLATFORM_ADMINISTRATION_CENTER_DESIGN_v1.1.md) form the approved successor design clarification. OD-01 is resolved as architecture; OD-02 is resolved by cumulative compatible requirements and explicit precedence, not a sentence-level equivalence proof. This note supersedes older pending OD-01/02 approval wording, not remaining implementation decisions. Preserve current ADR 0015 runtime behavior until reviewed PAC M0/M1 inventory, exact allowlist, impact, migration, recovery and verification are approved and activated. Unknown/new managed permissions must not be assumed safe. Keep all original sources, current issue obligations, #104/#112 → #105–107 → #110/#111/#108 and Phase 9 acceptance unchanged; no new implementation track, environment republication or test credit.

> **Consolidation approved — 2026-11-27:** [Technical Blueprint v1.3](../../blueprint/v1.3/README.md) is the approved consolidated design baseline. It preserves all twelve original review annexes and all 61 pinned repository documents, including this index's prior revision and all 24 accepted ADRs. This index and every individual approved specification remain detailed source references; original approval and checksum records are unchanged. The earlier no-consolidation wording records historical scope restrictions before separate owner approval. No new runtime or acceptance claim or change in implementation priority.

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

## Approved coordinated AES, EPW, FRS, HPG and RAI scope and source integrity — 2026-11-27

The owner approved the entire five-document package. Original draft-status wording, review baseline and proposed destination language remain unchanged; this record establishes approval of scope, not exact engineering choices or executed acceptance. All five source byte sequences are preserved verbatim.

| Specification | Requirements | Milestones | Acceptance | Source bytes | SHA-256 | Original Git blob |
|---|---|---|---|---:|---|---|
| [AES v1.0](ADAPTIVE_EXPERIENCE_AND_SETUP_DESIGN_v1.0.md) | AES-01–15 | M0–M5 | AC-01–30 | 45,494 | `b563e53474824931b38e425c18b00bf32f58eaf1a39efab05fb9722176ea2f00` | `8b5e416e52b7145fd853d4e15d4a5748d3ce7bab` |
| [EPW v1.0](EVENT_PLANNING_PRODUCTION_AND_OPERATIONAL_WORKFLOWS_DESIGN_v1.0.md) | EPW-01–16 | M0–M6 | AC-01–33 | 47,564 | `620af72a1f3b76b5ddcfcb014f4d0e1f0facbf7e4a723d013617b957c4627272` | `d67ff1ff54df7bd22a229e80df986adbaa4e86df` |
| [FRS v1.0](FORMS_REGISTRATION_AND_SUBMISSION_STUDIO_DESIGN_v1.0.md) | FRS-01–16 | M0–M5 | AC-01–32 | 49,261 | `5fd08d1096d88835b592676c943888ee0179c991203446c20c6859116dc69ac3` | `8943a0b42549ce26e86a4c3b39910094116f3f16` |
| [HPG v1.0](HOSPITALITY_PROTOCOL_AND_GUEST_SERVICES_DESIGN_v1.0.md) | HPG-01–16 | M0–M5 | AC-01–31 | 49,543 | `3c6b905ba5f978df95799dd7fe6587abfc59cab6b8c5e90db776e2a748c390b0` | `78b9f6d064dd11b4b8a91c5cfce9e0399f151f2e` |
| [RAI v1.0](REPORTING_ANALYTICS_AND_INTELLIGENCE_STUDIO_DESIGN_v1.0.md) | RAI-01–16 | M0–M6 | AC-01–35 | 54,406 | `6eb0054488220f877dfad553c46ad9d3a69fafe6bc3bce6317d3b36721095e2b` | `8be378c17d4b2b94dcf8bccbbd916cd7c30b8e2e` |

Primary issue ownership: AES #104 (cross-cutting UX/OAC), EPW and HPG #110, FRS and RAI #111; dependencies #105–108/#112 and existing domain designs as specified in each §10. All 79 requirement groups, 161 acceptance criteria and 32 milestones have bidirectional requirement-to-test traceability. Existing approved addenda retain all prior text and their historical source checksum references (OAC/UX/OLA #234, AGIS #235, CID #236); the original CID source at [e0fa44203f785284d597f69dae8510c91bada0d6](https://github.com/TeraflopsBH/eventor/tree/e0fa44203f785284d597f69dae8510c91bada0d6/docs/implementation-design/v0.3) is immutable, and subsequent cross-reference appends change complete-file digests without altering original bytes. Approved additive scope only; retain existing requirements, accepted ADRs, Blueprint v1.2, PROJECT_STATE and the #104/#112 → #105–107 → #110/#111/#108 development sequence. No immediate implementation, unrelated closure gates, environment republication or Blueprint v1.3 consolidation. Final integrated acceptance remains Phase 9.

## Coordinated consistency companion — 2026-11-27

[Reconciliation](../../blueprint/v1.3/DESIGN_CONSISTENCY_RECONCILIATION_v1.0.md), [shared engineering registers](../../blueprint/v1.3/ENGINEERING_REGISTERS_v1.0.md) and [TDS/PAC source reconciliation](../../blueprint/v1.3/TDS_PAC_SOURCE_RECONCILIATION_v1.0.md) clarify source precedence, preserve original and integrated editions, and record pending material authority decisions. All prior approved requirements and original acceptance cases remain retained; nonidentical clauses are not automatically adjudicated. Historical source hashes and accepted ADRs unchanged. No change to implementation priorities.
