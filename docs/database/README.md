# Database design and migration documentation

- [Database Review v0.2](DATABASE_REVIEW_v0.2.md) — historical SQL structural review and known gaps.
- [Migration Conventions](MIGRATION_CONVENTIONS.md) — forward-only migration, transaction and database-role conventions; PostgreSQL 18 baseline.
- [Database Integrity Design v0.3](DATABASE_INTEGRITY_DESIGN_v0.3.md) — tenant-safe relationships, reservation concurrency, optional capabilities and task responsibility.
- [Constraint and Concurrency Test Matrix v0.3](SCHEMA_CONSTRAINT_TEST_MATRIX_v0.3.md) — integrity cases to preserve in implementation tests.

## Successor implementation draft

- [Ordered PostgreSQL 18 migrations](../../database/migrations/) — 21 forward-only files covering tenancy, venue inventory, booking, reservations, cancellation, events, collaboration, RSVP, event disruption, attendance, RLS, identity isolation, collaboration grant scope, source projection enforcement and published-revision immutability.
- [Role bootstrap](../../scripts/db/bootstrap-roles.sql) and [checksum migration runner](../../scripts/db/migrate.sh). The dedicated `eventor_auth` role is separate from `eventor_runtime`; normal tenant code reads member profiles through an RLS-filtered view and cannot select global password hashes. Collaboration grant proposals use a narrowly scoped security-definer command because runtime table writes are revoked.
- [Original migration smoke tests](../../tests/database/) and [additional RLS/constraint tests](../../database/tests/rls_and_constraints.sql).
- [Independent-connection capacity test](../../scripts/db/test_resource_concurrency.sh) and [additional concurrency runner](../../scripts/db/test-concurrency.sh).
- [Unified PostgreSQL/API contract workflow](../../.github/workflows/contracts-and-database.yml).

The v0.2 SQL remains a historical reference. The v0.3 migrations are an implementation draft; [CI run #42850865186](https://github.com/TeraflopsBH/eventor/actions/runs/42850865186) applied all 21 migrations and passed on PostgreSQL 18.6. Coverage includes tenant RLS, hierarchy/intervals, reservations/concurrency, global identity isolation, collaboration grant lifecycle and actual-use scope, source layer/object/resource subset checks, narrowly filtered source-data RLS, revocation behavior, published revision immutability, append-only history and external cancellation actor attribution. The DDL still requires deeper code/security review, migration-upgrade and backup/restore tests, and approval before production deployment.
