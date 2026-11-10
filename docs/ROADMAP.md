# Delivery roadmap

This roadmap is provisional. Scope and acceptance criteria must be finalized after the design artifacts are reconciled.

## Phase 0 — Repository and design baseline

- [x] Import Technical Blueprint v1.2 and Implementation Design v0.2 source artifacts.
- [x] Perform initial static reconciliation and record findings in `docs/DESIGN_RECONCILIATION_v0.2.md` (remaining technical validation tracked separately).
- [ ] Complete PostgreSQL parser/runtime validation and migration tests; initial structural schema review is documented in `docs/database/DATABASE_REVIEW_v0.2.md`.
- [ ] Resolve cross-organization ownership and tenant/resource integrity findings (Issues #12 and #13).
- [x] Record initial architectural decisions and unresolved assumptions; add follow-up ADRs as decisions are approved.
- [ ] Define MVP and acceptance criteria.
- [ ] Add CI, issue/PR templates and repository protection settings.

## Phase 1 — Platform foundation

- [ ] Monorepo workspace and build tooling.
- [ ] Fastify API skeleton, configuration and health/readiness endpoints.
- [ ] PostgreSQL migrations, connection management and transaction conventions (migration standards documented; executable migrations pending schema reconciliation).
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
