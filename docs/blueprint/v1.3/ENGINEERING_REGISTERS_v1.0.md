# Eventor — Shared engineering registers v1.0

**2026-11-27 — consistency companion to approved Blueprint v1.3.** Read [reconciliation and open decisions](DESIGN_CONSISTENCY_RECONCILIATION_v1.0.md) and [blueprint](Eventor_Technical_Blueprint_v1.3.md) before use. These are consolidated semantic navigation/check registers, not executable schema, endpoint or permission changes. Existing accepted ADRs and exact current contracts govern implemented behavior; all source-specific requirements and acceptance cases remain cumulative. A field or state not repeated here is not removed. All unresolved exact mappings are checked during owning M0, without disrupting the existing development sequence. No acceptance results recorded here.

## ER-01 — Canonical domain ownership

| Owning domain | Authoritative records / effects | Consumers and boundary |
|---|---|---|
| Host / installer | Service identities, protected host commands, deployment keys, versions/migrations, recovery manifests | PAC requests/status; no application root, arbitrary shell, SQL or Docker socket |
| Identity / access | Global account, membership, session, scoped role/permission, enrollment and host managed-access provenance | PAC/OAC use same authorities; no implicit confidential access, OD-01 |
| PAC | Platform policy, governance, tenant provisioning, approved support and optional shared provider service | OAC/tenant scope separate; no direct tenant business mutations |
| OAC | Organization preferences, readiness, allowed capabilities, role configuration, owned branding/administrative settings | AES/UX compose; actual permission and owning publication independent |
| AES / UX | Presentation preference, setup draft, safe preset application/review receipt | Existing event ID/commands; EPW owns reusable planning template; no hidden side effects |
| Provider / booking | Catalogue, booking inquiry/draft/offer/customer decision/approval, holds/reservations, confirmed commercial facts, cancellation effect, provider notices | Organizer links explicit; EPW/HPG requests only; FRS maps reviewed intake; RAI reads |
| Event / session | Event identity, schedule, capability policy, lifecycle, event-owned booking association and disruption decision/receipt | Production, guest, admission, communication and reporting use scoped references |
| Collaboration | Grant proposal/revision/acceptance/revoke and allowed projection | No access inferred from event, booking, supplier, role label or association |
| Registry / participation | Reusable person/contact/reference/label/relationship, reviewed merge/restore, event participation and pinned identity | FRS proposes mapping; HPG requests and protocol, invitation and attendance separate |
| Spatial | Venue template/native geometry, source artifacts, resource identity, approved capacities and sanitized map/route | Allocation uses approved resources; AGIS current approved destination; no source annotation treated as approved capacity |
| Allocation | Constraints/locks/proposal runs/approved plan/assignments/publication/reflow | Solver advisory, human command; portal/AGIS/TDS current authorized projection; EPW/HPG only reviewed input |
| EPW | Production plan, schedule coordination, typed dependencies, tasks/shifts/cues/readiness, safe templates/recurring drafts, approval coordination/issue/handover | Reuse actual tasks/domain approvals; no task implies booking/attendance/payment; external CDI status only |
| FRS | Purpose-bound form schema/revision/intake/receipt/review/mapping, registration/waitlist and accreditation decision | TDS appearance; owning Registry, RSVP, booking, HPG and task apply; no auto identity merge, grant, pass or attendance |
| Invitations / RSVP | Invitation revision, purpose capability and response history/current projection | CID route/evidence independent; registration/participation/eligibility/attendance distinct; portal its own scope |
| HPG | Optional service demand/request/review/arrangement/fulfillment/correction, explicit protocol/assistance refs | Registry identity, booking resources and EPW tasks canonical; vendor gets minimum actionable projection; no medical or financial system |
| AGIS | Admission credential, attempt, authoritative attendance, station profile/device/lease/assignment, provisional capture/reconciliation | Info Pult/portal lookup read-only; printing receipt distinct from handover; EOC consumes authoritative counts |
| TDS | Typed template/content/brand/assets, immutable render input/output manifests and private artifacts | FRS validates form fields; RAI defines metric/result; CID sends; AGIS issues/replaces pass; rendering never mutates domain |
| CID | Reviewed communication intent/audience/route/attempt, provider evidence, preferences/consent, budget, reconciliation | Existing domain queues reused; no business approval, RSVP, attendance or fulfillment via transport |
| EOC | Authorized event operational projection, alert/assignment/intervention coordination and freshness | Reuses owning commands and shared realtime invalidations; no duplicate aggregate; RAI semantics |
| RAI | Approved dataset/metric/report/dashboard/schedule definitions, authorized query/result and artifact manifest | Reads owning facts, TDS appearance, CID distribution; no arbitrary SQL or domain write |
| Shared integrity | Audit provenance, idempotency receipts, transactional outbox, lease/fence, artifact authorization/retention | Each owning command retains transactional authority; shared infrastructure not universal bypass |

Source anchors: B13-DATA/API, approved addenda and source-range register; current [architecture](../../ARCHITECTURE.md), [operating model](../../OPERATING_MODEL.md), [database design](../../database/SCHEMA_DESIGN_v0.3.md) and [API design](../../api/API_DESIGN_v0.3.md).

## ER-02 — Permission and principal catalogue

Semantic authority, not proposed code installation. Verify current role codes, scope_kind, field policy, actor/principal type, actual grant path and downstream checks. Separate action checks may be composed in roles only when reviewed. No new automatic platform inheritance (DC-01). Every protected command, replay, job, callback correlation, subscription and artifact access enforces appropriate current authority. External callbacks are evidence, never staff grants.

| Principal / semantic permission family | Allowed actions when explicitly authorized | Independent checks / deny boundary |
|---|---|---|
| Host operator | bootstrap/host flag/recovery/maintenance/release | protected local boundary, actual host DB principal; no tenant impersonation |
| Platform owner / delegated PAC | tenant provision, typed policy, safe metadata, shared service management | no implicit raw tenant data; separate support grant and owner approval OD-01 |
| Tenant owner / OAC admin | org policy, member/role administration, feature config | delegation ceiling, last-admin, no platform flag; restricted fields separate |
| Staff / partner | exact event, booking, task or accepted grant | no permission from membership, title, booking link, mode or label alone |
| Setup author / applier | draft, preset review and explicit apply | owning event/create/config permission, no implicit approve/send |
| Booking prepare / offer issue / approve / confirm / cancel | exact owned booking lifecycle | separate checks, approved policy, actual actor, customer decision separate |
| Event manager / plan approver | event/session lifecycle, production/approval coordination | approved resource/plan/booking owners; no solver auto-commit |
| Registry read/edit / protected field / merge/restore / export | scoped profile and explicit review/transfer | event-only access not tenant Registry; encrypted field and separate export |
| Spatial author / capacity approver / plan publish | geometry, capacity confirmation, publication | approved venue authority, source evidence, no unapproved allocation |
| Allocation propose / edit / approve / publish | bounded proposal/manual revision and commit | same invariants, lock/constraint/expected revision; no solver write |
| FRS author / publish / review / mapper | typed definition, inbox, purpose apply | no submissions via author privilege; private attachment authorization; capacity and owning command |
| Invitation issue / RSVP staff record / portal access | distinct purpose and actor | no automatic admission; credential transport not permission |
| HPG coordinator / supplier | exact service/arrangement, minimum assigned projection | no unrestricted health/profile/Registry data or payment |
| AGIS operator / device | exact event/session/station mode/action/lease | operator and device checks separate; lookup no attendance, scan confirmation per policy |
| TDS author / reviewer / publisher / asset admin / preview / render | approved typed purpose/content and output | no recipient read, issuance or delivery implied; private artifact access |
| CID provider admin / prepare / approve / send / worker / reconcile | account/purpose/route/budget and reviewed recipients | write-only secrets, current consent/grant, no blind fallback or business effect |
| RAI dataset.read / aggregate / definition / publish / run | typed allowed query, field/aggregate, scoped report | separate preview/data rights; no arbitrary joins; no owner access by widget |
| RAI export generation / artifact download / share | separately evaluated semantic operations (exact codes OD-05) | current source/field/scope/expiry at download; share independent; suppression |
| RAI schedule prepare / approve / CID distribute | exact reviewed recurrence/audience/route | current recipient/source authority, independent send permission |
| Public / guest / applicant / customer | bounded purpose token, own minimal projection, explicit permitted submit | no staff privileges, cross-purpose reuse, enumeration or GET mutation |
| Provider callback / job service | authenticated correlation and bounded work | exact account/intent, lease/fence, current scope; evidence not domain authority |

Principal scope checks: before private lookup, under locks for mutations, on lease claim and before external side effect, on current artifact download, retry/receipt, reconnect/stream, and revocation. Retain separate principal classes and audit actual actors. Current [roles catalogue](../../product/USER_ROLES_AND_PERMISSIONS_v0.1.md), ADR 0015 and B13-API/DATA/SECURITY are controlling; table is not a grant list.

## ER-03 — Lifecycle and state transition vocabulary

Illustrative semantic states; actual enum and transition names resolved by existing contracts and exact domain sources. Do not introduce generic state engine or map unlike facts to one status. Every material mutation has owning guard, expected revision/locking, audit/receipt and idempotency as specified.

| Lifecycle | Distinct stages / facts | Prohibited conflation |
|---|---|---|
| Organization / membership / session | provision/setup → active → suspend/archive per policy; member invited/accepted/active/suspended/restored; session authenticated/revoked/expired | restoring membership does not restore session; suspend not booking cancellation |
| Capability readiness | installed/supported, allowed, enabled, configured, ready/degraded, actor authorized | not applicable/not started/in progress/blocked/ready; navigation not access |
| Setup draft | save/resume → preview/review → explicit apply → per-step receipts | autosave or preset not event publication/confirmation/send |
| Booking | inquiry → reviewed draft/revision → offer issued → customer decision; required approval independently; explicit confirmation with reservation | customer acceptance, approval, availability or delivery not confirmation; no-hold exception only approved |
| Booking cancel/amend | request → review/decision → execution/effect/obligation; superseding revision | request/approval/notice/acknowledgement not effective cancellation/refund |
| Event/session | draft/planning → authorized approval/publication → actual start/close/archive; disruption decision/affected session separately | linked booking not event lifecycle; cannot bypass required review |
| Collaboration | proposed → recipient review/accept → effective grant → revoke/expire | grant proposal/association not authority; no reactivation of ended link |
| Registry | active/archive/merge/restore/anonymize as authorized; reviewed source and destination | history not rewritten; no deleted value reconstruction |
| Geometry/plan | source import/trace → draft → approved capacity and publish; plan proposal/diff → review → publish/supersede | source count not approved capacity; solver feasible not published |
| FRS | draft/review/publish/retire form; submitted/under review/returned/accepted/rejected/withdrawn; applied owning receipt | submission/approval not apply; registration/waitlist not attendance or seat |
| Invitation / RSVP | issue/revoke/replace; delivery attempt; response append/change per pinned policy | no email prerequisite for scope; RSVP-disabled invitation may have no RSVP token; delivery/read not response |
| Portal / admission pass | purpose-bound access/active validity/revocation/expiry; pass separate | credential possession not verified identity; reprint/refresh not replacement |
| Gate | validation → confirm if required → accepted/duplicate/rejected/unknown/provisional attempt; authoritative arrival/departure/correction | validation/lookup/provisional/local eligibility not authoritative attendance |
| EPW | planned task/shift/cue; acknowledged/assigned/completed/corrected; approval review/decision/execution distinct | task completion not actual staffing/payroll/service fulfillment or business approval |
| HPG | estimated/requested/reviewed/confirmed/allocated/fulfilled/unmet/cancelled/corrected | demand not confirmed, confirmed not fulfilled, service not payment |
| TDS | draft/review/approve/publish/retire; preview/render/artifact/print/handover | publish not issuance/send; print submitted not handover |
| CID | intent/audience review → scheduled/queued → attempt/submitted → accepted/delivered/read verified or failed/suppressed/uncertain; manual evidence separate | accepted not delivered; uncertain not definite failure; approved idempotent replay only under DC-05 |
| EOC | alert raised/acknowledged/assigned/escalated/resolved/closed, intervention through owner | acknowledge not resolution or domain mutation |
| RAI | definition revision/publish → query/run/result → private artifact → scoped download/delivery → retire/expire | export not share, stale snapshot not current, missing history not zero |

## ER-04 — Shared glossary

| Term | Meaning |
|---|---|
| Person / participant | Reusable tenant Registry identity / event-specific participation with own snapshot; not interchangeable |
| Provider / requester / contracting party / organizer / operator | Distinct responsibilities; may coincide but no inferred data authority |
| Organization owner / platform owner / host | Independent tenant governance / installation governance / protected infrastructure operator |
| Scope / role / capability / readiness / mode | Exact object/field/action context / granted authority grouping / available feature / operational prerequisites / presentation preference |
| Review / approval / execution | Examine exact revision / authorized recorded decision / owning command applying effect; separate unless exact approved contract atomic |
| Preset / template / revision | Suggested setup configuration / reusable versioned content or planning definition / immutable published snapshot |
| Hold / reservation / availability | Time-bounded conditional hold / committed resource claim / advisory preview; no-hold exception per approved resource class |
| Capacity / estimated count / assignment | Approved maximum / planning estimate / actual scoped allocation; no inferred equivalence |
| Seat / row / zone / resource | Precise allocatable position / grouping / bounded area or pool / authoritative reservable or allocatable object as typed |
| Registration / accreditation / eligibility | Reviewed application acceptance / approved purpose access scope / owning decision permitting action |
| Invitation / RSVP / credential / attendance | Issued communication identity / response history / purpose-limited access proof / authoritative recorded event presence facts |
| Info Pult | Guest-safe self-service or staffed information station; no general directory, no automatic check-in |
| Offline local validation / deferred capture | Bounded local snapshot eligibility / queued provisional intent; neither server-confirmed |
| Reprint / refresh / replacement | Reproduce exact artifact / render new current approved artifact / revoke and issue new credential explicitly |
| Provider accepted / delivered / read / manual handover | Distinct verified external or attributable manual evidence; no inference |
| CDI | External prerequisite coordination and approved status/receipt only; no inspection/security command |
| Historical as-of / archived artifact | Source-supported historical reconstruction / retained immutable result; may not be interchangeable |
| Unknown / suppressed / N/A / zero | Insufficient evidence / protected value / explicitly inapplicable / known numeric zero |
| CI pass / acceptance pass | Covered automated regression / actual requirement-specific evidence on release candidate; not interchangeable |

## ER-05 — Capability dependency and adaptive experience matrix

Dependency check uses supported release, deployment policy, org enablement, event applicability and minimum current owning prerequisites; actor authorization remains independent. This is a minimum semantic matrix, not a substitute for typed DAG/disable impact catalogue. No forced advanced configuration. When a required dependency is unavailable, show why and safe alternative; never fake readiness. See ADR 0004 and AES/OAC/UX.

| Capability | Minimum relevant dependency | Not required merely to use it |
|---|---|---|
| Provider booking | provider-owned resource/catalogue, applicable booking policy | operational event, Registry, solver, guest app, SMTP for manual workflow |
| Minimal event | existing event draft validation/authorized owner | booked venue, precise drawing, guests, invitation, station, provider |
| Registry | selected org authority; participation requires target event | email, RSVP, QR or booking for every person |
| Simple spatial | approved room/capacity where relevant | detailed drawn geometry before basic workflow |
| Allocation | relevant approved resources/capacity, event/participation, applicable rules | solver for manual; exact seats for zone/count allocation |
| FRS registration | allowed purpose/published revision, target and capacity policy | QR, seat, external mail, auto merge |
| Invitation / RSVP | eligible subject and approved invitation/response policy; applicable authorized path including manual | email or registration studio; RSVP token if response not applicable |
| Guest portal | enabled own purpose and safe content | exact seat if general directions allowed; external internet on LAN |
| Admission | explicit eligible participation, separate credential or authorized manual policy, station/actor | RSVP yes alone not sufficient; seating only if policy requires; external cloud |
| Info Pult / display | station mode, minimal approved projection and verification where personal | admission mutation, guest directory, full internal geometry |
| EPW production | event/booking task owner and typed planning scope | confirmed reservations before draft; no automatic creation |
| HPG aggregate | event/service context and permitted count | guest list or sensitive data for refreshments estimate |
| TDS | purpose, allowed content assets and publishing authority | guest modules for booking correspondence; no delivery provider for preview |
| CID | reviewed owning intent, eligible route/current authority and policy | paid service for manual/in-app; no other channel solely because one configured |
| RAI | authorized dataset/metric, actual source evidence | all modules enabled; no Advanced builder for standard report |
| PAC/OAC / installer | protected bootstrap, typed configuration and role policy | external IdP/paid cloud, arbitrary host commands; both packaging modes same build |

Quick Start, Guided and Advanced share all domain commands, event identity and validation. Presets copy allowlisted configuration only; preview/review/apply, stale digest/CAS, per-step receipt, explicit publication and optional capability enable/disable impact, safe isolated synthetic training. Exact DAG and profile defaults scheduled with owning M0.

## ER-06 — Non-functional targets and reference envelopes

Preserve exact original NFR and addendum measurements. No number in this register is an achieved SLO or universal production requirement. Targets are measured on declared hardware, data, concurrency, network, clocks, workload and supported device/browser; record p50/p95/error/throughput and limits. More specific targets apply to their own workload; do not average or substitute unrelated benchmarks. Adjust only through recorded reviewed decision, preserving safety floor.

| Source | Measurement / provisional input | Verification |
|---|---|---|
| BP12 NFR-01, §38.5 | Typical 10k guest filter/search <2 s; simple Registry/event p95 <500 ms on agreed LAN | distinguish fuzzy jobs and exports |
| BP12 NFR-02–05 | ≥50 concurrent authenticated staff initial sizing; representative simultaneous gates; 1,000 guests/several thousand resources/rules; planned 99.5% event window availability with stated infrastructure exclusion | sustained load, zero duplicate authoritative effects, solver statuses, uptime evidence |
| BP12 §38.5 | Online QR p95 <2 s; portal main content ≤3 s; EOC incremental p95 ≤2 s, reconnect snapshot ≤5 s after stable connection | target network/mobile profile, exact commit-to-client and stale indication |
| BP12 NFR-06–12 | measured DB/file/key recovery with deployment RPO/RTO; material/sensitive audit; accessible keyboard/contrast/zoom, Firefox/Chromium/Safari as supported, UTF-8 bs-BA/en, native and Compose, documented APIs/tests/logs | actual evidence; no assumed certifications |
| AES §9 / AC-27 | 30 representative attempts; median ≤120 s and ≤4 required steps; p95 reported; readiness p95 ≤500 ms/save ≤750 ms at 50 concurrent; 20 identical create requests zero duplicates | ready tenant fixture, exact draft receipt |
| PAC original §19 / integrated §19 | reference 4 vCPU/8 GiB/SSD candidate; 100 org/10k staff first-50 directory p95 ≤1 s; bounded overview p95 ≤2 s; health 30 s refresh/90 s stale; recent auth 5 min; emergency max 30 min/support default 60 min; daily verified backup and 24 h/4 h candidate RPO/RTO | OD-02 explicitly preserve original proposals for M0 review, no binding SLA or authorization duration now |
| TDS §§11,13 | reference host candidate; ≤1 MiB/2,000 nodes/depth 24, component depth 8, raster ≤15 MiB/40 MP, preview p95 ≤3 s, save ≤500 ms, ~1 s debounce, ≤500 recipients/job partition larger with review, synthetic preview expiry candidate 24 h | actual font/output/PDF/client compatibility, safe queue/renderer sandbox, M0 benchmarks |
| EPW §9 | 500 tasks/1,000 edges/100 cues/30 staff/2 partner orgs/100 bounded occurrences; graph p95 ≤2 s, assigned list ≤750 ms, EOC ≤2 s; concurrency 20 identical intents | bounded acyclic graph, per-occurrence receipt |
| AGIS §17 / §22, CID §25, FRS/HPG/RAI §9, OAC/UX quality sections | Exact detailed workload and limits in source sections, including offline candidate lease/count/storage, actual gate/device/print, delivery/queue, form, service and dataset/export limits | owning M0 confirms reference envelope; all applicable exact AC IDs retained, no replacement by generic NFR |
| Security floor | zero tested cross-tenant unauthorized disclosure and duplicate authoritative commits; no arbitrary SQL/JS/host access; current revocation/lock/lease checks; no hidden blind external replay | negative/concurrency and failure tests, not waived for performance |

## ER-07 — Release acceptance and external evidence

OLA G1–G9 and every source acceptance ID remain cumulative. Test states: not_run, pass, fail, blocked, explicitly owner-approved non-applicable (N/A), with evidence; all rows below **not run for final release candidate**. Existing successful CI is only covered regression evidence. Actual release acceptance is Phase 9 after coherent build and both installers.

| Gate | Mandatory release evidence | Conditionality |
|---|---|---|
| G1 | exact-head and post-merge 5 required CI; integration and populated upgrades | never substitute old head or skipped required test |
| G2 | independent onboarding, provider-only/organizer/hybrid, same event through Quick Start expansion | no routine SQL, safe permissions |
| G3 | isolation, role/field/grant/device/credential security, actual actor, revocation, support/restore; OD-01 before PAC release | no critical safety waiver |
| G4 | TDS rendering/brand, FRS typed intake/review, CID channels, AGIS printing; original TDS/PAC full evidence | conditional per purpose, required product capability retained |
| G5 | end-to-end booking and organizer event, explicit collaboration, spatial/solver, attendance, EPW/HPG/RAI | synthetic independent organizations; no unrelated module prerequisites |
| G6 | accessibility/locale/performance/failure/concurrency, both offline modes and recovery as planned | strict mode per event allowed; product omission explicit approval |
| G7 | native Linux and production Compose clean install, upgrade, private DB/assets/key backup/restore, host recovery | both modes required, actual target |
| G8 | actual public HTTPS and external SMTP sandbox, advertised supported adapter/hardware evidence below | skipped is not pass; explicit conditional extension N/A only |
| G9 | all applicable original and consolidated cases traced, candidate/version/config/evidence, unresolved defect/limits and owner decision | no release-blocking defect or unapproved scope omission |

| Channel / mode | Required product support | Actual final evidence / optional activation |
|---|---|---|
| Intranet/local capture, manual digital share/print/post/handover/phone | Yes | actual supported manual workflow and receipts, no external account necessary |
| In-app delivery | Yes | authorized inbox, current scope/read vs evidence |
| SMTP | Yes | approved external sandbox delivery plus local capture; verified TLS/auth/headers per supported relay |
| HTTP email API | Yes | approved supported reference adapter/account, actual submission/correlation/reconciliation |
| OAuth-capable email | Yes | supported actual account authorization, token rotation/revoke and submission; not every provider promised |
| SMS | Yes | actual approved reference gateway delivery/evidence as supported, segmentation/consent/cost |
| WhatsApp | Yes | official supported business account/template policy and actual sandbox/provider evidence |
| Viber | Yes | official supported business/bot account mode, eligibility and actual evidence |
| Web push | Yes | opt-in supported browser subscription, delivery/expiry/revoke; no read inference |
| Telegram | Optional | if advertised, actual approved bot/binding tests; otherwise explicit disabled N/A |
| Public HTTPS | Supported opt-in | actual target HTTPS/security-header/public route and staff ingress isolation evidence |
| Admission/print | Supported target hardware | actual camera/HID/manual, print dimensions/decode/handoff and degraded modes |
| Native and Compose | Both required | same release/config/security/migrations, actual clean install/upgrade/restore |

No tenant is required to activate external providers. Inability to obtain provider account, unavailable network or skipped optional CI probes is not a pass for required release evidence. Document blocked status and plan approved test arrangement or explicit scope decision; never unilaterally omit product scope. Existing OLA, CID §27, AGIS §24 and all source-specific tests control. Record actual evidence with commit, build, schema/config, fixture/hardware/clock/network, expected and observed result, trace ID, reviewer, defects, restrictions and time. Use synthetic fixtures, approved real provider sandbox only with appropriate accounts and no live guest data.

## ER-08 — Outstanding decisions and work-package mapping

| Gate / ownership | Existing decisions to review before affected slice | Constraint |
|---|---|---|
| Current #104/#112 | existing event/session/Registry/booking/collaboration work, AES minimal draft and readiness compatibility | no unrelated new closure gate; follow current implementation state |
| PAC/OAC scheduled M0/M1 | OD-01 authority and OD-02 original/condensed detail, ownership/transfer/step-up/support/retention/role ceilings, host boundary | accepted successor required before authority change, current compatibility preserved |
| #105 | actual venue hierarchy/source annotations/capacities/geometry, accessibility verification | no GHB assumptions |
| #106 | resource/constraint schema, solver library/limits/weights and publication | human approved, no weakened constraints |
| #107 | AGIS OD-03/04, actual station/hardware, scope/credential/confirmation and offline crypto/clock/lease | no multiple active pass or offline authority inferred |
| #110 | EPW/HPG task/approval adapters, recurrence/timezones, service/protocol/privacy/fulfillment | no arbitrary workflow engine, no inferred precedence or finance |
| #111 | TDS/PAC OD-02 where applicable, FRS schema/mapping, CID supported providers/consent/quotas/evidence, RAI OD-05 and dataset/privacy/retention, shared branding | review all source-specific M0 choices, no duplicate engines |
| #108 | native/Compose protected installer, OS support, TLS/network/keys/backup/restore, actual provider arrangements | same release/security, no premature environment change |
| Phase 9 | OD-06 final tenant facts, exact candidate, actual target/device/provider evidence and owner signoff | no earlier VM, skipped ≠ passed |

Use [reconciliation §4](DESIGN_CONSISTENCY_RECONCILIATION_v1.0.md) for OD-01–06 and every original source decision register for full detail. These registers must be maintained by additive reviewed changes; do not change accepted ADRs, canonical API/migrations or source bytes in place. Future exact state/permission/API/data definitions must carry source IDs, decision reference and tests. No new issue or implementation authorization here.
