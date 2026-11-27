# Eventor Forms, Registration and Submission Studio (FRS)
## Technical specification v1.0

**Status:** Proposed for product-owner approval; no integration or implementation authorized by this draft.  
**Date:** 2026-11-27. **Read-only repository baseline:** `e0fa44203f785284d597f69dae8510c91bada0d6` (main, CID PR #236). All five required CI checks on this baseline were observed completed successfully during preparation. CI is not product acceptance.  
**Proposed destination:** `docs/implementation-design/v0.3/FORMS_REGISTRATION_AND_SUBMISSION_STUDIO_DESIGN_v1.0.md`. Links are relative to that future location. The five proposed documents are companion drafts, not yet repository files.  
**Document control:** FRS-01–16, FRS-M0–M5, FRS-AC-01–32. MUST denotes proposed product requirement, SHOULD preferred approach with justified exceptions, MAY optional. Endpoint names, entity names, permission codes and numerical envelopes are design proposals, not existing runtime contracts or certified targets. No acceptance tests executed.

## 1. Objective and boundaries

Provide a shared visual forms and registration studio for public booking inquiries, open/invitation-only registration, accreditation, RSVP questionnaires, vendor/staff submissions, hospitality requests, feedback and ordinary internal requests. Reuse existing booking-form schema, revision and submission boundary; common authoring and rendering do not create one unrestricted generic table or business-command engine. Each purpose has an allowlisted typed schema and owning handler. Intake, review, approved registration, identity resolution, event participation, RSVP, credential issuance, booking confirmation, task completion and attendance remain separate facts. Support no-email and assisted/manual intake; no mandatory external identity/provider. Accreditation is organizer authorization for participation under its own policy, not government or security clearance. No generic medical record collection, arbitrary code, payment collection or automatic identity merging.

## 2. Existing foundation and reconciliation

Blueprint §§6,12,21,25,26,33–34,37–38 and OAC-16 already require configurable forms, selected guest fields, localized public context and controlled submission. Existing public booking projection/submission migrations 000040–043, 000067–068 include get_booking_forms/create/revision/save/publish commands; `docs/product/PUBLIC_BOOKING_FORM_SCHEMA_v1.md` is a historical concrete schema reference. Booking inquiries map to owning review/draft workflow. Guest RSVP runtime 000075–89 and later auth guards, encrypted contacts, participation and reviewed import/merge migrations 000128–180 provide the relevant ownership boundary. #111 explicitly includes reusable forms/submissions; #104 owns identity/roster and #110 task evidence. Current forms are a working booking slice, not evidence of a generic drag-and-drop editor or registration workflow. Preserve legacy published booking URLs, schema, required validation and existing inquiry receipts.

Use [Blueprint v1.2](../../blueprint/v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md), [architecture](../../ARCHITECTURE.md), [roadmap](../../ROADMAP.md), [project state](../../PROJECT_STATE.md), [gap analysis](../../BLUEPRINT_TO_REPOSITORY_GAP_ANALYSIS_v1.0.md), [operating model](../../OPERATING_MODEL.md), and [roles](../../product/USER_ROLES_AND_PERMISSIONS_v0.1.md). Read [RSVP design](RSVP_AND_INVITATION_DESIGN_v0.3.md), [collaboration design](CROSS_ORGANIZATION_COLLABORATION_DESIGN_v0.3.md) and [disruption design](CANCELLATION_AND_EVENT_DISRUPTION_DESIGN_v0.3.md) for owning commands. Existing accepted decisions prevail until reviewed successor: [modular monolith](../../decisions/0001-modular-monolith.md), [self-hosting](../../decisions/0002-self-hosted-deployment.md), [human-approved allocation](../../decisions/0003-human-approved-allocation.md), [optional scope](../../decisions/0004-optional-event-operations-scope.md), [invitation separation](../../decisions/0005-separate-invitations-rsvp-attendance.md), [collaboration](../../decisions/0006-cross-organization-collaboration.md), [localization](../../decisions/0007-internationalization.md), [incremental staff UI](../../decisions/0008-modular-staff-frontend.md), [membership protection](../../decisions/0010-organization-membership-access.md), [login/workspaces](../../decisions/0015-email-first-login-and-platform-administration.md), [scoped grants](../../decisions/0023-permissioned-collaboration-grant-lifecycle.md), [reviewed grant acceptance](../../decisions/0024-shared-party-names-and-reviewed-grant-acceptance.md).

| Approved addendum | Reconciliation rule |
| --- | --- |
| [TDS](TEMPLATE_DESIGN_STUDIO_DESIGN_v1.0.md) | Shared visual components, brand/assets and preview; FRS owns typed data schema, validation and submission, not a second email/PDF renderer. |
| [PAC](PLATFORM_ADMINISTRATION_CENTER_DESIGN_v1.0.md) | Supported field/file types, size and abuse ceilings, data governance, protected support/recovery; no platform-wide submission browsing. |
| [OAC](ORGANIZATION_ADMINISTRATION_CENTER_DESIGN_v1.0.md) | Owns reusable forms, scoped destination, capability readiness and publication administration; domain owner reviews submissions. |
| [UX](EVENTOR_USER_EXPERIENCE_AND_NAVIGATION_v1.0.md) | Public minimal purpose-specific surfaces, accessible component system and review/error patterns; no staff session dependence. |
| [OLA](ORGANIZATION_LIFECYCLE_ACCEPTANCE_SCENARIOS_v1.0.md) | Extend OLA-05/06/07/09/10/13–15 with designer, registration, submission, review, privacy, restore. |
| [AGIS](ADMISSION_GUEST_INFORMATION_AND_STATION_MANAGEMENT_DESIGN_v1.0.md) | Accepted accreditation can become eligible participation through domain command; only separate authorized pass issue and scan record admission/attendance. |
| [CID](COMMUNICATION_INVITATION_DISTRIBUTION_AND_MULTI_CHANNEL_DELIVERY_DESIGN_v1.0.md) | Publication/share, approved receipts/reminders and reviewer notices through CID; no automatic live send by preview or form submission unless explicit reviewed domain policy. |

### Companion proposals (not yet approved)

| Companion | Interface and boundary |
| --- | --- |
| [AES](ADAPTIVE_EXPERIENCE_AND_SETUP_DESIGN_v1.0.md) | Quick preset with required fields and purpose, Guided optional sections and Advanced visual editor; same schema and review commands. |
| [EPW](EVENT_PLANNING_PRODUCTION_AND_OPERATIONAL_WORKFLOWS_DESIGN_v1.0.md) | Assign request/approval tasks and deadlines, link permitted evidence and domain decision; no arbitrary workflow execution. |
| [HPG](HOSPITALITY_PROTOCOL_AND_GUEST_SERVICES_DESIGN_v1.0.md) | Purpose-specific restricted dietary/accessibility/service request fields, minimized projection and separate review. |
| [RAI](REPORTING_ANALYTICS_AND_INTELLIGENCE_STUDIO_DESIGN_v1.0.md) | Approved aggregate submissions/status/registration metrics and permitted export; raw fields excluded from general dataset by default. |

## 3. Adaptive experience and user journeys

Quick Start: select purpose → published starter template → localized title and deadline → review public fields/visibility and destination → publish explicitly. No need to design layout. Guided: choose target event, open vs invitation-only, capacity policy, required data, consent notice, review rules and optional attachments. Advanced: component palette (typed text, number, choice, date/time, group/repeater, file, consent/notice, conditional section, approved identity/service component), form canvas, field settings, validation/conditions, locale tabs, accessible reorder, synthetic preview at desktop/mobile, diff and publication. Public form shows organization identity, purpose/notice, required labels, conditional questions, errors with focus, progress and confirmation receipt; no staff menu or searchable guest directory. Operator inbox displays permitted submission facts, dedup candidates where authorized, revision, status, assignment and review evidence. Reviewer sees before/after proposed owning record, approves/rejects/returns, and separately commits the domain action. Assisted entry is attributed to staff and actual respondent, not fabricated guest self-service.

Example: a synthetic conference permits public application, 100 registrations with separate waitlist. Applicant without email submits name and permitted contact alternative, receives safe receipt or assisted follow-up. Reviewer resolves potential Registry match, confirms participation eligibility using #104 command, then may separately issue CID invitation and AGIS pass when authorized. A submitted or waitlisted applicant does not reserve a seat, become an approved guest or count attendance. A booking-only C tenant uses existing booking form without event or Registry. A partner uploads evidence only for its assigned EPW task.

All modes are projections over the same canonical records and commands. Quick Start is not a permission class, price tier, alternate storage model or waiver of domain rules. Guided mode adds relevant questions; Advanced exposes authorized settings and diagnostics. Mode changes do not themselves mutate domain facts, publish, send, reserve, approve or grant authority. Defer optional setup; distinguish not applicable, not enabled, not configured, blocked and ready. A user can resume a draft and switch modes without losing valid work. Show reasons and a permitted next action, not inaccessible target IDs. Use bs-BA/en, IANA timezone, locale-aware number/date display and immutable authored translations; no silent translation of legal or guest-facing meaning. All visual interactions have keyboard/non-drag equivalents. User preference, organization default, and event capability are separate.

## 4. Functional requirements

### FRS-01 — Purpose catalogue and reuse

MUST maintain typed purpose/owner registry: booking inquiry, registration/application, accreditation, invitation/RSVP follow-up, vendor/task evidence, staff/volunteer application, guest service request, feedback, internal operational request. Each supports declared public/capability/staff mode, allowed fields, destination, handler, required permission and lifecycle. Reuse booking forms and RSVP/Registry/task commands; no generic arbitrary record update or direct DB mapping. New purpose requires reviewed contract and tests. Optional purposes disabled when owning feature unavailable.

### FRS-02 — Template library and safe copying

Tenant owns localized versioned form templates; select built-in neutral preset or clone approved schema/config into new draft. Copy field definitions, safe validations and brand refs only, not submissions, contact values, uploads, public tokens, prior approval or historical consent. Show purpose, owner, locale, revision, dependencies, retired/missing references. TDS common assets and brand inheritance; no arbitrary scripts/styles or external tracking pixels. PAC may supply safe defaults; tenant publishes independently.

### FRS-03 — Visual designer and stable field schema

Fields have stable key, type, label/help locale variants, required flag, classification, cardinality, typed validation, default source (safe constant or permitted domain projection), purpose allowlist, ordering and grouping. Distinct presentation and schema; field rename does not change key or reinterpret past answers. Repeater bounded count/depth; typed choice values stable, labels localized. Accessible reorder and preview; mark draft changes and unsaved state. No free-form HTML/JS, SQL, arbitrary URL fetch or unrestricted data binding. Validate unknown field, duplicate key, invalid type, unsupported condition and schema size server-side.

### FRS-04 — Conditional logic and multi-step intake

Use bounded declarative expressions over previous/allowed fields and enumerated constants; dependency graph acyclic, deterministic and evaluated identically server/client. Hidden fields cannot inject prohibited data or override required rules; define whether inactive answers cleared from draft and excluded at submission, disclose change. Required applies only to effective visible/allowed field or mandatory owning schema; owner fields cannot be removed through conditions. Multi-step navigation preserves safe draft values and revalidates all steps at submit; no conditional arbitrary command execution. Synthetic preview does not create live submission.

### FRS-05 — Validation and localization

Validate canonical typed values, Unicode/diacritics, max lengths, integer/decimal bounds, timezone/DST, enums, email/phone syntax without asserting verification, dates, repeated group counts, consent/notice revision and attachments. Client validation convenience only; server authoritative. Localized labels/help/errors, locale fallback explicitly approved, missing required translation blocks publication per policy. No sensitive fields by default, avoid unrestricted free-text prompts. Normalize safely for comparisons, preserve approved authored meaning and source value where needed. Return field-keyed redacted errors; never echo raw restricted answers.

### FRS-06 — Revision, publication and routing

Draft→review→published→superseded/retired, immutable schema/content/brand/notice/purpose/target refs after publication. Only explicit publication with expected revision and digest; public stable route resolves allowed current revision, in-progress form submits pinned revision only within reviewed compatibility/grace policy. Old revisions remain interpretable; incompatible/expired form requests safe refresh, no silent data reinterpretation. Close/retire blocks new intake, preserves prior submission/receipt and allowed status access. Public listing opt-in; capability-only forms not enumerable. Preview and publish never create participant, reserve, send or approve.

### FRS-07 — Access and intake modes

Support public open request, unlisted link, invitation-bound/capability form, authenticated staff and assigned partner; unlisted is not authentication. Public form gets only safe published schema and target metadata; invitation context resolved via purpose-bound token and minimal projection, no unrestricted prefill or guest lookup. Token expiry/revocation and membership/grant rechecked at submit; browser session and public context kept separate. No-email, no-device assisted completion with verified operator and source/respondent attribution; distinguish person, representative and staff entry. Optional saved draft uses secure expiry and access scope, no public PII in browser durable storage by default.

### FRS-08 — Submission lifecycle and idempotency

Submit validates exact published revision, current availability, authorization, effective field conditions, notice and attachment state. Persist immutable submitted snapshot and receipt atomically; one logical request per idempotency key+fingerprint under scope, changed payload conflict. Status received→under_review→returned→approved/rejected/withdrawn→applied (or owner-defined equivalent); approval not business execution. Amendments create new revision linked to original, reviewer sees diff; no mutation of original submission. Safe status capability separate from submit and domain tokens; receipt not confirmation of participation or booking. Staff may correct with reason and explicit review; no user ability to alter past decisions.

### FRS-09 — Registration, capacity and waitlist

Open/invitation-only event application with eligibility and approved registration policy: registration window, session choices, capacity/waitlist rules, guest/representative limits and review requirements. Separate request count, accepted registrations, eligibility, assignment and attendance. Authoritative acceptance locks event/session registration capacity and checks current eligibility, no oversubscription, waitlist ordered by configured reviewed rule with explicit tie-break, no opaque profiling. Waitlist position visible only if allowed and meaningful; promote via authorized review and capacity recheck, no automatic admission credential or RSVP. Walk-in registration uses same staff review/eligibility path; AGIS manual attendance separately authorized. Event/booking cancellation and published allocation changes require existing domain decisions.

### FRS-10 — Identity resolution and accreditation

Use reviewed Registry create/reuse/link commands; candidate matching by allowed normalized name/source/contact evidence, exact verified references and scoped permissions. No automatic merge or profile overwrite, no global contact search, no enumeration via public errors. Reviewer sees allowed differences, chooses create/reuse/update or reject; contested identity handled by #104 existing merge/correction. Accreditation records purpose, event/session, category/eligibility decision, issuer/approver and expiry, separate from RSVP and admission. No government identification upload by default; if legitimate narrowly approved need, classified restricted field, retention and legal review; no security clearance claim.

### FRS-11 — Attachment and evidence handling

Allow only purpose-approved file types, max size/count, MIME and content validation, private object IDs, bounded upload and quota. Stage/quarantine before safe scanning; disallow executable/archive or active content by default, sanitize where supported, never execute or fetch arbitrary remote URL. Hash source and approved derivative, retain provenance; pending/failed scan cannot be treated as accepted evidence. Private downloads require current owner/grant and field-level authority, time-limited safe response, no public direct path. FRS task evidence references EPW canonical task; upload not completion. Retention/hold and orphan cleanup with audit; no real documents in Git.

### FRS-12 — Review inbox, assignment and owning commit

Authorized inbox supports scope, purpose/status, date, revision, assignment, permitted search and safe summaries, with bounded pagination; no broad export by reviewer. Assign to eligible owner through EPW or existing booking queue. Review action captures actual actor, expected submission and target revision, proposed mapping, excluded/invalid fields, evidence and digest. Allow return for correction, reject with safe reason, approve then explicit owning action through known adapter. Recheck grants, policy, capacity and identity at execution; concurrent commit yields one owning receipt. Partial allowed only where purpose explicitly declares per-item outcomes; no silent partial record updates.

### FRS-13 — Mapping, feedback and external submissions

Allowlisted field-to-domain mappings versioned per purpose, typed conversion, source lineage and classification. No arbitrary target field, command, scripting or auto-approval. Booking submission continues existing inquiry creation path; task submission appends proposed evidence; hospitality request enters HPG restricted queue; feedback can be anonymous only if policy and technical design genuinely avoid identity correlation, never promise anonymity with identifiable content. Separate consent to receive follow-up from request acceptance. Public external form embed optional future integration, initially safe link; no broad CORS or third-party scripts.

### FRS-14 — Notifications, receipts and communication preferences

Receipt uses separate safe capability or authorized staff projection; may be printed/read verbally where needed. CID sends only policy-approved receipt/reminder/reviewer alert with verified eligible route; no email mandatory, provider failure does not invalidate submission. No message exposes restricted response/attachment/token except controlled purpose-bound channel. RSVP form answer uses owning RSVP command only after explicit confirmation, not GET/preview. Opt-out from marketing/follow-up does not silently erase existing request or necessary reviewed transactional obligation. Distinguish receipt, review decision and actual business action.

### FRS-15 — Privacy, consent and retention

Field classification public metadata/internal/restricted/high sensitivity; collect only necessary purpose. Publish versioned notice, consent evidence (actor/respondent, purpose/channel, revision/time/source), distinguish required legal acknowledgement from optional communications preference. No prechecked optional consent, no blanket cross-event/channel consent. Restricted answers encrypted with purpose-bound context and separate permissions, ordinary list/metrics masked. Configurable retention by purpose, legal holds and reviewed correction/purge, minimal audit and lineage retained where required; export/portability limited to allowed fields. No automatic transfer to master profile from a submission.

### FRS-16 — Operations, abuse and accessible reporting

Public submission rate/size limits and fair tenant quotas, bot/abuse protections with accessible fallback, no mandatory third-party captcha. Safe generic errors, no contact or guest enumeration. Queue health, pending scans, review age and conversion metrics derived from authoritative state with definitions; RAI scope restrictions. Quick preset/Guided/Advanced use same schema, publication and review. Test keyboard, screen reader, conditional focus, mobile, locale, zoom and plain print alternative. Support trusted local network when server reachable; offline unsubmitted values may be ephemeral only, no automatic background submit or unsafe persistence.

## 5. Workflow, transaction and failure semantics

### Intake and ownership sequence

Author draft and validate schema graph → review synthetic rendering, purpose, field classification, destination and revision → publish explicitly → resolve public schema/capability without mutation → validate submission at server → persist immutable snapshot/receipt and outbox in one transaction → assigned review → preview typed domain mapping and review digest → explicit owner approval/execute under current authorization and locks → immutable application receipt, separate notification intent if approved. For booking inquiry use current existing validated command path, no compatibility break. Submission status `approved` cannot be treated as registered until owning execution receipt. Returned submission receives revision-bound correction access; original read-only and fresh review.

### Concurrency and recovery

Lock registration-policy/event/session capacity in existing owning order at acceptance, not public submit; use unique active participation rules where appropriate, safe count capacity and waitlist ordering. Reject stale policy/subject and re-review. File staging lease and state separate from submission; finalize only clean, referenced uploads; on disconnect query receipt, never duplicate. Jobs scan/render/export using bounded private artifacts and recheck grant; uncertain external send handled by CID.

| Failure | Required behavior |
|---|---|
| Public form retired while open | Reject or allow pinned compatible revision per published policy, no silent switch |
| Invalid hidden field injection | Reject excluded/forbidden field; no stored restricted value |
| Attachment still scanning | Pending state or block submission per purpose; no review completion |
| Registration capacity reached | Waitlist/reject as configured, no oversubscription |
| Duplicate match | Review, not auto merge |
| Reviewer loses grant | Deny review/execute/export, preserve attribution |
| Provider unavailable | Receipt remains; manual contact or deferred CID |
| Return and resubmit | New snapshot, original preserved, old review invalidated |
## 6. Architecture and logical data model

Extend the existing Vue 3/TypeScript staff application, Fastify API/workers and PostgreSQL 18.6 modular monolith; no mandatory external SaaS or second database. Reuse domain commands, approved TDS renders, CID delivery, transactional outbox and scoped projections. Logical names below are candidates; inventory actual schema, role grants, lock order, indexes, views, current APIs and fixtures at M0. Add only missing extensions with forward migrations; no rewriting historical migrations, accepted ADRs or the v0.2 schema/OpenAPI snapshots. All tenant-owned keys include organization context; event references include event scope, verified by composite FK or equivalent command integrity. Cross-party references use explicit accepted grant/revision and permitted projection, never broad joins. Immutable published revisions, decisions, receipts and evidence retain source IDs; append correction/supersession rather than destructive rewrite. Sensitive values and private artifacts use authenticated encryption and purpose-bound identity; no secret in audit or general projections.

| Logical entity or existing aggregate | Principal fields / keys | Integrity and lifecycle |
| --- | --- | --- |
| booking form/revision/submission | existing tenant form, locale, published schema, inquiry refs | Canonical legacy path; compatibility tests |
| form_template/revision | org, purpose, locale, schema version, brand/notice refs, state, digest | Immutable published; typed allowlist, no prior response |
| form_field / rule manifest | revision, stable field key/type/classification, typed constraints/conditions | Unique keys; bounded acyclic conditions, owner-required fields |
| form_publication | tenant, form/rev, target type/id, audience/access mode, window, slug/capability digest | One active reviewed head where applicable; scoped target, revocable |
| form_draft (optional intake) | purpose-bound session, revision, encrypted minimal values, expiry | No broad access, bounded TTL, no implicit submit |
| submission / revision | org, purpose, form rev, target, respondent context, idempotency fingerprint, encrypted answers, state | Immutable snapshot; current status projection and history |
| submission_receipt/status capability | submission ref, digest, scope/expiry/revoke, safe status | Separate submit/action/RSVP/admission tokens |
| upload/artifact | org, submission/stage ref, object key, source digest, size/type, scan status, retention | Quarantine, private authorized access, hold/cleanup |
| submission_review / decision | subject rev/digest, actor/grant, mapping rev, target expected rev, decision/evidence | Immutable; stale invalidates execution |
| domain_application_receipt | review ID, owning action, target/receipt, idempotency | Unique logical execution; no duplicate aggregate |
| registration_policy/revision | event/session, eligibility, capacity/waitlist/window, review rule | Authoritative owner capacity check; history |
| registration_request/waitlist entry | submission ref, event/session, state/order key, accepted participation nullable | No attendance or seat by implication, atomic promotion |
| accreditation decision | event, participation/request, category, authority, expiry, status | Separate from pass; authorized correction/revocation |
| consent/notice evidence | purpose, notice revision, respondent/actor, time/source, scope, withdrawal | Append-only evidence, no blanket consent |

### Migration and compatibility

Audit existing tables and commands first; additive sidecar only where needed. Backfill through reviewed deterministic mapping with exception report, preserve existing IDs, historical snapshots and access semantics; default newly introduced capabilities to disabled/unconfigured unless existing equivalent facts justify activation. Test fresh install and populated upgrades, RLS and grants with runtime/auth/worker roles; old clients retain supported route behavior. No destructive down migration for recorded facts; recovery through tested compatible release or controlled restore and reconciliation. Add indexes for tenant/event/status/revision and due work; measure plans on synthetic representative cardinality; do not rely on client-side filtering.

## 7. API and permission contracts

Paths are relative to the existing API version; exact prefix, schema, codes and permissions determined after M0 inventory. Every staff route authenticates active user, selected membership, tenant, domain permission and object scope before lookup; delegated grants checked with current purpose, validity, projection and ceiling. Unknown/foreign IDs return non-enumerating error. Mutations use strict OpenAPI schemas, bounded input, CSRF/origin, expected revision and idempotency key scoped to tenant/actor/action; canonical request fingerprint binds reviewed inputs. Same key + same request returns original receipt only after current authority recheck; different request conflict. Stale revision/digest yields conflict and safe refresh, not silent override. Public capabilities are separate, opaque, high entropy, purpose-bound, expiring/revocable; store digest for lookup and minimal encrypted delivery envelope where required, fragment cleanup and no third-party referrer. GET/preview never issues credentials, publishes, approves, sends, reserves or changes business state. Use safe problem details/requestId, pagination with stable ordering and authorized filters; long jobs return 202 and receipt, not completed result. Recheck authority at job claim, artifact download, stream subscription/reconnect and consequential commit. Audit real actor/membership or scoped worker intent, purpose and outcome without plaintext sensitive data.

| Proposed operation | Input / result | Authority / effect |
| --- | --- | --- |
| GET /forms/catalog?purpose=… | allowed purpose/fields/templates | tenant author/read; no arbitrary targets |
| POST /forms/{id}/revisions | typed schema/locale/brand refs, base revision | author draft; legacy booking compatibility |
| POST /forms/{id}/review\|publish | schema digest, target/access window, revision | review/publish independent; no send |
| GET /public/forms/{slug} | safe published schema/locale and status | public allowed mode; no personal data |
| POST /public/form-capabilities/resolve | opaque purpose token → bounded context | non-destructive exchange, no staff session |
| POST /public/forms/{slug}/submissions | pinned rev, answers, clean upload refs, key | validate mode/rate/policy, safe receipt only |
| POST /forms/{id}/assisted-submissions | respondent/source, rev, answers, key | staff exact scope, actor recorded |
| POST /submissions/{id}/uploads/init\|finalize | bounded type/size/hash, private staged ID | purpose-bound upload authority; scan before use |
| GET /public/submission-status | status session/capability, safe receipt | status-only scope; no raw answers |
| GET /submissions?purpose=… | scoped filtered list, stable cursor | reviewer exact purpose/target, masked fields |
| POST /submissions/{id}/review | expected rev, mapping and target diff | reviewer; no domain mutation |
| POST /submissions/{id}/decision | digest, approve/reject/return, reason | eligible reviewer, immutable decision |
| POST /submissions/{id}/apply | approved digest and idempotency | owning command authority, lock/capacity/recheck |
| POST /registrations/{id}/promote | reviewed policy/expected rev | registration owner, capacity atomic |
| POST /forms/{id}/retire | review impact/digest | publisher, block new intake; preserve records |

### Permission matrix

| Authority (proposed semantic permission) | Scope | Allowed / exclusions |
| --- | --- | --- |
| form.author / form.publish | tenant/purpose | separate draft edit and approved publication; no response access |
| submission.create.assisted | event/booking/task scope | attributed intake; no approval |
| submission.review / assign | purpose and exact target | permitted list, evidence review; no broad Registry access |
| submission.restricted.read | specific field/purpose scope | only need-to-know, audited |
| registration.decide / participation.manage | event/session | accept/waitlist/link through owning command; no auto pass |
| registry.match/merge | tenant Registry | existing restricted permissions; not granted by form review |
| task.evidence / task.verify | assigned task | upload and review separately, no completion from upload |
| form.export / privacy.manage | allowed dataset/purpose | private reviewed exports/retention, separate sensitive rights |
| public capability holder | one publication/invitation/receipt | only scoped view/submit/status; no arbitrary IDs |
| PAC support | explicit grant and expiry | safe diagnostics, no universal submission access |

## 8. Security, privacy and reliability

Threats specific to intake: forged field schemas and mass assignment (typed allowlist and independent domain mapping), conditional bypass (authoritative evaluation), duplicate/racing registration (locks, unique intent and current capacity), public enumeration (uniform errors and rate limit), identity poison (reviewed match), malicious file (quarantine and scan, safe content disposition), cross-purpose token replay (purpose-bound scope), overcollection (field purpose and retention), stored XSS (safe rendering), CSV formula injection (escaped export), stale approval (digest and reauthorization), unauthorized draft recovery (scope before lookup). Public receipt/link carries minimal data; no analytics or third-party script receives secrets; CSP, no-referrer, bounded request parsing, no session restoration on public context. Abuse controls must preserve accessible assisted route. Do not infer sensitive traits, identity verification or legal eligibility from user-entered fields. No automatic external delivery or retry on ambiguous outcome.

Never trust user-supplied tenant, role, target ID, template, route or scope. DB RLS and narrow commands protect data independently of navigation; deny direct writes and broad worker access. Use current membership/grant revocation ordering and reviewed successor ADR if changing authority. Outbox records commit with owning state, use tenant-scoped bounded consumers, lease/fence and deduplication; reconnect fetches authorized snapshot and cursor, gap triggers resync. Notification intents use CID with separately approved eligibility, content, costs and uncertainty handling; no automatic retry of ambiguous external submission. Sensitive data excluded from logs, metrics labels, URLs and public snapshots; no arbitrary JS, SQL, host shell, filesystem paths or external destinations. Review legal purpose, retention, correction, holds, redaction and portability with tenant; no claim of deletion from all backups. Tenant suspension denies new protected actions, preserves historical receipts and independent memberships. Local host recovery remains protected per PAC.

## 9. Quality, observability and deployment

Proposed envelope: 100 concurrent public submissions, form up to 100 field definitions/10 steps/20 repeated entries (review limits by purpose), 10,000 submissions per event synthetic test, approved attachment size/count budget (initial proposal 10 MB/file, 3 files where enabled). Public schema p95 ≤500 ms and text-only submission p95 ≤1 s on reference local environment, excluding actual upload/scan/provider time; show pending separately. Review list p95 ≤750 ms with indexed filters. 20 concurrent acceptances for one remaining registration place yield exactly one accepted, remaining waitlist/reject per policy. 20 identical submit/apply requests produce one receipt. Record scan queue age, invalid rate, review age, retained artifact bytes and failures without field values or recipient labels. Exercise restore with staged uploads/approved but not applied submissions, no duplicate application or send. Verify existing booking form URLs/revisions and guest RSVP browser regression.

Targets are proposed measurements on documented synthetic fixtures/hardware/network, with actual p50/p95/error rate and query plans recorded; no performance assertion before test. Both native Linux and production Docker Compose use the same build/schema/fonts/config/security contract, dedicated non-root service roles, TLS, durable storage and secret handling. External integrations optional; local capture/manual path and trusted local-network operation where server reachable. Backup DB/assets/keys and job state consistently; restore in isolation, fence potentially completed work and reconcile before enabling side effects. Browser tests Chromium/Firefox plus supported mobile/Safari/device evidence where applicable; keyboard-only, screen reader, contrast, 200% zoom and 360/768/1280/1920 widths. Operational metrics scoped by tenant and coarse counts, no PII labels; record queue age, failures and bounded diagnostics.

## 10. Implementation milestones and ownership

Do not change current Codex #104/#112 foundation closure then #105 spatial, #106 allocation, #107 admission/Cockpit, #110 collaboration, #111 communications/forms/reporting, #108 dual installers in established roadmap order. Work packages refine owning slices, not a new parallel project or immediate task switch. Minimal safe defaults can ship before advanced editors. Every slice: audit, reviewed contract/schema, domain API, role-scoped UI, negative/concurrency/upgrade/browser tests and documentation. Do not mark schema as usable workflow. Keep all existing issue criteria; do not create unrelated closure gates. Final full acceptance VM Phase 9 after feature-complete candidate.

| Milestone | Deliverables and exit evidence | Existing owner |
| --- | --- | --- |
| FRS-M0 — Inventory and schema review | Audit existing booking form, RSVP, Registry and task contracts; purpose registry, field/notice/mapping and file threat model. | #111/#104/#110 |
| FRS-M1 — Shared safe authoring | Quick presets, typed schema, conditional logic, localized editor/preview, immutable publication; preserve booking paths. | #111/TDS |
| FRS-M2 — Intake and review | Public/capability/staff submission, receipt, reviewed mapping and owning apply, idempotency/authorization. | #111/#104/#112 |
| FRS-M3 — Registration and accreditation | Eligibility/capacity/waitlist, reviewed identity, no-email assisted intake and separate credential issue. | #104/#107/#111 |
| FRS-M4 — Task/service and file evidence | Private upload/quarantine, partner tasks and HPG requests, CID notices, retention. | #110/#111 |
| FRS-M5 — Reporting and integrated acceptance | RAI scoped metrics/exports, full accessibility/abuse/restore and both installer modes. | #111/#108/Phase 9 |

### Issue reconciliation proposal (after owner approval)

| Existing issue | Scope clarification only |
| --- | --- |
| [#104](https://github.com/TeraflopsBH/eventor/issues/104) | Reviewed registration identity/link, eligibility and contact/consent, no auto merge. |
| [#107](https://github.com/TeraflopsBH/eventor/issues/107) | Separate accreditation/participation from pass issue and attendance, assisted intake only. |
| [#110](https://github.com/TeraflopsBH/eventor/issues/110) | Assigned vendor/staff/task evidence and requests; no automatic task completion. |
| [#111](https://github.com/TeraflopsBH/eventor/issues/111) | Primary reusable form studio, purpose catalog, registration intake and review, localization, attachments and scoped outputs. |
| [#112](https://github.com/TeraflopsBH/eventor/issues/112) | Preserve public booking/cancellation routes and owning decisions; no generic form substitute. |
| [#108](https://github.com/TeraflopsBH/eventor/issues/108) | Private artifact storage/scan dependency, local operation, restore and both modes. |
| [#105](https://github.com/TeraflopsBH/eventor/issues/105) | Optional approved venue/session references only; no new spatial scope. |
| [#106](https://github.com/TeraflopsBH/eventor/issues/106) | Accepted registration does not assign seating; allocation owner remains canonical. |

## 11. Measurable acceptance criteria and traceability

Use isolated synthetic tenants A organizer/hybrid, B independent partner, C provider-only; distinct authorized/preparer/reviewer/revoked actors, fake guests/contacts, fixed clock with DST edge, approved synthetic venue/plan and local delivery capture. Test exact-head CI and post-merge CI; run domain command/DB, API, real browser and concurrency/fault/restore tests as indicated. Capture candidate SHA, fixture revision, role, request/receipt IDs, expected/observed counts and redacted artifacts, measured times and actual hardware/provider evidence where applicable. No mock is proof of external compatibility; optional skips not passes. A test is pass only if every required result holds; failed/blocked/N/A explicitly reasoned and authorized, no waiver of security/integrity.

| ID | Requirement | Fixture / precondition | Action | Expected measurable result | Evidence | Related acceptance / scope |
| --- | --- | --- | --- | --- | --- | --- |
| FRS-AC-01 | FRS-01 | Booking-only tenant | Submit existing booking form | Same inquiry/receipt behavior; zero event/guest records | API/browser | OLA-07 |
| FRS-AC-02 | FRS-01 | Unsupported purpose/target | Attempt generic form update | Rejected; no arbitrary domain write | API | OAC-16 |
| FRS-AC-03 | FRS-02 | Template with historical submissions | Clone safe schema | Zero responses/uploads/tokens/approvals copied | DB diff | AES/EPW |
| FRS-AC-04 | FRS-03 | Draft with duplicate field key/JS binding | Publish | Rejected; existing published rev unchanged | API | TDS |
| FRS-AC-05 | FRS-03 | Rename field label in successor | Read old submission | Stable field key and original revision interpretable | DB | OLA-05 |
| FRS-AC-06 | FRS-04 | Condition hides optional restricted field | Submit crafted hidden answer | Reject forbidden field, zero stored value | API/DB | OLA-11 |
| FRS-AC-07 | FRS-04 | Cyclic conditions / removed owner required field | Save/review | Reject cycle or missing required owner field | Unit/API | OAC-16 |
| FRS-AC-08 | FRS-05 | bs-BA/en diacritics and DST edge | Submit valid/invalid values | Exact valid normalization, localized safe errors | Unit/browser | UX-AC-10 |
| FRS-AC-09 | FRS-06 | Open form on retired revision | Submit after retirement | Allowed only explicit pinned grace; else safe refresh, no mutation | API | OLA-05 |
| FRS-AC-10 | FRS-06 | Synthetic preview/publish | Inspect DB/outbox | Zero live submissions/sends/participants | DB | TDS |
| FRS-AC-11 | FRS-07 | Invitation-bound form and wrong-purpose token | Resolve/submit | Denied, no foreign context | API | ADR 0005 |
| FRS-AC-12 | FRS-07 | Guest no email or device | Staff assisted submission | Actual actor/source and receipt, no fake self-response | Browser/DB | CID-11/12 |
| FRS-AC-13 | FRS-08 | 20 identical public submits | Concurrent request | One submission/receipt; changed payload conflict | DB race | OLA-14 |
| FRS-AC-14 | FRS-08 | Returned form with corrected answer | Resubmit | New snapshot; prior decision/history intact, review stale | DB | OAC-16 |
| FRS-AC-15 | FRS-09 | One remaining registration place, 20 applicants | Concurrent acceptance | Exactly one accepted, remaining explicit waitlist/reject; no seats/passes | DB race | OLA-09 |
| FRS-AC-16 | FRS-09 | Waitlist and revoked eligibility | Promote | Capacity/current eligibility enforced; no auto admission | API | AGIS |
| FRS-AC-17 | FRS-10 | Ambiguous Registry match | Review application | Explicit choose/reuse/create; no silent merge/overwrite | DB/browser | ADR 0009 |
| FRS-AC-18 | FRS-10 | Approved accreditation | Inspect RSVP/attendance/credentials | No implicit RSVP, pass or attendance | DB | AGIS/ADR 0005 |
| FRS-AC-19 | FRS-11 | Oversized/executable/infected upload | Finalize/review | Rejected/quarantined, no public access or completed evidence | API/security | OLA-10/14 |
| FRS-AC-20 | FRS-11 | Grant revoked after file preview | Download | Denied, no cross-tenant artifact | API | OLA-11 |
| FRS-AC-21 | FRS-12 | Approved reviewed mapping, target changed | Execute | Conflict; zero partial owning writes | DB race | OLA-14 |
| FRS-AC-22 | FRS-12 | 20 identical apply calls | Execute review | One owning receipt and domain effect | DB race | OLA-14 |
| FRS-AC-23 | FRS-13 | Assigned vendor task evidence | Submit valid evidence | Proposed evidence only; task status unchanged until owner command | API/DB | #110 |
| FRS-AC-24 | FRS-13 | Feedback with identifiable text | Attempt anonymous export claim | Explicit limitation, no misleading anonymity or restricted data | Review/export | RAI |
| FRS-AC-25 | FRS-14 | CID unavailable | Submit registration | Receipt valid, no send success claim; manual follow-up | E2E | CID |
| FRS-AC-26 | FRS-14 | GET receipt or RSVP link scanner | Open link | Zero response/decision mutation | API | RSVP design |
| FRS-AC-27 | FRS-15 | Optional consent unchecked | Submit legitimate request | Request accepted per policy; optional channel not authorized | DB | CID-13 |
| FRS-AC-28 | FRS-15 | Restricted answer and concurrent legal hold | Export/purge | No unauthorized field; hold blocks purge | DB/export | OLA-13 |
| FRS-AC-29 | FRS-16 | 100 concurrent text submissions | Measure p95 and counts | Targets measured, bounded queue, zero duplicates | Load | OLA-14 |
| FRS-AC-30 | FRS-16 | Keyboard, screen reader, mobile conditional form | Complete error/correction flow | All required actions accessible; focus/error announced | Manual/browser | UX-AC-13/14 |
| FRS-AC-31 | FRS-07, FRS-11, FRS-12, FRS-16 | Restore staged uploads and pending review | Resume in both modes | No duplicate apply/send; private files scoped and pending states reconciled | Host/VM | OLA-15 |
| FRS-AC-32 | FRS-03, FRS-06, FRS-12 | Two authors/reviewers | Publish/apply stale revision | Conflict, previous published/schema/decisions retained | DB race | OLA-05 |

### Requirement-to-acceptance traceability

| Requirement | Acceptance suffixes | Owning topic |
| --- | --- | --- |
| FRS-01 | 01, 02 | Purpose catalogue and reuse |
| FRS-02 | 03 | Template library and safe copying |
| FRS-03 | 04, 05, 32 | Visual designer and stable field schema |
| FRS-04 | 06, 07 | Conditional logic and multi-step intake |
| FRS-05 | 08 | Validation and localization |
| FRS-06 | 09, 10, 32 | Revision, publication and routing |
| FRS-07 | 11, 12, 31 | Access and intake modes |
| FRS-08 | 13, 14 | Submission lifecycle and idempotency |
| FRS-09 | 15, 16 | Registration, capacity and waitlist |
| FRS-10 | 17, 18 | Identity resolution and accreditation |
| FRS-11 | 19, 20, 31 | Attachment and evidence handling |
| FRS-12 | 21, 22, 31, 32 | Review inbox, assignment and owning commit |
| FRS-13 | 23, 24 | Mapping, feedback and external submissions |
| FRS-14 | 25, 26 | Notifications, receipts and communication preferences |
| FRS-15 | 27, 28 | Privacy, consent and retention |
| FRS-16 | 29, 30, 31 | Operations, abuse and accessible reporting |

### Release integration

Add the above evidence to applicable OLA scenarios and G1–G9 gates without replacing existing OLA/PAC/OAC/UX/TDS/AGIS/CID criteria. G1 CI, G2 independent organization, G3 isolation, G4 configuration/content/output, G5 cross-domain journey, G6 resilience/accessibility, G7 deployment/recovery, G8 external evidence when applicable, G9 traceability/release defects. Provider-only, simple organizer and complex hybrid journeys remain independently usable. Actual supported devices, deployment and external provider acceptance only in planned Phase 9; automated tests incrementally in owning slices.

## 12. Open decisions and proposed integration

Decide exact reuse/evolution of booking form schema and runtime handlers, field type registry, conditional language limits, public URL/access and pinned revision grace policy, identity match evidence and no-email receipt handling, registration capacity vs session eligibility and waitlist rules, accreditation owner/purpose and expiry, upload scanner/sanitizer and storage policy, notice/consent legal basis and retention, anonymous feedback definition, review and mapping allowlist, accessibility test fixtures. No real form field/policy or live provider credentials inferred. Paid registration/payment and arbitrary third-party integration are future scope, not required to make intake usable.

Before implementation, owner/tenant validates real capacities, legal/retention policies, staffing, commercial rules, programme, identity and accessibility needs; no fictional examples become GHB configuration. Engineering reviews candidate libraries, licensing, exact route/schema/role choices, security threat review and performance envelope when scheduled. Do not modify accepted ADRs except through reviewed successor. Once owner approves, integrate complete source verbatim at stated destination, record approval and original SHA-256/blob externally in [design index](README.md). Add dated additive cross-references in architecture, roadmap, gap analysis, relevant approved designs and mapped existing issues, retain historic source checksum references and all existing issue requirements. Verify complete docs-only Git tree diff, source read-back, link resolution, required exact-head CI and post-merge CI; no runtime code, migrations, OpenAPI, workflows, Blueprint v1.2, PROJECT_STATE, Codex branches, environment or early VM change. Future consolidated Blueprint v1.3 separately approved; no requirement silently dropped.
