# Eventor Reporting, Analytics and Intelligence Studio (RAI)
## Technical specification v1.0

**Status:** Proposed for product-owner approval; no integration or implementation authorized by this draft.  
**Date:** 2026-11-27. **Read-only repository baseline:** `e0fa44203f785284d597f69dae8510c91bada0d6` (main, CID PR #236). All five required CI checks on this baseline were observed completed successfully during preparation. CI is not product acceptance.  
**Proposed destination:** `docs/implementation-design/v0.3/REPORTING_ANALYTICS_AND_INTELLIGENCE_STUDIO_DESIGN_v1.0.md`. Links are relative to that future location. The five proposed documents are companion drafts, not yet repository files.  
**Document control:** RAI-01–16, RAI-M0–M6, RAI-AC-01–35. MUST denotes proposed product requirement, SHOULD preferred approach with justified exceptions, MAY optional. Endpoint names, entity names, permission codes and numerical envelopes are design proposals, not existing runtime contracts or certified targets. No acceptance tests executed.

## 1. Objective and boundaries

Deliver a unified reporting and analytics studio for standard operational reports, authorized configurable reports, dashboards, comparisons, exports and scheduled distribution. The term intelligence means defined metrics, trend and exception analysis over approved data, not an autonomous AI decision-maker, employee surveillance, predictive scoring of guests or unrestricted SQL. Data remains in owning booking, event, Registry, allocation, admission, task, hospitality, form, communication and governance domains; RAI builds safe read projections and private artifacts. OAC portfolio dashboards and EOC live operational metrics consume the same metric definitions where applicable. No dashboard, report, export or schedule grants underlying data rights or changes business facts. Basic Eventor works without advanced analytics, external BI vendor or data warehouse. Preserve source facts, revisions, definitions, data freshness and evidence distinctions; do not imply a booking is confirmed from an offer, RSVP from delivery, attendance from RSVP, or fulfillment from task notification.

## 2. Existing foundation and reconciliation

Blueprint §26 explicitly enumerates registry, RSVP, seating, capacity, arrival, no-show, revisions, staff coordination and prerequisite reports; §§14,35–37 describe scoped cockpit metrics, timeline and freshness; §21 and §38 protect sensitive fields. OAC-18 defines permissioned reporting, bounded jobs, artifact retention/export and field controls; TDS already governs printable and branded outputs; CID governs delivery and reconciliation. Existing migration 000036 notification campaign reporting, roster/Registry exports 000138–139, 000180 export references and related runtime API/UI provide meaningful scoped reports; `PROJECT_STATE.md` records filtered CSV/XLSX exports and import diagnostics. Current foundation is not a general visual report/dashboard designer, verified cross-domain metrics catalogue or scheduled reporting engine. #111 explicitly owns reports/exports and display outputs, #107 owns live cockpit, #104 owns Registry access. Read-only audit is not runtime validation; preserve current exports and existing report semantics.

Use [Blueprint v1.2](../../blueprint/v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md), [architecture](../../ARCHITECTURE.md), [roadmap](../../ROADMAP.md), [project state](../../PROJECT_STATE.md), [gap analysis](../../BLUEPRINT_TO_REPOSITORY_GAP_ANALYSIS_v1.0.md), [operating model](../../OPERATING_MODEL.md), and [roles](../../product/USER_ROLES_AND_PERMISSIONS_v0.1.md). Read [RSVP design](RSVP_AND_INVITATION_DESIGN_v0.3.md), [collaboration design](CROSS_ORGANIZATION_COLLABORATION_DESIGN_v0.3.md) and [disruption design](CANCELLATION_AND_EVENT_DISRUPTION_DESIGN_v0.3.md) for owning commands. Existing accepted decisions prevail until reviewed successor: [modular monolith](../../decisions/0001-modular-monolith.md), [self-hosting](../../decisions/0002-self-hosted-deployment.md), [human-approved allocation](../../decisions/0003-human-approved-allocation.md), [optional scope](../../decisions/0004-optional-event-operations-scope.md), [invitation separation](../../decisions/0005-separate-invitations-rsvp-attendance.md), [collaboration](../../decisions/0006-cross-organization-collaboration.md), [localization](../../decisions/0007-internationalization.md), [incremental staff UI](../../decisions/0008-modular-staff-frontend.md), [membership protection](../../decisions/0010-organization-membership-access.md), [login/workspaces](../../decisions/0015-email-first-login-and-platform-administration.md), [scoped grants](../../decisions/0023-permissioned-collaboration-grant-lifecycle.md), [reviewed grant acceptance](../../decisions/0024-shared-party-names-and-reviewed-grant-acceptance.md).

| Approved addendum | Reconciliation rule |
| --- | --- |
| [TDS](TEMPLATE_DESIGN_STUDIO_DESIGN_v1.0.md) | Single brand/asset and document rendering infrastructure for report layouts, charts, private PDF and approved printable plans; RAI owns data definitions and query policy. |
| [PAC](PLATFORM_ADMINISTRATION_CENTER_DESIGN_v1.0.md) | Platform health/usage diagnostics and aggregate governance separate from tenant data; protected support, job/recovery and retention policy. |
| [OAC](ORGANIZATION_ADMINISTRATION_CENTER_DESIGN_v1.0.md) | Scoped organization dashboards, saved reports and private exports, independent tenant report administration. |
| [UX](EVENTOR_USER_EXPERIENCE_AND_NAVIGATION_v1.0.md) | Role-filtered standard reports and configurable studio, accessible chart/table alternatives, freshness and explicit status. |
| [OLA](ORGANIZATION_LIFECYCLE_ACCEPTANCE_SCENARIOS_v1.0.md) | Extend OLA-04/05/07–11/13–15 and G1–G9 with metric correctness, scope, artifact/revoke, scheduled delivery and restore. |
| [AGIS](ADMISSION_GUEST_INFORMATION_AND_STATION_MANAGEMENT_DESIGN_v1.0.md) | Authoritative attendance, station/attempt evidence, current published seating and safe display projections; no exposing private station or guest info. |
| [CID](COMMUNICATION_INVITATION_DISTRIBUTION_AND_MULTI_CHANNEL_DELIVERY_DESIGN_v1.0.md) | Scheduled report intent and approved distribution use fixed audience/route, budget/consent, private link/attachment review and verified evidence; no blind resend. |

### Companion proposals (not yet approved)

| Companion | Interface and boundary |
| --- | --- |
| [AES](ADAPTIVE_EXPERIENCE_AND_SETUP_DESIGN_v1.0.md) | Quick standard reports, guided filters, advanced designer over same catalogue and authority. |
| [EPW](EVENT_PLANNING_PRODUCTION_AND_OPERATIONAL_WORKFLOWS_DESIGN_v1.0.md) | Task/cue planned-vs-actual, readiness, resource/service and series metrics, never inferred completion. |
| [FRS](FORMS_REGISTRATION_AND_SUBMISSION_STUDIO_DESIGN_v1.0.md) | Publication/submission/review/application metrics with approved fields, no raw private responses by default. |
| [HPG](HOSPITALITY_PROTOCOL_AND_GUEST_SERVICES_DESIGN_v1.0.md) | Demand/confirmed/fulfilled and service counts using minimal aggregate projection and small-cell safeguards. |

## 3. Adaptive experience and user journeys

Quick Start: open event → Reports → select standard report (guest summary, RSVP, booking calendar, attendance, task status) → choose date/scope → view or explicitly export if allowed. Show source definitions and “as of”; no mandatory dashboard authoring. Guided: select approved dataset, permitted dimensions and metric, date range, group/sort/filter and chart/table → preview, review and save private report. Advanced: drag/reorder approved widgets, typed calculated measures and dashboard layouts, comparisons and scheduled private reports; no raw SQL, arbitrary joins or executable formulas. OAC overview provides permitted portfolio metrics; EOC live uses authoritative operational projections and last refresh, not cached portfolio data for admission decisions. Saved personal view sharing is explicit, never elevates recipient data rights.

Example: synthetic organizer A compares two receptions on accepted RSVP, authoritative arrivals and printed passes; provider-only C reports booked resource hours and inquiry conversion with zero guest rows; partner B sees assigned task counts only. A manager may choose approved hospitality aggregate by service window, but not rare dietary group drill-down. A report designer without Registry read can configure allowed aggregate dataset and synthetic preview but cannot open real private details. A report scheduled to a colleague who later loses access must stop or exclude them after reviewed authorization; do not email old sensitive attachment simply because schedule was approved months earlier.

Every chart has a titled metric definition, units, time interval, filters, source and as-of, accessible tabular equivalent, zero vs unknown distinction, and safe drill-through only where authorized. Show suppressed, not applicable, partial or stale explicitly; no misleading chart denominator or percentages over incompatible populations.

All modes are projections over the same canonical records and commands. Quick Start is not a permission class, price tier, alternate storage model or waiver of domain rules. Guided mode adds relevant questions; Advanced exposes authorized settings and diagnostics. Mode changes do not themselves mutate domain facts, publish, send, reserve, approve or grant authority. Defer optional setup; distinguish not applicable, not enabled, not configured, blocked and ready. A user can resume a draft and switch modes without losing valid work. Show reasons and a permitted next action, not inaccessible target IDs. Use bs-BA/en, IANA timezone, locale-aware number/date display and immutable authored translations; no silent translation of legal or guest-facing meaning. All visual interactions have keyboard/non-drag equivalents. User preference, organization default, and event capability are separate.

## 4. Functional requirements

### RAI-01 — Dataset catalogue and domain ownership

MUST define approved versioned dataset registry with owner, purpose, grain, source projection, keys/joins, dimensions, measures, row and field permissions, classifications, filter/window limits, freshness, allowed outputs and release support. Use allowlisted compiled queries and stable semantic IDs, never arbitrary SQL/table selection. Data owners validate semantics before publish. Separate tenant and platform diagnostics; provider-only booking dataset requires no organizer guest scope. Dataset retired for new reports retains interpretable historical manifests. Standard and custom reports use the same catalogue.

### RAI-02 — Metric definitions and truthful status

Define metric numerator, denominator, unit, grain, distinct key, effective time, inclusion/exclusion, revision and treatment of missing/suppressed/unknown, cancellation and duplicates. Do not label sent as delivered, estimated headcount as attendance, request as confirmation, approved offer as booking, or printed pass as handover. Distinguish active vs historic snapshot and planned vs actual; show both where relevant. Explicitly define no-show only after event/session cutoff and eligibility/attendance reconciliation, not before; unresolved offline scans and provisional counts shown separately. Metric changes create new version, never silently recalculate historical published report under different definition.

### RAI-03 — Standard report families

Provide ready-made scoped reports for bookings/inquiries/offers/confirmed reservations and cancellation; resource/venue usage; Registry/roster and import diagnostics; RSVP/invitation/delivery; seating/zone/capacity/unassigned/conflict and revision; admission issuance/arrival/exception; EOC readiness/issues; tasks/production/assigned partner; FRS registration/submission; HPG service demand/fulfillment; CID costs/usage; approved governance/audit. Use only available owning data, unsupported reports visibly unavailable, not zeros. Preserve original Blueprint §26 families and current CSV/XLSX contracts. Configurable presets are not mandatory for basic event.

### RAI-04 — Report designer and saved definitions

Typed visual builder selects dataset, permitted fields/metric versions, date range/timezone, filter operators, grouping, sort, chart/table layout and output options. Bounded joins only preapproved paths; prohibit cross-grain fan-out unless semantic aggregation explicit. Validate field and aggregate permission separately, including sort/filter/group/having even if not displayed. No raw SQL, arbitrary JS, external fetch, spreadsheet executable formula or unrestricted custom expression. Safe bounded calculations (sum, count distinct, ratio, period difference, approved arithmetic) with typed units, zero denominator/unknown handling. Preview synthetic or explicitly authorized scoped real data; save versioned private/shared definition, publication/review as policy. Retired dataset/field prompts review, no silent substitution.

### RAI-05 — Dashboards and adaptive navigation

OAC portfolio, EOC event and personal task dashboard use shared widget catalogue with current permissions. Offer standard panels and optional advanced layout designer, responsive rows/cards/charts/table, accessible reorder and alternatives. Widget configuration includes dataset/metric version, scope selector, refresh policy, safe drill action and classification. A dashboard may compose multiple authorized datasets but never join inaccessible values on client. Refresh independently, show per-widget as-of and partial failures; hide unauthorized widget data/counts without leaking target IDs. No private widgets in passive display unless explicitly approved guest-safe aggregate; AGIS display owner enforces projection.

### RAI-06 — Temporal, comparison and historical semantics

Use IANA timezone and explicit half-open time intervals `[from,to)` in UTC for computation, display local with DST; define event vs booking vs processing time. Distinguish current authoritative state, as-of snapshot where historically supported, pinned published revision and actual timestamp. Do not promise reconstructable as-of if source lacks history; show limitation. Compare equivalent population/grain/time windows, normalize duration when meaningful, expose source revisions and policy changes. Series occurrences independently count, prevent double count of event guest across sessions or repeated joins. Historical reports pin query/metric version and source boundary; stored artifact immutable, rerun is new artifact with new as-of.

### RAI-07 — Booking and commercial metrics

Use owning booking inquiry, offer, decision, confirmation, reservation and cancellation snapshots. Inquiry conversion denominator distinct eligible inquiries in cohort with declared observation window; outcome categories defined and unknown/ongoing separate. Utilization uses approved available resource-hours denominator and confirmed occupied/blocked intervals, distinguish maintenance and setup/teardown; overlapping discrete resources handled per resource/quantity, no double count, occupancy not actual attendance. Financial metrics use pinned price/tax/discount/cancellation commercial values and currency; no mixing currencies without approved conversion basis and timestamp, no inferred collected revenue or refund from confirmed booking. Actual payment evidence only if owning supported recorded fact. Full accounting and invoicing future scope.

### RAI-08 — Guest, invitation and registration metrics

Differentiate Registry persons, event participations, companions/counts, application requests, accepted registration, active invitation, RSVP response and attendance; do not join raw Registry for event reports unless explicit field rights. Use pinned event identity for historic exports. Invitation/RSVP cohort defined by eligible issued or allowed participation policy; withdrawn/revoked and unknown states shown separately. FRS submission/application/waitlist and accepted participation from owning receipts, no conversion from review alone. CID attempt metrics by route/provider status and logical recipient/intent separately; retries do not inflate unique guests. No private contact values or raw answers in general reports.

### RAI-09 — Allocation, admission and EOC metrics

Use current approved published plan, typed seat/row/zone/capacity and assignment state; show unallocated/locked/conflicts and publication revision, draft solver not approved. Count initial authoritative arrivals by event/session and distinct attendance subject under AGIS policy, not scans/attempts; show duplicates/rejections/provisional offline and corrections separately. No-show calculated only after cutoff and reconciled attendance with declared eligible cohort. Station health and latency from current observed timestamps, offline marked stale, no personal details. EOC live metrics use owning outbox/read projections, not delayed analytics for admission decision. Safe map/report outputs TDS/AGIS authorized projection only.

### RAI-10 — Production, task and hospitality metrics

EPW planned vs actual cue/task duration, due/completed/blocked and readiness evidence, explicit scope, deadline/time assumptions and correction history. No employee performance ranking or inferred productivity; authorized workload/coverage only. HPG planned demand, confirmed service units, fulfilled/remaining and unresolved exceptions with service window and unit; distinguish manual estimate vs source and avoid repeated party/session double counts. Default aggregate only, suppression for rare sensitive service categories. Vendor sees assigned task/projection only, no unrelated attendee or commercial records. External prerequisite report shows minimal coordination status, not inspection findings or operational security data.

### RAI-11 — Communication, operational and governance metrics

CID reports distinguish logical intents, route submissions, accepted, verified delivered/read, failed, suppressed, uncertain and manual handover; accepted not delivered and unsupported receipt not failure. Costs show estimate, reserved maximum, actual verified or unresolved charge, currency and period, no invented price/provider invoice. PAC health/job metrics include queue age, retry/failure, backup/restore receipts, supported capability and coarse quotas, no tenant recipient data by default. Audit reports scoped to purpose/actor/action/time and safe reason, no plaintext secrets. External provider and partner metrics never expose another tenant customer, account or usage.

### RAI-12 — Privacy, aggregation and inference controls

Apply row/field and aggregate permissions at query compilation/execution, filters, sorting, joins, grouping, drill-down, saved definitions, scheduled run, artifact creation/download and distribution. Aggregates are data disclosure too; use approved minimum cell threshold, complementary suppression and restricted dimensions for sensitive categories and external/limited scopes, account for totals/differencing and repeated queries. Proposed initial k=5 for sensitive aggregate views subject to reviewed threat/policy; not universal anonymity guarantee. Suppressed cell is not zero; do not leak via chart tooltip, total, percent, sort, export or error. No arbitrary cohort selection that enables reconstruction; query budget/window restrictions where needed. Authorized detailed operational reports require explicit field-level need and audit, never default to broad analytics. No sensitive inference from demographics or automatic guest scoring.

### RAI-13 — Exports, printed reports and reproducibility

Offer scoped CSV/XLSX, private PDF/print via TDS and machine-readable structured export where approved. Pin dataset/metric versions, canonical query/filter/scope, locale/timezone, source refs/as-of, record count, suppression/exclusions, output schema, TDS/brand/renderer revision, artifact digest and created actor. CSV/XLSX neutralize formula injection; typed cell values, Unicode/diacritics, explicit units and safe spreadsheet names. PDF chart/table/print accessibility and pagination, no clipped critical values. Bounded synchronous small results, asynchronous larger jobs; private artifacts, no public direct path; recheck authorization and expiry on download, no artifact containing revoked scope served. Historical artifact remains interpretable and retained as permitted, never silently rerender. Export does not imply permission to share or send.

### RAI-14 — Scheduled reports and distribution

Authorized schedule pins report definition/revision, scope, local timezone/recurrence cap, intended recipient set and eligible delivery route, cadence, maximum window, output/retention, CID policy and budget if applicable. Preview representative output and recipient eligibility; explicit reviewed schedule, separate authority for report run/export and CID distribution. Each occurrence bounded and idempotent unique schedule+occurrence; recheck creator/service intent, active recipient membership/grant, current dataset and classification, schedule and approved delivery scope before run and send. Revoke/retire/stale definition pauses or requests review; no silently add recipients or broaden data. Prefer secure private link requiring current access; attachments only explicitly reviewed for classification and recipient, no bearer link in ordinary logs. Never auto retry ambiguous external send; missing provider leaves artifact/private delivery task. No external email mandatory.

### RAI-15 — Jobs, caching, refresh and failure handling

Bound query cost (time, rows/groups, filters, date range, memory) and queue per tenant; use indexed views and optional scoped materialized projections only after measurement, not data warehouse by default. Query cache key includes tenant, effective scope/permission revision, dataset/version, filter/timezone and as-of; never reuse across tenants/authority; invalidation on source or grant change. Do not expose cached artifact after revocation. Separate refresh from owning writes, read-only DB role/narrow functions and consistent snapshot; job leases/fences/idempotency. Cancel pending/running job with safe status; partial results not labeled complete, failure receipt redacted. Operational counts current vs stale explicit; restore reconciles jobs/artifacts before retry, no duplicate scheduled sends.

### RAI-16 — Governance, accessibility and quality

Report library with owner, revision, audience/classification, last run/freshness, retention and review date. Personal saved view vs organization-approved share distinct; recipient authorization always independently evaluated. Retire, revoke, correct, expire, retention/hold, export portability and scoped support integrated with OAC/PAC. Accessibility: table alternative for every chart, semantic headers, labels, keyboard navigation/reorder, focus and high contrast, locale-aware number/date/currency/units, no color-only signals. Compare against reference fixtures and actual domain command receipts, not visual impression. No automatic analysis advice that changes domain facts; any future predictive/AI work separate review.

## 5. Workflow, transaction and failure semantics

### Semantic reference examples (synthetic, proposed definitions)

| Metric key | Grain / formula | Exclusions / evidence |
|---|---|---|
| booking.confirmed_count | distinct booking IDs with confirmed effective status at declared time | exclude drafts/offers, cancellation state defined as-of |
| booking.inquiry_conversion | distinct eligible inquiry cohort with confirmed linked booking by observation cutoff / distinct cohort inquiries | pending separately; zero denominator unknown |
| resource.utilization_hours | union of confirmed occupied intervals clipped to available resource intervals, per resource; capacity-weighted only by explicit definition | maintenance excluded from available, overlap counted once; no attendance claim |
| event.rsvp_accepted | distinct eligible participation IDs with current accepted response | no reply ≠ declined; policy version pinned |
| event.arrivals | distinct attendance subjects with authoritative initial arrival, per declared event/session grain | duplicate scans not arrivals; provisional offline separate |
| event.no_show | eligible expected cohort without authoritative arrival after cutoff and reconciliation | unknown if unresolved/provisional; denominator visible |
| allocation.remaining | approved capacity units minus current committed assignments for typed resource | draft proposals excluded; no invented seats |
| cid.delivered | distinct route delivery IDs with verified delivered evidence, status precedence defined by CID | accepted/uncertain separate; retries separately counted |
| task.overdue | distinct open task IDs with due instant before as-of, configured calendar | no due date unknown/not applicable |
| hpg.fulfilled_units | sum of effective verified fulfillment events after corrections per service window/unit | confirmed not fulfilled; do not sum incompatible units |
| frs.applied | distinct submission IDs with successful owning application receipt | approved pending execution not applied |

### Execution contract

Select catalogue revision and effective actor scope → validate typed query (fields including hidden sort/filter, grain, operators, limits, metric definition and output) → authorize before data lookup → compile parameterized read projection → use consistent snapshot and capture source boundary → apply approved suppression and output filters server-side → render authorized results or enqueue bounded export with manifest → reauthorize each claim/complete/download and sharing action. No query runs on arbitrary user-supplied database identifiers or SQL. An export request idempotency key binds canonical query, scope, output/locale; repeat returns same private receipt after current authority check. Changed scope/data requires new reviewed run.

Schedule state `draft → reviewed → active → paused/retired`; per-run `scheduled → queued → running → ready/failed/cancelled/expired`; CID delivery evidence separately. On grant/definition/policy change pause affected schedule and deny old artifacts that include forbidden fields; preserve receipts and approved retention. Restore fences incomplete/possibly sent occurrences, reconciles outbox/usage and only resumes safe work. No business writes.

| Failure | Required behavior |
|---|---|
| Invalid or unapproved join | Reject with safe validation reason, no query |
| Query exceeds limit | Cancel and report safe error; suggest bounded filters |
| Source not available | Explicit unsupported/partial/stale; no zero substitute |
| Metric denominator zero | Unknown/not applicable; no divide-by-zero or misleading 100% |
| Sensitive small cell | Suppress cell and related totals/percent where needed |
| Recipient loses scope | Deny run/share/download; pause/review schedule |
| Network loss after export | Query existing receipt, no duplicate job |
| Uncertain CID submission | Block blind resend; reconcile via CID |
## 6. Architecture and logical data model

Extend the existing Vue 3/TypeScript staff application, Fastify API/workers and PostgreSQL 18.6 modular monolith; no mandatory external SaaS or second database. Reuse domain commands, approved TDS renders, CID delivery, transactional outbox and scoped projections. Logical names below are candidates; inventory actual schema, role grants, lock order, indexes, views, current APIs and fixtures at M0. Add only missing extensions with forward migrations; no rewriting historical migrations, accepted ADRs or the v0.2 schema/OpenAPI snapshots. All tenant-owned keys include organization context; event references include event scope, verified by composite FK or equivalent command integrity. Cross-party references use explicit accepted grant/revision and permitted projection, never broad joins. Immutable published revisions, decisions, receipts and evidence retain source IDs; append correction/supersession rather than destructive rewrite. Sensitive values and private artifacts use authenticated encryption and purpose-bound identity; no secret in audit or general projections.

| Logical entity or existing aggregate | Principal fields / keys | Integrity and lifecycle |
| --- | --- | --- |
| dataset_catalog/revision | owner module, semantic ID, grain, projection, typed fields, authority/classification, freshness, limits | Reviewed immutable version, approved query compiler mapping; no raw SQL user fields |
| metric_definition/revision | dataset, semantic key, numerator/denominator/unit/time grain, missing/suppression rules | Versioned, explicit compatibility and change history |
| report_definition/revision | org, owner, dataset/metric refs, typed filters/group/sort/layout, locale, scope/classification | Personal/shared review; no access grant from definition |
| dashboard_definition/revision | org/user, widget manifests, permitted action keys, refresh/layout | Versioned authorized composition; public display separate |
| report_run/job | org, report rev, actor/service intent, effective scope digest, source as-of, status/lease/fence | Bounded read job; idempotency, reauthorize; no business mutation |
| report_result_manifest | query digest, dataset/metric versions, source boundary, counts/suppression, renderer/brand rev | Immutable receipt; private artifact and retention |
| report_artifact | org, run, object ref, format/digest, classification, expiry/hold | Private authorized download; revocation denies access |
| report_schedule/revision | org, report rev, recurrence/timezone, reviewed recipients/routes, policy/budget, state | Explicit approved bounded schedule, no auto broadening |
| report_schedule_occurrence | schedule rev, occurrence key, run/intent refs, due time, state | Unique logical occurrence, CID status separate |
| report_share_grant (if needed) | report/definition, recipient scope, grant/review expiry | Cannot add underlying dataset rights, revocable |
| query_cache/projection checkpoint | scope digest, source/version/time, invalidation epoch, cursor | Bounded, no cross-scope cache; derived not source of truth |
| report audit/evidence | actor, action, approved scope, versions, safe reason, receipt | Append-only, no protected values in audit |

### Migration and compatibility

Audit existing tables and commands first; additive sidecar only where needed. Backfill through reviewed deterministic mapping with exception report, preserve existing IDs, historical snapshots and access semantics; default newly introduced capabilities to disabled/unconfigured unless existing equivalent facts justify activation. Test fresh install and populated upgrades, RLS and grants with runtime/auth/worker roles; old clients retain supported route behavior. No destructive down migration for recorded facts; recovery through tested compatible release or controlled restore and reconciliation. Add indexes for tenant/event/status/revision and due work; measure plans on synthetic representative cardinality; do not rely on client-side filtering.

## 7. API and permission contracts

Paths are relative to the existing API version; exact prefix, schema, codes and permissions determined after M0 inventory. Every staff route authenticates active user, selected membership, tenant, domain permission and object scope before lookup; delegated grants checked with current purpose, validity, projection and ceiling. Unknown/foreign IDs return non-enumerating error. Mutations use strict OpenAPI schemas, bounded input, CSRF/origin, expected revision and idempotency key scoped to tenant/actor/action; canonical request fingerprint binds reviewed inputs. Same key + same request returns original receipt only after current authority recheck; different request conflict. Stale revision/digest yields conflict and safe refresh, not silent override. Public capabilities are separate, opaque, high entropy, purpose-bound, expiring/revocable; store digest for lookup and minimal encrypted delivery envelope where required, fragment cleanup and no third-party referrer. GET/preview never issues credentials, publishes, approves, sends, reserves or changes business state. Use safe problem details/requestId, pagination with stable ordering and authorized filters; long jobs return 202 and receipt, not completed result. Recheck authority at job claim, artifact download, stream subscription/reconnect and consequential commit. Audit real actor/membership or scoped worker intent, purpose and outcome without plaintext sensitive data.

| Proposed operation | Input / result | Authority / effect |
| --- | --- | --- |
| GET /reports/catalog | allowed datasets, metrics, fields, limits and standard presets | dataset read/author scope; no hidden field catalogue |
| POST /reports/definitions/{id}/revisions | typed query, layout, expected rev | report author, validate field/query scope |
| POST /reports/definitions/{id}/preview | synthetic flag or bounded query, filters | real preview requires read scope, no artifact/send |
| POST /reports/definitions/{id}/publish | reviewed digest/rev | publisher, no new data rights |
| POST /reports/runs | definition/rev, filters, output, intent key | read + export if file, bounded job 202 or small result |
| GET /reports/runs/{id} | safe status, freshness, manifest/receipt | current scope before lookup |
| POST /reports/runs/{id}/cancel | expected state and reason | owner/job manage scope; no silent success |
| GET /reports/artifacts/{id}/download | private authorized stream | reauthorize source/field/export scope and expiry |
| GET /dashboards/{id} | allowed widget definitions/results/as-of | independent widget auth; no hidden data |
| POST /dashboards/{id}/revisions | typed widget/layout, expected rev | author/publish scope, no raw query |
| POST /reports/schedules/{id}/review | definition, recurrence, audience, route/policy/budget, digest | schedule prepare + read/export and CID review |
| POST /reports/schedules/{id}/activate | reviewed digest, intent key | schedule approver and delivery authority |
| POST /reports/schedules/{id}/pause | expected rev, reason | owner/manage; stop future occurrence claims |
| GET /reports/metrics/{key}/definition | permitted definition, unit/grain/time rules | authorized catalogue reader, no records |
| POST /reports/artifacts/{id}/retention-review | hold/expiry/correction request | data governance authority; no unreviewed purge |

### Permission matrix

| Authority (proposed semantic permission) | Scope | Allowed / exclusions |
| --- | --- | --- |
| dataset.read / dataset.aggregate | tenant/event/booking/task and metric scope | approved row/field/aggregate data only; no implicit detail drill |
| report.author / publish | tenant/purpose | definition and review; real preview independent |
| dashboard.manage | personal/tenant/event | layout only; every widget reauthorized |
| report.export | dataset/field scope | private artifact creation/download, not share |
| report.restricted.read | explicit field/purpose scope | need-to-know protected detail, audited |
| report.schedule.prepare/approve | report/source/recipient scope | review exact recurrence and audience, no silent send |
| communication.send/reconcile | CID purpose/route scope | separate eligible delivery, uncertainty rules |
| report.job.manage | tenant/job | cancel/retry safe jobs, redacted diagnostics |
| data.governance.manage | approved tenant/purpose | retention/hold/portability, no unrestricted read |
| partner task reader | accepted grant/exact task | only assigned projection and permitted aggregate |
| PAC support/health | platform or explicit scoped grant | coarse platform metrics, no blanket tenant data |

## 8. Security, privacy and reliability

Threats: SQL injection/expensive queries (typed catalogue, parameterization, cost limits and read-only narrow functions), hidden filters or join leakage (authorize every query field and preapproved join), cross-tenant inference (scope before lookup, cache key and suppressed aggregate policy), differencing/small-cell disclosure (complementary suppression and bounded queries; reviewed exceptions), stale permission/artifact replay (source authority recheck, expiry/revoke), misleading metrics (versioned grain/definitions and uncertainty), CSV formula execution (safe cells), report/attachment leakage through schedule (fixed approved audience, minimal secure links, current recipient eligibility), worker/restore duplicate effects (unique occurrence and fence/CID reconcile), XSS via labels (safe renderer), sensitive audit data (redacted receipts). No external analytics tracking or PII metric labels. No report grants ability to alter booking, person, attendance, approval, task, payment or service facts. Document risks of inference even after suppression; never claim anonymization solely from aggregation.

Never trust user-supplied tenant, role, target ID, template, route or scope. DB RLS and narrow commands protect data independently of navigation; deny direct writes and broad worker access. Use current membership/grant revocation ordering and reviewed successor ADR if changing authority. Outbox records commit with owning state, use tenant-scoped bounded consumers, lease/fence and deduplication; reconnect fetches authorized snapshot and cursor, gap triggers resync. Notification intents use CID with separately approved eligibility, content, costs and uncertainty handling; no automatic retry of ambiguous external submission. Sensitive data excluded from logs, metrics labels, URLs and public snapshots; no arbitrary JS, SQL, host shell, filesystem paths or external destinations. Review legal purpose, retention, correction, holds, redaction and portability with tenant; no claim of deletion from all backups. Tenant suspension denies new protected actions, preserves historical receipts and independent memberships. Local host recovery remains protected per PAC.

## 9. Quality, observability and deployment

Proposed fixture: 10,000 synthetic guests (Blueprint NFR-01), 100 events, 1,000 bookings, 50,000 delivery attempts, 5,000 tasks, 30 concurrent report readers and bounded export queue. Standard summary p95 ≤2 s on agreed local hardware; preview p95 ≤2 s for bounded query, export 10,000 rows within proposed 60 s excluding external distribution, with measured queue age and cancellation. Query limits initially 100,000 scanned/result rows according to approved dataset, 1,000 groups, bounded date range and server statement timeout; review actual plans and indexes rather than hardcoding unsupported guarantees. Validate exact totals with independent fixtures including DST, duplicate scans, retries, corrections, multiple sessions, currencies, missing values and zero denominator. Test canary restricted values through filters, chart, CSV/XLSX/PDF, cache, schedule and artifact download. No sensitive values in telemetry. Record query p95/error, queue age, artifact bytes, stale widgets, suppression count and failures without guest or confidential labels. Test both installer modes and restore of schedules/jobs/artifact keys; no automatic replay of uncertain deliveries.

Targets are proposed measurements on documented synthetic fixtures/hardware/network, with actual p50/p95/error rate and query plans recorded; no performance assertion before test. Both native Linux and production Docker Compose use the same build/schema/fonts/config/security contract, dedicated non-root service roles, TLS, durable storage and secret handling. External integrations optional; local capture/manual path and trusted local-network operation where server reachable. Backup DB/assets/keys and job state consistently; restore in isolation, fence potentially completed work and reconcile before enabling side effects. Browser tests Chromium/Firefox plus supported mobile/Safari/device evidence where applicable; keyboard-only, screen reader, contrast, 200% zoom and 360/768/1280/1920 widths. Operational metrics scoped by tenant and coarse counts, no PII labels; record queue age, failures and bounded diagnostics.

## 10. Implementation milestones and ownership

Do not change current Codex #104/#112 foundation closure then #105 spatial, #106 allocation, #107 admission/Cockpit, #110 collaboration, #111 communications/forms/reporting, #108 dual installers in established roadmap order. Work packages refine owning slices, not a new parallel project or immediate task switch. Minimal safe defaults can ship before advanced editors. Every slice: audit, reviewed contract/schema, domain API, role-scoped UI, negative/concurrency/upgrade/browser tests and documentation. Do not mark schema as usable workflow. Keep all existing issue criteria; do not create unrelated closure gates. Final full acceptance VM Phase 9 after feature-complete candidate.

| Milestone | Deliverables and exit evidence | Existing owner |
| --- | --- | --- |
| RAI-M0 — Inventory and semantic contracts | Audit current exports, domain read projections, role/field constraints; versioned dataset/metric catalogue and privacy/aggregation threat model. | #111/#104/#107 |
| RAI-M1 — Standard reports and compatibility | Keep existing roster/Registry/campaign exports, add standard scoped report definitions and truthful status/metric tests. | #111 |
| RAI-M2 — Visual report and dashboard studio | Typed query builder, filters/grouping/charts/tables, widget layout and safe drill, AES quick presets. | #111/OAC/UX |
| RAI-M3 — Cross-domain projections | Booking/venue, FRS, EPW, HPG, AGIS and CID metric families as owning slices arrive; EOC live freshness. | #104–107/#110/#112/#111 |
| RAI-M4 — Private export and governance | TDS outputs, manifests, retention/hold, field/aggregate auth, suppression and bounded jobs. | #111/PAC/OAC |
| RAI-M5 — Schedules and delivery | Reviewed recurrence/audience, CID secure distribution, revocation/uncertainty/restore fencing. | #111/CID |
| RAI-M6 — Integrated acceptance | Independent fixture correctness, load, accessibility, negative disclosure and both deployment modes; final evidence. | #108/Phase 9 |

### Issue reconciliation proposal (after owner approval)

| Existing issue | Scope clarification only |
| --- | --- |
| [#104](https://github.com/TeraflopsBH/eventor/issues/104) | Registry/roster approved source projections and historical identity/permissioned exports; preserve existing paths. |
| [#105](https://github.com/TeraflopsBH/eventor/issues/105) | Approved resource/venue availability and utilization dimensions; no private maps in general reports. |
| [#106](https://github.com/TeraflopsBH/eventor/issues/106) | Current published allocation/typed capacity reports; draft solver diagnostics restricted. |
| [#107](https://github.com/TeraflopsBH/eventor/issues/107) | Authoritative attendance, station health and EOC live metrics; no report-based admission decisions. |
| [#110](https://github.com/TeraflopsBH/eventor/issues/110) | Task/production/guest-service readiness and assigned-party projections, no restricted external prerequisite detail. |
| [#111](https://github.com/TeraflopsBH/eventor/issues/111) | Primary RAI catalogue, standard/custom reports, dashboard designer, private outputs, schedules and CID integration. |
| [#112](https://github.com/TeraflopsBH/eventor/issues/112) | Booking/disruption commercial facts, distinct decisions/acknowledgement, no inferred refunds. |
| [#108](https://github.com/TeraflopsBH/eventor/issues/108) | Bounded report jobs, storage/keys/restore, same native/Compose behavior and final acceptance. |

## 11. Measurable acceptance criteria and traceability

Use isolated synthetic tenants A organizer/hybrid, B independent partner, C provider-only; distinct authorized/preparer/reviewer/revoked actors, fake guests/contacts, fixed clock with DST edge, approved synthetic venue/plan and local delivery capture. Test exact-head CI and post-merge CI; run domain command/DB, API, real browser and concurrency/fault/restore tests as indicated. Capture candidate SHA, fixture revision, role, request/receipt IDs, expected/observed counts and redacted artifacts, measured times and actual hardware/provider evidence where applicable. No mock is proof of external compatibility; optional skips not passes. A test is pass only if every required result holds; failed/blocked/N/A explicitly reasoned and authorized, no waiver of security/integrity.

| ID | Requirement | Fixture / precondition | Action | Expected measurable result | Evidence | Related acceptance / scope |
| --- | --- | --- | --- | --- | --- | --- |
| RAI-AC-01 | RAI-01 | C provider-only with booking dataset | Open standard report | Authorized booking facts; zero guest/Registry dependencies | API/browser | OLA-07 |
| RAI-AC-02 | RAI-01 | User without restricted field rights | Load catalogue/query unknown field | No forbidden field metadata/value; non-enumerating deny | API | OLA-11 |
| RAI-AC-03 | RAI-02 | CID accepted vs delivered, RSVP vs scan fixture | Compute metrics | Exact distinct definitions; no inflated counts or incorrect labels | Unit/DB | CID/AGIS |
| RAI-AC-04 | RAI-02 | Zero denominator/unknown state | Render chart/table | Explicit unknown or N/A, not zero or 100% | Unit/browser | UX-10 |
| RAI-AC-05 | RAI-03 | Existing roster/Registry exports | Run compatibility regression | Existing authorized schema and filter behavior preserved | API/export | #104 |
| RAI-AC-06 | RAI-03 | Unsupported solver dataset | Select standard report | Unsupported status, no fabricated zero | Browser | OAC-02 |
| RAI-AC-07 | RAI-04 | Unapproved join/SQL/formula or hidden forbidden sort | Preview query | Reject before query; zero data disclosure | API/security | OLA-11 |
| RAI-AC-08 | RAI-04 | Known fan-out fixture | Group report by approved dimension | Exact distinct grain, no duplicate join counts | DB | OLA-14 |
| RAI-AC-09 | RAI-05 | Dashboard combines allowed and forbidden widget | Load as restricted viewer | Allowed widget only; no forbidden data/counts/IDs | API/browser | UX-05 |
| RAI-AC-10 | RAI-05 | Source lag and failed widget | Refresh dashboard | Per-widget freshness/partial, no false complete | Browser/fault | AGIS-16 |
| RAI-AC-11 | RAI-06 | DST and two series occurrences | Compare date intervals | Correct half-open instants, distinct occurrence counts | Unit/DB | EPW/AES |
| RAI-AC-12 | RAI-06 | Metric/source revision changed | View historic artifact and rerun | Historic manifest unchanged; new run labeled new version/as-of | DB/artifact | OLA-05 |
| RAI-AC-13 | RAI-07 | Overlapping reservation intervals and maintenance | Calculate utilization | Union/denominator exact; no double count | Unit/DB | #105/#112 |
| RAI-AC-14 | RAI-07 | Different currencies and no payment evidence | Compute commercial total | No mixed currency sum or inferred received/refund | Unit/DB | Booking design |
| RAI-AC-15 | RAI-08 | Multiple sessions, retries, waitlist and one person | Compute guest/registration/response counts | Correct grain and separate application/RSVP/attendance | DB | FRS/ADR 0005 |
| RAI-AC-16 | RAI-08 | Restricted Registry field in roster report | Run as event-only operator | No master profile leakage; historical event snapshot only | API/export | OLA-06 |
| RAI-AC-17 | RAI-09 | Duplicate scan + offline provisional + correction | Compute authoritative arrivals/no-show | One effective arrival per scope, provisional separate, no-show unresolved before cutoff | DB | AGIS |
| RAI-AC-18 | RAI-09 | Draft solver vs published plan | Export seating report | Only approved current source; no invented seats | API/export | ADR 0003 |
| RAI-AC-19 | RAI-10 | EPW cue due but not executed / HPG confirmed not fulfilled | Run readiness/service report | No inferred completion; exact planned vs actual | DB | EPW/HPG |
| RAI-AC-20 | RAI-10 | Vendor task scope | Drill/report across other tasks | Denied, own permitted counts only | API | OLA-10 |
| RAI-AC-21 | RAI-11 | Provider accepted, verified bounce, uncertain and cost reserve | Generate communication report | Distinct evidence/estimate/reserve/actual/unknown; no invented delivery or charge | DB | CID |
| RAI-AC-22 | RAI-11 | Platform health admin without support grant | Query tenant recipient history | Denied; coarse permitted platform health only | API | PAC |
| RAI-AC-23 | RAI-12 | Rare service category with complementary total | Group/filter/export/tooltip | Sensitive cell and reconstructing totals suppressed; no canary value | Security/export | HPG/OLA-13 |
| RAI-AC-24 | RAI-12 | Repeated differencing query / permission revoked | Compare or drill | Bounded approved queries; deny unauthorized values/cached results | API/security | OLA-11 |
| RAI-AC-25 | RAI-13 | Formula-like strings, diacritics and long labels | Export CSV/XLSX/PDF | Safe literal cells, exact units/digest/manifest and readable pagination | Artifact | TDS/OAC |
| RAI-AC-26 | RAI-13 | Artifact generated before grant revoke | Download after revoke | Denied; no private URL bypass | API | OLA-11 |
| RAI-AC-27 | RAI-14 | Approved schedule, recipient loses scope | Trigger occurrence | Pause/exclude only per reviewed rule; no unauthorized send | Worker/DB | CID |
| RAI-AC-28 | RAI-14 | 20 concurrent same schedule occurrence jobs | Claim/run/queue delivery | One logical occurrence/intent, no duplicate send | DB race | OLA-14 |
| RAI-AC-29 | RAI-14 | Provider uncertain report submission | Retry schedule delivery | No automatic duplicate/fallback; CID reconcile | Fault | CID |
| RAI-AC-30 | RAI-15 | Same query different tenant/role, revoked permission | Use cache/run | Scope-specific result, no cross-tenant reuse | API/security | OLA-11 |
| RAI-AC-31 | RAI-15 | Timeout or cancel bounded job | Inspect state/download | Explicit failure/cancel, no complete partial artifact | Worker | PAC |
| RAI-AC-32 | RAI-16 | Keyboard, screen reader, mobile/200% zoom bs-BA/en | Create chart/table and read definition | All essential actions and equivalent table usable | Manual/browser | UX-AC-13/14 |
| RAI-AC-33 | RAI-16 | Retention hold + purge race | Expire artifact | Hold blocks purge; scope/audit preserved | DB | OLA-13 |
| RAI-AC-34 | RAI-02, RAI-06, RAI-07, RAI-08, RAI-09, RAI-10, RAI-11 | Fixed 10k-person multi-domain fixture | Compare computed totals and benchmark | All independent expected totals exact; p95 measured and target assessed | Load/DB | OLA-14 |
| RAI-AC-35 | RAI-13, RAI-14, RAI-15, RAI-16 | Restore with pending/uncertain scheduled delivery | Resume both modes | No replay of uncertain submissions; private artifacts/revocations reconciled | Host/VM | OLA-15 |

### Requirement-to-acceptance traceability

| Requirement | Acceptance suffixes | Owning topic |
| --- | --- | --- |
| RAI-01 | 01, 02 | Dataset catalogue and domain ownership |
| RAI-02 | 03, 04, 34 | Metric definitions and truthful status |
| RAI-03 | 05, 06 | Standard report families |
| RAI-04 | 07, 08 | Report designer and saved definitions |
| RAI-05 | 09, 10 | Dashboards and adaptive navigation |
| RAI-06 | 11, 12, 34 | Temporal, comparison and historical semantics |
| RAI-07 | 13, 14, 34 | Booking and commercial metrics |
| RAI-08 | 15, 16, 34 | Guest, invitation and registration metrics |
| RAI-09 | 17, 18, 34 | Allocation, admission and EOC metrics |
| RAI-10 | 19, 20, 34 | Production, task and hospitality metrics |
| RAI-11 | 21, 22, 34 | Communication, operational and governance metrics |
| RAI-12 | 23, 24 | Privacy, aggregation and inference controls |
| RAI-13 | 25, 26, 35 | Exports, printed reports and reproducibility |
| RAI-14 | 27, 28, 29, 35 | Scheduled reports and distribution |
| RAI-15 | 30, 31, 35 | Jobs, caching, refresh and failure handling |
| RAI-16 | 32, 33, 35 | Governance, accessibility and quality |

### Release integration

Add the above evidence to applicable OLA scenarios and G1–G9 gates without replacing existing OLA/PAC/OAC/UX/TDS/AGIS/CID criteria. G1 CI, G2 independent organization, G3 isolation, G4 configuration/content/output, G5 cross-domain journey, G6 resilience/accessibility, G7 deployment/recovery, G8 external evidence when applicable, G9 traceability/release defects. Provider-only, simple organizer and complex hybrid journeys remain independently usable. Actual supported devices, deployment and external provider acceptance only in planned Phase 9; automated tests incrementally in owning slices.

## 12. Open decisions and proposed integration

Decide actual dataset catalogue, owning read functions, metric definitions and semantic versions, time/cohort/currency rules, allowed calculations and joins, scope/field/aggregate permission catalogue, small-cell and differencing threat model, thresholds and exceptions, renderer/chart library, private artifact limits and retention, schedule owner/service intent lifetime, query planner limits and benchmark. Validate actual financial and venue policies with tenant; do not invent prices, capacities or KPIs. Future external BI integrations and predictive/AI intelligence require separate approved scope, not implied by RAI name.

Before implementation, owner/tenant validates real capacities, legal/retention policies, staffing, commercial rules, programme, identity and accessibility needs; no fictional examples become GHB configuration. Engineering reviews candidate libraries, licensing, exact route/schema/role choices, security threat review and performance envelope when scheduled. Do not modify accepted ADRs except through reviewed successor. Once owner approves, integrate complete source verbatim at stated destination, record approval and original SHA-256/blob externally in [design index](README.md). Add dated additive cross-references in architecture, roadmap, gap analysis, relevant approved designs and mapped existing issues, retain historic source checksum references and all existing issue requirements. Verify complete docs-only Git tree diff, source read-back, link resolution, required exact-head CI and post-merge CI; no runtime code, migrations, OpenAPI, workflows, Blueprint v1.2, PROJECT_STATE, Codex branches, environment or early VM change. Future consolidated Blueprint v1.3 separately approved; no requirement silently dropped.
