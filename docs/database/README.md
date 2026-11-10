# Database documentation

- [Database Review v0.2](DATABASE_REVIEW_v0.2.md) — static review of the imported historical schema starter; not PostgreSQL execution validation.
- [Migration Conventions](MIGRATION_CONVENTIONS.md) — proposed migration, role, RLS, transaction and testing standards.
- [Database Integrity Design v0.3](DATABASE_INTEGRITY_DESIGN_v0.3.md) — successor design for tenant-safe FKs, typed scope references, venue hierarchy, catalogue revisions, reservations, optional modules and task responsibility.
- [Schema Constraint Test Matrix v0.3](SCHEMA_CONSTRAINT_TEST_MATRIX_v0.3.md) — acceptance scenarios to implement as database/integration tests.

The v0.2 SQL remains a historical design reference. Do not use it as a production migration. Successor DDL is pending cross-organization, integrity, RSVP and resource-model reconciliation plus execution against a supported PostgreSQL version.
