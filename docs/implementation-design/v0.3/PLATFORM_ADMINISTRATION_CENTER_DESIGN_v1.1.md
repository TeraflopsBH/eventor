# Eventor — Platform Administration Center technical specification v1.1

**Proposed successor review edition, not accepted yet.** 2026-11-27. Owner agreed direction of cumulative compatible requirements and least privilege. Existing v1.0 and approved Blueprint v1.3 remain in force pending review. No runtime, scope, accepted ADR or priority changes. Read with [Blueprint guide](../../blueprint/v1.3/README.md), [consistency reconciliation](../../blueprint/v1.3/DESIGN_CONSISTENCY_RECONCILIATION_v1.0.md), [engineering registers](../../blueprint/v1.3/ENGINEERING_REGISTERS_v1.0.md), [bidirectional source crosswalk](../../blueprint/v1.3/TDS_PAC_SOURCE_RECONCILIATION_v1.0.md).

## Part I — Reconciled requirements and implementation authority

The original detailed specification in Part II and integrated version plus subsequent approved clarifications in Part III constitute a source-complete proposed cumulative contract. All compatible approved requirements and detailed acceptance conditions remain mandatory; proposed choices, limits, routes, codes and examples retain their original qualifications. Apply the explicit dispositions below, accepted ADRs, DC-01–11 and current runtime compatibility. Historical status and integration instructions are provenance, not current orders. No silently dropped clause. Section-level reconciliation is not proof of every differing sentence; before declaring final semantic closure, adjudicate each remaining nonidentical clause against the existing line crosswalk, record equivalence/cumulative detail/explicit supersession or owner decision. Stop affected conflict, not unrelated work.

| Requirement | Original/integrated section | Consolidated disposition |
|---|---|---|
| 01–02 | 3–4 / 3–4 | Separate host, platform, delegated, ordinary tenant and scoped support/emergency; preserve current ADR 0015 until successor implemented. MFA/step-up, separate session context and actual actor. |
| 03–05 | 5 / 5 | Full directory, atomic provisioning, enrollment separate, lifecycle impact, identity and membership separation, no upsert, no legacy flag-to-owner inference. Exact permission provenance. |
| 06–08 | 6–7 / 6–7 | Retain navigation, safe scoped metrics/freshness, typed branding controls and immutable resolved output; TDS owns shared brand service. |
| 09–10 | 8 / 8 | Typed config, version/review/restart, module DAG/impact/drain; no host edit or history deletion. |
| 11–12 | 9–10 / 9–10 | Retention/holds/export locks, no invented law; explicit shared provider grants and independent tenant config; CID owns delivery. |
| 13–15 | 11–12 / 11–12 | Actual bounded health/diagnostics/job actions, backup/restore manifest and independent receipt; host typed request only; optional executor separate ADR. |
| 16–18 | 13–14 / 13–14 | Exact approved support, limited single-owner recovery, actual actor, expiry/revoke; protected control plane, narrow functions, RLS, no duplicate business engine. |
| Data/API | 15–16 / 15–16 | Detailed original entity, routes, review and error semantics preserved, grouped integrated families same intent; exact implementation choices pending M0. |
| Security/UX | 17–18 / 17–18 | Both threat models and accessibility/locale/observability conditions cumulative. |
| Quality | 19 / 19 | Retain complete original provisional envelope, not achieved or binding SLO. |
| Milestones/AC | 20–22 / 20–22 | Both exact acceptance texts, existing M0/M1 and Phase 9; preserve later OAC/AGIS/CID/AES/EPW/FRS/HPG/RAI additions. |

### Explicit resolutions
- Proposed [ADR 0025](../../decisions/0025-platform-governance-tenant-authority.md) resolves future direction only, no runtime change or claim of leak. Exact allowlist, owner designation, migration/recovery and affected permission inventory are separate mandatory M0/M1 review. Preserve ordinary independent grants; new sensitive permissions never assumed automatically authorized.
- One human may have separate host/platform/tenant roles. Local host confirmation for narrowly defined single-owner recovery is not blanket sensitive self-approval; if data authority unavailable recover without content. Never fake second reviewer, promote legacy flag or use generic reset/SQL/shell.
- PAC-only context and privileged MFA required future scope. Current auth is not represented as already implementing them. No root/Docker socket/owner database credentials through API; optional constrained host executor needs separate approved ADR and threat model.
- Shared provider requires explicit tenant service grant, not correspondence access; restore reconciles revoked authority and uncertain effects, DC-05/07. Tenant activation optional, full product evidence required, no mock/skip credit.
- Original §19 provisional envelope: Linux 4 vCPU/8 GiB/SSD; directory first 50 rows p95 ≤1s at 100 orgs/10,000 identities, overview p95 ≤2s bounded; health refresh 30s/stale 90s; recent-auth 5 min, support 60 min default, emergency 30 min max candidates; daily verified backup, candidate RPO 24h/RTO 4h subject to deployment review. Atomic audit, serialized maintenance, bounded jobs. No measured claim; M0 confirms/adjusts with evidence.

### Paired acceptance obligations

Both full original and integrated criterion conditions must be satisfied; no shorter paraphrase removes evidence. All 40 IDs paired; no test credited by this document. Original crosswalk retains line references. Source alias TDS-AC-n refers to original AC-n.

### PAC-AC-01

Original: PAC-AC-01  /  Explicit host bootstrap designates approved owner; ordinary account/first registration and legacy flag alone cannot become owner; last owner cannot be accidentally disabled  /  DB/API/host

Integrated: PAC-AC-01  /  Explicit host bootstrap designates approved owner; ordinary account/first registration and legacy flag alone cannot become owner; last owner cannot be accidentally disabled  /  DB/API/host

### PAC-AC-02

Original: PAC-AC-02  /  Owner transfer uses verified successor, host confirmation and audit; old owner authority and sessions revoked as required; offline recovery succeeds on disposable environment  /  Host/DB/E2E

Integrated: PAC-AC-02  /  Owner transfer uses verified successor, host confirmation and audit; old authority/sessions revoked as required; offline recovery on disposable environment  /  Host/DB/E2E

### PAC-AC-03

Original: PAC-AC-03  /  Existing platform-managed roles reconcile only managed grants to approved allowlist; independent tenant roles and historical references unchanged; new permission code not automatically granted  /  Populated upgrade/DB

Integrated: PAC-AC-03  /  Existing managed roles reconcile only managed grants to approved allowlist; independent tenant roles and history unchanged; new permission not auto-granted  /  Populated upgrade/DB

### PAC-AC-04

Original: PAC-AC-04  /  Platform owner/Superadmin without explicit sensitive grant cannot read guest notes, contacts, prerequisite attachments or confidential commercial fields via API, exports, report templates, jobs or indirect role editing  /  Two-tenant negative matrix

Integrated: PAC-AC-04  /  Owner/Superadmin without explicit sensitive grant cannot read guest notes, contacts, prerequisite attachments or confidential commercial fields via API, exports, report templates, jobs or indirect role editing  /  Two-tenant negative matrix

### PAC-AC-05

Original: PAC-AC-05  /  Ordinary tenant admin cannot read control-plane tables or invoke PAC, host flag setter, owner transfer or global directory; delegated admin cannot self-promote/create proxy privileged user  /  DB role/API/security

Integrated: PAC-AC-05  /  Tenant admin cannot read control-plane tables or invoke PAC, host flag setter, transfer or global directory; delegated admin cannot self-promote/create proxy privileged user  /  DB/API/security

### PAC-AC-06

Original: PAC-AC-06  /  MFA enrollment, login, step-up, recovery and revoke tested; expired or unverified step-up rejects high-impact command; secrets not exposed  /  Auth/browser/security

Integrated: PAC-AC-06  /  MFA enrollment/login/step-up/recovery/revoke; expired or unverified proof rejects high-impact action; secrets not exposed  /  Auth/browser/security

### PAC-AC-07

Original: PAC-AC-07  /  PAC/tenant/public sessions isolated; workspace switch retains real actor, rotates context, clears previous data, preserves expiry; pooled concurrent context never leaks  /  DB/API/browser/concurrency

Integrated: PAC-AC-07  /  PAC/tenant/public sessions isolated; switch preserves actual actor and expiry, rotates context, clears previous data; pooled concurrent context never leaks  /  DB/API/browser/concurrency

### PAC-AC-08

Original: PAC-AC-08  /  Organization wizard creates unique configured organization and reviewed admin membership; retry produces one record, duplicate slug rejected, failed transaction leaves no partial bootstrap  /  DB/API/browser

Integrated: PAC-AC-08  /  Org wizard creates unique configured organization/reviewed admin membership; retry one record, duplicate slug denied, rollback no partial setup  /  DB/API/browser

### PAC-AC-09

Original: PAC-AC-09  /  Suspend impact identifies active events, sessions, jobs and public links; unsafe transition blocked or reviewed; history retained; restore revalidates state; no implicit booking/event cancellation  /  Integration/concurrency

Integrated: PAC-AC-09  /  Suspend impact includes active events/sessions/jobs/public links; unsafe transition blocked/reviewed, history retained; restore revalidates, no implicit cancellation  /  Integration/concurrency

### PAC-AC-10

Original: PAC-AC-10  /  Invite existing case-insensitive identity without duplicate account; new invitation is one-time/purpose-bound and verified only after enrollment; revoked/expired token denied  /  Auth/API/SMTP capture

Integrated: PAC-AC-10  /  Invite existing case-insensitive identity without duplicate; new invitation one-time/purpose-bound, verified only after enrollment, revoked/expired denied  /  Auth/API/SMTP capture

### PAC-AC-11

Original: PAC-AC-11  /  Password reset/identity change does not disclose old credentials; targeted sessions revoked; non-enumerating errors; host bootstrap still works without SMTP  /  Auth/host/security

Integrated: PAC-AC-11  /  Reset/identity change no old credentials, target sessions revoked, non-enumerating errors, host bootstrap without SMTP  /  Auth/host/security

### PAC-AC-12

Original: PAC-AC-12  /  Membership alone grants no data access; directory/effective permissions show source and scope; grant/revoke and role-preset impact preserve unrelated memberships  /  DB/API/browser

Integrated: PAC-AC-12  /  Membership alone no data access; effective access source/scope shown, role grant/revoke/preset impact preserves unrelated memberships  /  DB/API/browser

### PAC-AC-13

Original: PAC-AC-13  /  Owner/delegated admin sees correct authorized overview counts with source and timestamp; unavailable/stale metric marked unknown, no small-cohort or restricted detail leakage  /  API/browser/fixture

Integrated: PAC-AC-13  /  Correct authorized overview counts/source/time, stale/unknown distinguished, no small-cohort/restricted leak  /  API/browser/fixture

### PAC-AC-14

Original: PAC-AC-14  /  Platform branding changes name/logo/favicon, approved theme, localized login/footer/support through draft/preview/publish without rebuild; rollback creates revision; invalid brand falls back safely  /  Browser/DB/i18n

Integrated: PAC-AC-14  /  Name/logo/favicon/theme/localized login/footer/support draft-preview-publish without rebuild; rollback new revision; invalid brand safe fallback  /  Browser/DB/i18n

### PAC-AC-15

Original: PAC-AC-15  /  Platform→organization→venue→event property inheritance correct; two tenants isolated; personal dark mode does not alter published artifacts; old TDS outputs retain exact pinned brand  /  Unit/API/TDS E2E

Integrated: PAC-AC-15  /  Platform/org/venue/event inheritance correct, tenants isolated, personal dark mode doesn't alter artifacts, prior TDS output pinned  /  Unit/API/TDS E2E

### PAC-AC-16

Original: PAC-AC-16  /  Unsafe SVG/HTML/CSS/remote assets rejected; public bootstrap exposes only approved public identity; login/MFA/security notices remain visible and usable  /  Security/browser

Integrated: PAC-AC-16  /  Unsafe SVG/HTML/CSS/remote asset rejected; public bootstrap only approved identity; auth/MFA notices remain usable  /  Security/browser

### PAC-AC-17

Original: PAC-AC-17  /  Typed config rejects unknown keys/invalid values; stale preview/revision conflicts; published settings show effective source, restart required and audit; secrets masked  /  DB/API/browser

Integrated: PAC-AC-17  /  Typed config rejects unknown/invalid; stale revision/preview conflict; effective source/restart/audit, secrets masked  /  DB/API/browser

### PAC-AC-18

Original: PAC-AC-18  /  Booking-only organization runs without guest/seating modules; enable missing dependency rejected; disabling active dependent module requires approved drain; historic records retained  /  Domain integration

Integrated: PAC-AC-18  /  Booking-only without guest/seating; missing dependency rejects enable; approved drain for active disable, history retained  /  Domain integration

### PAC-AC-19

Original: PAC-AC-19  /  Data inventory, retention dry run, legal hold and approved purge/anonymization honor scope; concurrent hold blocks deletion; retained snapshots/history safe  /  DB/concurrency/governance

Integrated: PAC-AC-19  /  Inventory/retention dry run/hold/purge-anonymize honor scope; concurrent hold blocks deletion, snapshots/history safe  /  DB/concurrency/governance

### PAC-AC-20

Original: PAC-AC-20  /  Import/export/privacy requests reviewed; artifacts private and expires/revokes on authority change; no global raw guest list or unapproved data download  /  API/security/worker

Integrated: PAC-AC-20  /  Import/export/privacy reviewed; private artifact expiry/revocation on authority change; no global raw guest or unapproved download  /  API/security/worker

### PAC-AC-21

Original: PAC-AC-21  /  Platform SMTP default/tenant override controlled, credentials write-only, safe connectivity check; synthetic marked test send has no live invitation/QR; unauthorized tenant cannot read secrets  /  DB/API/SMTP/security

Integrated: PAC-AC-21  /  SMTP default/override controlled, write-only credentials, safe check; synthetic test no live token, tenant secret isolation  /  DB/API/SMTP/security

### PAC-AC-22

Original: PAC-AC-22  /  Broadcast/announcement pins audience and localized content, separate preview/approve/send; cancel only eligible unsent jobs; uncertain provider result not blindly resent  /  Worker/API/browser

Integrated: PAC-AC-22  /  Broadcast pins audience/localized content, distinct preview/approval/send; cancel unsent only, uncertain not blindly resent  /  Worker/API/browser

### PAC-AC-23

Original: PAC-AC-23  /  Health shows actual API/DB/worker/storage/schema readiness and stale state; optional module failure differentiated; safe bounded logs/support bundle contain no tokens/contact/key values  /  Host/API/log review

Integrated: PAC-AC-23  /  Actual API/DB/worker/storage/schema readiness/freshness, optional failure differentiated, safe diagnostics without tokens/contact/key values  /  Host/API/log review

### PAC-AC-24

Original: PAC-AC-24  /  Safe job retry/cancel/reconcile enforces owning state/permission; duplicate requests and concurrent workers do not duplicate external effects  /  Worker/DB/concurrency

Integrated: PAC-AC-24  /  Owning retry/cancel/reconcile authorized; duplicate requests/concurrent workers no duplicate external effects  /  Worker/DB/concurrency

### PAC-AC-25

Original: PAC-AC-25  /  Backup manifest verifies encryption, independent destination, checksum, consistency and key references; failed/late/partial backup visibly flagged; success not conflated with restore drill  /  Host/backup drill

Integrated: PAC-AC-25  /  Backup manifest verifies encryption, independent target, checksum/consistency/key refs; partial/late/failure visible; success distinct from restore drill  /  Host/backup drill

### PAC-AC-26

Original: PAC-AC-26  /  Isolated restore of database/assets/keys verifies integrity and matching release; external delivery/public ingress disabled; record actual RPO/RTO and test evidence  /  Native/Compose restore

Integrated: PAC-AC-26  /  Isolated restore DB/assets/keys verifies integrity/release; external delivery/ingress disabled; actual RPO/RTO evidence  /  Native/Compose restore

### PAC-AC-27

Original: PAC-AC-27  /  Production-style restore on disposable target requires host confirmation, maintenance, data-loss preview, reconciliation of old sessions/revoked access/holds/delivery; independent recovery receipt survives restore  /  Recovery rehearsal

Integrated: PAC-AC-27  /  Disposable production-style restore host-confirmed, maintenance/loss preview/reconcile sessions/revocation/holds/delivery; independent receipt survives  /  Recovery rehearsal

### PAC-AC-28

Original: PAC-AC-28  /  Untrusted host action (arbitrary shell/SQL/path/URL/arguments/replay) rejected; runtime has no root/Docker socket/owner DB creds; browser cannot forge completion; host CLI works with application down  /  Host/security

Integrated: PAC-AC-28  /  Arbitrary shell/SQL/path/URL/args/replay rejected; runtime no root/Docker socket/owner DB creds; no browser forged completion; offline CLI works  /  Host/security

### PAC-AC-29

Original: PAC-AC-29  /  Maintenance drains workers, prevents forbidden writes, displays notice, retains authorized status paths and blocks conflicting operations; failure does not silently reopen service  /  Host/API/concurrency

Integrated: PAC-AC-29  /  Maintenance drains workers/prevents writes, notice, permitted status routes and conflicting operation lock; failure not auto-reopen  /  Host/API/concurrency

### PAC-AC-30

Original: PAC-AC-30  /  Trusted update artifact/preflight/backup/migrations/verification; unverified release rejected; failed upgrade stops with recovery receipt; incompatible code rollback prevented  /  Installer/upgrade

Integrated: PAC-AC-30  /  Trusted update/preflight/backup/migrations/verification; unverified release denied; failure safe receipt, incompatible rollback prevented  /  Installer/upgrade

### PAC-AC-31

Original: PAC-AC-31  /  Support request uses exact target, approved purpose and scoped permissions, visible real actor; no silent impersonation; audit includes reads/edits  /  API/browser/audit

Integrated: PAC-AC-31  /  Support exact target/purpose/scope, actual actor visible, no impersonation, read/edit audit  /  API/browser/audit

### PAC-AC-32

Original: PAC-AC-32  /  Emergency access strong step-up, bounded expiry, appropriate approval or documented local host recovery; cannot extend own scope/owner privilege; expiration/revoke blocks new commands, streams, jobs and downloads  /  Security/concurrency

Integrated: PAC-AC-32  /  Emergency strong step-up, bounded expiry, appropriate approval or documented host recovery; cannot extend own/owner scope; revoke/expiry denies commands/streams/jobs/downloads  /  Security/concurrency

### PAC-AC-33

Original: PAC-AC-33  /  Controlled correction uses domain command, not direct state mutation; published plan/offer unchanged except new approved revision, attendance correction append-only; unsupported domain action unavailable  /  Cross-domain E2E

Integrated: PAC-AC-33  /  Correction uses domain command; published plan/offer history unchanged except new approved revision, attendance append-only; unsupported action unavailable  /  Cross-domain E2E

### PAC-AC-34

Original: PAC-AC-34  /  Privileged mutation rolls back on audit failure; journal append-only, correct actual actor/target/host principal and redacted before/after; audit export independently authorized  /  DB/API/security

Integrated: PAC-AC-34  /  Mutation rolls back on audit failure, append-only actual actor/target/host principal, redacted diff, separate export authority  /  DB/API/security

### PAC-AC-35

Original: PAC-AC-35  /  Concurrent stale approval/revocation, role changes, org suspension and maintenance actions are serialized/rejected correctly; idempotent retry cannot broaden scope  /  DB/API concurrency

Integrated: PAC-AC-35  /  Stale/concurrent approval/revoke/role/org suspend/maintenance serialized or denied, retries cannot widen scope  /  DB/API concurrency

### PAC-AC-36

Original: PAC-AC-36  /  Keyboard-only creation, preview, review/publish, scope selection, lifecycle and recovery request; contrast, focus, status/confirmation and accessible errors; bs-BA/en and diacritics  /  Browser/manual accessibility

Integrated: PAC-AC-36  /  Keyboard-only create/preview/review/publish/scope/lifecycle/recovery; contrast/focus/status/error and bs-BA/en diacritics  /  Browser/manual accessibility

### PAC-AC-37

Original: PAC-AC-37  /  Provisional scale/load targets measured with actual hardware/fixture; bounded dashboard, filters, export and background jobs do not starve event/check-in; unsupported measurements reported  /  Load/operations

Integrated: PAC-AC-37  /  Proposed scale/load measured on actual hardware; bounded dashboard/export/jobs don't starve event/check-in; missing measurements reported  /  Load/operations

### PAC-AC-38

Original: PAC-AC-38  /  Fresh and populated migrations, existing tenant/booking/invitation/RSVP/session/host provisioning regressions, OpenAPI/shared types, frontend build and dependency/security checks pass  /  Exact-head + post-merge CI

Integrated: PAC-AC-38  /  Fresh and populated migration, tenant/booking/invitation/RSVP/session/host regressions, OpenAPI/types/build/dependency/security pass  /  Exact-head + post-merge CI

### PAC-AC-39

Original: PAC-AC-39  /  Native and Compose share same configuration, secure service identities, recovery/health/backup/upgrade functions; full owner workflow usable after clean install in both  /  Phase 9 acceptance VM

Integrated: PAC-AC-39  /  Native/Compose same configuration/secure identities/recovery/health/backup/upgrade; owner flow clean install both  /  Phase 9 VM

### PAC-AC-40

Original: PAC-AC-40  /  Original #104/#108/#111 and related domain acceptance remains intact; no premature VM reliance, no Studio/PAC feature assumed implemented from documentation  /  Traceability/release evidence

Integrated: PAC-AC-40  /  Original #104/#108/#111 and related acceptance intact; no premature VM or claims from docs  /  Traceability/release evidence

# Part II — Full detailed original specification

Original PAC review source, 98828 bytes, SHA-256 016bc76d55b6cb072f6511682f5f5007b0c01b8b889fc70a4aff6343876148e1. Exact source begins after marker newline; original relative paths/status retained as historical source context. Use pinned manifest for navigation.

<!-- BEGIN EXACT ORIGINAL PAC bytes=98828 sha256=016bc76d55b6cb072f6511682f5f5007b0c01b8b889fc70a4aff6343876148e1 -->
# Eventor — Platform Administration Center
## Technical specification v1.0

**Status:** Proposed for product-owner review; not an approved ADR or implementation assignment  
**Date:** 27 November 2026  
**Repository:** TeraflopsBH/eventor  
**Inspected main:** `e69d1c9cf86e8c4e55c4ee03f7c291830383bb2c`  
**Proposed repository path:** `docs/implementation-design/v0.3/PLATFORM_ADMINISTRATION_CENTER_DESIGN_v1.0.md`  
**Related work:** #104 (identity/access and organizer foundation), #108 (installation and operations), #111 (branding/communications); #232 (Template Design Studio documentation PR, open at inspection).  
**Change control:** This is a standalone proposal. No repository, issue, environment, dependency, schema, API or implementation priority has been changed.

---

## 1. Executive decision and product boundary

Eventor needs a deployment-level Platform Administration Center (PAC) distinct from the organization workspace and the live Event Operations Cockpit. PAC is the primary control plane for the human owner of an Eventor installation and explicitly delegated Superadmins. It exposes deployment-wide operational health, organizations, identities, security, system configuration, branding, governance and supported administrative interventions through a coherent UI. A single-organization installation has the same control plane as a multi-organization installation.

The Platform Owner has ultimate *governance* authority over the installation, including its product identity, delegated administrative authorities, policy, lifecycle and recovery. The owner can oversee all domains, enter an authorized organization context, correct records through their domain services, and obtain appropriately controlled emergency access where justified. Ownership does not mean every private record appears in a global search, or that immutable records, safety constraints, business approvals, audit trails or external parties' duties can be bypassed. Legal authority over information and authority to operate a host are different from application permissions.

PAC must be a functional administrative workspace, not only a status report or a shortcut to SQL. Its architecture must preserve the existing Vue 3 / TypeScript / Fastify / PostgreSQL modular monolith, tenant RLS, explicit grants, actor attribution and optional capabilities. Host recovery must continue to work when the application is unavailable. No mandatory cloud service, separate microservice cluster, Docker, external control plane, or paid component is introduced.

### Deliverable boundaries

- **PAC:** platform-level oversight, identity, policies, branding, scoped access, validated administrative commands, jobs, readiness and supported operations.
- **Organization workspace:** business ownership, event/booking/guest workflows, local role assignments, forms, inventories and organization/venue/event brand overrides. PAC links into these existing modules rather than implementing duplicate CRUD.
- **Event Operations Cockpit:** live event-specific activity, maps, allocations, attendance and interventions. PAC offers health and scoped drill-down, not a competing cockpit.
- **Template Design Studio (TDS):** shared authoring, assets, templates, versioned outputs and localization. PAC governs deployment defaults, branding policy and platform communication purposes; it does not build another editor or mail worker.
- **Host maintenance tooling:** installer, service lifecycle, secrets, database migrations, restore and release recovery. PAC may request and monitor approved operations through a narrow local boundary, never execute arbitrary commands or receive database-owner/root credentials.

Non-goals: general SQL browser/editor, invisible impersonation, public administrator API, bypass of payment/approval/attendance invariants, unrestricted shell/file manager, editing historical audit receipts, reading existing passwords or encryption keys, implementing police/CDI inspection, forced auto-updates, SaaS billing/licensing, cross-deployment fleet management. Future federation or SSO integrations require their own decision. No assumption of GHB-specific legal terms, real venue facts, identity provider, SMTP service or internet access.

## 2. Source reconciliation and verified baseline

### 2.1 Design traceability

| Existing source | Current requirement / decision | PAC treatment |
|---|---|---|
| Blueprint v1.2 §§4.1–4.2 | Platform administration covers configuration, organization management, provisioning, backup; no automatic access to restricted notes/documents; sensitive step-up and dual control | PAC-01–05, PAC-16–17; separate governance and content access |
| Blueprint §§18–21, 38 | Modular monolith; scoped APIs; separate credentials; RLS, audit, security and privacy | PAC-02, 12, 15–18; no privileged runtime pool |
| Blueprint §§23–24 | Intranet/internet modes, backup/PITR, restore testing, readiness, logs, monitoring and maintenance mode | PAC-13–15, 19; local host recovery boundary |
| Blueprint §§25, 35 | Permission-filtered UI; event administrator Cockpit | PAC-06–07; distinct PAC navigation and context |
| Blueprint §41 and §46 | Platform default → organization → venue → event branding; immutable resolved snapshots | PAC-08; add owner-controlled platform layer, keep tenant branding and historic outputs |
| User Roles and Permissions v0.1 | Platform operator/administrator, tenant lifecycle/support; no automatic guest, confidential or commercial access | PAC-01–05 and 17; preserve business approval policies |
| ADR 0004, 0005, 0006 | Optional modules; invitation/RSVP/admission distinct; separate organization ownership and explicit collaboration | PAC-04, 10, 16; no implicit cross-party sharing or attendance mutation |
| ADR 0007, 0008 | Explicit locales and modular staff UI | PAC-06, 08–09; BCP 47, bs-BA/en and existing locale precedence |
| ADR 0015 | Email-first login, membership switching, host-only platform flag, managed memberships and access audit | PAC-01–05; preserve host-only grant, review overly broad managed grants |
| ADR 0017 | Host bootstrap for initial staff account; no password on command line, no automatic roles/verification | PAC-03, 05, 15; keep host fallback, add safe invitation lifecycle |
| ADR 0020 | Host provisioning of existing active account's membership, no duplicate identity or implicit roles | PAC-03–05; reuse global identity and membership semantics |
| #104 | Organizer foundation, broader organization/user/member/access administration per PROJECT_STATE | PAC-03–05 and tenant drill-down extend existing commands; keep current work intact |
| #108 | Native/Compose installation, bootstrap, secure configuration, upgrades, backup/restore and health | PAC-13–15, 19; operations contracts shared across installers |
| #111 / TDS #232 | Authoring, branding, delivery, reports, forms, displays; TDS shared assets/templates | PAC-08, 12; shared revisions and delivery services; original #111 scope preserved |

### 2.2 What exists as of the inspected main

- `database/migrations/000002_authorization.sql`: permission catalogue with scope and sensitivity, roles and role-permission relations.
- `000172_organization_access_directory.sql`, `000177_organization_membership_access.sql`, `000178_organization_profile_settings.sql`, `000179_organization_member_search.sql`: tenant member directory, access administration, organization profile and member search.
- `000187_platform_administration_and_workspace_switching.sql`: `users.is_platform_admin` default false; private `platform_admin_organizations`, `platform_admin_access`, `platform_admin_audit`; host-admin refresh, membership guard, flag change and switch audit routines. Managed memberships cover active organizations; normal selected-tenant authorization and RLS remain in use. Revocation removes managed grants and revokes affected sessions, with prior membership restoration logic.
- `scripts/admin/platform-admin.sh`: host-owner grant/revoke using privileged migration connection and `SET LOCAL ROLE eventor_owner`; not an HTTP operation. `bootstrap-staff-account.sh` and `provision-staff-membership.sh` implement ADRs 0017/0020.
- `apps/api/src/staff-workspaces.ts`, `apps/staff-web/src/features/application-shell/StaffApplicationShell.vue`: workspace controls and platform-admin indicator, not a dedicated PAC. Current staff shell displays a simple E brand mark.
- `OrganizationAccessView.vue` and `OrganizationProfileView.vue`: scoped member/grant administration and profile settings. Host-managed accounts are labelled; tenant suspension controls are omitted. Server guards remain authoritative.
- `000013_event_changes_notifications.sql` and subsequent delivery migrations: notification templates/revisions, existing event campaign and delivery infrastructure; worker and email configuration UI. TDS design is tracked separately; do not count the open documentation PR as code or a merged ADR.
- `deploy/systemd/`, `scripts/db/bootstrap-roles.sql`, `scripts/db/migrate.sh`, logical backup/restore CI and `docs/operations/SELF_HOSTED_DEPLOYMENT_RUNBOOK.md`: operations foundations, not a tested production management console or full dual-mode installer.

The current PROJECT_STATE explicitly leaves broader tenant onboarding and a complete global account console open. No full PAC, global branding editor, global account directory, controlled intervention framework or complete operational control interface was established by the inspected source. This is static inspection, not a full endpoint/security audit or application exercise. Current progress percentages are intentionally not assigned here.

### 2.3 Critical reconciliation: ADR 0015 and restricted-data access

The implementation of `refresh_platform_admin_access` in migration 000187 inserts every permission code whose `scope_kind <> 'platform'` into the managed organization role. It repeats that operation during refresh; new non-platform permissions can therefore be automatically added. This is wider than the original blueprint's technical-admin privacy boundary. The presence of a permission in this managed role does not by itself prove that every corresponding sensitive endpoint can be used: its effective scope, individual command checks, field-level projections and RLS also matter. A full effective-access inventory and adversarial tests are required; do not label this an established data leak.

**Proposed successor decision:** preserve explicit host-provisioned platform authority and workspace selection, but replace automatic blanket non-platform grants with a reviewed allowlist of low-risk support capabilities. Technical authority alone gives no access to sensitive guest, security/prerequisite or confidential commercial content and no business approval authority. An owner may have ordinary independent organization roles, or obtain explicit purpose-bound authorized support elevation. New permission codes default to excluded until classified and approved. Sensitivity metadata is useful for review but not a sufficient policy alone: ordinary permissions may create an indirect escalation path. Protect assignment of sensitive roles, templates, report exports, invitations, jobs, API keys and collaboration scopes against delegated-admin self-escalation and confused-deputy paths. See §3.4 and §17.

Do not amend the accepted ADR or change current managed grants until a successor ADR, migration plan, tests and recovery design are reviewed. Existing `is_platform_admin` flag must not be reinterpreted as ownership automatically. See §20 for compatibility and migration.

## 3. PAC-01 — Identity, authority and role model

### 3.1 Distinguish governance, technical operation and tenant roles

| Role | Default authority | Explicit exclusions |
|---|---|---|
| Platform Owner | Installation governance; appoint/revoke delegated Superadmins via protected authority; platform policies, brand, organization lifecycle, recovery approval | No implicit read of sensitive tenant content; no unrestricted root/SQL or bypass of domain rules |
| Superadmin / Platform Administrator | Delegated global functions, tenant lifecycle/support, settings/health according to assigned capabilities | Cannot self-promote, transfer ownership or weaken own access controls; no automatic restricted data or high-impact business approvals |
| Platform Security Administrator | Security configuration, access review, session revocation, approved incident handling | No credential disclosure, self-grant or audit mutation |
| Platform Operations Administrator | Readiness, queues, logs, backup and release request/monitoring | No access to raw backup contents or tenant secrets by role |
| Platform Auditor | Filtered global audit and governance evidence, explicitly authorized exports | Read-only, no routine business content |
| Organization Administrator | Existing tenant-managed permissions and scoped role presets | No platform authority; cannot change host-managed privilege |
| Host Custodian | Out-of-band OS/deployment/database recovery and bootstrap | Separate real host identity, no fabricated membership actor |

A small self-hosted deployment may assign several roles to one human. Role separation is a capability model, not a requirement for multiple paid staff. One designated owner account (or explicitly approved governance arrangement) per installation is proposed. Owner account is not a shared credential. Host owner and application owner may be different people. An existing independent tenant membership remains independent of platform role changes. System jobs use narrowly scoped service identities, not human Superadmin tokens.

### 3.2 Authorization matrix (proposed; each cell requires specific permissions)

Legend: G = governance approval; D = delegated scoped authority; R = read-only projection; E = separate scoped elevation/business role; H = host operation; — = no default authority.

| Operation | Owner | Superadmin | Security | Ops | Auditor | Org admin | Host |
|---|---|---|---|---|---|---|---|
| Global status/health | R | R | R | R | R | Own scope | H |
| Platform branding/settings | G/D | D | — | D (ops) | R | Own scope | H (recovery) |
| Organization create/suspend/restore | G/D | D | D (incident hold) | — | R | Own allowed commands | H (recovery) |
| Global identities/memberships | G/D | D | D | — | R (redacted) | Own scope | H |
| Delegated platform roles | G | — | R/revoke if delegated | — | R | — | H |
| Owner transfer/recovery | G + H | — | Review only | — | R | — | H |
| Read restricted guest/business data | E | E | E | — | E | Scoped explicit role | H (not normal access) |
| Correct event/booking/attendance | E | E | — | — | — | Scoped command | H (not business actor) |
| Backup/restore/update | G/H | D request | Review | D request/H execution | R | — | H |
| Emergency intervention | G/E | D/E | D/E | D (ops only) | R | Existing domain scope | H |

Do not interpret a broad role label as permission to perform every action in its column. Authorize at command and resource level, evaluate current state and policy, and record the actual actor. No hidden "god mode" or raw table-write UI. Security-sensitive grants themselves are high-impact operations.

### 3.3 Owner setup, transfer and recovery

Keep ADR 0015's flag grant/revoke and ADR 0017/0020 host commands as the initial compatibility/recovery boundary. Bootstrap via #108 installer or host CLI with explicit account ID, reason and strong credential enrollment; never silently promote the first registration, derive owner from email/domain, or embed credentials in images. Prevent last-owner removal/disable or self-revocation from making normal governance irrecoverable. A locked-out owner must be recoverable through a documented offline host process with identity verification, audited reason, session/elevation revocation and credential recovery. No universal backdoor password.

Owner transfer is proposed as a distinct lifecycle: host-authorized initiation, validated successor account, verified MFA and acceptance, explicit confirmation and atomic activation/revocation of ownership authority, session re-evaluation, immutable audit, rollback/recovery instructions. Require independent approval when available; single-owner sites use deliberate local host confirmation for owner transfer, admin grant and disaster recovery rather than fake dual control. Initial version may expose request/status only in PAC; actual `is_platform_admin` changes remain host-only until an approved successor ADR. Do not expose the migration connection or generic flag setter to browser/API. Emergency authority cannot grant ownership or modify its own policy.

### 3.4 Delegation and separation of duties

Proposed platform permission families: `platform.overview.read`, `platform.organization.read/manage`, `platform.account.read/manage`, `platform.membership.manage`, `platform.role.review`, `platform.brand.read/edit/publish`, `platform.config.read/edit/publish`, `platform.module.manage`, `platform.governance.manage`, `platform.communications.manage`, `platform.security.manage`, `platform.audit.read/export`, `platform.ops.read`, `platform.ops.request`, `platform.backup.request`, `platform.release.request`, `platform.support.request/approve`, `platform.emergency.request/approve`, `platform.owner.govern`. Names illustrative; map to current permission catalogue before implementation. Host execution is not a platform permission.

Separate granting authority from the permission being granted. No administrator may self-assign or approve an elevation, expand its own delegation, alter approval policy for a pending action, use role-management to grant itself sensitive permissions, or route around controls by creating a secondary account. Apply maximum grant ceiling and separation-of-duty rules to create/update/clone/preset/import/restore and service job paths. Explicit ordinary tenant membership/role grants remain governed by tenant domain policies. High-risk operations pin approval digest, expected state, target and reason; changes require renewed review.

## 4. PAC-02 — Management authentication and session boundary

- Existing email-first login: preserve credential-first verification before workspace disclosure, rate limits, membership switching, opaque HttpOnly Secure cookies, CSRF/origin checks, session rotation and revocation. PAC is a separate explicit control-plane context, not an organization with a magic ID. Platform-only owner without tenant memberships must have a valid PAC sign-in path after reviewed auth changes.
- Require MFA for Owner/Superadmin and privileged roles; evaluate locally supported WebAuthn/passkeys and TOTP, hashed one-time recovery codes and offline recovery. Enrollment/change/recovery audited; enforce before privileged activation. Avoid relying on external SMS/IdP/internet. Step-up uses current strong authentication, not an old session or UI checkbox; do not log factors, codes or secrets. Suggested recent-auth window 5 minutes for high-impact actions (M0 validation).
- Prefer private management hostname/VPN/intranet ingress with explicit TLS origins and separate host-only cookie, narrow routes, CSP and no public exposure. If same host is chosen, independently scoped management session context, CSRF and reverse-proxy access policy still mandatory. No guest/capability/ordinary tenant token accepted by PAC; PAC token does not authorize a tenant command directly. Route registration/auth matrix enforce separation, not navigation hiding.
- Explicit PAC ↔ organization context transition using real actor and appropriate ordinary/elevated membership; rotate session/context, clear UI/cache/streams and invalidate prior context as appropriate. Preserve original expiration; switching does not refresh recent-auth proof. Distinguish actor and target; no invisible impersonation.
- Re-evaluate role, scope, account/org status, elevation expiry/revocation and policy epoch at every sensitive action and long-running job boundary; revoke sessions/streams and cancel or quarantine unauthorized pending jobs. Do not rely on stale JWT/grant cache. Concurrent revocation and action are ordered under locks/transaction; committed actions are reported, not silently undone. Session list shows device/time/context with minimized metadata, never cookie value.

## 5. PAC-03/04/05 — Organizations, identities and permissions

### 5.1 Organization directory and lifecycle (PAC-03)

Global list with stable ID, display name/slug, state, operating profile (organizer/provider/hybrid), locale/timezone, created date, designated administrators, module readiness, safe aggregate counts, storage/quota, last activity and pending issues. Paginate/filter/sort server-side. No guest/contact list or confidential booking values. Scope delegated admin to permitted organizations when configured; global overview does not imply global detail.

Create organization wizard: unique validated stable slug/code, display name, locale, timezone, operating profile, enabled supported module defaults, designated administrator (existing account or secure invitation), branding fallback, initial policies, configuration preview, confirm. Creation atomic for owner/scope/index/bootstrap records; asynchronous onboarding email separate; retry safe, incomplete onboarding visible, no automatic business records or cross-org data. Use explicit reviewed domain commands; do not clone real guests or venue plans. Reuse existing organization tables/profile commands and private platform index.

Lifecycle: proposed pending/setup → active → suspended → archived; restore to permitted state after validation. Reconcile existing DB status enum/constraints before expanding. Suspend/restore preview lists affected staff sessions, public links, active events, bookings, workers, partner links and outstanding jobs. Define per-domain behavior: block new writes/issuance, revoke affected staff sessions, pause eligible deliveries, preserve already issued legal/commercial history and necessary read-only customer status where policy permits. Do not silently cancel events/bookings or mark notices delivered. Active event/ongoing critical check-in requires explicit operational handling and owner-approved window. Security incident isolation can stop immediate access but must expose consequences and recovery. Archive preserves references and restoration path; deletion only through reviewed retention/anonymization workflow, never ordinary cascade. Host recovery remains available for inactive organizations. No tenant ownership transfer inferred from platform creation.

### 5.2 Global account directory (PAC-04)

Search/filter staff identities by approved display name/email/account ID/state, MFA enrollment indicator, memberships, verification status and delegated authority; show only needed fields, rate-limit search and audit sensitive views/exports. Distinguish global account status from each membership state and event role. No guest identity merge through staff account UI.

Create account by secure invitation (preferred) or host bootstrap (existing). Use one normalized case-insensitive email identity consistent with current login. Existing account goes through membership provisioning, not a duplicate/upsert. Invitation/verification/password-reset tokens high-entropy, purpose-bound, hashed at rest, one-time, expiring, revocable, rate limited and delivery-safe; non-enumerating public responses. Verify mailbox before marking verified. Host bootstrap never asserts verification or role. Accept password through secure form or hidden host input, Argon2id policy; never show or recover old password, hash, MFA seed, recovery codes or token. Initial/no-SMTP path documented secure host enrollment, no plaintext email passwords. Reset revokes appropriate sessions and unused reset tokens; sensitive identity/email changes require current strong authentication or explicit recovery with notifications to old/new verified channels as applicable. Review account collision rather than overwriting credentials. Restore/deactivate/lock/unlock with reason, impact and history; preserve historical actor identifiers. Global disable impacts all workspaces; tenant suspend only that membership. Last-owner safeguard applies.

### 5.3 Memberships, role presets and effective access (PAC-05)

Reuse existing membership/grant primitives. Add/remove/restore through distinct reviewed commands; membership alone grants no data permission. Display organization, status, actual source (ordinary, managed support, temporary elevation), role, scope, expiry and actor, not hidden host data. Provisioning existing accounts follows ADR 0020 (active account/organization, refuses existing memberships; correction distinct). Explain effective permissions through role/source/explicit grant/scope, constraints and expiry; show sensitive permission classification and potential delegation paths. Role presets versioned/reviewed; changes show affected members and privileges. System-managed role identity protected from tenant mutation; don't treat role display name as authority. Revoke, expire and suspend under current authorization with session/stream checks, preserve independent ordinary grants. Cross-org partner collaboration is explicit domain grant, not a consequence of platform support. No role grant auto-adds confidential fields to a global directory.

## 6. PAC-06/07 — UX and global oversight

PAC entry in staff workspace selector only for authorized control-plane users. Dedicated banner/chrome labelled Platform Administration; show current real identity, role, scope, active support/elevation and expiry. Links into tenant workspace clearly indicate tenant and return to PAC. No accidental write to wrong organization. Use Vue modular features and shared accessible components, server-filtered navigation, deep links with auth, no direct PostgreSQL access. Provide keyboard navigation, visible focus, semantic labels, contrast and responsive layouts; bs-BA/en UI catalogs following ADR 0007. User theme is presentation only. Each table has pagination/search, empty/unauthorized/stale/error states, safe export if separately permitted; each high-impact control has impact preview, specific confirmation, reason and receipt. No generic red/green health without data freshness.

### 6.1 Navigation and controls

| Area | Primary views and controls |
|---|---|
| Overview | Status summary, incidents, administrative activity, tenant aggregates, upcoming maintenance, action queue |
| Organizations | Directory, create/onboard, profile, lifecycle, readiness, enter workspace |
| Users & Access | Global account directory, invitations/reset, sessions, membership/grants, effective permission inspector, owner/delegated roles |
| Platform Identity | Product name/logo/favicon, login/about/footer, light/dark theme tokens, language/support/legal metadata, preview/publish |
| Configuration & Modules | Typed defaults, overrides, availability/dependencies, policy impact, revision history |
| Data Governance | Storage/retention/export/import jobs, restore/correction requests, legal holds, privacy requests |
| Communications | Delivery defaults/configuration, test send, queues, reconciliation, platform notices and TDS templates |
| System Health | Service readiness, metrics, incidents, sanitized diagnostics, job age, versions |
| Backups & Recovery | Backup policies, runs, verification/restore drill history, approved recovery requests |
| Security | MFA/session policies, access reviews, anomalies, privilege delegation/elevation, secret status |
| Audit & Support | Filtered append-only receipts, access audit, support cases, intervention request/approval/history |
| Maintenance & Updates | Maintenance windows, release compatibility, preflight, progress, rollback/forward recovery, host action instructions |

### 6.2 Dashboard and data freshness (PAC-07)

Global cards: active/pending/suspended organizations, active staff and privileged sessions (counts only), scheduled/active events, booking counts by safe status, enabled modules, queue age/dead letters/uncertain deliveries, storage, health, latest verified backup/restore, version/schema compatibility, upcoming maintenance, unresolved admin requests. Include time window, last update, source, scope, status and stale/unknown indicator. Small sensitive cohorts may require suppression or aggregation. No guest names, restricted notes, detailed seating/security plans, customer emails or confidential offer prices in overview. Use safe read models/aggregates, bounded refresh, tenant-safe filters and only authorized drill-down. Never construct a cross-tenant row query by disabling RLS in the web API. If metrics are unavailable, display unknown, not zero or healthy. Readiness separate from business progress. No fake uptime based on page load.

## 7. PAC-08 — Platform identity, branding and theming

Explicitly add a versioned **platform-default brand** controlled by deployment governance. Blueprint §41 already specifies inheritance, tenant brands and historical snapshots; the missing control is administrative authoring of the platform layer. Eventor is the software identity; configurable deployment display name, organization and legal ownership labels remain separate from software version, internal IDs, license notices and security status.

### 7.1 Editable controls

| Category | Properties and validation |
|---|---|
| Identity | Display name, tagline, description, About content, platform/deployment owner label, localized support/help contact; safe text or restricted rich content |
| Logos and icons | Primary/compact/wordmark, dark/light variants, favicon/PWA icon variants, safe SVG or bounded raster, dimensions/alt text |
| Visual theme | Primary/secondary/accent, neutral/surface/text/focus and semantic status colors; contrast validation; approved font tokens, base density/spacing within safe bounds |
| Login/selection | Welcome message, approved background/branding, language selector, support links; security notices/auth controls cannot be hidden |
| Footer/legal | Copyright, privacy/terms/help links and localized approved texts; retain required license/attribution and truthful version information |
| Defaults | Light/dark/system preference, supported UI locales, neutral default output templates and platform sender display name (not credentials) |
| Announcements | Localized maintenance/service banners with audience, schedule, priority and expiry; no executable HTML or hidden external requests |

Preview desktop/mobile, light/dark, login/auth failure, PAC, tenant shell, guest-safe sample and TDS output. Draft → review → publish immutable revision; record changed tokens, assets, author/reviewer and digest. Roll back by publishing a new revision referencing previously approved values; never mutate published snapshots. Last-known-good safe bundled fallback if storage/database/theme revision invalid; management/recovery remains legible. Only a minimal approved public bootstrap projection is accessible before login; no organization list disclosure or private brand assets. Tenant login branding only by explicitly public validated tenant routing; never infer organization from email before verification. Asset cache version/digest and purge rules, no private asset URL reuse. No arbitrary CSS/JS, remote fonts, HTML overlays, hiding MFA/security notices, external tracking or unlicensed assets. Accessibility override/high contrast/personal light/dark choices do not affect documents or other users.

### 7.2 Branding inheritance and TDS integration

Property resolution for approved surface: event override → permitted venue override → organization → platform default. Missing inherits; explicit removal only where allowed; mandatory footer/security/legal policy cannot be hidden by tenant override. Explicit ownership and approved shared reference for partner venue assets; booking link never grants access to organizer brand/guests. Platform governance may define allowed overridable properties, not silently overwrite a tenant's published identity. Personal preferences are a separate layer for UI, never an external brand override. Use common brand/asset/component/revision service with #111/TDS, not a competing asset store. Pin resolved brand/template/asset revision manifest at issuance/publication; new platform defaults affect only new resolutions and explicitly reviewed reissues, never old invitations, booking offers or PDFs. Preserve `en` deployment fallback and ADR 0007 resolution; a proposed configurable default for new organizations is distinct from language fallback and does not change existing authored revisions. Locale/timezone separate.

## 8. PAC-09/10 — Configuration registry and module governance

Configuration catalogue defines stable key, type/schema, valid values, scope, default, override rule, sensitivity, required permission, live/restart behavior, validator, impact and change classification. Unknown keys denied. Show effective value and source (bundled/deployment/organization/event), current revision and pending changes; never raw secret values. Draft validate → impact preview → review/confirm → publish atomically with expected revision and audit; rollback through new revision. Typed safe settings can be changed through PAC without rebuilding; infrastructure-owned env/file values are read-only or host-action request with explicit restart/reload. Never arbitrary environment variable writer. Secrets managed separately (§12). Suggested families: locale/timezone defaults, session/inactivity policies, supported upload/queue/storage quotas, notification limits, retention defaults, public endpoint availability, safety policy floors, onboarding, optional capabilities. Settings with legal or operational meaning require owner evidence. Currency, booking policy and event schedule remain domain data; platform defaults do not retroactively alter commitments.

**Module controls:** separate installed/supported version capability, deployment availability, organization default/activation and event activation/override. Display reason, readiness, required dependencies, responsibility owner and effective state. Module registry uses stable IDs and dependency DAG; reject cycles and missing dependencies. Disabled/uninstalled modules cannot be enabled by client or bypassed by direct API/job/subscription. Booking-only path works without guest/RSVP/seating/check-in. Organizer guest registry/event participation prerequisite for relevant RSVP; spatial allocation/admission/portal/cockpit dependencies as defined by owning modules, no hard-coded unnecessary dependency. Disable preview counts active dependencies, published artifacts, queued jobs, public links and ongoing events; block unsafe transitions or use reviewed drain/read-only plan. Do not delete historic data, cancel bookings, invalidate valid status access or alter attendance implicitly. Stop eligible background execution, drain or retain pending work visibly; explicit re-enable with validation. Tenant and event settings cannot override platform safety floor. Configuration alone cannot install missing code or mark a planned feature functional.

## 9. PAC-11 — Data governance, retention and privacy

Governance catalogue by data class/purpose/owner, scope, sensitivity, retention trigger and interval, legal hold, delete/anonymize method, backup treatment and approval owner. No assumed statutory durations. Platform sets supported policies/defaults and minimum protections; tenants choose lawful policy where allowed. Data inventory/storage overview uses aggregate counts/bytes, not raw global data search. Scope each import/export/restore/privacy request to owning organization and exact resource. Data-subject request workflow (verify requester outside general search, authorized owner reviews scope, approve fulfillment/deny with reason, minimal audit, secure delivery) supports correction, access/export, deletion/anonymization where lawful and feasible; no guaranteed deletion of all historic backups. Account anonymization and guest identity correction are distinct. Preserve legally/operationally required snapshots and audit references; redact or pseudonymize via reviewed domain commands. Legal hold blocks purge; reason/expiry/review; do not store confidential case text in general log.

Provide import/export job diagnostics, failed-row counts and authorized error report links; no raw data by default. Bulk operations use preview/diff, target digest, count limits, authorization, preconditions, resumable/idempotent execution and per-item receipts. Affected users/owners informed when policy requires. Deletion schedule dry run, hold check under lock, approved deletion receipt; never generic cascade or mass rewrite. Backup recovery must reapply deletion/hold/revocation reconciliation before exposing restored service. Private artifacts encrypted where required, expiry, access audit, signed/opaque short-lived download only after current permission (no public bearer archive). Export/delete jobs recheck authority; revoked access invalidates download. Avoid collecting new personal information solely for monitoring. Use synthetic data in fixtures/support exports; redact logs, diagnostics, screenshots and support bundles. No real data or keys in Git.

## 10. PAC-12 — Communications and notices

Extend existing notification/delivery configuration and TDS rather than new send subsystem. Platform default sender identity and SMTP/provider configuration are scoped and revisioned, with per-organization override/eligibility policy. No mandatory third-party SMTP: local capture and no-SMTP onboarding supported; external provider optional. Protect credentials with existing delivery encryption boundary or approved deployment secret reference; write-only replacement/rotation, masked existence/version/status, never reveal old value or log provider response secrets. Validate TLS, sender/from policy, reply-to, envelope/route, rate limits and provider capability. Host/network allowlist and safe egress policy for server destinations; no arbitrary URL testing or SSRF endpoint. Test SMTP connectivity and explicit synthetic test-send to approved recipient; no actual invitation/token, no real audience. Monitor queued/leased/sent/accepted/delivered/bounced/suppressed/uncertain with correct distinctions and timestamps. Cancel only eligible unsent jobs; safe retry idempotency, provider reconciliation before resend on uncertain result. Failure codes redacted, no broad recipient list. Reuse delivery history and audit. Global announcements are separate purpose/channel: draft localized content, select authorized platform staff/tenant admin audience, preview counts/digest and impact, approve/publish/send explicitly; no automatic broadcast to all guests. Respect applicable communication policies; branding/templates pin exact TDS revisions. Organization email configurations cannot access other tenant secrets; tenant users cannot edit deployment defaults.

## 11. PAC-13 — Health, diagnostics and job operations

Read-only overview of API liveness/readiness, DB connection/schema, workers (notification/render/solver when supported), storage, outbox/realtime, check-in connectivity aggregates, public portal reachability, release compatibility, TLS expiry and backups. Collect only supported measured signals, source/sample time and thresholds; unknown/stale/missing dependency clear. Liveness separate from readiness; optional module unavailable does not fail entire platform unless required. Readiness public endpoint minimal no internals; detailed health private and authenticated. Metrics CPU/memory/disk/database size, connection pool, latency/error, queue length/oldest age, worker leases, failure/timeout, backup/WAL age, restore duration and capacity. Avoid high-cardinality personal labels. Sanitize log stream/diagnostics at source; bounded time/range, correlation ID, severity, component, error code. No raw SQL, contact data, tokens, passwords, connection strings, provider credentials or key material. Support bundle preview redaction/size before download, explicit authorization and expiry.

Job operations: list type/tenant/safe state/age/attempts; inspect bounded redacted diagnostic; request cancel, retry/reconcile only through owning service with state-specific policy, not arbitrary worker payload edits. No duplicate external side effect. Rate-limit admin polling and isolate health probes; monitor itself must not overload application. Alert lifecycle acknowledge/assign/resolve with receipt and reason; alerts do not claim actual business cancellation. Allow local/on-prem metrics and alerts without SaaS. No unverified availability claims.

## 12. PAC-14/15 — Backup, restore, maintenance, secrets and releases

### 12.1 Backups and recovery (PAC-14)

Policy: selected database backup method, schedule, retention, encrypted off-host destination, WAL/PITR where feasible, coordinated asset/artifact and key backup, verification cadence, restore drill and recovery objectives. RPO/RTO suggested inputs only (§19). Dashboard shows backup type, source release/schema, snapshot consistency point, start/end, bytes/checksum, encrypted target label, WAL coverage/gaps, latest verified restore, next due, failure and expiry. Backup success != verified recoverability. Actual key escrow/rotation and recovery through host secure secret process; preserve matching keys for encrypted contacts/inquiries/delivery/offers and future assets, per existing runbook. No raw key/backup content in PAC.

Backup request: authorized schedule or manual request, bounded target ID, verify disk/credentials/consistency and no conflicting operation; runner records receipt/manifests; failure alerts; retry safe. Retention respects legal hold and off-host policy; verify deletion. Restore is distinct destructive operation: select verified backup/PITR point and explicit target environment; show release/schema, data loss window, key requirements, tenant and public/worker impacts; default isolated restore rehearsal with external delivery disabled, no live token exposure, no public ingress. Validate DB integrity/migrations, assets/checksums, encrypted data decryptability without displaying values, role/RLS and smoke tests. Production restore only host-confirmed with maintenance/quiescence, new pre-restore backup where safe, recovery plan, approval and cutover; reconcile post-snapshot data loss, revocations/deletions, provider delivery uncertainty, outstanding job leases, keys and sessions before traffic. Invalidate old sessions and stale tokens as policy requires; never blindly replay outbound deliveries. Report actual outcome, time and gaps; preserve recovery receipts outside restored database. No unrestricted per-tenant raw restore: tenant recovery uses reviewed scoped export/import/correction unless separate proven tenant-restore design.

### 12.2 Host maintenance boundary (PAC-15)

Mandatory supported host CLI for install, health, upgrade, rollback/forward recovery, backup, restore and service control under #108. PAC may create an authenticated **operation request**, preview, approval, receipt and status. Initial release can require local operator to execute approved command through CLI (copyable safe instructions with nonsecret request ID); this meets safe host control boundary without inventing an always-running privileged daemon. Optional later narrow local executor only after threat-model/ADR and parity testing: separate OS identity, private Unix socket/host-managed channel, allowlisted operations and typed validated parameters, action-specific privileges, caller proof, request signature/digest, expiry/replay prevention, local confirmation for destructive/security-critical actions, locked execution, tamper-evident external receipts and bounded output. Never generic shell/SQL, arbitrary path/URL/image tag/command, unrestricted root/sudo, Docker socket mount, migration DB connection or secret store to application runtime. Runner authenticates requests independently and rejects unsupported actions even if web API compromised. Host availability may fail; UI reports request pending/unavailable, not executed. Browser cannot directly access runner. No remote arbitrary executor.

Secret settings: mark configured/missing/last rotation/key version/expiry and test status only. Runtime-managed encrypted provider credentials remain narrow write-only operations; OS/database/key/TLS/reverse proxy credentials managed by host. Rotation plans include compatibility and recovery; do not destroy keys referenced by historical encrypted records/backups. Audit reference and result, never values. Apply secure file permissions, separate service accounts and least privilege in both deployment modes.

Maintenance: requested/scheduled → reviewed → announced → draining → active → verifying → completed/failed/recovery; per-scope supported modes (read-only, selected module pause, full maintenance), reason/window/impact. Reject unsafe transition while event admission or critical operations active unless explicit incident plan; stop new writes server-side, drain in-flight requests and workers, prevent new jobs, retain appropriate public status and accessible maintenance notice. Health/management/recovery remain available on private path where possible. Host migration lock coordinates with backup/restore/release; maintenance expiry does not automatically reopen unsafe state. Re-enable only after compatibility/readiness and confirmed smoke checks. Internet outage does not disable supported intranet operations.

Release/update: show actual app/frontend/worker/DB schema versions and supported release, signed or checksum-verified trusted distribution manifest, release notes, migration compatibility, security advisories if verified, availability timestamp. Offline package import verified against trusted release metadata; no arbitrary URL fetch, unverified packages or auto-update on viewing. Approved release selection/preflight disk/prereqs/config/schema/dependency/backup/keys, maintenance, graceful drain, deploy same pinned build native/Compose, checksum-verified serialized forward migrations, smoke/health, explicit reopen and receipt. Failed step stops safely and retains logs. Application rollback only if compatible with migrated schema; otherwise reviewed forward fix or verified restore with explicit loss window. No promise of automatic down migration or zero downtime. Host tool works if web/DB unavailable; independent recovery logs, idempotent resume, conflict prevention for simultaneous operations. Final acceptance under #108/Phase 9, not before features/installers ready.

## 13. PAC-16/17 — Controlled interventions and emergency access

### 13.1 Intervention levels

1. Inspect: platform-safe metrics, configs and authorized audit; no tenant content or mutation by default.
2. Administer: ordinary existing tenant authority or explicitly granted time-bounded support access; select exact organization, real actor, approved purpose and domain commands. Inspect before/after diff and submit correction; no silent impersonation.
3. Emergency elevation (break-glass): exceptional documented purpose, strong recent reauthentication, exact target/scope/action allowlist and bounded duration, independent approval where required, prominent UI, access audit and post-event review. Not a permanent Superadmin toggle or generic bypass.

### 13.2 Support cases and grants (PAC-16)

Support case records ticket/reference, requesting actor, affected organization/resource, reason/purpose, requested permission subset, sensitivity, time window, approver, policy version and outcome. Default metadata-only support; request authorized scoped read/edit as needed. Approval by appropriate organization/data authority for sensitive records according to approved governance policy; owner alone not assumed lawful access to all tenants. No wildcard global guest permission or all-events sensitive access. Ordinary independent roles still work through normal workspace with current policy. Support elevation grant links real account/membership and case, exact resources and permitted operations, approval digest, start/expiry and revocation; use existing scope/grant mechanisms or narrow extension after audit. Display live banner with remaining time; server checks time on every operation, expiry and explicit revocation immediately deny new action, revoke relevant session/streams, jobs reauthorize, clear cached content. Audit views/exports as well as edits; notify affected tenant per policy, immediate or justified delay for incident, review receipt. Avoid storing confidential reason text in general logs; use protected case reference.

### 13.3 Emergency recovery (PAC-17)

Proposed initial max elevation 30 minutes, renewal requires new request/approval. Exact purpose allowlist: restore legitimate access, isolate incident, correct a specified record, emergency operational continuity. No automatic approval on timeout, blanket elevation, self-approved sensitive export, ownership change, audit edit, key disclosure or permanent grants. Where a second authorized approver is available require independent review of high-risk request; where installation has only one operator, allow narrowly defined host-confirmed recovery actions under documented single-owner policy, with external protected receipt and mandatory after-action review, not unrestricted self-approval. If lawful/data authorization unavailable, limit to technical containment/recovery without content access. Emergency cannot override immutable history, integrity/safety invariants or legal holds. Always preserve actual actor and approval reason; audit failure blocks normal privileged mutation. Offline emergency host procedures remain separately documented and must import external receipt when restored; no claim host can be technically prevented from accessing its own database. Alert owner/security and affected data owner as policy permits. Test expiry/revoke race, concurrent approval, cached-session denial, last-owner recovery and no privilege persistence.

| Example action | Correct domain behavior |
|---|---|
| Fix guest identity | Existing reviewed registry correction/merge/restoration; maintain pinned event history |
| Modify confirmed booking/offer | Amendment/approved cancellation/disruption command; never mutate accepted commercial snapshot or move money implicitly |
| Reopen archived event | Only documented lifecycle correction with dependencies/approval; if unsupported, reject and record request |
| Change published allocation | New revision, capacity/invariant validation, authorized human approval; no silent solver commit |
| Revoke admission or RSVP link | Correct credential domain; separate from RSVP/attendance facts |
| Correct attendance | Audited append-only domain correction; no retroactive erasure |
| Stop campaign | Cancel eligible unsent deliveries; reconcile uncertain provider outcome |
| Fix stuck background job | Idempotent retry/reconcile supported command; no arbitrary state edit |
| Recover inactive tenant | Reviewed lifecycle/host recovery preserving history and unrelated memberships |
| External prerequisite | Record authorized status/coordination only; never certify external authority's work |
| Repair corrupted database | Host-approved backup/restore or reviewed forward migration; no browser SQL |

If domain command does not exist, PAC must expose unavailable/request workflow, not fabricate functionality. Platform owner has comprehensive *paths to authorized resolution*, not bypass buttons.

## 14. PAC-18 — Architecture and trust boundaries

```text
Private management ingress (TLS, VPN/intranet recommended)
  -> Vue PAC workspace / control-plane session
  -> Fastify PAC module: auth + policy + typed commands + read projections
     -> narrow control-plane DB routines / role (private global metadata)
     -> explicit authorized tenant context -> existing domain services/RLS
     -> append-only audit/outbox -> scoped admin jobs / existing worker
     -> host operation request/status (no host privileges)
          -> local host CLI / approved optional constrained executor
          -> independent recovery receipt / sanitized progress
Public/tenant ingress -> existing guest/staff routes, never PAC by default
TDS / branding / communication / backup tooling shared via explicit interfaces
```

Maintain modular monolith. Suggested frontend feature `apps/staff-web/src/features/platform-administration/`, shared contracts, server module by domain; avoid giant route handler and avoid direct client/database coupling. Global metadata uses narrowly scoped projections and commands, private control-plane schema/tables and least-privilege database role or audited routines. No blanket `BYPASSRLS` or owner/migrator credentials in runtime. Existing private admin tables remain inaccessible to ordinary roles; grant only reviewed functions with pinned search path, revoke PUBLIC execution, validate actor/session/scope and explicit arguments, no arbitrary SQL, bind actual actor from authenticated context not supplied identity. Global tenant metadata can derive from dedicated safe index/read model, or approved narrow cross-tenant aggregate routine with explicit permissions and audit; never broad unrestricted joins or turning RLS off in request path. RLS enforced for tenant content and all delegated domain operations. Separate pools/session context with transaction-local variables, reset and concurrency tests to prevent cross-tenant carryover. Outbox after committed state, idempotent jobs, tenant and policy-aware cache. Global read-only operations should be bounded, paginated, safe counts and not reveal forbidden record existence. PAC availability independent of event/guest modules; offline host recovery independent of PAC.

### 14.1 Audit and accountability (cross-cutting)

Retain existing `platform_admin_audit` as host journal with actual DB principal. Extend compatible receipt model or separate linked application control-plane journal to distinguish host actor, authenticated human account, service principal, actual organization membership, target user/resource, approval and case; never attribute to target or fabricate membership. Append-only records: ID, occurred time, action/result, actor and context, target scope/type/ID, reason/reference, redacted before/after or digests, policy/revision, request/idempotency/correlation, approval/elevation IDs, source session/device metadata minimized. Sensitive reads/downloads/export, denied elevation, role grants, owner changes, backup/restore/update/config/brand changes, session actions and failed host ops auditable. Redact values; audit can itself contain sensitive information; scoped audit read/export with approval and retention. No editable audit UI; protected archival/export and tamper-evident signed/hash-chain/checkpoint option, independently retained host recovery records, no claim tamper-proof against host. Atomic mutation+receipt for privileged domain changes; if audit write fails, rollback (read handling fail closed for sensitive content). Asynchronous external outcomes tracked via state transitions, never claim unverified success. Rate-limit failed auth audit without losing meaningful security evidence.

## 15. Proposed logical data model (not executable DDL)

Inventory existing schemas, status enums and guards first. All tenant-owned references use composite tenant FKs, explicit scope and RLS; global relations are private with narrow projection. Avoid duplicate `users`, `organizations`, role/grant, membership, job, campaign, brand or asset aggregates. Names illustrative. Use UUID conventions already accepted in repository, UTC instants and explicit IANA timezone for local schedules, BCP 47, stable codes, revision checks and immutable published snapshots.

| Logical entity / reuse | Key fields, boundaries and invariants |
|---|---|
| Existing users, organizations, memberships, roles, permissions, grants, sessions | Stable identities/ordinary grants; extend compatible state/management context only after review |
| Platform governance / ownership | Installation ID, owner account, status/revision, host-authorized transfer receipt; last-owner invariant under transaction; do not equate legacy flag with ownership |
| Platform delegated role assignments | Account, explicit capability set and ceiling, optional organization scope, expiry, issuer/approval; no self-grant, default deny unknown |
| Existing platform_admin_organizations / access | Private ID index and managed membership lineage; reconcile reviewed support baseline and retain independent grants/prior status provenance |
| Admin authentication factors / recovery | Account, factor metadata and protected verifier/seed where required, enrollment/revocation; secrets never projected |
| Identity onboarding/recovery challenges | Purpose/account or pending target, digest, expiry, attempt/use/revoke state; no raw reusable token storage |
| Platform config definitions / revisions | Stable typed key, scope/override class, proposed/effective value or secret ref, state/revision/digest/approval; immutable published revisions |
| Module definitions / effective assignment | Installed support, dependency graph, scope, policy revision, enable/drain state, impact snapshot; no orphan dependencies |
| Brand profile/revisions / assets (shared TDS) | Platform or explicit tenant ownership, typed properties, localized values, pinned assets, approval and published digest; no public private assets |
| Support case / temporary grant | Case, actual actor, owner scope/resource, action allowlist, approval/policy, expires/revoked, sensitivity/reason; no wildcard restricted access |
| Intervention request / review | Type, exact target, canonical payload digest, impact, revision, approval and command receipt; no arbitrary payload execution |
| Governance policy / hold / privacy request | Class, owner/purpose, retention/hold scope, approved lifecycle and outcome; hold protected against purge races |
| Existing jobs or admin job extension | Tenant or control-plane type, actor/case, idempotency, expected version, state/lease/attempt/progress, redacted diagnostics; reauthorize |
| Health snapshot / alert | Component, scope, sample/source/time/value/status, freshness and acknowledgement; bounded retention |
| Backup policy / backup manifest | Configured target ref, consistency/release/schema/key refs, hashes/size, verified status/coverage, retention; no raw content/key |
| Host operation request / receipt | Fixed operation enum, target ID, typed args digest, approval, expiry/replay nonce, runner identity, status and external recovery receipt reference |
| Release/maintenance record | Trusted release/version/checksum, compatibility, window, phase/drain/verification and recovery plan; serialized destructive action lock |
| Existing platform_admin_audit / application audit extension | Append-only host and app actor semantics, target, decision, correlation, redacted summary; separate access audit and retention |

Database invariants: owner uniqueness/last-owner protection; valid role ceiling; protected system-managed memberships; no cross-tenant FKs; grant/elevation expiry and scope checked server-side; idempotency uniqueness by actor/scope/action+request fingerprint; revision and approval digest consistency; immutable historical business snapshots; protected audit; no destructive purge under hold; exactly one conflicting maintenance action at a time; runner receipts cannot be fabricated by user input. Use canonical lock order and concurrency regression tests. Existing statuses and schema not silently rewritten. Forward migrations only, compatibility and populated upgrade tests in §20.

## 16. Proposed API and command contract

All route names below are conceptual; M0 reconciles them with `docs/api/openapi.v0.3.yaml`, existing error shapes, request ID, authentication, route naming and shared TypeScript contracts. These are not runtime endpoints or a commitment to one exact URL namespace. No existing contract change is authorized by this document.

### 16.1 Read projections

| Proposed method and route | Scope and result |
|---|---|
| GET /platform/me | Real actor, control-plane role/capability set, MFA/recent-auth indicator, accessible sections; no tenant data or raw session secret |
| GET /platform/overview | Approved bounded aggregate metrics with scope, source and observedAt/freshness |
| GET /platform/organizations | Filtered, paginated, safe global directory |
| GET /platform/organizations/{orgId} | Authorized profile, effective configuration and lifecycle/health summary |
| GET /platform/accounts | Paginated authorized global staff directory; field-specific authorization |
| GET /platform/accounts/{accountId}/memberships | Scoped membership/grant provenance and safe session status |
| GET /platform/accounts/{accountId}/effective-access | Effective permission sources, scope, expiry and delegation constraints; not secret values |
| GET /platform/permissions | Approved grantable catalogue, risk class, delegation ceiling |
| GET /platform/brand-profiles/default | Current published/draft platform revisions according to permission |
| GET /platform/configuration | Typed effective settings, revision and source, restart requirements; secret metadata only |
| GET /platform/modules | Installed/supported status, dependencies, effective scope and reason |
| GET /platform/governance/{policies,holds,requests} | Authorized policy/hold/request summaries |
| GET /platform/communications/{configuration,deliveries} | Redacted config/delivery health and authorized job summaries |
| GET /platform/health, /platform/jobs, /platform/alerts | Bounded status, safe diagnostic codes and freshness |
| GET /platform/backups, /platform/releases, /platform/maintenance | Approved manifest/status/recovery readiness |
| GET /platform/interventions/{id} | Request, approved target/operation, state, scope, expiry and receipts |
| GET /platform/audit | Paginated/redacted audit; sensitive filters/exports independently authorized |

An explicitly allowlisted public brand-bootstrap projection, if used for login, returns only the published nonpersonal platform identity/tokens/assets. No tenant directory, account existence, management URL, release internals or configuration secrets. Public liveness/readiness surfaces return minimal health states only as intended by deployment policy.

### 16.2 State-changing commands

| Proposed command family | Preconditions and resulting effect |
|---|---|
| POST /platform/organizations | Validated setup preview, unique slug, explicit operating profile/initial admin; atomic creation; onboarding separate |
| POST /platform/organizations/{orgId}/lifecycle-requests | Expected revision, target state, dependency impact/reason; approval and explicit execution; no implicit event cancellation |
| POST /platform/account-invitations | Authorized target identity/membership, purpose-bound expiring token; existing identity reuse; no verification assertion |
| POST /platform/accounts/{accountId}/recovery-requests | Strong actor authorization; secure reset/enrollment workflow; no old password disclosure |
| POST /platform/accounts/{accountId}/status-commands | Revision, impact, reason, last-owner check; status and session effects atomic where feasible |
| POST /platform/accounts/{accountId}/session-revocations | Exact session/all scoped, current authority; receipt and effective revocation |
| POST /platform/membership-commands | Target account/org, distinct provision/revoke/restore, expected revision, audit; ordinary roles separate |
| POST /platform/delegation-requests | Explicit permission subset/scope/expiry, ceiling and independent approval; initial host-only activation where required |
| POST /platform/owner-transfer-requests | Host-confirmed request only; successor verification and accepted governance policy; no generic flag setter |
| POST /platform/workspace-transitions | Explicit target context/ordinary or support authority; rotate session, preserve real actor and expiry |
| POST /platform/brand-drafts; PATCH draft; POST validate/review/publish | Typed safe tokens, assets, locale, digest/expected revision, approved immutable publication; rollback as new revision |
| POST /platform/configuration-change-requests | Typed allowlisted keys, preflight, dependency/impact digest, approval and explicit publish/reload request |
| POST /platform/module-change-requests | Installed capability, scope, dependency validation, impact/drain; no destructive history changes |
| POST /platform/governance/{hold,privacy,purge,export}-requests | Scope, legal/owner policy, preview, approval; bounded jobs; current download authorization |
| POST /platform/communications/test-deliveries | Verified approved target, synthetic test, masked provider config, rate limit; not a broadcast |
| POST /platform/announcements | Reviewed draft, localized audience digest, schedule and explicit publication/send |
| POST /platform/jobs/{id}/action-requests | Owning service allowlist; safe cancel/retry/reconcile; no arbitrary payload edit |
| POST /platform/host-operation-requests | Fixed type/target, validated args, preflight and approval; status pending local host execution, no shell invocation |
| POST /platform/support-cases | Specific scope/purpose and owner authority, bounded permissions; no automatic content access |
| POST /platform/intervention-requests | Exact command/target, expected state, impact, reason, case and scope; no generic CRUD bypass |
| POST /platform/requests/{id}/review-decisions | Current independent authority, digest and decision, append-only review; no auto approval |
| POST /platform/requests/{id}/execute | Recheck actual actor/approval/expiry/preconditions; dispatch only typed owning command or host-request state |
| POST /platform/elevations/{id}/revoke | Current authority, revoke grant/session/streams and prevent queued unauthorized execution |
| POST /platform/audit-export-requests | Authorized scope, approved fields/retention and private artifact job; no unrestricted raw logs |

Separate password-reset/verification/token enrollment paths may require public access but must be explicitly allowlisted for their own purposes, never PAC route exposure. Host completion receipts enter only through trusted local CLI or separately approved authenticated executor channel. A staff browser cannot mark a host operation successful.

### 16.3 Request, approval, response and error semantics

Illustrative request for reviewed configuration change (not a real API):

```json
{
  "action": "platform.brand.publish",
  "target": {"kind": "platformBrandRevision", "id": "synthetic-revision-id"},
  "expectedRevision": 7,
  "reason": "Publish approved visual identity",
  "impactDigest": "server-generated-preview-digest"
}
```

Actual API requires canonical IDs, validated schema and nonsecret bounded reason. Actor ID and authorization scope come from session, not payload. Mutation idempotency scoped by actor/action/resource, canonical request fingerprint; same key/same payload returns existing receipt after current permission check, changed payload conflicts. Use existing precondition conventions (expectedRevision/If-Match as appropriate), optimistic concurrency and deterministic lock order. Approval binds action, target, digest, actor policy, expiry, relevant version and effect; stale policy/state/target/inputs invalidate review. Never accept arbitrary serialized SQL, executable script, caller-specified role, generic object path or unvalidated target. Job APIs return accepted/requested state, not success until trusted result. Example result fields: requestId, state, scope, expectedRevision, impactSummary, approvalRequirement, expiry, correlationId, safeErrorCode, receiptId. Audit/history redacted. Use existing structured problem details and correlation IDs: 401 unauthenticated; 403 forbidden or non-enumerating equivalent; 404 safe not-found; 409 stale/conflict; validation 400/422 per existing convention; 429 bounded limits; 503 unavailable. No response exposes forbidden-field presence, password/key hash/secret, raw SQL or sensitive exception. OpenAPI, shared types, representative fixtures, auth matrix and contract validation updated together when implementation begins.

## 17. Threat model and non-negotiable security boundaries

Assume malicious tenant staff, compromised ordinary account, overprivileged/compromised Superadmin, compromised browser or application runtime, hostile upload/branding content, stale elevated session, malicious package and accidental owner operation. A trusted host custodian retains technical power over its host; the application cannot promise protection against an adversarial root or database owner. Separate protection domains and independent recovery evidence reduce risk.

| Threat | Required mitigation and verification |
|---|---|
| Blanket managed role / future permission expansion | Explicit reviewed allowlist, default deny new codes, test effective permissions including indirect escalation; reconcile ADR 0015 via successor decision |
| Tenant enumeration and disclosure | Separate platform-safe projections, exact scopes, forced RLS, tenant composite FKs, safe errors, scoped cache/metrics/export; test two tenants and partner grants |
| Cross-tenant pool/session residue | Transaction-local context, reset on failure, distinct management context, concurrency tests for same pooled connection and switching |
| Self-promotion or privilege delegation bypass | Host-only root authority, grant ceiling, independent approvals, protected system roles; test create/clone/import/secondary-account paths |
| Owner lockout / takeover | Explicit host bootstrap, MFA and last-owner guard, secure verified transfer, audited offline recovery; no default credentials |
| Authentication/CSRF/session theft | TLS, secure opaque cookies, strong MFA/step-up, origin/CSRF, bounded attempts, rotation/revocation, no public PAC routes |
| Support impersonation / expired elevation | Real actor context, exact approved scope/time, current server check, revoke stream/job/download, banner and access audit; race tests |
| Confidential content through aggregates/logs | Data minimization, suppression where needed, redaction, safe diagnostic exports; test token/contact/secret leakage across logs and errors |
| Unsafe branding/upload | Safe token schema, quarantined assets, bounded decode, sanitized SVG, no arbitrary CSS/JS or remote resource load; fallback login, no security notice hiding |
| SMTP/asset/diagnostic SSRF | Fixed allowlisted endpoints/egress, reject unapproved targets/private destinations as policy dictates, DNS/redirect handling, no arbitrary URL test proxy |
| Destructive action / stale approval | Preview, digest, reason, preconditions, independent confirmation, immutable audit, idempotency and canonical locks |
| Renderer/worker confused deputy | Explicit purpose, scope, actor/service authorization, bounded immutable job inputs, revalidation, no cross-tenant batch leakage |
| Host privilege escalation | No root/shell/Docker socket/owner DB credentials in runtime, independently validated allowlisted local host action, replay and malicious-argument tests |
| Restore revives revoked access/deleted data or sends again | Isolated rehearsal, protected reconciliation/cutover, session and delivery safeguards, reapply holds/deletion/revocation before exposure |
| Malicious software update | Trusted signed/checksum-verified artifacts, approved version/target, preflight/backup, host confirmation, fail closed |
| Audit tampering / false actor | Append-only protected records, atomic mutation receipt, real user/service/host principal, external recovery journal, verification evidence |
| Resource exhaustion | Bounded pagination, aggregate refresh, upload/queue/export limits, rate limiting, isolated jobs, controlled maintenance locks |

M0 must inventory current permissions (`is_sensitive`, scope and actual command checks), authentication/role privilege graph, existing token and audit mechanisms, private table/RLS grants, event/organization lifecycle and all background job paths. Record risks, decision, tests and migration plan in a successor ADR. Review adversarial permission combinations, not only role labels. No claim of current exploitability without reproducible evidence. If a verified material vulnerability is found, document and handle through normal security-fix policy independent of scheduling PAC features; avoid broad speculative rewrites.

## 18. Accessibility, localization, observability and operational quality

Target WCAG 2.2 AA for PAC interfaces; use actual keyboard-only, focus, contrast, semantic table/status, zoom/reflow and assistive technology checks. Critical operations show explicit text status, impact and pending state rather than color alone. Confirmation must name target and effect, not a generic OK. Destructive actions have deliberate separate review, no default auto-confirm. Errors preserve safe draft input without credentials. Use `bs-BA` and `en` for initial UI, localized text and date formatting while retaining stable codes; correct Č Ć Ž Š Đ rendering and locale/timezone independence. Translated content separately versioned, no machine-generated legal translations. Preserve historical brand and business outputs when changing settings. No unsupported browser-specific feature as sole means of administering the platform; host CLI fallback for critical recovery.

Observability includes structured correlation IDs, counts/durations, operation age and failures, security/elevation events and queue/backup health. Use actual sample timestamp/coverage and explicit stale thresholds. Instrument no guest names/emails/tokens/secret values or tenant-sensitive metric labels. Ensure dashboard refresh and admin exports cannot starve ordinary event/check-in services. Audit performance, operations and security separately. Document unsupported states, scope and evidence gaps.

## 19. Proposed non-functional targets and deployment constraints

The following are initial engineering test inputs, not measured SLOs or production sizing commitments. Refine M0 with reference host and realistic tenant/event scale; single-node and external database deployments may differ.

| Target | Provisional acceptance input |
|---|---|
| Reference environment | Linux 4 vCPU, 8 GiB RAM, SSD, local PostgreSQL; same application build native and Compose |
| Directory responsiveness | p95 ≤ 1 s for first 50 rows at synthetic 100 organizations / 10,000 staff identities with indexed filters; report measured hardware/data |
| Overview response | p95 ≤ 2 s for bounded cached safe aggregate, no unbounded cross-tenant query; sample age displayed |
| Health freshness | Suggested refresh 30 s; stale after 90 s without valid sample; configurable per signal, unknown not healthy |
| Privileged step-up | Suggested 5 min maximum recent-auth age, high-risk explicit re-check |
| Support/emergency access | Suggested max 30 min emergency, scoped support default 60 min; no automatic renewal; current action checks |
| Audit | Mutation receipt atomic, time/correlation/actor complete; no personal payload or raw secrets in operational logs |
| Backup/recovery | Provisional daily verified backup policy, off-host encrypted copy; RPO/RTO candidate 24 h/4 h unless tighter tested PITR objectives selected; not guarantees |
| Operations isolation | Concurrent backup/maintenance/release conflicts serialized; render/export/jobs bounded; API remains responsive during supported operations |

Native and Docker production installers use same governance/configuration contract, migrations, release fonts/assets, secure defaults and host command semantics. Native service identities/systemd and Compose nonroot containers/volumes must be tested independently. No assumption inbound HTTP port 80/SMTP port 25, mandatory external SMTP, external OIDC or a dedicated production server. TLS/DNS/network validation follows #108. Local capture and offline host procedures available. Host update and recovery can be used when web service unavailable. Backup restore verifies database, private assets/artifacts, encryption key availability and application compatibility. Do not schedule final acceptance VM merely for this specification; use existing automated tests and synthetic local fixtures during implementation.

## 20. Migration, compatibility and Codex continuity

### 20.1 Safe reconciliation sequence (only when scheduled and approved)

1. Inventory actual main and active branches, ADR 0015 semantics, `platform_admin_access` provenance, ordinary memberships/grants, effective sensitive capabilities, session switching, host audit, current auth role permissions, owner recovery, legacy data and integrations. Reuse rather than duplicate existing aggregates. Record evidence and propose successor ADR; no grant changes during documentation review.
2. Introduce compatible platform governance/capability metadata and private read models; keep old host flags/commands working during transition. Choose explicit owner mapping via authenticated host operation; never auto-promote all legacy platform admins or the first user. Establish recovery account/CLI, last-owner checks, MFA enrollment and reviewed delegation mapping first. Report legacy incompatible configurations to operator. Avoid lockout and no silent fallback to unrestricted access.
3. Dry-run report old vs new effective permissions per existing managed role, distinguishing ordinary independent grants and prior membership state. Audit downstream routes/jobs and role-editing escalation paths. Review explicit allowlist and sensitive grant policies. Test with populated upgrade (existing admins, ordinary memberships, inactive tenants, revoked sessions, legacy role references and newly introduced permission codes). No destructive deletion or editing historical migrations.
4. Under approved controlled cutover, atomically reconcile only identified system-managed role permissions and grants to approved baseline; remove overbroad managed permissions, preserve independent ordinary grants and historical actor IDs. Replace refresh algorithm so it cannot re-add excluded codes; new non-platform codes default denied. Bind session/policy version or revoke affected sessions and streams; handle concurrent refresh/revoke consistently, reauthorize jobs and sensitive downloads. Verify RLS, host recovery, role protection and no cross-tenant leakage. Fail safely with recovery plan, do not leave mixed blanket-grant state.
5. Add explicit PAC control-plane session and narrow commands incrementally after authority tests. Adapt host scripts via reviewed compatibility path, retain independently usable recovery; no automatic ability for normal runtime to change host flags. Do not remove existing working provisioning until replacement proven. Preserve append-only host audit and real actor. Forward migrations checksum-verified; application rollback only schema-compatible, otherwise reviewed forward fix or verified restore.
6. Add branding, modules, governance, operational requests and TDS integrations as owning modules mature. Update actual OpenAPI, shared contracts, migration references, UI/i18n and tests per vertical slice. Do not count design or schema alone as functional completion.

### 20.2 Development sequence and backlog mapping

| Package | Deliverable | Ownership/dependency and release gate |
|---|---|---|
| PAC-M0 | Baseline audit, authority/threat model, successor ADR(s), host recovery design, UI/API/schema plan | Review actual main when scheduled; no implementation assumption |
| PAC-M1 | Protected owner/delegated role model, MFA/session context, managed-grant reconciliation, recovery and audit | #104/auth foundation; security prerequisite for expanded PAC; populated upgrade + negative/concurrency tests |
| PAC-M2 | PAC shell, overview, organizations, global account onboarding/recovery, memberships and permission inspection | #104 existing organization/access commands; no duplicated event/guest CRUD |
| PAC-M3 | Platform identity, theme editor, typed defaults/modules, publication/rollback and safe announcements | #111/TDS common asset and brand revisions, ADR 0004/0007; optional modules kept independent |
| PAC-M4 | Data governance, support/elevation, controlled domain interventions, communications and jobs | Existing domain commands; #112 booking/disruption; #105–107 spatial/admission/cockpit, #110 vendor as available; no fabricated missing domain actions |
| PAC-M5 | Health/diagnostics, backup/restore, maintenance/release requests and host CLI integration | #108 native/Compose, verified recovery and trusted release manifests |
| PAC-M6 | Cross-domain hardening, complete tests, documentation, dual installer release gates and final acceptance | Coherent release candidate after product tracks; Phase 9 QEMU/KVM final acceptance only |

**Codex continuity — explicit handoff:** This proposal is backlog/design clarification, not an immediate coding assignment. Preserve current Codex work on #104 and #112, then #105–107 critical path, other established tracks #110/#111 and dual installers #108. Do not reset its checkout, reapply prior changes, alter its branches, rebase, merge, modify `PROJECT_STATE.md`, install dependencies, start a new application implementation or republish environment as a consequence of this draft. Schedule PAC work packages under existing #104/#108/#111 and their domain dependencies when the owner approves sequencing; no duplicate issue proliferation now. M0 security review may identify independently verified defects for ordinary security remediation; that is not permission for a speculative broad rewrite. PAC-M1 authority reconciliation is a gate before exposing new privileged control-plane actions. M3 branding depends on the shared TDS implementation, not on seating or check-in for basic platform identity. M5 host functionality depends on installers/recovery work and does not require early VM testing. Keep all original issue acceptance criteria. Use small vertical PRs, exact-head CI and post-merge checks as existing practice. No code work authorized by this document.

## 21. Measurable acceptance criteria and verification matrix

All criteria below are proposed release requirements for the applicable delivered scope. Tests use synthetic fixtures; no real credentials, guest identities, private venue plans or operationally sensitive data in Git. A skipped external check is not a pass. Evidence must include exact commit, environment, test results and any unverified limitation. Existing CI remains required; manual tests supplement rather than replace database/API/browser/security regression. No completion credit solely for schema, docs, mockup or test stub.

| ID | Requirement / measurable scenario | Evidence |
|---|---|---|
| PAC-AC-01 | Explicit host bootstrap designates approved owner; ordinary account/first registration and legacy flag alone cannot become owner; last owner cannot be accidentally disabled | DB/API/host |
| PAC-AC-02 | Owner transfer uses verified successor, host confirmation and audit; old owner authority and sessions revoked as required; offline recovery succeeds on disposable environment | Host/DB/E2E |
| PAC-AC-03 | Existing platform-managed roles reconcile only managed grants to approved allowlist; independent tenant roles and historical references unchanged; new permission code not automatically granted | Populated upgrade/DB |
| PAC-AC-04 | Platform owner/Superadmin without explicit sensitive grant cannot read guest notes, contacts, prerequisite attachments or confidential commercial fields via API, exports, report templates, jobs or indirect role editing | Two-tenant negative matrix |
| PAC-AC-05 | Ordinary tenant admin cannot read control-plane tables or invoke PAC, host flag setter, owner transfer or global directory; delegated admin cannot self-promote/create proxy privileged user | DB role/API/security |
| PAC-AC-06 | MFA enrollment, login, step-up, recovery and revoke tested; expired or unverified step-up rejects high-impact command; secrets not exposed | Auth/browser/security |
| PAC-AC-07 | PAC/tenant/public sessions isolated; workspace switch retains real actor, rotates context, clears previous data, preserves expiry; pooled concurrent context never leaks | DB/API/browser/concurrency |
| PAC-AC-08 | Organization wizard creates unique configured organization and reviewed admin membership; retry produces one record, duplicate slug rejected, failed transaction leaves no partial bootstrap | DB/API/browser |
| PAC-AC-09 | Suspend impact identifies active events, sessions, jobs and public links; unsafe transition blocked or reviewed; history retained; restore revalidates state; no implicit booking/event cancellation | Integration/concurrency |
| PAC-AC-10 | Invite existing case-insensitive identity without duplicate account; new invitation is one-time/purpose-bound and verified only after enrollment; revoked/expired token denied | Auth/API/SMTP capture |
| PAC-AC-11 | Password reset/identity change does not disclose old credentials; targeted sessions revoked; non-enumerating errors; host bootstrap still works without SMTP | Auth/host/security |
| PAC-AC-12 | Membership alone grants no data access; directory/effective permissions show source and scope; grant/revoke and role-preset impact preserve unrelated memberships | DB/API/browser |
| PAC-AC-13 | Owner/delegated admin sees correct authorized overview counts with source and timestamp; unavailable/stale metric marked unknown, no small-cohort or restricted detail leakage | API/browser/fixture |
| PAC-AC-14 | Platform branding changes name/logo/favicon, approved theme, localized login/footer/support through draft/preview/publish without rebuild; rollback creates revision; invalid brand falls back safely | Browser/DB/i18n |
| PAC-AC-15 | Platform→organization→venue→event property inheritance correct; two tenants isolated; personal dark mode does not alter published artifacts; old TDS outputs retain exact pinned brand | Unit/API/TDS E2E |
| PAC-AC-16 | Unsafe SVG/HTML/CSS/remote assets rejected; public bootstrap exposes only approved public identity; login/MFA/security notices remain visible and usable | Security/browser |
| PAC-AC-17 | Typed config rejects unknown keys/invalid values; stale preview/revision conflicts; published settings show effective source, restart required and audit; secrets masked | DB/API/browser |
| PAC-AC-18 | Booking-only organization runs without guest/seating modules; enable missing dependency rejected; disabling active dependent module requires approved drain; historic records retained | Domain integration |
| PAC-AC-19 | Data inventory, retention dry run, legal hold and approved purge/anonymization honor scope; concurrent hold blocks deletion; retained snapshots/history safe | DB/concurrency/governance |
| PAC-AC-20 | Import/export/privacy requests reviewed; artifacts private and expires/revokes on authority change; no global raw guest list or unapproved data download | API/security/worker |
| PAC-AC-21 | Platform SMTP default/tenant override controlled, credentials write-only, safe connectivity check; synthetic marked test send has no live invitation/QR; unauthorized tenant cannot read secrets | DB/API/SMTP/security |
| PAC-AC-22 | Broadcast/announcement pins audience and localized content, separate preview/approve/send; cancel only eligible unsent jobs; uncertain provider result not blindly resent | Worker/API/browser |
| PAC-AC-23 | Health shows actual API/DB/worker/storage/schema readiness and stale state; optional module failure differentiated; safe bounded logs/support bundle contain no tokens/contact/key values | Host/API/log review |
| PAC-AC-24 | Safe job retry/cancel/reconcile enforces owning state/permission; duplicate requests and concurrent workers do not duplicate external effects | Worker/DB/concurrency |
| PAC-AC-25 | Backup manifest verifies encryption, independent destination, checksum, consistency and key references; failed/late/partial backup visibly flagged; success not conflated with restore drill | Host/backup drill |
| PAC-AC-26 | Isolated restore of database/assets/keys verifies integrity and matching release; external delivery/public ingress disabled; record actual RPO/RTO and test evidence | Native/Compose restore |
| PAC-AC-27 | Production-style restore on disposable target requires host confirmation, maintenance, data-loss preview, reconciliation of old sessions/revoked access/holds/delivery; independent recovery receipt survives restore | Recovery rehearsal |
| PAC-AC-28 | Untrusted host action (arbitrary shell/SQL/path/URL/arguments/replay) rejected; runtime has no root/Docker socket/owner DB creds; browser cannot forge completion; host CLI works with application down | Host/security |
| PAC-AC-29 | Maintenance drains workers, prevents forbidden writes, displays notice, retains authorized status paths and blocks conflicting operations; failure does not silently reopen service | Host/API/concurrency |
| PAC-AC-30 | Trusted update artifact/preflight/backup/migrations/verification; unverified release rejected; failed upgrade stops with recovery receipt; incompatible code rollback prevented | Installer/upgrade |
| PAC-AC-31 | Support request uses exact target, approved purpose and scoped permissions, visible real actor; no silent impersonation; audit includes reads/edits | API/browser/audit |
| PAC-AC-32 | Emergency access strong step-up, bounded expiry, appropriate approval or documented local host recovery; cannot extend own scope/owner privilege; expiration/revoke blocks new commands, streams, jobs and downloads | Security/concurrency |
| PAC-AC-33 | Controlled correction uses domain command, not direct state mutation; published plan/offer unchanged except new approved revision, attendance correction append-only; unsupported domain action unavailable | Cross-domain E2E |
| PAC-AC-34 | Privileged mutation rolls back on audit failure; journal append-only, correct actual actor/target/host principal and redacted before/after; audit export independently authorized | DB/API/security |
| PAC-AC-35 | Concurrent stale approval/revocation, role changes, org suspension and maintenance actions are serialized/rejected correctly; idempotent retry cannot broaden scope | DB/API concurrency |
| PAC-AC-36 | Keyboard-only creation, preview, review/publish, scope selection, lifecycle and recovery request; contrast, focus, status/confirmation and accessible errors; bs-BA/en and diacritics | Browser/manual accessibility |
| PAC-AC-37 | Provisional scale/load targets measured with actual hardware/fixture; bounded dashboard, filters, export and background jobs do not starve event/check-in; unsupported measurements reported | Load/operations |
| PAC-AC-38 | Fresh and populated migrations, existing tenant/booking/invitation/RSVP/session/host provisioning regressions, OpenAPI/shared types, frontend build and dependency/security checks pass | Exact-head + post-merge CI |
| PAC-AC-39 | Native and Compose share same configuration, secure service identities, recovery/health/backup/upgrade functions; full owner workflow usable after clean install in both | Phase 9 acceptance VM |
| PAC-AC-40 | Original #104/#108/#111 and related domain acceptance remains intact; no premature VM reliance, no Studio/PAC feature assumed implemented from documentation | Traceability/release evidence |

### Representative integrated acceptance journey

On disposable fixture installation, host provisions owner using documented secure process. Owner enrolls MFA, opens PAC, checks measured health, configures neutral bilingual Eventor identity/logo/light-dark tokens, previews and publishes version 1. Creates organizer A and venue-provider B with different brand overrides and accounts. Provider cannot read organizer guest records. Owner delegates a Superadmin only tenant-lifecycle/health scope; attempts restricted data export/self-grant fail. Owner enters A under independently approved organization role, then requests a narrow support correction with explicit reason; actor and scope are visible, domain command preserves history. Revoke elevation concurrently; subsequent reads/edits/exports/stream/job work denied, committed outcome retained. Publish new platform brand and verify historical invitation retains original pinned revision. Test booking-only B with guest modules disabled. Perform synthetic communication test and safe queue failure/reconciliation. Generate backup with verified manifest, isolated restore with external delivery disabled, validate assets/keys and record recovery evidence. Request maintenance/release preflight, host confirms, upgrade on supported disposable target, verify recovery and health. Repeat clean native and Compose installations during final acceptance; record any unresolved gaps. Exercise single-owner lockout and recovery without requiring an unavailable second reviewer.

## 22. Open decisions and proposed integration plan

The owner is asked to approve product scope, not exact library, DDL, route names, quota or production SLO. Resolve before implementation as relevant:

1. Ownership governance: single designated owner vs explicit multiple-owner policy; host-only initial grant and protected transfer; local single-owner confirmation and independent approval thresholds. Define lawful data-owner consent/approval and incident notification policy for sensitive support access.
2. ADR 0015 reconciliation: effective access inventory, safe managed baseline and successor ADR; retain current working authority until reviewed migration. Approve exact permission classification/ceiling and host recovery path.
3. MFA mechanism, offline enrollment/recovery, management hostname/VPN or same-host separation, session and recent-auth limits. No mandatory IdP.
4. Branding: which properties owner may constrain, public asset policy, attribution and approved legal/support text; align TDS #232 once integrated. No GHB assets assumed.
5. Module dependency and suspension matrix by owning domain, critical-event continuity, existing legal/customer status and delivery effects. No generic toggle bypass.
6. Data retention/holds, privacy approval, backup/key escrow, RPO/RTO, log access and emergency review policies; no invented legal obligations.
7. Host operations UX: initial request+local CLI, optional later constrained executor only after threat-model decision; trusted release signing/checksum policy and supported distributions.
8. Confirm final workload/metrics and performance budgets; refine acceptance with real synthetic measurements. Library choices, exact data model and implementation estimates remain open.

After owner approval, prepare an isolated documentation PR adding this versioned design under v0.3, linking the design index, architecture, roadmap and gap analysis with a dated clarification. Preserve historical Blueprint v1.2 and accepted ADR texts; explicitly label the proposed successor authority decision and defer its actual acceptance/migration to M0/M1 review. Append scope references to #104/#108/#111 without replacing existing criteria or changing priorities; coordinate with TDS PR #232 and current main to avoid overlapping documentation edits. Use work-package checklist rather than immediate child issue proliferation. Verify docs-only diff and CI before safe merge; no changes to Codex active branches or environment. This proposed integration is not executed by this task.

## Appendix A — Repository references (read-only inspection)

All references are under the inspected repository and should be revalidated at implementation time. Links to main may advance; inspected commit is recorded on the cover.

- [Technical Blueprint v1.2](https://github.com/TeraflopsBH/eventor/blob/e69d1c9cf86e8c4e55c4ee03f7c291830383bb2c/docs/blueprint/v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md), especially §§4, 18–25, 35, 38, 41, 46.
- [User Roles and Permissions v0.1](https://github.com/TeraflopsBH/eventor/blob/main/docs/product/USER_ROLES_AND_PERMISSIONS_v0.1.md).
- [ADR 0015](https://github.com/TeraflopsBH/eventor/blob/main/docs/decisions/0015-email-first-login-and-platform-administration.md), [ADR 0017](https://github.com/TeraflopsBH/eventor/blob/main/docs/decisions/0017-host-staff-account-bootstrap.md), [ADR 0020](https://github.com/TeraflopsBH/eventor/blob/main/docs/decisions/0020-host-existing-staff-membership.md).
- [Accepted decisions directory](https://github.com/TeraflopsBH/eventor/tree/main/docs/decisions) (ADR 0004–0008 and subsequent domain decisions).
- [Architecture](https://github.com/TeraflopsBH/eventor/blob/main/docs/ARCHITECTURE.md), [Operating model](https://github.com/TeraflopsBH/eventor/blob/main/docs/OPERATING_MODEL.md), [Project state](https://github.com/TeraflopsBH/eventor/blob/main/docs/PROJECT_STATE.md), [Roadmap](https://github.com/TeraflopsBH/eventor/blob/main/docs/ROADMAP.md), [Gap analysis](https://github.com/TeraflopsBH/eventor/blob/main/docs/BLUEPRINT_TO_REPOSITORY_GAP_ANALYSIS_v1.0.md).
- [Authorization migration 000002](https://github.com/TeraflopsBH/eventor/blob/main/database/migrations/000002_authorization.sql), [Platform administration migration 000187](https://github.com/TeraflopsBH/eventor/blob/e69d1c9cf86e8c4e55c4ee03f7c291830383bb2c/database/migrations/000187_platform_administration_and_workspace_switching.sql), [Migrations directory](https://github.com/TeraflopsBH/eventor/tree/main/database/migrations), [Host admin scripts](https://github.com/TeraflopsBH/eventor/tree/main/scripts/admin).
- [Staff application features](https://github.com/TeraflopsBH/eventor/tree/main/apps/staff-web/src/features), [OpenAPI v0.3](https://github.com/TeraflopsBH/eventor/blob/main/docs/api/openapi.v0.3.yaml).
- [Self-hosted deployment runbook](https://github.com/TeraflopsBH/eventor/blob/main/docs/operations/SELF_HOSTED_DEPLOYMENT_RUNBOOK.md), [Systemd templates](https://github.com/TeraflopsBH/eventor/tree/main/deploy/systemd).
- [Issue #104](https://github.com/TeraflopsBH/eventor/issues/104), [#108](https://github.com/TeraflopsBH/eventor/issues/108), [#111](https://github.com/TeraflopsBH/eventor/issues/111), [TDS PR #232](https://github.com/TeraflopsBH/eventor/pull/232). #232 was open and unmerged at inspection; its issue addendum was already present. No merge or update performed in this task.

**End of proposed specification.**

<!-- END EXACT ORIGINAL PAC -->

# Part III — Full integrated specification and later approved clarifications

Pinned PAC repository edition at fd993fb2d66b93fbe81ce99c5bfb50c9ec025542, 58511 bytes, SHA-256 1285c6d9db034e8acb86e5cc7e8a0f8532aaf59ab637bad5bc8824885582c9bc. Exact source begins after marker newline.

<!-- BEGIN EXACT INTEGRATED PAC bytes=58511 sha256=1285c6d9db034e8acb86e5cc7e8a0f8532aaf59ab637bad5bc8824885582c9bc -->
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

## Approved AGIS deployment and support boundary — 2026-11-27

[AGIS v1.0](ADMISSION_GUEST_INFORMATION_AND_STATION_MANAGEMENT_DESIGN_v1.0.md) adds deployment-level station security defaults, device/session and offline-policy ceilings, health/diagnostic redaction, recovery and protected host operations. Tenant OAC manages its own devices, station profiles, permissions and configuration; EOC assigns them to events/sessions. PAC support requires explicitly scoped, expiring, audited access under the real actor, never a global guest directory or unrestricted device/host remote control. Remote lock means revoke Eventor authorization/clear connected session; disconnected devices may only learn of revocation at reconnect or lease/package expiry. Recovery must reconcile credential/device revocations, pending offline intents and uncertain print outcomes before reopening; preserve protected host recovery and both installers. No weakening of existing PAC authority constraints or new runtime access to host/OS credentials. This is an approved scope clarification, not a runtime implementation claim or instruction to interrupt the existing #104/#112 → #105–107 sequence. Preserve accepted ADRs, historical Blueprint v1.2, existing domain commands and issue criteria; final integrated acceptance remains Phase 9.

## Approved CID shared-service and recovery boundary — 2026-11-27

[CID v1.0](COMMUNICATION_INVITATION_DISTRIBUTION_AND_MULTI_CHANNEL_DELIVERY_DESIGN_v1.0.md) allows optional owner-managed communication provider profiles with explicit tenant/purpose/sender grants, quotas, budget reservations, usage and revocation; tenant-owned provider accounts remain independent. Platform service access is not tenant guest or correspondence access, delegated Superadmin authority is not unrestricted provider/secret access, and tenant administrators cannot read platform or other tenant credentials. Separate policy/configuration authority, secret write-only/rotation and cost/audit projections. Actual actor, scoped expiry, support grant and review for intervention. No arbitrary host shell, arbitrary network destination, raw callback/payload or provider account access. Emergency suspension/restore must fence jobs, reconcile uncertain external outcomes and not automatically replay already submitted messages. Both deployment modes support configurable TLS/egress/callbacks, secret backup/recovery, optional local capture/manual operation. This is an approved scope clarification, not a runtime or acceptance claim. Preserve all existing requirements, accepted ADRs, historical Blueprint v1.2, current #104/#112 → #105–107 sequence and established #110/#111/#108 roadmap; no immediate implementation or environment republication. Final integrated acceptance remains Phase 9.

## Approved coordinated governance and operations boundaries — 2026-11-27

[AES v1.0](ADAPTIVE_EXPERIENCE_AND_SETUP_DESIGN_v1.0.md), [EPW v1.0](EVENT_PLANNING_PRODUCTION_AND_OPERATIONAL_WORKFLOWS_DESIGN_v1.0.md), [FRS v1.0](FORMS_REGISTRATION_AND_SUBMISSION_STUDIO_DESIGN_v1.0.md), [HPG v1.0](HOSPITALITY_PROTOCOL_AND_GUEST_SERVICES_DESIGN_v1.0.md), [RAI v1.0](REPORTING_ANALYTICS_AND_INTELLIGENCE_STUDIO_DESIGN_v1.0.md) retain PAC authority ceilings. AES installer and setup defaults use typed policies and explicit protected host commands, never arbitrary remote execution. EPW workflow configuration cannot delegate platform rights or bypass domain approvals. FRS publication/attachment policy, HPG restricted service-data handling and RAI governed metric/report artifacts require tenant scope, bounded retention, scoped support and actual actor audit. PAC may provide safe operational health/usage metrics, never a universal guest or supplier directory. Recover jobs, encrypted artifacts, reviewed state and CID uncertain submissions without blind replay in both installers. Approved additive scope only; retain existing requirements, accepted ADRs, Blueprint v1.2, PROJECT_STATE and the #104/#112 → #105–107 → #110/#111/#108 development sequence. No immediate implementation, unrelated closure gates, environment republication or Blueprint v1.3 consolidation. Final integrated acceptance remains Phase 9.

<!-- END EXACT INTEGRATED PAC -->
