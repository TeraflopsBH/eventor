# Eventor Organization Lifecycle Acceptance Scenarios
## End-to-end verification and release gates v1.0

**Status:** Proposed for product-owner review. All scenarios are **not run**; this document defines future evidence, not test results.  
**Date:** 2026-11-27. **Inspected main:** `0c5e7a2ddf0a676a89bb75faef1265438dc2ae45`.  
**Proposed destination:** `docs/implementation-design/v0.3/ORGANIZATION_LIFECYCLE_ACCEPTANCE_SCENARIOS_v1.0.md`.  
**Companions:** [OAC technical specification](ORGANIZATION_ADMINISTRATION_CENTER_DESIGN_v1.0.md) and [UX and Navigation](EVENTOR_USER_EXPERIENCE_AND_NAVIGATION_v1.0.md). Read with [PAC](PLATFORM_ADMINISTRATION_CENTER_DESIGN_v1.0.md), [TDS](TEMPLATE_DESIGN_STUDIO_DESIGN_v1.0.md), [Blueprint v1.2](../../blueprint/v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md), [Roadmap](../../ROADMAP.md), [Operating Model](../../OPERATING_MODEL.md), [roles/permissions](../../product/USER_ROLES_AND_PERMISSIONS_v0.1.md), and existing issue acceptance requirements. This suite adds cross-module customer journeys; it never waives domain-specific tests or implies implementation completion.

## 1. Release objective and verification policy

A newly provisioned organization must become independently operational through supported application interfaces and secure enrollment. It must manage its own facilities, bookings, people, events, communications and permitted data without routine platform-owner intervention or manual SQL. A booking-only organization must not need guest records or operational events. An organizer must be able to use an explicitly authorized partner venue without accessing source records or requiring ownership of a venue. A hybrid organization may do both. Event-day staff, guests, customers and vendors must see only their intended scoped experience. Platform recovery remains a protected host task; the no-manual-SQL criterion applies to ordinary business/onboarding operations, not automated installer migrations, synthetic fixture setup or documented emergency recovery.

The final release requires evidence for all applicable blueprint, issue, PAC, TDS, OAC, UX and OLA gates. Every test records actual expected vs observed outcomes. Passing CI verifies that commit's covered behavior, not production readiness. Skipped external probes, mocked HTTP, schema presence, screenshots and editor concepts are not substitutes for real integrated behavior. Required but unsupported behavior is a release gap, not a pass. Approved non-applicability applies only to a specifically disabled optional module in a specific scenario; the overall release must still test the module in an appropriate scenario. Tests execute against disposable synthetic data; never use production guest records, real credentials, sensitive venue plans or real recipients. Do not execute actual production restore, destructive actions, bulk campaigns or external authority operations.

### 1.1 Evidence levels and schedule

| Level | Evidence | When |
|---|---|---|
| L1 | Unit/schema/contract checks; static design/validation | Each scheduled vertical slice |
| L2 | Real PostgreSQL runtime-role, RLS, API, worker, concurrency and migration tests | Each owning feature PR, exact head and post-merge |
| L3 | Browser/API/DB integrated scenarios; Chromium/Firefox, local SMTP capture, synthetic fixtures, actual editor/renderer/scanner test adapter | As owning feature becomes usable; no final VM needed |
| L4 | Cross-module journey, accessibility manual review, fault injection/load and isolated restore rehearsals | Once dependencies available; CI/local disposable environment |
| L5 | Final native Linux and Docker Compose clean install/upgrade/recovery and actual host/device/public HTTPS/SMTP evidence | Phase 9 only, after coherent release and both installers |

Use existing acceptance scripts/runbooks and suites where possible. Do not create competing fixtures/suites or recode already-passing tests. Tests that require missing features remain blocked in planning, not silently omitted. Exact acceptance commands, API operation IDs, schema names and role codes reconciled at implementation; steps below specify behavior, not invented existing endpoints.

## 2. Synthetic reference installation and fixture contract

| Fixture | Role and data |
|---|---|
| P | Platform Owner, explicit protected bootstrap; separate limited Superadmin and platform auditor for delegation tests |
| A (GHB-reference) | Hybrid organization; synthetic name/brand only, bs-BA, Europe/Sarajevo; administrator A-admin, booking manager, finance approver, venue coordinator, event manager, Registry manager, communications designer/operator, seating manager, gate operators A-g1/A-g2 and auditor |
| B (independent organizer) | en, synthetic distinct identity/brand; B-admin, event manager, Registry manager and task collaborator; no owned venue required |
| C (provider-only) | Synthetic separate organization, booking/resources only; C-admin/booking operator; all guest/event capabilities disabled by default |
| M | Existing named user with independent memberships in A and B, different role in each |
| N | Active member with no business grants |
| X | Unauthorized user or unrelated organization/account for negative tests |
| V | External vendor/task-scoped collaborator, no implicit membership |
| K | External booking requester/contact, no staff account |
| R1/R2 | Synthetic guest profiles with accented Bosnian names; R1 participates in two events; one restricted field/contact explicitly protected |
| Venue VA | Synthetic GHB-like facility with hall and prayer-row/count-zone template; dimensions/capacity fictional and validated within fixture |
| Venue VC | Provider C facility and resource; booking-only test |
| Events EA1/EA2, EB | Own A events, B independent event; distinct schedules/sessions, capacities, brand/policy snapshots |
| SMTP | Local capture service; isolated external sandbox in final phase only; never real guest addresses |

Use reserved domains such as `example.invalid` for fake addresses and configured local capture aliases. Define timestamps using a fixed fixture clock and IANA timezone, one DST edge case. IDs stable per isolated run, reset between scenario groups or declare dependencies; no real names/identifiers required. Assign actual supported role codes via reviewed setup, not assumed job title authority. Separate identities for approval/denial tests; single-owner technical recovery tested separately per PAC. Record explicit test policies: capacity, pricing/currency/tax, cancellation policy, approval thresholds, allowed modules, retention/hold, publication locale rules, MFA/recovery and permitted support scope. Fixture values synthetic, not GHB operational claims. Test both allowed and denied conditions with real runtime-role access; direct privileged fixture setup only in disposable environments and not part of normal user acceptance path.

## 3. Required run record

For each scenario and subassertion record: ID, owning requirement/issue, status (`not_run`, `blocked`, `pass`, `fail`, `not_applicable`), exact release/commit and deployment mode, build/migration checksums, browser/device/version, scenario fixture version, actor/scope, steps executed, expected and observed outcomes, safe timestamps/correlation IDs, evidence file/CI URL, deviations and reviewer. No secrets in screenshots/logs/receipts. Record setup prerequisites, actual assertions (DB state/count, response status, rendered output digest, queue state, audit actor, denial and no mutation), cleanup and any irreversible synthetic action. For negative tests prove prohibited result absent, not merely button hidden. For asynchronous actions prove final receipt or explicitly uncertain state; do not count 202 or provider connection success as delivered. Required test fail/blocked/not_run prevents full release sign-off. Document remediation under owning issue; avoid duplicate tracking issues. Do not mark this spec itself as implementation evidence.

### Example evidence record (blank template, not a result)

```yaml
scenario: OLA-07
assertion: booking-confirmation-conflict
status: not_run
commit: null
deployment: null
fixture_version: null
actor_scope: null
expected: exactly_one_confirmation_for_conflicting_resource
observed: null
correlation_ids: []
evidence: []
reviewer: null
notes: null
```

## 4. End-to-end scenarios

### OLA-01 — Installation owner provisions organization

**Tracks:** #104/#108; PAC-M1/M2; OAC-01/07, OAC-AC-01. **Level:** L2/L3 now when implemented, L5 final.

**Prerequisites:** installation bootstrap, management auth/roles, PAC provisioning service; synthetic blank tenant set. **Actors:** host custodian, P, ordinary tenant user X.

1. Using supported host bootstrap, establish explicit owner identity and required MFA/recovery; sign in to PAC. Attempt same privilege with ordinary account/first registration and verify denial.
2. In PAC wizard create A (hybrid), B (organizer) and C (provider), set locale/timezone, permitted capabilities and initial named administrator. Preview and explicitly approve each. Retry same idempotency request, attempt duplicate slug and invalid profile.
3. Record created tenant IDs and invitation/assignment receipts; simulate failed invitation delivery and retry/reissue without duplicate organization or identity. Existing user enrollment must not overwrite credential or imply verification.
4. Attempt tenant-admin access to PAC/global directory/host operations and global flag changes; verify safe denial at API/DB, not just missing menu.

**Pass:** exactly one organization per successful request; stable IDs; no partial authorized business records after failed transaction; authorized initial-admin onboarding path; no manual SQL for ordinary provisioning; global platform status/brand and other tenants not mutated. Host bootstrap and recovery protected; audit actual host/operator identity. **Evidence:** sanitized PAC wizard/receipts, DB count and RLS role checks, exact denial/no-mutation assertions, audit receipt.

### OLA-02 — Secure administrator enrollment and first sign-in

**Tracks:** #104/#108; PAC identity; OAC-AC-02/03; UX-AC-01. **Level:** L2/L3/L5.

1. Receive A-admin invitation through local capture or approved secure local onboarding; verify recipient identity, establish credentials/MFA under policy, accept membership and initial roles. No password sent or displayed in plaintext. Repeat with existing M identity for an additional tenant; require verified existing sign-in, no credential reset.
2. Redeem token twice concurrently; attempt expired, revoked, wrong purpose and wrong-account acceptance. Try invalid credentials for known and unknown email. Verify workspace names not disclosed until password verified.
3. Sign in with single membership (direct tenant), M (explicit authorized selection), N (member without grants) and active identity without memberships (safe support guidance). Test sign-out/expiry and approved recovery with no external SMTP.
4. Inspect browser storage, URL/referrer and logs for credential/token/other memberships; none present in prohibited locations. Verify actual actor and tenant session, no hidden access from membership alone.

**Pass:** one active intended membership/receipt on valid redemption; replay/wrong recipient denied; no new global account for existing identity; no premature verification assertion; ordinary member has only allowed workspaces; credential-first behavior and MFA policy observed. **Evidence:** auth API/DB and concurrent redemption results, captured synthetic mail metadata (redacted links), browser screenshots and audit/session records. ADR 0015/0017/0020 remain authoritative until reviewed successor.

### OLA-03 — First-login guided configuration and module readiness

**Tracks:** #104/#105/#111; OAC-02/04/06, OAC-AC-04/05/07/09; UX-AC-03/10. **Level:** L3/L4.

1. A-admin first login opens OAC setup. Set profile metadata and authorized defaults, choose modules, optionally inherit platform brand; save partial setup, sign out, resume another browser/device. Configure facilities, commercial policies, communications and people through owning features; return to wizard and observe recomputed readiness.
2. Change profile/timezone using valid revision; concurrently edit same profile from second session; stale write rejected. Verify already configured settings and historical facts not overwritten by wizard.
3. C-admin skips all organizer-only steps. Configure venue/booking form/catalogue/availability and required policy; SMTP unavailable but supported manual booking path remains. Publish only after review; invalid dependency/unsupported module rejected. B-admin with no owned venue can use approved partner projection when available.
4. Test non-admin landing and direct deep link to allowed existing work during incomplete setup. Toggle optional module with existing obligations; preview impact; deny unsafe disable or perform approved drain, verify history remains. Readiness cannot be forced by client state or used as permission.

**Pass:** actual saved state resumes and reflects owning facts; no global all-optional-modules gate; provider usable without event/guest, unauthorized setup denied; active reservations/issued artifacts unchanged; explicit publication/activation, no live email/credentials by wizard. **Evidence:** readiness snapshots/revisions, UI flows, API negative test, DB history and module dependency tests.

### OLA-04 — Organization home, daily navigation and scoped overview

**Tracks:** #104; OAC-AC-06/24; UX-AC-04/05. **Level:** L3/L4.

1. Seed known synthetic counts for inquiries, pending decisions, events and tasks. Open home as A-admin, C-admin, B event manager and finance approver; compare displayed metrics and drill-down filters against authorized fixture queries.
2. Test profile defaults and explicit enabled/disabled capability changes. A user with only an event grant lands on authorized event, not general Registry. User N cannot access business modules by direct route/API.
3. Simulate optional data service failure and stale observation. Check unknown/stale/empty/denied distinction, timestamp/timezone and independent widgets. Search allowed and forbidden terms; attempt favorites/notifications from prior context.

**Pass:** counts equal authorized dataset and definitions, no mixed-currency totals/forbidden cohort inference; route/action hints match current grants; only correct profile/task groups shown; no PAC visibility for tenant. Optional failure does not destroy unrelated work. **Evidence:** expected/actual count fixtures, browser routes, API projection tests and stale-state checks.

### OLA-05 — Independent branding, themes and template authoring

**Tracks:** #111; PAC-M3/TDS-M1–M4; OAC-AC-08/18; UX-AC-09/10. **Level:** L3/L4.

1. P publishes platform default brand. A-admin sets own logos, colors and bs-BA/en footer/identity; B uses distinct brand; preview inherited and allowed venue/event overrides. Draft, publish, edit and rollback as new revision; simulate invalid/missing asset and unsafe SVG/HTML/remote fetch.
2. Toggle personal theme/light/dark/high contrast and language. Verify login safe pre-tenant identity, selected shell brand, event brand, guest/public approved projection, no cross-tenant asset access or enumeration. Validate diacritics and contrast.
3. Authorized TDS designer creates localized rich-text invitation, responsive block email and A5 graphical card with typed fields; preview synthetic recipient and long name, batch PDF/print layout. Test designer without send privilege. Approved issuer sends explicit synthetic batch/test message with appropriate non-live marker for tests. Verify text/HTML multipart, rendered output and correct locale; synthetic preview has no live credential.
4. Publish new brand/template; compare exact digest/revision of previously issued artifact and new authorized output. Ensure old historical bytes preserved, no implicit resend.

**Pass:** distinct A/B brands, correct property precedence and immutable manifests; no rebuild for authorized brand revision; no unsafe asset execution/exfiltration, no extra recipient data from designer; preview/test not actual issuance; old artifact digest unchanged; accessibility and TDS acceptance criteria additionally required. **Evidence:** rendered HTML/text/PDF, manifest/hash, screenshot, SMTP capture, asset negative tests and no extra delivery/credential rows.

### OLA-06 — Tenant staff self-service, role scopes and workspace switching

**Tracks:** #104; ADR 0010/0015; OAC-AC-03/10–12/17/23/24; UX-AC-02/06/15. **Level:** L2/L3/L4.

1. A-admin invites booking, finance, guest and reception staff using graphical authorized workflow only; assign roles at organization/event/station scope within delegation ceiling. Add M existing identity, confirm no disclosure of B membership to A admin. Inspect effective permissions/source/expiry.
2. Sign in as each role. Exercise authorized action and direct API deny for unrelated guest, financial, export, role escalation, PAC and other event/tenant. Create/edit role preset beyond ceiling, grant to proxy account, try managed flag setter; all denied. Member N no business data. A event-scoped guest operator accesses EA1 roster only, not EA2 or Registry.
3. M switches A→B with active tabs, request/subscription and draft state. Verify session rotation, expiry preserved, actual actor, old data and requests cleared, stale links reauthorized. Concurrent revocation/operation records real result; cached reply rechecks authority. Test back/forward and unauthorized search/count.
4. A-admin suspends A membership of M; verify A sessions revoked, B unaffected; restore fresh login and preserved role grants. Attempt suspend last active organization admin or protected host-managed platform member; deny per ADR. Revoke role, expiry, download and stream access; current authorization prevents new actions.

**Pass:** all allowed workflows usable without platform ticket/manual SQL after handoff; no privilege escalation or cross-scope leak; last admin and managed membership protection; exact membership-scoped revocation and actual audit attribution. **Evidence:** runtime-role SQL and API negative matrix, parallel transactions, browser session traces (redacted), role/actor receipts. PAC authority changes tested separately only after reviewed successor migration.

### OLA-07 — Provider-only venue, catalogue and booking lifecycle

**Tracks:** Phase 1/#105/#112; OAC-AC-05/13–15/19; UX-AC-07/08/11. **Level:** L2/L3/L4/L5.

1. C-admin creates own facility/space, resources/services and calendar; validated capacity/availability, prices/taxes/approval/cancellation settings, localized public form. Use simple space without seating/guest setup. Configure setup/teardown buffers and out-of-service resource; preserve existing confirmed reservation on later catalogue change.
2. K submits public inquiry without account; submit invalid and repeat inputs, verify validation and scoped receipt, no booking confirmation/event. C booking manager reviews, drafts, alternatives, prices and offer; finance approval when policy requires; K accepts via scoped link. Attempt unsupported discount or self-approval, wrong-purpose or expired capability.
3. Authorized confirmer confirms; race competing reservation for same resource/time and verify exactly one eligible conflicting commit (or correct count-capacity invariant). Inspect pinned commercial/policy snapshot, calendar and fulfilment tasks. Change price/tax/form revision; previous records retain source facts.
4. Attempt guest Registry, invitation and event endpoints for provider-only without grants/modules; deny. Verify booking completed with zero operational event and guest/admission rows created by booking. Inspect customer projection omits internal notes and unrelated data.

**Pass:** complete provider journey from own configuration through confirmed booking using normal UI/API; atomic resource enforcement, approval and snapshot correctness, no event/guest dependency. **Evidence:** form/offer/approval/reservation IDs, DB counts/constraints, UI receipts, concurrency and negative tests. Existing Phase 1 acceptance and #105 scope remain intact.

### OLA-08 — Amend, cancel or disrupt without conflating business facts

**Tracks:** #112; OAC-AC-15; UX-AC-08. **Level:** L2/L3/L4.

1. Confirm synthetic booking with pinned cancellation policy; customer submits authorized request. Review and approve/reject or return; show consequences and allowed authority. Attempt unapproved execution or wrong actor. Execute approved cancellation once; retry idempotently and inspect release and follow-ups.
2. Test separate amendment/postponement path when supported; revalidate changed resource availability, preserve old offer and decision history; no implied money movement. Provider records disruption with approved public summary; notice alone does not cancel booking/event or automatically send.
3. Explicitly publish scoped notice to linked organizer; organizer acknowledges receipt, then separately reviews appropriate event decision. Verify no automatic event cancellation, guest notification or settlement completion. Deny access to private operational notes. Cross-party delivery/resolution must be genuinely implemented for full scenario; do not count existing record-only slice as done.

**Pass:** request/decision/effective cancellation/reservation release/notice/acknowledgement/resolution distinguishable; no bypass of commercial policy, old snapshots preserved, no unauthorized send or refund claim. **Evidence:** domain states before/after, append-only effects/audit, approved receipt, concurrency/retry tests and minimal projection. All original #112 criteria required.

### OLA-09 — Hybrid organization's own event through event-day operation

**Tracks:** #104/#105/#106/#107/#110/#111; OAC-AC-13/16–19/21; UX-AC-07/08/11/12. **Level:** L3/L4/L5.

1. A-admin or assigned staff configure synthetic hall and prayer-row/count zone, import reference plan and calibrate/draw/label with keyboard alternatives. Review/publish immutable venue revision. Create EA1/EA2 with sessions, timezone, optional modules/responsibilities; duplicate as new draft without credentials/approved facts. Use own venue or explicit booking association, not implicit conversion.
2. Registry manager imports synthetic CSV/XLSX with duplicates/invalid rows, maps headers, reviews matches, commits and tests supervised correction. R1 linked to EA1 and EA2 as one identity with distinct participation. Restricted note/contact only authorized role. Revoke event-only user Registry attempt; preserve historical names/references.
3. Publish authorized registration/invitation template and RSVP policy. Preview synthetic; explicit approved issue/send to test fixture; guest responds via purpose-bound link; staff records correction with audit; policy changes don't rewrite issued snapshot. Assert zero attendance from RSVP.
4. Assign guests manually with hard capacity/exclusions, lock assignments; generate CP-SAT advisory proposal, inspect conflicts/diff, reject infeasible and stale proposal; authorized explicit commit and publication. Guest Portal sees own allocation/map safe projection only, no source geometry/private annotations. Print personalized card/pass through TDS; validate QR and actual dimensions.
5. Issue separate admission credential; scan at two stations concurrently, duplicate/revoked/expired rejected; use manual lookup on camera denial, test bounded offline queue/reconnect/conflict and authorized attendance correction. Assert exactly one attendance subject fact unless explicit audited correction.
6. Event manager enters EOC from portfolio; verify current counts, map revision, tasks/alerts and stale/reconnect. Assign V vendor task, evidence and deadline; V cannot read other tasks/guests. External prerequisite/CDI coordinator records requirement/request/status/authorized completion only, no inspection or confidential data shown publicly. Display sanitized agenda/directions. Close/archive event through lifecycle and report authorized outcomes.

**Pass:** all transitions via owning commands and authorized UI, immutable published venue/plan/template/policy history, advisory solver only, separate credentials/attendance, least-privilege vendor and guest projections, live state truthful. No reliance on platform owner for routine tasks. **Evidence:** exact revision IDs and hashes, DB/API/browser/concurrent scan and worker receipts, PDF/QR decode, actual role negative matrix and cockpit count comparison. All #105–107/#110/TDS specific tests still required; each unsupported subflow blocks full integrated pass.

### OLA-10 — Cross-organization booking and organizer collaboration

**Tracks:** #104/#112/#110; ADR 0004/0006/0021–0024; OAC-AC-05/07/16/20/21; UX-AC-11. **Level:** L2/L3/L4.

1. A as venue provider confirms booking for B organizer. B creates EB; no B guest names in A booking. B requires no owned venue. A proposes exact allowed booking-link grant with empty projection where applicable; B reviews captured names, scope/actions/validity and fingerprint, accepts. Attempt accept by wrong party, stale digest and unauthorized action. No source data permission or global directory from grant.
2. B links eligible booking to EB under authorized event management and accepted scope; inspect permitted venue snapshot only. Verify A cannot view EB roster/RSVP/seat allocation/contact/notes and B cannot read A internal prices/booking data except explicit projection. A/B retain independent membership roles; no implicit cross-tenant context switch. Rename A after proposal: captured name unchanged.
3. Delegate bounded venue/setup task to A operator or V with explicit approval. Provider receives only assigned data. Record notice, explicit cross-party delivery, receipt acknowledgement and separate event resolution; deny unauthorized operations.
4. Revoke/expire grant with concurrent accept/link and retry; new access denied, past link/projection/history provenance retained as policy allows, no cancellation or data overwrite. End association separately under owning command. Try stale cached response.

**Pass:** reviewed exact scope, immutable captured names, separate party ownership, no broad guest/commercial data access; revocation/expiry enforced including retries and jobs; no automatic membership, cancellation, notice send or resolution. **Evidence:** actual grant digest/actor/time/scope, API/DB negative assertions, concurrency cases, browser partner review and association receipts. ADR 0023/0024 programmatic compatibility not silently changed.

### OLA-11 — Authorized support, security, reporting and audit

**Tracks:** PAC-M1/M4, #104/#111; OAC-AC-12/22–25; UX-AC-06/15. **Level:** L2/L3/L4.

1. A-admin requests help on exact synthetic booking/event problem; P inspect safe metadata only. Attempt restricted Registry/contact/export with no grant; deny under approved PAC successor policy. Obtain reviewed narrow support grant with actual actor, reason, expiry and required approval/step-up; organization banner and receipts visible. Perform supported owning correction (e.g. reviewed amendment, not generic status edit).
2. Attempt role self-escalation, unrelated event/other tenant, arbitrary SQL, bypass immutable snapshot, direct host operation or audit edit; deny. Expire/revoke scope while active request, stream, queued export and private download; reauthorize all future access. No invisible impersonation. Test single-owner technical recovery separately with local confirmation; no universal confidential-data self-approval.
3. Authorized A auditor/report operator creates scoped report/export, verify defined counts/columns, safe CSV formula handling, PDF pinned revision and manifest. Deny unauthorized field and download after revoke/expiry. Inject required audit failure and verify privileged mutation rollback. Inspect actual actor vs target and redacted logs.

**Pass:** exact authority and real attribution, no automatic sensitive content or escalation after successor reconciliation; immutable audit/history, safe private exports and fail-closed checks. If reviewed PAC successor not implemented, mark this scenario blocked, not a claim of existing leakage. **Evidence:** PAC and domain audit receipts, negative API/runtime-role tests, revoke race and artifact manifest. PAC-AC-03–07,31–35 remain mandatory.

### OLA-12 — Organization suspension, module drain and restoration

**Tracks:** PAC lifecycle/#104/#108; OAC-AC-09/26; UX-AC-08. **Level:** L2/L3/L4.

1. A requests temporary closure or PAC initiates suspension with known active bookings/events, public forms, partner grants, sessions, queued jobs. Preview exact impact and required approvals. Attempt unsafe suspension or module disable without approved drain; deny or require explicit approved safe policy.
2. Execute approved transition. Check new access/writes and eligible jobs stopped under policy, customer status only if expressly permitted, other tenant sessions of M unaffected by tenant-specific suspension. Verify no implicit booking cancellation, guest deletion, data purge, auto refund or email. Verify historical receipts retained and legal holds intact.
3. Restore via authorized lifecycle/PAC host recovery if necessary; review current memberships, readiness, policies and dependencies. Require explicit reactivation of services/public forms if appropriate, do not restore revoked grants/tokens or resend old deliveries.

**Pass:** reviewed lifecycle effects accurately enforced; no history loss, unrelated organization access intact; restoration validates current authority and explicit activation. **Evidence:** state/queue/session before/after, API denial tests, audit, retained hashes and recovery receipts.

### OLA-13 — Tenant portability, retention and offboarding

**Tracks:** OAC-18/22, PAC governance/#111/#108; OAC-AC-22/27; UX-AC-07. **Level:** L3/L4/L5.

1. Authorized A admin requests machine-readable scoped organization export before planned offboarding. Specify categories, filters and fields, review scope/approval, create bounded job; verify manifest schema/version/relationships/assets/omissions and exact counts vs allowed source. Download via current authorization; test forbidden cross-tenant fields, platform keys, raw capability tokens, other memberships and confidential audit access denied.
2. Submit synthetic privacy correction/anonymization/purge request under approved retention policy. Apply hold concurrently; purge blocked under lock. Review permitted redaction preserving required historical references; execute only approved scoped operation with per-item receipt and no unrelated cascade. No promised removal from all backups.
3. Offboarding request → PAC impact/review/drain/archive with explicit retention, revoke own tenant access and partner grants; retain global identity for B membership. Verify approved export handoff and time-bounded artifact expiry. Restore/reopen only if supported reviewed policy; no automatic reactivation.

**Pass:** export complete within declared scope, omitted items explicit, digest verified, no global/other tenant secrets; retention/holds and independent account preserved; no destructive unreviewed closure. **Evidence:** export manifest and parsed record comparisons, hold/purge concurrency, audit, access expiry. Portability is not physical backup.

### OLA-14 — Integrated reliability, accessibility and security regression

**Tracks:** all; OAC-AC-23/24/28; UX-AC-05/10/13–16; PAC/TDS nonfunctional. **Level:** L2/L3/L4, L5 device evidence.

1. Run fresh and populated upgrade migrations, exact-head OpenAPI/shared types/build/runtime-role/RLS/concurrency/security and secret scan; verify existing ordinary roles/IDs/issued public links/queued jobs/history retained and reviewed PAC permission changes affect only managed lineage. Re-run existing #104–112 tests.
2. Execute representative core workflows using keyboard-only and assistive technology, focus order/error/contrast/labels, drag alternative in TDS/venue/allocation; 360/768/1280/1920 viewport and 200% zoom in Chromium/Firefox, supported mobile/device at final acceptance. bs-BA/en diacritics, date/time/currency and DST; missing required authored translation visible and blocked/approved alternate, no clipping of critical controls.
3. Fault inject optional render/solver/SMTP/storage/realtime failure and interrupted worker/reconnect. Unrelated booking/manual guest work remains available where supported; stale dashboard not zero, retry/reconcile safe, no duplicate external side effect. Test timeout and cancellation receipts, session expiry/revocation and protected artifact download.
4. Measure representative synthetic load (initial proposal 4 vCPU/8 GiB/SSD; record actual hardware/dataset/concurrency), p95 home/readiness/search/commands and queue saturation under booking/check-in; verify agreed budgets and bounded resources, not invented SLO. Run threat model negative matrix (XSS/SSRF/CSRF/role/context/existence leak/credential/unsafe upload). Audit logs contain no credentials or protected values.

**Pass:** required regression suite passes exact tested commit; measured agreed performance and manual accessibility evidence with limitations; no cross-tenant leakage, stale privilege or unsafe retry; explicit partial degradation and recovery. No required missing test labelled pass. **Evidence:** CI runs, actual measurements, accessibility findings, browser captures, fault/concurrency/negative results and known limitations.

### OLA-15 — Final release acceptance on both installation modes

**Tracks:** #108 and Phase 9; OAC-AC-28; UX-AC-16; PAC-M5/M6. **Level:** L5 only.

**Prerequisites:** all required functional modules ready, both production installers delivered, exact release candidate and approved synthetic policies, supported host/device setup, actual test SMTP/TLS arrangements and recovery destination. Reserve the `eventor-acceptance` QEMU/KVM VM for this phase, as previously decided. No need to start it during documentation or ordinary feature development.

1. Clean native Linux install using supported installer, no manual routine DB setup, non-root identities, private PostgreSQL, secrets and TLS. Validate health, configuration, logs and bootstrap owner recovery. Record release/migration/config versions and actual host. Run OLA-01–14 applicable full journey on this mode with synthetic data, plus all original release acceptance gates.
2. Clean production Docker Compose install using same application build/schema/defaults and supported topology, persistent volumes, health/secret/backup paths; repeat journeys and compare equivalent results. No unrestricted Docker socket in API. Test idempotent installer and populated upgrade in both modes.
3. Actual intended public HTTPS/domain/proxy and external SMTP sandbox test with synthetic recipients; record real delivery/provider outcome and security headers, no live guest data. Missing domain/provider/port arrangement blocks those checks; do not invent successful evidence. Local email capture remains supported; no mandatory inbound SMTP server. Test LAN operation when public internet fails where supported.
4. Take encrypted verified backup with independent destination and matching protected keys/config/assets/release. Isolated restore with public ingress/external delivery disabled; validate data, hashes, encryption and RPO/RTO timings. Reconcile revoked memberships/sessions/holds/deleted records/queued deliveries before reopening. Simulate failed upgrade and supported rollback/forward-fix/recovery; never restore old code against incompatible schema. Maintenance/drain and explicit reopen audited. Host recovery works when web unavailable. Verify independent recovery receipt survives restore.
5. Record all required checks, approved limitations and actual evidence. Freeze release only when every mandatory gate passes; fail/blocked/not-run required gates keep release not ready. Compare native/Compose differences and resolve unsupported parity rather than silently waive. Sign-off by available responsible operator/product owner per policy; no fabricated independent reviewer.

**Pass:** clean install and upgrade/recovery both modes, ordinary organization becomes operational and completes required journeys, no security/tenant violations, measured restore/operational targets met and actual external evidence. **Evidence:** installer transcripts redacted, version/checksum manifest, per-mode scenario run records, actual public/SMTP tests, restore/integrity/recovery timing, final signed acceptance report. This test is future work; no VM, external service or environment change is requested now.

## 5. Coverage and release traceability

| Scenario | Main owning issues / prior decisions | OAC criteria | UX criteria |
|---|---|---|---|
| OLA-01 | #104/#108, PAC bootstrap | 01 | — |
| OLA-02 | #104/#108, ADR 0015/0017/0020 | 02,03 | 01 |
| OLA-03 | #104/#105/#111, ADR 0004/0007 | 04,05,07,09 | 03,10 |
| OLA-04 | #104, OAC home | 06,24 | 04,05 |
| OLA-05 | #111, TDS/PAC | 08,18 | 09,10 |
| OLA-06 | #104, ADR 0010/0015 | 03,10,11,12,17,23,24 | 02,06,15 |
| OLA-07 | Phase 1/#105/#112 | 05,13,14,15,19 | 07,08,11 |
| OLA-08 | #112, ADR 0022 | 15 | 08 |
| OLA-09 | #104–107/#110/#111, ADR 0003/0005 | 13,16,17,18,19,21 | 07,08,11,12 |
| OLA-10 | #104/#112/#110, ADR 0006/0021–0024 | 05,07,16,20,21 | 11 |
| OLA-11 | PAC/#104/#111 | 12,22,23,25 | 06,15 |
| OLA-12 | PAC/#104/#108 | 09,26 | 08 |
| OLA-13 | #111/#108, PAC governance | 22,27 | 07 |
| OLA-14 | All, ADR 0008 | 23,24,28 | 05,10,13,14,15,16 |
| OLA-15 | #108 / Phase 9 | 28 | 16 |

IDs in columns are suffixes of OAC-AC-xx and UX-AC-xx. The table covers all 28 OAC and 16 UX criteria. Existing 40 PAC and 25 TDS criteria remain separately traceable in those specifications; no equivalence claim for untested requirements. Original #104–108/#110–112 acceptance checklists and Blueprint §§39/46 plus original acceptance baseline remain required. Add actual links to test implementation/evidence as each domain ships, not invented test paths.

## 6. Proposed release gate and evidence checklist

| Gate | Requirement | Current document status |
|---|---|---|
| G1 | Required domain features and exact-head/post-merge CI verified for candidate | Not run for future candidate |
| G2 | OAC/UX independent onboarding and profile-specific operation, no manual SQL | Not run |
| G3 | Role/field/tenant/collaboration/credential and support boundaries; negative/concurrency tests | Not run |
| G4 | Branding/forms/TDS/render/email/print and historic version integrity | Not run |
| G5 | Event lifecycle including solver review, attendance, vendor and display | Not run |
| G6 | Accessibility/localization/performance/failure recovery measured | Not run |
| G7 | Native + Compose clean install, upgrade, backup/restore and recovery | Not run |
| G8 | Actual target public HTTPS and SMTP sandbox evidence | Not run |
| G9 | All mandatory original and new criteria traceable, no unresolved release-blocking defects | Not run |

Use an acceptance report with explicit gate outcome, candidate commit, environment, test evidence, open defect and responsible reviewer. A waiver is not a pass; any scope change or explicit non-applicability requires product-owner approval and updated requirements, with limitations visible. Do not waive critical isolation, integrity or credential security to claim readiness. No numeric completion percentage derived from the number of scenarios alone.

## 7. Scheduling, Codex continuity and documentation integration

Preserve existing current #104/#112 foundation closure then #105–#107 critical path; #110 coordination, #111 communications/branding and #108 dual installers continue in established roadmap order. OLA evidence is built incrementally with owning vertical slices; not an instruction to implement all new OAC/UX capabilities now, rewrite auth or repeat final VM tests after every PR. OAC-M0–M6 and UX-M0–M5 track proposed planning work packages, no new issue proliferation. Use existing CI/fixture architecture and keep protected host recovery per PAC. No live data or credentials committed, no environment republication. Final VM only Phase 9. Existing docs, accepted ADRs, branches, issue bodies and code remain untouched during preparation.

After approval, integrate OAC/UX/OLA as coordinated v0.3 addenda, link architecture, design index, operating model, roles/permissions, roadmap, gap analysis and shared PAC/TDS boundaries. Add issue cross-references preserving prior obligations, not duplicating implementations or delaying unrelated closure. Future Blueprint v1.3 consolidation separately reviewed. Acceptance methods, actual supported distributions/devices, thresholds, legal/retention policy and real GHB facilities/roles remain decisions for scheduled design and owner validation. This document is a proposed test contract, not completed tests or authorization to modify any environment.
