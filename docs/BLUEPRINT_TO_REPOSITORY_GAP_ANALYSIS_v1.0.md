# Blueprint-to-repository gap analysis — v1.0

**Audit baseline:** `main` at `a0a346268016079d58756bd95e7af2b87ccc4fec` (2026-11-18).

**Blueprint:** Technical Blueprint v1.2  
**Purpose:** establish what exists in the repository, what is only a design/schema foundation, what is partially usable, and what remains to be built before Eventor is a ready-to-use event operations product.

This is a static repository audit of the source tree, API route registrations, Vue application composition, migrations, tests and deployment files. It is not a claim that every existing workflow has been manually exercised. CI evidence and the separate external-acceptance record remain authoritative for what has actually been tested.

## 1. Executive assessment

Eventor is **not yet a complete event operations application**. The current implementation is materially weighted toward the venue-booking/commercial vertical. It has a substantial PostgreSQL/security foundation, working staff authentication, a Vue staff shell, public booking inquiry forms, booking inquiry/draft/offer workflows, commercial configuration, notification campaigns/delivery, a meaningful invitation/RSVP slice, and an integrated booking-cancellation request/review/approved-execution workflow with a public customer request/status journey.

The organizer workspace now supports event and session lifecycle, persistent guest profiles, event rosters, mapped imports, exports, supervised merge and roster organization. The spatial editor, guest allocation, admission, check-in, operations cockpit, branding and external prerequisites still need product workflows.

A usable slice connects the role-scoped API and staff or guest interface. The matrix records the remaining work within each slice.

### Status vocabulary

- **Implemented (usable slice):** runtime API and user-facing workflow exist; scope may still have limitations.
- **Partial:** a meaningful runtime slice exists, but important workflow stages or product requirements are missing.
- **Foundation only:** schema, security primitives, design or tests exist, but there is no complete runtime/user workflow.
- **Missing:** no meaningful implementation was found in the audited repository tree.
- **Not assessed:** requires venue-owner input, real deployment or runtime exercise beyond static GitHub inspection.

## 2. Product-area gap matrix

| Blueprint domain | Current repository evidence | Status | Main gap to close |
|---|---|---|---|
| Platform, tenancy, authentication and authorization | PostgreSQL migrations 000001–000015 and later hardening; RLS/least-privilege roles; Fastify staff sessions, CSRF/origin checks; staff login UI; audit commands and tests | **Partial / strong foundation** | Complete organization/user/membership administration, role assignment UX, event-scoped permission coverage, operational health/readiness and full admin workspace. |
| Venue booking and public inquiry | Public booking form projection/submission, spam/rate protections, inquiry inbox/detail, assignment/status/notes/history, draft conversion and revisions, allocation availability preview | **Implemented slice** | Finish and acceptance-test the end-to-end commercial booking lifecycle, fulfilment tasks and operational communications; distinguish requested, approved and delivered service. |
| Commercial offers, approval, pricing and tax | Offer lifecycle, approval policies, price lists, tax profiles/calculation, cancellation policies, public offer acceptance/rejection and booking reservation commands; staff views | **Implemented slice / needs end-to-end acceptance** | Close remaining workflow edges, customer-facing presentation, manual booking path, resource fulfilment and cancellation/change lifecycle acceptance. 
| Booking cancellation and disruption | Migrations 000115–000120; staff request queue/detail, approve/reject/return-for-changes, policy-pinned preview, approved execution with atomic reservation release, public single-use request capability and reusable read-only status capability | **Partial / implemented cancellation slice** | Complete venue/event disruption notices and follow-up projection, amendment/postponement lifecycle, and a dedicated public cancellation browser E2E journey. A customer request is not effective cancellation and does not move money. |
| Event administration and sessions | The bilingual Events workspace supports list/create/edit/archive, approval and publication, and event start and close. Sessions support list/create/edit, scheduling, start and completion. The guest list can be activated per event. | **Implemented slice** | Broader event settings, session-specific disruption handling and venue assignment. |
| Persistent Guest Registry | Organization-scoped search, profile creation/edit/archive and history. Encrypted contact values and source references have separate access grants. Staff can record or revoke contact confirmation. Mutual and directed relationships are available with dedicated grants. Supervised merge preserves original closed-event references and can restore the source. | **Implemented slice** | Controlled merge resolution for linked contacts, identifiers, active relationships and open or overlapping event history, configurable profile fields, anonymization and retention. |
| Event participation and guest list | Permissioned Registry linking with pinned event identity. Staff can filter/search the roster, save personal views, manage categories, internal and restricted tags, group hierarchy and roles, event relationships and encrypted custom fields. Bulk status, category and internal tag actions use revision checks and transactions. | **Implemented slice** | Broader field search and sorting/grouping, allocation preferences and group-to-group relationships, controlled bulk archival and event identity overrides. |
| Guest imports and exports | Staff can map CSV/XLSX name columns, select a worksheet/header row, preview conflicts, and explicitly reuse or update a Registry match or create a separate profile during name review. Exact source-reference matching and reviewed creation use protected Registry identifiers. Filtered exports and row reports are available. | **Implemented slice** | Support more import fields and matching strategies, and verify a full controlled import-to-export journey. |
| Invitations and RSVP | Guest capability resolution, invitation view, RSVP submission/history, issue/reissue/revoke, staff-recorded RSVP/correction, delivery-attempt history, staff invitation workspace and guest invitation page | **Implemented slice** | Batch issuance, reminders, broader guest self-service, provider reconciliation for ambiguous delivery and full journey acceptance. |
| Guest Portal and wayfinding | Public guest invitation page and RSVP flow | **Partial** | Authenticated/personal portal home, event information, personal allocation, guest-safe interactive maps, directions, accessibility-aware wayfinding and branded guest materials. |
| Venue, building, room and space registry | Venue/resource schema foundation and booking resource APIs | **Foundation / partial** | Reusable venue hierarchy and template management UI/API, versioned rooms/spaces, capacities and event-owned snapshots. Booking resource availability is not a venue editor. |
| Floor-plan import and spatial editor | Blueprint describes SVG-native editor and source-plan onboarding; no corresponding frontend feature, API route family or runtime module found | **Missing** | PDF/image/SVG background import, XLSX source-plan workflow, geometry editor, layers, scale calibration, spatial features, rows, zones and floor-position resources. |
| Guest seating and allocation | Booking-draft allocation catalogue/availability preview exists for reserving venue resources | **Missing for event guest allocation** | Manual/category/hybrid/solver allocation, hard/soft constraints, locks, diagnostics, proposal diff, approval and targeted reflow. Booking resource selection is not guest seating. |
| Allocation optimizer | Architecture references a C++ OR-Tools CP-SAT process; no solver source, executable, worker or integration found in current tree | **Missing** | Implement solver boundary, validated input/output contracts, diagnostics, reproducible proposals and human-approved commit. |
| Plan revisions, approval, publication and print | General revision/approval patterns exist in booking and configuration domains | **Foundation only for event plans** | Immutable event allocation-plan revisions, approver workflow, publication, staff plan viewers, printable PDFs and historical supersession. |
| Guest cards and admission QR | Invitation capabilities are opaque bearer links; no separate admission credential issuance or QR scanning workflow found | **Missing** | Separate revocable admission credential, QR generation/print, credential lifecycle, offline-safe validation and privacy-safe payloads. Do not reuse invitation tokens as admission passes. |
| Gate check-in and attendance | Attendance is in the early schema foundation; no check-in API, station UI, camera scanner or PWA found | **Foundation only** | Station/operator management, camera scanning, manual lookup, duplicate detection, corrections, multiple gates, synchronization and offline tolerance. |
| Live Event Operations Cockpit | No event cockpit UI/API, realtime event stream or WebSocket implementation found | **Missing** | Live metrics, operational map layers, alerts, timeline, interventions, event health/readiness and role-filtered realtime subscriptions. |
| Role-specific staff workspaces | Current staff shell exposes booking, email delivery/campaign, guest invitation and locale/settings tabs | **Partial** | Reception, seating, venue, gate, floor/zone, prerequisite and management workspaces with independent permission-filtered projections. |
| Vendor/service/task coordination | Responsibility/delegated-task/audit database primitives exist; no vendor workspace/cockpit or complete task UI found | **Foundation only** | Assignments, vendor/staff workspaces, deliverables, deadlines, status, evidence, communication and scoped collaboration. |
| External prerequisites / CDI | General responsibility/event design exists; no dedicated prerequisite API/UI found | **Missing** | Record external party, request, scheduling, due date, status history and authorized completion/readiness gate. CDI remains external; Eventor must not implement police inspection activity. |
| Email delivery and campaign operations | SMTP configuration/test UI, campaign review/approval/queue/delivery tracking, worker, retries/reconciliation and provider integration primitives | **Implemented slice** | Complete authoring experience and product-ready template management. Current campaign view reviews a message template; it is not a visual email composer/editor. |
| Email text composer/editor | Campaign UI displays subject/body templates in a review panel; no dedicated template authoring/editor UI found | **Missing as an authoring feature** | Template CRUD/revisions, rich/plain text editing, variable insertion/validation, preview, test-send, localization and branded layout controls. |
| Public forms and data/request submission | Versioned public booking forms, field schema, published revision validation, public inquiry submission and staff review workflow | **Implemented for booking inquiries** | Generalize only where product workflows require it; do not conflate booking inquiry forms with guest registration, vendor submissions or event data capture forms. |
| Branding and reusable templates | No brand profile/asset/inheritance runtime or UI found in migrations/API/frontend | **Missing** | Organization → venue → event inheritance, asset library, revisions, template assignments and pinned brand snapshots. |
| Notifications and realtime synchronization | Transactional outbox, notification campaigns, email/SMS abstractions and delivery worker | **Partial** | Event-triggered notifications across all workflows, WebSocket delivery, subscriptions, change propagation and operational alerting. |
| Reports, exports, guest cards, signage and information displays | Filtered roster CSV/XLSX exports, separate Registry export permission and downloadable import diagnostics | **Partial** | Operational reports, printable plans/cards, configurable signage and read-only display mode. |
| Localization and accessibility | English and Bosnian locale support in staff UI and selected booking/guest flows | **Partial** | Complete coverage of all workflows, localized templates/outputs, keyboard alternatives to drag/drop and accessibility testing. |
| Import/onboarding of existing floor plans | No source-plan artifact/conversion workflow found | **Missing** | Preserve original workbook/PDF, map source cells/regions to native geometry, validation and human sign-off. |
| Monitoring and operational administration | systemd API/worker templates, migration runner, backup/restore CI rehearsal and deployment runbook | **Partial** | Liveness/readiness, metrics, structured operational dashboard, tested backup policy/PITR, installer and host-level validation. |

## 3. Concrete evidence and boundaries

### 3.1 Current staff application

The current staff navigation includes:
- Email delivery configuration.
- Campaign review and delivery operations.
- Guest invitation management (including staff RSVP capture/correction).
- Booking inquiry workspace.
- Booking approval policies.
- Booking forms.
- Price lists.
- Cancellation policies.
- Booking cancellation request/review workspace.
- Tax profiles.
- Organization locale settings.
- Organizer event and session administration.
- Guest Registry, event roster and import/export.

This is a real staff application, not a blank shell. However, it is not yet the blueprint's event operations cockpit or the complete navigation/workspace map.

### 3.2 Runtime API boundary

The current API route families include booking forms/inquiries/drafts/offers, price/tax/approval/cancellation policies, booking reservation commands, staff booking-cancellation review/detail/decision/preview/execution, external booking-action capability issue/revoke/resolve, public cancellation request/status, organizer event administration, event invitation projections, guest invitation issue/revoke, guest RSVP and delivery configuration/campaign operations.

Guest Registry profiles, imports, restricted roster operations and permission-filtered exports have runtime API and staff UI paths. Venue/floor-plan editing, event guest allocation, admission QR, check-in stations, cockpit/realtime, external prerequisites, branding and vendor workspaces need runtime slices.

The current API has separate API and notification-worker entry points. The worker handles notification delivery; it is not the planned allocation solver or event-operations job platform.

### 3.3 Database maturity

Migrations 000124–000127 provide session administration and organizer lifecycle commands. Migrations 000128–000163 extend the existing person, participation and roster tables with tenant-scoped commands, protected fields and reviewed imports. CI covers PostgreSQL migrations, RLS, concurrency, populated upgrade and logical backup/restore.

### 3.4 Email and forms

There is already an email delivery configuration and test-send screen, campaign review/approval/queueing and delivery history. The campaign view displays the subject and body template for review, but no visual/template authoring interface was found. Likewise, public booking request forms are implemented; that does not mean guest registration forms, vendor forms or generic event submission forms are complete.

### 3.6 Booking cancellation and disruption boundary

The cancellation slice is now integrated rather than being only a schema foundation:
- Staff can review a tenant-scoped request queue, inspect authorized request history, approve/reject/return requests for changes, preview the pinned cancellation policy and exact reservation effects, and execute an approved cancellation.
- Approved execution is serialized on the booking and releases the exact booking reservations in the same transaction; the confirmed commercial snapshot and pinned policy revision remain auditable.
- A customer can submit a purpose-bound single-use request and receive a separate reusable, contact-scoped, read-only status capability. Only token hashes are persisted; the raw status token is returned by the API.
- Public tokens are carried in URL fragments, removed from browser history, omitted from cookies and redacted from request logs. The status link preserves the selected locale.

This is not the whole disruption domain. Venue/event cancellation notices, customer-facing follow-up, amendment/postponement workflows and a dedicated browser E2E test for the public cancellation journey remain outstanding. A customer request does not itself cancel a booking; no refund, fee, credit or other money movement is inferred or initiated.

### 3.5 QR and check-in distinction

Guest invitation links are capability-protected links for invitation/RSVP. They are not admission QR passes. Admission credentials need a separate lifecycle, scope, revocation model and scanning/check-in workflow. The current repository does not contain the gate-scanning product slice.

## 4. Recommended implementation sequence

The following order prioritizes a coherent, usable product and avoids building acceptance infrastructure around unfinished workflows.

### Track A — Complete the venue-booking product vertical

1. Reconcile current booking implementation against the accepted Release 1 scope.
2. Finish remaining booking lifecycle edges: manual booking, offer revision/approval/acceptance, confirmation, amendment/postponement and venue/event disruption notices. The staff/public cancellation request and approved-execution slice is integrated; it still needs dedicated browser E2E and full disruption follow-up acceptance.
3. Complete venue-side fulfilment tasks and assigned responsibility workflows.
4. Complete booking communication/template authoring and operational history.
5. Add health/readiness and operator-facing diagnostics.

### Track B — Build the event organizer foundation

6. Complete organization/user/membership and role administration, event settings and session disruption handling.
7. Extend the delivered Guest Registry and import workflows with reviewed resolution of linked records and more import fields.
8. Extend roster configuration, group allocation preferences, bulk controls and permission-scoped acceptance.
9. Extend invitations/RSVP to batches, reminders and the full guest portal journey.

### Track C — Venue geometry, allocation and plans

10. Implement reusable venue/building/level/room hierarchy and versioned templates.
11. Implement source-plan artifact onboarding (PDF/image/XLSX) and human-reviewed native geometry conversion.
12. Build the SVG spatial editor with zones, rows, tables, seats, floor positions, capacity pools and non-allocatable features.
13. Implement manual and category-based guest allocation first.
14. Add hard/soft constraints, locked assignments, solver proposal/diagnostics and targeted reflow; integrate OR-Tools only behind a stable validated boundary.
15. Add plan revision comparison, approval, publication, print packages and staff viewers.

### Track D — Event-day operations

16. Implement separate admission QR credential issuance, revocation and branded guest cards.
17. Implement the responsive check-in PWA, station/operator management, camera scan, manual fallback, duplicate detection, corrections and offline strategy.
18. Build role-specific staff workspaces and the Live Operations Cockpit.
19. Add realtime updates, operational alerts, task ownership, reports and information-display/signage modes.
20. Implement external prerequisite tracking, including CDI request/schedule/completion coordination.

### Track E — Product-wide completion and release

21. Add organization/venue/event branding inheritance and template authoring across all generated outputs.
22. Complete localization, accessibility, privacy, retention and audit requirements.
23. Complete application-level integration, browser and workflow test coverage continuously during development.
24. Deliver and validate both installation methods.
25. Only after the product is functionally complete, deploy the release candidate to the `eventor-acceptance` VM and run the final end-to-end acceptance suite.
26. Conduct external HTTPS/provider/recovery/production-host acceptance after the VM acceptance baseline is clean.

Tracks can overlap where dependencies permit, but the order above reflects the principal dependencies. The Guest Registry and event participation model should precede full guest seating/check-in; venue geometry should precede allocation; admission credentials should precede gate scanning; the Cockpit should consume stable event, allocation, attendance and task projections.

## 5. Installation deliverable: native Linux and Docker

The installer is a product deliverable and must support two explicit deployment modes. Both modes must run the same release artifacts, use the same PostgreSQL schema/migrations and pass the same application acceptance suite.

### 5.1 Native Linux mode

- Supported Linux distribution/version matrix and prerequisite checks.
- Install/pin supported Node.js runtime and PostgreSQL compatibility requirements.
- Create dedicated unprivileged API/worker accounts and protected directories.
- Configure PostgreSQL roles and database, run checksum-verified migrations.
- Generate independent secrets and create root-managed, least-privilege environment files.
- Build/install versioned API and frontend release artifacts.
- Install and enable API/worker systemd units.
- Configure or integrate a supported reverse proxy and HTTPS; do not assume inbound port 80 is available (DNS-01 certificate validation must be supported).
- Create the initial organization and administrator through a secure first-run/bootstrap flow.
- Provide upgrade, rollback compatibility checks, backup, restore, service restart and health verification.

### 5.2 Docker mode

- Provide a maintained `compose.yaml` and versioned application images/build definitions.
- Include API, worker, web/reverse-proxy and PostgreSQL services with explicit health checks and dependency conditions.
- Persist PostgreSQL and required application data in named volumes or operator-selected bind mounts.
- Keep secrets out of images, source control, command history and container environment inspection where practical; document secret-file handling.
- Use non-root application containers, read-only filesystems where practical, dropped capabilities and explicit resource limits.
- Run migrations as a controlled one-shot deployment step, not as an uncontrolled race on every replica startup.
- Provide TLS/reverse-proxy integration, backup/restore, upgrade and recovery procedures.
- Support external PostgreSQL as an alternative where appropriate, without making it mandatory for the single-host deployment.

### 5.3 Shared installer requirements

- Interactive and non-interactive modes suitable for automation.
- Preflight checks, configuration validation and clear failure/rollback behavior.
- No destructive database reset during upgrade.
- Explicit database backup gate before schema migration.
- Versioned releases and compatibility checks between app and schema.
- Secure first-admin bootstrap; no hard-coded default password.
- SMTP is optional at install time; support local development/test capture (for example Mailpit) and later SMTP configuration such as Gmail SMTP or a transactional provider.
- Installation mode must not alter application features or security guarantees.

Native deployment has systemd unit templates, role bootstrap, migration and backup/restore checks. The native installer and operator runbook still need prerequisite detection, secure first-admin bootstrap, release staging, health/readiness and tested upgrade and recovery. The development Compose file starts PostgreSQL 18.6 on loopback. The release Docker topology and application images remain outstanding.

## 6. Immediate engineering priorities

1. Finish the organizer workflows in issue #104, starting with supervised merge cases involving active records and event controls.
2. Use issues #105–#107 for venue geometry, guest allocation and admission/check-in, in that dependency order.
3. Complete the booking lifecycle edges and disruption coordination tracked in issue #112.
4. Prepare the two production installation paths under issue #108 with controlled migrations, health verification, secure configuration and recovery.
5. Keep CI/unit/PostgreSQL/browser tests running on every feature PR. Reserve the dedicated `eventor-acceptance` VM for the final integrated release candidate.

## 7. Known limitations of this audit

- The matrix summarizes source inspection and references repository verification. Product-wide end-to-end acceptance, deployed-host testing and the final VM run remain outstanding.
- A route/schema/test fixture is not proof of a complete user workflow; classifications intentionally require both runtime and UI evidence for a usable feature.
- The GHB reference venue workbook, venue capacities, physical hierarchy, branding assets and operational policies still require validation with authorized venue representatives.
- No independent human reviewer was available for this audit. It is an implementation inventory and planning artifact, not an independent security or product certification.
- The audit baseline is the exact `main` commit stated at the top. Re-run/reconcile it as features merge.

## Dated scope clarification — 2026-11-27 (not a new runtime audit)

The owner-approved [Template Design Studio v1.0](implementation-design/v0.3/TEMPLATE_DESIGN_STUDIO_DESIGN_v1.0.md) clarifies #111 / Phase 7. Existing notification templates/revisions, campaign review and delivery infrastructure remain foundations. Rich-text WYSIWYG authoring, visual responsive block email authoring, graphical invitation/card canvas and print PDF pipeline are **missing as product workflows** at the inspected 2026-11-25 main baseline. Shared branding/asset/component and typed binding infrastructure is planned. Track TDS-M0–M6 and AC-01–25 separately; do not infer implementation or change completion scores merely from documentation. Preserve all previous gaps and current #104/#112 → #105–#107 priorities. Specialized seating, admission and maps wait for owning domains; no final VM acceptance before coherent release and both installers.

## Dated PAC scope clarification — 2026-11-27 (not a new runtime audit)

[Platform Administration Center v1.0](implementation-design/v0.3/PLATFORM_ADMINISTRATION_CENTER_DESIGN_v1.0.md) supplements Blueprint §§4,21,24,25,41 and #104/#108/#111. At the inspected e69d1c9 baseline, migration 000187, host provisioning scripts, selected-tenant workspace switching, scoped member directory/role administration and profile settings are implemented foundations. A dedicated graphical PAC, owner transfer/delegation/recovery lifecycle, global account/org console, platform-default brand editor, typed global policy/module governance, sensitive support/elevation, governance and host-operations console are **not delivered**. Existing systemd and database backup/restore CI are foundations, not deployed-host acceptance. Migration 000187 grants all non-platform permission codes to managed roles; reconcile Blueprint restricted-data boundary through a proposed successor ADR and reviewed compatibility migration, not an immediate change or claim of exploited leakage. Share TDS asset/brand revisions and domain/host command boundaries; track PAC-M0–M6 and PAC-AC-01–40. No changed completion estimate, current implementation priority, environment or final VM schedule follows from this documentation.

## Dated OAC / UX / lifecycle clarification — 2026-11-27 (not a new runtime audit)

At inspected main `0c5e7a2d`, permission-filtered tabs, email-first login, selected organization switching, profile/locale settings, host account/member provisioning, role grants and member suspension/restoration are foundations. Independent graphical tenant onboarding/staff enrollment/recovery, first-login resumable per-capability readiness, full OAC overview/portfolio and role-sensitive shell, tenant branding and coherent end-to-end lifecycle are **not yet complete**. Existing booking/event/Registry/invitation/delivery and collaboration workflows must be reused, not recoded. [OAC](implementation-design/v0.3/ORGANIZATION_ADMINISTRATION_CENTER_DESIGN_v1.0.md), [UX](implementation-design/v0.3/EVENTOR_USER_EXPERIENCE_AND_NAVIGATION_v1.0.md) and [OLA](implementation-design/v0.3/ORGANIZATION_LIFECYCLE_ACCEPTANCE_SCENARIOS_v1.0.md) provide scope, cross-module UX and future acceptance evidence respectively. No progress estimate or completion status changes simply because documentation is approved. Owner approved the three v1.0 scopes for documentation integration on 2026-11-27. The three reviewed source files are preserved verbatim, including their historical proposed-status text; this approval record governs their integration status, not approval of exact engineering decisions or immediate implementation. Existing accepted ADRs, historical Blueprint v1.2/v0.2 snapshots, issue obligations and current #104/#112 → #105–107 priorities remain unchanged. No runtime implementation or acceptance results are implied.

## Dated AGIS clarification — 2026-11-27 (not a new runtime audit)

[AGIS v1.0](implementation-design/v0.3/ADMISSION_GUEST_INFORMATION_AND_STATION_MANAGEMENT_DESIGN_v1.0.md) elaborates Blueprint §§11–13, 34–39 and existing issues #105–107/#111. At inspected main `a5cfcf0a`, migration `000014_allocation_attendance.sql` defines allocation revisions, assignments and locks, admission credentials, check-in stations, check-in attempts, attendance records and operational alerts. Schema presence is not evidence of operational issuance/scanning, device enrollment, exactly-once admission projection, guest-safe published allocation/wayfinding, verified kiosk lookup, configurable station designer, printing/reissue, live health or offline reconciliation. Reuse existing event, membership and invitation/RSVP boundaries, and audit current constraints, privileges and APIs at owning implementation time; new schema/route names are proposals only. Track these gaps and AGIS-AC-01–40 through existing issues and milestones, without counting documents as shipped functionality. This is an approved scope clarification, not a runtime implementation claim or instruction to interrupt the existing #104/#112 → #105–107 sequence. Preserve accepted ADRs, historical Blueprint v1.2, existing domain commands and issue criteria; final integrated acceptance remains Phase 9.

## Dated CID clarification — 2026-11-27 (not a new runtime audit)

[CID v1.0](implementation-design/v0.3/COMMUNICATION_INVITATION_DISTRIBUTION_AND_MULTI_CHANNEL_DELIVERY_DESIGN_v1.0.md) elaborates Blueprint §37.4 pluggable channels and existing invitation/notification designs. The inspected baseline `a5cfcf0a` already provides organization delivery config revisions/heads (000033–34), event campaign review/queue/history/reconciliation and signed Resend callbacks (000013, 000031–39), booking-offer email delivery/reconciliation (000058–59/74), invitation issue/delivery/attempt history and later authorization/idempotency guards (000075–89, 000099–105, 000111). SMTP supports secure transport and password/no authentication; Resend callbacks are not an HTTP sending adapter. Current automated invitation issue requires an eligible email route; current transport is plain text. Existing channel schema/purpose entries and queues are foundations, not evidence of SMS, OAuth, HTTP send, WhatsApp/Viber, Telegram, push, no-email invitation issuance, rich media, physical handover tracking, multi-provider routing, consent or cost governance. Implement compatible shared interfaces/read projections first; preserve legacy identities, snapshots, uncertainty semantics and populated upgrades. Track CID-AC-01–48 through #111 and owning domain dependencies. This is an approved scope clarification, not a runtime or acceptance claim. Preserve all existing requirements, accepted ADRs, historical Blueprint v1.2, current #104/#112 → #105–107 sequence and established #110/#111/#108 roadmap; no immediate implementation or environment republication. Final integrated acceptance remains Phase 9.

## Dated coordinated design clarification — 2026-11-27 (not a new runtime audit)

[AES v1.0](implementation-design/v0.3/ADAPTIVE_EXPERIENCE_AND_SETUP_DESIGN_v1.0.md), [EPW v1.0](implementation-design/v0.3/EVENT_PLANNING_PRODUCTION_AND_OPERATIONAL_WORKFLOWS_DESIGN_v1.0.md), [FRS v1.0](implementation-design/v0.3/FORMS_REGISTRATION_AND_SUBMISSION_STUDIO_DESIGN_v1.0.md), [HPG v1.0](implementation-design/v0.3/HOSPITALITY_PROTOCOL_AND_GUEST_SERVICES_DESIGN_v1.0.md), [RAI v1.0](implementation-design/v0.3/REPORTING_ANALYTICS_AND_INTELLIGENCE_STUDIO_DESIGN_v1.0.md) were prepared against `e0fa44203f785284d597f69dae8510c91bada0d6`. Existing event capability sets/revisions/overrides (000008), event/session commands (000121–127), organization settings, Registry/roster fields and import review provide AES/FRS/HPG foundations. Delegated task/audit commands (000023, 000108), booking resource/approval/cancellation workflows and event lifecycle provide EPW foundations, not a production planner or generalized approval designer. Public booking form projection/submission and authoring commands (000040–43, 000068) are working domain-specific form foundations, not full FRS. Guest group/relationship/encrypted note and field primitives (000145–48, 000168–70) are not a hospitality service workflow. Existing roster/Registry exports (000138–40, 000180), campaign reporting (000036) and permissioned domain projections are RAI foundations, not configurable reporting. Missing/partial capabilities include adaptive resumable setup, safe presets/recurrence, production plans and dependencies, reviewed registration/waitlists/accreditation, service requests and fulfilled arrangements, typed metric/dataset catalogue, configurable reports and scheduled delivery. Audit current runtime before compatible additive extensions; schema and documentation are not shipping evidence. Approved additive scope only; retain existing requirements, accepted ADRs, Blueprint v1.2, PROJECT_STATE and the #104/#112 → #105–107 → #110/#111/#108 development sequence. No immediate implementation, unrelated closure gates, environment republication or Blueprint v1.3 consolidation. Final integrated acceptance remains Phase 9.
