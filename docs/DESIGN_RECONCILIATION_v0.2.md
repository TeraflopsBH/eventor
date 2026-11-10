# Design reconciliation report — Blueprint v1.2 and Implementation Design v0.2

**Review date:** 2026-11-10  
**Status:** initial static reconciliation; implementation contracts remain draft  
**Repository branch:** `docs/import-design-v0.2`

## 1. Source set imported

| Source | Repository path | Disposition |
|---|---|---|
| Technical Blueprint v1.2 | `docs/blueprint/v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md` | Imported as the product/architecture baseline |
| Implementation Design v0.2 | `docs/implementation-design/v0.2/Event_Operations_Implementation_Design_v0.2.md` | Imported as the detailed working design |
| Consolidated SQL v0.2 | `docs/implementation-design/v0.2/eogp_schema_v0.2.sql` | Imported as a schema starter/reference, not a migration |
| OpenAPI v0.2 | `docs/implementation-design/v0.2/eogp_openapi_v0.2.yaml` | Imported as a first API contract draft |
| Backlog v0.2 | `docs/implementation-design/v0.2/EOGP_Backlog_v0.2.csv` | Imported; 64 work items |
| GHB form reference v0.2 | `docs/implementation-design/v0.2/GHB_Rental_Form_Reference_v0.2.csv` | Imported as an unapproved capture of the public form |

The Markdown design documents remain the historical v1.2/v0.2 snapshots. Future corrections should be issued as a new version or explicit addendum.

## 2. Reconciliation findings

### 2.1 Architecture and product scope — aligned

The detailed design is consistent with the Blueprint v1.2 on the principal architectural choices:

- API-first modular monolith with PostgreSQL as the authoritative store.
- Vue/TypeScript staff and guest-facing clients; Fastify/TypeScript API and workers.
- Self-hosted, intranet-first deployment with explicitly exposed public routes.
- Persistent person registry separated from event-specific participation.
- Versioned venue/spatial plans and the distinction between physical features, spatial regions, allocation resources and capacity pools.
- Solver-generated allocations are proposals; authorized humans preview and explicitly commit.
- Organization → venue → event branding inheritance.
- CDI represented only as an externally performed prerequisite/coordination record.
- Venue inquiry, editable booking draft, offer/approval, confirmed booking and optional operational event remain distinct.
- Organization-specific forms, catalogues, prices, services and workflow choices are versioned data rather than hardcoded enums.

No architectural reason was found to replace the modular-monolith baseline with microservices.

### 2.2 SQL package contains a duplicate booking addendum — resolved for import

The v0.2 source package provides both:

- `eogp_schema_v0.2.sql`: 86 `CREATE TABLE` definitions.
- `eogp_booking_schema_addendum_v0.2.sql`: 22 `CREATE TABLE` definitions.

A name-level comparison found that **all 22 addendum table definitions are already present in the consolidated schema**. The consolidated file consists of 64 core definitions plus the 22 booking/configuration definitions. The README's stated total of 86 is therefore consistent with the consolidated file, but the package's suggestion that the separate addendum should be appended to the core schema is unsafe when the consolidated v0.2 file is used.

**Disposition:** the consolidated `eogp_schema_v0.2.sql` is imported. The separate duplicate addendum is not copied as an executable file. Its source SHA-256 is `44bc1aa2c31e69898f210ab1da8bfd5065da0eacd131f59545671d0b3c545117`.

Additional labeling inconsistency: the consolidated file is named v0.2 but its opening comments identify the core starter as v0.1; the embedded extension comments also refer to appending after a v0.1 file. Preserve the historical import for traceability and correct the version/migration packaging in a reviewed successor artifact.

### 2.3 RSVP/invitation lifecycle is incomplete — follow-up required

The previous product decisions require both guest self-service RSVP and staff-recorded responses. Current v0.2 artifacts do not yet define that flow sufficiently:

- `event_guests.rsvp_status` stores a current status, but not response source, timestamp, staff operator, notes or response history.
- `guest_credentials` distinguishes `guest_portal` and `admission_qr` credentials, but the design does not define a full invitation issuance/delivery/reminder/revocation lifecycle.
- OpenAPI has guest portal token resolution and allocation retrieval, but no guest RSVP response/update endpoint and no explicit staff-recorded RSVP command.
- The current design does not fully specify RSVP deadlines, response changes, reminders, response states or manual-capture permissions.
- RSVP is conceptually distinct from check-in, but the schema/API contract must enforce that distinction and preserve the audit trail.

**Disposition:** recorded as [Issue #6](https://github.com/TeraflopsBH/eventor/issues/6). Do not implement invitations or RSVP only from the current `rsvp_status` field. The next design revision must specify the lifecycle, response history, delivery records, token purpose/scope, state transitions and API commands.

### 2.4 Booking lifecycle — consistent, with implementation gaps

The v0.2 design correctly separates the original inquiry from a working booking draft, offers and confirmed booking. It also distinguishes requested, approved and delivered values, and treats confirmation as an atomic resource reservation command.

The resource model is not yet a complete production inventory/calendar implementation. Shared equipment/personnel reservation behavior, post-confirmation amendments/change orders, and all concurrency controls remain explicit implementation/review tasks in the SQL comments and backlog. Rehearsal/setup/teardown are intended to be separate time blocks; the captured GHB request form currently asks only whether a rehearsal is wanted and provides no captured rehearsal date/time fields.

### 2.5 GHB form capture — reference only

The CSV contains 21 captured controls/fields. All 21 have `html_required_property=false` and were visible in the initial DOM snapshot. The field `datum-vrijeme` was captured as a text input, not a typed date/time control. The shared `Vrsta upita` selector includes general-contact options as well as a rental option; it is not itself a rental-specific field.

The extracted blank-state DOM does not establish whether controls become conditionally visible after user interaction. Conditional form behavior should be configured and tested only when verified. The GHB reference form lists the large hall as 206 places; other material has described a different large-hall capacity. Capacity, room names, public-rental eligibility, form choices, current prices, discounts and operational policy all require GHB confirmation.

**Disposition:** the CSV is committed as an unapproved source snapshot. It is not seed data and must not be treated as a policy or source of truth for capacity or pricing.

### 2.6 Venue plan material — deliberately excluded

The original workbook is a grid-like drawing, not a clean seat table. The separate observations register includes provisional zone counts and labels for special spatial features. These are useful review notes, but the capacities and interpretation are not approved.

**Disposition:** source XLSX, rendered workbook image and observations CSV remain outside GitHub until an authorized venue review determines what can be safely shared and what native geometry/capacity is approved. The application must preserve the source-to-native traceability and must not convert every cell or number into an allocation resource.

## 3. Validation performed

| Artifact/check | Result | Limitation |
|---|---|---|
| Blueprint Markdown | Imported | Historical source snapshot |
| Implementation Design Markdown | Imported | Historical source snapshot |
| OpenAPI YAML | Parsed with PyYAML 6.0.3; 36 paths, 46 operations, 46 unique operation IDs | Not yet run through a full OpenAPI 3.1.1 semantic validator or contract tests |
| Backlog CSV | 64 data rows | Backlog priorities/dependencies still require MVP review |
| GHB rental-form CSV | 21 data rows | Public form capture; current behavior and policy unconfirmed |
| Consolidated SQL | 86 table definitions; booking addendum overlap checked (22/22) | Not executed; no PostgreSQL server/client was available in the validation environment |
| SQL security controls | Confirmed no active `CREATE POLICY`, `ENABLE ROW LEVEL SECURITY` or trigger definitions in the starter | Source comments explicitly defer tenant RLS and immutability enforcement |

The source package's stated validation of the OpenAPI parse, path count and CSV counts was independently reproduced. A full semantic OpenAPI validator, SQL parser/runtime test and disposable PostgreSQL migration test remain outstanding.

## 4. Security and production gates

Before production use, the design/schema must be extended and tested for:

1. Tenant RLS policies for every tenant-owned table, tested as the non-owner runtime database role; application authorization remains mandatory.
2. Immutable published form/catalogue/price revisions, inquiry snapshots, issued offers and audit history.
3. Explicit invitation and RSVP response history, token storage/revocation and staff-capture audit.
4. Booking confirmation concurrency, exclusion/overlap handling and atomic reservation of all enabled resources.
5. Upload quarantine, public endpoint rate limits/anti-automation, safe serializers and data-retention/deletion rules.
6. Backup/restore, migration ordering and deployment-specific secrets/roles.
7. GHB approval of public-form choices, capacities, spatial geometry, prices, venue policy and public exposure.

## 5. Next work sequence

1. Complete [Issue #6](https://github.com/TeraflopsBH/eventor/issues/6) and update the RSVP data model/API contract in a successor design version.
2. Complete [Issue #2](https://github.com/TeraflopsBH/eventor/issues/2): review consolidated schema, correct versioning/packaging, validate DDL and establish real migrations.
3. Complete [Issue #3](https://github.com/TeraflopsBH/eventor/issues/3): full OpenAPI validation and domain/security contract reconciliation.
4. Complete [Issue #4](https://github.com/TeraflopsBH/eventor/issues/4): MVP scope, roles and acceptance scenarios.
5. Only then establish implementation package boundaries and begin the platform foundation.

## 6. Source fingerprints

Original package checksums for imported files:

- Blueprint v1.2 Markdown: `3ebb97dab8d5b596cb1b05d1b8f8cdf96578ec4cdccff6cf4d67dded41112728`.
- Implementation Design v0.2 Markdown: `b81eb1a90cea4d4989ebefca65a4cbb5b3cafb960be5265f0d1925698f448b73`.
- Consolidated SQL v0.2: `3ca75c855d5bf49566a40807f722de8ea38785042f50f2094e7ee27014c9b7f7`.
- OpenAPI v0.2: `99289459b27e8721e1c453b42cebf0a98c705a651ebd3472616e29fd1cba40d3`.
- Backlog CSV v0.2: `491c26b56cea336688e028acff23aa4390b416165ed9f883469340a9ae6eebd7`.
- GHB form reference CSV v0.2: `0ecea44a2289f2c8fbb1e801d45bef2db0b671e29a82043a794403ef7ded18b9`.

Note: the Files content export normalizes text/newlines, so the GitHub Markdown/CSV copies are content imports but should not be represented as byte-for-byte archive copies. The SQL and OpenAPI fingerprints above refer to the original package artifacts.
