# Database integrity and resource reservation design — v0.3

**Status:** accepted integrity design baseline for successor DDL; exact schema and runtime validation remain open  
**Date:** 2026-11-10  
**Parent reference:** v0.2 schema starter  
**Related:** [Issue #13](https://github.com/TeraflopsBH/eventor/issues/13), [Issue #2](https://github.com/TeraflopsBH/eventor/issues/2), [ADR 0004](../decisions/0004-optional-event-operations-scope.md), [ADR 0006](../decisions/0006-cross-organization-collaboration.md)

This proposal does not modify the historical v0.2 SQL snapshot. Its purpose is to define the integrity patterns that a reviewed successor schema must implement and test.

## 1. Design principles

1. Use database constraints for invariants that can be represented relationally.
2. Every tenant-owned row has one explicit owner organization. A same-tenant relationship uses a composite organization-scoped foreign key.
3. A cross-organization relationship is a separate, explicit domain relationship with its own owner identifiers and scoped grant; it is never represented by weakening an existing tenant FK to a bare UUID.
4. Avoid polymorphic `scope_type + scope_id` references where the target is a known table and can be represented by typed foreign keys.
5. Resolve availability and capacity conflicts within the same transaction that commits a hold/reservation.
6. A venue-only booking does not depend on event, guest, RSVP, check-in or other organizer modules.
7. Event module/task ownership is explicit. A global user identity alone does not prove the user is authorized to act for a given organization.

## 2. Tenant-scoped self-references

The v0.2 tables `persons` and `guest_credentials` already have `UNIQUE (organization_id, id)`, but self-references use only the UUID.

Successor constraints:
- Replace `persons.merged_into_person_id REFERENCES persons(id)` with a composite FK `(organization_id, merged_into_person_id) -> persons(organization_id, id)`.
- Replace `guest_credentials.replaced_by_credential_id REFERENCES guest_credentials(id)` with `(organization_id, replaced_by_credential_id) -> guest_credentials(organization_id, id)`.
- Keep nullable targets nullable; a null target means no merge/replacement. Ensure state checks require a target only where the lifecycle semantics require one.
- Add tests proving a person/credential in organization A cannot point to a row in organization B.

The same pattern applies to any future tenant-owned parent/child or supersedes/replaces reference.

## 3. Venue hierarchy consistency

The current `venue_spaces` row separately points to `venue_id`, optional `building_id` and optional `level_id`. Existing FKs prove each object belongs to the organization, but not that the building belongs to the selected venue or the level belongs to the selected building.

### 3.1 Required candidate keys

Add composite candidate keys:
- `venue_buildings(organization_id, venue_id, id)`.
- `venue_levels(organization_id, building_id, id)`.

Then use:
- Existing `(organization_id, venue_id) -> venues`.
- `(organization_id, venue_id, building_id) -> venue_buildings(organization_id, venue_id, id)`.
- `(organization_id, building_id, level_id) -> venue_levels(organization_id, building_id, id)`.

The final FK requires nullable hierarchy to be internally consistent. Use a CHECK so `level_id IS NOT NULL` implies `building_id IS NOT NULL`. A space without a building/level remains valid if that is a supported venue layout. If a space has a building but no level, that can be allowed where the model requires it.

Tests must reject:
- Building from another venue in the same organization.
- Level from another building in the same organization.
- Building/level from another organization.
- Level without a building.

## 4. Catalogue option revision consistency

Current v0.2 structure:
- `config_catalogue_options` belongs to one catalogue.
- `config_catalogue_option_revisions` belongs to one stable option.
- `config_catalogue_revision_options` references catalogue revision, stable option and option revision independently.

This permits a catalogue revision to pair option A with option B's revision, or to pair an option from a different catalogue, because independent FKs do not prove the identities match.

### 4.1 Relational design

Add `catalogue_id` to `config_catalogue_option_revisions` as a controlled redundant key and enforce it with:
- `UNIQUE (organization_id, catalogue_id, option_id, id)`.
- Composite FK `(organization_id, catalogue_id, option_id) -> config_catalogue_options(organization_id, catalogue_id, id)`.

Ensure `config_catalogue_revisions` has `UNIQUE (organization_id, catalogue_id, id)`.

Add `catalogue_id` to `config_catalogue_revision_options`; enforce:
- `(organization_id, catalogue_id, catalogue_revision_id) -> config_catalogue_revisions(organization_id, catalogue_id, id)`.
- `(organization_id, catalogue_id, option_id, option_revision_id) -> config_catalogue_option_revisions(organization_id, catalogue_id, option_id, id)`.

The stable option identity, selected option revision and containing catalogue revision then have to match. A trigger is not needed for this identity check. The migration must backfill `catalogue_id` from the existing option relationship and fail if historic rows are inconsistent.

## 5. Polymorphic scope references

The v0.2 pattern `scope_type + scope_id` appears in several places. A CHECK validates the type string but cannot prove that `scope_id` points to a row in the correct table or belongs to the same organization.

### 5.1 Keep a type when it is only a capability category

`roles.scope_type` describes the kinds of scopes where a role can be granted. It does not point to a particular event/venue/space row. A constrained enum/check is appropriate.

### 5.2 Replace polymorphic target IDs with typed nullable FKs

For records that point to a specific known entity, prefer explicit columns and checks:
- `user_role_grants`: `scope_event_id`, `scope_venue_id`, `scope_space_id`, `scope_station_id`, plus a scope-type CHECK requiring exactly the matching target and nulling the others. Organization scope has no target ID.
- `brand_profiles`: `scope_venue_id` or `scope_event_id`; organization scope uses neither.
- `document_templates`: same explicit organization/venue/event scope pattern.
- `config_catalogues`: organization/venue/space/event typed references according to the actual supported domain.
- `booking_form_definitions`: organization/venue/space typed references.
- `booking_price_lists`: organization/venue/space typed references.

Every typed FK includes `organization_id`. If the referenced scope belongs to a different organization, it is not valid through that owner's local scope FK; the cross-organization design uses a grant and event-owned snapshot instead.

This is intentionally more columns/checks than a generic UUID, but the integrity is visible, migration-testable and enforced by PostgreSQL. Consider reusable typed scope tables only if they can retain actual FK enforcement without adding an untestable polymorphic escape hatch.

## 6. Actor identity and organization membership

The v0.2 schema uses global `users(id)` in many `created_by`, `updated_by`, `approved_by` and other actor fields. A user is a login identity and can be a member of several organizations; `users(id)` alone does not prove membership in the organization that owns the record.

### 6.1 Membership-scoped actor reference

For ordinary actions on tenant-owned records:
- Use `organization_memberships` as the acting context.
- Add/use a unique key `(organization_id, id)` and `UNIQUE (organization_id, user_id)`.
- Store `actor_membership_id` (or a normalized actor reference) on tenant-owned audit/business action rows and composite-FK it to `organization_memberships(organization_id, id)`.
- Where the user ID is also stored for immutable display/audit, enforce `(organization_id, actor_user_id) -> organization_memberships(organization_id, user_id)`.

The authorization service must still check role/permission and scope at command time. Membership FKs prove organization membership, not permission to perform the action.

### 6.2 Cross-organization delegated action

A collaborator acting on another organization's task is not a member of the data owner's organization. Do not fake membership or weaken the FK.

Instead, record:
- Target/data-owner organization.
- Actor user and actor membership in the grantee organization.
- Active collaboration grant/task assignment authorizing the operation.
- The operation, resource, time and request ID.

The service verifies both the actor's grantee membership and the active grant. Audit records must retain the acting organization separately from the target data owner.

Background/system actions should use explicit service principals or job identities, not a fabricated human user.

## 7. Space holds and confirmed reservations

### 7.1 Problem

v0.2 has `booking_holds` and `booking_space_reservations` as separate tables. A normal B-tree index can help find overlaps but cannot prevent two concurrent transactions from reserving the same space/time, especially when one row is a hold and the other is a confirmed reservation.

### 7.2 Recommended unified occupancy relation

Use one authoritative relation, candidate name `venue_space_time_blocks`, for every interval that makes a space unavailable. It may cover:
- Temporary hold.
- Confirmed booking block (setup, rehearsal, event, teardown or buffer).
- Maintenance/closure/unavailability block (where facility operations require it).

Columns include:
- Owner organization and venue-space FK.
- Exactly one relevant source reference (inquiry/draft/booking/maintenance as applicable).
- Reservation kind and lifecycle status.
- `starts_at`, `ends_at` as `timestamptz`.
- `expires_at` for temporary holds.
- Actor/audit metadata and idempotency key.
- Optional source draft/booking revision.

Use half-open intervals `[starts_at, ends_at)`, so a booking ending at 12:00 does not conflict with another starting at 12:00. Enforce `ends_at > starts_at`.

### 7.3 Database overlap constraint

Use PostgreSQL range/GiST exclusion to prevent overlapping active blocks for the same venue space:
- Install `btree_gist` through an approved migration.
- Exclusion keys: `organization_id WITH =`, `venue_space_id WITH =`, and `tstzrange(starts_at, ends_at, '[)') WITH &&`.
- Apply the exclusion to active statuses such as held/confirmed/maintenance/blocked. Released, cancelled, consumed or expired blocks do not exclude time.
- Make the constraint deferrable only if a controlled multi-row reschedule needs to swap time blocks within one transaction; default immediate checking is simpler.

An index predicate cannot depend on volatile `now()`. An expired hold must be transitioned to `expired` by a worker and also during every reservation operation for the affected space, before conflict checking. All hold, confirm, extend, release and reschedule commands lock the space row in a consistent order and update the unified relation in one transaction. The exclusion constraint is the final race-condition guard.

If the extension cannot be installed in the target PostgreSQL environment, an alternative must be explicitly designed and tested; do not silently fall back to a normal B-tree overlap index.

### 7.4 Booking confirmation transaction

1. Lock all affected venue-space rows in stable sorted ID order.
2. Mark expired holds for those spaces as expired.
3. Verify current draft/offer/policy revisions and authorization.
4. Insert/transition all required space-time blocks.
5. Let the exclusion constraint detect any overlapping active hold/reservation.
6. Commit booking status, confirmed snapshot and reservation blocks atomically.
7. On any conflict, roll back everything and return a clear conflict response.

Do not create a confirmed booking if only some of its required spaces/time blocks were reserved.


### 7.5 Typed reservation origin references

The unified occupancy row must not reintroduce an unchecked polymorphic `source_type + source_id` pair. Use typed nullable origin columns (for example, `booking_draft_revision_id`, `booking_id` and `maintenance_window_id`) with organization-scoped foreign keys and a CHECK that exactly one supported origin is selected. If the implementation instead introduces a reservation-subject supertype, that supertype must itself contain typed FK targets and enforce the same exactly-one invariant.

Keep the original draft/offer provenance separately where needed; the current occupancy owner is not a substitute for the immutable booking revision or approval snapshot. The chosen origin model must support a hold transitioning to a confirmed booking without creating a gap in occupancy protection.

## 8. Equipment/personnel and count-based resources

The current `booking_resource_lines` correctly captures requested, approved and delivered quantities/values, but a commercial line is not itself a schedule reservation.

Keep commercial/service lines separate from physical resource reservations.

### 8.1 Discrete units

Model bookable assets/personnel units in a normalized resource inventory. A unit reservation contains owner organization, unit ID, booking, interval, quantity (normally one), status and source line. Apply the same half-open GiST exclusion approach per unit to prevent overlapping active reservations.

Examples: a particular projector, wireless microphone set, interpreter booth, vehicle or named staff assignment.

### 8.2 Pooled capacity

For fungible pools (for example 10 identical microphones, 4 technicians, 80 chairs), reserve a quantity against a resource pool and interval.

A simple exclusion constraint cannot enforce a sum of overlapping quantities. Use a single parent resource/pool row as the serialization point:
- Every reserve/change/release operation locks the pool row with `SELECT ... FOR UPDATE` (or a transactionally equivalent lock).
- Expire stale holds.
- Calculate overlapping committed quantity under the agreed conflict policy.
- Reject if `existing + requested > capacity`.
- Insert/update the reservation in the same transaction.
- Use a stable lock order when reserving multiple pools.

Test with concurrent transactions, not only sequential fixtures. For highly contended pools, consider serializable isolation after measuring its retry behavior.

### 8.3 Personnel scheduling

Personnel can be represented as discrete units or skill/capacity pools depending on the operation. Availability, working-hour limits, role qualifications and breaks are separate constraints; they must not be inferred from the presence of a commercial personnel line.


### 8.4 Correct pooled-capacity overlap calculation

The capacity check must evaluate the maximum simultaneous quantity over the requested interval, not simply sum every reservation whose interval intersects it. Two existing reservations may each intersect a long requested interval while not overlapping one another; summing both for the entire interval can falsely reject a valid request.

After locking the pool row, collect the interval boundaries of the requested reservation and all active overlapping reservations, partition the requested interval into adjacent half-open segments, and verify that the sum of active quantities plus the requested quantity never exceeds pool capacity in any segment. Define how zero-duration boundaries are handled consistently with the half-open `[starts_at, ends_at)` convention. Execute the capacity read and insert/update in the same transaction after acquiring the serialization lock; use a stable pool lock order for multi-pool commands.

## 9. Event module defaults and configuration

The v0.2 `events.checkin_enabled` defaults to `true`, contradicting ADR 0004.

Successor design:
- Remove per-feature boolean proliferation where practical.
- Represent module activation through published, versioned event capability settings.
- Event creation begins with only core event identity/session capabilities; guest registry, invitations/RSVP, seating, check-in, guest portal, prerequisites and cockpit are off until explicitly enabled or inherited by an approved event preset.
- Organization operating profile supplies defaults; each event can override.
- A venue booking does not need any event module.
- Module dependencies are explicit (for example, invitation-based RSVP requires guest participation plus guest-facing route; check-in does not require RSVP).
- Configuration changes after activation are revisioned and audited.

If a transitional boolean remains in the migration, it must default false and have one source of truth. Do not keep both `checkin_enabled` and an event-module registry with independent mutable values.

## 10. Event task responsibility

ADR 0004 and ADR 0006 require explicit responsibility. `event_prerequisites` currently has an internal coordinator and an external-party name, but not accountable/performed party assignments.

Add a normalized `event_responsibility_assignments` (candidate name) for module or task:
- Event owner organization.
- Capability/task code and optional task instance reference.
- Accountable party kind: organization, external party or event-owning organization.
- Accountable organization ID or external-party ID (exactly one where applicable).
- Performing organization/person/team, potentially distinct from the accountable party.
- Approver and informed party references as needed.
- Collaboration grant reference where a different Eventor organization is involved.
- Scope of data projection/capabilities for the assigned party.
- Due time, status, evidence/reference and readiness rule as appropriate.

An event prerequisite is one task category using this common responsibility model. A venue setup request may also use it. A third-party operator without an Eventor tenant can remain a named external party; an external login is not required.

The accountable organization is a business assignment recorded by Eventor, not a legal liability decision. The platform must not infer or certify statutory responsibility.

## 11. Integrity validation matrix

| Scenario | Expected database/application result |
|---|---|
| Person A references merged target owned by B | FK rejection |
| Credential A references replacement credential B in another tenant | FK rejection |
| Space references building from another venue | FK rejection |
| Space references level from a different building | FK rejection |
| Level provided without building | CHECK rejection |
| Catalogue revision contains option A paired to option B's revision | FK rejection |
| Event role grant references a venue/space in another tenant without approved grant | FK/application rejection |
| Actor user has no membership in target organization | FK/application rejection |
| User is member but lacks permission | API authorization rejection |
| Concurrent active space holds overlap | One transaction rejected |
| Active hold overlaps a confirmed reservation | One transaction rejected |
| Two concurrent pooled resource reservations exceed capacity | One transaction rejected or retried then rejected |
| Event check-in not enabled | Check-in APIs/UI unavailable |
| Venue-only booking | No operational event/guest/module rows required |
| External event collaborator performs an assigned task after grant revocation | Authorization rejection; historical audit preserved |

## 12. Migration and rollout sequence

1. Select the PostgreSQL major version and ensure required extensions (including `btree_gist`) are available.
2. Resolve cross-organization ownership using the accepted ADR 0006 model and event-owned venue snapshots.
3. Build new typed scope references, tenant-safe self-FKs, venue hierarchy FKs and catalogue composite keys.
4. Add membership-scoped actors and scoped collaboration attribution.
5. Replace separate space holds/reservations with the unified occupancy relation; design data migration for active, historical, cancelled and expired blocks.
6. Add discrete and pooled equipment/personnel reservation structures.
7. Add event module capability revisions and responsibility assignments.
8. Reconcile with invitation/RSVP v0.3 design and Issue #10.
9. Apply migrations to an empty disposable PostgreSQL database and run all positive/negative integrity scenarios.
10. Run concurrency tests using independent database connections and the actual non-owner runtime role.
11. Test upgrade from the prior schema, recovery/backup and grant revocation behavior.
12. Only then close Issues #2 and #13.

## 13. Open implementation choices

The architecture above is recommended. The exact DDL still needs review for:
- PostgreSQL version and extension availability.
- Which space-time block kinds share one exclusion relation.
- Whether equipment/personnel use the same generic resource model or distinct tables over a common reservation abstraction.
- Capacity-pool transaction isolation and retry policy.
- How service principals/jobs are represented consistently in audit.
- Whether typed scope columns should be generated through migration templates or repeated explicitly.

These are engineering choices; they must preserve the invariants and acceptance scenarios above.
