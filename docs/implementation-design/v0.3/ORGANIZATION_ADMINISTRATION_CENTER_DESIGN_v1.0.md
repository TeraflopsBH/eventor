# Eventor Organization Administration Center (OAC)
## Technical specification v1.0

**Status:** Proposed for product-owner review; not approved for repository integration or implementation.  
**Date:** 2026-11-27. **Inspected main:** `0c5e7a2ddf0a676a89bb75faef1265438dc2ae45`.  
**Proposed destination:** `docs/implementation-design/v0.3/ORGANIZATION_ADMINISTRATION_CENTER_DESIGN_v1.0.md`.  
**Companions:** [UX and Navigation v1.0](EVENTOR_USER_EXPERIENCE_AND_NAVIGATION_v1.0.md) (UX); [Organization Lifecycle Acceptance v1.0](ORGANIZATION_LIFECYCLE_ACCEPTANCE_SCENARIOS_v1.0.md) (OLA). Place all three together at the proposed destination directory.  
**Normative language:** MUST = proposed release requirement, SHOULD = preferred approach with documented exception, MAY = optional. Existing accepted ADRs and validated runtime contracts remain authoritative until formally amended. Numbers, routes, logical entity names and role presets below are proposals, not existing contracts. All examples use synthetic data; GHB is a reference organization, not a hardcoded tenant or assumed operational policy.

## 1. Product objective and scope

An installation owner provisions a customer organization and its initial authorized administrator. That organization can then configure itself and conduct its business through Eventor without routinely asking the platform owner to create staff, enter venues, design booking forms, adjust prices, maintain events or publish invitations. The platform owner retains governance, host operations and controlled support; the organization retains ownership of its business decisions, records and approval policies. Event operators manage individual assigned events. External customers, guests and vendors use scoped surfaces rather than being forced into staff accounts.

OAC is the selected-organization home and administration shell within the existing staff application, with reusable configuration, readiness, portfolio, access and oversight workflows. It is not a new booking/guest database, separate product tier, separate tenant authentication system, new solver or parallel design studio. It MUST compose the existing feature modules and commands, preserve the historical records, and make supported domain workflows discoverable. The UX companion specifies common screen patterns; the OLA companion defines objective release evidence. No billing SaaS, automatic external organization creation, arbitrary SQL, unrestricted data access or external identity provider is required.

### 1.1 Scope boundaries and authority

| Surface | Authority / ownership | Does not imply |
|---|---|---|
| Platform Administration Center (PAC) | Deployment identity, organization lifecycle/provisioning, global security policy, delegated platform roles, host-operation requests | Tenant confidential data, routine business approval, host root |
| OAC | Selected organization's authorized settings, personnel/memberships, portfolio, policies and owned resources | Other organizations' data, global identity mutations, platform admin designation |
| Event Operations Cockpit (EOC) | Authorized event planning/live operations, assigned tasks, approved projections | Registry-wide access or organization administration |
| TDS (Template Design Studio) | Shared editor, asset, template, branding and rendering services; invoked within authorized scope | Issuance, delivery, access to additional fields |
| Customer / guest / vendor / station / displays | Purpose-specific grants, credentials and projections | General staff or tenant membership |
| Host custodian | Installer, OS, DB bootstrap/recovery, protected operations | An ordinary OAC HTTP session or fabricated tenant actor |

This is a hierarchy of contexts, not automatic permission inheritance. An organizer need not own the venue. A venue provider need not operate an event. A hybrid organization may do both without creating duplicate entities. One account can have multiple memberships and multiple independently granted roles; switching changes context, not the person.

## 2. Reconciliation and baseline

Repository read-only inspection confirms existing email-first login, workspace switching, permission-filtered staff tabs, profile settings, member search/role presets/scoped grants/suspension, host initial account/membership commands, booking inquiry/offer/confirmation and cancellation slices, organizer events/sessions, Registry/rosters/import/export, invitation/RSVP, delivery/campaign review, and reviewed collaboration grants. Existing default landing is Events if permitted, otherwise another allowed workspace; a membership alone grants no business-data access. Full OAC dashboard, first-login wizard, tenant self-service staff onboarding/recovery and graphical venue authoring are not established at this baseline. PAC/TDS documentation is merged, not feature implementation. Do not assume every historical issue checklist reflects current runtime; audit exact main before each slice.

| Governing source | OAC alignment |
|---|---|
| [Blueprint v1.2](../../blueprint/v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md) §§4,5,21,24–26,35,41,46 | Scoped administration, optional modules, UI/navigation, governance, cockpit and branding; OAC is the missing organization-level integration |
| [Operating Model](../../OPERATING_MODEL.md) / [Roles](../../product/USER_ROLES_AND_PERMISSIONS_v0.1.md) | Provider/organizer/hybrid presets; independent party roles, approval thresholds and explicit duties |
| [ADR 0001](../../decisions/0001-modular-monolith.md), [0002](../../decisions/0002-self-hosted-deployment.md), [0008](../../decisions/0008-modular-staff-frontend.md) | Modular monolith, self-hosting, incremental feature UI extraction |
| [ADR 0003](../../decisions/0003-human-approved-allocation.md), [0004](../../decisions/0004-optional-event-operations-scope.md), [0005](../../decisions/0005-separate-invitations-rsvp-attendance.md), [0006](../../decisions/0006-cross-organization-collaboration.md) | Advisory solver; optional capability; separate RSVP/admission/attendance; scoped cross-party access |
| [ADR 0007](../../decisions/0007-internationalization.md), [0016](../../decisions/0016-event-rsvp-policy-settings.md) | Locale precedence; versioned policy, not retrospective changes |
| [ADR 0010](../../decisions/0010-organization-membership-access.md), [0015](../../decisions/0015-email-first-login-and-platform-administration.md), [0017](../../decisions/0017-host-staff-account-bootstrap.md), [0020](../../decisions/0020-host-existing-staff-membership.md) | Preserve admin survivability, credential-first auth, managed memberships, host fallback and identity reuse |
| [ADR 0009](../../decisions/0009-guest-registry-merge.md), [0011](../../decisions/0011-database-uuid-compatibility.md), [0012](../../decisions/0012-reference-encryption-identity.md), [0013](../../decisions/0013-reviewed-merge-restoration.md), [0014](../../decisions/0014-registry-profile-labels.md), [0018](../../decisions/0018-reviewed-registry-label-merges.md), [0019](../../decisions/0019-reviewed-registry-relationship-merges.md) | Reuse Registry identity, reference encryption, labels and reviewed merge/restoration; no new parallel identity or reinterpretation of legacy IDs |
| [ADR 0021](../../decisions/0021-booking-event-association-commands.md), [0022](../../decisions/0022-event-disruption-publication-and-acknowledgement.md), [0023](../../decisions/0023-permissioned-collaboration-grant-lifecycle.md), [0024](../../decisions/0024-shared-party-names-and-reviewed-grant-acceptance.md) | Explicit link, notice, acknowledgement, grant proposal/review/accept/revoke; immutable shared names, no global directory inference |
| [PAC v1.0](PLATFORM_ADMINISTRATION_CENTER_DESIGN_v1.0.md), [TDS v1.0](TEMPLATE_DESIGN_STUDIO_DESIGN_v1.0.md) | Reuse platform provisioning, global account authority, settings/module catalogue, brand/assets, delivery and support. No replacement ADR, no duplicate systems. |
| [Project state](../../PROJECT_STATE.md), [Roadmap](../../ROADMAP.md), [Gap analysis](../../BLUEPRINT_TO_REPOSITORY_GAP_ANALYSIS_v1.0.md) | Current work #104/#112 then #105–107; organize later implementation by existing issues; final VM only after coherent release and both installers. |

PAC identifies migration 000187's broad managed-role grants as a discrepancy with Blueprint §4.2. OAC neither changes that behavior nor relies on it for customer onboarding. Follow the reviewed PAC successor ADR and compatibility path when scheduled. Existing platform administrators remain host-managed until that change; OAC cannot modify their protected designation. No claim of exploited leakage follows from the discrepancy.

## 3. Requirements: organization entry and setup

### OAC-01 — Provisioning and secure handoff

PAC creates a unique stable organization identity, operating profile, locale/timezone, allowed capabilities and initial administrator assignment through a reviewed idempotent command. Provisioning and enrollment are separate: a pending or failed invitation does not remove the organization or create duplicate accounts. The administrator is a named individual, not a shared GHB password. Existing identity is reused after verified consent/acceptance; no password replacement or mailbox verification assertion from an administrator's email entry. A customer contact is not a staff account or automatic organization. PAC controls platform-level activation and lifecycle; OAC controls tenant readiness. Host bootstrap/provisioning remains protected fallback per ADRs 0017/0020, including no-SMTP installations. Ordinary onboarding MUST require no manual SQL, host credentials or platform-owner routine intervention after the initial handoff. Initial assignment must preserve a usable authorized administrator; the implementation must account for pending, active, suspended and revoked memberships separately.

### OAC-02 — First-login setup and readiness

After verified credential and required MFA enrollment, a single active membership opens directly; multiple memberships require explicit selection after credential verification (ADR 0015). Enter OAC home; authorized administrators with incomplete setup see a resumable wizard. Other users see their permitted workspace, not forced administrator tasks. Wizard steps are server-derived readiness projections of authoritative settings, not a second database of venue/policy state. Drafts can be saved and resumed from another device; optional steps are skippable, missing dependencies have actionable links; concurrent edits invalidate stale review. Existing organizations are assessed without being forcibly reset to unconfigured or losing published workflows. Show real actor, selected organization and progress per capability.

| Step | Required when | Completion evidence / owning service |
|---|---|---|
| Identity and contacts | All | Valid active profile, contact/support metadata, locale and IANA timezone |
| Operating profile and modules | All | Valid enabled capability set and responsibilities; effective limits from PAC |
| Branding | Optional customization; neutral fallback always available | Published shared brand revision or safe inherited default |
| Facilities and resources | Provider booking or owned venue operations | At least one eligible owned space/resource and approved availability/capacity facts as required |
| Commercial setup | Paid booking enabled | Required current rate/tax/approval/cancellation rules and form, or explicitly configured no-charge/manual policy |
| Communications | Email-dependent actions only | Valid sender/provider and synthetic test receipt; local capture in test, secure manual alternative when supported |
| Personnel | All | Active administrator, required role/approval responsibilities or explicit single-operator policy |
| Templates/forms | Enabled workflows that require them | Valid published form/template and locale coverage, inherited starters where allowed |
| Review/activate | Per capability | Dependency and security checks, reviewed state/revision, explicit publication/activation of relevant service |

Readiness is not access control and does not silently enable modules. Use proposed statuses `not_applicable`, `not_started`, `in_progress`, `blocked`, `ready`, with reason codes, owning route, observed revision and last checked time. Distinguish configuration ready, enabled, deployed supported, published, operational health and permission. Example: booking form ready but not published; SMTP unavailable prevents email delivery, not manual booking; seating disabled does not block RSVP; no venue ownership required for organizer using approved partner plan. Activation validates at command time; never rely on a client checkbox. No global all-or-nothing gate for all optional modules. Safety-critical disabled workflows fail closed. Show readiness changes after edit and impact on current activities; do not silently unpublish old contractual facts.

### OAC-03 — Organization dashboard and work queues

Default landing for authorized organization administrators and users with overview permission: tailored provider/organizer/hybrid home. Other staff land on permitted tasks/assigned event/explicit safe deep link. Cards show permitted counts and actionable queues: inquiries awaiting assignment, drafts/offers/approvals, reservation calendar conflicts, venue readiness, upcoming/active events, incomplete setup, RSVP/guest summary for authorized event scope, delivery issues, collaboration notices, assigned tasks and upcoming deadlines. Define metric source, exact status/time window, selected organization/event/venue, locale/timezone, observedAt and freshness; missing/denied/unknown not zero. Financial totals by currency with approved definition; no mixed-currency sum or inferred revenue from offers. Guest aggregates require corresponding authorization; no inference from forbidden search counts or small sensitive cohorts. Query bounded/paginated read models; drill-down uses the same scope/policy. User preferences for visible widgets cannot broaden data access. Work queue badges reflect authoritative actionability, not merely presence of records. Empty state links to legitimate creation/configuration; no fake demo data in live tenant. Dashboard remains usable when optional worker is degraded.

### OAC-04 — Organization profile

Manage own display/legal names and approved localized variants, contact/address/website, support and administrative contact, default locale/timezone, operating profile, allowed identifiers and policy metadata. Stable organization ID/slug and public URLs have controlled changes/aliases, impact validation, no automatic impersonation or routing takeover. Validate structured fields, revisions and audit. Distinguish legal party, brand label and booking/event snapshot; rename does not retroactively alter shared names, offers, issued artifacts or history. Do not invent required GHB registration/tax/legal facts; configuration requires evidence and owner confirmation. Existing profile APIs extended rather than recreated.

### OAC-05 — Identity, branding and preferences

Use TDS shared brand profiles/revisions and PAC platform default. Organization administrator manages authorized logos, wordmark, safe SVG/PNG, semantic palette, typography, localized footer/contact, permitted login/public-page treatment and reusable default templates. Venue/event approved overrides only within assigned ownership. Per-property precedence event → authorized venue → organization → platform default; no automatic sharing across partners. Draft/preview/publish/rollback via new revision, validate contrast and safe assets, immutable prior outputs pin exact brand/template. Pre-login unknown organization sees safe platform identity; no account/tenant discovery through email. Personal light/dark/system/high-contrast preference separate from external brand; preserve mandatory legal/security attribution. Do not expose arbitrary HTML/CSS/JS, external asset fetch or login field capture. Shared service contract as PAC-08/TDS-08/09; no competing branding tables.

### OAC-06 — Operating profiles, capabilities and configuration

Profiles are defaults, not paywalls (ADR 0004). Provider: bookings/resources/services/approval and venue tasks default; organizer: events/guest/invitations and optional operations; hybrid combines. Any permitted module may be explicitly selected as needed. Effective capability = installed/supported × deployment availability/policy × organization selection × applicable booking/event activation × dependency readiness; permission checked separately for each operation. Profile change offers diff and impact; no silent mass toggle, migration of ownership or deletion. Dependency graph narrow, acyclic; RSVP independent of seating; check-in separate from invitation/RSVP, supports approved manual subject lookup; venue booking independent of events. Disabled module history remains readable where authorized; active workflows require reviewed drain/transition or block disable; no implicit cancellation, reservation release or credential invalidation. Use PAC typed settings registry (scope, type, revision, defaults, allowed override, safety floor, impact); tenant settings cannot modify global security, host environment or arbitrary config. Public activation explicit and revision-pinned.

## 4. Requirements: organization governance and staff

### OAC-07 — Organization owner and administrator

Organization owner governs tenant settings, appoints authorized administrators and reviews policy; administrator operates delegated tenant capabilities. Neither can designate platform administrators, view other tenant memberships, bypass approvals or automatically access restricted data. Model role presets over the existing catalogue, not new privileged account flags without ADR. Protect system-managed roles and prevent last usable organization administrator lockout per ADR 0010 (another active user with active organization-wide organization.manage for suspension). Extend guard to any proposed revoke/deactivate/transfer path through reviewed compatibility design. Owner transfer, if introduced, is reviewed, verified successor acceptance and auditable atomic grant/revoke, retains independent roles; PAC recovery if no usable admin. Single-operator sites can run ordinary workflows where policy permits; do not fake independent approval or require unavailable staff for all actions. Configurable dual control/thresholds for sensitive commercial/other high-impact actions. No owner self-promotion into platform or secret visibility.

### OAC-08 — Tenant staff self-service

Authorized GHB administrator invites existing/new named employees by email or documented secure no-SMTP alternative. Proposed enrollment service shared with PAC: typed invitation purpose, selected organization, allowed proposed role(s) within delegation ceiling, token hash, expiry, revocation, attempt/rate limits and one-time redemption. For existing global identity require sign-in/re-authentication and confirmed recipient binding; do not leak account existence, other memberships or reset password. New recipient proves mailbox/control as policy requires and creates credentials/MFA, accepts tenant invitation; no verified assertion merely because invitation sent. No plaintext password email, raw token in logs or browser storage. Pending invitations can be listed, reissued/revoked, stale tokens invalidated; duplicate/case-insensitive identity collision and concurrent redemption safe. Membership may be created before acceptance only if safely nonactive, reconcile existing states. Role grants explicit, reviewed by an authorized assigner, not automatic by identity. Account recovery belongs to global identity service: tenant admin may initiate approved reset invitation, cannot read/reset another tenant's credentials directly or globally disable an account. Tenant suspension revokes sessions for this membership only; restoration preserves grants and requires fresh login/active global user (ADR 0010). Platform-managed memberships identified and protected per ADR 0015. Ordinary organization onboarding requires neither shell commands nor platform-owner ticket; host fallback remains for initial bootstrap/recovery.

### OAC-09 — Access, roles and responsibility

| Role preset (illustrative) | Typical scope/actions | Explicit exclusions / additional grants |
|---|---|---|
| Organization owner/admin | Tenant profile, policies, members, allowed modules, administrative oversight | No global account list/host operations; sensitive guest/finance/export independently authorized |
| Director / approver | Own-tenant authorized aggregate overview and configured decisions | No automatic edit or self-approval |
| Booking manager | Inquiries, drafts, offer preparation, confirmation/cancellation where granted | Commercial exception approval separate |
| Finance | Price/tax, commercial review and approved consequences | No general guest data; no money movement claim |
| Venue/resources coordinator | Owned spaces, calendars, setup, equipment/services | No unrelated organizer records |
| Event manager | Assigned event/session/config/operations | No Registry-wide access from event grant |
| Guest-list / Registry manager | Authorized profiles/rosters, import/merge/correction | Field permissions, export/merge separate |
| Communications designer/operator | TDS source/design or reviewed audience/send | Design not send; no extra data via variables |
| Allocation / plan approver | Event geometry/proposals, approval/publication as granted | No solver auto-commit; no edit of approved revision |
| Reception / gate / zone | Assigned station/zone, minimal lookup/scan | No broad exports or Registry |
| Vendor / collaborator | Explicit task/booking/event projection | No membership or cross-tenant directory implied |
| Auditor | Authorized read/export separately | No write |

Permission checks use active actor/session/selected org + scope + role/grant validity + action/field sensitivity + module/policy/state + approval as applicable; fail closed. Delegator may grant only explicitly delegable subset of own ceiling, not merely any permission they can use; no escalation through role edits, clone/import, proxy account, approval or support. Show effective access provenance (role, scope, issuer, expiry, managed vs ordinary), impact of change, and pending/effective distinction. Reuse tenant access lock and optimistic revisions; concurrent revoke/action has serialized or documented committed outcome. Revoke removes future operations, subscriptions and downloads; ordinary independent memberships/roles retained. For assigned tasks, record accountable/performing/approving/informed parties, deadlines, not-applicable/external status and scoped data, not implied legal liability. Audit actual actor and target; hide protected actions but enforce server-side regardless of UI.

## 5. Requirements: daily business administration

### OAC-10 — Venue and facility portfolio (#105)

Authorized organization staff create and maintain owned sites/buildings/levels/rooms/spaces and templates, addresses, operating calendars, availability/closure, safe capacities, accessibility and layout metadata. Resource hierarchies are distinct from geometry. Support hall/meeting/prayer/other neutral templates, source PDF/image/SVG/workbook import with original provenance, scale calibration, layers, non-allocatable features, rows/table/position/count zones and human validation. Use #105 spatial commands and revisions, no parallel venue aggregate. Publish immutable geometry/capacity snapshot; edit draft, review conflicts against bookings/plans, explicitly adopt new version. Do not assume GHB actual capacities or map labels; no real private plans in Git. Partner venue access via approved projection/grant, no edit of provider's source geometry from organizer context. Venue-only setup can start with validated non-seating spaces and calendars.

### OAC-11 — Resources, equipment and services (#105/#110/Phase 1)

Manage tenant-owned inventory/resource types, count/units, reusable service catalogue, setup/teardown/rehearsal buffers, availability/out-of-service, dependency, maintenance, task responsibility and authorized charges. Separate physical allocatable resources from commercial catalogues and consumables; units/capacity/date validation; prevent concurrent double-reservation using existing reservation authority. Effective-dated or revisioned changes; deactivation blocks new use, does not silently release confirmed reservation. Staff assignment and equipment usage restricted to appropriate scope. Venue service fulfilment has status/readiness and issues, no assertion of external completion without authorized evidence. Do not implement payroll or inventory purchasing system by implication.

### OAC-12 — Booking and commercial operations (Phase 1/#112)

Booking overview, filtered inquiry queue, calendar (list and accessible grid), direct staff booking where supported, configurable published public form, assignment/clarification, draft/revision, availability/alternatives, price/tax/discount/approval policy, offer, customer decision, approval and confirmation using existing commands. Separate requester, contracting party/payer, provider and organizer. Atomic capacity recheck on confirmation; immutable offer/price/tax/cancellation snapshots; approved amendment/cancellation and resource release; consequence preview and settlement follow-up, no claim of payment/refund automation. Venue disruption is separate from effective cancellation; notice recording, explicit delivery, acknowledgement and organizer resolution separate. Provider can run booking-only without event conversion, guest names or RSVP. Hybrid organization may explicitly associate its own or a partner booking to an event under existing authorization. Calendar never leaks other tenant private schedule; show busy only when permitted. Domain states and commands authoritative, not a generic status editor.

### OAC-13 — Event portfolio (#104/#106/#107)

Authorized portfolio across own assigned events, filters/calendar by lifecycle/date/venue, create bilingual event and sessions, time zone, title/programme, ownership, responsibility, optional capability defaults and settings. Duplicate as new draft only with explicit safe copy choices (no guests/credentials/approvals/history/reservations by default); no duplicate booking facts. Lifecycle planning/review/approve/publish/start/close/archive as existing; cancellation/postponement explicit authorized commands with booking/provider coordination independent. Event summary shows authorized readiness/RSVP/allocation/attendance/tasks and links into EOC with exact event context. Manual seating and human-reviewed solver (ADR 0003) use #106; plans immutable after publication. RSVP, eligibility, QR admission and attendance separate (#107). No automatic publish or bulk send on event creation. Cross-event reporting only authorized and correctly defined.

### OAC-14 — Persistent Guest Registry (#104)

Use current Registry and roster feature paths. Organization-level identity, separate event participation/pinned display history, contacts/references/classifications/relationships and role/field-scoped custom data/notes. Authorized staff create/search/edit/archive, reviewed mapped CSV/XLSX import with row diagnostics, duplicates and match confirmation, approved merges/restoration and permission-filtered exports/saved views/bulk operations. No direct overwrites of protected references or history; preserve consent, source provenance and identity encryption compatibility; unresolved conflicts blocked with review. Event-only grant never gives general Registry. Venue-only workflows do not collect organizer guest data. Minimize sensitive/special-category data, purpose and retention policies, access audit, no real records in fixtures. No automatic cross-tenant identity deduplication.

### OAC-15 — Communications and TDS (#111)

Organization-level access to shared TDS library, branded rich-text/email/graphical editor, locale variants, safe assets/typed variables, review/publish, PDF/print and retained historical manifest. Template rights separate from recipient view, invitation/credential issue and send rights. Existing SMTP/provider configuration (PAC defaults and authorized tenant override), write-only credentials/masked status, local capture and separate synthetic test; approved sender routing and rate limits. Authorized audience preview/digest, explicit issue/reissue/revoke/reminder and send, delivery state/uncertain reconciliation, cancel eligible unsent, no blind retry. TDS preview/save/publish never creates live credentials or sends. Use distinct public RSVP/admission links; no hidden external tracking. Event/booking/legal snapshots and language fallback follow TDS/ADR 0007. Organization admin can self-manage communications within approved policy, without platform approval for every message.

### OAC-16 — Public forms and requests (#111/Phase 1/#110)

Compose/reuse versioned booking, guest registration and vendor/staff request forms using owning form schema/commands; do not duplicate booking form engine or confuse TDS layouts with submission data contracts. Configure typed fields, required/optional/validation, localized labels/help/consent/notice, allowed attachment policy, conditional visibility with bounded rules, brand and authorized destination. Preview synthetic, review/publish immutable revision, public stable scoped link and controlled withdrawal; responses pin form revision, server validates even if client changed. Spam/rate limits, anti-enumeration, safe upload quarantine, no scripts/arbitrary SQL or collection of unnecessary sensitive data. A submission is request, not confirmed booking, guest identity merge, RSVP approval or vendor acceptance. Staff inbox/assignment/review/resolve with receipts, safe exports and retention. Guest-specific forms require appropriate scoped token; public booking does not require staff login. No public guest directory.

### OAC-17 — Vendors, staff and cross-organization collaboration (#110/#112)

Maintain own contacts/service/task catalogue and responsibility assignments. Invite/assign staff and vendors to bounded event/venue/task, deliverables/deadlines/status, evidence, communication history; external vendor does not gain tenant membership unless explicitly separately onboarded. External prerequisites/CDI track coordination request, responsible authority, schedule and authorized confirmation, restricted references only, not inspection or law-enforcement activity. Partner access uses existing proposal → exact scope/actions/projection review + fingerprint → recipient acceptance → effective validity → revoke/expire. Preserve ADR 0023/0024 captured names and stale review/retry checks; no global org directory or source-data permission from names/booking link. Provider receives its booking and contracted service info; organizer owns guests/RSVP and plan; explicit partner grant only for named tasks/data. Notice publication/acknowledgement not resolution/cancellation; retain history on revoke without new access. Vendor UI shows only assigned projection and role/task scope; actual actor/evidence audited.

## 6. Requirements: administration, navigation and exit

### OAC-18 — Reports, exports and tenant data governance

Scoped reports by authorized venue/booking/event/guest/delivery/task data; filters, date range/timezone, definitions and source freshness. Separate read, export and sensitive fields; verify authorization at creation/execution/download, bounded jobs, encrypted private artifacts and audited receipts. CSV/XLSX formula-injection safety, PDF/TDS pinned templates/brand, machine-readable stable IDs and schema/version. No automatic report privilege by dashboard widget. Configure tenant retention/defaults within PAC safety and legal policy; holds, privacy request review and lawful correction/purge/anonymization with scope, impact, approval and retained required history. Use PAC governance service; no raw DB dump or arbitrary destructive SQL. Portability includes authorized own records/relationships/assets and manifest, no platform credentials, other organizations' source records, live capabilities or protected global audit; explicitly list omissions. Export ≠ backup/restore; PAC/host owns physical recovery. Actual retention/legal requirements must be approved, not assumed.

### OAC-19 — Security, privacy and audit

Use existing Argon2id/session, credential-first login/rate limit/CSRF and selected-tenant RLS, least privilege; PAC shared MFA and recovery when implemented, require privileged MFA at release. Tenant policy can strengthen platform floor, never weaken. Session/access review limited to own membership, actual actor, scoped grants; do not expose global account directory or host secrets. Every domain command validates scope/state/approval on server; actor not client supplied, tenant composite FKs, transaction-local context and pool reset. Approvals pin target/payload/revision/policy/expiry; stale/permission change rejects; idempotency scope actor/action/target+fingerprint, current authorization even cached response. Record append-only audit for configuration, access, sensitive reads/exports and mutations, actor/target/context/reason/diff or safe digest/time/correlation and approval receipt; no tokens, keys, passwords, guest contacts in logs. Audit failure blocks required privileged mutation/read. Private asset/export isolation, no remote arbitrary fetch, safe uploads, bounded queues/search/metrics, no side-channel counts. Realtime subscriptions authorize on connect and revalidate on revoke; UI clears data. No silent impersonation or bypass; host recovery separate.

### OAC-20 — Unified navigation and UX

Adopt UX companion as common contract: stable scoped routes, profile- and permission-aware navigation, overview/setup landing, shared search/notification/task primitives, consistent breadcrumbs/headers/tables/forms/validation/empty/error/loading states, responsive keyboard-accessible controls, explicit preview/commit for high impact, server-derived capability hints. Organization and event context visibly distinct; events link to EOC; PAC reachable only by authorized explicit transition; TDS within appropriate context. Existing feature tabs and deep links remain supported until migrated incrementally (ADR 0008). No all-at-once frontend rewrite or requirement that all features wait for new shell. Future components use shared primitives as touched. Bosnian/English and accessible light/dark/system modes; safe date/currency formatting. UX preferences never grant permission or change domain facts.

### OAC-21 — Platform support and interventions

OAC provides support contact, case creation with consent/scope/purpose, minimal safe diagnostic bundle, pending/active/revoked grant status and authorized activity receipt. Reuse PAC levels inspect/administer/emergency, real platform actor, explicit data authority and scoped/expiring permissions; no invisible impersonation or blanket access. Tenant may request assistance, cannot grant platform designation or waive integrity/approval constraints. Only owning commands correct booking, event, guest, plan, attendance or campaign; unsupported commands show request-only. Sensitive support approval per reviewed PAC policy; single-owner host recovery only for defined technical recovery, not universal self-grant. Revoke/expiry closes new operations and streams/jobs/downloads; history retained. No tenant ability to execute host ops.

### OAC-22 — Lifecycle, portability and offboarding

Tenant admin may prepare organization closure/export/transfer request; actual platform organization suspension/archive/restore remains PAC-controlled. Impact preview includes active bookings/events, public forms/links, collaboration, queued deliveries/jobs, sessions, legal holds and retained obligations. Approved drain or block unsafe transition; preserve history and necessary scoped customer access only as policy permits. No implicit event cancellation, payment/refund, data purge or destructive archive. Revocation of memberships/partner grants scoped and auditable; preserve global identity if other memberships. Portability manifest and time-bounded private authorized export before closure or controlled after under policy; verify delivery, retention/hold, safe anonymization/purge through governance jobs. Restoration requires reviewed profile/capability/role readiness and current authority; not automatic public reactivation, resending messages or resurrecting tokens. Backup/PITR restoration belongs to host/PAC, reconcile revoked access/holds/deleted data/delivery before reopening. No promised statutory retention or contractual liability without owner evidence.

## 7. Technical architecture and authority boundaries

```text
PAC provisioning / policy / support      Protected host CLI / installer
            | reviewed handoff                      | out-of-band recovery
            v                                       v
Staff HTTPS → email-first session → selected tenant → OAC shell
                                      |             | readiness, overview, navigation
                                      |             v
                                      +→ feature composables / API client
                                         → Fastify scoped commands and read models
                                         → existing PostgreSQL aggregates + forced RLS
                                         → audit / outbox / bounded jobs
                                         → existing workers, TDS render service, solver
                                         → EOC / authorized role-specific projections
Public booking / guest / vendor / station / display → distinct scoped endpoints
```

OAC is a Vue 3/TypeScript feature composition with shared UI components, locale/formatting utilities and modular state. Proposed areas `features/organization-home`, `features/organization-onboarding`, `features/organization-access` (extend existing), `features/application-shell` (extend incrementally). Existing booking/event/Registry/features stay owning modules. Fastify domain service for readiness aggregates, scoped overview/search and tenant enrollment orchestration delegates to authoritative commands and shared identity/PAC/TDS services. No new database owner access or browser-to-DB; explicit API pool roles, narrowly reviewed SECURITY DEFINER functions only as necessary, pinned search path and revoked PUBLIC grants. Control-plane global identity lookup and issuance via narrow approved service, never tenant table unrestricted SELECT. Transactional mutation, audit and outbox; protected jobs use scoped actor/target and current authority, recheck eligibility on delayed execution. Render/solver workers have bounded sanitized projection. Service principal separate from human. Do not add new mandatory infrastructure. Native and Compose same application build/security. Failures isolated; unavailable optional module does not block unrelated work.

### 7.1 Permission resolution and readiness contract

Proposed server logic (illustrative, not code): resolve authenticated principal → validate active account/session/selected membership and current context → exact operation/resource scope → applicable capability and state/policy → field-level projection/approval/step-up requirements → execute through domain command with audit. Navigation/readiness signals computed from same current policy, not authority tokens. A blocked capability may still allow permitted read-only history, readiness editing or support request; server distinguishes those actions. A delegated grant's scope cannot expand on tenant switch. Data from old organization must not survive client cache/subscription transitions. Public surfaces do not inherit staff authorization even in same browser. Hidden/disabled UI controls are not security boundaries.

## 8. Logical data model (proposed, not DDL)

Audit current schema, constraints, RLS, command surfaces and ownership first. Prefer projections and existing aggregates; add tables only where durable new facts require them. Stable UUIDs including supported legacy variants; tenant-owned entities carry organization_id with composite foreign keys. UTC instants and explicit IANA timezone; BCP 47 locale; no translated domain codes. Private global relations remain inaccessible to ordinary tenant/runtime roles; narrow identity provisioning procedure may write only a validated organization membership/enrollment through approved command. Distinguish source records, configuration revisions and derived read models. No persisted "completed" flag substitutes for validation.

| Logical entity | Facts / invariants |
|---|---|
| organizations / profile settings (existing) | Stable ID, slug, status, operating profile, default locale/timezone, revision; extend authorized localized metadata only as needed |
| users / memberships / roles / grants / sessions (existing) | Identity and case-insensitive uniqueness; membership scoped; independent grants/expiry/actual actor, protected managed lineage and admin survivability |
| Enrollment invitation / recovery (shared with PAC, proposed extension) | Purpose, tenant, recipient binding, proposed delegated grants, token digest, expiry/status, issuer/review/acceptor, consumed/revoked timestamps; no raw token at rest in general table; global reset separate |
| Setup checklist state (optional new) | Tenant, step key/version, dismissed optional step or last selected step, actor/time/revision; readiness recomputed from authoritative facts; no credential/PII draft copied into checklist |
| Effective capability / config assignments (reuse PAC) | Scope, typed setting/module, version, default/override and readiness/drain; dependencies/limits and pinned review |
| Organization policies (existing where available) | Approval, commercial, RSVP, communication, retention etc. managed by owning module with pinned revisions |
| Shared brand/asset/template revisions (TDS/PAC) | Tenant ownership, immutable dependencies, approved published revision and safe inherited defaults |
| Venue, space, resource/service catalogue / reservation (existing/future #105) | Owning tenant, hierarchy, versioned geometry/capacity/catalogue, conflict authority and immutable booking facts |
| Booking/form/inquiry/draft/offer/cancellation (existing) | Distinct parties, purpose-scoped links, valid lifecycle, immutable commercial/policy revision; no implicit event conversion |
| Event/session/participation/Registry/invitation (existing) | Separate identity/participation/RSVP/admission/attendance, scope, actual actor, pinned history |
| Allocation/plan/station/attendance (#106/107) | Owning event, approved version, credential purpose, conflict/concurrency invariants |
| Collaboration grant/task/evidence (#110/112) | Explicit parties/scope/actions/projection/validity, immutable shared name and reviewed digest, assignment/evidence/audit |
| User preferences/saved views (reuse/extend) | Actor and allowed scope, stable widget/view IDs, non-sensitive settings; no cached unauthorized data |
| Overview/search/work queue projections | Derived authorized bounded read models with definitions and freshness; rebuildable, no business truth |
| Tenant notice / task notification | Typed reference to owning object, intended user/scope, safe title/state/time; reauthorize on open, no secret payload |
| Support / governance / export jobs (PAC/existing) | Scope/actor/approval/digest/lease/state/expiry, private artifact manifest and access audit |
| Audit / outbox (existing) | Actual actor, context, target, reason and safe revision/receipt, atomic command; append-only, no raw credentials |

Required constraints: identity uniqueness/concurrent enrollment, membership and delegated ceiling, last active admin protection, tenant foreign keys and owner scope, immutable snapshots, approval/digest precondition, idempotency and grant/revocation ordering, bounded retention/hold and audit. Model migration additive/forward only; do not rewrite v0.2 SQL/OpenAPI snapshots, historical migrations or accepted ADRs. Populate existing organizations using validated read projections, not guessed legal profile/brand or "complete" flags. Preserve existing sessions/IDs/URLs where compatible; incompatible auth changes require PAC successor ADR and explicit recovery. Migration tests fresh + populated, preserved source/legacy IDs/queued jobs and historical artifacts. No mandatory OAC table fork.

## 9. API design and shared contracts

These are conceptual operation families, not current OpenAPI endpoints. Audit actual Fastify registrations and `docs/api/openapi.v0.3.yaml` first; reuse existing paths/operation IDs where possible. All organization commands use selected authenticated tenant context and verify path ID; no caller-supplied actor or arbitrary target tenant. Public enrollment is purpose-bound, not a general user directory. CSRF/origin for staff mutations; pagination, validation, safe redacted errors, consistent time/locale, authorized fields only. Existing `/me/workspaces` navigation hints extend compatibly, never grant authority.

| Family / illustrative endpoint | Contract / reuse |
|---|---|
| GET /me, /me/workspaces | Existing principal, memberships, locale, safe available feature IDs; extend capability hints under versioning |
| POST /me/workspace-switch | Existing ADR 0015 semantics, actual actor/session rotation/expiry, clear context |
| GET /organizations/{orgId}/home | Typed profile-aware cards/work queue/authorized counts and timestamps; partial section errors, no hidden counts |
| GET /organizations/{orgId}/setup-readiness | Per-capability steps, statuses/reasons/dependencies/owning links/revisions/observedAt; safe projection |
| PATCH /organizations/{orgId}/setup-preferences | Optional dismissal/resume pointer, expected revision; cannot force ready |
| POST /organizations/{orgId}/activation-reviews; .../activate | Validated module/public service impact, review digest, explicit command; delegate to owning publisher |
| GET/PATCH /organizations/{orgId}/profile | Reuse existing revision-checked settings; authorized fields |
| GET /organizations/{orgId}/effective-settings; POST .../change-requests | PAC shared typed config/dependencies; allowed overrides and impact/digest |
| GET/POST .../staff-invitations; .../{id}/revoke or reissue | Tenant scoped authorized invitation issue; proposed role ceiling; masked state; retry safe |
| POST /staff-enrollment/accept | Purpose-bound token + identity verification; atomic one-time acceptance; no account enumeration |
| POST .../members/{id}/recovery-requests | Initiate shared recovery workflow, not direct password reset or global disable |
| .../members, .../roles, .../grants | Reuse existing access directory/search/preset/assign/revoke/suspend/restore; current scope and last-admin guard |
| GET .../members/{id}/effective-access | Explicit provenance/expiry/ceiling; no other membership data |
| GET .../calendar, .../search, .../work-items | Scoped bounded read projections; no search side channel, page/sort filters; safe references only |
| .../venues, .../resources, .../services | #105/Phase 1 owning commands; versioned capacity/catalogue and booking conflict checks |
| .../booking-*, .../events, .../registry, .../guest-lists | Existing business command families; OAC links/compose, not replacement generic CRUD |
| .../brand-profiles, .../templates, .../forms | Shared TDS and form owner command families; validated draft/review/publish |
| .../delivery-configuration, .../campaigns | Existing worker/config/approval/reconciliation; safe synthetic test and masked secrets |
| .../collaboration-grants, .../tasks | Existing reviewed grant lifecycle/owning task commands; exact scope and review fingerprint |
| .../report-jobs, .../governance-requests | Scoped preview, approval, bounded job, authorized artifact download |
| .../support-cases, .../closure-requests | PAC request/receipt only for global action, no direct platform/host command |

Suggested readiness response fields: `organizationId`, `profile`, `observedAt`, `configurationRevision`, `capabilities[]` each `{key, installed, permittedByPlatform, configuredEnabled, readiness, effectiveState, reasons[], steps[]}` where each step has `key`, `status`, `required`, `sourceRevision`, `actionRef` (allowlisted internal route ID and safe target). Do not disclose forbidden missing resource IDs. Overview item `{key, scope, definitionKey, asOf, window, value?, status, link?}` distinguishes denied/unknown/no records, suppress denied widgets entirely where appropriate. Work item `{kind, resourceRef, actionHint, status, dueAt?, revision}` never grants action. Return structured problem codes with correlation ID, not SQL/PII. Mutations use existing optimistic version / expectedRevision convention; idempotency with canonical payload fingerprint, duplicate same result after auth recheck, mismatch conflict. 202 = pending not success; stale conflict (409 or existing convention), validation error, auth required/denied/non-enumerating not found, rate limit/unavailable. Domain command does not infer approval from readiness. OpenAPI/shared types/contract tests updated alongside implementation only.

## 10. Security and failure cases

| Threat / failure | Required protection |
|---|---|
| Tenant context bleed, guessed ID, cross-org search/count | RLS/composite FKs, exact scope, bounded projections and per-request context, no forbidden existence oracle; revoke/clear caches |
| Tenant admin creates global identity or grants above own authority | Shared purpose-bound enrollment, verified recipient, delegation ceiling, protected system roles, no self-escalation or global flag change |
| Invitation reuse or race with revoke | Hashed purpose-bound short-lived token, single-use under lock; no logs; verify current invitation/recipient/role on redemption |
| Last admin suspended or global identity locked | ADR 0010 guard, audit all equivalent paths, host/PAC recovery for exceptional case |
| Disabled module/dependency or stale wizard | Server validates operation and relevant revisions; readiness != permission; explicit drain and review |
| Stale approval / double booking / repeated send | Digest+expected revision, authoritative locks, idempotency and worker reconciliation; no blind retry |
| Leakage via reporting, template bindings, notifications or assets | Scope/field-specific allowlists, TDS safe variables, current artifact auth, public-safe projections, no external fetch |
| Misleading support impersonation | Actual actor, time-bound approved access, visible scope, revoke/expiry and sensitive access audit |
| Malicious forms/uploads/branding | Strict schemas, sanitized assets, safe upload quarantine, limits, CSP and no arbitrary scripts/CSS/SSRF |
| Backup restore reintroduces revoked rights or queued external actions | PAC protected restore/reconcile before reopening; OAC status truthful |
| Partial infrastructure outage | Isolate optional features, stale timestamps and safe retry; do not declare unavailable counts as zero or send/confirm as success |

Security tests include negative API and actual PostgreSQL runtime-role cases, not just hidden tabs. RLS forced and tenant contexts tested under concurrency. MFA methods, host workflow, approval exceptions and legal retention follow PAC reviewed decisions; no new direct owner privilege or generic override introduced here.

## 11. Non-functional and implementation quality

Initial proposed reference class: 4 vCPU/8 GiB/SSD, representative synthetic datasets; benchmark before setting binding SLOs. Measure p95 home/readiness and page transitions, large Registry/booking lists, scope-filtered search, concurrent booking and check-in under job load, API/worker/storage failures and browser accessibility. Bound query pages/results, search terms, export sizes, attachment sizes and background concurrency; report real measured limits and safe degradation. No UI load of all tenants, guests or history to calculate totals. Keyboard, focus, error recovery, accessible tables/alternatives, bs-BA/en diacritics, DST and locale formatting per UX. Self-hosted no mandatory cloud, optional internet/email; local capture in CI. Native/Compose parity per #108. No secrets or real guest/venue information in source, fixtures, CI logs or screenshots. Use synthetic fixtures and exact commit evidence; no production readiness claim from passing docs CI.

## 12. Milestones and issue reconciliation

Work packages are planning references, not a replacement roadmap or new issue queue. Keep all existing issue requirements; integrate only scheduled vertical slices. Each slice includes current schema/command audit, authorization, migrations if needed, API/shared types, feature UI, tests and docs. Never count a schema foundation as a completed workflow.

| Work package | Deliverables / dependencies | Existing track |
|---|---|---|
| OAC-M0 | Inventory current routes/roles/readiness/domain states, UX/authority review; agree shared PAC enrollment/branding/settings contracts, no immediate auth rewrite | Architecture + #104; ADR review |
| OAC-M1 | Incremental organization shell/home, profile/readiness, role and setup projections; safe onboarding/self-service when shared identity ready | Phase 2 #104, PAC-M1/M2; #108 bootstrap |
| OAC-M2 | Provider booking overview/calendar and independent facilities/resources/services; existing commercial and disruption closure | Phase 1 and #105/#112, #110 fulfilment |
| OAC-M3 | Event portfolio, Registry integration, EOC transitions, allocation/admission/task/collaboration integration | #104/#106/#107/#110/#112 Phases 2–6 |
| OAC-M4 | Organization identity/brand, TDS, communications, forms, policy/module controls, reports/portability and governance | Phase 7 #111, TDS and PAC-M3/M4 |
| OAC-M5 | Secure provisioning, host recovery, closure, dual installers, accessibility/operational readiness | #108, PAC-M5; Phase 8 |
| OAC-M6 | Full customer journeys, multi-tenant and role negative tests, native/Compose final acceptance | Phase 9, OLA scenarios and existing issue criteria |

| Issue | Proposed additive cross-reference (not a new issue or change to closure criteria unrelated to its domain) |
|---|---|
| [#104](https://github.com/TeraflopsBH/eventor/issues/104) | OAC-01–09, 13–14, 19–20; independent tenant administration and overview, shared PAC identity; preserve Registry and event requirements |
| [#105](https://github.com/TeraflopsBH/eventor/issues/105) | OAC-10–11; owned venue portfolio and authorized geometry, keyboard alternatives |
| [#106](https://github.com/TeraflopsBH/eventor/issues/106) | OAC-13/UX EOC transitions; retain advisory solver, human approval and immutable plan |
| [#107](https://github.com/TeraflopsBH/eventor/issues/107) | OAC-13/20; role-scoped event/station/display navigation, distinct credentials and attendance |
| [#108](https://github.com/TeraflopsBH/eventor/issues/108) | OAC-01/08/19/22; PAC secure bootstrap/recovery and no-manual-SQL normal journey, dual installers |
| [#110](https://github.com/TeraflopsBH/eventor/issues/110) | OAC-11/17; bounded vendor/staff/tasks and external prerequisites |
| [#111](https://github.com/TeraflopsBH/eventor/issues/111) | OAC-05/06/15/16/18; shared brand/TDS/forms/config/reports, no duplicate authoring/delivery |
| [#112](https://github.com/TeraflopsBH/eventor/issues/112) | OAC-12/17; booking/customer/organizer separation, reviewed partner access/disruption, notice vs resolution |

**Codex continuity (mandatory integration note):** preserve current #104/#112 foundation closure and then #105–#107 critical path. Do not switch tasks, reset/rebase unpublished work unnecessarily, redesign identity, start OAC implementation, create duplicate aggregates or change priorities solely because these docs are approved/merged. New work follows scheduled owning issue. Shell evolves incrementally per ADR 0008. PAC successor authority decisions must be reviewed before permission changes. Phase 7 branding/TDS and Phase 8 installers remain scheduled as before. Final acceptance VM only once the coherent application and both supported installers are ready; continue synthetic CI now. No environment publication. Work packages stay in design until explicitly scheduled; no issue proliferation. Preserve PROJECT_STATE/handoff unless actual implementation changes.

## 13. Measurable acceptance and traceability

All proposed criteria are unverified until implementation evidence; detailed reproducible scenarios in OLA. UX criteria additional. Existing blueprint, PAC, TDS and issue acceptance remain applicable; these tests compose rather than replace them.

| ID | Required measurable outcome | Verification / OLA scenario |
|---|---|---|
| OAC-AC-01 | PAC creates one organization and designated initial admin with idempotent retry; staff cannot create arbitrary tenant or self-promote | OLA-01; DB/API/host |
| OAC-AC-02 | Valid invitation establishes exactly one active membership under intended identity; expired/revoked/reused/cross-account token denied | OLA-02; auth/concurrency |
| OAC-AC-03 | Credential-first login selects only active memberships; no business access from membership alone; switch clears context | OLA-02/06; API/browser |
| OAC-AC-04 | Wizard resumable; actual configuration changes update readiness; optional steps not global gate; authorized non-admin sees own work | OLA-03; browser/API |
| OAC-AC-05 | Provider-only setup publishes booking without Registry/events/RSVP/seating; organizer without owned venue can use approved partner projection | OLA-03/07/10; E2E |
| OAC-AC-06 | Overview shows correct authorized counts/time window; denied/stale/unknown not misleading; links obey scope | OLA-04/06; fixtures/browser |
| OAC-AC-07 | Profile update validated/revision checked; no retroactive change to shared names/offer/event history | OLA-03/10; DB/API |
| OAC-AC-08 | Organization brand preview/publish/rollback works without rebuild; distinct tenant appearance; old issued artifact unchanged | OLA-05; TDS/browser |
| OAC-AC-09 | Module activation respects supported/dependency/policy; unsafe disable blocks or drains; historical facts preserved | OLA-03/12; domain tests |
| OAC-AC-10 | Tenant admin invites/assigns named staff without host SQL/owner ticket; existing identity reused, no other memberships disclosed | OLA-06; API/browser |
| OAC-AC-11 | Last active admin protected, host-managed member protected; suspend revokes selected membership sessions only; restore fresh login | OLA-06; ADR 0010/0015 |
| OAC-AC-12 | Role delegation ceiling and field/scope checks stop self-escalation, export and cross-tenant access, including cached retry | OLA-06/11; security |
| OAC-AC-13 | Authorized venue staff create/configure own venue/space/layout and publish revision, no overwrite of partner source | OLA-07/09; #105 tests |
| OAC-AC-14 | Catalogue/availability/maintenance changes preserve confirmed reservation, conflict recheck rejects double-booking | OLA-07; DB/concurrency |
| OAC-AC-15 | Public inquiry → offer → accepted/approved confirmation without account/event; immutable price/tax/policy; approved cancellation effects audited | OLA-07/08; E2E |
| OAC-AC-16 | Create own event/sessions, optional modules, lifecycle and explicit booking association; safe event duplication excludes live credentials | OLA-09/10; E2E |
| OAC-AC-17 | Reuse profile in two events; scoped roster cannot read Registry; import errors/merge correction and history preserved | OLA-09/06; DB/API |
| OAC-AC-18 | Branded bilingual template, synthetic preview/test and explicit authorized real synthetic-recipient issue/send; no live credential in preview | OLA-05/09; TDS/delivery |
| OAC-AC-19 | Public form revision pinned; invalid/abusive request denied; no confirmation/merge/approval from submission alone | OLA-07/09; API/browser |
| OAC-AC-20 | Reviewed partner grant exact scope/digest, current permission/expiry; revocation prevents new use, no guest/price leakage or history rewrite | OLA-10; ADR 0023/0024 |
| OAC-AC-21 | Vendor sees assigned tasks only, evidence/confirmation attributed; CDI limited to external coordination | OLA-09/10; #110 |
| OAC-AC-22 | Scoped report/export manifest, current download auth, retention/hold and safe CSV/PDF; no platform/other tenant data | OLA-11/13; security |
| OAC-AC-23 | Audit actual actor, reason and approved revision; negative API/RLS tests pass; no secrets in logs | OLA-06/11/14; DB/API |
| OAC-AC-24 | Navigation, search, deep links and mobile/keyboard use obey scope/capability; disabled module not a permission bypass | OLA-04/06/14; UX |
| OAC-AC-25 | PAC support under actual actor and expiring scoped grant; no silent impersonation or forbidden intervention; revoke/expiry denies | OLA-11; security/concurrency |
| OAC-AC-26 | Suspend/archive/restore reviewed impact; no deletion/cancellation/mass send; independent memberships preserved | OLA-12; E2E |
| OAC-AC-27 | Authorized portability export complete within declared scope/omissions, verified artifact; lawful hold blocks purge | OLA-13; governance |
| OAC-AC-28 | Clean native and Compose full onboarding and operation + restore reconciliation, actual measurements and issue gates | OLA-14/15; final VM |

## 14. Open decisions and proposed documentation integration

Product-owner approval is needed for this scope, not exact routes, role ceilings, authentication method, retention windows, provisioning policy, business approval thresholds, legal/contact identity, allowed brand overrides, public URL policy or performance targets. Resolve in scheduled M0/owning ADRs and tenant consultation. GHB names, capacities, prices, staffing and legal requirements must be supplied/validated; synthetic examples are not configuration. PAC/TDS addenda remain accepted scope; their proposed engineering details remain proposals until reviewed.

Proposed documentation-only integration after approval: add these three files to v0.3 index; additive cross-references in OPERATING_MODEL, ARCHITECTURE, roles/permissions, ROADMAP, gap analysis, PAC/TDS (handoff/shared ownership only), and existing #104–108/#110–112 issues. Preserve Blueprint v1.2 and accepted ADRs/historical snapshots; possible later versioned v1.3 consolidation separately. No actual source, issue, branch, runtime contract, environment or CI changes made during preparation. All criteria and status are proposed; no feature implementation or execution claimed.

## Approved AGIS organization station administration — 2026-11-27

[AGIS v1.0](ADMISSION_GUEST_INFORMATION_AND_STATION_MANAGEMENT_DESIGN_v1.0.md) elaborates OAC-02/04/05/06/09/10/13/15/19/20/21/22: independent authorized tenant station and device inventory, profile/layout presets and brand resolution, pairing and revocation, operator assignment within delegation ceilings, per-mode readiness, locations, printers and support. Event configuration selects station assignments, allowed actions, published destination projection, verification policy and operational windows; EOC runs/monitors the selected event. Provider-only organizations need no guest station data. A device may serve different modes only after authorized reassignment, clearing old context and revalidating new permissions. No implied guest Registry access, cross-tenant lookup, platform authority or mandatory advanced designer before online gate operation. Reuse OAC capability readiness and existing identity/role controls. Original OAC-AC-01–28 remain required. This is an approved scope clarification, not a runtime implementation claim or instruction to interrupt the existing #104/#112 → #105–107 sequence. Preserve accepted ADRs, historical Blueprint v1.2, existing domain commands and issue criteria; final integrated acceptance remains Phase 9.

## Approved CID organization communication administration — 2026-11-27

[CID v1.0](COMMUNICATION_INVITATION_DISTRIBUTION_AND_MULTI_CHANNEL_DELIVERY_DESIGN_v1.0.md) elaborates OAC-06/08/09/13/14/15/17/18/19/20/21/22: an independently administered Communication and Delivery Center with tenant-owned provider accounts, optional explicitly granted platform services, verified sender identities, write-only secrets, test/readiness, preferences/consent, campaign preparation/review/scheduling, manual distribution tasks, delivery history and cost/usage limits. Provider eligibility, recipient contact authority and domain scope are checked server-side; organization, event and task scopes remain distinct. A booking-only organization needs no guest module or external provider; guests without electronic contact can receive controlled physical or telephone distribution. Separate configuration, authoring, approval, sending, reconciliation and budget permissions. Existing OAC onboarding and capability readiness are reused, not duplicated; no routine platform-owner intervention. This is an approved scope clarification, not a runtime or acceptance claim. Preserve all existing requirements, accepted ADRs, historical Blueprint v1.2, current #104/#112 → #105–107 sequence and established #110/#111/#108 roadmap; no immediate implementation or environment republication. Final integrated acceptance remains Phase 9.
