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

## Operating scope and module activation

A deployment may be used by a venue provider, an event organizer, or a hybrid operator. Organization configuration establishes a default profile; an individual booking/event can override it. Profiles are defaults, not product tiers. A venue booking remains valid without an operational event record. Full event operations are explicitly activated only when needed.

Distinguish venue provider, booking customer/requester, contracting party, event organizer and operational operator. These roles may differ. Module/task responsibility is assigned explicitly to an accountable party and performing parties; scoped collaboration is granted deliberately and never inferred from a booking relationship. The venue provider retains its own facility/resource and contracted service responsibilities; Eventor does not transfer legal duties.

Modules such as guest participation, invitations/RSVP, seating, guest portal, check-in, external prerequisites and event-day cockpit are independently optional. Module dependencies are narrow and explicit. For example, venue booking does not depend on guest registry or RSVP. Public and staff projections collect and expose only information needed for the enabled scope.

See [Operating Model](OPERATING_MODEL.md) and [ADR 0004](decisions/0004-optional-event-operations-scope.md).

## Logical modules

- Identity, authentication, sessions and authorization.
- Organization, venue and event management.
- Configuration registry: forms, catalogues, services, equipment, prices, workflow and branding revisions.
- Booking inquiry, draft, offer, approval and confirmed booking (independent of operational-event conversion).
- Optional guest registry, event participation, invitations and RSVP.
- Venue/spatial inventory and venue-side floor plans/resources; optional event allocation and seating.
- Optional guest portal, QR credential issuance and check-in.
- Optional event prerequisites and external coordination.
- Optional event operations cockpit, notifications, audit and reporting.
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
