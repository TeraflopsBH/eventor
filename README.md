# Eventor

**Event Operations & Guest Logistics Platform (EOGP)**

Eventor is a self-hosted, API-first platform that can be used for venue booking/resource management alone, full event organization and operations, or a configurable combination. Guest records, invitations/RSVP, seating, check-in and event-day operations are optional capabilities—not requirements for every venue booking.

The first reference deployment is planned for **Gazi Husrev-beg's Library (GHB), Sarajevo**. The product is being designed as a reusable organization- and venue-aware platform rather than a one-off GHB application.

> **Project status:** accepted design baseline; 64 PostgreSQL 18 migrations, the canonical OpenAPI v0.3 contract, a Fastify staff API/notification-worker foundation and an initial Vue 3 staff workspace are present on draft PR #27. Migrations 000040–000041 provide published-form retrieval and encrypted, idempotent, rate-limited public inquiry submission. Migration 000042 and the API provide permissioned staff inquiry inbox/detail, assignment, review-status changes, internal annotations and immutable histories. Migration 000043 adds exact published-revision lookup and server-side field-schema v1 answer validation. Migration 000044 adds permission-gated assignment roster and inquiry capability projections. Migration 000045 atomically converts an open inquiry into a separate booking draft with immutable revision 1, preserving the encrypted submission snapshot and appending status history/audit records. Migration 000046 adds organization-scope `booking.draft.read`/`booking.draft.manage` permissions, protected draft projections, immutable successor revisions, ECP1 encryption, optimistic concurrency and active-hold checks. The staff UI now supports authorized draft reading/editing with revision history. The commercial offer/approval workflow, versioned price lists and cancellation/tax configuration are implemented in stacked draft PRs #28–#33; per-adjustment tax classification and allocation are included in PR #33. The wider venue-booking application remains incomplete. Recent GitHub Actions runs failed before runner assignment (`runner_id: 0`, no steps or logs), so current-head code validation is still outstanding.

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

The accepted design baseline now has 46 ordered PostgreSQL migrations, a canonical OpenAPI v0.3 contract, a Fastify staff API plus notification workers, and the initial Vue staff workspace for authentication, organization SMTP configuration, notification campaigns and booking inquiry review. PR #27 adds encrypted/idempotent/rate-limited public inquiry intake, permissioned staff inquiry review APIs, exact published-revision lookup, field-schema v1 validation, a permission-gated assignee roster/capability projection, and the staff inbox/detail/assignment/status/internal-note/history interface. Atomic inquiry-to-draft conversion and immutable successor draft revisions now exist, including the protected staff draft editor. The commercial offer/approval and booking confirmation workflow is implemented in stacked draft PRs #28–#33; production validation remains outstanding. The latest fully green three-job CI run (#43027314682) predates migrations 000039–000046. Recent Actions attempts failed before runner assignment and never started steps, so PR #27 has not received current-head end-to-end validation. No production database deployment has been established.

## Security and data handling

Never commit real guest personal data, invitation tokens, credentials, private keys, production exports, or sensitive venue/security material. Use synthetic fixtures. The source venue floor-plan workbook and other sensitive source materials remain outside this repository unless explicitly reviewed and approved for publication here.

## Contributing

Read [AGENTS.md](AGENTS.md) and [CONTRIBUTING.md](CONTRIBUTING.md) before making changes. Architectural changes require an ADR under `docs/decisions/`.
