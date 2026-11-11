# Project state

**Status:** accepted product/domain design baseline; 21-migration PostgreSQL 18 implementation draft and OpenAPI v0.3 contract in draft PR #26; current PostgreSQL 18.6 and OpenAPI CI passing; deeper security, upgrade/recovery and production-readiness reviews remain open  
**Last updated:** 2026-11-10  
**Implementation status:** database migrations and API contract exist in draft PR #26; no application route code or production database deployment has been established.

## Product

Eventor is a reusable, self-hosted platform that can operate as a venue booking/resource system, a full event operations platform, or a configurable combination. GHB Sarajevo is the first reference organization/venue, not the product's only intended deployment.

## Established direction

- API-first modular monolith.
- Vue 3 + TypeScript + Vite staff and guest-facing applications.
- Fastify + TypeScript API and background workers.
- PostgreSQL as the authoritative datastore.
- SVG-based spatial editor and map rendering.
- WebSockets with transactional outbox.
- C++ OR-Tools CP-SAT optimization worker/service.
- Self-hosted Linux deployment; Docker is optional, not mandatory.

## Agreed domain behavior

### Operating scope and party responsibilities

- A venue provider is not automatically the event organizer. Venue booking and venue-side service delivery are distinct from organizing the renter's event.
- Organization-level operating profiles establish defaults: venue provider, event organizer or hybrid. They are configuration presets, not product/license tiers.
- Booking/event-level scope can override organization defaults and independently activate only the modules required for that booking/event.
- A booking can be completed without creating an operational event or collecting guest-level data.
- Distinguish venue provider, booking requester/customer, contracting party, event organizer and operational operator; these roles may belong to different entities.
- Organizer-side guest management, invitation/RSVP, seating, check-in, external prerequisites and live event cockpit are optional for venue-provider-only workflows.
- Task/module responsibility and scoped collaboration must be explicit. A booking customer does not automatically become a tenant/member or gain access to the venue provider's workspace.
- Accepted cross-organization model: venue and booking data remain provider-owned; operational event and guest data remain organizer-owned; collaboration uses explicit grants and immutable, revision-pinned venue-space snapshots. See [Cross-Organization Collaboration v0.3](implementation-design/v0.3/CROSS_ORGANIZATION_COLLABORATION_DESIGN_v0.3.md) and [ADR 0006](decisions/0006-cross-organization-collaboration.md). The initial migration implementation is present in draft PR #26; broader authority/tenant review remains open.
- The venue provider retains its own venue/facility and contracted service responsibilities. Eventor records assigned operational ownership; it does not transfer duties or make legal determinations.

### Optional event capabilities

- An operational event is created only when the booking/event scope requires it; confirmed venue booking alone does not create one.
- Guest Registry, invitations/RSVP, seating, check-in, external prerequisites and event-day cockpit are independently optional capabilities.
- Capability activation and task responsibility are explicit; module defaults may be overridden for an individual event.
- The organizer's guest data is not made visible to the venue provider solely because it supplies the space. Cross-party access is task-specific and explicitly granted.
- See [RSVP and Invitation Design v0.3](implementation-design/v0.3/RSVP_AND_INVITATION_DESIGN_v0.3.md) and [ADR 0005](decisions/0005-separate-invitations-rsvp-attendance.md).

### Booking

- Public inquiry is a relatively simple intake, not a complex booking configuration exercise.
- Staff review an inquiry and may create a separate editable booking draft prepopulated from it.
- Drafts can change dates, spaces, resources, services and prices without changing the original inquiry.
- Offer/approval and explicit confirmation are distinct workflow stages.
- Staff can also create bookings without an inquiry.
- Preserve original requested values, offered/approved values and delivered/actual values separately.
- Rehearsals are separately schedulable reservations with their own date, time and duration.
- Historical records pin the form and catalogue revisions and retain the labels/answers shown at the time.

### Invitations, RSVP and attendance

- Invitations, delivery attempts, invitation-link validity, RSVP answers, participation/waitlist eligibility and physical attendance are separate lifecycle dimensions.
- Guest self-service RSVP uses a high-entropy, opaque, revocable invitation link; no guest account is required by default.
- Email is the initial delivery channel; channels, templates and reminder cadence are configurable.
- Staff can record responses received in person, by telephone, email, written communication, a representative or another configured channel, without requiring a guest link or email address.
- Capture source, response-received time, server-recorded time, authenticated operator and optional restricted notes/reason.
- Response history is append-only. Changes/corrections add a new record and do not erase the prior response.
- RSVP choices, deadline, event timezone, reminder policy and response-change rules are versioned event configuration.
- No response remains unanswered; it is not an automatic decline. Invitation delivery failure does not change RSVP state.
- RSVP response and physical attendance/check-in are separate. Accepting an invitation never creates attendance.
- Guest operations are optional and assigned to the organizer or explicitly contracted operating party; a venue-only booking requires no guest records, invitations or RSVP.

### Guest registry

- Persistent person records are separate from event-specific participation.
- Reuse profiles across events; support duplicate detection and supervised merge.
- Support custom fields, attachments, import/export and history with permissions and audit.

### Spatial model and seating

- Model venues, buildings, floors, rooms, zones, rows, positions, physical features and count-based capacity pools as distinct concepts.
- Do not interpret every numeral or colored region in a source plan as an individual seat.
- Support both zone-only allocation and precise zone/row/position allocation.
- Seating constraints include together/avoid, preferences, exclusions by table/row/zone/room/building/distance/session, hard and soft rules, locked assignments and scoped reruns.
- Support manual, category-based, hybrid and solver-assisted allocation.
- Solver output is a proposal with diagnostics and preview; a person explicitly commits it.

### Guest portal and operations

- Personalized portal/QR shows only the relevant guest's permitted information and a sanitized public map.
- No public guest directory or internal security information.
- Staff cockpit is role-configurable and shows live status, map, counts, alerts, history and permitted controls.
- Role-specific workspaces expose only required data.

### Configuration and branding

- Admins can add, modify, retire, reorder and publish forms, fields, options, catalogues, services, equipment, prices and workflow rules without code changes.
- Support dependencies/conditional visibility where needed, but do not impose elaborate conditional forms without a validated requirement.
- Version and publish configuration; support rollback. Retire referenced options rather than deleting them or changing their meaning.
- Branding inherits Organization → Venue → Event, with versioned snapshots for invitations, portal, QR/guest cards, maps, signage and reports.

### External prerequisites

- Model external coordination (for example, police coordination when required) as a configurable event-readiness checklist.
- Track requirement, responsible authority, internal coordinator, submission/scheduled/completed status, dates, references and restricted attachments.
- Do not build internal law-enforcement methods, findings or inspection management. Cockpit shows only appropriate readiness status.

## Reference deployment cautions

- GHB room capacities, venue descriptions, current rates, discounts, operating hours and rental policies require confirmation by GHB before enforcement.
- Existing GHB form options are reference data, not hardcoded product behavior.
- The supplied mosque workbook is a grid-like spatial drawing. Preserve the source and map approved objects deliberately; do not blindly convert cells/numbers into seats.
- The source venue workbook and sensitive operational details must not be committed unless explicitly reviewed and sanitized.

## Operating model

See [Operating Model](OPERATING_MODEL.md) and [ADR 0004](decisions/0004-optional-event-operations-scope.md). This accepted product requirement is reflected in the successor v0.3 designs and implementation draft; historical Blueprint v1.2 and Implementation Design v0.2 files remain unchanged snapshots.

## Cancellation and event disruption

The accepted v0.3 design covers customer/organizer-initiated booking cancellation, venue-provider-initiated booking cancellation, organizer-owned event cancellation/postponement, guest notification campaigns and cross-organization disruption handling. Booking and event outcomes remain independent; invitation, RSVP and attendance history is preserved. The workflow is tracked in [Issue #21](https://github.com/TeraflopsBH/eventor/issues/21) and documented in [Cancellation and Event Disruption Design v0.3](implementation-design/v0.3/CANCELLATION_AND_EVENT_DISRUPTION_DESIGN_v0.3.md). Initial schema and API contract coverage is included in draft PR #26. GHB-specific commercial terms, approval thresholds and operational policies still require confirmation.

## Successor database and API baseline

The accepted successor logical model and API design derive from ADRs 0004–0006, the RSVP/invitation and cancellation designs, and the venue-first MVP/role model. The database integrity baseline was merged in PR #24 and the aligned logical schema/API design in PR #25. The executable migration and OpenAPI implementation draft is PR #26; it remains unmerged and requires review.

## Executable schema and API contract draft

The branch [feat/postgresql18-migrations-openapi-v0.3](https://github.com/TeraflopsBH/eventor/tree/feat/postgresql18-migrations-openapi-v0.3), in [draft PR #26](https://github.com/TeraflopsBH/eventor/pull/26), contains 21 ordered PostgreSQL 18 migrations, least-privilege role bootstrap, a checksum-verified migration runner, database integrity/RLS tests, pooled-capacity concurrency tests and the canonical OpenAPI 3.1.1 contract at `docs/api/openapi.v0.3.yaml` (106 paths / 123 operations).

The latest complete CI run on PR head `a86c2922817fbd1c3abe2b2e0af5cee4b8cef865` is [run #42850865186](https://github.com/TeraflopsBH/eventor/actions/runs/42850865186); PostgreSQL 18.6 and OpenAPI jobs both succeeded. The PostgreSQL 18.6 job applied all 21 migrations to a fresh CI database and passed integrity/RLS/concurrency tests, split-authentication-role privileges, collaboration grant proposal/acceptance/revocation, grant-scoped booking links, approved layer/object/resource projections, narrowly filtered source-data RLS, post-revocation source hiding with retained event-owned snapshots, session/snapshot-content use checks, published-revision immutability, append-only protections and migration-ledger reporting.

A static candidate-key/FK-target audit covered 120 declared tables without unresolved targets; this is a structural scan, not a substitute for database/runtime validation. No production database has been migrated, and no application API routes have been implemented. The 21-migration draft separates global identity access into `eventor_auth`, removes global password-hash access from `eventor_runtime`, adds audited collaboration grant proposal/acceptance/revocation commands, enforces active grant scope at booking-link/snapshot/session-use points, restricts source-data RLS to the provider-approved layer/resource projection, and freezes published revisions and revision children. These are CI-validated against a fresh PostgreSQL 18.6 database, not yet approved for production. PR #26 remains a draft pending review.

## Database schema review and remaining validation

The initial [Database Review v0.2](database/DATABASE_REVIEW_v0.2.md) records findings in the historical 86-table starter schema. The new v0.3 migrations have now been executed successfully against PostgreSQL 18.6 in CI; the earlier statement that PostgreSQL runtime testing was unavailable is no longer current. Issue #2 and related schema issues remain open for deeper DDL/RLS/authority review, broader constraint-matrix coverage, migration upgrade testing and backup/restore validation. The v0.2 SQL remains a historical reference rather than the executable successor schema.

## Accepted MVP boundary

The recommended first production release is **venue booking and venue operations** for the GHB reference deployment, with GHB acting as venue provider by default. It is complete without an operational event or guest-level records. Guest registry, invitations/RSVP, seating, guest portal, admission/check-in, organizer prerequisites and full event cockpit are later optional capabilities; an organization/event can activate them when it is responsible for those tasks.

The accepted initial scope and acceptance scenarios are in [MVP Scope v0.1](product/MVP_SCOPE_v0.1.md); the baseline role and permission model is in [User Roles and Permissions v0.1](product/USER_ROLES_AND_PERMISSIONS_v0.1.md). Organization-specific assignments, approval thresholds and GHB capacities, service inventory, prices and operating policies still require validation before production configuration.

## API contract review

The imported OpenAPI v0.2 contract passed YAML parsing and local structural checks (36 paths, 46 operations, unique operation IDs, 172 resolved local references); that historical check was not a full OpenAPI semantic validation. The canonical v0.3 contract is [`docs/api/openapi.v0.3.yaml`](api/openapi.v0.3.yaml) and is validated in CI by the strict Eventor structural/security validator, the pinned OpenAPI 3.1.1 validator and Redocly lint. It currently contains 106 paths and 123 operations. API route implementation, generated TypeScript client verification and route-level request/response contract tests remain open under Issues #3 and #17.

## Imported design artifacts and reconciliation

The working design sources are now in the repository:
- [Technical Blueprint v1.2](blueprint/v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md).
- [Implementation Design v0.2](implementation-design/v0.2/Event_Operations_Implementation_Design_v0.2.md).
- [Consolidated PostgreSQL schema starter](implementation-design/v0.2/eogp_schema_v0.2.sql) — 86 table definitions (64 core + 22 booking/configuration).
- [OpenAPI v0.2 draft](implementation-design/v0.2/eogp_openapi_v0.2.yaml).
- [64-item backlog](implementation-design/v0.2/EOGP_Backlog_v0.2.csv) and [GHB rental-form capture](implementation-design/v0.2/GHB_Rental_Form_Reference_v0.2.csv).
- [Design reconciliation report](DESIGN_RECONCILIATION_v0.2.md).

The separate v0.2 booking SQL addendum duplicates all 22 booking/configuration table definitions already present in the consolidated schema and is therefore not included as an additional executable schema file. The source workbook, rendered workbook image and spatial observations register remain outside GitHub pending venue-owner review.

## Immediate next steps

1. Complete a deeper review of the v0.3 DDL, RLS policies, actor attribution, cross-organization access boundaries and full constraint-test matrix.
2. Add migration-upgrade and backup/restore validation; current CI proves fresh-database installation, not recovery readiness.
3. Add API route implementations, generated TypeScript client verification and route-level request/response contract tests.
4. Begin the application foundation and first venue-booking vertical slice only after the database/API contract review is accepted: staff authentication and organization context, public booking inquiry, staff draft, offer/approval and explicit reservation confirmation.
5. Confirm GHB-specific venue inventory, capacities, pricing, cancellation terms, approval thresholds and operating policies before seeding production configuration.

## Open questions / validation gates

- Confirm GHB capacities, room/resource inventory, pricing and current rental policy.
- Validate actual approval/offer stages and who is authorized to approve/confirm.
- Confirm RSVP deadline, reminder schedule, response-change policy and guest contact-channel requirements.
- Confirm which guest and staff data fields are mandatory and who may view them.
- Review the venue spatial drawing with an authorized venue representative.
- Confirm public deployment hostname, reverse-proxy boundaries, email delivery and retention requirements.
