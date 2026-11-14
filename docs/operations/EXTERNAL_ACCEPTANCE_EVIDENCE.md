# External deployment acceptance evidence

**Disposition:** blocked / not yet executed  
**Candidate:** record the exact reviewed Git commit SHA for every activity.  
**Safety:** use isolated, non-production infrastructure and synthetic data only. Do not use production recipients, production credentials or production databases for acceptance.

This record is intentionally a template. Empty fields are not evidence of a pass.

## 1. Acceptance environment

- Environment name:
- Owner/operator:
- Hostname(s) and Linux distribution/version:
- Node.js exact version:
- PostgreSQL exact version:
- Reverse proxy and version:
- Public test hostname:
- API/staff-web candidate SHA:
- Migration ledger/checksum evidence:
- Test-data seed/version:
- Date/time and timezone:
- Evidence location:

## 2. Browser-driven business workflow

**Owner:** unassigned  
**Disposition:** deferred until an isolated acceptance stack and test identities exist.

- [ ] Staff sign-in and sign-out.
- [ ] Organization and venue setup.
- [ ] Distinct staff roles and permission boundaries.
- [ ] Two-organization tenant-isolation checks.
- [ ] Price-list and tax-profile revision lifecycle.
- [ ] Booking draft creation and resource/space allocation.
- [ ] Alternative allocation preview and selection.
- [ ] Offer generation and public booking form.
- [ ] Public capability cannot expose staff or guest-directory data.
- [ ] Booking confirmation, cancellation and reservation release.
- [ ] English and Bosnian locale workflows.
- [ ] Capture browser traces/screenshots and sanitized request/response evidence.

Record each failure as a reproducible defect with route, actor/role, tenant, request correlation ID, expected result and observed result. Do not include credentials, session cookies, capability tokens or guest personal data in evidence.

## 3. Email-provider sandbox

**Selected provider:** Resend adapter / SMTP transport  
**Owner:** unassigned  
**Disposition:** deferred until provider sandbox credentials and a non-production sender/domain are provisioned.

- [ ] Confirm provider sandbox/test mode and permitted recipient behavior.
- [ ] Configure only non-production credentials and sender identity.
- [ ] Verify invitation and booking-offer email delivery.
- [ ] Verify provider rejection and retry classification.
- [ ] Verify connection timeout and uncertain DATA-stage outcome handling.
- [ ] Verify idempotency/duplicate handling and delivery status projection.
- [ ] Verify webhook authentication, correlation and replay/idempotency.
- [ ] Confirm logs redact credentials, tokens, message content and guest contact values.

Record provider, non-secret configuration, message references, timestamps, observed attempts/retries and sanitized logs. A generic SMTP server accepting a message is not proof of inbox delivery or bounce processing.

## 4. Migration upgrade rehearsal

**Owner:** unassigned  
**Disposition:** deferred until a representative prior schema snapshot and isolated database are available.

- [ ] Identify and document the prior supported schema version.
- [ ] Restore or construct representative synthetic data at that version.
- [ ] Record baseline row counts and integrity checks.
- [ ] Apply the complete migration chain using the deployment migrator identity.
- [ ] Verify migration ledger, checksums and PostgreSQL version.
- [ ] Verify constraints, RLS and role boundaries after upgrade.
- [ ] Run API/staff-web smoke tests against the upgraded database.
- [ ] Exercise an interrupted migration/retry in a disposable clone.
- [ ] Record recovery action and prove no partial migration state remains.

Do not infer upgrade compatibility from a fresh-database migration run.

## 5. Backup and recovery drill

**Owner:** unassigned  
**Disposition:** deferred until backup destination, key escrow/recovery and RPO/RTO are approved.

- Approved RPO:
- Approved RTO:
- Backup method and cadence:
- Retention:
- Off-host destination:
- Encryption/key custody:
- Restore target:
- Drill date/time:
- Measured recovery point:
- Measured recovery time:
- Evidence location:

- [ ] Take a backup of the isolated acceptance database.
- [ ] Verify backup integrity before restore.
- [ ] Restore to a clean isolated PostgreSQL instance.
- [ ] Restore the matching application encryption keys from the approved secret-recovery process.
- [ ] Verify migration ledger, row counts and application-level invariants.
- [ ] Verify tenant isolation after restore.
- [ ] If PITR is configured, restore to a selected timestamp and record the result.
- [ ] Compare measured recovery against approved RPO/RTO.

A database backup without the matching Eventor encryption keys is not a complete recovery.

## 6. Host and network acceptance

**Owner:** unassigned  
**Disposition:** deferred until the actual target host and network are selected.

- [ ] Install the API and worker units on the target Linux distribution.
- [ ] Confirm service users cannot modify the release tree or read the other process's secret file.
- [ ] Confirm API/worker process startup and restart under their dedicated identities.
- [ ] Confirm SIGTERM shutdown completes within configured systemd timeouts.
- [ ] Confirm API is reachable only through the intended reverse proxy.
- [ ] Confirm proxy header trust is restricted to exact proxy addresses.
- [ ] Confirm public HTTPS, certificate renewal and secure cookie behavior.
- [ ] Confirm PostgreSQL TLS certificate and hostname verification.
- [ ] Confirm host firewall and database ingress restrictions.
- [ ] Confirm backup monitoring, log retention, disk monitoring and alert routing.

## 7. Exit decision

- Browser workflow disposition: deferred / pass / fail
- Email sandbox disposition: deferred / pass / fail
- Migration upgrade disposition: deferred / pass / fail
- Backup/restore disposition: deferred / pass / fail
- Host/network disposition: deferred / pass / fail
- Product/venue acceptance owner:
- Operations owner:
- Security reviewer:
- Final decision and date:

Production release remains blocked until all required activities have evidence, accountable owners and an explicit approval. CI success and this checklist do not constitute production certification.
