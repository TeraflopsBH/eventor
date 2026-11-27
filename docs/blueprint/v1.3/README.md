# Eventor Technical Blueprint v1.3 — approved design baseline

> **Owner-approved design resolution — 2026-11-27 (PR #239):** [ADR 0025](../../decisions/0025-platform-governance-tenant-authority.md) is accepted for future least-privilege platform governance, and [R1–R9 and the cumulative clause dispositions](TDS_PAC_CLAUSE_DISPOSITIONS_v1.0.md) plus [TDS v1.1](../../implementation-design/v0.3/TEMPLATE_DESIGN_STUDIO_DESIGN_v1.1.md) and [PAC v1.1](../../implementation-design/v0.3/PLATFORM_ADMINISTRATION_CENTER_DESIGN_v1.1.md) form the approved successor design clarification. OD-01 is resolved as architecture; OD-02 is resolved by cumulative compatible requirements and explicit precedence, not a sentence-level equivalence proof. This note supersedes older pending OD-01/02 approval wording, not remaining implementation decisions. Preserve current ADR 0015 runtime behavior until reviewed PAC M0/M1 inventory, exact allowlist, impact, migration, recovery and verification are approved and activated. Unknown/new managed permissions must not be assumed safe. Keep all original sources, current issue obligations, #104/#112 → #105–107 → #110/#111/#108 and Phase 9 acceptance unchanged; no new implementation track, environment republication or test credit.

**Approval:** Product owner approved the source-complete review edition for repository integration on 2026-11-27. This integration records that approval; it does not certify implementation or production readiness.

**Authoritative consolidated product and engineering design:** [Eventor Technical Blueprint v1.3](Eventor_Technical_Blueprint_v1.3.md). Retain the historical [Blueprint v1.2](../v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md), [accepted ADRs](../../decisions/), [approved design addenda and domain designs](../../implementation-design/v0.3/README.md), current [architecture](../../ARCHITECTURE.md), [operating model](../../OPERATING_MODEL.md), [roadmap](../../ROADMAP.md), [gap analysis](../../BLUEPRINT_TO_REPOSITORY_GAP_ANALYSIS_v1.0.md), and [Codex handoff](../../CODEX_HANDOFF.md).

## Integrity and authority

- Exact approved archival Markdown: **2,841,192 UTF-8 bytes**.
- SHA-256: `e8ab359ce26203e3c86e11403086433172ec114420c00b33a520126bf850a2d8`.
- Git blob SHA-1: `24f3cec749362307f1d77d676ab237e2b2dd036d`.
- Pinned repository source baseline: [`fd993fb2d66b93fbe81ce99c5bfb50c9ec025542`](https://github.com/TeraflopsBH/eventor/tree/fd993fb2d66b93fbe81ce99c5bfb50c9ec025542), PR #237, with all five required CI checks passed.
- All 61 embedded repository sources (including 24 accepted ADRs) independently matched the pinned Git tree's file lengths and Git blob SHA-1 identities; all 61 SHA-256 values and all 12 original review annexes' lengths, SHA-256 values and Git blob identities were revalidated from the approved export before integration.
- Historical wording, including the earlier review edition's source-transfer limitation, proposed status, dates, original relative links, and the original TDS/PAC review text, is deliberately byte-preserved. The leading source materialization certificate supersedes the transfer limitation; **this approval record supersedes draft/pending approval status only**. Annexes are interpreted in their original path context; use the manifest for pinned source navigation. Do not rewrite the approved archival bytes to fix historical relative links.
- Current implemented behavior, accepted ADRs, applicable SQL/OpenAPI contracts and authorization boundaries govern engineering behavior until properly reviewed successors are implemented. If a material conflict remains, preserve the stricter invariant and obtain an explicit decision; never treat an illustrative proposed route, logical table, permission or target as implemented.
- Parts IV and V contain complete source material, not superseding parallel contracts. TDS/PAC original review editions differ from the integrated repository editions; follow the reconciliation ledger and accepted repository decisions. All previously approved scope and acceptance requirements remain in force.

## Reading guide for Codex

The large Markdown file is intentionally archival and may exceed GitHub's web preview limit or a connector's single-file display limit. Read it locally from a synchronized checkout, in bounded sections. The following 1-based line ranges apply to the exact approved blob (19,673 LF-split lines, including the terminal empty line).

| Lines | Purpose |
|---|---|
| 1–35 | Source materialization certificate, control and precedence |
| 36–96 | Product invariants, operating model, governance, adaptive UX |
| 97–177 | Booking/disruption, event production, Registry, spatial and allocation |
| 178–257 | Forms, invitations/RSVP/portal, hospitality, admission, content, communications, cockpit and reporting |
| 258–364 | Data ownership, API, security, deployment, quality |
| 365–418 | Decision reconciliation and accepted ADR register |
| 419–480 | Roadmap continuity and release acceptance |
| 481–2239 | Source-to-consolidated requirement traceability |
| 2240–2374 | Pinned repository source manifest |
| 2375–6822 | Twelve full original review annexes (A–L) |
| 6823–end | 61 exact pinned repository source annexes |

Example (read-only, from repository root, after synchronizing with current main; never discard local work):

```sh
sed -n '1,480p' docs/blueprint/v1.3/Eventor_Technical_Blueprint_v1.3.md
rg -n 'B13-BOOKING|B13-REGISTRY|B13-DECISIONS|B13-ROADMAP|B13-ACCEPTANCE' docs/blueprint/v1.3/Eventor_Technical_Blueprint_v1.3.md
sha256sum docs/blueprint/v1.3/Eventor_Technical_Blueprint_v1.3.md
git hash-object docs/blueprint/v1.3/Eventor_Technical_Blueprint_v1.3.md
```

Before implementation, read [AGENTS.md](../../../AGENTS.md), [PROJECT_STATE.md](../../PROJECT_STATE.md), [CODEX_HANDOFF.md](../../CODEX_HANDOFF.md), the relevant Part I requirements, Part II traceability, the applicable detailed source sections, actual runtime code and tests. Use the live roadmap and issue state to choose the next existing implementation slice. **Do not start a parallel implementation track or redesign working components because this consolidated blueprint exists.** Preserve the #104/#112 → #105–107 → #110/#111/#108 sequence. Final integrated product/host acceptance remains Phase 9, with both native Linux and Docker Compose. CI regression success is not release acceptance. No environment republication or early VM acceptance is authorized by this documentation integration.

## Coordinated consistency companion (2026-11-27)

Read the [design consistency reconciliation](DESIGN_CONSISTENCY_RECONCILIATION_v1.0.md) before affected implementation. Its eleven findings distinguish clarifications of existing scope from pending material decisions OD-01 (ADR 0015/PAC managed authority) and OD-02 (TDS/PAC cumulative detail); neither is an accepted successor ADR or authorization for changed scope. The [TDS/PAC source reconciliation](TDS_PAC_SOURCE_RECONCILIATION_v1.0.md) preserves complete bidirectional nonblank-line coverage and all 65 matching acceptance IDs, with nonidentical clauses explicitly pending semantic adjudication. The [eight engineering registers](ENGINEERING_REGISTERS_v1.0.md) define shared domain ownership, semantic authorization, lifecycle, terminology, capability dependency, quality, release evidence and decision gates. These are companion clarifications, not implementation or proof of complete equivalence. Original approved archival blob remains exact; no blanket new authority, no silent requirement deletion or test waiver. Existing accepted ADRs/current contracts and roadmap remain in force. Read Part I plus exact relevant source clauses and companion notes, not the entire archival inventory. Material decisions and affected engineering M0 review remain gated; continue unrelated existing work.
