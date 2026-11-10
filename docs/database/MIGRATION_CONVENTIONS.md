# PostgreSQL migration conventions

**Status:** proposed baseline for implementation; requires confirmation against the selected PostgreSQL major version.

These conventions apply once the logical schema has been reconciled. The imported v0.2 SQL remains a reference and must not be placed directly into production as-is. See [Database Review v0.2](DATABASE_REVIEW_v0.2.md).

## 1. Migration files and history

- Use ordered, immutable, human-readable migration names, for example `000001_create_organization_core.sql`.
- A migration is applied once and recorded in a migration ledger with version, filename, checksum, applied timestamp, execution duration and runner identity.
- Never silently edit a migration already applied to any shared environment. Correct it with a new forward migration.
- Keep schema changes and data migrations explicit. Large/backfill operations should be separately planned and observable.
- Do not use `CREATE TABLE IF NOT EXISTS` as a substitute for migration ordering; unexpected schema drift must fail visibly.
- Migrations should be deterministic and safe to rerun only where the runner explicitly supports that behavior.

## 2. Transaction and search-path rules

A normal migration should own one transaction:

```sql
BEGIN;
SET LOCAL search_path TO eogp, public;

-- DDL / DML for this migration only.

COMMIT;
```

- Prefer schema-qualified object names for security-sensitive or ambiguous references.
- Use `SET LOCAL`, not session-persistent `SET search_path`, when a search path is required.
- Do not place nested `BEGIN`/`COMMIT` blocks inside a migration.
- Operations that PostgreSQL does not permit inside a transaction (for example some concurrent index operations) must be marked and executed by an explicit non-transactional migration mechanism.
- Acquire a migration lock so two deployers cannot apply migrations concurrently.

## 3. Database roles

Use separate roles with least privilege:
- **Schema owner:** owns schemas and objects; not used by application requests.
- **Migration role:** may create/alter objects and apply reviewed migrations.
- **Runtime role:** used by the API/worker; does not own tables, is not superuser and does not have `BYPASSRLS`.

The API must not connect as the schema owner or migration role. Credentials are deployment secrets and are never stored in Git.

## 4. Tenant isolation and RLS

- Every tenant-owned row carries a non-null organization/tenant owner or has an explicit documented global/reference-data reason.
- Same-tenant foreign keys should include organization_id on both source and target columns.
- Cross-organization references must be explicit relationships with separate owner identifiers and an authorization grant; do not weaken same-tenant foreign keys to bare UUIDs.
- Enable and force RLS on tenant-owned tables where appropriate. Policies must default-deny and cover SELECT/INSERT/UPDATE/DELETE.
- Runtime tests must connect as the non-owner runtime role. Table owner/superuser tests do not prove RLS behavior.
- Set authenticated organization context transaction-locally after authorization and before queries; never trust an organization_id supplied only by a client.
- Ensure pooled connections cannot carry tenant context from one request into another.

## 5. Integrity and concurrency

- Use database constraints for invariants where PostgreSQL can enforce them: FK, CHECK, UNIQUE, exclusion and appropriate partial indexes.
- Do not rely on an availability query or a B-tree overlap index to prevent double booking.
- Hold creation, confirmation, extension, release and expiry must serialize against the same resource reservation invariant.
- Use idempotency keys for commands that may be retried.
- Historical snapshots and response/audit histories are append-only at the application permission layer; use database protections where needed.
- Validate resource capacities and reservation quantities in the same transaction that commits the reservation.

## 6. Versioned configuration and reference data

- Stable option identity is separate from localized/presentation revision.
- Published revisions are immutable; publish a new revision instead of editing a live one.
- Retire used options; do not delete or repurpose their meaning.
- Inquiries, offers, bookings, invitations and RSVP responses pin the revisions/labels needed to reconstruct what was presented at the time.
- Seed only platform/system reference data in migrations. Organization-specific GHB catalogues, prices and venue geometry are separately reviewed, versioned configuration data.

## 7. Test requirements

Each schema migration must be tested against:
1. Empty supported PostgreSQL database.
2. The immediately preceding released schema version.
3. Valid synthetic fixtures.
4. Invalid foreign keys, cross-tenant references and check/unique/exclusion violations.
5. Concurrent conflicting operations where availability/capacity is involved.
6. The actual non-owner runtime role with RLS enabled.
7. Backup/restore and forward-recovery procedure appropriate to the change.

Record exact PostgreSQL major/minor version and command output in CI. No migration is considered validated merely because SQL text was accepted by a linter or because the application compiles.
