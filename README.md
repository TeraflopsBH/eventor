# Eventor

**Event Operations & Guest Logistics Platform (EOGP)**

Eventor is a self-hosted, API-first platform for managing event inquiries and bookings, guest records, invitations and RSVP, spatial allocation, check-in, and live event operations.

The first reference deployment is planned for **Gazi Husrev-beg's Library (GHB), Sarajevo**. The product is being designed as a reusable organization- and venue-aware platform rather than a one-off GHB application.

 > **Project status:** design baseline imported and initially reconciled; Phase 0 technical validation is still open. No production application implementation is present yet.

## Product goals

- Manage venue inquiries, booking drafts, offers/approvals, and confirmed bookings as distinct records and workflow stages.
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

See [Project state](docs/PROJECT_STATE.md), [Architecture](docs/ARCHITECTURE.md), [Roadmap](docs/ROADMAP.md), [Design reconciliation](docs/DESIGN_RECONCILIATION_v0.2.md), [Blueprint v1.2](docs/blueprint/v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md), [Implementation Design v0.2](docs/implementation-design/v0.2/), and [Architecture decisions](docs/decisions/).

## Repository layout

```
apps/                 Staff web, guest portal, check-in PWA, API and workers
services/             C++ optimization service
packages/             Shared domain, contracts, UI and infrastructure packages
database/             Migrations, seeds and schema reference
docs/                 Product, architecture, decisions and operational docs
infra/                Deployment, reverse proxy, backup and service definitions
tests/                Unit, integration, end-to-end, security and solver tests
```

Directories will be introduced as their corresponding implementation work begins.

## Development status

The initial design baseline is being consolidated from the product blueprint and implementation design. Database schemas and API specifications are design artifacts until validated by automated checks and implemented migrations. Do not treat them as deployed or production-ready.

## Security and data handling

Never commit real guest personal data, invitation tokens, credentials, private keys, production exports, or sensitive venue/security material. Use synthetic fixtures. The source venue floor-plan workbook and other sensitive source materials remain outside this repository unless explicitly reviewed and approved for publication here.

## Contributing

Read [AGENTS.md](AGENTS.md) and [CONTRIBUTING.md](CONTRIBUTING.md) before making changes. Architectural changes require an ADR under `docs/decisions/`.
