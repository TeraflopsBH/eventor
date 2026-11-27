# Eventor Event Planning, Production and Operational Workflows (EPW)
## Technical specification v1.0

**Status:** Proposed for product-owner approval; no integration or implementation authorized by this draft.  
**Date:** 2026-11-27. **Read-only repository baseline:** `e0fa44203f785284d597f69dae8510c91bada0d6` (main, CID PR #236). All five required CI checks on this baseline were observed completed successfully during preparation. CI is not product acceptance.  
**Proposed destination:** `docs/implementation-design/v0.3/EVENT_PLANNING_PRODUCTION_AND_OPERATIONAL_WORKFLOWS_DESIGN_v1.0.md`. Links are relative to that future location. The five proposed documents are companion drafts, not yet repository files.  
**Document control:** EPW-01–16, EPW-M0–M6, EPW-AC-01–33. MUST denotes proposed product requirement, SHOULD preferred approach with justified exceptions, MAY optional. Endpoint names, entity names, permission codes and numerical envelopes are design proposals, not existing runtime contracts or certified targets. No acceptance tests executed.

## 1. Objective and boundaries

Provide a planning-to-handover workspace for simple checklists through complex production schedules. Event managers coordinate tasks, milestones, run-of-show, staffing, equipment, approvals, ordinary operational issues, recurring events and reusable templates. Keep the event/session/schedule, booking reservations, collaboration grants, external prerequisites, published allocation and business approvals canonical in their existing domains. EPW composes plans and issues explicitly authorized commands; it cannot itself confirm a booking, move guests, cancel an event, declare an external authority has completed an inspection or authorize an expenditure. This is not a general-purpose project-management or emergency response platform, personnel surveillance or payroll system. Financial planning means estimates and references to approved commercial facts; full accounting, enterprise identity and external integration remain future work.

## 2. Existing foundation and reconciliation

Blueprint §§5, 7, 10, 14–16, 25, 35–37 provides lifecycle, venue resources, dynamic changes, cockpit, assigned responsibility and a lightweight incident board. OAC-11/12/13/17 describe resource/service catalog, calendar, safe event duplication and collaboration. Migration 000008 defines event/session/schedule/capabilities; 000006 reserves spaces/resources; 000023 provides get_assigned_task_projection/update_assigned_task_status and collaboration constraints; 000108 hardens delegated authorization; 000014 contains operational alerts and allocation foundations. Current implementation provides organizer event/session and booking/partner slices, not a complete production workspace. #110 explicitly owns staff/vendor workspaces, task deadlines, evidence and external prerequisite coordination; #112 owns disruption lifecycle. Reuse and audit canonical tasks and resource reservations, not new competing aggregates.

Use [Blueprint v1.2](../../blueprint/v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md), [architecture](../../ARCHITECTURE.md), [roadmap](../../ROADMAP.md), [project state](../../PROJECT_STATE.md), [gap analysis](../../BLUEPRINT_TO_REPOSITORY_GAP_ANALYSIS_v1.0.md), [operating model](../../OPERATING_MODEL.md), and [roles](../../product/USER_ROLES_AND_PERMISSIONS_v0.1.md). Read [RSVP design](RSVP_AND_INVITATION_DESIGN_v0.3.md), [collaboration design](CROSS_ORGANIZATION_COLLABORATION_DESIGN_v0.3.md) and [disruption design](CANCELLATION_AND_EVENT_DISRUPTION_DESIGN_v0.3.md) for owning commands. Existing accepted decisions prevail until reviewed successor: [modular monolith](../../decisions/0001-modular-monolith.md), [self-hosting](../../decisions/0002-self-hosted-deployment.md), [human-approved allocation](../../decisions/0003-human-approved-allocation.md), [optional scope](../../decisions/0004-optional-event-operations-scope.md), [invitation separation](../../decisions/0005-separate-invitations-rsvp-attendance.md), [collaboration](../../decisions/0006-cross-organization-collaboration.md), [localization](../../decisions/0007-internationalization.md), [incremental staff UI](../../decisions/0008-modular-staff-frontend.md), [membership protection](../../decisions/0010-organization-membership-access.md), [login/workspaces](../../decisions/0015-email-first-login-and-platform-administration.md), [scoped grants](../../decisions/0023-permissioned-collaboration-grant-lifecycle.md), [reviewed grant acceptance](../../decisions/0024-shared-party-names-and-reviewed-grant-acceptance.md).

| Approved addendum | Reconciliation rule |
| --- | --- |
| [TDS](TEMPLATE_DESIGN_STUDIO_DESIGN_v1.0.md) | Versioned run sheet, briefing pack, task sheets and handover PDF use shared renderer and approved content; no print implies approval. |
| [PAC](PLATFORM_ADMINISTRATION_CENTER_DESIGN_v1.0.md) | Support, platform policy ceilings and jobs/recovery; no unscoped production interventions. |
| [OAC](ORGANIZATION_ADMINISTRATION_CENTER_DESIGN_v1.0.md) | Portfolio/calendar, owned resources, reusable templates/policy and tenant team management; EOC consumes event projections. |
| [UX](EVENTOR_USER_EXPERIENCE_AND_NAVIGATION_v1.0.md) | Consistent task list, calendar, timeline and accessible alternatives to drag; same status taxonomy and role-filtered navigation. |
| [OLA](ORGANIZATION_LIFECYCLE_ACCEPTANCE_SCENARIOS_v1.0.md) | Extend OLA-03/07–10/14/15 for planning, staffing, readiness, disruption and safe recurrence. |
| [AGIS](ADMISSION_GUEST_INFORMATION_AND_STATION_MANAGEMENT_DESIGN_v1.0.md) | Run-of-show and readiness feed EOC stations; no change to admission/attendance or guest-safe maps from task completion. |
| [CID](COMMUNICATION_INVITATION_DISTRIBUTION_AND_MULTI_CHANNEL_DELIVERY_DESIGN_v1.0.md) | Reminder, task and approved change notifications use domain intent, verified audience/consent, delivery evidence; read ≠ acknowledgement. |

### Companion proposals (not yet approved)

| Companion | Interface and boundary |
| --- | --- |
| [AES](ADAPTIVE_EXPERIENCE_AND_SETUP_DESIGN_v1.0.md) | Owns Quick Start experience and safe application flow; EPW owns template content, dependency checks and recurrence plan. |
| [FRS](FORMS_REGISTRATION_AND_SUBMISSION_STUDIO_DESIGN_v1.0.md) | Intake forms and evidence submissions feed assigned task reviews; no form approves a task automatically. |
| [HPG](HOSPITALITY_PROTOCOL_AND_GUEST_SERVICES_DESIGN_v1.0.md) | Service demand and hospitality tasks reference EPW time windows and responsibilities; HPG owns restricted needs. |
| [RAI](REPORTING_ANALYTICS_AND_INTELLIGENCE_STUDIO_DESIGN_v1.0.md) | Approved planning/actual metrics, due/overdue, readiness and resource utilization through scoped datasets; no duplicate analytics truth. |

## 3. Adaptive experience and user journeys

Simple event: choose a small checklist (prepare room, invite participants, confirm room ready, close), assign yourself or approved staff, due dates optional only where policy allows. No Gantt, shifts, suppliers or approvals beyond mandatory domain requirements. Guided event: choose template, add event milestones, schedule, resources and dependencies, review readiness. Advanced event: calendar, Gantt/list, resource conflicts, parallel approval routes, private issue board, programme run sheet and actual timeline. In OAC portfolio show authorized events, due work and planned availability; in EOC show current cue, upcoming cues, blocked tasks, readiness and approved change receipts. Vendor/staff landing only assigned tasks and permitted evidence. Provide print-friendly day plan and keyboard move/reorder controls; in timeline distinguish planned vs actual, baseline vs working revision, dependent delays and tentative suggestions. Time is absolute with locale and zone. No automatic action on a cue or scheduled deadline.

Synthetic example: reception with setup 14:00–16:00, rehearsal 16:00–16:30, staff briefing 17:00, reception 17:30, programme 18:00, teardown 20:00. The event begins only via existing start command. A projector outage creates an ordinary equipment issue and proposed task/resource adjustment; staff see relevant instructions, not restricted cause details. A venue conflict creates a booking change request, not automatic cancellation. A small meeting uses the same checklist without these optional elements.

All modes are projections over the same canonical records and commands. Quick Start is not a permission class, price tier, alternate storage model or waiver of domain rules. Guided mode adds relevant questions; Advanced exposes authorized settings and diagnostics. Mode changes do not themselves mutate domain facts, publish, send, reserve, approve or grant authority. Defer optional setup; distinguish not applicable, not enabled, not configured, blocked and ready. A user can resume a draft and switch modes without losing valid work. Show reasons and a permitted next action, not inaccessible target IDs. Use bs-BA/en, IANA timezone, locale-aware number/date display and immutable authored translations; no silent translation of legal or guest-facing meaning. All visual interactions have keyboard/non-drag equivalents. User preference, organization default, and event capability are separate.

## 4. Functional requirements

### EPW-01 — Planning views and ownership

MUST provide scoped workspaces for organization portfolio, event plan, session plan, and assigned task. Use canonical event/session IDs; plan revisions pin schedule, venue/booking refs and task policy. Distinguish organizer tasks from venue-provider fulfillment and contracted task ownership. Simple checklist is same task model projected without timeline columns. Support draft, reviewed, published and superseded revisions; routine task status may change as operational facts without rewriting plan baseline.

### EPW-02 — Milestones and task structure

Support milestones, work packages, tasks, subtasks and checklist items with stable identity, localized label, owner, responsible party, due/start/end windows, priority, status, dependencies and permitted evidence. Separate plan revision from actual progress; support zero-duration milestones. Reuse delegated-task/responsibility primitives and actor binding. Never infer actual completion from elapsed time. Add or retire task via revisioned command; preserve historical assignments and completion records.

### EPW-03 — Dependency graph and critical path

Typed finish-start and optional start-start/finish-finish links with signed lag bounded by policy, no unbounded recursive chains. Validate same permitted planning context, cycles, missing targets and temporal constraints. Compute earliest/latest feasible times and slack with stated calendar/time assumptions; flag unresolved tasks without invented durations. Suggested ripple changes are advisory with before/after and affected dependencies; explicit review commits plan revisions. Critical path is planning aid, not a safety guarantee or reservation authority.

### EPW-04 — Run-of-show and programme

Create versioned internal production cues mapped where applicable to public programme sessions; cues include planned time/duration, owner, dependency and approved non-sensitive instruction. Support rehearsal, briefing, transition, break, technical setup and teardown. Maintain actual started/completed/skipped/held timestamps and attributable reason independent of published schedule. Public programme gets only approved guest-safe projection, not internal technical/private notes. Clock drift/degraded sync displayed; no automatic cue execution or start/close event.

### EPW-05 — Staff roster and shift coordination

Assign eligible staff, contracted roles or approved responsible party to tasks and shift windows; indicate coverage gaps and overlaps, breaks/availability and handover. Use active membership/grant and event/task-specific ceiling, not personal job title alone. No automatic role grant on assignment. Schedule estimates are not payroll/timekeeping; record actual handover/acknowledgement as distinct facts. Reassignment/absence updates current plan with review and preserves original responsibility. External workers see only accepted assigned scope.

### EPW-06 — Resources, equipment and services

Link tasks and cues to owned facility, equipment, quantity, service catalog and setup/teardown buffers. Use existing reservation/availability authority and atomic conflict checks for any hold/confirmation; task estimate/assignment never creates confirmed booking. Support consumable estimates and service readiness distinct from stock/financial facts; out-of-service or maintenance blocks new use via owning resource command. Compare proposed alternatives; no double reservation or unauthorized resource ownership transfer.

### EPW-07 — Readiness, checklists and external prerequisites

Reuse OAC readiness and EOC alerts. Define typed checklists with required/optional applicability, assigned verifier, due time, evidence requirement and dependencies. Record verification, rejection, expiry and authorized correction; status is not legal certification. External prerequisite/CDI coordination uses existing requirement/request/schedule/completion references and authorized coordinator, no police procedure/findings, inspections or tactical operations. External authority acts independently; record only approved minimal status. Block owning action only if existing configured rule requires; display missing items/reasons and safe actions.

### EPW-08 — Constrained approval policy designer

Permit graphical configuration of allowlisted approval templates for domain actions (booking commercial review, event publication, plan publication, campaign, ordinary production change). Typed conditions over approved domain facts, thresholds and sequential/parallel stages, quorum and explicit separation-of-duty policy. Versioned policy, role/purpose eligibility, delegation ceiling and mandatory owner constraints. No arbitrary script, SQL, new domain state or generic automatic execution. Existing booking/cancellation approval commands remain authoritative; designer cannot weaken mandatory review. Preview synthetic evaluation and show resolved approvers without unauthorized disclosure.

### EPW-09 — Approval instances and escalation

Bind exact reviewed subject, expected revision/digest, policy version, actor scope and evidence; review decision append-only with reason, timestamp and actual actor. Distinguish submitted, under review, returned, approved, rejected, expired, superseded and executed. Parallel quorum respects distinct eligible actors and any separation of duty; revoked actor cannot create new decision. Stale subject invalidates pending execution, re-review required. Escalation/reminder routes to permitted substitute/role only, never auto-approval or silent bypass; expiry blocks execution. Execute through owning domain command once with current authority.

### EPW-10 — Operational issue board and change control

Lightweight ordinary issue record with severity, affected approved scope, owner, status, safe summary, restricted reason where required, action links, decision and resolution receipt. Triage → assign → propose → review → resolve/close; reopened via new attributed event. No safety/emergency command system or private police findings. Link to #112 disruption, #106 reallocation or resource change through owning command; no hidden mutation from issue status. Provide impact preview (tasks/cues/resources/approved plans, messages), protected detail projections, and clear before/after baseline.

### EPW-11 — Event templates and safe cloning

Create tenant-owned versioned templates of safe configuration: event type, relative sessions/durations, optional capability suggestions, category definitions (not membership), generic allocation rules, approved template/form/station profile references, task/checklist structures, resource requirements, relative due offsets, role presets and hospitality defaults. Explicit copy allowlist and exclusion report. No people, actual staffing, restricted notes, consents, live credentials, old approval, attendance, job, confirmed reservation or evidence copied. Review against current tenant policy, availability, retired dependencies; new draft independent, pin template source revision. AES supplies preview/apply UX.

### EPW-12 — Recurring events and booking series

Support finite reviewed series of draft occurrences with timezone-aware recurrence rule, end/count cap (proposed default max 100), exclusions and explicit edits to individual/future draft occurrences. Preview DST and local-time conflicts, unique series+occurrence key, allow partial explicit selection. Each occurrence independent event identity, schedule, approvals, booking and participation; no automatic reservations/sends or future unlimited jobs. Recurring booking uses existing booking domain with per-occurrence review; provider-only independent. Changes never rewrite past/live/approved occurrence; cancellation requires owning commands. No silent cascade.

### EPW-13 — Handover and post-event review

Provide versioned approved production plan, actual timeline, outstanding tasks, resource return/status, incident resolution and handover checklist. Closing event uses existing event lifecycle and configured readiness, not a task board shortcut; preserve open obligations and explicit assignment where allowed. Record retrospective findings/action items as scoped ordinary operational records, not employee surveillance. Export approved briefing/handback pack with TDS pinned revision and authorized fields; historical plan/actual comparison remains reproducible within retention.

### EPW-14 — Live coordination and communication

Publish scoped outbox changes after task/plan/actual commit; EOC receives current readiness, cues, ownership and exceptions, no private detail in public displays. Assigned party receives approved CID notification/reminder intent when policy requires; external read/delivery is not accepted task or completion. Reconnect fetch current revision, cursor and gaps; stale view warning. No new unsafely queued offline task approval; limited local draft notes only if separate reviewed policy, not authoritative completion.

### EPW-15 — Cross-party delegation and data boundaries

Use existing accepted scoped collaboration grant revision, explicit task responsibility and least-privilege projection. Venue provider owns booking/resource facts, organizer owns event/guest facts; vendor receives only assigned work and necessary fields, not registry or commercial data. Revocation/expiry stops writes, streams, exports and future protected notifications while preserving attribution/history. Changing party name does not rewrite historical accepted task context. Support role reassignment with explicit owner decision, not arbitrary external lookup.

### EPW-16 — Planning quality and adaptive UX

Quick checklist, guided template and advanced timeline share same tasks and constraints; switch without losing work. Accessible list/table alternatives for Gantt, calendar and approval flow; keyboard reorder with revision check, no drag-only function. Localized time and status, timezone/DST, visual/text indicators, synthetic test preview. Record planning metrics, due job age and readiness freshness with no private content/employee profiling. Measure proposed scale and reliability; do not require advanced schedule for small event.

## 5. Workflow, transaction and failure semantics

### Lifecycle and locking

Plan `draft → reviewed → approved → published → superseded`; approval and publication separate where configured; existing owning event lifecycle not replaced. Task planned state `draft/assigned/accepted/in_progress/blocked/completed/cancelled` mapped to current canonical statuses at M0; actual progress append-only, corrections reference original event. Plan update locks event/plan head in established order, validates scope, expected revision, dependency graph, approved subject refs and affected booking/plan changes. Resource availability preview is advisory; hold/confirm via existing transaction. No DB transaction remains open during computation/render/network calls. A worker may calculate advisory schedule against pinned inputs; output has input digest, algorithm version and conflicts; stale result cannot commit.

Approval route policy revision → evaluated instance → independent decisions → approved receipt → explicit owning execute. On stale subject/policy requiring new review, mark superseded rather than delete decisions. Quorum check and execute serialize with domain state; concurrent requests yield one execution receipt. Cancellation, payment, grant acceptance and event start remain separate domain commands.

Series preview normalizes bounded occurrences in IANA zone, includes conflicts/ambiguity and no holds; confirmation uses intent key and occurrence unique constraint. If a selected occurrence cannot be created, show explicit per-occurrence failure or all-or-nothing for declared atomic batch; no duplicate rerun. Existing occurrences unaffected by editing series. For handover, record assigned outgoing/incoming actor and accepted evidence; unresolved obligation remains visible.

| Failure | Expected response |
|---|---|
| Dependency cycle | Reject draft change, return safe cycle path within scope |
| Delayed cue | Suggest affected time diff, no auto booking or programme publication |
| Staff loses role | Remove new authority and prompt authorized reassignment; retain history |
| Resource unavailable | Show conflict, no phantom reservation |
| Approval expires | Block execution, route renewed review |
| Vendor upload fails | Task remains pending evidence; no completion |
| Lost response after execution | Receipt lookup, no repeat action |
| External notice received | Record/ack separately; owning #112 decision remains required |
## 6. Architecture and logical data model

Extend the existing Vue 3/TypeScript staff application, Fastify API/workers and PostgreSQL 18.6 modular monolith; no mandatory external SaaS or second database. Reuse domain commands, approved TDS renders, CID delivery, transactional outbox and scoped projections. Logical names below are candidates; inventory actual schema, role grants, lock order, indexes, views, current APIs and fixtures at M0. Add only missing extensions with forward migrations; no rewriting historical migrations, accepted ADRs or the v0.2 schema/OpenAPI snapshots. All tenant-owned keys include organization context; event references include event scope, verified by composite FK or equivalent command integrity. Cross-party references use explicit accepted grant/revision and permitted projection, never broad joins. Immutable published revisions, decisions, receipts and evidence retain source IDs; append correction/supersession rather than destructive rewrite. Sensitive values and private artifacts use authenticated encryption and purpose-bound identity; no secret in audit or general projections.

| Logical entity or existing aggregate | Principal fields / keys | Integrity and lifecycle |
| --- | --- | --- |
| events/event_sessions/schedule revisions | existing event scope and schedule head | Canonical lifecycle |
| responsibility/delegated task aggregates | existing owner/grantee/task, assigned actor, state | Reuse; no parallel task truth |
| production_plan/revision | event, version, source schedule/venue/template refs, status, digest | Immutable published, one current head |
| plan_item / item revision | stable task/cue/milestone key, parent, planned times, owner ref, duration | Acyclic parent and revision; task actual separate |
| plan_dependency | plan revision, from/to item, kind, lag | Unique, same revision, cycle/size check |
| task_progress / handover evidence | canonical task ID, actor, action, timestamp, restricted evidence ref | Append-only corrections, scope checked |
| shift_assignment | event, membership/grant, role/task, interval, planned coverage | Active scope, overlap policy; no grant automatically |
| resource_requirement | plan item, resource/service reference, quantity, window, reservation ref nullable | Requirement ≠ hold; FK to owning authority |
| readiness_check/revision/result | purpose, item, requirement, due, owner, verified actor, evidence | Pinned rule, explicit result/expiry; reuse prerequisite status |
| approval_policy/revision/instance | domain action key, typed conditions/stages, subject revision/digest, instance state | Compatible with existing domain policies; no generic bypass |
| approval_decision/execution_receipt | instance, stage, eligible actor, decision, reason, owning receipt | Distinct voters; immutable, at most one execution |
| operational_issue/history | event, scope, safe summary, restricted ref, owner, state, action links | Append-only status/correction; no sensitive public fields |
| event_template/revision | org, version, locale, safe configuration manifest, refs | Allowlist; immutable reviewed revision |
| event_series/occurrence | org, rule, zone, range/cap, revision, occurrence key, event/booking ref | Unique occurrence; bounded creation, no implicit reservation |
| production_review/retrospective | plan revision, actual summary, unresolved item refs, action owner | Scoped, immutable receipt, retention policy |

### Migration and compatibility

Audit existing tables and commands first; additive sidecar only where needed. Backfill through reviewed deterministic mapping with exception report, preserve existing IDs, historical snapshots and access semantics; default newly introduced capabilities to disabled/unconfigured unless existing equivalent facts justify activation. Test fresh install and populated upgrades, RLS and grants with runtime/auth/worker roles; old clients retain supported route behavior. No destructive down migration for recorded facts; recovery through tested compatible release or controlled restore and reconciliation. Add indexes for tenant/event/status/revision and due work; measure plans on synthetic representative cardinality; do not rely on client-side filtering.

## 7. API and permission contracts

Paths are relative to the existing API version; exact prefix, schema, codes and permissions determined after M0 inventory. Every staff route authenticates active user, selected membership, tenant, domain permission and object scope before lookup; delegated grants checked with current purpose, validity, projection and ceiling. Unknown/foreign IDs return non-enumerating error. Mutations use strict OpenAPI schemas, bounded input, CSRF/origin, expected revision and idempotency key scoped to tenant/actor/action; canonical request fingerprint binds reviewed inputs. Same key + same request returns original receipt only after current authority recheck; different request conflict. Stale revision/digest yields conflict and safe refresh, not silent override. Public capabilities are separate, opaque, high entropy, purpose-bound, expiring/revocable; store digest for lookup and minimal encrypted delivery envelope where required, fragment cleanup and no third-party referrer. GET/preview never issues credentials, publishes, approves, sends, reserves or changes business state. Use safe problem details/requestId, pagination with stable ordering and authorized filters; long jobs return 202 and receipt, not completed result. Recheck authority at job claim, artifact download, stream subscription/reconnect and consequential commit. Audit real actor/membership or scoped worker intent, purpose and outcome without plaintext sensitive data.

| Proposed operation | Input / result | Authority / effect |
| --- | --- | --- |
| GET /events/{id}/production | current allowed plan, checklist/timeline, freshness | event read; filtered items |
| POST /events/{id}/production/revisions | base rev, typed item/dependency changes | plan edit, CAS; draft only |
| POST /events/{id}/production/review | revision/diff → digest, conflicts | plan review, no publish |
| POST /events/{id}/production/publish | reviewed digest, approved receipt | owning publish authority, immutable new head |
| POST /tasks/{id}/transition | expected revision, transition, evidence/ref | existing task command, actor scope |
| POST /events/{id}/shifts/review\|apply | intervals, assignments, digest | staff assign, current active role |
| POST /events/{id}/resource-requirements/review | quantity/window, alternatives | read availability; no hold |
| POST /events/{id}/cues/{cue}/actual | start/hold/complete/correct, rev | cue operator, no event lifecycle change |
| POST /events/{id}/readiness/{check}/verify | revision, result, evidence | assigned verifier/owner; no external certification |
| POST /approval-policies/{id}/publish | typed reviewed policy, expected rev | domain policy admin; constraints |
| POST /approval-instances/{id}/decisions | stage, exact digest, reason | eligible distinct approver |
| POST /approval-instances/{id}/execute | review receipt/idempotency | owning domain execution authority |
| POST /events/{id}/issues/{issue}/transition | expected state, link/evidence, safe reason | scoped issue actor; no implicit domain mutation |
| POST /event-templates/{id}/publish | allowlisted config manifest/digest | tenant template manager |
| POST /event-series/preview\|commit | bounded rule, zone, choices, review digest | event/booking create authority per occurrence |
| POST /events/{id}/handover | reviewed plan/actual refs, unresolved tasks | responsible actor, immutable receipt |

### Permission matrix

| Authority (proposed semantic permission) | Scope | Allowed / exclusions |
| --- | --- | --- |
| production.read/edit/publish | exact event | read, draft, publish separately; no booking or event start implied |
| task.assign / assigned task update | event/task grant | owner allocates responsibility; assignee only own allowed transitions |
| shift.manage | event | schedule eligible staff, no role grants or payroll |
| resource.manage/reserve | venue/booking | owning authority only; planning read not reserve |
| readiness.verify | assigned check | minimal evidence, no external authority impersonation |
| approval.policy.manage | domain/tenant | configure constrained policy, no self-elevation |
| approval.decide / domain.execute | subject/action scope | separate eligible review and command permissions |
| issue.read/manage/restricted | event/area | safe issue projection; restricted reason separate |
| event.template.manage / series.create | tenant/event | safe config or bounded new drafts only |
| handover.review / report.export | event/scope | approved summary and private export; no broader data access |

## 8. Security, privacy and reliability

Specific threats: dependency explosion (bounded graph, timeout, no recursion on client trust), forged schedule/approval (digest, server evaluation, current authority), hidden self-approval (distinct actors/quorum and mandatory owner rules), resource race (owning reservation command and lock), recurring mass creation abuse (bounded count, quotas and idempotent unique occurrences), cloned PII (strict configuration allowlist, explicit exclusions, synthetic fixtures), task delegation escalation (grant + purpose + owner before lookup), restricted incident leakage (safe summary separate), incorrect readiness (explicit verification/source/time), clock/timezone shifts (absolute instants and reviewed recurrence). Protect evidence attachments via FRS private scanning/review; no raw secrets in plan/export. No automation executes arbitrary actions on schedule or triggers; approved reminders only. No operational security instructions, surveillance or external inspection data.

Never trust user-supplied tenant, role, target ID, template, route or scope. DB RLS and narrow commands protect data independently of navigation; deny direct writes and broad worker access. Use current membership/grant revocation ordering and reviewed successor ADR if changing authority. Outbox records commit with owning state, use tenant-scoped bounded consumers, lease/fence and deduplication; reconnect fetches authorized snapshot and cursor, gap triggers resync. Notification intents use CID with separately approved eligibility, content, costs and uncertainty handling; no automatic retry of ambiguous external submission. Sensitive data excluded from logs, metrics labels, URLs and public snapshots; no arbitrary JS, SQL, host shell, filesystem paths or external destinations. Review legal purpose, retention, correction, holds, redaction and portability with tenant; no claim of deletion from all backups. Tenant suspension denies new protected actions, preserves historical receipts and independent memberships. Local host recovery remains protected per PAC.

## 9. Quality, observability and deployment

Proposed planning fixture: 500 tasks, 1,000 dependency edges, 100 cues, 30 concurrent staff, two independent partner organizations and 100 bounded draft occurrences. Graph preview p95 ≤2 s, assigned task list p95 ≤750 ms and local committed update visible to connected authorized EOC p95 ≤2 s, record hardware/load. Detect cycles and return bounded diagnostic; no indefinite worker runs. Concurrent 20 identical approval execute/series commit produces at most one logical receipt/occurrence. Track overdue items by defined calendar, unresolved conflicts and readiness age, not worker performance ranking. Plan export pinned TDS revision; verify generated digest and private download expiry. Rehearse restore with pending reminders and external ambiguity before enable.

Targets are proposed measurements on documented synthetic fixtures/hardware/network, with actual p50/p95/error rate and query plans recorded; no performance assertion before test. Both native Linux and production Docker Compose use the same build/schema/fonts/config/security contract, dedicated non-root service roles, TLS, durable storage and secret handling. External integrations optional; local capture/manual path and trusted local-network operation where server reachable. Backup DB/assets/keys and job state consistently; restore in isolation, fence potentially completed work and reconcile before enabling side effects. Browser tests Chromium/Firefox plus supported mobile/Safari/device evidence where applicable; keyboard-only, screen reader, contrast, 200% zoom and 360/768/1280/1920 widths. Operational metrics scoped by tenant and coarse counts, no PII labels; record queue age, failures and bounded diagnostics.

## 10. Implementation milestones and ownership

Do not change current Codex #104/#112 foundation closure then #105 spatial, #106 allocation, #107 admission/Cockpit, #110 collaboration, #111 communications/forms/reporting, #108 dual installers in established roadmap order. Work packages refine owning slices, not a new parallel project or immediate task switch. Minimal safe defaults can ship before advanced editors. Every slice: audit, reviewed contract/schema, domain API, role-scoped UI, negative/concurrency/upgrade/browser tests and documentation. Do not mark schema as usable workflow. Keep all existing issue criteria; do not create unrelated closure gates. Final full acceptance VM Phase 9 after feature-complete candidate.

| Milestone | Deliverables and exit evidence | Existing owner |
| --- | --- | --- |
| EPW-M0 — Inventory and decisions | Audit canonical responsibility/task, approval, resource and schedule primitives; define graph/lock, scope and template allowlists. | #110/#104/#112 |
| EPW-M1 — Basic checklist and responsibilities | Simple event checklist, task assignment/ack/status/evidence, scoped work list and history. | #110 |
| EPW-M2 — Timeline and production | Plan revision, milestones/dependencies, cue list/actuals, shift and resource previews. | #105/#110/#107 |
| EPW-M3 — Readiness and issue board | Configured checklists, existing prerequisite coordination, issue/change links, scoped live projections. | #110/#107/#112 |
| EPW-M4 — Constrained approvals | Reuse existing policy and commands, reviewed rule editor, quorum/revision and execution fencing. | #104/#112/#110/#111 |
| EPW-M5 — Templates and series | Safe reusable configuration, bounded recurrence and AES review, no copy of actual records. | #104/#110 |
| EPW-M6 — Outputs and integrated acceptance | TDS packs, CID reminders, RAI metrics, dual installer and fault tests. | #111/#108/Phase 9 |

### Issue reconciliation proposal (after owner approval)

| Existing issue | Scope clarification only |
| --- | --- |
| [#104](https://github.com/TeraflopsBH/eventor/issues/104) | Event template/series and safe draft creation, settings; no prerequisite to finish current Registry. |
| [#105](https://github.com/TeraflopsBH/eventor/issues/105) | Owned resource/space availability and setup/teardown windows; no new spatial engine. |
| [#106](https://github.com/TeraflopsBH/eventor/issues/106) | Approved allocation-change links only, not solver/seat ownership. |
| [#107](https://github.com/TeraflopsBH/eventor/issues/107) | EOC production/readiness/issue projection and public approved programme. |
| [#110](https://github.com/TeraflopsBH/eventor/issues/110) | Primary task, dependencies, staff/vendor, external prerequisites, production and issue board. |
| [#111](https://github.com/TeraflopsBH/eventor/issues/111) | Shared TDS outputs, CID task notifications and RAI reporting; optional constrained campaign approvals. |
| [#112](https://github.com/TeraflopsBH/eventor/issues/112) | Keep booking and event disruption/approval commands independent; link reviewed requests. |
| [#108](https://github.com/TeraflopsBH/eventor/issues/108) | Persist/recover scheduled jobs and both modes; final acceptance. |

## 11. Measurable acceptance criteria and traceability

Use isolated synthetic tenants A organizer/hybrid, B independent partner, C provider-only; distinct authorized/preparer/reviewer/revoked actors, fake guests/contacts, fixed clock with DST edge, approved synthetic venue/plan and local delivery capture. Test exact-head CI and post-merge CI; run domain command/DB, API, real browser and concurrency/fault/restore tests as indicated. Capture candidate SHA, fixture revision, role, request/receipt IDs, expected/observed counts and redacted artifacts, measured times and actual hardware/provider evidence where applicable. No mock is proof of external compatibility; optional skips not passes. A test is pass only if every required result holds; failed/blocked/N/A explicitly reasoned and authorized, no waiver of security/integrity.

| ID | Requirement | Fixture / precondition | Action | Expected measurable result | Evidence | Related acceptance / scope |
| --- | --- | --- | --- | --- | --- | --- |
| EPW-AC-01 | EPW-01 | Simple draft and advanced plan | Switch checklist/timeline | Same task IDs and facts, no permission increase | Browser/DB | AES/UX |
| EPW-AC-02 | EPW-01 | Approved published plan | Edit working draft | Published source unchanged, new revision only | DB | Blueprint §10 |
| EPW-AC-03 | EPW-02 | Assigned task and milestone | Complete task with due time elapsed | Only explicit authorized action changes status | API/DB | #110 |
| EPW-AC-04 | EPW-02 | Correction to completed task | Correct via owning command | Original actor/event retained; new attributed history | DB | OLA-10 |
| EPW-AC-05 | EPW-03 | A→B→C dependencies | Add C→A | Reject cycle, no persisted invalid edge | Unit/DB | OLA-14 |
| EPW-AC-06 | EPW-03 | Pinned schedule and delayed task | Calculate critical path and suggested ripple | Expected slack/conflicts; zero booking or event changes | Unit/API | #105 |
| EPW-AC-07 | EPW-04 | Internal cue with private note | Publish public programme projection | Only approved guest-safe fields, no private note | API/browser | AGIS-11 |
| EPW-AC-08 | EPW-04 | Cue due at current time | Wait then record actual | No automatic event start; explicit cue receipt only | DB/E2E | OLA-09 |
| EPW-AC-09 | EPW-05 | Revoked staff membership | Assign shift/accept handover | Denied, historical assignment retained | API/DB race | OAC/ADR 0010 |
| EPW-AC-10 | EPW-05 | Overlapping shifts | Preview and apply per policy | Conflict shown, mandatory coverage rule enforced | API/browser | #110 |
| EPW-AC-11 | EPW-06 | One resource and two requests | Concurrent confirm via booking command | At most allowed capacity; requirement itself creates zero holds | DB race | #105/#112 |
| EPW-AC-12 | EPW-06 | Out-of-service equipment | Preview alternative | Unavailable item excluded; no booking mutation | API | #105 |
| EPW-AC-13 | EPW-07 | External prerequisite marked pending | Attempt required readiness gate | Owning rule blocks; no invented external clearance | E2E | #110 |
| EPW-AC-14 | EPW-07 | Authorized coordinator | Record minimal completion status | Status/evidence receipt, no external inspection details | API/DB | #110 |
| EPW-AC-15 | EPW-08 | Typed policy with forbidden action | Publish arbitrary command or invalid condition | Rejected, zero policy activation | API | PAC/ADR |
| EPW-AC-16 | EPW-08 | Existing mandatory commercial review | Set weaker generic approval | Rejected; existing booking policy remains authoritative | DB/API | #112 |
| EPW-AC-17 | EPW-09 | Two eligible and one unqualified approver | Submit duplicate and unauthorized votes | Only distinct eligible votes counted; invalid denied | DB race | OLA-11 |
| EPW-AC-18 | EPW-09 | Approved subject revision changes | Execute stale receipt | Conflict, zero domain change | API/DB | OAC-AC-05 |
| EPW-AC-19 | EPW-09 | 20 simultaneous executions | Execute same reviewed digest | One owning receipt, no duplicate mutation | DB race | OLA-14 |
| EPW-AC-20 | EPW-10 | Issue restricted reason + safe summary | View as vendor | Only permitted safe fields, no reason leakage | API/browser | #110 |
| EPW-AC-21 | EPW-10 | Issue linked to seating/booking conflict | Close issue without domain decision | No allocation/booking change | DB | ADR 0003/#112 |
| EPW-AC-22 | EPW-11 | Template from rich historical event | Clone safe configuration | Zero PII, passes, approval, job, reservation or attendance copies | DB diff | OAC-13 |
| EPW-AC-23 | EPW-11 | Retired dependency | Apply preset after review | Conflict or explicit re-review; no silent substitute | API | AES |
| EPW-AC-24 | EPW-12 | Recurrence across DST | Preview bounded series | Correct local-time instants, ambiguity explicit, no holds | Unit/API | UX-AC-10 |
| EPW-AC-25 | EPW-12 | 20 duplicate series submissions | Commit same occurrence keys | At most one draft per selected occurrence | DB race | OLA-14 |
| EPW-AC-26 | EPW-12 | Series with past approved occurrence | Edit future drafts | Past/live/approved snapshot unchanged | DB | Blueprint §10 |
| EPW-AC-27 | EPW-13 | Event with outstanding handover item | Close/review handover | Explicit unresolved obligations; no false completion | E2E | OLA-09 |
| EPW-AC-28 | EPW-14 | Task update and disconnect | Reconnect scoped EOC | Authorized current state, gap resync, no unauthorized data | Browser/fault | AGIS-16 |
| EPW-AC-29 | EPW-14 | CID provider accepted message | View task status | No acknowledgement or task completion inferred | DB/E2E | CID |
| EPW-AC-30 | EPW-15 | Revoked partner grant | Read/update task and download evidence | Denied with no scope leakage; history intact | API/DB | ADR 0023 |
| EPW-AC-31 | EPW-16 | 500-task synthetic graph | Run reference benchmark | p95 targets measured, bounded graph result | Load | OLA-14 |
| EPW-AC-32 | EPW-16 | Keyboard/zoom/bs-BA/en | Create plan and reorder without drag | All essential actions accessible, no data loss | Manual/browser | UX-AC-13 |
| EPW-AC-33 | EPW-07, EPW-13, EPW-14 | Restore with due reminders and unresolved tasks | Recover in both installers | No duplicate ambiguous sends; current readiness and history reconciled | Host/VM | OLA-15 |

### Requirement-to-acceptance traceability

| Requirement | Acceptance suffixes | Owning topic |
| --- | --- | --- |
| EPW-01 | 01, 02 | Planning views and ownership |
| EPW-02 | 03, 04 | Milestones and task structure |
| EPW-03 | 05, 06 | Dependency graph and critical path |
| EPW-04 | 07, 08 | Run-of-show and programme |
| EPW-05 | 09, 10 | Staff roster and shift coordination |
| EPW-06 | 11, 12 | Resources, equipment and services |
| EPW-07 | 13, 14, 33 | Readiness, checklists and external prerequisites |
| EPW-08 | 15, 16 | Constrained approval policy designer |
| EPW-09 | 17, 18, 19 | Approval instances and escalation |
| EPW-10 | 20, 21 | Operational issue board and change control |
| EPW-11 | 22, 23 | Event templates and safe cloning |
| EPW-12 | 24, 25, 26 | Recurring events and booking series |
| EPW-13 | 27, 33 | Handover and post-event review |
| EPW-14 | 28, 29, 33 | Live coordination and communication |
| EPW-15 | 30 | Cross-party delegation and data boundaries |
| EPW-16 | 31, 32 | Planning quality and adaptive UX |

### Release integration

Add the above evidence to applicable OLA scenarios and G1–G9 gates without replacing existing OLA/PAC/OAC/UX/TDS/AGIS/CID criteria. G1 CI, G2 independent organization, G3 isolation, G4 configuration/content/output, G5 cross-domain journey, G6 resilience/accessibility, G7 deployment/recovery, G8 external evidence when applicable, G9 traceability/release defects. Provider-only, simple organizer and complex hybrid journeys remain independently usable. Actual supported devices, deployment and external provider acceptance only in planned Phase 9; automated tests incrementally in owning slices.

## 12. Open decisions and proposed integration

Decide existing task-state mapping and plan item identity, calendar/slack algorithm and graph limits, recurrence grammar/cap, resource buffer semantics, authority for shift assignment, which approval domain adapters may be configured, quorum/expiry/delegation and single-owner safeguards, checklist required policy and ordinary issue severity, evidence retention and print scope. Validate actual production programme, staffing and commercial approval rules with tenant. Full emergency/security command, payroll, automatic purchase/payment and unlimited recurrence excluded. Independent integration center and advanced finance remain future planning, not implicit EPW requirements.

Before implementation, owner/tenant validates real capacities, legal/retention policies, staffing, commercial rules, programme, identity and accessibility needs; no fictional examples become GHB configuration. Engineering reviews candidate libraries, licensing, exact route/schema/role choices, security threat review and performance envelope when scheduled. Do not modify accepted ADRs except through reviewed successor. Once owner approves, integrate complete source verbatim at stated destination, record approval and original SHA-256/blob externally in [design index](README.md). Add dated additive cross-references in architecture, roadmap, gap analysis, relevant approved designs and mapped existing issues, retain historic source checksum references and all existing issue requirements. Verify complete docs-only Git tree diff, source read-back, link resolution, required exact-head CI and post-merge CI; no runtime code, migrations, OpenAPI, workflows, Blueprint v1.2, PROJECT_STATE, Codex branches, environment or early VM change. Future consolidated Blueprint v1.3 separately approved; no requirement silently dropped.
