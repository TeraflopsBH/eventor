# Remote acceptance and verification boundaries

> **Release versus CI clarification — 2026-11-27:** Optional external probe workflow configuration is not a waiver of the approved release contract. [ER-07/G8](../blueprint/v1.3/ENGINEERING_REGISTERS_v1.0.md) and [OLA](../implementation-design/v0.3/ORGANIZATION_LIFECYCLE_ACCEPTANCE_SCENARIOS_v1.0.md) require actual intended public HTTPS and external SMTP sandbox evidence at final integrated acceptance, together with advertised supported adapters and hardware evidence. Missing targets/credentials or skipped probes remain unverified. Conditional extensions may be N/A only under explicit reviewed applicability; no silent release waiver. A successful probe supplies only its documented evidence, not full business, delivery or production acceptance. Both installers and Phase 9 remain required.

This document distinguishes repeatable GitHub-hosted checks from acceptance that requires a real, separately approved environment. CI is not production certification.

## Automated on the integration branch

The `Contracts and PostgreSQL migrations` workflow runs:

- OpenAPI 3.1 validation/lint, API route tests, TypeScript generation/type-checking and high/critical dependency audit.
- Staff-web regression tests, type-check/build and dependency audit.
- PostgreSQL 18.6 fresh migration chain, migration-history-gap guard, populated 000073-to-000074 upgrade rehearsal, RLS/tenant isolation, authorization/revocation races and concurrency regressions.
- PostgreSQL-backed session authentication, worker/fake-SMTP integration, booking/commercial end-to-end tests and migration 000114 draft reservation-release behavior.
- systemd unit syntax and referenced identity checks.
- A logical `pg_dump`/restore rehearsal into a separate ephemeral database, including comparison of selected row counts and verification that the restored migration-000114 function exists.
- Full reachable Git-history secret scanning in the separate secret-history workflow.

The logical backup/restore check validates a dump and restore in ephemeral CI. It does not exercise WAL archiving, point-in-time recovery, off-host retention, encryption-key escrow, or recovery objectives.

## Optional external probes

The `Optional external acceptance probes` workflow can be enabled without placing credentials in source control:

- Set repository variable `EVENTOR_SMTP_SANDBOX_ENABLED=true` and configure the `EVENTOR_SMTP_*` repository secrets to run one explicit test message through the configured non-production SMTP sandbox.
- Set repository variable `EVENTOR_PUBLIC_BASE_URL` to an approved public HTTPS endpoint to check certificate validation, successful HTTP response, HSTS, `X-Content-Type-Options` and `Referrer-Policy`.

These probes are opt-in. A skipped job is not a pass. The SMTP probe verifies provider acceptance of the configured test recipient; it does not prove inbox placement, bounce/complaint processing or domain reputation.

## Not established by ephemeral CI

The following still require an identified, isolated acceptance environment and accountable operator:

- Full browser-driven business workflows through the deployed staff web and public booking pages. API session integration is not equivalent to browser acceptance.
- Real Resend/SMTP sandbox acceptance unless the optional job is explicitly enabled and succeeds.
- Upgrade from a representative prior deployed database snapshot. The current 000073-to-000074 rehearsal is a targeted synthetic upgrade, not evidence of an actual customer or production baseline.
- Backup destination, off-host retention, encryption-key recovery and WAL/PITR restore drill against an approved RPO/RTO.
- Target Linux host service startup, filesystem permissions, firewall, reverse proxy, trusted-proxy CIDRs, DNS, TLS renewal, PostgreSQL TLS and operational monitoring.
- Product/venue acceptance, security review and production release approval.

Never point repository CI at a production database or production mail recipients. Use synthetic data and separately approved staging credentials. Record the exact candidate commit SHA and sanitized evidence for each external activity. Missing evidence remains deferred, not passed.
