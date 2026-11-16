# Eventor delivery roadmap

**Baseline date:** 2026-11-16  
**Product/design baseline:** Technical Blueprint v1.2 and accepted v0.3 domain/architecture decisions.  
**Implementation baseline:** `main` at `da421567f68fd93976582374bf1ad8b493549d02` (PRs #128 and #129 cancellation integrations merged).  
**Detailed audit:** [Blueprint-to-repository gap analysis v1.0](BLUEPRINT_TO_REPOSITORY_GAP_ANALYSIS_v1.0.md).

## Current integration note — 2026-11-16

- Booking cancellation request/review, purpose-bound customer request capabilities and approved execution with atomic reservation release are integrated through PR #116 (migrations 000115–000118).
- Staff cancellation workspace and booking-revision-aware detail projection are integrated through PR #128 (migration 000119).
- Public customer cancellation request and reusable read-only status capability are integrated through PR #129 (migration 000120). The exact-head PostgreSQL 18.6 migration/RLS/concurrency suite, OpenAPI/API tests, staff-web tests/build, systemd verification and secret-history scan passed. Post-merge `main` contracts/PostgreSQL workflow #43934221982 and secret-history scan #43934221882 passed as well.
- The public page's source-level security regression tests cover fragment-only tokens, history cleanup, locale continuity, cookie omission and logger redaction. A dedicated Chromium/Firefox public cancellation browser journey remains to be added; existing browser acceptance covers auth and guest invitations.
- The next product implementation track is #104 (event administration and persistent Guest Registry), followed by #105–#107. The native and Docker Compose installers remain required under #108.
- Repository inventory still has only systemd deployment templates, no production Compose topology/Dockerfile and no complete native installer. The final acceptance VM remains deferred until product and both installers are ready.

## Delivery principle

Build a coherent, usable Eventor product before final environment acceptance. Continue automated tests throughout development. Do not spend the next phase repeating already-completed external acceptance preparation while core user workflows remain absent.

The product remains an API-first modular monolith:
- Vue 3 + TypeScript + Vite for staff and guest-facing interfaces.
- Fastify + TypeScript for the API and background workers.
- PostgreSQL as authoritative storage.
- SVG-based spatial model and editor.
- Transactional outbox and real-time publication.
- OR-Tools CP-SAT for advisory allocation proposals; a human must review and explicitly commit solver output.

## Phase 0 — Establish the current baseline

- [x] Merge the integrated PostgreSQL migration and feature stack (PR #85).
- [x] Merge worker and staff-session browser acceptance coverage (PR #99).
- [x] Merge guest invitation browser acceptance coverage (PR #101; mocked HTTP boundary).
- [x] Align invitation OpenAPI paths with runtime behavior (PR #102).
- [x] Audit Technical Blueprint v1.2 against actual runtime/API/UI/migrations/tests (PR #103).
- [x] Keep project-state, roadmap and issue tracker synchronized with the current implementation.
- [ ] Reconcile stale historical issues and PRs; do not mistake historical checklists for current status.

## Phase 1 — Complete a coherent venue-booking vertical

**Existing foundation:** public booking inquiries and forms, staff inquiry review, booking drafts/revisions, commercial offer and approval foundations, pricing/tax/cancellation configuration, resource reservations, notification campaigns and delivery worker.

- [ ] Audit each booking lifecycle transition against the v0.3 domain design and identify any remaining runtime/UI gaps.
- [ ] Complete direct/manual booking creation where not already covered.
- [ ] Complete offer revision, customer acceptance/rejection, approval and confirmation as one demonstrable workflow.
- [ ] Complete cancellation, amendment and postponement workflows with resource release and immutable commercial snapshots.
- [ ] Complete venue-side fulfilment/task assignment and responsibility history.
- [ ] Complete customer-facing booking communications and delivery reconciliation.
- [ ] Add operator-facing liveness/readiness and useful diagnostics.
- [ ] Define and automate end-to-end booking acceptance scenarios using synthetic fixtures.

## Phase 2 — Event organizer and Guest Registry foundation

- [ ] Complete organization, user, membership and role administration UX.
- [ ] Implement event create/edit/archive, lifecycle and session management.
- [ ] Implement persistent Guest Registry CRUD, search, profile history and permissioned access.
- [ ] Implement event participation and guest-list management independently of person records.
- [ ] Add categories, tags, groups, relationships and configurable custom fields.
- [ ] Add CSV/XLSX import/export with preview, validation, duplicate detection and error reporting.
- [ ] Add supervised identity merge with audit trail and safe correction/rollback strategy.
- [ ] Add bulk actions and saved views.
- [ ] Preserve tenant and organization ownership boundaries; never expose the organizer's guest directory to a venue provider by default.

## Phase 3 — Venue model and spatial editor

- [ ] Implement reusable venue/building/level/room/space hierarchy and versioned venue templates.
- [ ] Support halls, rooms, mosque/prayer spaces and other configured layouts without hardcoding one venue.
- [ ] Implement source-plan onboarding for PDF/image/SVG and workbook references, preserving originals and requiring human review.
- [ ] Build the SVG spatial editor with scale calibration, layers, geometry, labels and reusable objects.
- [ ] Model tables, rows, prayer rows, individual positions, capacity zones and non-allocatable features distinctly.
- [ ] Support color-coded tableless zones and mixed precise/count-based capacity.
- [ ] Add map revisions, approval, publication, history and printable output.
- [ ] Ensure accessibility and keyboard alternatives to drag-and-drop editing.

## Phase 4 — Guest seating and allocation

- [ ] Implement manual assignment and movement first.
- [ ] Implement category/group-based allocation and capacity validation.
- [ ] Implement together/avoid, preferences, exclusions, distance/session and other hard/soft constraints.
- [ ] Implement locks, diagnostics, conflicts and targeted reflow.
- [ ] Add OR-Tools CP-SAT worker behind a versioned, validated input/output contract.
- [ ] Present solver output as a proposal with explanation and before/after diff.
- [ ] Require explicit authorized human commit; never silently apply optimization.
- [ ] Publish immutable allocation-plan revisions and provide live staff and printable plan views.
- [ ] Render sanitized guest-facing map/wayfinding views.

## Phase 5 — Guest portal, invitations and admission

**Existing foundation:** capability-protected invitation links, RSVP, staff-recorded response/correction and invitation management UI.

- [ ] Complete batch invitations, reminders, delivery controls and full guest communication history.
- [ ] Build branded guest portal/PWA with event information and personal permitted data.
- [ ] Show the guest's own allocation and safe map/wayfinding, including accessibility information.
- [ ] Design and implement a separate admission credential lifecycle; invitation links are not admission passes.
- [ ] Generate revocable opaque QR credentials and printable guest cards.
- [ ] Implement gate scanning UI/PWA, station/operator management, manual lookup and correction.
- [ ] Prevent duplicate admission and preserve audit history across multiple gates.
- [ ] Add real-time synchronization and bounded offline tolerance with explicit reconciliation.
- [ ] Keep invitation, RSVP, eligibility and physical attendance as separate facts.

## Phase 6 — Event-day operations and collaboration

- [ ] Build the Live Event Operations Cockpit with role-scoped live metrics, map layers, alerts, timeline and interventions.
- [ ] Add role-specific reception, gate, seating, venue, floor/zone and management workspaces.
- [ ] Implement staff/vendor assignments, deliverables, deadlines, evidence and scoped collaboration.
- [ ] Implement external prerequisite/CDI tracking as a readiness checklist (request, responsible party, schedule, status, completion and restricted references).
- [ ] Add transactional-outbox-backed realtime updates and reconnect/resynchronization.
- [ ] Add read-only information display panels for welcome, session, venue, seating, directions and announcements.
- [ ] Add operational reports, exports, printable plans, guest cards and signage.

## Phase 7 — Communications, branding and configuration

- [ ] Build a real email template composer/editor (not merely campaign review).
- [ ] Support plain text and HTML, variables, validation, preview, test-send, localization and revision history.
- [ ] Support approved bulk send, reminders, audience selection, retries and ambiguous-outcome reconciliation.
- [ ] Implement organization → venue → event branding inheritance and pinned asset/template revisions.
- [ ] Complete reusable forms and data/request submission workflows for guest registration and vendor/staff operations where required.
- [ ] Complete localization and accessibility across all user-facing modules.
- [ ] Add configurable reporting and document templates.

## Phase 8 — Installation, upgrade and operations

One release artifact must support two equivalent installation modes.

### Native Linux
- [ ] Dependency and supported-distribution detection.
- [ ] Dedicated service identities, filesystem permissions and secure secret provisioning.
- [ ] PostgreSQL setup/connection, migration and least-privilege role provisioning.
- [ ] API, worker and frontend deployment with systemd services.
- [ ] Reverse-proxy/HTTPS integration and trusted-proxy configuration.
- [ ] Initial administrator/bootstrap flow and configuration validation.
- [ ] Upgrade, rollback, backup/restore and service health commands.

### Docker Compose
- [ ] Production-oriented Compose topology for API, worker, frontend/reverse proxy and PostgreSQL as appropriate.
- [ ] Persistent volumes, non-root containers, health checks and dependency readiness.
- [ ] Secret/environment handling without committing credentials or baking them into images.
- [ ] Migration and initial-admin bootstrap workflow.
- [ ] Upgrade, rollback, backup/restore and log/health procedures.
- [ ] Document external reverse-proxy use and optional bundled proxy topology.

### Shared release requirements
- [ ] Both modes use the same application build, migrations, configuration schema and security defaults.
- [ ] Installer offers a clear native-versus-Docker choice and validates prerequisites before changing the host.
- [ ] Idempotent install/upgrade behavior and safe failure recovery.
- [ ] Document supported Linux versions, resource sizing, networking, SMTP and DNS/TLS options.
- [ ] Local email capture (for example, Mailpit) supported for development/testing; external SMTP is configurable, not mandatory for local development.

## Phase 9 — Integrated release candidate and final acceptance

**The `eventor-acceptance` QEMU/KVM VM is deliberately reserved for this final phase.** It is not the environment for early feature discovery.

- [ ] Freeze a coherent release candidate after Phases 1–8 are functionally complete.
- [ ] Run a clean native installation on the acceptance VM.
- [ ] Run a clean Docker Compose installation on the acceptance VM.
- [ ] Exercise upgrade and rollback paths for both deployment modes.
- [ ] Execute complete venue booking and organizer event workflows.
- [ ] Execute guest import, invitations, RSVP, seating, QR admission and multi-gate check-in.
- [ ] Exercise cockpit, vendor/staff coordination, CDI readiness and information displays.
- [ ] Test email capture and at least one external SMTP sandbox/provider.
- [ ] Validate public HTTPS with the intended reverse proxy/tunnel and domain.
- [ ] Rehearse representative database upgrade, off-host backup/restore, PITR and encryption-key recovery.
- [ ] Run security, tenant isolation, accessibility, browser/device, load and failure-recovery checks.
- [ ] Record evidence and unresolved limitations; do not claim production readiness without passing gates.

## Scope and product-owner dependencies

- The platform remains reusable and self-hosted; GHB is the first reference organization, not a hardcoded product boundary.
- Booking-only venue-provider use must remain possible without activating organizer guest/event capabilities.
- Venue facts, capacities, prices, approval authorities, cancellation terms and operational policies require owner confirmation before being enforced as GHB-specific configuration.
- The application records external coordination and assigned responsibilities; it does not implement law-enforcement or inspection activity.
- No real guest information, credentials, invitation tokens, private venue drawings or operationally sensitive source material may be committed.

## Current priority

Proceed with **Phase 1 audit/closure and Phase 2 event/Guest Registry foundation**. Do not start the acceptance VM stage until the application and both installers form a coherent release candidate.
