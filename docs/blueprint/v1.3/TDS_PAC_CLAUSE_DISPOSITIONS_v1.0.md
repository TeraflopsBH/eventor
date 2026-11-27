# TDS/PAC v1.1 — Approved clause dispositions and authority resolution

> **Owner-approved design resolution — 2026-11-27 (PR #239):** [ADR 0025](../../decisions/0025-platform-governance-tenant-authority.md) is accepted as the future authority architecture; the nine interpretations R1–R9 and cumulative disposition matrices in this document and the source-complete [TDS v1.1](../../implementation-design/v0.3/TEMPLATE_DESIGN_STUDIO_DESIGN_v1.1.md) / [PAC v1.1](../../implementation-design/v0.3/PLATFORM_ADMINISTRATION_CENTER_DESIGN_v1.1.md) contract are approved. OD-01 is resolved at design-direction level; OD-02 is resolved by cumulative retention and explicit interpretations, not a formal sentence-level equivalence proof. This approval supersedes earlier pending/proposed approval wording for these decisions only. Exact permission allowlist, implementation/migration activation, affected-access inventory, owner/approval policy, recovery and M0 technical choices remain separately reviewed. ADR 0015 continues to govern current implemented behavior until the reviewed successor is safely activated; do not expand legacy grants. No change to runtime, other outstanding decisions, source bytes, acceptance results or existing #104/#112 → #105–107 → #110/#111/#108 priorities; final integrated acceptance remains Phase 9.

**Status: owner-approved design clarification, 2026-11-27.** R1–R9 and the cumulative-preservation disposition matrices are accepted. No runtime testing or authorization to migrate grants is implied. Date 2026-11-27. PR #239. Read with [ADR 0025](../../decisions/0025-platform-governance-tenant-authority.md), [TDS v1.1](../../implementation-design/v0.3/TEMPLATE_DESIGN_STUDIO_DESIGN_v1.1.md), [PAC v1.1](../../implementation-design/v0.3/PLATFORM_ADMINISTRATION_CENTER_DESIGN_v1.1.md), [original bidirectional crosswalk](TDS_PAC_SOURCE_RECONCILIATION_v1.0.md), [consistency ledger](DESIGN_CONSISTENCY_RECONCILIATION_v1.0.md) and [engineering registers](ENGINEERING_REGISTERS_v1.0.md).

## Authority and adjudication method

The approved contract is the **conjunction of the exact original and integrated clauses** in the two v1.1 files, with only the explicit precedence interpretations below. No non-identical sentence is treated as equivalent or removed merely because of similarity. A condensed paragraph cannot discharge a more detailed original condition. Both complete editions remain embedded and individually addressable; all acceptance evidence conditions are cumulative. Exact identical text need not be duplicated in implementation; source trace remains. Historical statuses/baselines/integration requests are provenance, illustrative names/examples are not final contracts, and expressly provisional limits remain M0 proposals. Accepted ADRs and deployed domain guards remain authoritative for current behavior until a reviewed change is activated. A later approved addendum refines its own scope, not unrelated requirements. If an unlisted genuinely incompatible clause is discovered, stop only the affected implementation, record exact sources and seek decision; do not silently choose one.

The following disposition matrix records the substantive review by bounded source ranges. An exhaustive line-addressable coverage index follows. This is a conservative cumulative adjudication, not a claim that every nonidentical sentence has been proven semantically equivalent. Range classifications apply to all clauses in that range, with examples/statuses/qualified language retaining their qualifications. Original appendix and later integrated addenda are separate, not claimed to be counterpart paragraphs.

## Specific approved interpretations

| ID | Decision | Consequence / test |
|---|---|---|
| R1 | TDS source refers to RSVP and admission QR types; later approved AGIS adds separate permitted portal/info credential and station outputs. Typed catalogue supports only explicitly approved purpose slots; no generic token variable or automatic issuance. Preview (even real-recipient preview) is non-live. Opening already issued permitted artifact is an independent owning-domain retrieval; output refresh, render, reprint, handover and replacement are distinct. Seat/brand change requires explicit reviewed output update, not automatically replacing a valid credential. | TDS AC-07/10/24 plus AGIS/DC-03/04; deny swapped/revoked credentials, final-size decode, test no attendance on preview or print, no stale output silently updated. |
| R2 | Revocation/quarantine blocks new use of asset/component and prohibited redistribution. Retained historical bytes/manifest are immutable and can be held for lawful audit; ordinary new output or reissue cannot bypass current asset, grant or credential authority. Previously distributed physical or external bytes cannot be recalled by software. | TDS AC-08/13/19/24, PAC AC-15/20; revoke dependency, inspect permitted historic audit, deny new render/redistribution, legal hold does not confer read access. |
| R3 | Reproducibility means exact retained permitted artifact/payload/digest and pinned manifest where lawful, not guaranteed byte-identical rerender or recreation of purged content. Independently authorize generation, download, sharing and distribution using current scope; expiring link is not standalone bearer permission. Retention/hold controls deletion not data access. | TDS AC-13/17/19/22, PAC AC-19/20/26, RAI/DC-08/10; exercise purge, restore, grant revocation during run/download, historical evidence retained only as authorized. |
| R4 | Resolve brand per property event → permitted venue → organization → platform with explicit override/removal and mandatory notices; personal theme separate. No rewriting published artifacts or automatic credential replacement. Missing required legal/commercial translation blocks issue unless explicitly selected approved alternative under existing policy; no silent fallback or machine translation. | TDS AC-11/12/24 and PAC AC-14/15/16; test cross-owner brand denial, legal fallback policy and pinned snapshots. |
| R5 | Distinguish identical internal command receipt replay, render retry, external submission and delivery reconciliation. CID/DC-05 permits identical externally idempotent replay only with actual documented provider guarantee, identical payload and valid original key under current authority. No blind retry, fresh-key duplicate or automatic fallback while uncertain; otherwise reconcile. | TDS AC-14/15, PAC AC-21–24/27 and CID uncertainty evidence; verify leases, known/uncertain results and restore. |
| R6 | Required product-supported provider/channel adapter evidence under CID and release matrix is not mandatory tenant activation. Local capture/manual path/no internet remains supported. A configured deployment's HTTPS/SMTP acceptance probe skipped or unavailable is not a pass; actual supported provider evidence still required before advertising support. Optional Telegram only if implemented/advertised. Numeric TDS/PAC envelopes stay provisional, original detailed inputs retained, actual measurement required. | TDS AC-21/22/23/25, PAC AC-37–40, OLA/DC-07; record actual provider/device/installer/measurement evidence with explicit applicability, no early VM. |
| R7 | Apply the accepted future design architecture of ADR 0025: positive reviewed managed allowlist (unknown/new codes excluded), separate explicit independent tenant roles, narrow control-plane projections, scoped expiring support. No permission code deemed safe in advance. Current ADR 0015 authentication/workspace and managed behavior preserved until separately approved migration activated at PAC M0/M1. Owner can hold explicit tenant business role without using PAC authority. | PAC AC-01–12/31–35/38; per-code/direct/indirect permission inventory, ordinary grant provenance, affected access report and recovery, populated upgrade and revocation race before cutover. No present-day permission change. |
| R8 | One designated named owner is proposed initial arrangement, not a shared account; explicit multi-owner policy would require separate reviewed decision. Where independent review is unavailable, protected local host confirmation is permitted only for documented technical recovery, owner transfer or delegated admin grant within approved governance ceiling, never a generic self-approved tenant data elevation. No data-authority approval means containment/recovery without content. Emergency cannot transfer ownership, edit audit, disclose keys or extend own privileges. First supported web host-action UI is request/status plus protected CLI; optional constrained executor separate ADR. | PAC AC-01/02/05/06/28/31–35/39; tests for last owner, recovery, local host receipt, no self-promotion, expired support and real actor. Actual lawful authority, approval thresholds, named owner and expiry policy to be reviewed at M0; no fictitious approval. |
| R9 | Global staff account directory and safe control-plane aggregates are explicit bounded projections, not tenant Registry access. Account identity/verification/membership metadata only with per-field/scope authorization; no tenant existence before proof or unrestricted drill-down. Health metrics never imply business authority; PAC-only session cannot invoke tenant command; protected host technical power is outside application business grants. | PAC AC-04/05/07/12/13/16/23/34; tenant/partner negative tests, public bootstrap and redaction, scope and small-cell controls; no assertion of tamper-proof host security. |

## Remaining implementation decisions (not product scope omissions)

M0 must still review actual permissions and downstream behavior, determine the exact approved allowlist and affected user access, owner/approval policy and recovery, MFA/ingress and retention/holds, brand/legal policies, adapter evidence, library choices, exact schemas/API and measured limits. No material new implementation or permission change is authorized by a documentation merge. TDS-AC-01–25 and PAC-AC-01–40 remain required and not yet executed. Existing implementation sequence #104/#112 → #105–107 → #110/#111/#108; Phase 9 final acceptance. A verified independently reproduced security defect follows ordinary security policy, not a speculative rewrite.

## Source disposition matrices

Notation: O = original review edition source line, I = integrated v1.0 edition at the Blueprint source revision. UNION = retain both full clause conditions, not assert identity; PROPOSAL = explicit engineering choice remains proposed; PROVENANCE/BASELINE = historical references/status, no new runtime claim; AC = retain all paired evidence; Rn = specific interpretive rule above. Mixed labels preserve the qualifications of individual clauses. For line-level lookup use the immutable source annexes in the linked v1.1 files and prior crosswalk.

### TDS

| Disposition | Original lines | Integrated lines | Treatment | Detailed carry-forward |
|---|---|---|---|---|
| TDS-D01 | 1–15 | 1–7 | PROVENANCE | Approval, historical audit and change-control wording; proposed status is not new authority; retain as evidence. |
| TDS-D02 | 16–35 | 8–25 | UNION | All three editors, purpose/output catalogue and named correspondence/print/report/signage cases; retain bounded optional PNG and page-flow letter output. Later CID and AGIS broaden typed outputs only through owning domains; no generic form or reporting engine. |
| TDS-D03 | 36–57 | 26–42 | BASELINE | Keep source references and identified legacy notification aggregates, campaign review and text worker. Inspection is not runtime acceptance; repeat actual inventory at M0. |
| TDS-D04 | 58–76 | 43–48 | UNION | Retain every listed permission family and boundary, including real-recipient preview/export as separate data authority, no parent brand edit by event manager, explicit cross-owner reference/copy and scope-before-lookup. |
| TDS-D05 | 77–82 | 49–52 | UNION | Retain lifecycle, author/reviewer separation according to policy, digest invalidation, optimistic concurrency, explicit discard and restore-as-draft. Unsafe asset revocation prevents new use; no automatic recall. Real-time collaboration not initial requirement. |
| TDS-D06 | 83–88 | 53–58 | UNION | Retain every library filter, mode selection, dependency/usage/history/review detail, accessible navigation and independent staff/document locale; AES adds progressive disclosure. |
| TDS-D07 | 89–96 | 59–64 | UNION | Keep all listed WYSIWYG formatting controls, plain text edit and explicit regenerate/compare, office paste loss notice, subject/preheader single-line and CR/LF denial. Sanitized HTML import/edit is an approved bounded authoring capability; not raw executable source; clone for conversion. Preserve explicit test of long/empty/multiline Unicode values. |
| TDS-D08 | 97–103 | 65–71 | UNION | All listed block types, align and reorder, keyboard alternatives, responsive width/stack, image-blocked fallback, actual MIME multipart via eligible provider; image hosting optional, private data never fetched through URLs. No client parity promise. |
| TDS-D09 | 104–111 | 72–79 | UNION+R1 | All physical size, trim/bleed/safe margins, exact coordinates, front/back, layers, locks, numeric editing, QR ECC/minimum/quiet zone/final decode, text overflow and multi-up order/fit requirements retained. R1 governs credential purpose and rendering. |
| TDS-D10 | 112–115 | 80–83 | UNION+R2 | Retain all neutral starters, component import/export/remapping, versioned dependencies/cycles, tenant-specific content hashes, license/embedding rights, asset picker metadata. R2 clarifies retention and revocation. |
| TDS-D11 | 116–134 | 84–99 | UNION+R1 | Typed variable catalogue, exact context/type/permission, required missing and forbidden distinct, no presence oracle, bounded conditions/lists, URL/QR slots. Preserve example field types as illustrative; approved later AGIS/CID catalogue extensions not arbitrary bindings. |
| TDS-D12 | 135–136 | 100–101 | UNION+R1+R3 | Keep synthetic watermark, authorized audited real data preview with nonlive placeholders, authorized retrieval of issued artifact separate; digest binds selected audience and source revisions; no rendering command issues credentials. R3 preserves retention and current permission. |
| TDS-D13 | 137–142 | 102–107 | UNION+R4 | Preserve all original brand properties, override/removal, mandatory footer and language/formatting rules, explicit translated layout and RTL data extensibility without premature RTL support promise. R4 distinguishes published approved fallback from silent translation. |
| TDS-D14 | 143–156 | 108–111 | UNION | Architecture examples remain illustrative; mandatory no general network/DB credentials in renderer, narrow orchestration, same isolation both installers, no duplicated engine. |
| TDS-D15 | 157–180 | 112–117 | UNION+PROPOSAL | Versioned canonical envelope, legacy text adapter, validated transformations create new draft, short-lived quarantine, stable IDs, exact coordinates and rounding tests. Preserve complete illustrative JSON and QR examples as examples only. |
| TDS-D16 | 181–184 | 118–119 | UNION+PROPOSAL | Retain all M0 library/spike criteria, dependency audit, pinned lockfiles, no mandatory subscription and sandbox never disabled. Actual library decision open. |
| TDS-D17 | 185–190 | 120–125 | UNION+R2+R3 | All manifest fields, exact permitted retained artifact or canonical payload, QR/print DPI and page boxes, actual print evidence, no claim tagged PDF/PDF-UA without verification. R2 and R3 govern revoked dependency, retention, key policy and current access. |
| TDS-D18 | 191–194 | 126–129 | UNION+R5 | Separate render/delivery queues, fingerprint and scope, progress, dead-letter, verified synthetic TEST destination, audience/digest, recheck eligibility, no silent legacy fallback. R5 exact-replay exception only under CID. |
| TDS-D19 | 195–217 | 130–150 | UNION+PROPOSAL | All named logical entities, fields, composite FKs, uniqueness, state/digest, actor and deletion invariants and seven-stage migration preserved; names not executable DDL. No second email aggregate; legacy readers and queued behavior preserved. |
| TDS-D20 | 218–248 | 151–171 | UNION+PROPOSAL+R3 | Every original method/family, proposed inputs, response shapes, 202/409/validation and current-download/no-store rules preserved; grouped endpoint rows not deletion. Exact routes/codes reconcile at M0. R3 controls export/access. |
| TDS-D21 | 249–270 | 172–191 | UNION+R3 | All listed attack vectors/negative controls, CSP and sandbox, public asset and link constraints, real manual keyboard/assistive review, WCAG 2.2 AA target and limited output claims retained. |
| TDS-D22 | 271–287 | 192–197 | UNION+PROPOSAL+R6 | Full numerical envelopes, lower configurable budgets, per-tenant/global isolation, artifact expiry/hold, both-mode fonts/renderer and DB/assets/key restore, queue metrics and attribution. M0 validates provisional inputs; R6 product support vs deployment activation. |
| TDS-D23 | 288–305 | 198–213 | UNION+PROVENANCE | M0–M6 complete scope and dependencies; retain all original #111 gates, independent synthetic design before QR, real outputs wait owning domain, no automatic scheduling/early VM. Current roadmap controls. |
| TDS-D24 | 306–337 | 214–245 | AC+R1+R2+R3+R4+R5+R6 | All 25 paired criteria are conjunctions, not substitutions. AC-03 save/headings, AC-05 actual margins and overflow, AC-07 gated live admission, AC-10 nonlive preview, AC-12 legal fallback, AC-13 retained digest, AC-15 partial cancel/uncertainty, AC-22 real provider evidence, AC-24 explicit output refresh/replacement distinction; preserve every other original and integrated check. |
| TDS-D25 | 338–345 | 246–247 | AC+R1+R3 | Complete owner scenario retained with real approved domain actions, preview isolation, rebrand, revoked access and booking-only proof. Synthetic preview does not require actual admission. |
| TDS-D26 | 346–349 | 248–251 | PROPOSAL | Keep original recommended defaults and all open product/technical choices; later owner-approved addenda govern already resolved cross-module scope; no actual GHB policy/assets assumed. |
| TDS-D27 | 350–369 | 252–272 | PROVENANCE+UNION+R1+R5+R6 | Original integration proposal is historical; current approved additive OAC/UX, AGIS, CID and coordinated AES/EPW/FRS/HPG/RAI paragraphs remain normative. Scope unchanged; TDS appearance vs schema/query/station/delivery/approval/service authority distinct. |

### TDS individual nonblank line coverage

All listed line numbers are mapped to the disposition above; exact textual identity where present does not alter the source qualifications. The numbers include headings, table delimiters and code examples, which are not new requirements. This generated index verifies complete coverage, not an automatic semantic equivalence determination.

| Disposition | Original nonblank lines | Integrated nonblank lines |
|---|---|---|
| TDS-D01 | 1, 2, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14 | 1, 3, 4, 5, 6 |
| TDS-D02 | 16, 18, 20, 22, 24, 25, 26, 27, 28, 29, 30, 31, 32, 34 | 8, 10, 12, 14, 15, 16, 17, 18, 19, 20, 21, 22, 24 |
| TDS-D03 | 36, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 52, 54, 56 | 26, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 39, 41 |
| TDS-D04 | 58, 60, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 75 | 43, 45, 47 |
| TDS-D05 | 77, 79, 81 | 49, 51 |
| TDS-D06 | 83, 85, 87 | 53, 55, 57 |
| TDS-D07 | 89, 91, 92, 93, 94, 95 | 59, 61, 62, 63 |
| TDS-D08 | 97, 99, 100, 101, 102 | 65, 67, 68, 69, 70 |
| TDS-D09 | 104, 106, 107, 108, 109, 110 | 72, 74, 75, 76, 77, 78 |
| TDS-D10 | 112, 114 | 80, 82 |
| TDS-D11 | 116, 118, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 133 | 84, 86, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98 |
| TDS-D12 | 135 | 100 |
| TDS-D13 | 137, 139, 141 | 102, 104, 106 |
| TDS-D14 | 143, 145, 146, 147, 148, 149, 150, 151, 152, 153, 155 | 108, 110 |
| TDS-D15 | 157, 159, 161, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176, 177, 179 | 112, 114, 116 |
| TDS-D16 | 181, 183 | 118 |
| TDS-D17 | 185, 187, 189 | 120, 122, 124 |
| TDS-D18 | 191, 193 | 126, 128 |
| TDS-D19 | 195, 197, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 214, 216 | 130, 132, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 149 |
| TDS-D20 | 218, 220, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244, 245, 247 | 151, 153, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 170 |
| TDS-D21 | 249, 251, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 267, 269 | 172, 174, 175, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 188, 190 |
| TDS-D22 | 271, 273, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 286 | 192, 194, 196 |
| TDS-D23 | 288, 290, 292, 293, 294, 295, 296, 297, 298, 299, 300, 302, 304 | 198, 200, 201, 202, 203, 204, 205, 206, 207, 208, 210, 212 |
| TDS-D24 | 306, 308, 310, 311, 312, 313, 314, 315, 316, 317, 318, 319, 320, 321, 322, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336 | 214, 216, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 243, 244 |
| TDS-D25 | 338, 340, 341, 342, 343, 344 | 246 |
| TDS-D26 | 346, 348 | 248, 250 |
| TDS-D27 | 350, 352, 354, 355, 356, 357, 358, 360, 362, 363, 364, 365, 366, 367 | 252, 254, 256, 258, 260, 262, 264, 266, 268, 270 |

### PAC

| Disposition | Original lines | Integrated lines | Treatment | Detailed carry-forward |
|---|---|---|---|---|
| PAC-D01 | 1–13 | 1–8 | PROVENANCE | Historical approval status and static audit baseline; not current engineering authorization. |
| PAC-D02 | 14–31 | 9–14 | UNION | Retain complete governance/operations scope, distinct PAC/OAC/EOC and protected host role, no unrestricted content/SQL or duplicate business engines. No mandatory external services. |
| PAC-D03 | 32–65 | 15–31 | BASELINE | Keep original source trace and actual baseline limitations; no claim PAC implemented. Re-audit current main and real privileges M0. |
| PAC-D04 | 66–73 | 32–35 | R7 | OD-01 accepted future design only. Current ADR 0015 remains implemented until the separately reviewed migration is activated; no inferred exploit or new grant. |
| PAC-D05 | 74–108 | 36–47 | UNION+R7+R8 | Retain original full role-operation matrix, including security incident hold and operations request vs host execution. Each cell still requires exact permission; host technical capability is not business authority. R8 constrains emergency and single-owner exception. |
| PAC-D06 | 109–120 | 48–51 | UNION+PROPOSAL+R7+R8 | Preserve owner setup, no first registration/legacy flag promotion, separate real identity, atomic verified transfer, offline recovery, grant ceiling and all original illustrative platform permission families. Single owner vs approved alternative remains decision, not shared credential. |
| PAC-D07 | 121–128 | 52–57 | UNION+PROPOSAL+R7 | Retain MFA/passkeys/TOTP evaluation, hashed one-time recovery, private ingress preference, independent same-host context, origin/CSRF, original expiry, recent-auth no refresh, stale cache and revoke ordering. PAC-only session future; no mandatory IdP. |
| PAC-D08 | 129–138 | 58–61 | UNION+R7 | Retain every directory field where allowed, wizard inputs and onboarding separate, atomic bootstrap, lifecycle/state enum audit, critical check-in impact, customer status retention and independent provider. No implicit ownership transfer. |
| PAC-D09 | 139–144 | 62–63 | UNION | Retain staff identity distinction, case-insensitive reuse, mailbox verification, separate reset token/session revocation, old/new verified notices as appropriate, no plaintext credentials/upsert, no guest merge. |
| PAC-D10 | 145–148 | 64–65 | UNION+R7 | Retain effective grant provenance, prior membership state, role presets, system role guard, ADR 0020 provisioning vs correction and independent ordinary memberships. |
| PAC-D11 | 149–173 | 66–86 | UNION+R9 | Retain every navigation area and actual permitted safe metric, source/time/window/freshness, bounded filters/exports, small cohort protection and no raw tenant content. R9 distinguishes authorized staff directory from tenant data. |
| PAC-D12 | 174–195 | 87–92 | UNION+R4+R9 | Retain all editable original brand fields, login public routing only if explicitly approved, no email-based discovery, contrast/fallback/attribution and per-property ownership. R4 and R9 govern inherited output and public projection. |
| PAC-D13 | 196–201 | 93–98 | UNION | Typed catalogue, validator/impact classification, versioned publish, restart status, scope and safety floor, no environment writer. Preserve module DAG, readiness, active dependency impact/drain and history; config cannot install features. |
| PAC-D14 | 202–207 | 99–102 | UNION+R3 | Retain requester verification, approval/denial, owner notification per policy, resumable bounded bulk with per-item receipts, hold/purge locks, legal policy, restored-state reconciliation. R3 protects artifact access/retention; no universal backup deletion promise. |
| PAC-D15 | 208–211 | 103–106 | UNION+R5+R6 | Retain all sender/envelope/TLS/capability/credential and status controls, explicit localized approved platform audience, no guest broadcast. Later CID extends channels; exact replay only per R5; actual product evidence R6. |
| PAC-D16 | 212–217 | 107–110 | UNION | Retain original full measured signal/metric list including pool, DB size, worker leases, WAL age and restore duration, redacted bounded diagnostics, bundle expiry, alert acknowledge/assign/resolve and local alerting. Optional failure not global outage; no inferred uptime. |
| PAC-D17 | 218–225 | 111–114 | UNION+R3+R5+R8 | Retain encrypted independent destination, coordinated DB/assets/key backup, cadence/checksum/WAL gaps, decryptability without values, backup vs restore evidence, isolated rehearsal, pre-restore backup where safe, exact cutover reconciliation and independent receipt. No unsupported raw tenant restore. |
| PAC-D18 | 226–235 | 115–118 | UNION+PROPOSAL+R8 | Retain host CLI as required, first release request/status + protected local execution sufficient, optional executor requires new ADR and typed caller/replay/least-privilege controls. Secret status only, key compatibility, full maintenance phases and explicit reopen, trusted offline release, no auto-update/down migration. |
| PAC-D19 | 236–267 | 119–138 | UNION+R7+R8 | All intervention levels, case fields, owner approval and notices, revoke and after-action review, all named domain correction examples. R8 narrows technical recovery only; no self-approved sensitive access or ownership changes through emergency. |
| PAC-D20 | 268–289 | 139–144 | UNION+R7+R9 | Full trust boundary and actual actor/audit fields, redacted denied/sensitive read/export evidence, protected receipt, atomic mutation, fail-closed sensitive read, scoped audit export; no blanket BYPASSRLS or host impersonation. Host technical trust limitation explicit. |
| PAC-D21 | 290–316 | 145–171 | UNION+PROPOSAL | Retain every original entity, typed scope/field/constraint, current IDs, owner/ceiling/hold/audit/maintenance invariants. Names illustrative and actual schema reviewed M0. |
| PAC-D22 | 317–375 | 172–204 | UNION+PROPOSAL+R7+R9 | Retain every original read and command route family and its exact preconditions/result, grouped integrated operations are not omitted scope. Separate public enrollment/bootstrap, protected host receipt, actual actor and approval; exact API names pending. |
| PAC-D23 | 376–391 | 205–206 | UNION+PROPOSAL | Retain illustrative request only, canonical IDs/fingerprint, revision, policy/expiry, current-authorized receipt replay, safe problem details incl non-enumeration, bounded reason and typed arguments. |
| PAC-D24 | 392–417 | 207–225 | UNION+R7+R8 | Keep every original threat and negative combination, host root trust limitation, no generic privileged data access, audit M0 and ordinary verified vulnerability remediation separately from feature priority. |
| PAC-D25 | 418–423 | 226–229 | UNION | Retain original WCAG target/manual checks, localized stable codes, explicit confirmation names effect, no default auto-confirm, safe error draft, CLI fallback, no machine-generated legal translations, performance isolation. |
| PAC-D26 | 424–441 | 230–233 | UNION+PROPOSAL+R6+R8 | All original provisional quantitative targets including first-50 directory and health freshness, daily backup and candidate recovery objectives, duration/recent auth, reference host; M0 review not achieved SLO. Actual native/Compose, optional configured network probes distinct from release adapter evidence. |
| PAC-D27 | 442–466 | 234–254 | UNION+R7+R8 | Retain detailed six-stage safe migration sequencing and M0–M6; establish compatible metadata, explicit owner/MFA/recovery before cutover, no broad fallback, stable grants/IDs, host script compatibility; existing work priorities retained. |
| PAC-D28 | 467–513 | 255–301 | AC+R3+R5+R6+R7+R8+R9 | All 40 paired acceptance criteria apply, including original explicit actual status, safe recovery succeeds on disposable target, owner-approved grant and history, redaction, no inferred verification, native/Compose, actual metrics and prior issue gates. |
| PAC-D29 | 514–517 | 302–303 | AC+R7+R8 | Full representative two-tenant owner workflow including actual actor, independent role/support/revoke, rebrand, booking-only, backup and isolated recovery, host-confirmed upgrade and single-owner lockout. No test credited. |
| PAC-D30 | 518–532 | 304–309 | PROPOSAL+PROVENANCE | Retain eight open decision groups and original integration proposal as historical. M0 approves actual allowlist, owner governance, MFA, ingress, privacy/retention, host executor/trusted release, policies and measured budgets. No scope or priority change. |
| PAC-D31 | 533–549 | 310–326 | PROVENANCE+UNION | Preserve original repository references as historical provenance; all later approved OAC/UX/OLA, AGIS, CID and coordinated scope clarifications retain cumulative authority. No downgrade of offline reconciliation, provider/shared service isolation or permission boundaries. |

### PAC individual nonblank line coverage

All listed line numbers are mapped to the disposition above; exact textual identity where present does not alter the source qualifications. The numbers include headings, table delimiters and code examples, which are not new requirements. This generated index verifies complete coverage, not an automatic semantic equivalence determination.

| Disposition | Original nonblank lines | Integrated nonblank lines |
|---|---|---|
| PAC-D01 | 1, 2, 4, 5, 6, 7, 8, 9, 10, 12 | 1, 2, 4, 5, 6, 7 |
| PAC-D02 | 14, 16, 18, 20, 22, 24, 25, 26, 27, 28, 30 | 9, 11, 13 |
| PAC-D03 | 32, 34, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 53, 55, 56, 57, 58, 59, 60, 61, 62, 64 | 15, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 30 |
| PAC-D04 | 66, 68, 70, 72 | 32, 34 |
| PAC-D05 | 74, 76, 78, 79, 80, 81, 82, 83, 84, 85, 86, 88, 90, 92, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 107 | 36, 38, 39, 40, 41, 42, 43, 44, 45, 46 |
| PAC-D06 | 109, 111, 113, 115, 117, 119 | 48, 50 |
| PAC-D07 | 121, 123, 124, 125, 126, 127 | 52, 54, 56 |
| PAC-D08 | 129, 131, 133, 135, 137 | 58, 60 |
| PAC-D09 | 139, 141, 143 | 62 |
| PAC-D10 | 145, 147 | 64 |
| PAC-D11 | 149, 151, 153, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 170, 172 | 66, 68, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 85 |
| PAC-D12 | 174, 176, 178, 180, 181, 182, 183, 184, 185, 186, 187, 188, 190, 192, 194 | 87, 89, 91 |
| PAC-D13 | 196, 198, 200 | 93, 95, 97 |
| PAC-D14 | 202, 204, 206 | 99, 101 |
| PAC-D15 | 208, 210 | 103, 105 |
| PAC-D16 | 212, 214, 216 | 107, 109 |
| PAC-D17 | 218, 220, 222, 224 | 111, 113 |
| PAC-D18 | 226, 228, 230, 232, 234 | 115, 117 |
| PAC-D19 | 236, 238, 240, 241, 242, 244, 246, 248, 250, 252, 253, 254, 255, 256, 257, 258, 259, 260, 261, 262, 263, 264, 266 | 119, 121, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 137 |
| PAC-D20 | 268, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 284, 286, 288 | 139, 141, 143 |
| PAC-D21 | 290, 292, 294, 295, 296, 297, 298, 299, 300, 301, 302, 303, 304, 305, 306, 307, 308, 309, 310, 311, 312, 313, 315 | 145, 147, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 170 |
| PAC-D22 | 317, 319, 321, 323, 324, 325, 326, 327, 328, 329, 330, 331, 332, 333, 334, 335, 336, 337, 338, 339, 340, 341, 343, 345, 347, 348, 349, 350, 351, 352, 353, 354, 355, 356, 357, 358, 359, 360, 361, 362, 363, 364, 365, 366, 367, 368, 369, 370, 371, 372, 374 | 172, 174, 176, 177, 178, 179, 180, 181, 182, 183, 184, 185, 187, 189, 190, 191, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203 |
| PAC-D23 | 376, 378, 380, 381, 382, 383, 384, 385, 386, 387, 388, 390 | 205 |
| PAC-D24 | 392, 394, 396, 397, 398, 399, 400, 401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412, 413, 414, 416 | 207, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 224 |
| PAC-D25 | 418, 420, 422 | 226, 228 |
| PAC-D26 | 424, 426, 428, 429, 430, 431, 432, 433, 434, 435, 436, 437, 438, 440 | 230, 232 |
| PAC-D27 | 442, 444, 446, 447, 448, 449, 450, 451, 453, 455, 456, 457, 458, 459, 460, 461, 462, 463, 465 | 234, 236, 237, 238, 239, 240, 241, 243, 244, 245, 246, 247, 248, 249, 250, 251, 253 |
| PAC-D28 | 467, 469, 471, 472, 473, 474, 475, 476, 477, 478, 479, 480, 481, 482, 483, 484, 485, 486, 487, 488, 489, 490, 491, 492, 493, 494, 495, 496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512 | 255, 257, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 271, 272, 273, 274, 275, 276, 277, 278, 279, 280, 281, 282, 283, 284, 285, 286, 287, 288, 289, 290, 291, 292, 293, 294, 295, 296, 297, 298, 299, 300 |
| PAC-D29 | 514, 516 | 302 |
| PAC-D30 | 518, 520, 522, 523, 524, 525, 526, 527, 528, 529, 531 | 304, 306, 308 |
| PAC-D31 | 533, 535, 537, 538, 539, 540, 541, 542, 543, 544, 545, 547 | 310, 312, 314, 316, 318, 320, 322, 324 |

## Review gate

Owner decision: adopt R1–R9 and the cumulative disposition matrices as the v1.1 design contract, while retaining original bytes and remaining engineering decisions. OD-01 architectural direction has been explicitly accepted; migration readiness remains separate. OD-02 source coverage is exhaustive at line/range level and the cumulative rule avoids semantic loss; no formal independent sentence-level proof claimed. Following owner approval, update status/precedence and current design references additively, verify docs-only diff and exact-head CI, then safe squash merge and post-merge CI. No implementation or environment publication.
