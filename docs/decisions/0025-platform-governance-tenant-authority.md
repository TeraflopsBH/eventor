# ADR 0025 — Platform governance, tenant authority and controlled support access

- Date: 2026-11-27
- Status: **Proposed for final owner review.** Least-privilege direction agreed; concrete permission inventory and migration not approved or implemented.
- Resolves OD-01 in [consistency reconciliation](../blueprint/v1.3/DESIGN_CONSISTENCY_RECONCILIATION_v1.0.md).
- On acceptance supersedes only the blanket managed grant rule in [ADR 0015](0015-email-first-login-and-platform-administration.md), retaining credential-first authentication, host-only designation, selected-tenant RLS, actual actor, workspace rotation and independent grant provenance. ADRs 0010, 0017, 0020, 0023 and 0024 remain unchanged.
- Implementation gate PAC M0/M1, current roadmap; no new track.

## Context and decision

Migration 000187 reconciles managed platform administrator roles with all non-platform permissions. Tenant RLS does not itself establish whether an operator needs confidential data. Actual downstream effective access requires inventory and negative testing, not an inference of exploited leakage. Adopt a positive reviewed allowlist, independent tenant business roles and explicitly approved scoped support. Unknown and new permission codes default excluded. No mandatory multi-person staffing or external identity provider.

| Authority source | Permitted by explicit role/scope | Never implied |
|---|---|---|
| Host custodian | Protected local installation, designation, recovery, upgrade and backup execution | Routine business impersonation, HTTP shell |
| Named platform owner | Governance, provisioning, approved platform policy and delegation | Tenant business/secret access, automatic ownership from legacy flag |
| Delegated Superadmin/security/operations/auditor | Exact delegated capability, organization scope, grant ceiling, expiry; auditor read-only | Self-promotion, owner transfer, unrestricted diagnostics/backup contents |
| Independent organization member | Ordinary tenant role, field/action grants | Platform or host authority |
| Temporary support | Reviewed case, purpose, exact resource/action/field, approving data authority, expiry/revoke | Wildcard confidential access, self-approval, standing rights |
| Emergency recovery | Limited technical containment/recovery with strong step-up, actual actor, protected receipt, after-action review | Ownership promotion, unrestricted data access, audit edits or integrity bypass |
| Service principal | Typed owning job and exact scope | Human administrator token or arbitrary SQL |

One person may hold separate roles, but context and grant sources are explicit. PAC alone cannot authorize tenant business commands; ordinary tenant authority cannot invoke PAC. Host execution is not an application permission. Validate current effective grant, lifecycle, field and domain rules at every relevant boundary. No role authority through display names, client organization ID, booking links or case IDs.

## Managed grants and governance

Version exact positive allowlist entries with code, permitted scope/purpose, direct/indirect risk, owner and tests. Default baseline safe coarse health/readiness through dedicated redacted control-plane projections; an empty managed tenant allowlist is valid if these suffice. No specific existing tenant permission presumed safe without audit. Exclude guest/contacts/notes, commercial terms, restricted prerequisite files, business CRUD/approval, admission, exports, real data templates, sends, role editing, secret recovery, arbitrary retry and collaboration grant changes by default, including equivalent indirect paths. Independent ordinary grants preserved. Sensitivity labels alone are insufficient. Classify every new code and test exclusion from managed roles. Enforce delegation ceiling across role/preset/import/restore, secondary accounts, service/job/report/export paths; no self-grant, policy weakening for pending action or proxy escalation.

Explicit host-designated named owner; no first-signup/domain inference or migration converting all legacy flags into owners. Owner transfer uses host-authorized proposal, verified successor identity and MFA, acceptance, local protected confirmation, atomic authority replacement/revocation, session review, last-owner protection and immutable receipt. No universal backdoor. Keep ADR 0017/0020 distinct, no password reset/upsert or fake verification. Host recovery available when app unavailable.

Support request → scope/impact review → approved bounded grant → active use → revoke/expire/close → after-action review. Approval pins exact actor, approver, case, purpose, scope, fields/actions, policy revision, expiry and digest. Current lawful/data-owner authority required for sensitive access, no ownership-as-consent. Recheck authority before lookup, under mutation lock, on job/download/stream/replay. Strong MFA/step-up; provisional 5-minute recent-auth, 60-minute support default, 30-minute emergency maximum subject to M0. No automatic renewal. Display actual actor/case/expiry; protected redacted read/change/export/denial audit; tenant notice per approved policy, justified incident delay only. Single-owner deliberate local host confirmation supports limited technical recovery and owner transfer, not unrestricted confidential self-approval. Where lawful data authorization unavailable, contain/recover without content access.

## Session and service boundary

Preserve email-first proof before workspace disclosure, Argon2id, rate limits, opaque Secure HttpOnly cookies, CSRF/origin, original expiry and target-before-session lock order. Explicit separate PAC context and platform-only sign-in after reviewed implementation; no magic tenant. Transition to ordinary or scoped support context rotates credentials, clears cache/streams, preserves expiry and recent-auth time; switch does not refresh authentication. Narrow service/auth/runtime functions, pinned search_path, explicit EXECUTE, FORCE RLS; real host identity separate. Revocation ordered against concurrent command; committed fact remains history. No generic SQL/shell/file/URL access, Docker socket or owner DB credentials through application.

## Implementation and migration gate

1. M0 inspect migration 000187 and successors, live catalogue, managed grant lineage/prior status, ordinary independent grants, host tools, lock order and all direct/indirect downstream effects. Produce per-code/current-scope/owner/risk/disposition/test/affected-membership inventory and dry-run impact digest, no confidential content. Distinguish observed exposure from potential.
2. Review exact allowlist, owner designation, support and separate context model, compatible forward migration and recovery plan. Confirm material affected access decisions with owner; do not invent ordinary grants as compensation. Test last admin/owner and host recovery.
3. M1 additive transactional migration, stable canonical locks, replace only tracked managed grants, preserve IDs, independent grants and historical provenance. Unknown codes excluded, incompatible lineage blocks rather than silently deleting. Fence/revoke affected sessions, jobs, streams/downloads, recheck pending approvals and require fresh authorized context; completed audit retained.
4. Validate old/new compatibility and populated upgrade before activation. No fallback to broad inheritance on error. Backups and isolated recovery, safe forward repair; rollback may not silently restore broad rights. Current ADR 0015 behavior stays in force until accepted successor implementation activated, not merely merged documentation. No privilege expansion for unrelated development.
5. Negative matrix: two tenants/provider-only and organizer, platform-only, dual-role, ordinary admin, support and revoked roles; API/DB/UI/export/report/template/job/stream/callback/cached replay, proxy grant attempts, new code excluded, unrelated rights preserved. MFA/recovery, last owner/admin, host bootstrap, concurrent revoke/commands, audit rollback, restore old grants/uncertain work. Fresh/populated migrations and existing auth/booking/Registry/RSVP/collaboration regression, all PAC-AC-01–40 and OLA gates. Exact-head/post-merge CI and final native/Compose Phase 9.

## Alternatives and consequences

Blanket inheritance retains compatibility but conflicts with least privilege. Sensitivity-only is insufficient; separate application/database per tenant is unnecessary. Positive allowlist plus separate authority gives explicit, testable boundaries at cost of inventory, migration and granular checks. No concrete allowlist, scope change or runtime permission change approved by this draft; owner review and implementation evidence still required.

## Subsequent review note — 2026-11-27

The [clause disposition and authority review](../blueprint/v1.3/TDS_PAC_CLAUSE_DISPOSITIONS_v1.0.md) now proposes explicit R1–R9 interpretations, cumulative original and integrated clause authority, and exhaustive source-line/range coverage. The review note does not certify sentence-by-sentence equivalence. Both full source editions and paired acceptance conditions remain intact; proposed technical choices retain their qualifications. Final owner decision on the proposed interpretations and ADR wording remains required; no current implementation, grant or roadmap change.
