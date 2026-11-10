# Database design and migration documentation

- [Database Review v0.2](DATABASE_REVIEW_v0.2.md) — historical SQL structural review and known gaps.
- [Migration Conventions](MIGRATION_CONVENTIONS.md) — forward-only migration, transaction and database-role conventions; PostgreSQL 18 baseline.
- [Database Integrity Design v0.3](DATABASE_INTEGRITY_DESIGN_v0.3.md) — tenant-safe relationships, reservation concurrency, optional capabilities and task responsibility.
- [Constraint and Concurrency Test Matrix v0.3](SCHEMA_CONSTRAINT_TEST_MATRIX_v0.3.md) — intended PostgreSQL integration test cases.

## Successor implementation draft

- [Ordered PostgreSQL 18 migrations](../../database/migrations/) — 15 forward-only files covering tenancy, venue inventory, booking, reservations, cancellation, events, collaboration, RSVP, event disruption, attendance and RLS.
- [Role bootstrap](../../scripts/db/bootstrap-roles.sql) and [checksum migration runner](../../scripts/db/migrate.sh).
- [RLS/constraint smoke tests](../../database/tests/rls_and_constraints.sql) and [concurrency test runner](../../scripts/db/test-concurrency.sh).
- [PostgreSQL/API contract workflow](../../.github/workflows/schema-and-api-contracts.yml).

The v0.2 SQL remains a historical reference. The v0.3 migrations are an implementation draft and must pass the PostgreSQL 18.6 CI job before being considered executable/validated. No production database has been migrated.
