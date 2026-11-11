# Delivery roadmap

This roadmap tracks the accepted Eventor product direction and implementation gates. PR #26 contains the initial PostgreSQL/OpenAPI baseline; PR #27 is a separate stacked remediation and application-foundation draft. Both remain open, unmerged drafts.

## Phase 0 — Repository and design baseline

- [x] Import Technical Blueprint v1.2 and Implementation Design v0.2 source artifacts.
- [x] Perform initial static reconciliation and record findings in `docs/DESIGN_RECONCILIATION_v0.2.md` (remaining technical validation tracked separately).
- [x] Apply the initial ordered migrations and run PostgreSQL 18.6 migration/integrity/RLS/concurrency tests in CI (draft PR #26); broader upgrade and recovery validation remains open.
- [x] Accept the cross-organization ownership and tenant/resource integrity successor designs (PRs #15, #24 and #25); implementation review remains open in draft PR #26.
- [x] Record initial architectural decisions and unresolved assumptions; add follow-up ADRs as decisions are approved.
- [x] Define the venue-first MVP and acceptance criteria (PR #20).
- [ ] Add CI, issue/PR templates and repository protection settings.

## Phase 0.5 — Successor contracts

- [x] Accept database integrity and resource reservation constraints (Issue #13 / PR #24).
- [x] Produce an initial ordered PostgreSQL 18 migration draft and checksum runner.
- [x] Produce canonical OpenAPI 3.1.1 v0.3 YAML from the route/security design.
- [x] Add PostgreSQL integration/concurrency/RLS tests and pinned OpenAPI validation to the unified CI workflow.
- [x] Pass the unified three-job CI workflow on PostgreSQL 18.6, OpenAPI 3.1 and the initial staff-web build on PR #27 head `8c19c51b37a67f1cb1faf6f158d5db32e8c32d9e` ([run #43027314682](https://github.com/TeraflopsBH/eventor/actions/runs/43027314682)). This successful run predates migrations 000039–000044 and the subsequent Resend/public booking-intake/staff-inquiry changes; it does not validate the current PR #27 head.
- [ ] Complete deeper schema/permission review, migration-upgrade/backup tests and route-level API contract tests before accepting the DDL.
- [ ] Close Issues #2, #3, #13 and #17 only after their runtime/CI acceptance criteria pass.

## Phase 1 — Platform foundation

- [ ] Monorepo workspace and build tooling.
- [x] Fastify API bootstrap, environment configuration, database pools and staff-session integration are present in PR #27.
- [ ] Add unauthenticated liveness and dependency-aware readiness endpoints, plus operational health checks.
- [x] A 44-file PostgreSQL 18 migration chain, least-privilege roles, checksum runner and transactional command conventions are present across PRs #26/#27. Fresh-database validation passed on the earlier PR #27 head; migration-upgrade, backup/restore and current-head CI validation remain open. Migrations 000040–000041 add restricted published-form retrieval and encrypted, idempotent, rate-limited public inquiry submission; migration 000042 adds permissioned staff inquiry projections, assignments, review status, internal annotations and immutable histories; migration 000043 adds exact published-revision projection for validation against the revision the visitor actually submitted; migration 000044 adds a permission-gated active assignee roster and membership capability projection.
- [ ] Shared contracts, validation and error model.
- [ ] Complete review of the implemented database-backed staff sessions, CSRF/origin checks, tenant-scoped authorization and audit boundaries; extend role/permission coverage to the remaining API operations.
- [x] Organization, venue and event tenancy foundations and RLS migrations are present.
- [ ] Complete runtime API projections and staff workflows for organization, venue and event administration.
- [ ] CI checks and synthetic test fixtures.

## Phase 2 — Configurable venue booking

**Next application vertical slice:** convert a reviewed inquiry into a separate editable booking draft, support immutable draft revisions, issue/revise offers, record acceptance/rejection and confirm the booking using the existing reservation commands. The public API validates answers against the exact immutable published revision using field-schema v1, and the staff UI now supports permission-aware inbox/detail, assignment, status, internal notes and histories. Keep booking-only operation independent of optional event/guest capabilities.

- [ ] Versioned form/catalogue/configuration management.
- [x] Public inquiry intake and spam/rate protections.
- [x] Permissioned staff inquiry review API, assignment, status, internal notes and immutable history.
- [x] Staff inquiry inbox/detail UI with permission-aware assignment, status and annotation controls.
- [x] Versioned field-schema v1 answer validation against the exact published revision.
- [ ] Separate editable booking draft and offer/approval flow.
- [ ] Explicit booking confirmation and resource reservation.
- [ ] Resource inventory, pricing and separately scheduled rehearsals.
- [ ] Notifications and booking audit trail.
- [ ] Customer/organizer cancellation requests, venue-initiated cancellation, approval policy, commercial consequence snapshot and atomic resource release ([Issue #21](https://github.com/TeraflopsBH/eventor/issues/21)).

## Phase 3 — Guest registry, invitations and RSVP

Cancellation/postponement behavior is proposed in `docs/implementation-design/v0.3/CANCELLATION_AND_EVENT_DISRUPTION_DESIGN_v0.3.md`; design review and contract alignment are tracked in [Issue #21](https://github.com/TeraflopsBH/eventor/issues/21).

The domain design is documented in `docs/implementation-design/v0.3/RSVP_AND_INVITATION_DESIGN_v0.3.md`; schema/API implementation is tracked in [Issue #10](https://github.com/TeraflopsBH/eventor/issues/10).

- [ ] Persistent guest registry and event participation.
- [ ] Imports, duplicate detection and supervised merge.
- [ ] Invitation batches, secure links and delivery tracking.
- [ ] Guest self-service RSVP and response-change rules.
- [ ] Staff-recorded RSVP with source/operator/time/notes.
- [ ] Guest portal and privacy-safe personal view.
- [ ] Event cancellation/postponement, RSVP reconfirmation, notification audiences and tracked cancellation campaigns ([Issue #21](https://github.com/TeraflopsBH/eventor/issues/21)).

## Phase 4 — Venue spatial model and seating

- [ ] Venue geometry, floors, rooms, zones, rows, positions and capacity pools.
- [ ] SVG floor-plan editor and versioned maps.
- [ ] Manual and category-based allocation.
- [ ] Constraint model, diagnostics and solver integration.
- [ ] Proposal preview, locking, scoped reruns and explicit commit.
- [ ] Sanitized guest-facing map rendering.

## Phase 5 — Check-in and live operations

- [ ] QR issuance and revocation.
- [ ] Staff check-in PWA and attendance corrections.
- [ ] Live operations cockpit and role-specific workspaces.
- [ ] Real-time events, alerts, readiness and operational audit.
- [ ] Reports, signage and guest materials.

## Phase 6 — Hardening and deployment

- [ ] Security review and threat model.
- [ ] Backup/restore and disaster-recovery validation.
- [ ] Performance, accessibility and browser/device testing.
- [ ] Monitoring, logs and operational runbooks.
- [ ] Pilot deployment, user acceptance and production readiness.
