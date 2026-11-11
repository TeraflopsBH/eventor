# Eventor

**Event Operations & Guest Logistics Platform (EOGP)**

Eventor is a self-hosted, API-first platform that can be used for venue booking/resource management alone, full event organization and operations, or a configurable combination. Guest records, invitations/RSVP, seating, check-in and event-day operations are optional capabilities—not requirements for every venue booking.

The first reference deployment is planned for **Gazi Husrev-beg's Library (GHB), Sarajevo**. The product is being designed as a reusable organization- and venue-aware platform rather than a one-off GHB application.

> **Project status:** accepted design baseline; 39 PostgreSQL migrations targeting 18.6, canonical OpenAPI v0.3, Fastify staff API/worker and the first Vue 3 staff-web slice are implemented and CI-validated on draft PR #27. The full booking/event application, remaining API operations and production deployment are not yet complete.

## Product goals

- Manage venue inquiries, booking drafts, offers/approvals and confirmed bookings independently of optional operational-event management.
- Support venue-provider, event-organizer and hybrid operating profiles with explicit responsibilities and scoped collaboration.
- Maintain a reusable guest registry and event-specific participation records.
- Support both guest self-service RSVP through secure invitation links and staff-recorded responses.
- Model venues as spatial resources: rooms, zones, rows, individual positions, and count-based capacity pools.
- Provide assisted/manual seating allocation and explainable constraint-based optimization.
- Deliver personalized guest information, QR-based check-in, and role-specific live operations views.
- Make forms, catalogues, services, equipment, pricing, workflow rules, and branding administratively configurable and versioned.
- Run on infrastructure controlled by the deploying organization, with only explicitly selected public endpoints exposed.

## Architecture at a glance

- Frontend: Vue 3, TypeScript, Vite; separate staff and guest-facing experiences.
- Backend: Fastify + TypeScript API, organized as a modular monolith.
- Data: PostgreSQL; API-authoritative access, migrations and versioned reference data.
- Spatial UI: SVG-based floor-plan editor and map rendering.
- Realtime: WebSockets backed by a transactional outbox.
- Optimization: isolated C++ service using Google OR-Tools CP-SAT.
- Deployment: self-hosted Linux; Docker is not a mandatory architectural dependency.

See [Project state](docs/PROJECT_STATE.md), [Architecture](docs/ARCHITECTURE.md), [Roadmap](docs/ROADMAP.md), [MVP Scope](docs/product/MVP_SCOPE_v0.1.md), [Roles and Permissions](docs/product/USER_ROLES_AND_PERMISSIONS_v0.1.md), [API contract review](docs/api/API_CONTRACT_REVIEW_v0.2.md), [Database review](docs/database/DATABASE_REVIEW_v0.2.md), [Migration conventions](docs/database/MIGRATION_CONVENTIONS.md), [Design reconciliation](docs/DESIGN_RECONCILIATION_v0.2.md), [Blueprint v1.2](docs/blueprint/v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md), [Implementation Design v0.2](docs/implementation-design/v0.2/), and [Architecture decisions](docs/decisions/).

## Repository layout

```
apps/                 Staff web (initial slice), guest portal, check-in PWA, API and workers
services/             C++ optimization service
packages/             Shared domain, contracts, UI and infrastructure packages
database/             Migrations, seeds and schema reference
docs/                 Product, architecture, decisions and operational docs
infra/                Deployment, reverse proxy, backup and service definitions
tests/                Unit, integration, end-to-end, security and solver tests
```

Directories will be introduced as their corresponding implementation work begins.

## Development status

The accepted design baseline now has 38 ordered PostgreSQL migrations, a canonical OpenAPI v0.3 contract, a Fastify API/worker foundation and an initial Vue staff workspace. These are under review on draft PR #27; no production database deployment has been established, and the full booking/event product remains incomplete.

## Security and data handling

Never commit real guest personal data, invitation tokens, credentials, private keys, production exports, or sensitive venue/security material. Use synthetic fixtures. The source venue floor-plan workbook and other sensitive source materials remain outside this repository unless explicitly reviewed and approved for publication here.

## Contributing

Read [AGENTS.md](AGENTS.md) and [CONTRIBUTING.md](CONTRIBUTING.md) before making changes. Architectural changes require an ADR under `docs/decisions/`.
