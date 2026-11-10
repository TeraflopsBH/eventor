# Database design and migration documentation

- [Database Review v0.2](DATABASE_REVIEW_v0.2.md) — historical SQL structural review and known gaps.
- [Migration Conventions](MIGRATION_CONVENTIONS.md) — forward-only migration, transaction and database-role conventions; PostgreSQL 18 baseline.
- [Database Integrity Design v0.3](DATABASE_INTEGRITY_DESIGN_v0.3.md) — tenant-safe relationships, reservation concurrency, optional capabilities and task responsibility.
- [Constraint and Concurrency Test Matrix v0.3](SCHEMA_CONSTRAINT_TEST_MATRIX_v0.3.md) — intended PostgreSQL integration test cases.

The v0.2 SQL remains a historical reference. No executable successor migration has yet been validated against PostgreSQL.
