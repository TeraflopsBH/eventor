# Blueprint-to-repository gap analysis — v1.0

**Audit baseline:** `main` at `f9664bc2a4d5a8e5b770988441198acf0c624f31`, with the Registry contact branch assessed separately (2026-11-17)

**Blueprint:** Technical Blueprint v1.2  
**Purpose:** establish what exists in the repository, what is only a design/schema foundation, what is partially usable, and what remains to be built before Eventor is a ready-to-use event operations product.

This is a static repository audit of the source tree, API route registrations, Vue application composition, migrations, tests and deployment files. It is not a claim that every existing workflow has been manually exercised. CI evidence and the separate external-acceptance record remain authoritative for what has actually been tested.

## 1. Executive assessment

Eventor is **not yet a complete event operations application**. The current implementation is materially weighted toward the venue-booking/commercial vertical. It has a substantial PostgreSQL/security foundation, working staff authentication, a Vue staff shell, public booking inquiry forms, booking inquiry/draft/offer workflows, commercial configuration, notification campaigns/delivery, a meaningful invitation/RSVP slice, and an integrated booking-cancellation request/review/approved-execution workflow with a public customer request/status journey.

The event-operations domains that make the product distinctive remain mostly unimplemented at runtime: persistent guest registry management, venue/floor-plan editing, guest seating and zone allocation, solver-assisted allocation, admission QR credentials, gate scanning, live operations cockpit, role-specific event-day workspaces, branding inheritance, CDI/prerequisite coordination, and reporting/print/display outputs.

The distinction is important: **a database table, migration, OpenAPI schema, test fixture or design document is not a finished user-facing feature**. The status below separates foundations from usable application workflows.

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
| Event administration and sessions | Migrations 000121–000123 and the bilingual Events workspace provide event list/create/edit/archive. Migration 000124 adds session listing and planned-session creation. Migration 000125 adds revision-checked session editing. Migration 000126 adds organizer approval and schedule publication. Migration 000127 adds event start and close and session scheduling, start and completion. | **Partial** | Session-specific disruption handling, event settings, capability activation, and venue assignment. |
| Persistent Guest Registry | Migration 000128 adds organization-scoped name search, profile creation, viewing, editing and archival to the existing person records. Migration 000129 adds profile and event participation history. Migration 000132 adds encrypted contact capture and consent. | **Partial** | Contact verification, duplicate review and audited merge, import/export, saved views, relationships and groups. |
| Event participation and guest list | Participation/eligibility projections, RSVP/invitation runtime and permissioned Registry linking with pinned identity snapshots and revision-checked status changes | **Partial** | Complete event guest-list management, categories/tags/custom fields, groups, bulk actions, event-specific snapshots, search and data provenance. |
| Invitations and RSVP | Guest capability resolution, invitation view, RSVP submission/history, issue/reissue/revoke, staff-recorded RSVP/correction, delivery-attempt history; staff invitation workspace and guest invitation page | **Implemented slice** | Batch issuance, reminders, broader guest self-service, full communication controls, provider callback/reconciliation for ambiguous guest-invitation delivery, and full guest journey acceptance. |
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
| Reports, exports, guest cards, signage and information displays | No complete report/export/document-generation or display-panel feature found | **Missing** | Permission-scoped exports, operational reports, printable plans/cards, configurable signage and read-only information display mode. |
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
- Organizer event administration.

This is a real staff application, not a blank shell. However, it is not yet the blueprint's event operations cockpit or the complete navigation/workspace map.

### 3.2 Runtime API boundary

The current API route families include booking forms/inquiries/drafts/offers, price/tax/approval/cancellation policies, booking reservation commands, staff booking-cancellation review/detail/decision/preview/execution, external booking-action capability issue/revoke/resolve, public cancellation request/status, organizer event administration, event invitation projections, guest invitation issue/revoke, guest RSVP and delivery configuration/campaign operations.

The audited route registrations did not reveal runtime route families for Guest Registry CRUD/import, venue/floor-plan editing, event guest allocation, admission QR, check-in stations/scanning, cockpit/realtime, external prerequisites, branding or vendor workspaces. Their appearance in design documents or early migrations must not be counted as implementation.

The current API has separate API and notification-worker entry points. The worker handles notification delivery; it is not the planned allocation solver or event-operations job platform.

### 3.3 Database maturity

Main has 131 ordered migrations. The Registry contact branch adds migration 000132. They provide a substantial foundation for tenancy, authorization, venue/resource booking, event/guest/invitation/attendance concepts, collaboration, notifications and commercial booking. The migration count is not a feature-completion metric: later runtime/API/UI work is still required for several domains. Migrations 000115–000120 add the cancellation request/review/execution and public status-capability slice; they do not complete event administration or the Guest Registry.

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

6. Complete organization/user/membership/role administration and event CRUD/session lifecycle.
7. Implement persistent Guest Registry CRUD, import/export, deduplication, supervised merge and event participation management.
8. Complete guest categories, tags, groups, relationships, custom fields and bulk workflows.
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

The existing systemd unit templates, role bootstrap and migration runner are useful foundations, but they are not yet a complete native installer. Development Compose supplies PostgreSQL 18.6. The release Compose topology and application images remain outstanding.

## 6. Immediate engineering priorities

1. Treat this document as the current static gap baseline and reconcile the older roadmap/project-state documents so they no longer refer to superseded draft PR stacks or stale phase status.
2. Create a dependency-aware product backlog with one issue per vertical slice, each defining API, UI, database, security, localization and acceptance criteria.
3. Agree the first complete usable product milestone. Recommended: finish the venue-provider booking lifecycle as a coherent product while starting the Guest Registry/event organizer foundation; do not declare Eventor complete at the booking-only milestone.
4. Implement Guest Registry CRUD, search and history using the existing person and participation foundations. Follow with import preview and commit, duplicate handling and supervised merge.
5. Keep CI/unit/PostgreSQL/browser tests running on every feature PR. Reserve the dedicated `eventor-acceptance` VM for the final integrated release candidate.

## 7. Known limitations of this audit

- Static source inspection only; no local build, browser session, database deployment or VM test was run for this audit.
- A route/schema/test fixture is not proof of a complete user workflow; classifications intentionally require both runtime and UI evidence for a usable feature.
- The GHB reference venue workbook, venue capacities, physical hierarchy, branding assets and operational policies still require validation with authorized venue representatives.
- No independent human reviewer was available for this audit. It is an implementation inventory and planning artifact, not an independent security or product certification.
- The audit baseline is the exact `main` commit stated at the top. Re-run/reconcile it as features merge.
