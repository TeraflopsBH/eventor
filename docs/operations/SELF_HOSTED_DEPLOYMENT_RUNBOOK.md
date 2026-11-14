# Self-hosted deployment and operations runbook

**Status:** deployment procedure draft; not a production certification.  
**Scope:** the current Fastify API, notification worker, Vue staff web and PostgreSQL database. This runbook deliberately separates repository-verifiable steps from environment-specific operational controls that have not yet been exercised.

## 1. Deployment status and prerequisites

The accepted deployment decision is self-hosted Linux. Docker and managed cloud services are not mandatory. The repository currently provides application build/start commands, PostgreSQL role bootstrap and a checksum-verified migration runner. It does **not** yet provide a complete tested systemd unit set, reverse-proxy configuration, automated backup/restore tooling or a production recovery drill.

Before a first deployment, prepare:

- A supported Linux host and a supported Node.js 22 release (staff-web development documentation specifies Node 22.16.0; use the same pinned release for reproducible builds).
- PostgreSQL 18.6, reachable only from the API/worker hosts and authorized administration/migration hosts.
- A trusted TLS certificate authority for PostgreSQL connections; production connection strings must use `sslmode=verify-full`.
- A same-origin HTTPS reverse proxy for the staff web and API. Preserve the `/api` prefix mapping expected by the staff web, or configure `VITE_API_BASE_URL` consistently at build time.
- Separate secret/configuration storage for API, worker and database credentials. Do not commit real environment files.
- A backup destination independent of the database host, with access controls and encryption appropriate for guest/contact data.
- An operator-approved maintenance and recovery window. No zero-downtime migration guarantee is currently documented.

Do not treat this draft runbook as evidence that a target host, firewall, proxy, certificate, backup schedule or recovery objective has been tested.

## 2. Process and network topology

Recommended initial topology:

- Reverse proxy: public HTTPS entry point; route the staff-web application and `/api/*` to the API after removing the `/api` prefix.
- API: Fastify process listening on the configured `HOST`/`PORT` (defaults to `0.0.0.0:8080`, which binds all interfaces). Set `HOST` to a private interface address (or loopback when the proxy is local) where practical, and enforce firewall rules so the API port is never directly reachable from the public internet.
- Notification worker: separate process using only `EVENTOR_WORKER_DATABASE_URL`.
- PostgreSQL: private network only. The API uses separate runtime and auth pools; the worker uses its own worker role.
- Staff web: build the static application and serve its generated assets through the reverse proxy. The Vite development server and `vite preview` are not production servers.

Only expose the reverse proxy publicly. Restrict database ingress to the required hosts and administration network. If the API is behind a proxy, set `EVENTOR_TRUST_PROXY_CIDRS` to the exact proxy addresses/CIDRs; never trust arbitrary forwarded headers.

## 3. Database initialization and migration

Perform this on a new or explicitly approved target database, using a database administrator account for role bootstrap:

1. Create the Eventor database using the organization's approved encoding, locale, ownership and storage policy.
2. Bootstrap the least-privilege roles from the repository root:

   ```sh
   psql "$ADMIN_DATABASE_URL" -X -v ON_ERROR_STOP=1 \
     -v database_name=eventor -f scripts/db/bootstrap-roles.sql
   ```

   Connect `ADMIN_DATABASE_URL` directly to the Eventor database; the bootstrap script does not switch databases. The script reconciles role attributes and memberships. It does not set passwords.
3. Set distinct strong passwords for `eventor_migrator`, `eventor_runtime`, `eventor_auth` and `eventor_worker` using the organization's secret-management process or interactive PostgreSQL `\password`. Never place passwords in shell history or commit them.
4. Verify the role attributes and membership graph using `tests/database/auth_role_smoke.sql` and the role checks in the database CI workflow, adapted only as needed for the target environment.
5. Take and verify a pre-migration backup using the organization's PostgreSQL backup procedure.
6. Run migrations from a trusted release checkout, connecting as `eventor_migrator`:

   ```sh
   cd apps/api
   npm ci
   npm run build
   cd ../..
   DATABASE_URL="$EVENTOR_MIGRATOR_DATABASE_URL" scripts/db/migrate.sh
   ```

   `EVENTOR_MIGRATOR_DATABASE_URL` is a shell variable supplied by the deployment secret store; it must connect as `eventor_migrator`. The migration runner requires `psql`, `sha256sum`, PostgreSQL 18.6 and the repository migration directory. It verifies checksums, serializes concurrent migration attempts and records each migration in the same transaction as its schema changes.
7. Run the database smoke/security tests against a disposable or explicitly approved test database before production traffic. Do not run destructive test fixtures against production.

Migrations are forward-only. There is no automatic down-migration command. A checksum mismatch on an already-applied migration is a stop condition: do not edit the historical migration or bypass the check.

## 4. Build and configure application processes

Build from the same reviewed release commit that was migrated:

```sh
cd apps/api
npm ci
npm run build

cd ../staff-web
npm ci
VITE_API_BASE_URL=/api npm run build
```

The staff-web build produces static assets in its Vite output directory. Publish those assets to the configured web root using an atomic release/symlink strategy chosen by the operator. Keep the API and staff-web assets on compatible release versions.

Configure the API process with:

- `EVENTOR_RUNTIME_DATABASE_URL`
- `EVENTOR_AUTH_DATABASE_URL`
- `EVENTOR_ALLOWED_ORIGINS`
- `EVENTOR_AUTH_FINGERPRINT_KEY`
- `EVENTOR_FIELD_ENCRYPTION_KEY`
- `EVENTOR_CONTACT_ENCRYPTION_KEY`
- `EVENTOR_DELIVERY_CREDENTIALS_KEY`
- `EVENTOR_PUBLIC_INQUIRY_FINGERPRINT_KEY`
- `EVENTOR_BOOKING_CAPABILITY_KEY`

The worker process requires:

- `EVENTOR_WORKER_DATABASE_URL`
- `EVENTOR_CONTACT_ENCRYPTION_KEY`
- `EVENTOR_DELIVERY_CREDENTIALS_KEY`

Booking-offer and guest-invitation email delivery additionally require worker-only `EVENTOR_PUBLIC_APP_BASE_URL`; set it to the HTTPS public web-app base URL (including any deployment path prefix) so invitation links resolve to the guest portal. Provider callback URL display requires API-side `EVENTOR_PUBLIC_API_BASE_URL`. Optional pool and worker tuning variables are documented in `apps/api/.env.example`.

Generate six independent cryptographically random 32-byte keys and base64-encode each one. Never reuse a key across purposes or place keys in source control, command-line arguments, logs or deployment artifacts. Keep the booking-capability key stable while issued links remain valid. Encryption-key rotation requires an explicit re-encryption procedure; replacing a key alone makes existing ciphertext unreadable.

Set `EVENTOR_ALLOWED_ORIGINS` to the exact HTTPS staff-web origin(s), not a wildcard. Configure API and worker database URLs with certificate and hostname verification. Use separate OS service accounts with only the filesystem and network permissions each process needs. Run the API and worker as separate supervised services; do not run either as root or with migration/owner credentials.

The repository now includes example systemd units and installation guidance in `deploy/systemd/`. They are templates, not target-host-validated service definitions: confirm the Node executable path, service accounts, release symlink, environment-file permissions, sandbox compatibility, restart policy and graceful-shutdown timeout on the selected distribution. A tested reverse-proxy configuration is still not included; configure and review that separately before deployment.

## 5. First-start verification

Before opening public traffic, verify all of the following:

- API and worker start under their dedicated service accounts and remain healthy after a controlled restart.
- API runtime/auth and worker connections authenticate as the intended PostgreSQL roles; none uses `eventor_owner` or `eventor_migrator`.
- PostgreSQL connections validate the server certificate and hostname.
- Staff web and API are served over the same HTTPS origin; cookies retain the required `Secure`, `HttpOnly`, `SameSite` and `__Host-` behavior.
- The exact staff-web origin is allow-listed; untrusted origins and untrusted forwarded headers are rejected.
- A controlled staff login/logout works, CSRF checks reject missing/invalid tokens, and tenant boundaries are verified.
- Worker queue processing is observed using synthetic test data and a controlled test mailbox. Do not send production campaigns as a deployment smoke test.
- Logs and metrics are collected without session tokens, passwords, encryption keys, guest contact values, ciphertext or provider secrets.
- Public endpoints, rate limits, firewall rules, DNS and TLS renewal have been reviewed.

A passing application health check alone does not establish that email delivery, backup recovery or all business workflows are production-ready.

## 6. Backup, restore and recovery requirements

A production operator must select and document a PostgreSQL backup method before accepting real data. The repository does not prescribe a tested backup implementation yet.

At minimum, the operational design must specify:

- Backup type and cadence (base backups and, if required, continuous WAL archiving/PITR).
- Encryption in transit and at rest, separate storage credentials and off-host/off-site retention.
- Retention periods, deletion policy and access audit.
- Monitoring for failed, incomplete, late or unexpectedly small backups and WAL archive gaps.
- Recovery Point Objective (RPO) and Recovery Time Objective (RTO), approved by the organization.
- A restore procedure for a clean host, including PostgreSQL configuration, role/bootstrap state, database restore, application release, secret restoration and DNS/proxy cutover.
- Protection and recoverability of the six application encryption keys. A database backup without the matching keys is insufficient to recover encrypted contact, inquiry, delivery or offer data.
- A recurring restore drill in an isolated environment, with documented timings and integrity checks.

Before every production migration or release that changes database behavior, take a verified backup and confirm that the recovery path is available. If a migration fails, stop deployment and preserve logs. Do not improvise manual schema edits or assume a down migration exists. Recovery options are a tested backup/PITR restore or a reviewed forward-fix migration; choose according to the incident and the organization's data-loss tolerance.

## 7. Upgrade and rollback procedure

1. Review the release commit, migration list, dependency changes and CI results. Confirm that the exact commit to deploy is the one validated.
2. Confirm a tested backup/restore path and available encryption keys.
3. Put the application into an operator-controlled maintenance state if required. The current repository does not provide a complete maintenance-mode switch; coordinate traffic and worker shutdown explicitly.
4. Stop or pause worker processing and prevent concurrent migration runners.
5. Apply migrations once, using the dedicated migrator connection.
6. Deploy the API and staff-web assets from the same release commit.
7. Start the API, verify authentication and tenant-scoped read paths, then start the worker and verify queue processing.
8. Re-enable traffic and monitor application/database errors, queue age, SMTP outcomes, disk capacity and backup status.
9. If application rollback is required after a schema change, do not automatically restore old application code against the new schema. Confirm backward compatibility first. If the database must be restored, follow the tested recovery procedure and explicitly account for writes made after the backup/PITR point.

No prior released production schema baseline has been established in this repository. Upgrade-from-previous-release compatibility is therefore unverified and must be tested once a real release baseline exists.

## 8. Production readiness evidence still required

The following are external or unimplemented gates, not claims that this repository can satisfy by itself:

- Tested target-host installation and service supervision.
- Reviewed production reverse-proxy and firewall configuration.
- Secret provisioning, access control, backup and key-recovery procedures.
- Automated backup monitoring and a successful isolated restore/PITR drill.
- Approved RPO/RTO and incident ownership.
- Upgrade test from a defined preceding release schema.
- Load, capacity, log-retention and operational monitoring baselines.
- A documented security/incident response process.

Until these are evidenced, classify the deployment as **pre-production**.

## 9. External acceptance evidence

Use `docs/operations/EXTERNAL_ACCEPTANCE_EVIDENCE.md` as the dated evidence record for browser-driven business workflow acceptance, Resend/SMTP sandbox acceptance, prior-schema migration upgrade rehearsal, backup/restore/PITR drills and target-host/network acceptance. Assign an accountable owner and exact candidate SHA to each activity. Mark activities deferred until the required isolated environment, credentials, representative data or approved operational targets exist; do not convert missing evidence into a pass. Production remains blocked until the required evidence and approvals are complete.
