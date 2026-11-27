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

## Planned Template Design Studio (Phase 7)

See [Template Design Studio v1.0](implementation-design/v0.3/TEMPLATE_DESIGN_STUDIO_DESIGN_v1.0.md) and [#111](https://github.com/TeraflopsBH/eventor/issues/111). Three authoring modes share revisioned templates, brand/assets, locale variants, typed purpose-specific data bindings and audit. Extend existing notification template identities and delivery paths; do not create a competing email aggregate. Server-authoritative rendering uses a bounded isolated worker with private artifacts and no general network or database access. Preview, render and publication never issue credentials or trigger delivery; existing domain commands remain authoritative. Specific editor/renderer libraries and schema/API design require the M0 review and ADR. This is planned functionality, not current runtime or a change to implementation order.

## Planned Platform Administration Center

See [PAC v1.0](implementation-design/v0.3/PLATFORM_ADMINISTRATION_CENTER_DESIGN_v1.0.md). Separate deployment-level management session/ingress, safe global metadata and explicit scoped tenant transitions under the real actor; reuse existing identity, memberships, domain services and TDS brand/asset revisions. Host-only bootstrap and recovery remain outside runtime. Typed approved host operation requests are not shell execution; no owner/migrator credentials, root or unrestricted Docker socket in the web app. Existing ADRs 0015/0017/0020 remain accepted; proposed managed-permission reconciliation requires a reviewed successor ADR, populated upgrade, independent-grant preservation and recovery tests before any implementation. This is planned scope, not a runtime claim or priority change.

## Organization Administration Center and shared experience (approved scope, 2026-11-27)

See [OAC v1.0](implementation-design/v0.3/ORGANIZATION_ADMINISTRATION_CENTER_DESIGN_v1.0.md), [UX v1.0](implementation-design/v0.3/EVENTOR_USER_EXPERIENCE_AND_NAVIGATION_v1.0.md) and [organization lifecycle acceptance v1.0](implementation-design/v0.3/ORGANIZATION_LIFECYCLE_ACCEPTANCE_SCENARIOS_v1.0.md). PAC, OAC and EOC are separate authorization/context boundaries in the same modular monolith, not independent products or a chain of inherited privileges. PAC provisions the organization and first administrator; OAC owns tenant self-service orchestration, readiness, permission-filtered overview and navigation; EOC owns the selected event operational experience. Reuse existing domain commands and data models, shared TDS brand/assets, notification and identity services; readiness is derived from server-validated configuration per capability, not an editable checklist. ADR 0008 requires incremental shell/composable/feature evolution; navigation hints never authorize actions. Preserve ADR 0015 and PAC's proposed successor authority review. Owner approved the three v1.0 scopes for documentation integration on 2026-11-27. The three reviewed source files are preserved verbatim, including their historical proposed-status text; this approval record governs their integration status, not approval of exact engineering decisions or immediate implementation. Existing accepted ADRs, historical Blueprint v1.2/v0.2 snapshots, issue obligations and current #104/#112 → #105–107 priorities remain unchanged. No runtime implementation or acceptance results are implied.

## Admission, guest information and station management — approved scope (2026-11-27)

[AGIS v1.0](implementation-design/v0.3/ADMISSION_GUEST_INFORMATION_AND_STATION_MANAGEMENT_DESIGN_v1.0.md) establishes six purpose-bound station modes in the existing API-first modular monolith: entrance/gate, self-service and staffed Info Pult, seating assistance, printing and passive information display. PAC governs deployment policy and recovery; OAC owns tenant station/profile/device administration; EOC owns event/session assignments and live operations. Reuse migration 000014 admission credentials, check-in stations/attempts and attendance records, allocation revisions, guest portal, TDS brand/assets/rendering and transactional outbox. Audit current SQL and runtime boundaries before adding compatible extensions. No parallel attendance, identity, spatial or rendering engine. Staff, station/device, kiosk guest and public display contexts have independent server-enforced scope. A lookup, RSVP, preview or print never records attendance; only the authorized check-in command can do so. Separate online authority, encrypted bounded deferred capture and time-limited local-validation packages per Blueprint §13.4; offline validation is provisional until reconciled. Station Designer uses typed allowlisted components and actions, not arbitrary code. This is an approved scope clarification, not a runtime implementation claim or instruction to interrupt the existing #104/#112 → #105–107 sequence. Preserve accepted ADRs, historical Blueprint v1.2, existing domain commands and issue criteria; final integrated acceptance remains Phase 9.
