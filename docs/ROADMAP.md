# Eventor delivery roadmap

**Baseline date:** 2026-11-16  
**Product/design baseline:** Technical Blueprint v1.2 and accepted v0.3 domain/architecture decisions.  
**Implementation baseline:** `main` at `06d47b255c7107b94201c191da562ea2612e57c1` (PR #201). See [current state](PROJECT_STATE.md) for verification receipts.
**Detailed audit:** [Blueprint-to-repository gap analysis v1.0](BLUEPRINT_TO_REPOSITORY_GAP_ANALYSIS_v1.0.md).

## Current integration note — 2026-11-23

- Event administration, session lifecycle, persistent Guest Registry and event participation are usable from the bilingual staff workspace.
- Staff can review mapped CSV/XLSX imports, resolve matches by name or exact source reference, review proposed profile updates, and download filtered exports and import reports.
- Access administration includes organization profile settings, member search, scoped event roles and suspension/restoration. Provider disruption notices can be recorded and reviewed; cross-party delivery and acknowledgement remain open.
- The current product implementation track is #104, followed by venue geometry, allocation and admission under #105–#107. Issue #112 covers the remaining disruption coordination.
- Native and Docker production installation paths remain under #108. Current development Compose runs PostgreSQL only. Final acceptance remains scheduled for the integrated release candidate on the acceptance VM.

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

- [x] Ship organizer event create/edit/archive, approval, publication, start and close, and session list/create/edit/schedule/start/complete.
- [x] Ship persistent Registry profile search, edit/archive, history, encrypted contacts, source references and organization-level relationships with scoped grants.
- [x] Link Registry profiles to independently managed event participations with pinned event identity.
- [x] Ship event categories, internal and restricted tags, groups and roles, guest relationships and encrypted custom fields.
- [x] Ship mapped CSV/XLSX name imports with review, protected exact reference matching, and downloadable diagnostics and exports.
- [x] Ship supervised and reversible merges for unlinked profiles and non-overlapping closed-event history.
- [x] Ship personal roster views and atomic bulk category, status and internal tag edits.
- [ ] Finish organization, user, membership and role administration, event settings and session disruption workflows.
- [x] Extend reference imports to create profiles for authorized staff reviewing unmatched references.
- [ ] Add reviewed merge resolution for contacts, identifiers, active relationships and open or overlapping events.
- [x] Extend roster filtering and bulk management and add group allocation preferences and group-to-group relationships.
- [x] Verify signed-in provider isolation and event-scoped guest access, including grant revocation and Registry restrictions.
- [ ] Complete organizer/venue collaboration acceptance across booking, disruption and operational workflows.

**Planned platform administration refinement:** [PAC v1.0](implementation-design/v0.3/PLATFORM_ADMINISTRATION_CENTER_DESIGN_v1.0.md) defines PAC-M0–M2 for reviewed authority, organization/global account administration and a dedicated control-plane workspace, reusing #104. No immediate authentication rewrite; ADR 0015/0017/0020 remain in force until a reviewed successor decision and migration. Existing #104/#112 → #105–107 priorities remain unchanged.

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

- [ ] Deliver the [Template Design Studio v1.0](implementation-design/v0.3/TEMPLATE_DESIGN_STUDIO_DESIGN_v1.0.md) under #111: shared library, rich-text WYSIWYG, visual responsive drag-and-drop email design and precision graphical invitation/card design.
- [ ] Implement typed purpose-specific variables, reusable components/assets, versioned branding/locale variants, reviewed publication, secure server rendering and individual/bulk PDF/print layouts (TDS-M0–M6; AC-01–25). Admission/seating/map outputs depend on their owning workflows; basic invitation authoring does not.

**Scope clarification (2026-11-27):** this adds requirements to Phase 7, not a change of current priorities. Continue #104/#112, then #105–#107 as planned. Do not start Studio implementation merely because this documentation is merged. Preserve all existing Phase 7 acceptance requirements.

- [ ] Support plain text and HTML, variables, validation, preview, test-send, localization and revision history.
- [ ] Support approved bulk send, reminders, audience selection, retries and ambiguous-outcome reconciliation.
- [ ] Implement organization → venue → event branding inheritance and pinned asset/template revisions.
- [ ] Complete reusable forms and data/request submission workflows for guest registration and vendor/staff operations where required.
- [ ] Complete localization and accessibility across all user-facing modules.
- [ ] Add configurable reporting and document templates.

**PAC coordination:** PAC-M3/M4 add owner-controlled platform-default identity/theming, typed policy/module controls, data governance, scoped support and communications, sharing TDS brand/assets and existing domain commands under #111. Specialized interventions wait for owning workflows. No separate brand or delivery subsystem.

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

**PAC operations integration:** PAC-M5 under #108 covers measured health, backup manifests/restore drills, typed host-operation requests, local host maintenance/release recovery, same secure native and Compose procedures. PAC-M6 contributes AC-01–40 to Phase 9; no earlier VM requirement. The application must never receive arbitrary host privileges.

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

## Coordinated OAC / UX / organization lifecycle scope clarification — 2026-11-27

[OAC v1.0](implementation-design/v0.3/ORGANIZATION_ADMINISTRATION_CENTER_DESIGN_v1.0.md), [UX v1.0](implementation-design/v0.3/EVENTOR_USER_EXPERIENCE_AND_NAVIGATION_v1.0.md) and [OLA v1.0](implementation-design/v0.3/ORGANIZATION_LIFECYCLE_ACCEPTANCE_SCENARIOS_v1.0.md) are approved scope addenda. Track OAC-M0–M6, UX-M0–M5, OAC-AC-01–28, UX-AC-01–16, OLA-01–15 and G1–G9 without replacing existing gates. Phase 1: provider journey and booking workspace (#112 as applicable). Phase 2: tenant dashboard, resumable onboarding, independent staff administration and scoped shell (#104, PAC). Phase 3: organization-owned facilities/resources (#105). Phases 4–6: event transitions, allocation, admission and collaboration (#106/#107/#110/#112). Phase 7: shared brand/TDS, forms, reporting and governance (#111). Phase 8: PAC-to-OAC provisioning, secure enrollment/recovery, both installers (#108). Phase 9: full provider/organizer/hybrid lifecycle on both modes, with measured evidence, not earlier VM testing. Build incremental vertical slices under existing priorities; do not move all OAC/UX work ahead of spatial development or treat navigation redesign as an immediate rewrite. Owner approved the three v1.0 scopes for documentation integration on 2026-11-27. The three reviewed source files are preserved verbatim, including their historical proposed-status text; this approval record governs their integration status, not approval of exact engineering decisions or immediate implementation. Existing accepted ADRs, historical Blueprint v1.2/v0.2 snapshots, issue obligations and current #104/#112 → #105–107 priorities remain unchanged. No runtime implementation or acceptance results are implied.

## Approved AGIS scope clarification — 2026-11-27

[Admission, Guest Information and Station Management v1.0](implementation-design/v0.3/ADMISSION_GUEST_INFORMATION_AND_STATION_MANAGEMENT_DESIGN_v1.0.md) defines AGIS-01–20, AGIS-M0–M6 and AGIS-AC-01–40 as additional planned requirements and acceptance evidence. Preserve current #104/#112 foundation closure. Phase 3 (#105) supplies approved physical station anchors, guest-visible geometry and accessible routes; Phase 4 (#106) supplies published allocation and controlled changes; Phases 5–6 (#107) deliver safe station/device profiles, online admission, verified Info Pults, live Cockpit, bounded offline capture and local-validation package after security review. M0 runs when owning work is scheduled, M1–M4 follow domain dependencies. Phase 7 (#111/#107) completes configurable Station Designer, shared TDS brand/assets, localized print/reissue and passive display integration (M5). A safe built-in station UI and minimal online gate slice need not await advanced designer/route/print features. M6 integrated hardening, deployment/recovery in Phase 8 and actual dual-mode release acceptance in Phase 9 include all applicable criteria; offline event-level opt-out does not waive release-wide planned offline capability. This is an approved scope clarification, not a runtime implementation claim or instruction to interrupt the existing #104/#112 → #105–107 sequence. Preserve accepted ADRs, historical Blueprint v1.2, existing domain commands and issue criteria; final integrated acceptance remains Phase 9.

## Approved CID scope clarification — 2026-11-27

[CID v1.0](implementation-design/v0.3/COMMUNICATION_INVITATION_DISTRIBUTION_AND_MULTI_CHANNEL_DELIVERY_DESIGN_v1.0.md) defines CID-01–24, CID-M0–M7 and CID-AC-01–48. Phase 7 (#111) is primary ownership: M0 inventory and engineering review; M1 compatible shared delivery projection/SMTP adapter; M2 account management, optional platform-managed services, OAuth/HTTP email and TDS multipart; M3 no-email invitation issuance and controlled manual/physical distribution; M4 reviewed campaigns, schedules, preferences/consent, fallback and cost reservations; M5 official SMS/WhatsApp/Viber adapters (Telegram optional); M6 push/in-app and domain integration/hardening. M7 covers actual provider evidence, recovery and both installation modes in Phases 8–9. Existing #104 contact/identity and #112 booking/disruption work may complete using current SMTP/manual paths; #105/#106 supply approved maps/allocations, #107 supplies AGIS/portal, #110 supplies scoped task authority. No dependency on full CID for unrelated slice closure. Deployment independence; no mandatory paid service or assumption of a particular ISP. Verify advertised adapters with actual accounts/sandbox evidence, not mocks alone. This is an approved scope clarification, not a runtime or acceptance claim. Preserve all existing requirements, accepted ADRs, historical Blueprint v1.2, current #104/#112 → #105–107 sequence and established #110/#111/#108 roadmap; no immediate implementation or environment republication. Final integrated acceptance remains Phase 9.
