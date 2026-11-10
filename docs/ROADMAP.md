# Delivery roadmap

This roadmap tracks the accepted Eventor product direction and implementation gates. PR #26 contains the first executable database/API contract draft; it remains unmerged pending review.

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
- [x] Pass the unified CI workflow end-to-end on PostgreSQL 18.6 and the canonical OpenAPI contract (latest PR run #42837964380 on head `ce9fd3d7e4889b713f36e1d93d1b40c3e0c609f2`; both jobs succeeded).
- [ ] Complete deeper schema/permission review, migration-upgrade/backup tests and route-level API contract tests before accepting the DDL.
- [ ] Close Issues #2, #3, #13 and #17 only after their runtime/CI acceptance criteria pass.

## Phase 1 — Platform foundation

- [ ] Monorepo workspace and build tooling.
- [ ] Fastify API skeleton, configuration and health/readiness endpoints.
- [ ] PostgreSQL migrations, connection management and transaction conventions (20-file migration draft and green PostgreSQL 18.6 CI are in draft PR #26; deployment is not started).
- [ ] Shared contracts, validation and error model.
- [ ] Authentication, sessions, authorization and audit foundation.
- [ ] Organization, venue and event tenancy model.
- [ ] CI checks and synthetic test fixtures.

## Phase 2 — Configurable venue booking

- [ ] Versioned form/catalogue/configuration management.
- [ ] Public inquiry intake and spam/rate protections.
- [ ] Staff inquiry review and immutable inquiry history.
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
