# Database design and migration documentation

- [Database Review v0.2](DATABASE_REVIEW_v0.2.md) — historical SQL structural review and known gaps.
- [Migration Conventions](MIGRATION_CONVENTIONS.md) — proposed forward-only migration and transaction conventions.
- [Database Integrity Design v0.3](DATABASE_INTEGRITY_DESIGN_v0.3.md) — tenant-safe relationships, reservation concurrency, optional capabilities and task responsibility.
- [Constraint and Concurrency Test Matrix v0.3](SCHEMA_CONSTRAINT_TEST_MATRIX_v0.3.md) — intended PostgreSQL integration test cases.
- [Successor Schema Design v0.3](SCHEMA_DESIGN_v0.3.md) — logical table inventory, ownership, lifecycle and migration decomposition.

The v0.2 SQL remains a historical reference. No executable successor migration has yet been validated against PostgreSQL.
