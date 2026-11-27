# Eventor — Platform Administration Center (PAC)
## Technical specification v1.0

**Status:** Product-owner-approved scope, 2026-11-27. Detailed engineering decisions, successor ADRs, permission migration, API names and host execution design remain proposed pending implementation review.  
**Baseline inspected:** e69d1c9cf86e8c4e55c4ee03f7c291830383bb2c; documentation branch based on 0cc970eff4ecb99d1ee5e43b614962899e1c3261 after TDS PR #232.  
**Tracking:** #104, #108, #111. Repository integration edition of the prepared 2026-11-27 specification: retains PAC-01–18, PAC-M0–M6 and PAC-AC-01–40; condensed editorially, not a byte-for-byte reproduction.  
**Change control:** This addendum changes product documentation only. It neither supersedes accepted ADRs nor authorizes immediate implementation, permission changes, environment republication or a change of current priorities.

## 1. Executive decision and scope

Deliver a distinct deployment-level Platform Administration Center (PAC) for the installation Owner and explicitly delegated Superadmins, independent of organization workspaces and the Event Operations Cockpit. A single-organization deployment uses the same control plane as a multi-organization installation. The Owner has ultimate governance authority: platform identity, organizations, delegated authority, policies, lifecycle, recovery, oversight and paths to controlled corrections. Governance is not unrestricted access to all content, arbitrary shell/SQL, silent impersonation, or permission to bypass business approvals, security/attendance/allocation invariants, immutable history or external parties' duties.

PAC owns global safe metadata, policy, authorized commands, health and administrative requests. Existing tenant services own business records. PAC links into them under the real actor and an explicitly authorized tenant context, not duplicate guest/booking/event CRUD. TDS owns shared authoring, assets, template and brand revisions; PAC governs deployment defaults, identity and communication policy. Host CLI/installer owns privileged maintenance and recovery; the web app can request/monitor supported operations but never gets unrestricted host/database owner privileges. No mandatory SaaS, cloud, Redis, Docker, external IdP, billing/fleet management or separate microservice. No GHB-specific legal/venue facts assumed.

## 2. Reconciliation and verified foundation

| Source | Treatment |
|---|---|
| [Blueprint v1.2](../../blueprint/v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md) §§4,18–21,38 | Platform configuration/provisioning without automatic confidential content; scoped roles, step-up, audit and RLS |
| Blueprint §§23–25,35,41,46 | Maintenance, backups/PITR, health, permission-filtered navigation, separate event cockpit; platform default branding and immutable output snapshots |
| [Roles and permissions](../../product/USER_ROLES_AND_PERMISSIONS_v0.1.md) | Technical administration distinct from confidential/financial/business approvals |
| [ADR 0004](../../decisions/0004-optional-event-operations-scope.md), [0005](../../decisions/0005-separate-invitations-rsvp-attendance.md), [0006](../../decisions/0006-cross-organization-collaboration.md) | Optional capabilities, independent credentials/attendance, explicit collaboration |
| [ADR 0007](../../decisions/0007-internationalization.md), [0008](../../decisions/0008-modular-staff-frontend.md) | BCP 47 bs-BA/en, separate locale/timezone, modular Vue |
| [ADR 0015](../../decisions/0015-email-first-login-and-platform-administration.md) | Preserve email-first login, workspace switch, host-only platform flag; review managed access baseline |
| [ADR 0017](../../decisions/0017-host-staff-account-bootstrap.md), [0020](../../decisions/0020-host-existing-staff-membership.md) | Preserve secure host provisioning and identity reuse; no implicit verification/role |
| [#104](https://github.com/TeraflopsBH/eventor/issues/104) | Extend organization/account/access commands, preserve organizer and Registry obligations |
| [#108](https://github.com/TeraflopsBH/eventor/issues/108) | Secure bootstrap, dual installers, health, upgrade, backup/recovery |
| [#111](https://github.com/TeraflopsBH/eventor/issues/111), [TDS](TEMPLATE_DESIGN_STUDIO_DESIGN_v1.0.md) | Shared brand/asset/template revision services and delivery; all original forms/reports/displays obligations retained |

Inspected migrations 000002, 000172, 000177–179 and [000187](../../../database/migrations/000187_platform_administration_and_workspace_switching.sql). Existing permission catalogue, membership/grants, organization settings, staff access directory, private platform_admin_organizations/access/audit and managed memberships; auth workspace switching, scoped tenant role grants and member suspension. Existing [host scripts](../../../scripts/admin/) grant/revoke platform flag and provision new staff or memberships using privileged migration connection, not HTTP. Staff shell displays platform-admin indicator and simple E mark; no dedicated PAC or full global account console. Systemd templates, development DB and CI logical backup/restore are foundations, not proof of production operations. Audit actual main before work.

### Critical reconciliation

Migration 000187 refreshes managed organization roles with all permission codes WHERE scope_kind <> 'platform'. This grants broad non-platform authority including newly added codes; actual effective restricted access depends on downstream checks. Blueprint §4.2 and role model explicitly exclude automatic confidential guest/operational/commercial access. Treat as a design discrepancy requiring effective-permission audit, not evidence of an exploited leak. Proposed successor ADR: retain host-provisioned authority and selected-tenant RLS, replace blanket managed baseline with reviewed low-risk support allowlist, default-exclude new codes; separate independent ordinary business roles and approved temporary support grants. Sensitivity flag alone insufficient (indirect escalation via role assignment, reports, exports, templates, jobs, credentials, collaboration). No silent flag-to-owner mapping, no current permission change, no edit to accepted ADR. M0/M1 review and migration/recovery evidence required.

## 3. PAC-01 — Governance, roles and delegation

| Role | Authority | Exclusions |
|---|---|---|
| Platform Owner | Installation governance, delegate/revoke admins, branding/policy, lifecycle/recovery approval | No automatic confidential data or root/SQL |
| Superadmin | Explicit platform capabilities and optional organization scope | No self-promotion or owner transfer, no implicit business approval |
| Security administrator | Delegated policy, access review/revocation and incidents | No secrets, own privilege changes or audit edit |
| Operations administrator | Health, jobs, diagnostics, backup/release request and monitoring | No raw backup contents or tenant secrets |
| Platform auditor | Authorized redacted audit/evidence, separate export permission | Read-only |
| Organization administrator | Existing ordinary tenant grants | No control-plane or host authority |
| Host custodian | Out-of-band OS/DB/bootstrap/recovery | Real host principal; not fabricated tenant actor |

One human may hold multiple roles in a small installation; separate capabilities, not mandatory extra staff. Proposed one explicitly designated owner per installation, no shared credential. Host and app owner may differ. Owner transfer/bootstrap/recovery: explicit host-authorized account ID, verified strong enrollment and successor acceptance, atomic authority replacement/revocation/session review, reason and independent protected receipt. Prevent last-owner accidental disable/removal and privilege lockout; offline documented recovery even if web/DB unavailable, no universal backdoor. No first-registration promotion or email/domain inference. Existing flag grant/revoke stays host-only pending approved successor ADR. Initial PAC may expose request/status rather than execute owner/flag change. Independent approval for configured high-risk actions; single-owner sites use documented deliberate local host confirmation for narrowly defined recovery, owner transfer/admin grant, not fake dual control or unrestricted self-approval.

Proposed platform permission families: platform.overview.read, platform.organization.read/manage, platform.account.read/manage, platform.membership.manage, platform.role.review, platform.brand.read/edit/publish, platform.config.read/edit/publish, platform.module.manage, platform.governance.manage, platform.communications.manage, platform.security.manage, platform.audit.read/export, platform.ops.read/request, platform.backup.request, platform.release.request, platform.support.request/approve, platform.emergency.request/approve, platform.owner.govern. Illustrative, reconcile catalogue. No host execution permission. Per-command/resource scope, maximum grant ceiling, default deny, actual actor. Prohibit self-approval/elevation/role widening or creating proxy accounts, editing approval policy for pending requests, role preset/import/restore escalation; validate services/jobs as well as UI. Approval pins target, digest, state, policy and expiry; changes invalidate.

## 4. PAC-02 — Management authentication and sessions

Preserve credential-first login before membership disclosure, rate limits, Argon2id, opaque HttpOnly Secure cookies, CSRF/origin checks, membership switching and actual expiry. PAC is explicit control-plane context, not magic tenant ID; support approved platform-only account without tenant membership. Require MFA for privileged roles (evaluate local WebAuthn/TOTP and hashed one-time recovery codes; no mandatory SMS/IdP/internet). Enrollment, rotation/recovery/revocation audited; strong step-up for high-risk actions, proposed recent-auth 5 minutes, M0 validates. No secrets/factors/codes in logs.

Prefer private TLS management hostname/VPN/intranet with host-only isolated cookie and route allowlist; same-host requires independently scoped session and ingress policy. Public/guest/ordinary tenant tokens never authorize PAC, PAC token alone not tenant commands. Explicit context transitions rotate session/context, clear client cache/streams, preserve real identity and original expiry; switching does not refresh recent-auth. Recheck account/org state, permissions, scope, policy epoch, expiry/revocation every sensitive action and job boundary; revoke affected sessions/streams/jobs and downloads. Lock/order concurrent action vs revocation; report committed actions, never silently undo. Minimized session metadata, no raw cookie.

## 5. PAC-03 / PAC-04 / PAC-05 — Organizations, accounts, access

**PAC-03:** paginated authorized global directory with ID/name/slug, lifecycle, operating profile, locale/timezone, administrators, module readiness, safe counts/storage/activity/issues. No raw guest/commercial details. Organization wizard: unique stable slug, profile (provider/organizer/hybrid), defaults/module capabilities, brand fallback, explicit initial admin (existing identity or invitation), reviewed policy/impact. Atomic org/index/membership bootstrap, async onboarding separate, retry-safe, no partial business records or copied real data. Lifecycle setup/pending → active → suspended → archived, restore subject to validated existing enum and dependencies. Preview impacts on sessions, events/booking/public links/partners/queues and critical check-in. Block or approved drain/read-only policy; revoke appropriate access, pause eligible jobs, preserve history and necessary customer status where allowed, no implied cancellation/delivery/attendance. Incident containment explicit. Archive retains references; deletion via reviewed governance only. Host recovery for inactive org.

**PAC-04:** global staff directory with approved name/email/ID/status, verification/MFA indicators, memberships and platform roles. Field authorization, pagination/rate limit/audit. Distinguish global account vs membership vs event permission. Secure invite preferred; existing case-insensitive identity reused, never upsert credentials. Purpose-bound high entropy hashed one-time expiring revocable tokens, verified mailbox before verified assertion, non-enumerating responses, rate limits. Host bootstrap as ADR 0017; hidden password input, no old password/hash/factor/recovery code disclosure or emailed plaintext; local no-SMTP enrollment. Password reset/recovery and email changes require current strong auth or approved recovery, relevant session/token revocation and notices; collision reviewed, no overwrite. Lock/unlock/deactivate/restore with impact, reason, retained actor references and last-owner safeguard. Global disable vs tenant membership suspend distinguished.

**PAC-05:** reuse memberships/role/grant primitives and ADR 0020. Membership alone confers no data authority. Provision/revoke/restore distinct; existing membership refused by provision. Effective-permissions inspector shows ordinary/managed/temporary source, scope, expiry, issuer, constraints and sensitivity/delegation risk. Reviewed role presets and affected member/permission diff. Protected system role IDs; no authority from display name. Revocation/expiry/suspension reauthorize sessions/jobs/streams and retain independent ordinary grants. Partner collaboration remains explicit. No role inspector leaks forbidden content.

## 6. PAC-06 / PAC-07 — Workspace and oversight

Dedicated permission-filtered PAC entry, real actor/role/scope/elevation banner and expiry, obvious tenant transition/return, accessible keyboard/focus/semantic labels, bs-BA/en, safe deep links, paginated search/filter, loading/empty/error/stale/unauthorized states. Every high-impact action has impact preview, expected revision, reason, specific confirmation and receipt. No browser DB access.

| Area | Controls |
|---|---|
| Overview | Authorized counts, incidents, health, activity, pending requests/maintenance |
| Organizations | Directory/wizard, lifecycle/profile/modules and enter workspace |
| Users & access | Global accounts, enrollment/reset, sessions, memberships, roles, effective permissions |
| Platform identity | Eventor brand, logo, icons, login, About/footer, themes, preview/publish |
| Configuration/modules | Typed defaults, dependencies, overrides, revisions and impact |
| Data governance | Inventory/storage, holds, retention/privacy/import/export jobs |
| Communications | SMTP/provider defaults, test send, reconciliation, notices, TDS |
| System health | API/DB/worker/storage/realtime, versions, safe diagnostics and jobs |
| Backups/recovery | Policies, manifests, verification, restore drills, requests |
| Security | MFA/session policies, anomaly/access review, delegation/elevation |
| Audit/support | Protected receipts, sensitive access audit, support cases/interventions |
| Maintenance/updates | Windows/drain, trusted release, compatibility, preflight and recovery |

Overview cards: organizations by status, active staff/privileged session counts, scheduled/active events, safe booking counts, modules, queue age/uncertain outcomes/dead letters, storage, health, backup/restore status, version/schema compatibility and pending administration. Every metric source/time/window/scope/freshness, unknown not zero/healthy; suppress small sensitive cohorts if needed. Bounded safe read models/aggregates, no unrestricted cross-tenant content query or disable RLS. Authorized drilldown only. No raw guest names, restricted notes/plans, customer emails/offer prices. Business progress separate from health; uptime not fabricated.

## 7. PAC-08 — Platform identity, branding and theming

Owner-controlled revisioned platform-default brand, separate software identity/version/internal IDs/license/security status from editable deployment name. Controls: display name/tagline/description/About, owner/support/help/legal/contact metadata (localized), primary/compact/wordmark/light-dark logo, favicon/PWA icons, bounded safe SVG/raster, alt/dimensions, palette semantic primary/secondary/accent/surface/text/focus/status, approved typography/density/spacing, login welcome/background/language/support, footer copyright/privacy/terms/help and truthful version/attribution, neutral platform templates/sender display name, localized notices with schedule/audience/expiry. Theme preferences light/dark/system/high contrast per user independent of external brand. Preview login/auth errors, mobile/desktop, PAC, tenant shell, guest-safe and TDS output; contrast validation. Draft/review/publish immutable revision and digest; rollback by new revision referencing previously approved values. Safe bundled/last-known-good fallback if bad revision/unavailable storage; management/recovery remains readable. No arbitrary CSS/JS/remote fonts/tracking, hidden MFA/security notices or unlicensed assets. Prelogin public bootstrap exposes only explicitly public nonpersonal brand assets/tokens, no organization discovery or email inference. Cache by revision/digest.

Resolution per property event → authorized venue → organization → platform default. Missing inherits, explicit removal only where allowed; mandatory legal/security notices preserved. Cross-owner brand assets explicitly permitted; no automatic access via booking. Owner may govern overridable properties, not silently rewrite tenant identity. Use shared TDS brand/asset/component/revision service, no competing store; pin resolved brand/template/asset manifest for generated artifacts. Old invitations/offers/PDFs unchanged by rebrand; explicit reissue. ADR 0007 en fallback preserved; default for new org not a changed locale fallback or rewrite. Locale and IANA timezone separate.

## 8. PAC-09 / PAC-10 — Typed settings and module controls

Catalogue stable key, type/schema/allowed range, scope/default/override/sensitivity, permission, live/restart behavior, validation/impact/change risk. Unknown denied; show effective value/source/revision, pending changes and restart requirement, never raw secrets. Draft/validate/preview/review/publish atomically with revision/audit, rollback as new revision. No arbitrary environment writer; infrastructure env/file settings read-only or host request. Suggested session policies, locale/timezone defaults, upload/storage/queue/notification limits, retention, public route availability, onboarding, capability safety floors. Owner evidence for legal/operational meaning; commercial/currency/schedule remains domain data.

Module definition stable ID, installed/supported version, deployment availability, org defaults/activation, event override and effective state/reason/ownership/readiness. DAG dependencies validate cycles/missing dependencies. ADR 0004 booking-only remains independent from guest/seating/check-in; no unsupported modules enabled or direct API/job/subscription bypass. Disable impact active dependencies/artifacts/jobs/links/events, block unsafe changes or approved drain/read-only plan; no deletion, implicit booking cancellation, status/attendance mutation. Preserve pending work visibly; re-enable explicit and validated. No tenant override of safety floor; config cannot install absent code.

## 9. PAC-11 — Governance and privacy

Catalogue data classes/purpose/owner/sensitivity, retention triggers/interval, holds, purge/anonymization method, backup treatment and approval. No invented statutory retention. Platform defaults and safety floor, lawful tenant policy. Aggregate storage inventory not global raw data. Exact scoped privacy/export/correction/deletion requests, verify requester, owner reviews and approves/denies, minimal audit and private delivery; no guaranteed deletion of all backups. Separate account anonymization from guest correction; preserve required historic snapshots/actor refs via reviewed domain redaction/pseudonymization. Holds with reason/review/expiry block purge under lock. Dry run, scope/digest/count limits, approved bulk operation preconditions and idempotent per-item receipts; no mass generic cascade. Authorized diagnostic/export/import reports; no raw rows by default. Private encrypted artifacts as required, short-lived scoped download, reauthorize current permission, expiry/revocation and access audit. Restore must reconcile holds/purges/revoked sessions/access/delivery before traffic. Redact support bundles/logs; synthetic fixtures only.

## 10. PAC-12 — Communications

Extend existing encrypted delivery config/provider abstraction and TDS. Platform sender/SMTP defaults and per-org authorized overrides, revisioned policies, from/reply-to/TLS/routing/limits/capabilities; local capture/no mandatory external provider. Credential write-only replacement/rotation or approved secret reference, masked status only. Safe egress allowlist, no arbitrary URL/SSRF connection test. Synthetic explicit test send approved recipient, TEST/nonlive, never real invitation/QR or broadcast. Monitor queue/lease/sent/provider acceptance/delivered/bounced/suppressed/uncertain distinctions with redacted failure codes. Cancel only eligible unsent jobs; idempotent retry and reconciliation before resend of uncertain outcome. Notices: localized draft, allowed staff/admin audience, preview count/digest, approval, scheduled publish/send and expiry; no implicit broadcast to all guests. Pin TDS revisions; no tenant secret crossover.

## 11. PAC-13 — Health, diagnostics, jobs

Real measured API/DB/schema/worker/render/solver/storage/outbox/realtime/check-in connectivity/portal reachability/TLS/release/backup status. Minimal public liveness, protected detailed readiness/metrics, freshness/source/last successful observation, healthy/degraded/down/unknown/not applicable. Optional worker failure must not disable unrelated booking/manual operations. CPU/memory/disk/queue age/latency/error rates and backup destination capacity through bounded trusted collectors. Incident alerts/acknowledgement distinct from remediation, thresholds/notification dedup/rate limits. Bounded structured sanitized logs with correlation ID and safe support bundle; no arbitrary file paths, credentials, tokens, contacts, sensitive query values. Jobs use owning service allowlisted cancel/retry/reconcile, actual state/lease checks, idempotency, safe progress and current permission; do not blindly resend uncertain provider result. No arbitrary payload editing or clearing errors to claim success.

## 12. PAC-14 / PAC-15 — Backups, host maintenance and releases

**PAC-14:** define backup policy with cadence, target, independent encrypted off-host destination, retention/hold, RPO/RTO proposals and verification. Include consistent PostgreSQL data/schema/role bootstrap and WAL/PITR where supported, private assets, TDS source/output dependencies, files and configuration, exact release/manifest and matching encryption keys protected separately under approved escrow. No raw backup/key downloads to browser. Record scope, size, hashes, consistency, time, target ref, encryption/key references, verification and expiry, partial/late/failed alert. Backup checksum success distinct from actual restore rehearsal. Restore isolated target with outbound email/public ingress disabled; verify references/decryption, release compatibility, integrity and actual recovery timing. Production restore local host confirmation, impact/data-loss preview, maintenance, tested backup and post-restore reconciliation of sessions/revocation/holds/purges/queued deliveries; independent recovery receipt survives DB restore. Do not automatically overwrite current live database or claim zero data loss.

**PAC-15:** host operations fixed typed enum and target, validation, impact/preflight, approval/digest/expiry/replay protection, serialized conflicts and local host confirmation. First release request/status + documented existing CLI/systemd/Compose workflows; optional constrained local executor only after separate threat-model/ADR, independent least privilege, allowlisted operations/args, no generic shell/SQL/file/URL or Docker socket, no browser completion. Runtime never root, owner/migrator creds or unrestricted filesystem. Host CLI works when web/DB down, independent protected audit/progress receipts, idempotent recovery. Secret status/ref/version, rotate via protected mechanism; no expose values. Maintenance schedule/notice, block forbidden writes, drain/pause workers safely, preserve authorized public read-only/status and critical event policy; no automatic reopen on expiry or failed step. Restore/upgrade/backup lock coordination; explicit health/compatibility/smoke and operator reopen.

Release panel actual app/frontend/worker/schema versions, trusted signed/checksum-verified release manifests, notes and compatibility, verified update availability or unknown. Offline verified package path; no arbitrary URL/download or auto-update. Preflight disk/prereqs/config/deps/migration lock/verified backup/key readiness, drain, deploy pinned build native/Compose, checksum-verified serialized forward migrations, smoke/health, explicit reopen and receipt. Failure stops with recovery evidence; rollback application only if schema compatible; else reviewed forward fix or verified restore with explicit loss window. No automatic down migration or zero downtime guarantee. #108 final dual installer and Phase 9 only.

## 13. PAC-16 / PAC-17 — Controlled intervention and emergency access

Three levels: inspect safe global metadata/authorized audit; administer using independent ordinary tenant role or approved scoped support grant with real actor; emergency narrowly time-limited strong step-up and explicit purpose/approval. No invisible impersonation. Case/reference, actor, affected org/resource, purpose/reason, requested permission subset, sensitivity/time window, approver/policy, digest, outcome. Metadata-only default. Appropriate data-owner authority for sensitive access under approved policy; ownership not automatic legal authority. Exact target/action allowlist, no wildcard restricted guest/event access. Visible scope/expiry banner, audit reads/exports/edits, notify affected tenant under policy (justified delay for incident), post-review. Revoke/expiry server-side deny new commands, streams, jobs/downloads and clear cache; renewal fresh review. Proposed emergency max 30 minutes, M0 validates. No self-grant, automatic approval on timeout, scope extension, sensitive mass export, owner transfer, permanent grant, audit edit or key disclosure. Independent approver when required/available; single owner local host confirmation for narrowly documented technical recovery, external receipt and mandatory after-action review, not universal self-approval. Without lawful data authority restrict to containment/recovery. No bypass of integrity/safety/legal holds. Audit failure blocks privileged mutation; offline host procedure separate, import receipt after restore. Do not claim technical prevention against host root.

| Intervention | Owning workflow |
|---|---|
| Guest identity correction | Reviewed merge/restoration, preserve pinned history |
| Confirmed booking/offer correction | Amendment/approved cancellation/disruption, no silent commercial snapshot rewrite/money movement |
| Reopen event | Only supported lifecycle correction with dependencies |
| Published allocation | New validated revision and human approval, no silent solver commit |
| RSVP/admission revocation | Separate correct credential domain, no attendance implication |
| Attendance correction | Audited append-only correction |
| Campaign stop | Eligible unsent cancellation, uncertain reconcile |
| Job recovery | Owning idempotent command |
| Inactive org recovery | Reviewed lifecycle/host recovery, preserve independent memberships |
| External prerequisite | Record authorized coordination only, not external certification |
| Database repair | Protected restore/forward migration, never web SQL |

Unsupported command is visibly unavailable/request-only; do not fabricate implementation.

## 14. PAC-18 — Architecture and audit

Private management ingress → Vue PAC feature → Fastify management auth/policy/typed commands → narrow control-plane DB routines and safe read models; explicit authorized selected-tenant context → existing domain services and RLS; append-only audit/outbox and scoped jobs → existing worker; host operation request/status → protected local CLI/optional constrained executor → independent receipt. Public/tenant ingress never authorizes PAC by default. Share TDS/branding/communication/backup interfaces; no mandatory new microservice. Suggested staff feature platform-administration, shared types and modular server domain. Private global tables remain inaccessible to tenant/runtime/auth/worker direct queries. Reviewed least-privilege role/functions, pinned search path, revoke PUBLIC, bind actual authenticated actor, no arbitrary SQL or BYPASSRLS/owner/migrator in runtime. Safe global metadata/index/aggregate routine only. Transaction-local context/isolated pools, reset and race tests. Outbox after commit; bounded paginated queries and scoped caches, no existence oracle. PAC independent of optional event features, host recovery independent of PAC.

Keep existing platform_admin_audit as host journal actual DB principal; compatible extension or linked control-plane journal records real actor/service/host, selected membership if actual, target/scope/action/result, time, reason/reference, redacted before/after/digest, approval/policy/revision/elevation, correlation/idempotency/session/device minimized. Never fabricate actor from target. Append-only, atomic receipt+mutation rollback on audit failure; sensitive reads fail closed when required audit unavailable. Record privileged grants/revokes, owner changes, denials/elevations, sensitive views/downloads, sessions, config/brand, backup/restore/releases and failed operations; scoped read/export and retention. Protected archival, optional tamper-evident checkpoint/signature, no tamper-proof promise against host. Independent recovery receipts survive restore. Async outcomes not reported successful until trusted result.

## 15. Logical data model (proposed, not DDL)

Inventory actual schema/guards/enums first; UUID conventions, UTC instants and IANA schedule timezone, BCP 47, stable codes, tenant composite FKs/RLS, typed scope not unchecked polymorphic refs. Private global relations accessed narrowly. No duplicate identity, membership, role, job, campaign, asset or brand aggregate.

| Entity/reuse | Required fields/invariants |
|---|---|
| users, organizations, memberships, roles, permissions, grants, sessions | Existing IDs/history/ordinary grants; reviewed management context/status extensions |
| ownership | Installation/owner/status/revision/host receipt; explicit designation and last-owner invariant |
| delegated platform assignments | Account, capability set/ceiling, org scope, issuer/review, expiry; no self-grant |
| platform_admin_organizations/access | Private index/managed lineage, prior state and independent grants preserved |
| MFA factors/recovery | Account, protected verifier/seed and metadata/status; never projected secret |
| onboarding/recovery challenge | Purpose/target/digest/expiry/use/attempt/revoke |
| config definitions/revisions | Typed key/scope/default/value or secret ref, digest/review/state |
| module definition/assignment | Installed support/dependencies/scope/policy/effective/drain/impact |
| shared TDS brand/revision/asset | Explicit ownership, typed localized props, pinned assets/digest |
| support case/elevation | Actual actor, case/scope/resource, allowlist, approval/reason/expiry/revoke |
| intervention request/review | Typed action/target, canonical payload/impact digest, expected revision, receipt |
| governance/hold/privacy request | Class/purpose/owner/scope/retention/review/lifecycle, purge lock |
| admin job extension | Type/scope/actor/case/idempotency/state/lease/attempt/progress/safe error |
| health snapshot/alert | Scope/component/source/time/value/freshness/ack |
| backup policy/manifest | Target ref, release/schema/consistency/key refs/hash/size/verification/retention |
| host operation request/receipt | Fixed enum/target/args digest/review/expiry/replay/runner/status/external evidence |
| release/maintenance | Trusted version/checksum/compatibility/window/drain/phase/recovery/lock |
| host and app audit | Append-only actual actor/target/context/reason/digests/approval/receipt |

Invariants: owner uniqueness/last-owner protection, delegation ceiling, system membership guard, tenant integrity, effective grant expiry, idempotency actor/scope/action/fingerprint, immutable published/history, approval digest/precondition, purge blocked by hold, serialized conflicting maintenance and trusted host completion only. Canonical locks, forward-only migrations and populated upgrade tests.

## 16. Proposed API contract

Conceptual routes; reconcile OpenAPI v0.3/shared types/error conventions when scheduled. No runtime contract changed. Staff management authentication and CSRF/origin, exact permissions/field scopes, bounded pagination/limits; no general public management API.

| Read families | Projection |
|---|---|
| GET /platform/me, /platform/overview | Real actor/capabilities/MFA freshness; safe timed aggregates |
| GET /platform/organizations[/{orgId}] | Authorized directory/profile/effective config/lifecycle |
| GET /platform/accounts[/{id}/memberships or /effective-access], /platform/permissions | Staff directory, provenance/scope/expiry/ceiling |
| GET /platform/brand-profiles/default, /platform/configuration, /platform/modules | Revisions/effective source/readiness/dependencies; masked secrets |
| GET /platform/governance/{policies,holds,requests}, /platform/communications/{configuration,deliveries} | Scoped governance and redacted delivery |
| GET /platform/health, /platform/jobs, /platform/alerts | Bounded diagnostics/freshness |
| GET /platform/backups, /platform/releases, /platform/maintenance | Manifest/status/recovery readiness |
| GET /platform/interventions/{id}, /platform/audit | Scoped case/approval/expiry and redacted audit |

Public brand bootstrap explicitly allowlisted nonpersonal identity only, no tenant/account/management internals. Public liveness minimal. Enrollment/reset purpose-specific routes separate.

| Command family (POST unless indicated) | Effect/preconditions |
|---|---|
| /platform/organizations; /organizations/{id}/lifecycle-requests | Setup preview/unique ID; expected revision/impact/review |
| /account-invitations; /accounts/{id}/recovery-requests, /status-commands, /session-revocations | Purpose-bound challenge; strong auth/last-owner/impact/session effect |
| /membership-commands; /delegation-requests; /owner-transfer-requests | Distinct reviewed provisioning/restore/revoke; ceiling/expiry; host confirmation |
| /workspace-transitions | Real actor, authorized context, session rotation |
| /brand-drafts; PATCH draft; validate/review/publish | Safe tokens/assets/locale, digest/revision; rollback new revision |
| /configuration-change-requests; /module-change-requests | Typed allowlist, dependency/impact/drain/review |
| /governance/{hold,privacy,purge,export}-requests | Owner authority, bounded jobs/hold lock/current download |
| /communications/test-deliveries; /announcements | Synthetic test/verified target; pinned audience review and explicit publish/send |
| /jobs/{id}/action-requests | Owning safe cancel/retry/reconcile |
| /host-operation-requests | Fixed action, validated target/args/preflight/review; pending host execution |
| /support-cases; /intervention-requests | Exact scope, typed command/target, reason, impact, policy |
| /requests/{id}/review-decisions; /requests/{id}/execute; /elevations/{id}/revoke | Current reviewer/approval digest; recheck execution authority; revoke scope/session/streams/jobs |
| /audit-export-requests | Approved fields/scope/retention, private artifact |

All command families under /platform. Actual actor/session/scope derived server-side, not payload. Expected revision/If-Match as existing; canonical fingerprint idempotency key scoped actor/action/resource: identical retry returns receipt after current authorization, changed payload conflicts. Approval binds target/action/digest/relevant versions/policy/expiry; no arbitrary SQL/script/path/role. Result requestId/state/scope/expectedRevision/impactSummary/approvalRequirement/expiry/correlationId/safeErrorCode/receiptId; 202 pending job not success, 401, 403/non-enumerating 404, 409 conflict, existing validation 400/422, 429/503. Redacted errors, no raw secret/hash/personal payload. Host receipt only trusted CLI/executor, never browser. Contracts, authorization matrix and representative fixtures updated together at implementation.

## 17. Threat model and non-negotiable boundaries

| Threat | Control |
|---|---|
| Automatic broad grants, role/secondary-account escalation | Reviewed allowlist, default exclude, grant ceilings and no self-approval including indirect paths |
| Cross-tenant leakage/context bleed | Forced tenant RLS, typed scoped commands, safe aggregate projection, exact scope/session, pool reset/race tests |
| Confused deputy jobs/export/templates | Reauthorize actor/target/current grant on execution and download; no wildcard |
| Credential theft/recovery abuse | MFA/step-up, scoped isolated session/CSRF, hashed one-time challenge, local recovery, no secret disclosure |
| Brand XSS/SSRF/phishing | Safe typed tokens/sanitized uploads, no active/remote arbitrary assets, protected login/MFA |
| Unauthorized host operations or forged receipt | Fixed local allowlist, preflight/approval/expiry/replay, authenticated real host receipt; no arbitrary shell/SQL/path/URL, root or Docker socket |
| Stale approval/race | Digest/state/policy/revision/expiry recheck, transactional lock and idempotency |
| PII or confidential content | Explicit data authority, minimized projection/audit/access logs, encryption/private artifacts, bounded retention |
| Restore resurrects access/delivery/deleted data | Isolated restore and reconciliation before reopening |
| Audit tampering/falsified actor | Append-only protected journal/independent recovery receipt, fail-closed mutation |
| Untrusted release/supply chain | Trusted manifest/checksum/signature policy, pinned deps, preflight and tested recovery |
| Exhaustion/unsafe bulk change | Pagination/quotas/rate limits, job bounds, impact preview, hold/maintenance lock, no starvation |

No public PAC, no generic database editor, no secret viewer, no impersonation, no forced auto-update, no irreversible mass purge or bypass of domain invariants. Owner can resolve problems through supported commands and protected recovery, not unrestricted application god mode.

## 18. Accessibility, localization, observability

Target WCAG 2.2 AA applicable staff web, keyboard-only navigation, scope selection, editing/preview/publish/review and recovery requests; semantic tables, labels, focus, accessible errors/status (not color-only), mobile usability and manual assistive tech checks. bs-BA/en and Bosnian diacritics, stable codes, explicit locale/timezone; UI preference independent of brand. Bounded structured logs/correlation, minimized safe metrics, meaningful status and actual timestamps, no sensitive values in telemetry. Document operational limits and unsupported metrics.

## 19. Non-functional targets and deployment

M0 benchmark proposals, not verified SLOs: representative self-hosted hardware (4 vCPU/8 GiB/SSD as starting test class), realistic synthetic multi-tenant dataset, bounded paginated lists and dashboard refresh, p95 timings measured under concurrent event/check-in, backpressure, maximum job/export/diagnostic sizes and per-scope rate limits. Suggested recent-auth 5 min and emergency 30 min subject to policy and measurement. Set RPO/RTO, retention, queue/backup targets and workload explicitly before release; report actual measured results, not guesses. No mandatory external internet, cloud, Redis, Docker or commercial components. Dual native/Compose same build/security/configuration, non-root services, private endpoints, documented DNS/TLS, maintenance/backup/key recovery and local SMTP capture. External SMTP/HTTPS actual target acceptance only when configured; skipped probes not pass. Host tools independent of app. Final VM test only after coherent release and both installers.

## 20. Compatibility, migration and milestones

Only when scheduled and approved:
1. Inventory actual flags, managed roles/grants/prior memberships, sensitivity and indirect escalation paths, existing auth/tenant/host command coverage. Synthetic populated baseline and recovery drill.
2. Agree successor ADR for governance, explicit ownership (no automatic flag promotion), reviewed allowlist and safe recovery. Add new compatible metadata/session/policy without removing existing behavior prematurely. Bootstrap designated owner through protected host flow; confirm MFA/recovery.
3. Under reviewed serialized forward migration and preflight, reconcile only platform-managed grants to explicit approved baseline, preserve independent memberships/grants/history and IDs, review previous status provenance, revoke/re-evaluate affected sessions/jobs; new codes excluded. Test revocation races, legacy provisioning, no lockout. No direct rewrite of historical ADR or blanket revoke.
4. Enable PAC safely, use existing domain commands; add each vertical slice with schema/API/shared types/UI/auth/audit/regression coverage; no old-code rollback against incompatible schema. Restore/forward-fix plan.
5. Verify exact-head CI/post-merge, fresh and populated DB upgrade, permissions/actor/RLS/concurrency, browser, dependency audit, health and recovery evidence. Release integration only at Phase 9.

| Milestone | Scope / existing track |
|---|---|
| PAC-M0 | Baseline audit, authority/threat model, successor ADR, host recovery and design review |
| PAC-M1 | Protected owner/delegation/MFA/context, managed-grant reconciliation and audit; #104/auth foundation |
| PAC-M2 | PAC shell/overview/org lifecycle/accounts/onboarding/recovery/effective access; reuse #104 |
| PAC-M3 | Platform identity/theme/typed config/modules/notices; #111/TDS, ADR 0004/0007 |
| PAC-M4 | Governance/support/elevation/communications/jobs and controlled intervention; domain commands as available under #112/#105–107/#110 |
| PAC-M5 | Health/diagnostics, backups/recovery, maintenance/releases and host CLI; #108 |
| PAC-M6 | Integration/hardening, full acceptance and dual installer gates; Phase 9 |

**Codex continuity:** approved backlog refinement only. Continue existing #104/#112 foundation closure then #105–#107 critical path as planned. Do not switch tasks, reset/replace branches, rewrite authentication or implement PAC merely because documentation merges. Review any independently discovered security defect through normal priority decisions, not a forced roadmap change. PAC-M0/M1 may be scheduled explicitly alongside identity work; branding shares Phase 7/TDS, operations #108; specialized intervention depends on owning modules. Keep existing issue obligations and use work packages until scheduled, no duplicate child issue proliferation. Do not edit PROJECT_STATE or Codex handoff solely for design. No environment republication or early acceptance VM.

## 21. Acceptance matrix

All criteria proposed release gates, not passed tests. Synthetic fixtures; exact-head CI and post-merge checks plus recorded manual/host evidence where required.

| ID | Acceptance scenario | Verification |
|---|---|---|
| PAC-AC-01 | Explicit host bootstrap designates approved owner; ordinary account/first registration and legacy flag alone cannot become owner; last owner cannot be accidentally disabled | DB/API/host |
| PAC-AC-02 | Owner transfer uses verified successor, host confirmation and audit; old authority/sessions revoked as required; offline recovery on disposable environment | Host/DB/E2E |
| PAC-AC-03 | Existing managed roles reconcile only managed grants to approved allowlist; independent tenant roles and history unchanged; new permission not auto-granted | Populated upgrade/DB |
| PAC-AC-04 | Owner/Superadmin without explicit sensitive grant cannot read guest notes, contacts, prerequisite attachments or confidential commercial fields via API, exports, report templates, jobs or indirect role editing | Two-tenant negative matrix |
| PAC-AC-05 | Tenant admin cannot read control-plane tables or invoke PAC, host flag setter, transfer or global directory; delegated admin cannot self-promote/create proxy privileged user | DB/API/security |
| PAC-AC-06 | MFA enrollment/login/step-up/recovery/revoke; expired or unverified proof rejects high-impact action; secrets not exposed | Auth/browser/security |
| PAC-AC-07 | PAC/tenant/public sessions isolated; switch preserves actual actor and expiry, rotates context, clears previous data; pooled concurrent context never leaks | DB/API/browser/concurrency |
| PAC-AC-08 | Org wizard creates unique configured organization/reviewed admin membership; retry one record, duplicate slug denied, rollback no partial setup | DB/API/browser |
| PAC-AC-09 | Suspend impact includes active events/sessions/jobs/public links; unsafe transition blocked/reviewed, history retained; restore revalidates, no implicit cancellation | Integration/concurrency |
| PAC-AC-10 | Invite existing case-insensitive identity without duplicate; new invitation one-time/purpose-bound, verified only after enrollment, revoked/expired denied | Auth/API/SMTP capture |
| PAC-AC-11 | Reset/identity change no old credentials, target sessions revoked, non-enumerating errors, host bootstrap without SMTP | Auth/host/security |
| PAC-AC-12 | Membership alone no data access; effective access source/scope shown, role grant/revoke/preset impact preserves unrelated memberships | DB/API/browser |
| PAC-AC-13 | Correct authorized overview counts/source/time, stale/unknown distinguished, no small-cohort/restricted leak | API/browser/fixture |
| PAC-AC-14 | Name/logo/favicon/theme/localized login/footer/support draft-preview-publish without rebuild; rollback new revision; invalid brand safe fallback | Browser/DB/i18n |
| PAC-AC-15 | Platform/org/venue/event inheritance correct, tenants isolated, personal dark mode doesn't alter artifacts, prior TDS output pinned | Unit/API/TDS E2E |
| PAC-AC-16 | Unsafe SVG/HTML/CSS/remote asset rejected; public bootstrap only approved identity; auth/MFA notices remain usable | Security/browser |
| PAC-AC-17 | Typed config rejects unknown/invalid; stale revision/preview conflict; effective source/restart/audit, secrets masked | DB/API/browser |
| PAC-AC-18 | Booking-only without guest/seating; missing dependency rejects enable; approved drain for active disable, history retained | Domain integration |
| PAC-AC-19 | Inventory/retention dry run/hold/purge-anonymize honor scope; concurrent hold blocks deletion, snapshots/history safe | DB/concurrency/governance |
| PAC-AC-20 | Import/export/privacy reviewed; private artifact expiry/revocation on authority change; no global raw guest or unapproved download | API/security/worker |
| PAC-AC-21 | SMTP default/override controlled, write-only credentials, safe check; synthetic test no live token, tenant secret isolation | DB/API/SMTP/security |
| PAC-AC-22 | Broadcast pins audience/localized content, distinct preview/approval/send; cancel unsent only, uncertain not blindly resent | Worker/API/browser |
| PAC-AC-23 | Actual API/DB/worker/storage/schema readiness/freshness, optional failure differentiated, safe diagnostics without tokens/contact/key values | Host/API/log review |
| PAC-AC-24 | Owning retry/cancel/reconcile authorized; duplicate requests/concurrent workers no duplicate external effects | Worker/DB/concurrency |
| PAC-AC-25 | Backup manifest verifies encryption, independent target, checksum/consistency/key refs; partial/late/failure visible; success distinct from restore drill | Host/backup drill |
| PAC-AC-26 | Isolated restore DB/assets/keys verifies integrity/release; external delivery/ingress disabled; actual RPO/RTO evidence | Native/Compose restore |
| PAC-AC-27 | Disposable production-style restore host-confirmed, maintenance/loss preview/reconcile sessions/revocation/holds/delivery; independent receipt survives | Recovery rehearsal |
| PAC-AC-28 | Arbitrary shell/SQL/path/URL/args/replay rejected; runtime no root/Docker socket/owner DB creds; no browser forged completion; offline CLI works | Host/security |
| PAC-AC-29 | Maintenance drains workers/prevents writes, notice, permitted status routes and conflicting operation lock; failure not auto-reopen | Host/API/concurrency |
| PAC-AC-30 | Trusted update/preflight/backup/migrations/verification; unverified release denied; failure safe receipt, incompatible rollback prevented | Installer/upgrade |
| PAC-AC-31 | Support exact target/purpose/scope, actual actor visible, no impersonation, read/edit audit | API/browser/audit |
| PAC-AC-32 | Emergency strong step-up, bounded expiry, appropriate approval or documented host recovery; cannot extend own/owner scope; revoke/expiry denies commands/streams/jobs/downloads | Security/concurrency |
| PAC-AC-33 | Correction uses domain command; published plan/offer history unchanged except new approved revision, attendance append-only; unsupported action unavailable | Cross-domain E2E |
| PAC-AC-34 | Mutation rolls back on audit failure, append-only actual actor/target/host principal, redacted diff, separate export authority | DB/API/security |
| PAC-AC-35 | Stale/concurrent approval/revoke/role/org suspend/maintenance serialized or denied, retries cannot widen scope | DB/API concurrency |
| PAC-AC-36 | Keyboard-only create/preview/review/publish/scope/lifecycle/recovery; contrast/focus/status/error and bs-BA/en diacritics | Browser/manual accessibility |
| PAC-AC-37 | Proposed scale/load measured on actual hardware; bounded dashboard/export/jobs don't starve event/check-in; missing measurements reported | Load/operations |
| PAC-AC-38 | Fresh and populated migration, tenant/booking/invitation/RSVP/session/host regressions, OpenAPI/types/build/dependency/security pass | Exact-head + post-merge CI |
| PAC-AC-39 | Native/Compose same configuration/secure identities/recovery/health/backup/upgrade; owner flow clean install both | Phase 9 VM |
| PAC-AC-40 | Original #104/#108/#111 and related acceptance intact; no premature VM or claims from docs | Traceability/release evidence |

Integrated synthetic journey: host owner bootstrap/MFA, publish bilingual platform brand, create organizer A and provider B with different overrides and staff; provider cannot read A guests; delegate limited Superadmin, deny restricted export/self-grant; owner uses ordinary authorized A role, request narrow support/correction and revoke concurrently, verify real actor/history/denied subsequent reads/edits/jobs/downloads. Rebrand old invitation unchanged, booking-only B independent, synthetic SMTP and uncertain reconciliation. Backup manifest, isolated restore external delivery disabled, assets/keys/digests/time evidence; maintenance/release local confirmation and upgrade/recovery; test single-owner lockout offline; repeat native and Compose in final acceptance.

## 22. Open decisions and integration

Owner approval covers product scope, not exact permission allowlist, DDL, endpoints, library/MFA method, governance/dual approval thresholds, lawful data authority, notification policy, management ingress, overridable brand props/public asset policy, module dependency/suspension rules, retention/holds/RPO/RTO, secret escrow, host executor/trusted release policy, supported distributions, workloads or SLOs. M0 validates actual main and resolves these through reviewed ADRs. Preserve historical Blueprint v1.2, ADRs and v0.2 snapshots. This edition coordinates with merged TDS PR #232 and extends design index/architecture/roadmap/gap analysis and existing issue scope without changing active priorities. No runtime implementation or testing claimed by documentation.

References: [Project state](../../PROJECT_STATE.md), [Roadmap](../../ROADMAP.md), [Architecture](../../ARCHITECTURE.md), [Gap analysis](../../BLUEPRINT_TO_REPOSITORY_GAP_ANALYSIS_v1.0.md), [Deployment runbook](../../operations/SELF_HOSTED_DEPLOYMENT_RUNBOOK.md), [OpenAPI](../../api/openapi.v0.3.yaml), [TDS PR #232](https://github.com/TeraflopsBH/eventor/pull/232). All implementation evidence describes the inspected source baseline, not acceptance.

## Approved OAC handoff clarification — 2026-11-27

[OAC v1.0](ORGANIZATION_ADMINISTRATION_CENTER_DESIGN_v1.0.md), [UX v1.0](EVENTOR_USER_EXPERIENCE_AND_NAVIGATION_v1.0.md) and [OLA v1.0](ORGANIZATION_LIFECYCLE_ACCEPTANCE_SCENARIOS_v1.0.md) refine the organization-facing journey. PAC owns deployment provisioning, protected initial administrator designation/enrollment handoff, platform availability and governance, platform support and host recovery. OAC owns the tenant's independent first-login setup, capability readiness, ordinary staff administration and daily operation; do not implement a duplicate account/invitation or configuration system. Tenant authority does not imply platform authority; support uses real actor, explicit grant, expiry and audit. Preserve existing ADRs and the proposed managed-permission successor review; no immediate privilege changes. PAC criteria remain required, and OLA supplies additional integrated evidence, not substitution. Owner approved the three v1.0 scopes for documentation integration on 2026-11-27. The three reviewed source files are preserved verbatim, including their historical proposed-status text; this approval record governs their integration status, not approval of exact engineering decisions or immediate implementation. Existing accepted ADRs, historical Blueprint v1.2/v0.2 snapshots, issue obligations and current #104/#112 → #105–107 priorities remain unchanged. No runtime implementation or acceptance results are implied.
