# Eventor API and notification worker

This package now contains the first deployable command API bootstrap and a separate event-notification campaign-preparation worker. It remains an application foundation, not the complete staff product or delivery system.

## API commands

- `POST /auth/session` — Argon2id staff login bound to an active organization membership.
- `DELETE /auth/session` — revoke the current database-backed session.
- `GET /me` — return the current principal and active organization memberships.
- `POST /bookings/{bookingId}/reservations/release`
- `POST /events/{eventId}/change-requests`
- `POST /event-change-requests/{requestId}/approve`
- `POST /event-change-requests/{requestId}/reject`
- `POST /event-change-requests/{requestId}/execute`
- `GET /event-notification-campaigns/{campaignId}/review` — permission-gated review of the recipient snapshot, channel/exclusion totals and pinned template; contact values are never returned.
- `POST /event-notification-campaigns/{campaignId}/confirm` — event-scoped send permission, audit attribution and idempotency; confirms the fixed snapshot but deliberately does not queue delivery.

The command handlers call permission-gated PostgreSQL functions rather than performing ad-hoc table writes.

## Database roles and credentials

The API uses two independent pools:

- `eventor_runtime` for tenant-scoped application commands.
- `eventor_auth` for global identity lookup, password-hash verification, login throttling and opaque session storage. This role cannot read venue/business tables and does not have `BYPASSRLS`.

The notification worker connects separately as `eventor_worker`. Do not run API or worker processes with the migration/owner credentials.

## Staff session security

- Passwords are verified as Argon2id PHC hashes. New hashes use the library defaults; successful logins rehash when the configured parameters are outdated.
- The session cookie is a random 256-bit opaque token named `__Host-eventor_session`, marked `Secure`, `HttpOnly`, `SameSite=Strict` and `Path=/`. Only its SHA-256 hash is stored in PostgreSQL.
- A separate random CSRF token is held in a readable `__Host-eventor_csrf` cookie and returned to the same-origin client at login. State-changing requests must send the matching `X-CSRF-Token` header. The server checks the allow-listed `Origin` and validates the CSRF token hash against the active session.
- Sessions are bound to a specific user, organization and active membership. Revocation, user disablement, membership suspension/revocation and organization suspension are checked on authentication.
- Login failures are throttled in PostgreSQL using HMAC fingerprints of the normalized email and request source. Configure a dedicated 32-byte fingerprint key.
- Do not put secrets in logs. Configure exact origins; wildcards are rejected.

When behind a reverse proxy, configure `EVENTOR_TRUST_PROXY_CIDRS` with only the proxy addresses/CIDRs you control. Without that setting Fastify uses the direct peer IP for login throttling. Do not trust arbitrary forwarded headers.

## Environment

Copy `.env.example` into your deployment's secret/configuration system and supply real values. The checked-in example contains placeholders only.

Both database connection URLs should use TLS with certificate and hostname verification in production (for example, PostgreSQL `sslmode=verify-full` with a trusted CA). Configure database passwords outside this repository.

Start the API after building:

```sh
npm install
npm run build
npm start
```

Start the notification worker as a separate process:

```sh
npm run build
npm run start:worker
```

## Contact-value encryption contract

The contact registry stores email/phone values in `person_contact_points.encrypted_value`. New application code must use the shared `src/contact-crypto.ts` codec rather than inventing an envelope or reusing the private-event-reason encryption domain.

- Format: `ECP1` magic bytes, a fresh 12-byte nonce, a 16-byte AES-256-GCM authentication tag, then ciphertext.
- Key: a dedicated, cryptographically random 32-byte `EVENTOR_CONTACT_ENCRYPTION_KEY`, base64-encoded in deployment configuration. It must differ from the field-encryption and authentication-fingerprint keys.
- Key derivation: HMAC-SHA-256 domain separation with the `eventor:contact-point-encryption:v1` label.
- Authenticated context: tenant UUID and contact kind (`email`, `phone`, `postal`, or `other`). Moving ciphertext to another tenant or contact kind fails authentication.
- The normalized contact hash remains a separate lookup value; it is not encryption key material.
- Ciphertext is never logged or returned by review APIs. Decryption belongs only in the isolated delivery process immediately before provider submission.

Existing ciphertext without the `ECP1` envelope is legacy/unknown format and is deliberately rejected by this codec. Do not attempt fallback decryption or send it. Before enabling delivery, migrate or re-enter legacy contacts through an approved source format, verify them, and ensure their consent is still `permitted`. Key rotation requires an explicit re-encryption migration with old and new keys; replacing the key alone makes existing values unreadable.

## Notification outbox behavior

The organizer's event-change command writes a transactional outbox event. The worker:

1. Discovers only tenant IDs for the `event.change.notification_requested` topic.
2. Sets transaction-local tenant context before reading that tenant's outbox or event data.
3. Resolves the audience from the selected rule (accepted/tentative, active invitees, previously invited or explicit custom participation IDs).
4. Copies only verified, permitted email/phone contact snapshots from the organizer's contact registry. The stored contact ciphertext is copied as ciphertext; the worker does not decrypt it or log addresses.
5. Records exclusions where no verified, permitted contact exists.
6. Creates a `previewed` event notification campaign with a published purpose-matched template and the recipient count. The organizer can review the campaign through the staff API and explicitly confirm it with the event-scoped notification-send permission. Confirmation validates the current event decision, recipient-count consistency and active published template, then records the confirming membership in audit history. It does not queue delivery.

Worker processing is transactional, row-locked with `SKIP LOCKED`, idempotent at the outbox/campaign level, and retryable with bounded exponential backoff. After 12 failed attempts, the event is dead-lettered for operator review.

**The worker does not send email or SMS.** No delivery attempts are created and no campaign is marked as sent or delivered. A delivery-provider adapter, callback processing and failure/retry management remain separate work. A failed or delayed message never rolls back the event cancellation/postponement.

## OpenAPI types and tests

From this directory:

```sh
npm install --no-package-lock
npm run typecheck
npm test
```

`npm run generate:openapi` generates TypeScript declarations from `docs/api/openapi.v0.3.yaml`. CI regenerates these before strict compilation and route tests.

## Remaining integration work

- Connect the staff frontend to login, CSRF token handling, `/me` and the implemented command routes.
- Implement the actual delivery-provider adapter, provider callbacks and failure/retry management; provider callbacks must update per-recipient attempts without rewriting RSVP/attendance history or the event decision.
- Implement the rest of the OpenAPI operations.
- Complete production secret provisioning, database TLS/network policy, proxy configuration, backups/recovery, monitoring and operational runbooks.
