# Remote acceptance and operational verification

This runbook describes what the GitHub-hosted acceptance workflow verifies without a developer workstation or VM.

## Automated on every CI run

- PostgreSQL 18.6 migration, RLS, tenant-isolation and concurrency suite.
- API/OpenAPI and staff-web tests, type-checks, production build and dependency audits.
- Real PostgreSQL-backed execution of the TypeScript SMTP notification worker using a deterministic in-memory SMTP transport. No external mail is sent.
- Chromium and Firefox browser checks for staff login, Secure/HttpOnly cookie persistence, session restoration through `GET /me`, CSRF-protected mutation, logout and revocation.
- Upgrade rehearsal from the immediately preceding committed migration baseline (version 72) to version 73, with representative data present across the upgrade.
- Logical PostgreSQL backup/restore rehearsal into a separate ephemeral database, followed by schema-ledger and data-count verification.
- Full reachable Git-history secret scanning.

The worker E2E uses synthetic addresses under `example.invalid`, synthetic encryption keys and a fake SMTP transport. It exercises the real worker code and real PostgreSQL claim/complete functions, but it does not prove delivery to an external mail provider.

## Optional live checks

The workflow can run a real SMTP sandbox probe when repository variable `EVENTOR_SMTP_SANDBOX_ENABLED=true` is set and the corresponding `EVENTOR_SMTP_*` secrets are configured. The probe verifies the provider connection and sends one explicitly configured test message to `EVENTOR_SMTP_TO`.

A public TLS/HTTP probe runs when repository variable `EVENTOR_PUBLIC_BASE_URL` is configured. It checks certificate validation, HTTPS reachability and selected response headers. This is a probe of the configured public endpoint, not a substitute for host hardening or deployment review.

## Explicitly not proven by ephemeral CI

- A PITR recovery from the production/staging WAL archive. A logical `pg_dump` restore is tested; PITR additionally needs an actual WAL archive, retention policy, recovery target and isolated restore destination.
- Production systemd service startup, filesystem permissions, firewall and reverse-proxy behavior on the actual target host. CI verifies the committed systemd unit syntax and referenced identities only.
- Production DNS, TLS termination, trusted-proxy CIDRs, real email deliverability, SPF/DKIM/DMARC alignment, provider reputation and bounce/complaint handling unless the optional external probes are configured.
- Upgrade from a real deployed production database snapshot. The automated rehearsal starts from migration 72 in a fresh isolated database; it is not evidence that a customer database is at that version.

No workflow in this repository should connect to or mutate a production database. Production recovery and host acceptance require a separately approved staging target and credentials.
