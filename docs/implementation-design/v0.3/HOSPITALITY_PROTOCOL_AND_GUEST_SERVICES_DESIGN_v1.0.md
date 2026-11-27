# Eventor Hospitality, Protocol and Guest Services (HPG)
## Technical specification v1.0

**Status:** Proposed for product-owner approval; no integration or implementation authorized by this draft.  
**Date:** 2026-11-27. **Read-only repository baseline:** `e0fa44203f785284d597f69dae8510c91bada0d6` (main, CID PR #236). All five required CI checks on this baseline were observed completed successfully during preparation. CI is not product acceptance.  
**Proposed destination:** `docs/implementation-design/v0.3/HOSPITALITY_PROTOCOL_AND_GUEST_SERVICES_DESIGN_v1.0.md`. Links are relative to that future location. The five proposed documents are companion drafts, not yet repository files.  
**Document control:** HPG-01–16, HPG-M0–M5, HPG-AC-01–31. MUST denotes proposed product requirement, SHOULD preferred approach with justified exceptions, MAY optional. Endpoint names, entity names, permission codes and numerical envelopes are design proposals, not existing runtime contracts or certified targets. No acceptance tests executed.

## 1. Objective and boundaries

Provide optional event-specific hospitality, protocol and guest services for simple refreshments/headcounts through complex receptions and delegations. Cover catering demand, dietary requirements, accessibility assistance, approved protocol precedence, party/delegation and accompanying guest coordination, host/escort service, transport and accommodation references, and requests from guests/staff. The canonical Registry person, event participation, RSVP, approved allocation, booking/resource reservation, task and admission records remain separate. The platform coordinates service requests and fulfillment; it is not a medical system, food safety certification, hotel PMS, taxi dispatcher, restaurant POS, payment processor or security command. Do not infer health, religion, disability or dietary restrictions from identity or demographic attributes. A guest need not supply sensitive information to be invited. HPG uses minimum actionable service projection and explicit consent/lawful-purpose review; no private detail on kiosks, ordinary print lists, signage or vendor exports.

## 2. Existing foundation and reconciliation

Blueprint §§6,8,12,14–16,33–38 already address categories, delegations, groups/relationships, allocation preferences, accessibility/service requirements, restricted notes and guest-safe maps. Migration 000011 and 000128–180 extend Registry/participation, contact verification, categories, group roles/hierarchy, relationships, custom fields, encrypted notes, restricted tags, placement preferences and placement rules. 000014 defines allocation/admission foundations; 000023 and 000108 establish scoped assigned-task projection/commands. OAC-11 resources/services, OAC-14 Registry and OAC-16 forms anticipate service coordination. #104 owns identity; #106 owns approved seating constraints; #110 owns scoped tasks and fulfillment; #111 owns form/report/communication support. Existing data and tags do not establish a complete hospitality workflow or permission to reuse sensitive attributes. Treat actual guest requirements and tenant service policies as unverified until supplied.

Use [Blueprint v1.2](../../blueprint/v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md), [architecture](../../ARCHITECTURE.md), [roadmap](../../ROADMAP.md), [project state](../../PROJECT_STATE.md), [gap analysis](../../BLUEPRINT_TO_REPOSITORY_GAP_ANALYSIS_v1.0.md), [operating model](../../OPERATING_MODEL.md), and [roles](../../product/USER_ROLES_AND_PERMISSIONS_v0.1.md). Read [RSVP design](RSVP_AND_INVITATION_DESIGN_v0.3.md), [collaboration design](CROSS_ORGANIZATION_COLLABORATION_DESIGN_v0.3.md) and [disruption design](CANCELLATION_AND_EVENT_DISRUPTION_DESIGN_v0.3.md) for owning commands. Existing accepted decisions prevail until reviewed successor: [modular monolith](../../decisions/0001-modular-monolith.md), [self-hosting](../../decisions/0002-self-hosted-deployment.md), [human-approved allocation](../../decisions/0003-human-approved-allocation.md), [optional scope](../../decisions/0004-optional-event-operations-scope.md), [invitation separation](../../decisions/0005-separate-invitations-rsvp-attendance.md), [collaboration](../../decisions/0006-cross-organization-collaboration.md), [localization](../../decisions/0007-internationalization.md), [incremental staff UI](../../decisions/0008-modular-staff-frontend.md), [membership protection](../../decisions/0010-organization-membership-access.md), [login/workspaces](../../decisions/0015-email-first-login-and-platform-administration.md), [scoped grants](../../decisions/0023-permissioned-collaboration-grant-lifecycle.md), [reviewed grant acceptance](../../decisions/0024-shared-party-names-and-reviewed-grant-acceptance.md).

| Approved addendum | Reconciliation rule |
| --- | --- |
| [TDS](TEMPLATE_DESIGN_STUDIO_DESIGN_v1.0.md) | Approved guest-service confirmations, restricted task sheets, meal counts and host briefing packs use shared rendering; no sensitive detail in public cards. |
| [PAC](PLATFORM_ADMINISTRATION_CENTER_DESIGN_v1.0.md) | Policy ceilings, retention, protected support and recovery; no universal private hospitality access. |
| [OAC](ORGANIZATION_ADMINISTRATION_CENTER_DESIGN_v1.0.md) | Tenant-owned service catalog, responsible teams, approved presets and capability readiness, event-specific requests remain event-scoped. |
| [UX](EVENTOR_USER_EXPERIENCE_AND_NAVIGATION_v1.0.md) | Quick headcount and advanced service board, accessible guest-facing request, permission-filtered projections and explicit status. |
| [OLA](ORGANIZATION_LIFECYCLE_ACCEPTANCE_SCENARIOS_v1.0.md) | Extend OLA-06/09/10/11/13–15 for service requests, guest-safe operations, partner restrictions, privacy and recovery. |
| [AGIS](ADMISSION_GUEST_INFORMATION_AND_STATION_MANAGEMENT_DESIGN_v1.0.md) | Verified Info Pult may show own permitted service directions or help contact; gate and passive display never expose health/service detail. No request, pass or delivery records attendance. |
| [CID](COMMUNICATION_INVITATION_DISTRIBUTION_AND_MULTI_CHANNEL_DELIVERY_DESIGN_v1.0.md) | Purpose-bound request acknowledgements, service notices and tasks use verified recipient/channel, minimal content, consent, uncertainty handling. |

### Companion proposals (not yet approved)

| Companion | Interface and boundary |
| --- | --- |
| [AES](ADAPTIVE_EXPERIENCE_AND_SETUP_DESIGN_v1.0.md) | Optional capability; simple headcount and checklist without sensitive fields, guided select service needs, advanced restricted board. |
| [EPW](EVENT_PLANNING_PRODUCTION_AND_OPERATIONAL_WORKFLOWS_DESIGN_v1.0.md) | Service owners, time windows, resource requirements and assigned tasks use EPW/owning task authority; HPG owns request/fulfillment facts. |
| [FRS](FORMS_REGISTRATION_AND_SUBMISSION_STUDIO_DESIGN_v1.0.md) | Approved service request forms, private attachments only if legitimate need; submission not fulfillment or profile update. |
| [RAI](REPORTING_ANALYTICS_AND_INTELLIGENCE_STUDIO_DESIGN_v1.0.md) | Scoped aggregate counts, demand/fulfilled/remaining and small-cell safeguards; no unrestricted person-level health exports. |

## 3. Adaptive experience and user journeys

Quick Start: organizer enables refreshments or hospitality, enters expected headcount and service window, selects approved service preset and owner, saves draft. No mandatory menus, personal data, named dietary lists or vendor workflow. Guided: service categories, estimated demand source, session/room, dietary/accessibility collection policy, responsibility and reviewed capacity. Advanced: event service board by session/location/service, demand and capacity, fulfillment/exception queues, delegation/host assignments, transport/accommodation references, restricted request inbox, authorized projections. Guest may submit own request through FRS/portal or ask authorized staff/representative; confirmation explains collection purpose and what will be shared. Staff see safe action, not diagnoses. At event close, review outstanding obligations, de-identify/retain per policy.

Synthetic example: a 200-person reception has approved refreshment service, 12 guests request a particular meal option and 3 request step-free arrival assistance. Catering coordinator sees approved aggregate meal counts and a purpose-limited handover list only if needed. Usher sees assigned assistance action and permitted meeting location, not medical details or why the request exists. Host sees delegation arrival and authorized salutations. Vendor sees accepted task and required service totals, not organizer Registry or unrelated protocol. No guest needs hospitality enabled to receive invitations or attend.

| Surface | Safe default |
|---|---|
| EOC | Counts, readiness, outstanding exceptions within scope |
| Guest portal | Own confirmed service information and approved contact/help |
| Info Pult | Verified own directions and request referral only |
| Gate | Admission result, destination and authorized actionable assistance flag only if necessary |
| Catering vendor | Approved aggregate quantity/service task; no names by default |
| Print/exports | Minimal authorized service projection with revision and retention label |

All modes are projections over the same canonical records and commands. Quick Start is not a permission class, price tier, alternate storage model or waiver of domain rules. Guided mode adds relevant questions; Advanced exposes authorized settings and diagnostics. Mode changes do not themselves mutate domain facts, publish, send, reserve, approve or grant authority. Defer optional setup; distinguish not applicable, not enabled, not configured, blocked and ready. A user can resume a draft and switch modes without losing valid work. Show reasons and a permitted next action, not inaccessible target IDs. Use bs-BA/en, IANA timezone, locale-aware number/date display and immutable authored translations; no silent translation of legal or guest-facing meaning. All visual interactions have keyboard/non-drag equivalents. User preference, organization default, and event capability are separate.

## 4. Functional requirements

### HPG-01 — Optional service taxonomy and readiness

MUST support tenant-configurable allowlisted service categories (refreshments/meals, accessibility support, host/escort, delegation, transport, accommodation, reception/general request). Define purpose, owning event/session, responsible team, service window, capacity/unit, permitted fields, visibility, approval rule and retention. Separate capability enabled, configured, approved, ready and currently degraded. No service category mandatory for simple event; do not infer needs from guest category. OAC owns catalog/presets; event pins revision; deactivate for new use without deleting prior facts.

### HPG-02 — Service demand and headcount

Record planned aggregate count with source (manual estimate, approved RSVP/registration projection, accepted request), observed time and revision. Distinguish expected, invited, accepted RSVP, eligible, assigned, arrived, service requested, confirmed and fulfilled. No arithmetic assumes each invitation equals a meal or person; explicit accompanying guest and per-session policy. Avoid double count across party/delegation and repeated service windows; allow reviewed corrections and discrepancy reasons. Aggregate simple headcount works without individual guest list; never creates attendance, allocation or confirmed order.

### HPG-03 — Catering and menu coordination

Define approved service/menu options, serving windows, quantity/unit, supplier task, planned capacity/buffer, preparation and handover status. Collect only operationally necessary preference/restriction from guest/authorized representative, allow “not provided” and safe manual follow-up. Distinguish preference, reported allergy/intolerance and confirmed provider capability; no guarantee of food safety or medical classification, staff must verify actual supplier handling. Display actionable instructions and explicit unresolved/unsafe-to-confirm status, not diagnosis. Do not assign alternative meal automatically if reported restriction conflicts. Quantity review includes approved source and change diff; purchase/financial settlement remain owning commercial commands/manual. No personal dietary export to vendor unless explicit need and authorized scoped grant.

### HPG-04 — Accessibility and assistance

Support guest-reported/requested accessible seating, step-free route, interpreter/communication assistance, mobility support, companion and escort needs, or other limited action. Do not require diagnosis, infer disability or promise accessibility without validated venue data. Use #105 approved accessibility graph and #106 reviewed allocation constraints; unavailable route/position clearly shown and referred to responsible human. Request, verified feasible arrangement and actual assistance distinct. Restricted reason stays private; only action/meeting point/time/assigned operator shared where needed. No forced self-disclosure at public kiosk.

### HPG-05 — Delegation and accompanying guest coordination

Reuse event group hierarchy/roles, relationships, Registry and participation; delegation is event-specific grouping with lead/representative role, party size and approved service assignments, not new person database. Accompanying guests have explicit participation or approved count subject to event policy; distinguish unconfirmed estimated companions and identified participants. Lead may act only under explicit representative authority for permitted purpose, no group-wide data entitlement. Preserve each guest own RSVP/credential/attendance, separate communication and consent. Link/merge/correction via existing reviewed Registry commands.

### HPG-06 — Protocol and precedence

Support event-specific approved protocol categories, display title/salutation snapshot, precedence order, host role and placement preferences; rules must be transparent, versioned and tenant-approved, not inferred from name, nationality, religion, health or political affiliation. Separate honorific display from authority or eligibility. Map permitted seating preference/constraint into #106 owner; hard safety/capacity/accessibility constraints prevail, solver remains advisory, authorized human commit. Ties and conflicts visible with explicit review and reason; no autonomous ranking of people. Historic approved programme/cards retain pinned title/precedence; corrections do not rewrite prior output.

### HPG-07 — Host, escort and reception assignment

Assign eligible staff or accepted scoped operator to guest/group service task with meeting point, time window, allowed actions and handover; use EPW/existing task responsibility, no implied Registry or gate access. Separate assignment, acknowledgement, accepted handover, in progress, completion and unresolved exception. Changes require current permission and revision; revoked operator loses new access. No location tracking or surveillance; optional actual service time recorded by actor, not inferred from device movement. Guest-safe contact/help route only, no private staff details.

### HPG-08 — Transport coordination

Optional pickup/drop-off or arrival arrangement reference: approved meeting location, time window, capacity estimate, responsible party, vehicle/service reference where legitimate, status and task assignment. Use approved external transport arrangements and existing resource authority if tenant-owned; no live tracking, dispatch automation, route guarantee, passenger manifest disclosure or vehicle booking without separate authority. Distinguish requested/confirmed by supplier/guest notified/fulfilled. Share minimum operational itinerary to assigned provider and guest; do not expose home address unless necessary and explicitly authorized. Changes create reviewed history and CID notices only if policy.

### HPG-09 — Accommodation coordination

Optional rooming/service request references to externally arranged accommodation, dates, counts, provider confirmation reference and responsible task. No payment card/passport data by default, no automatic room reservation, hotel inventory or payment processor. Group/individual sharing requires consent/policy and scoped role. Aggregate room count vs confirmed external reference distinguished; supplier response evidence recorded without assuming guaranteed booking. Correction/cancel only through responsible party, no implicit event/guest cancellation. Preserve history and retention.

### HPG-10 — Service requests and assisted intake

FRS published guest service request or verified portal/self-service, staff/representative assisted intake. Purpose-bound request linked to event/participation where authorized or aggregate task; minimal typed fields, optional safe contact preference, notice revision, actual source and actor. `received → under_review → confirmed/declined/returned → assigned → in_progress → fulfilled/closed` with cancelled/exception and correction history; exact states reconciled with existing domain. Submission alone neither updates master profile nor confirms service. Guest can see own safe status and ask correction; no public enumeration. Requests can exist without digital contact; telephone/in-person route with attribution.

### HPG-11 — Review, capacity and fulfillment

Review request eligibility, feasibility, current approved service capacity, conflict with sessions/venue, minimum data and responsible party. Pin reviewed request/revision, service policy, capacity/reservation refs and decision digest. Serialize allocation of limited service units under owning constraint; one logical fulfillment allocation per approved subject/window, no oversubscription. If resource booking required, existing command commits separately with exact receipt, no phantom confirmed service. Track assigned and actual fulfillment, partial delivery, decline, waitlist/alternative and correction, reason restricted where appropriate. No auto-complete from message, scan or time.

### HPG-12 — Change and exception handling

Changed guest request, RSVP, schedule, seat, service provider or venue capacity triggers explicit impact preview and stale/needs-review state, not automatic reassignment, cancellation, meal promise or guest notification. Preserve previous confirmed arrangements until owner authorizes replacement or records unavailability; show current truth and approved next action. Targeted corrections and unresolved issue links EPW/#112; no operational security or medical emergency handling. Escalate to responsible human where support unavailable; no false readiness. Guest communication via CID separately eligible and reviewed.

### HPG-13 — Privacy classification and minimal projections

Treat dietary/allergy/accessibility and private accommodation/transport details as restricted by default, potentially highly sensitive. Collect purpose-specific fields only, separate health reason from action, use explicit notice and approved lawful basis/consent policy; no blanket collection from Registry. Encrypt protected values with tenant/event/purpose binding, no free text by default or unnecessary documents. Separate full restricted reviewer, operational assignee, aggregate vendor and guest own projections. Ordinary roster, gate, signage, Info Pult, logs, metrics, report builder and public print never include restricted values by default. Need-to-know grant, expiry/revocation, field read audit and retention/hold/redaction. No automatic cross-event reuse; explicit guest confirmation for current need and approved purpose.

### HPG-14 — Service communication and artifacts

Use TDS pinned localized template/brand/revision for approved meal count sheets, host/transport briefings, guest confirmation/directions and handover packs. CID handles eligible recipients and minimal content; use secure purpose-bound access instead of sensitive message body. Print job not handover; external provider acceptance not fulfilled service. Private artifact creation/download/reprint needs current scoped permissions; print manifest includes revision/freshness and safe handling; superseded outputs clearly identified. No public name/dietary combination or unrestricted PDF export.

### HPG-15 — Adaptive workspace and reporting

Quick aggregate service plan and standard counts, guided options/request review, advanced board for assignments/capacity/exception and protocol. Same canonical records, no extra permissions. RAI provides defined counts by session/service/state and planned vs confirmed vs fulfilled, privacy-aware aggregates and safe export. Small groups/rare service categories require suppression or wider aggregation when disclosure risk; no staff ranking, sensitive cross-event profiling or inference. EOC shows only authorized actionable readiness/exception; guest sees own permitted info, no list of others. Accessible keyboard/touch and bs-BA/en, no color-only status.

### HPG-16 — Lifecycle, corrections and recovery

Event closure reviews unfulfilled service tasks, outstanding supplier obligations, approved handover and retention plan. No auto settlement, refund, task completion or attendance; existing event owner closes through canonical command. Retain necessary historical receipts/revisions, correct or redact restricted fields per approved retention/hold, never silently rewrite approved output. Suspend/disable capability with open requests requires reviewed drain/reassign/close policy, preserve history and independent memberships. Restore reconciles pending tasks, reservations, private artifact access and potentially sent messages before resuming; no duplicate service fulfillment.

## 5. Workflow, transaction and failure semantics

### Service transaction and state boundaries

1. Configure service catalog revision and event/session window, optional aggregate estimate.
2. Collect approved FRS/portal/staff request and source/notice; store immutable submitted snapshot and safe receipt.
3. Reviewer resolves permitted subject, checks feasible service and current capacity, produces reviewed decision digest and minimal assignment projection.
4. Authorized confirm locks service window and applicable owning reservation/assignment in established order; verify scope, capacity, current policy/revision and idempotency. If separate domain reservation is required, record explicit pending/confirmed receipt and never report readiness until required outcomes known.
5. Assign EPW task to eligible operator and emit approved CID intent as separate controlled effect. Guest sees own confirmed arrangement only.
6. Operator records partial/fulfilled/exception with actual actor and evidence; corrections append new events, never fabricate attendance or supplier confirmation.

Service demand estimate, approved service allocation and physical fulfillment are separate projections. Pending or uncertain external outcome does not trigger duplicate order/reservation or automatic alternate. Do not hold database transaction across external provider calls. On schedule change, re-evaluate impacted approved requests and show review tasks; no implicit change of seat, booking, meal or accommodation.

| Exception | Required action |
|---|---|
| Reported allergy cannot be safely confirmed | Mark unresolved; route to authorized human/provider, do not promise safe meal |
| Step-free route not validated | Show no verified route, offer permitted assistance referral |
| Supplier task revoked | Block access, owner reviews reassignment and minimal data handling |
| Guest declines RSVP after confirmation | Flag impact and approved capacity release review; no auto cancellation or reassignment |
| Two staff confirm last service unit | Exactly one accepted unit; other explicit conflict/waitlist |
| Printed service sheet stale | Show revision superseded and controlled refresh; no silent rewrite |
| Missing digital contact | Staff-assisted/physical workflow remains valid |
## 6. Architecture and logical data model

Extend the existing Vue 3/TypeScript staff application, Fastify API/workers and PostgreSQL 18.6 modular monolith; no mandatory external SaaS or second database. Reuse domain commands, approved TDS renders, CID delivery, transactional outbox and scoped projections. Logical names below are candidates; inventory actual schema, role grants, lock order, indexes, views, current APIs and fixtures at M0. Add only missing extensions with forward migrations; no rewriting historical migrations, accepted ADRs or the v0.2 schema/OpenAPI snapshots. All tenant-owned keys include organization context; event references include event scope, verified by composite FK or equivalent command integrity. Cross-party references use explicit accepted grant/revision and permitted projection, never broad joins. Immutable published revisions, decisions, receipts and evidence retain source IDs; append correction/supersession rather than destructive rewrite. Sensitive values and private artifacts use authenticated encryption and purpose-bound identity; no secret in audit or general projections.

| Logical entity or existing aggregate | Principal fields / keys | Integrity and lifecycle |
| --- | --- | --- |
| Registry/event participation/group/relationship | existing org/event identity, pinned guest snapshot and group roles | Canonical; no duplicate persons or inferred authority |
| service_catalog/revision | org, typed service key, localized name, unit, allowed field/policy, default capacity | Immutable approved revision; tenant-owned |
| event_service_window/revision | event/session, catalog rev, location/time, capacity, owner, policy | Current approved head, no implied booking |
| service_demand_snapshot | window, source type/rev, aggregate count, observed time, estimate/approved marker | Definition/source pinned; no invented guest facts |
| service_request/revision | event, subject or aggregate, purpose, restricted encrypted values, notice/source, status | Immutable submission/correction; minimized data |
| service_decision/allocation | window, request rev, reviewer, digest, units, policy/reservation refs, state | Serialize capacity and uniqueness; independent task/booking |
| service_fulfillment_event | allocation, actor, action/units, time, safe evidence, restricted ref | Append-only; corrections reference original |
| protocol_profile/revision | event, category/title/precedence/preferences, reviewed rules | No inferred sensitive rank; #106 owns allocation |
| delegation service link | existing group/participation, service request or host task | Explicit representative scope only |
| transport/accommodation arrangement | event, service window, approved external ref, minimal location/count/status, responsible task | No automatic booking/payment; restricted details separate |
| service task/projection | canonical EPW task ref, allowed action/time/location, grant rev | Scope/purpose/expiry; no raw health data |
| service artifact manifest | approved source refs, brand/template revision, classification, digest/retention | Private access rechecked; printed ≠ handed over |

### Migration and compatibility

Audit existing tables and commands first; additive sidecar only where needed. Backfill through reviewed deterministic mapping with exception report, preserve existing IDs, historical snapshots and access semantics; default newly introduced capabilities to disabled/unconfigured unless existing equivalent facts justify activation. Test fresh install and populated upgrades, RLS and grants with runtime/auth/worker roles; old clients retain supported route behavior. No destructive down migration for recorded facts; recovery through tested compatible release or controlled restore and reconciliation. Add indexes for tenant/event/status/revision and due work; measure plans on synthetic representative cardinality; do not rely on client-side filtering.

## 7. API and permission contracts

Paths are relative to the existing API version; exact prefix, schema, codes and permissions determined after M0 inventory. Every staff route authenticates active user, selected membership, tenant, domain permission and object scope before lookup; delegated grants checked with current purpose, validity, projection and ceiling. Unknown/foreign IDs return non-enumerating error. Mutations use strict OpenAPI schemas, bounded input, CSRF/origin, expected revision and idempotency key scoped to tenant/actor/action; canonical request fingerprint binds reviewed inputs. Same key + same request returns original receipt only after current authority recheck; different request conflict. Stale revision/digest yields conflict and safe refresh, not silent override. Public capabilities are separate, opaque, high entropy, purpose-bound, expiring/revocable; store digest for lookup and minimal encrypted delivery envelope where required, fragment cleanup and no third-party referrer. GET/preview never issues credentials, publishes, approves, sends, reserves or changes business state. Use safe problem details/requestId, pagination with stable ordering and authorized filters; long jobs return 202 and receipt, not completed result. Recheck authority at job claim, artifact download, stream subscription/reconnect and consequential commit. Audit real actor/membership or scoped worker intent, purpose and outcome without plaintext sensitive data.

| Proposed operation | Input / result | Authority / effect |
| --- | --- | --- |
| GET /organization/services | authorized catalog/revisions and defaults | tenant service config/read |
| POST /organization/services/{id}/publish | typed policy/revision/digest | catalog publisher; no event activation |
| GET /events/{id}/hospitality | safe aggregate/window/readiness projection | event read; field/role filtering |
| POST /events/{id}/service-windows | catalog rev, time/quantity, owner, expected rev | event service manage; no reservation implied |
| POST /events/{id}/service-requests | purpose, subject/source, allowed values, idempotency | staff assisted or owning FRS capability, distinct token |
| GET /service-requests/{id} | permitted own/staff projection | scope before lookup; restricted read separate |
| POST /service-requests/{id}/review | expected rev, feasible options, excluded fields/digest | eligible reviewer |
| POST /service-requests/{id}/confirm | digest, units, approved refs, intent key | service confirm and resource owner if needed; locks |
| POST /service-allocations/{id}/assign | eligible canonical task assignment | EPW owner/grant, minimal projection |
| POST /service-allocations/{id}/fulfillment | actual units/status/evidence, expected rev | assigned operator/owner, no auto attendance |
| POST /events/{id}/protocol/review\|publish | typed precedence/preferences, expected rev | protocol manager; no seat commit |
| POST /events/{id}/arrangements/{id}/review | external confirmation/ref, minimum projection | authorized service owner; no external booking |
| POST /events/{id}/hospitality/impact-preview | changed source rev, affected items/reasons | authorized owner; no mutation |
| POST /events/{id}/service-artifacts | approved scope and revision → private job | report/export + restricted field authority as needed |
| POST /events/{id}/hospitality/close-review | outstanding obligations and retention plan | event/service owner; actual event close separate |

### Permission matrix

| Authority (proposed semantic permission) | Scope | Allowed / exclusions |
| --- | --- | --- |
| service.catalog.manage | organization | configure approved service taxonomy/defaults, no guest records |
| hospitality.read/manage | event/session | aggregate and safe service plan; restricted read separate |
| service.request.assisted | exact event/participation | attributed request, not review |
| service.restricted.read | purpose/field/exact subject | minimum protected values, audited, no blanket Registry |
| service.review/confirm | event/window | decision and capacity commit; separate booking authority |
| service.assigned.execute | task/grant | only assigned action, no unrelated details or approval |
| protocol.manage | event | review precedence/preferences, no solver commit or role assignment |
| representative capability | exact guest/group action | only explicit consent/authority and bounded scope |
| service.export | dataset and field scope | private authorized artifacts, no generic sensitive list |
| guest own capability | own request/status | safe submit/correct/status, no other person lookup |
| PAC support | scoped grant/expiry | redacted diagnostics, no unrestricted sensitive data |

## 8. Security, privacy and reliability

Threats: sensitive inference and profiling (no automatic derivation, no default cross-event reuse), small group disclosure (minimum cells and complementary suppression in reports), unauthorized vendor read (task projection/accepted grant, revocation recheck), false accessibility/food assurance (reported vs verified feasibility and explicit uncertainty), overbooking service units (transaction/uniqueness/capacity), duplicate supplier effect (idempotency and uncertainty review), stale seating/protocol (pinned revisions and current review), print leakage (private manifests, restricted field permission and safe physical handling), coercive collection (optional minimal purpose and notice), cross-party handover leakage (separate approved projection). Do not store medical records, operational security details, arbitrary identity documents or actual payment credentials. Guest can request correction and use assisted route without explaining sensitive reasons to ordinary staff. Legal and food/accessibility obligations require real tenant policy and professional verification; Eventor records evidence, does not certify compliance.

Never trust user-supplied tenant, role, target ID, template, route or scope. DB RLS and narrow commands protect data independently of navigation; deny direct writes and broad worker access. Use current membership/grant revocation ordering and reviewed successor ADR if changing authority. Outbox records commit with owning state, use tenant-scoped bounded consumers, lease/fence and deduplication; reconnect fetches authorized snapshot and cursor, gap triggers resync. Notification intents use CID with separately approved eligibility, content, costs and uncertainty handling; no automatic retry of ambiguous external submission. Sensitive data excluded from logs, metrics labels, URLs and public snapshots; no arbitrary JS, SQL, host shell, filesystem paths or external destinations. Review legal purpose, retention, correction, holds, redaction and portability with tenant; no claim of deletion from all backups. Tenant suspension denies new protected actions, preserves historical receipts and independent memberships. Local host recovery remains protected per PAC.

## 9. Quality, observability and deployment

Proposed fixture: 1,000 synthetic participants, 10 service windows, 200 requests, 20 concurrent reviewers/assignees, multiple external task grants. Authorized aggregate/service list p95 ≤750 ms, review/confirm p95 ≤1 s excluding external provider, EOC committed safe update p95 ≤2 s locally. 20 concurrent confirmations for last unit yield one approved allocation, no negative remaining capacity. Test restricted field absence in all generic roster/gate/Info Pult/signage/metrics and ordinary exports with canary values. Compare demand counts against fixed fixture, avoid duplicate party/session counts. Audit protected reads and corrections without values; monitor due/blocked/fulfilled counts and queue age only. Both deployment modes, isolated restore with pending task, capacity and uncertain CID intent; no repeat fulfillment or disclosure.

Targets are proposed measurements on documented synthetic fixtures/hardware/network, with actual p50/p95/error rate and query plans recorded; no performance assertion before test. Both native Linux and production Docker Compose use the same build/schema/fonts/config/security contract, dedicated non-root service roles, TLS, durable storage and secret handling. External integrations optional; local capture/manual path and trusted local-network operation where server reachable. Backup DB/assets/keys and job state consistently; restore in isolation, fence potentially completed work and reconcile before enabling side effects. Browser tests Chromium/Firefox plus supported mobile/Safari/device evidence where applicable; keyboard-only, screen reader, contrast, 200% zoom and 360/768/1280/1920 widths. Operational metrics scoped by tenant and coarse counts, no PII labels; record queue age, failures and bounded diagnostics.

## 10. Implementation milestones and ownership

Do not change current Codex #104/#112 foundation closure then #105 spatial, #106 allocation, #107 admission/Cockpit, #110 collaboration, #111 communications/forms/reporting, #108 dual installers in established roadmap order. Work packages refine owning slices, not a new parallel project or immediate task switch. Minimal safe defaults can ship before advanced editors. Every slice: audit, reviewed contract/schema, domain API, role-scoped UI, negative/concurrency/upgrade/browser tests and documentation. Do not mark schema as usable workflow. Keep all existing issue criteria; do not create unrelated closure gates. Final full acceptance VM Phase 9 after feature-complete candidate.

| Milestone | Deliverables and exit evidence | Existing owner |
| --- | --- | --- |
| HPG-M0 — Inventory and sensitive-data decisions | Audit roster/group/relationship/encrypted field and task/resource commands; service taxonomy, projection, privacy/retention and feasibility policy. | #104/#110 |
| HPG-M1 — Basic service planning | Optional headcount, catalog/window, simple checklist and approved service responsibility. | #110/OAC/AES |
| HPG-M2 — Request and review | FRS/assisted intake, minimal protected fields, reviewed capacity/fulfillment and scoped tasks. | #104/#110/#111 |
| HPG-M3 — Protocol and accessibility | Event-specific approved precedence/preferences, delegation/host coordination, #105 safe routes/#106 reviewed allocation. | #104/#105/#106/#107 |
| HPG-M4 — Extended coordination and outputs | Transport/accommodation references, AGIS guest-safe referrals, TDS artifacts, CID notices, RAI metrics. | #107/#110/#111 |
| HPG-M5 — Integrated acceptance | Privacy/revocation/restore, actual service feasibility and both installers, final full journey. | #108/Phase 9 |

### Issue reconciliation proposal (after owner approval)

| Existing issue | Scope clarification only |
| --- | --- |
| [#104](https://github.com/TeraflopsBH/eventor/issues/104) | Reuse identity, groups/roles/relationships and protected fields; service needs event-specific, reviewed profile update only. |
| [#105](https://github.com/TeraflopsBH/eventor/issues/105) | Verified accessible geometry/routes and service locations, no unverified accessibility claims. |
| [#106](https://github.com/TeraflopsBH/eventor/issues/106) | Approved protocol/accessibility preferences through owning allocation rules, human commit. |
| [#107](https://github.com/TeraflopsBH/eventor/issues/107) | Safe EOC and own guest help/Info Pult projection, no private reasons or attendance mutations. |
| [#110](https://github.com/TeraflopsBH/eventor/issues/110) | Primary guest-service tasks, supplier coordination, fulfillment and ordinary issue handover. |
| [#111](https://github.com/TeraflopsBH/eventor/issues/111) | FRS intake, TDS private artifacts, CID minimal notices and RAI scoped reports. |
| [#112](https://github.com/TeraflopsBH/eventor/issues/112) | Ordinary service change links disruption/booking command, no automatic cancellation/payment. |
| [#108](https://github.com/TeraflopsBH/eventor/issues/108) | Protected storage/recovery, both deployment modes and final acceptance. |

## 11. Measurable acceptance criteria and traceability

Use isolated synthetic tenants A organizer/hybrid, B independent partner, C provider-only; distinct authorized/preparer/reviewer/revoked actors, fake guests/contacts, fixed clock with DST edge, approved synthetic venue/plan and local delivery capture. Test exact-head CI and post-merge CI; run domain command/DB, API, real browser and concurrency/fault/restore tests as indicated. Capture candidate SHA, fixture revision, role, request/receipt IDs, expected/observed counts and redacted artifacts, measured times and actual hardware/provider evidence where applicable. No mock is proof of external compatibility; optional skips not passes. A test is pass only if every required result holds; failed/blocked/N/A explicitly reasoned and authorized, no waiver of security/integrity.

| ID | Requirement | Fixture / precondition | Action | Expected measurable result | Evidence | Related acceptance / scope |
| --- | --- | --- | --- | --- | --- | --- |
| HPG-AC-01 | HPG-01 | Simple meeting with hospitality disabled | Create and operate event | No service setup required; no service records | E2E | AES/OAC |
| HPG-AC-02 | HPG-01 | Retire service catalog used by historic event | Open old/new setup | Old pinned revision retained; new use blocked | DB | OAC-11 |
| HPG-AC-03 | HPG-02 | Fixture with 20 people, 2 companions, repeated sessions | Compute approved demand | Exact defined counts per window; no duplicate/no attendance mutation | Unit/DB | RAI |
| HPG-AC-04 | HPG-02 | Manual aggregate only, no guest list | Save headcount | Valid estimate with source; zero guest records | E2E | AES |
| HPG-AC-05 | HPG-03 | Guest reports restriction; supplier capability unknown | Review meal request | Unresolved status, no guaranteed safe meal or automatic substitute | Browser/API | OLA-09 |
| HPG-AC-06 | HPG-03 | Catering vendor granted aggregate task | Read/export service projection | Approved counts only; no names/restriction values | API/export | OLA-10 |
| HPG-AC-07 | HPG-04 | Unvalidated accessible route | Request directions | No invented route; explicit referral | Browser | AGIS-10 |
| HPG-AC-08 | HPG-04 | Approved accessible seating request | Apply placement preference | Only reviewed #106 command may change seat; human commit | DB/API | ADR 0003 |
| HPG-AC-09 | HPG-05 | Delegation lead without representative grant | Read/respond for others | Denied; no other guest disclosure | API | ADR 0006 |
| HPG-AC-10 | HPG-05 | Approved accompanying count | Review service demand | Counts distinct from named participants; no credential/RSVP created | DB | OLA-09 |
| HPG-AC-11 | HPG-06 | Protocol rule with sensitive inferred rank | Publish policy | Rejected; only explicit approved categories/preferences | API | OLA-11 |
| HPG-AC-12 | HPG-06 | Precedence conflict with capacity/accessibility | Review seating proposal | Hard constraints prevail; no auto commit | DB/solver contract | ADR 0003 |
| HPG-AC-13 | HPG-07 | Host assigned then revoked | Read/acknowledge task | Denied after revoke, original attribution retained | API/DB | OLA-10/11 |
| HPG-AC-14 | HPG-08 | Transport request without provider confirmation | View guest itinerary | Requested/pending, not confirmed; private address absent | API/browser | CID/UX |
| HPG-AC-15 | HPG-09 | Accommodation count only | Review external arrangement | No hotel booking/payment, exact pending/confirmed evidence | DB | OLA-07 |
| HPG-AC-16 | HPG-10 | Guest no device/email | Staff records service request | Actual source and actor, no profile auto-update | E2E | FRS/CID |
| HPG-AC-17 | HPG-10 | Own portal vs foreign request token | Resolve request status | Own minimal status only, foreign denied | API | AGIS/FRS |
| HPG-AC-18 | HPG-11 | One remaining service unit and 20 confirmations | Concurrent commit | Exactly one allocation; no oversubscription | DB race | OLA-14 |
| HPG-AC-19 | HPG-11 | Fulfillment partial and later correction | Record actuals/correct | Original events retained; correct current units; no attendance | DB | ADR 0005 |
| HPG-AC-20 | HPG-12 | Schedule/seat change after confirmation | Impact preview | Affected review items only; no automatic booking/seat/service change | API/DB | #112 |
| HPG-AC-21 | HPG-12 | Unknown supplier outcome | Retry/alternate proposal | No blind duplicate; review required | Fault | CID |
| HPG-AC-22 | HPG-13 | Restricted canary values in request | Read roster/gate/kiosk/signage/export as ordinary staff | Zero canary leak, restricted read denied | API/browser/export | OLA-11/13 |
| HPG-AC-23 | HPG-13 | Legal hold + purge race | Attempt delete protected details | Hold blocks purge; scoped correction/history | DB race | OLA-13 |
| HPG-AC-24 | HPG-13 | Prior event dietary need | Create new event from template | No copied sensitive request or consent | DB | EPW/AES |
| HPG-AC-25 | HPG-14 | Approved service sheet then revision change | Render and refresh | Historical digest retained; stale indication; no handover inferred | Artifact/DB | TDS/AGIS |
| HPG-AC-26 | HPG-14 | CID accepted service notice | Inspect fulfillment | No fulfillment or guest RSVP mutation | DB | CID |
| HPG-AC-27 | HPG-15 | Rare service category within small group | Run general report | Suppressed/aggregated per policy; no restricted detail | Report/export | RAI |
| HPG-AC-28 | HPG-15 | Keyboard/mobile bs-BA/en | Create simple headcount, review request | All essential actions accessible, truthful status | Browser/manual | UX-AC-13 |
| HPG-AC-29 | HPG-16 | Open unfulfilled task on disable/close | Review impact | Explicit drain/block/handover; no false completion or deletion | E2E | OAC-22 |
| HPG-AC-30 | HPG-11, HPG-13, HPG-16 | Restore pending allocations and restricted artifacts | Resume both modes | No duplicate allocation/fulfillment, access rechecked, uncertainty retained | Host/VM | OLA-15 |
| HPG-AC-31 | HPG-02, HPG-11, HPG-15 | Reference 1,000-person fixture | Measure counts and latency | Defined totals match, p95 measured and target assessed | Load/DB | OLA-14 |

### Requirement-to-acceptance traceability

| Requirement | Acceptance suffixes | Owning topic |
| --- | --- | --- |
| HPG-01 | 01, 02 | Optional service taxonomy and readiness |
| HPG-02 | 03, 04, 31 | Service demand and headcount |
| HPG-03 | 05, 06 | Catering and menu coordination |
| HPG-04 | 07, 08 | Accessibility and assistance |
| HPG-05 | 09, 10 | Delegation and accompanying guest coordination |
| HPG-06 | 11, 12 | Protocol and precedence |
| HPG-07 | 13 | Host, escort and reception assignment |
| HPG-08 | 14 | Transport coordination |
| HPG-09 | 15 | Accommodation coordination |
| HPG-10 | 16, 17 | Service requests and assisted intake |
| HPG-11 | 18, 19, 30, 31 | Review, capacity and fulfillment |
| HPG-12 | 20, 21 | Change and exception handling |
| HPG-13 | 22, 23, 24, 30 | Privacy classification and minimal projections |
| HPG-14 | 25, 26 | Service communication and artifacts |
| HPG-15 | 27, 28, 31 | Adaptive workspace and reporting |
| HPG-16 | 29, 30 | Lifecycle, corrections and recovery |

### Release integration

Add the above evidence to applicable OLA scenarios and G1–G9 gates without replacing existing OLA/PAC/OAC/UX/TDS/AGIS/CID criteria. G1 CI, G2 independent organization, G3 isolation, G4 configuration/content/output, G5 cross-domain journey, G6 resilience/accessibility, G7 deployment/recovery, G8 external evidence when applicable, G9 traceability/release defects. Provider-only, simple organizer and complex hybrid journeys remain independently usable. Actual supported devices, deployment and external provider acceptance only in planned Phase 9; automated tests incrementally in owning slices.

## 12. Open decisions and proposed integration

Decide service taxonomy, capacity unit and release semantics, guest/representative authority, menu/food restriction classification and responsible supplier confirmation, accessible route verification, minimum actionable field projection, actual tenant protocol precedence (never infer), transport/accommodation retention, notice/lawful basis and protected read audit, small-cell rule, artifact physical handling and service closure policy. Validate actual GHB venue, staffing, services, contracts and legal obligations with tenant. No medical diagnosis, certification, travel/payment booking or full commercial/financial system is implied.

Before implementation, owner/tenant validates real capacities, legal/retention policies, staffing, commercial rules, programme, identity and accessibility needs; no fictional examples become GHB configuration. Engineering reviews candidate libraries, licensing, exact route/schema/role choices, security threat review and performance envelope when scheduled. Do not modify accepted ADRs except through reviewed successor. Once owner approves, integrate complete source verbatim at stated destination, record approval and original SHA-256/blob externally in [design index](README.md). Add dated additive cross-references in architecture, roadmap, gap analysis, relevant approved designs and mapped existing issues, retain historic source checksum references and all existing issue requirements. Verify complete docs-only Git tree diff, source read-back, link resolution, required exact-head CI and post-merge CI; no runtime code, migrations, OpenAPI, workflows, Blueprint v1.2, PROJECT_STATE, Codex branches, environment or early VM change. Future consolidated Blueprint v1.3 separately approved; no requirement silently dropped.
