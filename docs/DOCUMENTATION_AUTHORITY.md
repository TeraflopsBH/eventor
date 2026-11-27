# Eventor documentation authority and navigation register

**Status:** approved documentation governance clarification, 2026-11-27. Baseline inspected: [3941f872](https://github.com/TeraflopsBH/eventor/tree/3941f87200bcc28f74267d403ef06cf42c70551d), PR #239; [all five post-merge checks passed](https://github.com/TeraflopsBH/eventor/actions/runs/46067011709). This is not a runtime audit or new feature decision.

## Read in this order

1. [Agent instructions](../AGENTS.md), [current project state](PROJECT_STATE.md), [resume](development/RESUME.md), [Codex handoff](CODEX_HANDOFF.md), [roadmap](ROADMAP.md). Reconcile dated checkpoints with actual checkout, live GitHub and any unpublished work; never reset or reapply merged work.
2. [Blueprint v1.3 guide](blueprint/v1.3/README.md), relevant consolidated requirements and exact sources; [approved design index](implementation-design/v0.3/README.md), [consistency ledger](blueprint/v1.3/DESIGN_CONSISTENCY_RECONCILIATION_v1.0.md), [engineering registers](blueprint/v1.3/ENGINEERING_REGISTERS_v1.0.md).
3. [ADR status and supersession index](decisions/README.md), [R1–R9 and clause dispositions](blueprint/v1.3/TDS_PAC_CLAUSE_DISPOSITIONS_v1.0.md), [TDS v1.1](implementation-design/v0.3/TEMPLATE_DESIGN_STUDIO_DESIGN_v1.1.md), [PAC v1.1](implementation-design/v0.3/PLATFORM_ADMINISTRATION_CENTER_DESIGN_v1.1.md) for affected work.
4. Actual code, [OpenAPI](api/openapi.v0.3.yaml), migration chain, database grants and tests for current behavior. [Deployment runbook](operations/SELF_HOSTED_DEPLOYMENT_RUNBOOK.md), [remote acceptance](operations/REMOTE_ACCEPTANCE.md) and [external acceptance evidence](operations/EXTERNAL_ACCEPTANCE_EVIDENCE.md) for verification.

## Classification and precedence

| Classification | Meaning and governing sources |
|---|---|
| Current normative design | Blueprint v1.3 plus approved detailed addenda, accepted ADRs, R1–R9 and explicit successor interpretations; preserve cumulative compatible requirements. |
| Current implemented | Actual code, migration history, OpenAPI, tested contracts and exact-revision evidence; not permission to weaken approved future requirements. |
| Historical | Blueprint v1.2, implementation design v0.2, original source annexes, earlier receipts, original crosswalk and dated checkpoints. Preserve bytes and source context; not a new implementation order. |
| Proposed engineering | Logical DDL, illustrative routes/codes, numerical budgets, exact policy and library choices, OD-03–06 and unresolved M0 choices; require owning review, never infer implementation. |
| Superseded provision | Explicit decision with exact scope and transition gate. ADR 0025 supersedes future blanket managed grants of ADR 0015 only; current behavior remains until reviewed migration activation. |

Use the most specific approved compatible requirement; do not choose a weaker rule, silently discard source clauses, or treat code presence as acceptance. On a newly found material conflict, record exact source references and seek a decision for the affected slice; unrelated work continues. Security issues with reproducible evidence follow normal security remediation. No change to scope or #104/#112 → #105–107 → #110/#111/#108. Final acceptance remains Phase 9 with both installers.

## DC-12–18 harmonization disposition

| ID | Resolution | Verification boundary |
|---|---|---|
| DC-12 | Project state points to current approved design; retain actual implementation checkpoint and historical receipts. | Documentation update does not update Codex's local checkout or implementation status. |
| DC-13 | ADR index lists all 25 accepted decisions, separates current and future authority and records explicit partial supersession. | All original ADR files unchanged. |
| DC-14 | TDS/PAC crosswalk's pending wording is historical; approved R1–R9 and cumulative dispositions govern. | Preserve the crosswalk body, original payloads, 65 criteria, and exact archived blueprint. |
| DC-15 | Runbook identifies existing systemd templates, development Compose, role/migration tooling and isolated CI backup/restore; incomplete production installers and production recovery remain open. | No claim of target-host acceptance or production readiness. |
| DC-16 | Dated resume is a checkpoint, not an instruction to replay old work; revalidate exact checkout/PR/live status and current design. | Do not overwrite active Codex checkpoint or infer unpublished work. |
| DC-17 | Central authority register and links distinguish historical references from current design. | No broad rewriting of original source references. |
| DC-18 | Optional CI probe configuration is separate from required product capability and Phase 9 evidence. | Actual intended public HTTPS and external SMTP evidence required by G8; skipped probes never pass. Conditional extensions only N/A with explicit reviewed applicability; no silent release waiver. |

## Maintenance

When approving a successor, update the authority and ADR indices, relevant current reading guides and decision gates, keeping pinned source bytes intact. When implementing a slice, update the implementation checkpoint, contracts and evidence only on verified facts. A documentation-only change may record its own verified integration SHA separately without replacing the last verified application checkpoint. Preserve both exact-head and post-merge required checks; never substitute a previous SHA's pass. Historical links may point to prior commits by design. No new issue or implementation track created by this package.
