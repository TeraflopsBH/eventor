# PostgreSQL schema review — v0.2

**Review date:** 2026-11-10  
**Status:** initial static structural review; PostgreSQL parser/runtime validation remains outstanding  
**Source:** `docs/implementation-design/v0.2/eogp_schema_v0.2.sql`  
**Related issues:** [#2](https://github.com/TeraflopsBH/eventor/issues/2), [#12](https://github.com/TeraflopsBH/eventor/issues/12), [#13](https://github.com/TeraflopsBH/eventor/issues/13), [#10](https://github.com/TeraflopsBH/eventor/issues/10)

## 1. Executive result

The v0.2 SQL is a useful design starter, but it is **not ready to become the initial production migration**. Its high-level table and foreign-key structure is mostly internally connected, but important multi-tenant, scheduling, optional-module and operational ownership constraints remain incomplete.

### Static structural checks

| Check | Result |
|---|---:|
| Consolidated CREATE TABLE definitions | 86 |
| Duplicate table names | 0 |
| Foreign-key constraints found | 206 |
| Composite foreign-key constraints | 121 |
| Referenced tables/columns found | No missing targets found by the static scanner |
| Foreign-key referenced columns backed by PK/unique constraints | No missing unique targets found by the static scanner |
| Forward references to tables declared later | 0 |
| Explicit CREATE INDEX statements | 17 |
| Duplicate index names | 0 |
| organization_id columns declared nullable | 0 |
| CREATE POLICY / ENABLE ROW LEVEL SECURITY | 0 |
| CREATE TRIGGER | 0 |
| Exclusion constraints for time overlap | 0 |

The checks above were performed with a lightweight structural scanner, not the PostgreSQL parser or server. They establish useful structural consistency, **not SQL syntax validity, successful PostgreSQL execution, correct query plans, concurrency safety or production readiness**.

The working environment did not have `psql`, a PostgreSQL server, Docker, or a PostgreSQL parser library available. An offline attempt to obtain a parser could not access the package index. Therefore no PostgreSQL execution test is claimed.

## 2. Packaging and migration concerns

### 2.1 The consolidated file contains two transaction blocks

The consolidated SQL contains the core schema and booking/configuration extension in one physical file, but it has two separate `BEGIN`/`COMMIT` pairs and two `SET search_path` statements. This reflects its historical assembly from two design sections.

For a migration system, split this into ordered, independently checksummed migrations. Do not preserve nested or repeated transaction boundaries inside a single migration runner's transaction.

### 2.2 search_path is session-scoped

The file uses `SET search_path = eogp, public`, not `SET LOCAL`. A session-level setting can persist after COMMIT and contaminate a reused migration connection.

Use schema-qualified identifiers where practical and transaction-local search-path configuration where necessary:

```sql
BEGIN;
SET LOCAL search_path TO eogp, public;
-- migration statements
COMMIT;
```

### 2.3 Version labels are inconsistent

The file is named v0.2, but its header identifies the core schema as v0.1 and the booking portion references a v0.1 predecessor. Preserve the historical v0.2 file as a reference; new migrations should use a clean versioned migration history and not append to this starter.

### 2.4 Duplicate booking addendum

The original package's separate 22-table booking addendum is already included in the consolidated 86-table file. All 22 table names overlap. Applying both files would attempt to recreate those tables. The duplicate addendum is not a second migration.

## 3. Blocking model gaps

### 3.1 Cross-organization venue-provider and organizer ownership

ADR 0004 allows a venue provider and event organizer to be different organizations. The v0.2 schema generally assumes one `organization_id` owns both sides of a relationship:

- `booking_records.linked_event_id` references `events` using the booking's same `organization_id`.
- `event_session_spaces` uses one `organization_id` for both the event session and venue-space revision.
- Event guest allocations reference allocation resources under the same `organization_id`.
- Venue geometry and event operations therefore cannot be independently owned by a venue provider and organizer and still retain these composite foreign keys.

This prevents a natural case: GHB owns its venue, space revisions and booking; the conference organizer owns the operational event, guests, invitations and attendance.

Do not solve this by copying the organizer's guest data into the venue provider's tenant. The successor model needs separate owner identifiers on cross-organization relationships, revision-pinned venue references, explicit collaboration grants and distinct data projections. Track this in [Issue #12](https://github.com/TeraflopsBH/eventor).

### 3.2 Tenant-scoped self-references

Two self-references are currently single-column foreign keys:
- `persons.merged_into_person_id -> persons(id)`
- `guest_credentials.replaced_by_credential_id -> guest_credentials(id)`

They do not enforce that source and target rows belong to the same organization. Add composite tenant-scoped references in the successor schema.

### 3.3 Venue hierarchy consistency

`venue_spaces` independently references a venue, building and level. Its constraints establish that each row belongs to the organization, but do not prove that the selected building belongs to the selected venue or that the selected level belongs to the selected building. Introduce composite keys/foreign keys that enforce the full hierarchy.

### 3.4 Catalogue option revision integrity

`config_catalogue_revision_options` references the stable option and the option revision independently. It does not enforce that the selected `option_revision_id` belongs to the selected `option_id`. The successor schema should enforce this pairing and the relevant catalogue relationship.

### 3.5 Polymorphic scope references

Several tables store `scope_type` plus `scope_id`, including role grants, brand profiles, document templates, catalogues, booking forms and price lists. The database cannot validate the referenced table/entity from a generic UUID column.

For each use, either add a normalized scope relation/registry or document and test a deliberately chosen application-integrity boundary. Organization-level scopes should be constrained to the organization; venue/event scopes must be checked against the same owner or an approved cross-organization grant.

### 3.6 Scheduling and resource reservation safety

- `booking_space_reservations` has a normal overlap-search index, not a database exclusion constraint or equivalent concurrency-safe guard.
- `booking_holds` is a separate table and is not constrained against confirmed space reservations. A hold and a confirmed reservation could overlap unless the application serializes every competing operation correctly.
- `booking_resource_lines` records requested/approved/delivered equipment, personnel and service lines, but does not identify a concrete reservable equipment/personnel unit or protect its time-slot availability.
- No exclusion constraint was found in the v0.2 DDL.

The successor model must protect space holds and reservations atomically under concurrency, and must define a resource-unit/quantity scheduling model for equipment and personnel. A normal B-tree index is useful for lookup but does not prevent overlapping reservations. See [Issue #13](https://github.com/TeraflopsBH/eventor).

### 3.7 Event modules and responsibility

- `events.checkin_enabled` defaults to `true`, which conflicts with ADR 0004's rule that check-in and other operational modules are optional. New event/module configuration should default off unless explicitly enabled.
- `event_prerequisites` records a coordinator and external party text but has no explicit accountable organization/party, performer/approver responsibility assignment or scoped collaborator reference.
- The operating model needs module-level responsibility and access grants; a booking must not automatically expose the event guest list or organizer-only prerequisites to a venue provider.

### 3.8 RSVP and invitation separation

The v0.2 `event_guests.rsvp_status` mixes invitation status, response status and waitlist state. `guest_credentials` combines portal/admission/staff-assist purposes, while `notification_deliveries` is not linked to an invitation entity.

The successor invitation and RSVP model is specified in [v0.3 design](../implementation-design/v0.3/RSVP_AND_INVITATION_DESIGN_v0.3.md) and ADR 0005. Its implementation is tracked in [Issue #10](https://github.com/TeraflopsBH/eventor).

## 4. Security and authorization findings

- No RLS enablement or policies are present in the v0.2 DDL.
- No immutable-history triggers are present for published form/catalogue revisions, inquiry snapshots, audit records, RSVP responses or operational history.
- Many actor columns reference global `users(id)` directly. This is compatible with a global user identity model, but it does not prove the actor is a member of the row's organization or holds the required event permission. The service layer and/or relational grants must enforce this and tests must exercise it.
- The `role_permissions` join table has no organization_id; this is acceptable only if permissions are intentionally platform-global and organization-owned roles remain the scoped side of the relationship.
- Public projections, cross-organization event links, background jobs, files, notifications and WebSocket subscriptions must all enforce the same organization and module boundaries.

RLS policies must be tested using the actual non-owner runtime role, not the migration/schema-owner role. If a transaction-local organization context is used, verify it cannot leak between pooled connections or be supplied directly by an untrusted client.

## 5. Migration convention

See [Migration Conventions](MIGRATION_CONVENTIONS.md). The v0.2 file should remain a reviewed design reference. After issues #12 and #13 are designed, derive a clean successor schema and implement ordered migrations. Do not label the current starter as an executable production migration.

## 6. Required validation before closing Issue #2

1. Resolve cross-organization ownership and linking in Issue #12.
2. Resolve relational tenant integrity and reservation constraints in Issue #13.
3. Align invitation/RSVP structures with v0.3 design and Issue #10.
4. Split the baseline into ordered migrations and remove the historical double-transaction/search-path packaging.
5. Select and pin a supported PostgreSQL major version.
6. Parse and execute every migration against a disposable fresh PostgreSQL database.
7. Test upgrade from the immediately preceding schema version.
8. Test constraints with intentionally invalid cross-tenant, invalid hierarchy, mismatched option-revision and overlapping reservation fixtures.
9. Apply migrations as the migration role; exercise all tenant read/write paths as a non-owner runtime role with RLS enabled.
10. Exercise rollback/recovery using backups and forward corrective migrations; do not assume destructive down-migrations are safe.
