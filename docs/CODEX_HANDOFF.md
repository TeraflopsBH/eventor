# Codex Project Handoff — EVENTOR

> **Current design handoff — 2026-11-27 (supersedes earlier design-reference wording, not engineering priorities):** Product owner approved [Technical Blueprint v1.3](blueprint/v1.3/README.md) for integration. Read the guide and the relevant sections of the complete [consolidated Markdown](blueprint/v1.3/Eventor_Technical_Blueprint_v1.3.md) from the checkout, then follow `PROJECT_STATE.md`, `ROADMAP.md`, current issue/PR status, actual code, OpenAPI/migrations and accepted ADRs. Parts II–V provide traceability and complete sources; do not load the entire archival file unnecessarily. The design baseline is source-complete and approved; implementation/acceptance remain separate. Continue the established #104/#112 → #105–107 → #110/#111/#108 sequence; do not restart or fork current work, republish the environment, or run final acceptance before the integrated release candidate. Historical facts and old CI receipts in this handoff remain historical.

**Purpose:** Persistent takeover brief for OpenAI Codex in the desktop app, including sessions or accounts that do not have access to the previous ChatGPT conversation.  
**Repository:** `TeraflopsBH/eventor`  
**Default branch:** `main`  
**Handoff prepared:** 2026-11-16

This document is a transfer of engineering context, not a substitute for inspecting the live repository. **GitHub and the checked-out repository are the source of truth.** Some historical branch, issue and CI details below may have changed; verify them before acting.

## 1. First-session instructions — do these before coding

1. Read the repository-wide `AGENTS.md` and follow it. Then read:
   - `README.md`
   - `docs/PROJECT_STATE.md`
   - `docs/ROADMAP.md`
   - `docs/BLUEPRINT_TO_REPOSITORY_GAP_ANALYSIS_v1.0.md`
   - relevant ADRs under `docs/decisions/` and design material under `docs/implementation-design/`.
2. Inspect the local working tree before changing anything: `git status --short --branch`, current branch, remotes, uncommitted changes and recent history. Never discard or overwrite user changes.
3. Fetch current GitHub state: `main` SHA, open/closed PRs, issues, branch list and latest Actions runs. Use `gh` if authenticated; otherwise use available GitHub integration. Do not assume this account has the same connected integrations as the previous account.
4. Reconcile this document against the live state. Update it if important project facts have changed.
5. Resume with the immediate priorities in section 8. Do implementation, not just planning, whenever repository access permits.

## 2. Working relationship and execution authority

The project owner expects Codex to act as an autonomous engineering agent, not merely a reviewer or adviser.

Authorized work includes:
- Inspecting and modifying application code, migrations, tests, docs and CI.
- Creating focused branches, commits and pushes.
- Creating/updating GitHub issues and pull requests.
- Reviewing and consolidating obsolete or superseded branches/PRs.
- Squash-merging changes when implementation is complete, review is performed, required checks pass and the change is safe to integrate.

There are no independent human reviewers available. Compensate with careful self-review, focused changes, comprehensive automated tests, exact-head CI verification and post-merge checks. Do not bypass required checks or claim a test passed unless it actually ran and passed. Explain any skipped tests and why.

The owner has one Zorin OS PC with QEMU/KVM and can run the `eventor-acceptance` VM. There is no separate Linux server. The acceptance VM is deliberately reserved for final integrated validation, not early feature development.

The final release **must provide both native Linux and Docker Compose installation**. Docker is an optional deployment mode, not a mandatory architectural dependency.

## 3. Current project baseline (verify live)

At the time this handoff was prepared:
- Latest known `main` was `da421567f68fd93976582374bf1ad8b493549d02`.
- PR #129 had been squash-merged. It delivered the public customer cancellation request/status journey and migration 000120.
- `docs/PROJECT_STATE.md` and `docs/ROADMAP.md` had been refreshed on 2026-11-16 and report post-merge main workflows #43934221982 (contracts/PostgreSQL) and #43934221882 (secret-history scan) as passed.
- Do not rely on these identifiers if live GitHub now reports a later main commit or newer workflow results.

### Integrated work relevant to cancellation
- PR #116 integrated backend cancellation commands and migrations 000115–000118.
- PR #128 integrated staff cancellation workspace and booking-revision-aware detail projection (migration 000119).
- PR #129 integrated public customer cancellation request and reusable read-only status capability (migration 000120).
- Customer submission is a request, not execution of cancellation. Staff review/approval and approved execution remain separate.
- Public status capability is reusable/read-only; bearer token is hash-persisted, fragment-carried, removed from browser history, and protected with no-store/no-referrer and logging redaction controls.
- Cancellation does not imply automatic refunds, fee calculation or money transfer.
- The canonical migration 000120 was cleaned during integration: one complete function definition plus final REVOKE/GRANT statements (about 182 lines). An earlier stacked branch had duplicated/orphaned SQL fragments (~5,456 lines). Preserve the clean canonical migration; do not restore the malformed version.
- Source-level security tests cover fragment-only token handling, history cleanup, locale continuity, cookie omission and logger redaction. A dedicated full browser acceptance journey for public cancellation was still a follow-up; existing browser acceptance covered authentication and guest invitations.
- Optional live SMTP/public HTTPS probes were skipped when external endpoint/sandbox configuration was absent. A skipped probe is not a pass and CI is not production acceptance.

### Other integration history
Important merged work includes PRs #85, #99, #101, #102, #103, #109, #116, #128 and #129. PR #103 is the blueprint-to-repository gap audit; PR #109 refreshed roadmap/project-state documentation. Consult live GitHub for exact merge SHAs and status rather than relying on stale branch copies.

## 4. Product vision and architecture

Eventor is a self-hostable, configurable event-operations platform spanning venue booking and commercial workflows, organizer event management, guest registry, invitations/RSVP, seating, admission/check-in, event-day operations and venue/vendor collaboration.

Keep the product an **API-first modular monolith** unless an accepted ADR changes that:
- Frontend: Vue 3, TypeScript, Vite.
- API: Fastify, TypeScript.
- Database: PostgreSQL (authoritative source of truth).
- Background work: TypeScript workers and transactional outbox.
- Spatial plans: explicit spatial model with SVG rendering/editor.
- Allocation: C++ OR-Tools CP-SAT as an advisory solver.
- Deployment: Linux/systemd native mode and Docker Compose mode.

Do not introduce mandatory microservices, cloud services, Redis/Valkey, Docker, or third-party SaaS without an approved architectural decision. Reuse the existing schema, route, authorization, UI and shared-contract foundations rather than creating duplicate aggregates.

## 5. Non-negotiable domain, security and product decisions

- PostgreSQL is authoritative. Keep business rules and authorization on the server; browser clients never connect directly to PostgreSQL.
- Preserve tenant, organization, venue, event, role and field-level authorization. Use existing permission helpers and RLS. Never bypass RLS or weaken grants to make a test pass.
- Use transactional commands, idempotency where appropriate, audit history and explicit permission checks.
- Maintain immutable/versioned snapshots for schedules, published configurations, commercial terms, plans and historical facts.
- Guest person identity is separate from event participation. One person may attend multiple events without duplicated identity records.
- Organizer guest data is private from venue providers by default; collaboration must be explicitly scoped.
- Invitation delivery, RSVP, admission eligibility and physical check-in are distinct facts. Invitation tokens are not admission QR passes.
- Admission credentials must be opaque, cryptographically random, scoped, revocable and stored safely (prefer hashes at rest).
- Public capability endpoints expose only purpose-bound, minimal projections. Use expiry/revocation, rate limits as appropriate, safe token handling, no-store/no-referrer, and secret/log redaction.
- Guest allocation is separate from venue resource reservation.
- OR-Tools output is advisory only: validate a versioned problem, show diagnostics and before/after diff, and require an authorized human to explicitly commit. Never silently apply solver results.
- Event cancellation, booking cancellation, postponement and customer cancellation requests are distinct workflows.
- Preserve commercial policy/price/tax snapshots. Do not invent fees, legal obligations or refund behavior; do not automatically transfer money.
- External prerequisite/CDI work is coordination/readiness tracking, not an official inspection, certification or legal responsibility system.
- Treat uploaded files and source floor plans as untrusted. Preserve originals and require validation/human review.
- Never commit real guest data, contact details, attendance records, bearer tokens, credentials, private keys, production dumps or sensitive venue/security drawings. Use synthetic fixtures.

## 6. Major remaining product tracks

Use the live issue tracker and current gap analysis as the detailed specification. The issue numbers below were current in the previous checkpoint; verify they remain open and have not been superseded.

### #104 — Event administration and persistent Guest Registry (next main track)
Existing foundations include migrations 000008, 000011, 000012 and subsequent invitation/RSVP work; inspect them before designing anything new. Event foundations include events, immutable schedule revisions, sessions, capability sets/revisions and per-event capability overrides. Existing helper `eogp.assert_event_command_permission(organization,event,membership,permission)` handles organization-wide or event-scoped grants and locks membership/grant rows. `event.manage` is a sensitive event-scoped permission.

Important design points:
- Event creation has no event ID yet: require organization-scope `event.manage`, then atomically create the event, initial immutable schedule revision, initial capability set and audit event.
- Subsequent event/session commands use event-scoped authorization and optimistic revision checks.
- Schedule changes create new immutable revisions; never mutate historical snapshots.
- Implement event lifecycle, sessions, timezone/configuration and capability management.
- Implement persistent person CRUD, contact management, search, profile history, participation, guest lists/groups, relationships, categories/tags/custom fields, bulk actions and saved views.
- Add CSV/XLSX import/export with preview, validation, row errors, duplicate detection, supervised identity merge and audit.
- Keep person identity independent of event participation. Protect organizer guest data from venue-provider access by default.
- Before coding, inspect migrations 000008–000012 and later, route inventory, staff shell, OpenAPI v0.3, authorization/RLS and issue acceptance criteria.

### #105 — Venue spatial model and SVG floor-plan editor
Venue/building/level/room/space hierarchy; reusable templates; source plan onboarding (PDF/image/SVG); SVG editor; layers and scale calibration; tables, rows, prayer rows, individual positions, capacity zones and non-allocatable features; mixed precise/count capacity; versioned revisions, approval/publication and printable plans. Provide keyboard/accessibility alternatives to drag-and-drop. Never infer that every number on a drawing is a seat.

### #106 — Guest seating and allocation
Manual assignment/movement first; groups/categories, capacities, together/avoid constraints, preferences/exclusions, session constraints, locks, conflict diagnostics and targeted reflow. Then advisory OR-Tools CP-SAT proposals with versioned inputs, diagnostics, objective and before/after diff. Explicit authorized human approval/commit only.

### #107 — Admission QR, check-in and Operations Cockpit
Separate admission credential lifecycle from invitation tokens. Implement revocable opaque QR credentials, guest cards, check-in PWA, camera/manual scan, station/operator management, duplicate prevention, multi-gate operation, corrections/audit, bounded offline operation and reconciliation. Then live cockpit with metrics, map layers, alerts, timeline, interventions, role workspaces and real-time synchronization.

### #110 — Vendor/staff collaboration and external prerequisites
Assignments, accountable/performing parties, deliverables, deadlines, evidence, status history, scoped collaboration, external prerequisites and readiness checklists. Do not imply formal inspection or legal authority.

### #111 — Communications, branding and reporting
Real email composer (plain text/HTML, variables, preview, validation, test-send, localization and revision history), organization/venue/event branding inheritance, configurable reports, document templates, information displays and operational exports. Existing campaign review is not a full composer.

### #112 — Booking cancellation/disruption and event coordination
Do not recreate work already delivered in #116/#128/#129. Reassess remaining scope from live issue and code. Potential remaining work includes venue-initiated cancellation/disruption notices, follow-up projections, explicit linkage to organizer event operations, amendment/postponement integration and full end-to-end acceptance. Keep venue booking cancellation, organizer event cancellation, organizer postponement and customer cancellation request separate.

### #108 — Native Linux and Docker Compose installer (mandatory)
Native: supported distro/dependency detection, dedicated service users, filesystem permissions, PostgreSQL, least-privilege roles, secure secrets, migrations, API/worker/frontend, systemd, reverse proxy/HTTPS, initial admin bootstrap, validation, upgrade, rollback, backup/restore.
Docker: production Dockerfiles and Compose topology, non-root services, volumes, health/readiness, controlled migrations, secure secrets, upgrade and backup/restore.
Both modes must run the same application build, migrations and configuration/security contract. Docker is optional, not the only installation path. Existing systemd templates are not a complete installer; previous inventory found no production Compose topology/Dockerfile or complete native installer.

## 7. Delivery order (adapt to dependencies and live state)

1. Verify current main and CI; reconcile stale docs/issues/PRs.
2. #104 Event administration + persistent Guest Registry.
3. #105 Venue spatial model/editor.
4. #106 Seating/allocation.
5. #107 Admission QR/check-in/operations cockpit.
6. #110 Vendor/staff collaboration and prerequisites.
7. #111 Communications/branding/reporting/displays.
8. Complete remaining #112 booking disruption/event coordination, integrating where dependencies require.
9. #108 Native + Docker Compose production installers.
10. Final `eventor-acceptance` VM validation of both install modes and full workflows.
11. Release preparation and operational documentation.

The sequence is not rigid if dependencies or defects justify adjustment. Do not start final VM validation before the product and both installation modes are ready.

## 8. Immediate next actions

1. Verify live `main`, PR #129 merge state, workflow #43934221982 and #43934221882 (or newer descendant runs). The project-state document at handoff time reports both post-merge workflows passed; confirm current reality.
2. Read and reconcile `docs/PROJECT_STATE.md`, `docs/ROADMAP.md` and `docs/BLUEPRINT_TO_REPOSITORY_GAP_ANALYSIS_v1.0.md`. The first two were refreshed 2026-11-16; preserve accurate current status rather than blindly rewriting them.
3. Inspect issue #112 and mark only genuinely completed scope as done; retain remaining disruption/amendment/postponement/end-to-end work.
4. Start #104 with a repository-first vertical-slice analysis and implementation. Trace existing migrations, DB command patterns, authorization/RLS, API routes, OpenAPI, shared types, frontend structure, tests and UI conventions.
5. Implement the vertical slice end to end: migration/schema (if needed), controlled DB commands, RLS/permissions, API, OpenAPI/shared contracts, frontend, audit/idempotency, regression tests and docs.
6. Run the relevant checks locally where possible; push a focused branch, create/update PR, validate exact PR head, squash-merge when green and safe, then verify post-merge main.
7. Keep project state, roadmap, issue acceptance criteria and PR descriptions synchronized with actual merged work.

## 9. Engineering workflow and quality bar

For each feature:
1. Inspect current main, existing schema/migrations, routes, OpenAPI, UI, authorization helpers, tests and issue requirements.
2. Define a coherent vertical slice and acceptance criteria; identify dependencies and security/privacy impact.
3. Implement using existing conventions. Schema changes need forward migrations, schema-reference updates and tests. API changes need OpenAPI and shared types. User workflows need authorization, audit, validation, accessibility and failure handling.
4. Test relevant TypeScript strict checks, API tests, frontend tests/type-check/build, OpenAPI 3.1 validation, PostgreSQL migrations/RLS/concurrency, idempotency, audit and browser acceptance. Run secret-history scanning and systemd checks where relevant.
5. Review the actual diff for accidental scope, duplicate schema/functions, authorization gaps, unsafe logging, migration upgrade hazards, missing rollback and docs drift.
6. Integrate against current main; avoid deep/fragile stacked branches. Prefer small reviewable PRs.
7. Verify exact PR head checks before merge; then verify post-merge main CI.
8. Record what was actually tested, what was skipped, and why. Never claim production acceptance based only on CI.

## 10. User environment and practical constraints

- Development machine: Zorin OS, QEMU/KVM available.
- No separate Linux server and no independent reviewers.
- `eventor-acceptance` VM exists/has been used previously; use it only in final acceptance.
- Final install must offer native Linux and Docker Compose.
- Earlier network constraints reported: ISP blocks inbound TCP 80 and 25; TCP 443 is available. Mailpit is available for local email development/testing. Re-verify if networking becomes relevant.
- Prefer local/self-hosted operation and avoid unnecessary recurring cloud subscriptions.
- External SMTP, public HTTPS and deployed-host probes require real configured environments; mark them skipped/unverified when absent.

## 11. Useful repository references

- `AGENTS.md` — repository-wide agent/contributor rules; read first.
- `docs/PROJECT_STATE.md` — current integration baseline and evidence.
- `docs/ROADMAP.md` — delivery phases and remaining work.
- `docs/BLUEPRINT_TO_REPOSITORY_GAP_ANALYSIS_v1.0.md` — detailed product blueprint vs actual implementation audit.
- `docs/ARCHITECTURE.md` and `docs/OPERATING_MODEL.md` — architecture and operational model.
- `docs/api/openapi.v0.3.yaml` — API contract.
- `docs/implementation-design/` — feature implementation design.
- `docs/decisions/` — accepted architectural/product decisions.

## 12. Codex session operating rules

- Be proactive and continue through a coherent batch of work; do not repeatedly ask the owner to approve routine engineering steps already authorized here.
- Ask only when a product/legal/commercial assumption materially changes behavior and cannot be resolved from accepted design or existing code.
- Do not stop after producing a plan if implementation is possible.
- Before destructive Git actions, inspect and preserve user work. Never force-push or rewrite shared history without a clear necessity and explicit justification.
- Never merge failing or unverified code merely to reduce PR count.
- Keep PRs focused, tests meaningful and commit history understandable.
- At each handoff/session end, update this file and the project-state docs with current branch/PR/commit/check status, completed work, outstanding risks and the exact next action.
- The goal is a complete, secure, maintainable, production-quality, self-hostable EVENTOR product — not simply a green CI pipeline.


## Cloud development checkpoint — 2026-11-16

Remote main matched `ff24d14ffe91c8d70c7f6f04d0907852b2b7394b`; initial branch `work` was clean. Local Node 24.22.1 validation: API 108 passed/2 skipped, staff web 48 passed, API and frontend builds passed. PostgreSQL 18.6 applied all 120 migrations ; the event-change command smoke failed at fixture setup because its referenced organization was absent (foreign-key violation), so runtime behavior remains unvalidated. Vite served the application HTML locally; this is not browser acceptance or full API startup validation. README and project baseline were refreshed. No feature implementation, commit, push or merge was performed.

GitHub REST/GraphQL access returned HTTP 403; PR #129 and latest Actions status remain independently unverified, and live issues #104/#112 could not be read. The cloud draft saves dependency/build instructions, startup guidance and api.github.com access. Review/save settings and publish; then retry GitHub access before reconciling issues. Next: read the complete design/contract for #104, implement an authorized event-administration vertical slice, and validate PostgreSQL authorization plus API/UI behavior. Keep both installation modes required and defer final VM acceptance.


### Follow-up environment verification — 2026-11-16

The network diagnosis is confirmed: the enforced runtime allowlist lacks `api.github.com`, while saved draft revision 3 includes it. The proxy rejects CONNECT before GitHub authentication; token access has not yet been tested. Activate the saved network configuration before retrying REST/GraphQL.

An isolated `eventor_validation` database in the existing development PostgreSQL container now contains the committed synthetic CI fixtures and all 120 migrations. Populated upgrades through 000074 and the 000077 forward-migration assertion passed. The repository upgrade script stopped because ADMIN_URL was absent; its forward assertion and remaining migration steps were then executed explicitly against eventor_validation, without resetting the original database. Event-change command authorization and cancellation/postponement SQL smoke tests passed as eventor_migrator; guest invitation capability smoke passed as eventor_runtime. The earlier missing-fixture failure is resolved. This is selected database validation, not the complete CI suite or final acceptance.


### Verified GitHub access and event administration follow-up — 2026-11-16

GitHub API access is now working in the newly published environment. PR #129 is merged at da421567f68fd93976582374bf1ad8b493549d02. Its post-merge runs 43934221982 and 43934221882 passed; latest main ff24d14 also passed contracts/PostgreSQL run 43936836187 and secret-history run 43936836236. This supersedes the earlier access limitation.

Live inspection discovered existing PR #132 (event administration core), so development continued there instead of duplicating it. Repairs remove the duplicate OpenAPI event collection path, align staff tab types, bind the database fixture tenant/actor, and add migration 000122 to revoke direct runtime event writes. Local contract validation, API tests (109 pass, 2 skip), staff tests (51 pass), production builds, and the event administration SQL test passed. Full updated-head CI and broader product review remain required before merging. Issue #104 remains open for session administration and the persistent Guest Registry. Issue #112 remains open for disruption notices, linked-event follow-up, amendment/postponement integration and final workflow acceptance. No final VM acceptance is claimed.


Latest work is on local branch `fix/event-administration-ci`, pushed to PR #132 (`integrate/event-administration-main-2026-11-16`). Follow-up commits bind update/archive idempotency to event ID (regression reproduced before fix) and pin definer search paths via 000123. Local auth-role security and event administration SQL tests passed after applying 000123. Check the latest PR head and CI before merging; earlier checkpoints describing an unimplemented event-admin slice are superseded by this open PR.
