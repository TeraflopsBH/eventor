# Agent and contributor instructions

> **Owner-approved design resolution — 2026-11-27 (PR #239):** [ADR 0025](docs/decisions/0025-platform-governance-tenant-authority.md) is accepted for future least-privilege platform governance, and [R1–R9 and the cumulative clause dispositions](docs/blueprint/v1.3/TDS_PAC_CLAUSE_DISPOSITIONS_v1.0.md) plus [TDS v1.1](docs/implementation-design/v0.3/TEMPLATE_DESIGN_STUDIO_DESIGN_v1.1.md) and [PAC v1.1](docs/implementation-design/v0.3/PLATFORM_ADMINISTRATION_CENTER_DESIGN_v1.1.md) form the approved successor design clarification. OD-01 is resolved as architecture; OD-02 is resolved by cumulative compatible requirements and explicit precedence, not a sentence-level equivalence proof. This note supersedes older pending OD-01/02 approval wording, not remaining implementation decisions. Preserve current ADR 0015 runtime behavior until reviewed PAC M0/M1 inventory, exact allowlist, impact, migration, recovery and verification are approved and activated. Unknown/new managed permissions must not be assumed safe. Keep all original sources, current issue obligations, #104/#112 → #105–107 → #110/#111/#108 and Phase 9 acceptance unchanged; no new implementation track, environment republication or test credit.

> **Current approved design baseline (2026-11-27):** [Eventor Technical Blueprint v1.3 reading guide](docs/blueprint/v1.3/README.md). Read its relevant consolidated requirements and original source traceability alongside current `PROJECT_STATE.md`, applicable ADRs, runtime contracts and tests. Preserve the existing development sequence; the blueprint does not authorize a new implementation track, environment republication or early final acceptance.

These instructions apply repository-wide unless a more specific `AGENTS.md` is added in a subdirectory.

## Working principles

1. Read `README.md`, `docs/PROJECT_STATE.md`, the relevant design documents, and applicable ADRs before changing code.
2. Treat the repository as the source of truth. Update project state, decisions, API contracts, migrations, and tests when implementation changes make them stale.
3. Do not invent product requirements, venue facts, capacities, prices, legal obligations, or operational policies. Mark unverified assumptions and ask for confirmation where they affect behavior.
4. Prefer small, reviewable changes. Explain the intent, affected modules, migration impact, security implications, and verification performed.
5. Do not claim code, migrations, tests, builds, deployments, or integrations have been run unless they actually have been run and the result is known.
6. Keep the system a modular monolith unless an ADR approves a different boundary. Do not introduce microservices, Docker, Redis/Valkey, cloud dependencies, or third-party SaaS as mandatory components without an approved decision.
7. Use TypeScript strict mode for TypeScript projects. Keep API contracts explicit and validate untrusted input at the boundary.
8. Keep business rules on the server. The browser must not connect directly to PostgreSQL or make authorization decisions.
9. Use stable identifiers for configurable options. Retire options referenced by historical records; do not destructively delete or silently repurpose them.
10. Preserve historical meaning: inquiries, offers, approvals and confirmed bookings must retain the exact form/catalogue revisions and labels relevant at the time.

## Security and privacy

- Never add real guest names, contact details, attendance records, invitation URLs/tokens, credentials, secrets, private keys, or production database dumps to Git.
- Use synthetic data in fixtures, screenshots, tests and documentation.
- Invitation and QR credentials must be cryptographically random, opaque, scoped, revocable and stored safely (prefer token hashes at rest).
- Separate public guest projections from staff/internal records. Never expose a guest directory or internal security/coordination notes through public endpoints.
- Enforce tenant, organization, venue, event, role and field-level authorization on the server.
- Treat uploaded files as untrusted; quarantine and validate them before use.
- Keep sensitive source venue drawings and security-sensitive operational details out of the repository unless explicitly approved and sanitized.

## Architecture constraints

- API-first modular monolith: Vue 3 + TypeScript + Vite; Fastify + TypeScript; PostgreSQL.
- Separate staff UI, guest portal and check-in experience may be independently built/deployed, but share contracts and domain packages.
- Use transactional outbox for reliable realtime publication.
- Floor plans use an explicit spatial model and SVG rendering; do not infer every number in a source drawing to be a seat.
- Optimization is advisory: solver proposals require preview, diagnostics and explicit human commit. Never silently apply a solver result.
- RSVP is not attendance. Keep invitation delivery, RSVP response and physical check-in as distinct facts.
- External prerequisite coordination is a readiness/checklist workflow, not an internal law-enforcement or inspection system.

## Change workflow

- Keep `docs/PROJECT_STATE.md` concise and current: verified baseline, implemented behavior, next work and validation limits. Preserve detailed historical receipts in the linked state archive instead of appending superseded status to the active handoff.

- For schema changes, add a forward migration and update schema reference and relevant tests.
- For API changes, update the OpenAPI contract and shared request/response types.
- For configurable forms/catalogues, preserve published revisions and historical snapshots.
- For user-visible workflows, include authorization, audit, validation, failure and accessibility considerations.
- Add tests for behavior and regression cases. Document any tests not run and why.
- Use an ADR for decisions that materially affect architecture, security, data model, deployment, or product behavior.

## Design consistency companion — 2026-11-27

Read [Blueprint v1.3 consistency reconciliation](docs/blueprint/v1.3/DESIGN_CONSISTENCY_RECONCILIATION_v1.0.md) and [shared engineering registers](docs/blueprint/v1.3/ENGINEERING_REGISTERS_v1.0.md) with the relevant detailed source. Respect pending OD-01/02 decisions; do not infer new sensitive authority, automatic supersession or waived acceptance. Existing ADRs/runtime contracts and current roadmap remain in force. No parallel development track.
