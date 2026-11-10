# Architecture overview

**Status:** proposed baseline, pending reconciliation with Implementation Design v0.2 and subsequent ADRs.

## Shape

Eventor is a modular monolith with independently deployable frontend entry points and background/optimization processes where operationally justified. Modules share one domain model and PostgreSQL database through explicit application boundaries; they are not independent microservices.

```
Staff Web ───────┐
Guest Portal ────┼── HTTPS ── Fastify API ── PostgreSQL
Check-in PWA ────┘                 │              │
                                  ├── Worker ─────┘
                                  ├── WebSocket / transactional outbox
                                  └── C++ OR-Tools optimization process
```

All database access is server-side. The API is authoritative for validation, workflow transitions, permissions and audit records.

## Logical modules

- Identity, authentication, sessions and authorization.
- Organization, venue and event management.
- Configuration registry: forms, catalogues, services, equipment, prices, workflow and branding revisions.
- Booking inquiry, draft, offer, approval and confirmed booking.
- Guest registry, event participation, invitations and RSVP.
- Venue/spatial inventory, floor plans, allocations and seating.
- Guest portal, QR credential issuance and check-in.
- Event prerequisites and external coordination.
- Operations cockpit, notifications, audit and reporting.
- Import/export, document generation and background jobs.

## Frontends

- Staff web: administrative and operational workspaces.
- Guest portal: personalized, public-facing PWA with narrowly scoped data.
- Check-in PWA: staff-authorized scanning and attendance operations.

They may share UI and contract packages but must not share privileged data projections indiscriminately.

## Data and integration

- PostgreSQL is the source of truth.
- Migrations are forward-only and reviewed; destructive changes require explicit data migration strategy.
- WebSocket messages are published from a transactional outbox to avoid committing database state without corresponding event publication.
- Long-running imports, notifications, document rendering and optimization execute asynchronously.
- Email is an initial invitation delivery channel behind a provider abstraction. Do not bind the domain to a specific SaaS provider.
- Public access is limited to explicitly allowlisted portal/RSVP/booking endpoints through a reverse proxy. Admin interfaces and internal APIs remain private unless separately approved.

## Optimization boundary

The C++ OR-Tools CP-SAT process receives a validated, versioned allocation problem and returns a proposal, objective/diagnostics and assignment result. The API checks the result against current state and permissions. A human previews and explicitly commits the proposal. The solver cannot directly mutate authoritative booking or allocation records.

## Security boundaries

- Tenant/organization/venue/event scope is enforced server-side.
- RBAC is supplemented by field- and operation-level authorization.
- Public guest views are purpose-built projections; no general-purpose guest API is exposed publicly.
- Invitation and check-in tokens are different credentials with different scopes and revocation.
- Audit records cover privileged access, sensitive changes, manual RSVP entry, booking approval and check-in correction.
- Uploads are quarantined and validated before downstream processing.
- Real personal data and sensitive venue/security details are excluded from source control and test fixtures.

## Deployment

Target is self-hosted Linux. Deployment may use native packages/systemd and a reverse proxy. Containers may be used optionally, but no architectural requirement depends on Docker, Redis/Valkey or a cloud service. Exact deployment topology, backup/restore and observability standards require separate implementation decisions.
