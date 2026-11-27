# Eventor Adaptive Experience and Setup (AES)
## Technical specification v1.0

**Status:** Proposed for product-owner approval; no integration or implementation authorized by this draft.  
**Date:** 2026-11-27. **Read-only repository baseline:** `e0fa44203f785284d597f69dae8510c91bada0d6` (main, CID PR #236). All five required CI checks on this baseline were observed completed successfully during preparation. CI is not product acceptance.  
**Proposed destination:** `docs/implementation-design/v0.3/ADAPTIVE_EXPERIENCE_AND_SETUP_DESIGN_v1.0.md`. Links are relative to that future location. The five proposed documents are companion drafts, not yet repository files.  
**Document control:** AES-01–15, AES-M0–M5, AES-AC-01–30. MUST denotes proposed product requirement, SHOULD preferred approach with justified exceptions, MAY optional. Endpoint names, entity names, permission codes and numerical envelopes are design proposals, not existing runtime contracts or certified targets. No acceptance tests executed.

## 1. Objective and boundaries

Make a small meeting as easy to configure as a calendar appointment while allowing the same event to become a complex institutional ceremony. Provide Quick Start, Guided Setup and Advanced Setup, a common setup/readiness contract, organization presets and progressively disclosed specialist tools. The minimum event is a draft containing the existing mandatory name, schedule/timezone and ownership fields; location and expected participants may be supplied or explicitly unresolved where the domain permits. No requirement to activate guests, RSVP, venue drawing, seating, admission, suppliers, hospitality or external delivery. A venue provider can create a booking inquiry/draft without any event. Never create a second simplified event table or duplicate auth, capacity, booking or policy state. Event templates are EPW-owned; AES presents and applies their reviewed configuration choices. No AI-generated irreversible decisions, arbitrary automation or bypass of approval/security. This is the cross-module experience contract; not a redesign of every existing page before further delivery.

## 2. Existing foundation and reconciliation

Blueprint §§2, 4–6, 7–13, 25, 34–35, 41–46 already allow optional event capabilities and typed layouts. Migration `000008_event_foundation.sql` defines events, event_schedule_revisions, event_sessions, event_capability_sets, event_capability_revisions and event_capability_overrides; 000121–127 provide organizer commands and lifecycle, 000189 RSVP settings. OAC-02 readiness, OAC-13 safe duplicate, UX-03 setup and UX-04/05 permission-scoped navigation are foundations. Current staff workspace implements event/session administration and optional roster capability, not a complete adaptive creation flow. Current handoff remains #104/#112. Do not assume that a feature listed in the design or database is operational.

Use [Blueprint v1.2](../../blueprint/v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md), [architecture](../../ARCHITECTURE.md), [roadmap](../../ROADMAP.md), [project state](../../PROJECT_STATE.md), [gap analysis](../../BLUEPRINT_TO_REPOSITORY_GAP_ANALYSIS_v1.0.md), [operating model](../../OPERATING_MODEL.md), and [roles](../../product/USER_ROLES_AND_PERMISSIONS_v0.1.md). Read [RSVP design](RSVP_AND_INVITATION_DESIGN_v0.3.md), [collaboration design](CROSS_ORGANIZATION_COLLABORATION_DESIGN_v0.3.md) and [disruption design](CANCELLATION_AND_EVENT_DISRUPTION_DESIGN_v0.3.md) for owning commands. Existing accepted decisions prevail until reviewed successor: [modular monolith](../../decisions/0001-modular-monolith.md), [self-hosting](../../decisions/0002-self-hosted-deployment.md), [human-approved allocation](../../decisions/0003-human-approved-allocation.md), [optional scope](../../decisions/0004-optional-event-operations-scope.md), [invitation separation](../../decisions/0005-separate-invitations-rsvp-attendance.md), [collaboration](../../decisions/0006-cross-organization-collaboration.md), [localization](../../decisions/0007-internationalization.md), [incremental staff UI](../../decisions/0008-modular-staff-frontend.md), [membership protection](../../decisions/0010-organization-membership-access.md), [login/workspaces](../../decisions/0015-email-first-login-and-platform-administration.md), [scoped grants](../../decisions/0023-permissioned-collaboration-grant-lifecycle.md), [reviewed grant acceptance](../../decisions/0024-shared-party-names-and-reviewed-grant-acceptance.md).

| Approved addendum | Reconciliation rule |
| --- | --- |
| [TDS](TEMPLATE_DESIGN_STUDIO_DESIGN_v1.0.md) | Quick selection of published templates and synthetic preview; Advanced opens shared editor, no implicit issuance/send. |
| [PAC](PLATFORM_ADMINISTRATION_CENTER_DESIGN_v1.0.md) | Platform allowed/supported capabilities, policy ceilings, managed defaults and local host recovery; tenant wizard cannot elevate authority. |
| [OAC](ORGANIZATION_ADMINISTRATION_CENTER_DESIGN_v1.0.md) | Compose the existing independent tenant onboarding/readiness and facility settings; same role and ownership model. |
| [UX](EVENTOR_USER_EXPERIENCE_AND_NAVIGATION_v1.0.md) | Extend UX-03/04/05; preserve route guards, accessible component system, context switch and truthful action receipts. |
| [OLA](ORGANIZATION_LIFECYCLE_ACCEPTANCE_SCENARIOS_v1.0.md) | Add simple, guided and advanced journeys and in-place upgrade to OLA-03/05/07/09/14/15. |
| [AGIS](ADMISSION_GUEST_INFORMATION_AND_STATION_MANAGEMENT_DESIGN_v1.0.md) | Only expose stations and admission when explicitly enabled; safe built-in layouts and verified Info Pult remain governed by AGIS. |
| [CID](COMMUNICATION_INVITATION_DISTRIBUTION_AND_MULTI_CHANNEL_DELIVERY_DESIGN_v1.0.md) | Manual or quick invitation route and advanced campaigns use CID consent, cost, audience review and independent issuance. |

### Companion proposals (not yet approved)

| Companion | Interface and boundary |
| --- | --- |
| [EPW](EVENT_PLANNING_PRODUCTION_AND_OPERATIONAL_WORKFLOWS_DESIGN_v1.0.md) | Owns versioned reusable event templates, series and production workflow. AES previews/applies selected safe configuration via EPW and owning commands. |
| [FRS](FORMS_REGISTRATION_AND_SUBMISSION_STUDIO_DESIGN_v1.0.md) | Ready-made published form or advanced schema designer; setup chooses purpose; submissions never silently approve. |
| [HPG](HOSPITALITY_PROTOCOL_AND_GUEST_SERVICES_DESIGN_v1.0.md) | Optional basic headcount/service request or detailed hospitality; restricted fields never inherited into generic wizard. |
| [RAI](REPORTING_ANALYTICS_AND_INTELLIGENCE_STUDIO_DESIGN_v1.0.md) | Standard reports as defaults, authorized custom reports in advanced view; no extra data rights from mode. |

## 3. Adaptive experience and user journeys

OAC > Events > New event opens a simple choice: Quick Start (default), Guided, Advanced, or from authorized preset. Keep a visible “Show advanced settings” / “Return to simple view” action; selection follows current user preference, not tenant subscription. Quick Start example: synthetic 20-person meeting, bilingual name with required locale, date/start/end or duration, timezone prefilled visibly, location optional/existing room/external/online, estimated participants optional, basic guest list optionally enabled. Review exact choices, save draft, show next actions. Add invitations only after explicit choice and readiness; no forced layout. For Guided, step Basics → location/time → needs → optional module-specific steps → review; skip/defer unneeded sections with reasons. For Advanced, show event settings, revisioned domain workspaces, warnings and same draft. On mobile use one-column stepper with progress and back; desktop summary and accessible step navigation. Focus returns to error or newly opened section; preserve valid answers when switching steps. Autosave only explicitly authorized draft fields, disclose save state; no send, approval or reservation from autosave. User may close and resume from OAC work list. For already-published/live event, configuration changes enter owning reviewed change flow, never draft wizard overwrite.

| Preset (illustrative) | Suggested choices, never compulsory |
|---|---|
| Meeting | Basic schedule, optional list, simple room |
| Reception | Guests, optional invitation/RSVP, optional table assignment |
| Conference | Sessions, registration, programme, optional admission |
| Prayer gathering | Typed zones/capacity if enabled, optional map and directions |
| Training | Registration, optional attendance, feedback |
| Online | Approved external meeting link, optional registration/communication, no physical reservation |
| Formal ceremony | Production, protocol, allocation, hospitality, stations, approvals if applicable |

Example of progression: draft meeting → add list/RSVP → publish approved venue/allocation → enable admission and staff tasks → operate EOC. Same event ID and guest participation history; previous published artifacts and decisions remain unchanged. Quick Start is available also from venue, roster import, seating, communications, forms, reports and installer workflows; specialized advanced pages remain discoverable to authorized users.

All modes are projections over the same canonical records and commands. Quick Start is not a permission class, price tier, alternate storage model or waiver of domain rules. Guided mode adds relevant questions; Advanced exposes authorized settings and diagnostics. Mode changes do not themselves mutate domain facts, publish, send, reserve, approve or grant authority. Defer optional setup; distinguish not applicable, not enabled, not configured, blocked and ready. A user can resume a draft and switch modes without losing valid work. Show reasons and a permitted next action, not inaccessible target IDs. Use bs-BA/en, IANA timezone, locale-aware number/date display and immutable authored translations; no silent translation of legal or guest-facing meaning. All visual interactions have keyboard/non-drag equivalents. User preference, organization default, and event capability are separate.

## 4. Functional requirements

### AES-01 — Setup modes and preference

MUST offer Quick Start, Guided and Advanced with the same canonical actions and default validation. Personal mode preference is per user/workspace or event view, not shared event lifecycle state; organization may set suggested default and permitted preset catalog. Mode switch persists presentation only and never alters existing configuration; a manager using Advanced cannot gain more access than the same manager in Quick Start. Never hide mandatory review, disabled controls with critical warnings or an ongoing action solely because the view is simple.

### AES-02 — Minimal event creation

Use existing event create command and mandatory validation; offer generated code only if existing domain permits, required localized title, IANA zone, start/end or explicitly unscheduled draft if domain permits. Show interpreted absolute instants including DST ambiguity; require choice when nonexistent/ambiguous local time. Estimated attendees not capacity, RSVP or reservation. External/online location is descriptive, not a booking. Existing room selection checks authorized availability as a preview, not a hold. Final button Save draft is explicit; event lifecycle remains draft until separate owning command.

### AES-03 — Guided step orchestration

Use an allowlisted typed step registry, prerequisites and current effective answers; server computes applicable questions from selected needs, authority and existing feature readiness. Bounded acyclic dependency graph, deterministic ordering and reasons. Back/skip/defer preserve compatible draft values; removing an answer invalidates dependent review only, never silently deletes existing entities. Persist progress as versioned draft; cross-device resume revalidates membership, event revision, policy and current capabilities. No hidden mandatory approval; direct Advanced route remains available.

### AES-04 — Progressive capability configuration

Separate supported by release, permitted by platform, enabled by tenant/event, configured, ready, authorized for actor and temporarily degraded. Use existing capability set/revision/override aggregate; detect conflicts and dependencies with a reviewed impact preview. Allow enable later on same event, create only needed domain configuration. No requirement for seating if only RSVP, no guest module for venue-only bookings, no QR for information lookup. Disabling a capability with active credentials, jobs, allocations or responsibilities requires owning drain/revoke/retire decision and retains history. Not enabled is not permission denial or a paywall.

### AES-05 — Presets and safe template application

Organization owns suggested preset metadata and explicit EPW template revision references. Review diff before applying: choices, resolved settings, required modules, missing permissions, dependencies, target revisions and skipped items. Clone safe configuration only. Never copy guests, contact points, notes, consents, credentials, delivery queues, reservations, approvals, attendance or prior evidence. Resolve branding, policy, locale and published template refs using current allowed revisions, warn if retired/missing, no silent fallback. User may start empty or override permitted defaults; preserve provenance.

### AES-06 — Draft resilience and review digest

Setup draft has revision, step progress, chosen mode, intended target event or create-intent, input snapshot and expiry/owner context. Sensitive data minimized; no tokens or credentials. Autosave uses compare-and-set and visibly reports unsaved conflict, never overwrites another operator. Review computes canonical digest of selected actions, expected target revisions, template/policy versions, actor scope and exclusions. Commit rechecks digest and permissions; atomically create event plus supported inseparable configuration where feasible; optional cross-domain steps have explicit per-step receipts and resume, no ambiguous partial success. Repeating same intent never creates duplicate event.

### AES-07 — Contextual navigation and readiness

Derive authorized menu, actions, badges, search and counts from effective scope and enabled capabilities. Simple meeting shows Overview, optional Guests, optional Invitations, Settings; advanced does not list inaccessible objects. Readiness uses OAC existing statuses, reason code, as-of timestamp, route key and allowed action; display unsupported or blocked only if safe. Separate configuration completeness from runtime health and approval. Role revocation clears cached views/streams, active draft and private previews on context change.

### AES-08 — Quick venue and allocation path

Provide basic room hierarchy and reviewed capacity without detailed drawing; authorized venue manager can create versioned simple space through #105. Geometry, source plan import and calibration optional unless map/precise allocation requires them. Count zone/manual table assignment uses #106 authoritative capacity constraints and approved plan; never generate fictitious seats, route or publish solver output automatically. Wizard can defer plan creation, display unavailable dependencies and link authorized spatial workflow. Provider resource availability remains separate from organizer seating.

### AES-09 — Quick guest and registration path

Allow add one profile or link existing, review import column suggestions and choose existing match/new profile via existing Registry commands. Event-specific data remains separate. Never auto-merge from similarity or copy restricted fields to wizard. Basic registration selects FRS published preset; invitation-only or open application intake requires explicit audience/policy. Review accepted registrations before linking participation; no submission, RSVP or invitation acceptance automatically records attendance.

### AES-10 — Quick invitation and communication path

Select published localized TDS template, explicit audience and preferred eligible CID route, show exclusions and estimate, preview synthetic or authorized protected individual context. Staff can issue without email when CID supported; manual print/share and telephone remain explicit. Send only separate authorized review/confirm; no auto-send on event create, preset apply or mode change. Advanced campaign designer available without recreating invitation or recipient. No consent inheritance from other events/channels.

### AES-11 — Quick production and hospitality path

Simple event may use a checklist and headcount rather than timeline, detailed shifts or service plans. EPW tasks retain owner, due, scope and evidence; HPG can collect aggregate demand without personal sensitive data. Guided mode suggests only relevant steps; approval and hard constraints remain mandatory even with one operator. Detailed production/guest services can be enabled later without moving records. No default staffing, meal quantities or actual GHB needs inferred.

### AES-12 — Quick reports and training

Offer authorized standard event summary, roster or attendance report, with visible metric definitions, scope and freshness; RAI advanced report configuration uses same dataset catalogue. Provide synthetic preview/sample event only in explicitly isolated training workspace or separate test tenant with local capture and no live credentials/external sends; do not silently seed real tenant or create training mode as permission bypass. Accessible contextual help and step explanations without leaking other tenants.

### AES-13 — Setup defaults and administrative policy

Resolution order explicit permitted user choice → event preset/template revision → tenant defaults → platform defaults, except hard ceilings always enforced and event/venue brand precedence unchanged. Record source/revision per effective setting; missing default prompts or remains deferred, never invent legally binding policy, capacity or authority. Tenant administrator controls own approved defaults via OAC; PAC governs supported features and bounds. Default changes affect new drafts only unless explicitly reviewed transition. Provide preview of changes and safe reset of view preferences only.

### AES-14 — Installer and recovery experience

Phase 8 native/Compose installer offers guided default and advanced configuration through the same validated local host plan; dry-run shows dependencies, network/TLS/DB/storage/secret prerequisites, intended changes and recovery path. No browser shell/root access, no assumed home ISP restrictions, no SMTP required for manual/local mode. Persist safe progress and idempotent checkpoints, detect existing installation, do not overwrite secrets/data, explicit confirmation before host mutations. Both modes equivalent and final VM Phase 9.

### AES-15 — Adaptive quality and accessibility

Measure time and number of required steps for representative simple setup; propose median ≤120 seconds for trained operator from authenticated ready tenant with one simple event draft, ≤4 steps, no optional module blockers. Guided explanations use plain language and safe next actions. Support keyboard-only and touch, responsive and localized form labels, undo unsaved changes, focus management, clear offline/degraded state. No action that appears successful until server receipt. Record metrics without names or content; mode preference cannot affect domain permission results.

## 5. Workflow, transaction and failure semantics

### State and transaction contract

`new → editing → reviewed → committing → applied` with `editing/reviewed → expired/abandoned`; failed or stale commit returns editable draft with reason and fresh review requirement. A setup receipt lists event ID, completed steps, skipped/deferred steps, failed step IDs and current revisions. A partially applied plan does not masquerade as rollback: atomic core transaction creates draft and inseparable basic settings; optional steps run only when explicitly included and owning command can safely execute. Persist per-step idempotency key/receipt and display partial status; do not run subsequent dependent steps after failure. Never compensate by deleting created event with history. Resume from current state, recheck authority and review material changes.

1. Load current actor, capability/readiness and preset catalog (authorized projection).
2. Save draft with expected revision; validate bounded values and server-calculated applicability.
3. Preview changes, exclusions, unresolved prerequisites, current revisions and no-side-effect guarantee.
4. Explicit commit with digest and idempotency; lock target event/create-intent, validate current policy and permissions, invoke owning domain command; outbox/audit commit together.
5. Return exact receipt. Enable separate next actions for guest import, invitation review, approval/publication, reservation or station activation.

### Example failures

| Situation | Response |
|---|---|
| Room becomes unavailable | Show stale preview/conflict; draft survives without reservation, request alternative |
| Template retired after review | Re-review allowed replacement or start empty; no hidden substitute |
| Membership revoked during resume | Deny and clear personal context; another authorized manager may recover permitted draft |
| Network loss after commit | Unknown result; query idempotent receipt under current authority, never create again blindly |
| Live event capability disable with active passes | Block/defer to AGIS revoke/drain and approved impact review |
| Missing external provider | Manual/local CID path or defer communications; no event creation block |
| Unsupported module on release | Display not supported, no fake activation; preserve approved product gap |
## 6. Architecture and logical data model

Extend the existing Vue 3/TypeScript staff application, Fastify API/workers and PostgreSQL 18.6 modular monolith; no mandatory external SaaS or second database. Reuse domain commands, approved TDS renders, CID delivery, transactional outbox and scoped projections. Logical names below are candidates; inventory actual schema, role grants, lock order, indexes, views, current APIs and fixtures at M0. Add only missing extensions with forward migrations; no rewriting historical migrations, accepted ADRs or the v0.2 schema/OpenAPI snapshots. All tenant-owned keys include organization context; event references include event scope, verified by composite FK or equivalent command integrity. Cross-party references use explicit accepted grant/revision and permitted projection, never broad joins. Immutable published revisions, decisions, receipts and evidence retain source IDs; append correction/supersession rather than destructive rewrite. Sensitive values and private artifacts use authenticated encryption and purpose-bound identity; no secret in audit or general projections.

| Logical entity or existing aggregate | Principal fields / keys | Integrity and lifecycle |
| --- | --- | --- |
| events / sessions / schedule revisions | existing tenant/event IDs, time zone, schedule revisions | Canonical; preserve lifecycle and approvals |
| event_capability_sets/revisions/overrides | existing typed keys, effective state | Reuse, no shadow enabled flags; reviewed dependency changes |
| setup_draft (candidate) | org, actor/owner, target event nullable, revision, schema version, mode hint, progress, typed input, expiry | CAS; protect payload; never store raw tokens; draft-only state |
| setup_review / receipt | draft revision, canonical digest, expected domain revisions, intent ID, step receipts, timestamps | Immutable review/receipt, single create-intent; reauthorize replay |
| setup_preset / revision | org, key, localized name, EPW template ref, optional capability suggestions | Published immutable metadata; no guest data or authority |
| user experience preference | user, membership context, view mode, revision | Presentation only, no role or domain change |
| readiness projection | scope, capability key, support/enable/config/health, reason, observed revision/time, action key | Derived from owners, no persistent duplicate truth |
| installer plan (host artifact) | local manifest version, mode, actions, prereq results, checkpoints | Protected local host only; no web arbitrary commands |

### Migration and compatibility

Audit existing tables and commands first; additive sidecar only where needed. Backfill through reviewed deterministic mapping with exception report, preserve existing IDs, historical snapshots and access semantics; default newly introduced capabilities to disabled/unconfigured unless existing equivalent facts justify activation. Test fresh install and populated upgrades, RLS and grants with runtime/auth/worker roles; old clients retain supported route behavior. No destructive down migration for recorded facts; recovery through tested compatible release or controlled restore and reconciliation. Add indexes for tenant/event/status/revision and due work; measure plans on synthetic representative cardinality; do not rely on client-side filtering.

## 7. API and permission contracts

Paths are relative to the existing API version; exact prefix, schema, codes and permissions determined after M0 inventory. Every staff route authenticates active user, selected membership, tenant, domain permission and object scope before lookup; delegated grants checked with current purpose, validity, projection and ceiling. Unknown/foreign IDs return non-enumerating error. Mutations use strict OpenAPI schemas, bounded input, CSRF/origin, expected revision and idempotency key scoped to tenant/actor/action; canonical request fingerprint binds reviewed inputs. Same key + same request returns original receipt only after current authority recheck; different request conflict. Stale revision/digest yields conflict and safe refresh, not silent override. Public capabilities are separate, opaque, high entropy, purpose-bound, expiring/revocable; store digest for lookup and minimal encrypted delivery envelope where required, fragment cleanup and no third-party referrer. GET/preview never issues credentials, publishes, approves, sends, reserves or changes business state. Use safe problem details/requestId, pagination with stable ordering and authorized filters; long jobs return 202 and receipt, not completed result. Recheck authority at job claim, artifact download, stream subscription/reconnect and consequential commit. Audit real actor/membership or scoped worker intent, purpose and outcome without plaintext sensitive data.

| Proposed operation | Input / result | Authority / effect |
| --- | --- | --- |
| GET /setup/catalog?purpose=event | allowed modes, presets, steps, dependency/readiness | active event-create/settings scope; no secret or unauthorized IDs |
| POST /setup/drafts | purpose, optional target, selected preset, intent key → draft receipt | create/edit authority; no event yet |
| PATCH /setup/drafts/{id} | typed answers, step progress, expected revision | draft owner or allowed manager, CAS |
| POST /setup/drafts/{id}/review | expected revision → digest, planned effects/exclusions | owning domain preflight; no mutation beyond review receipt |
| POST /setup/drafts/{id}/commit | review digest, intent key → event/step receipts | owning permissions, transaction and replay guard |
| GET /setup/drafts/{id}/receipt | current permitted receipt and resumable state | reauthorize before lookup; no token |
| POST /events/{id}/capabilities/review | expected rev, proposed changes, impact | event configure plus owner-specific review |
| POST /events/{id}/capabilities/apply | approved digest, expected revisions | owning commands; block unsafe disable |
| GET /events/{id}/workspace | authorized nav, ready/deferred actions and freshness | event scope; no other tenant counts |
| PUT /me/experience-preference | mode and expected revision | self only; no role changes |
| POST /organization/setup-presets/{id}/publish | reviewed typed preset revision | tenant config role; no activation/send |
| Host installer --plan / --apply | local typed plan/confirm/checkpoint | protected host operator only, not API route |

### Permission matrix

| Authority (proposed semantic permission) | Scope | Allowed / exclusions |
| --- | --- | --- |
| event.create / event.configure | organization or exact event | create and edit draft; no reservation/approval/send by implication |
| setup.preset.manage | tenant | publish suggested preset within ceilings; no event mutation |
| event.capability.manage | event | request reviewed changes; owning feature permission also required |
| venue.manage / allocation.commit | venue/event | owning space and seat rules; no bypass from quick UI |
| invitation.issue / campaign.approve / send | event/purpose | independent CID actions; template selection no send authority |
| report.read/export | dataset scope | standard and advanced same restrictions |
| platform.policy.manage | platform | allowed capability/limits, not tenant data access |
| host operator | local host | installer confirmation, not web login |
| viewer / delegated operator | exact scope | read permitted actions only; cannot acquire management from mode |

## 8. Security, privacy and reliability

Threats specific to AES: crafted hidden step bypass (server validates all mandatory owning constraints); template injection (typed allowlist, reject arbitrary route/variables); stale or duplicated create (digest + CAS + idempotency); dependency cycle (bounded DAG validation); cross-tenant draft recovery (scope-before-lookup and current membership); privileged defaults (ceilings and independent authority); false success after partial application (step receipts and explicit resume); unsafe module disable (impact and drain/revoke owning command); accidental live sends (separate CID authorization); demo contamination (isolated environment, local capture, no production credentials). Do not store contact/health data in generic wizard answers; owning editors use encrypted fields. Clear drafts/previews when tenant switches; no offline commit or silent replay. Training does not copy real people or configurations.

Never trust user-supplied tenant, role, target ID, template, route or scope. DB RLS and narrow commands protect data independently of navigation; deny direct writes and broad worker access. Use current membership/grant revocation ordering and reviewed successor ADR if changing authority. Outbox records commit with owning state, use tenant-scoped bounded consumers, lease/fence and deduplication; reconnect fetches authorized snapshot and cursor, gap triggers resync. Notification intents use CID with separately approved eligibility, content, costs and uncertainty handling; no automatic retry of ambiguous external submission. Sensitive data excluded from logs, metrics labels, URLs and public snapshots; no arbitrary JS, SQL, host shell, filesystem paths or external destinations. Review legal purpose, retention, correction, holds, redaction and portability with tenant; no claim of deletion from all backups. Tenant suspension denies new protected actions, preserves historical receipts and independent memberships. Local host recovery remains protected per PAC.

## 9. Quality, observability and deployment

Proposed simple setup benchmark: 30 synthetic attempts by representative authorized operators on a ready organization, count mandatory questions and time from opening wizard to draft receipt; report median and p95, target median ≤120 s and ≤4 required steps. Server catalog/readiness p95 ≤500 ms and draft save p95 ≤750 ms at 50 concurrent synthetic operators on agreed reference system; large readiness projections paginated. Test supported/disabled/degraded capabilities and network unknown outcome. Measure duplicate event creations = 0 under 20 concurrent identical requests; stale writes rejected; no mandatory advanced module for simple creation. Audit mode/preset/application decisions without recording free text. Installer plan dry run produces zero host mutations; repeated apply retains configuration and data.

Targets are proposed measurements on documented synthetic fixtures/hardware/network, with actual p50/p95/error rate and query plans recorded; no performance assertion before test. Both native Linux and production Docker Compose use the same build/schema/fonts/config/security contract, dedicated non-root service roles, TLS, durable storage and secret handling. External integrations optional; local capture/manual path and trusted local-network operation where server reachable. Backup DB/assets/keys and job state consistently; restore in isolation, fence potentially completed work and reconcile before enabling side effects. Browser tests Chromium/Firefox plus supported mobile/Safari/device evidence where applicable; keyboard-only, screen reader, contrast, 200% zoom and 360/768/1280/1920 widths. Operational metrics scoped by tenant and coarse counts, no PII labels; record queue age, failures and bounded diagnostics.

## 10. Implementation milestones and ownership

Do not change current Codex #104/#112 foundation closure then #105 spatial, #106 allocation, #107 admission/Cockpit, #110 collaboration, #111 communications/forms/reporting, #108 dual installers in established roadmap order. Work packages refine owning slices, not a new parallel project or immediate task switch. Minimal safe defaults can ship before advanced editors. Every slice: audit, reviewed contract/schema, domain API, role-scoped UI, negative/concurrency/upgrade/browser tests and documentation. Do not mark schema as usable workflow. Keep all existing issue criteria; do not create unrelated closure gates. Final full acceptance VM Phase 9 after feature-complete candidate.

| Milestone | Deliverables and exit evidence | Existing owner |
| --- | --- | --- |
| AES-M0 — Inventory | Audit current capability/creation/readiness commands, UX components, role semantics, default/preset policy and fixture cases; agree step/receipt design. | #104/OAC/UX |
| AES-M1 — Basic adaptive setup | Quick draft, guided navigation, safe defaults and revision/receipt semantics, real browser tests. | #104 |
| AES-M2 — Progressive capabilities | Dependency/readiness/disable review, same ID upgrade, permission-filtered shell and recovery. | #104/#107 |
| AES-M3 — Presets and specialist quick flows | EPW template reference, simple venue/seat/import/FRS/HPG quick flows as owners arrive. | #105/#106/#110/#111 |
| AES-M4 — Communications/reports | TDS/CID/RAI quick actions, review and advanced access, localized templates. | #111 |
| AES-M5 — Installer and integrated acceptance | Host plan, both modes, usability and cross-module tests, isolated training path. | #108/Phase 9 |

### Issue reconciliation proposal (after owner approval)

| Existing issue | Scope clarification only |
| --- | --- |
| [#104](https://github.com/TeraflopsBH/eventor/issues/104) | Core event quick/guided draft, optional capabilities and role-safe readiness; no new event aggregate. |
| [#105](https://github.com/TeraflopsBH/eventor/issues/105) | Basic venue and capacity path without mandatory detailed geometry. |
| [#106](https://github.com/TeraflopsBH/eventor/issues/106) | Manual allocation defaults and optional advanced solver; no bypass. |
| [#107](https://github.com/TeraflopsBH/eventor/issues/107) | Enable AGIS/EOC progressively; safe disable and privacy. |
| [#110](https://github.com/TeraflopsBH/eventor/issues/110) | Optional EPW/HPG tasks and checklist defaults. |
| [#111](https://github.com/TeraflopsBH/eventor/issues/111) | Quick TDS/CID/FRS/RAI paths using owning authorizations. |
| [#108](https://github.com/TeraflopsBH/eventor/issues/108) | Guided/advanced host installer, same security and dual modes. |
| [#112](https://github.com/TeraflopsBH/eventor/issues/112) | Provider-only booking and disruption independent of event wizard; preserve existing domain scope. |

## 11. Measurable acceptance criteria and traceability

Use isolated synthetic tenants A organizer/hybrid, B independent partner, C provider-only; distinct authorized/preparer/reviewer/revoked actors, fake guests/contacts, fixed clock with DST edge, approved synthetic venue/plan and local delivery capture. Test exact-head CI and post-merge CI; run domain command/DB, API, real browser and concurrency/fault/restore tests as indicated. Capture candidate SHA, fixture revision, role, request/receipt IDs, expected/observed counts and redacted artifacts, measured times and actual hardware/provider evidence where applicable. No mock is proof of external compatibility; optional skips not passes. A test is pass only if every required result holds; failed/blocked/N/A explicitly reasoned and authorized, no waiver of security/integrity.

| ID | Requirement | Fixture / precondition | Action | Expected measurable result | Evidence | Related acceptance / scope |
| --- | --- | --- | --- | --- | --- | --- |
| AES-AC-01 | AES-01 | Same authorized manager, same draft | Switch Quick→Advanced→Quick | Same event/draft revision and permissions; no business mutation | Browser + DB diff | UX-AC-16 |
| AES-AC-02 | AES-01 | Restricted viewer | Open advanced deep link | 403/non-enumerating; no new actions | API/browser | OAC-AC-09 |
| AES-AC-03 | AES-02 | Ready tenant, no optional capabilities | Save minimal meeting | One event draft, zero guests/holds/credentials/sends | DB/E2E | OLA-09 |
| AES-AC-04 | AES-02 | DST overlap/gap | Enter local invalid/ambiguous time | No silent incorrect instant; explicit valid choice required | Unit/API | UX-AC-10 |
| AES-AC-05 | AES-03 | Guided seating disabled | Go back/change answer/resume | Only applicable steps; valid fields retained; no optional blocker | Browser | UX-03 |
| AES-AC-06 | AES-03 | Crafted skipped required step | POST commit directly | Reject missing mandatory domain input; zero created event | API/DB | OLA-11 |
| AES-AC-07 | AES-04 | Existing simple event with roster | Enable RSVP then seating | Same event and guest IDs, reviewed revisions, history unchanged | DB/browser | ADR 0004/0005 |
| AES-AC-08 | AES-04 | Active admission passes | Attempt disable capability | Blocked or explicit authorized revoke/drain; no deletion | DB/E2E | AGIS-14/17 |
| AES-AC-09 | AES-04 | C provider-only | Create booking without guests | No event/guest requirements; valid existing booking flow | E2E | OLA-07 |
| AES-AC-10 | AES-05 | Preset from historic event | Preview/apply safe choices | No guests, credentials, approvals, reservations or delivery jobs copied | DB diff | OAC-13 |
| AES-AC-11 | AES-05 | Retired template after preview | Commit reviewed digest | Conflict; no hidden fallback | API/concurrency | TDS revision |
| AES-AC-12 | AES-06 | 20 identical create-intent requests | Concurrent commit | Exactly one event ID and receipt; differing payload conflict | DB/API race | OLA-14 |
| AES-AC-13 | AES-06 | Disconnect after commit | Resume same key | Original receipt after reauthorization, no duplicate | Fault injection | UX-10 |
| AES-AC-14 | AES-06 | Two editing clients | Save stale revision | Conflict; winning fields retained | API/browser | OAC-04 |
| AES-AC-15 | AES-07 | Tenant switch and revoked grant | Load cached/readiness/search | No prior tenant data, no unauthorized counts | Browser/API | OLA-06/11 |
| AES-AC-16 | AES-07 | Unsupported/degraded capability | Open wizard | Explicit status/reason and allowed next action, basic event usable | E2E | OAC-02 |
| AES-AC-17 | AES-08 | Simple uncalibrated room | Create basic capacity then assign | No map required for basic count; overcapacity denied | API/DB | #105/#106 |
| AES-AC-18 | AES-08 | Draft solver result | Quick publish attempt | No automatic commit; explicit human approval required | DB/API | ADR 0003 |
| AES-AC-19 | AES-09 | Ambiguous name match in import | Accept suggestions without match review | No auto-merge; review required | DB/browser | ADR 0009 |
| AES-AC-20 | AES-10 | Preset and email provider unavailable | Save draft and preview invite | Zero sends, manual/defer available | E2E | CID-11/12 |
| AES-AC-21 | AES-10 | Consent revoked after quick review | Attempt send | Suppressed/denied; no provider submission | API/worker | CID-13/14 |
| AES-AC-22 | AES-11 | Simple checklist / no hospitality | Save event | No shifts/meals/vendors mandatory; optional later enable | Browser/DB | EPW/HPG |
| AES-AC-23 | AES-12 | Basic report and restricted fields | Open standard report / advanced edit | Same field rules, no restricted values/count leakage | API/export | RAI |
| AES-AC-24 | AES-12 | Training workspace | Attempt live send or production link | Denied; only synthetic/local capture | E2E | PAC/TDS/CID |
| AES-AC-25 | AES-13 | Tenant default change | Open prior approved event and new draft | Historic revisions unchanged; new permitted default visible | DB | OAC-05 |
| AES-AC-26 | AES-14 | Existing install, both modes | Dry-run then rerun validated apply | No dry-run writes; no duplicate services/data loss, protected host | Host/VM | OLA-15 |
| AES-AC-27 | AES-15 | Ready tenant and fixed fixture | Run 30 minimal setup trials | Median ≤120 s, ≤4 required steps, p95 reported | Measured usability | UX-AC-13/14 |
| AES-AC-28 | AES-15 | Keyboard and 360px viewport bs-BA/en | Complete wizard and correct error | All essential actions usable; focus and status announced | Browser/manual | UX-AC-13/14 |
| AES-AC-29 | AES-03, AES-06, AES-07 | Revocation during reviewed setup | Commit or fetch receipt | Denied, no foreign data; scope check before ID lookup | API/DB race | OLA-11 |
| AES-AC-30 | AES-04, AES-05, AES-10 | Preset suggests unavailable messaging and seating | Review then apply | Only permitted ready choices applied; no send or automatic booking | E2E | OLA-03/09 |

### Requirement-to-acceptance traceability

| Requirement | Acceptance suffixes | Owning topic |
| --- | --- | --- |
| AES-01 | 01, 02 | Setup modes and preference |
| AES-02 | 03, 04 | Minimal event creation |
| AES-03 | 05, 06, 29 | Guided step orchestration |
| AES-04 | 07, 08, 09, 30 | Progressive capability configuration |
| AES-05 | 10, 11, 30 | Presets and safe template application |
| AES-06 | 12, 13, 14, 29 | Draft resilience and review digest |
| AES-07 | 15, 16, 29 | Contextual navigation and readiness |
| AES-08 | 17, 18 | Quick venue and allocation path |
| AES-09 | 19 | Quick guest and registration path |
| AES-10 | 20, 21, 30 | Quick invitation and communication path |
| AES-11 | 22 | Quick production and hospitality path |
| AES-12 | 23, 24 | Quick reports and training |
| AES-13 | 25 | Setup defaults and administrative policy |
| AES-14 | 26 | Installer and recovery experience |
| AES-15 | 27, 28 | Adaptive quality and accessibility |

### Release integration

Add the above evidence to applicable OLA scenarios and G1–G9 gates without replacing existing OLA/PAC/OAC/UX/TDS/AGIS/CID criteria. G1 CI, G2 independent organization, G3 isolation, G4 configuration/content/output, G5 cross-domain journey, G6 resilience/accessibility, G7 deployment/recovery, G8 external evidence when applicable, G9 traceability/release defects. Provider-only, simple organizer and complex hybrid journeys remain independently usable. Actual supported devices, deployment and external provider acceptance only in planned Phase 9; automated tests incrementally in owning slices.

## 12. Open decisions and proposed integration

Resolve mandatory minimum fields against current event command and whether unscheduled draft is supported; default preset and capabilities, dependency graph ownership, draft sharing/expiry, step persistence and transactional core boundary, supported external/online location representation, live capability disable authority, view preference precedence, usability sample and host installer prompts. Do not choose actual event presets, capacities or legal/approval rules on behalf of organization. Training and enterprise identity remain future coordinated improvements; this document requires safe synthetic preview and isolated training path, not a new production data clone service.

Before implementation, owner/tenant validates real capacities, legal/retention policies, staffing, commercial rules, programme, identity and accessibility needs; no fictional examples become GHB configuration. Engineering reviews candidate libraries, licensing, exact route/schema/role choices, security threat review and performance envelope when scheduled. Do not modify accepted ADRs except through reviewed successor. Once owner approves, integrate complete source verbatim at stated destination, record approval and original SHA-256/blob externally in [design index](README.md). Add dated additive cross-references in architecture, roadmap, gap analysis, relevant approved designs and mapped existing issues, retain historic source checksum references and all existing issue requirements. Verify complete docs-only Git tree diff, source read-back, link resolution, required exact-head CI and post-merge CI; no runtime code, migrations, OpenAPI, workflows, Blueprint v1.2, PROJECT_STATE, Codex branches, environment or early VM change. Future consolidated Blueprint v1.3 separately approved; no requirement silently dropped.
