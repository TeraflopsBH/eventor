# Eventor API and notification delivery worker

This package contains the first deployable command API and a separate tenant-aware notification worker. It is an application foundation, not the complete staff product or delivery system.

## API commands

- `POST /auth/session` — Argon2id staff login bound to an active organization membership.
- `DELETE /auth/session` — revoke the current database-backed session.
- `GET /me` — return the current principal and active organization memberships.
- `POST /bookings/{bookingId}/reservations/release`
- `POST /events/{eventId}/change-requests`
- `POST /event-change-requests/{requestId}/approve`
- `POST /event-change-requests/{requestId}/reject`
- `POST /event-change-requests/{requestId}/execute`
- `GET /event-notification-campaigns/{campaignId}/review` — permission-gated review of recipient snapshots, channel/exclusion totals and the pinned template; contact values are never returned.
- `POST /event-notification-campaigns/{campaignId}/confirm` — explicitly confirms the fixed audience snapshot. It does not queue or send messages.
- `POST /event-notification-campaigns/{campaignId}/queue` — separate, explicit authorization to queue email delivery. Requires an enabled organization SMTP configuration and event-scoped send permission.
- `GET /organization/delivery/email/configuration` — read safe SMTP settings and credential/test status; never returns credentials.
- `POST /organization/delivery/email/configuration` — create a new immutable SMTP configuration revision. Credentials are write-only.
- `POST /organization/delivery/email/test` — verify the current SMTP connection and send one explicitly requested test message to the supplied address. A successful test enables that exact configuration revision.

All mutating staff routes require an idempotency key, an authenticated session, an allow-listed browser Origin and a valid CSRF token. Database commands enforce tenant and permission checks.

## Organization-owned SMTP

SMTP settings are tenant-scoped and versioned. Each organization controls its host, port, TLS mode, authentication mode, sender identity and reply-to address. Only STARTTLS and implicit TLS are accepted; certificate validation is always enabled. SMTP credentials are encrypted with AES-256-GCM using the separate `EVENTOR_DELIVERY_CREDENTIALS_KEY`, an EDC1 envelope and organization/channel-bound authenticated context.

A configuration revision is not enabled merely by saving it. An authorized administrator must explicitly request a test email. The API verifies the connection, sends a test message only to the requested address, then enables that exact current revision if it has not been superseded. Replaying the same idempotency key does not send a second test message. Changing SMTP settings creates a new revision and disables delivery until that new revision is tested.

SMTP is a network egress capability. Production deployments must apply outbound firewall policy so the API and worker can reach only approved SMTP destinations and ports. Do not expose the worker to unrestricted internal networks or cloud metadata endpoints. TLS certificate and hostname verification must remain enabled.

## Campaign delivery lifecycle

1. The event-change transaction creates an outbox request.
2. The preparation worker builds a `previewed` campaign with an immutable audience and contact snapshot. It does not send anything.
3. An authorized organizer reviews the campaign and explicitly confirms it.
4. A separately authorized user explicitly queues it. The queue command pins the current, successfully tested SMTP configuration revision and creates one delivery-attempt record per recipient.
5. The delivery worker processes only queued email attempts. It decrypts contact and SMTP credentials immediately before submission and never logs addresses, ciphertext or credentials.

A queued campaign continues to use the exact SMTP revision pinned when it was queued. Updating the organization's current SMTP settings affects future queue actions, not already authorized campaigns. The staff API does not yet expose a campaign hold/cancel command; treat queueing as an irreversible authorization to send and queue only when ready.

The worker records SMTP acceptance as `sent`; it does not claim that the recipient read or even received the message. Temporary connection and SMTP 4xx failures are retried with bounded exponential backoff (up to five attempts). Permanent 5xx and configuration/template errors are not automatically retried. If the connection fails at the SMTP DATA stage and acceptance is ambiguous, the attempt is marked `uncertain` and is not automatically resent, to avoid duplicate messages. Expired in-flight leases are also marked uncertain for operator reconciliation.

SMS recipients are recorded as suppressed with `SMS_CHANNEL_NOT_CONFIGURED`. No SMS provider is integrated or called. SMTP acceptance and delivery attempts never modify RSVP, invitation or attendance history, and notification failure never rolls back an event cancellation or postponement.

### Notification template placeholders

The first plain-text SMTP renderer supports only these placeholders:

- `{{event.title}}`
- `{{event.code}}`
- `{{event.status}}`
- `{{event.startsAt}}`
- `{{event.endsAt}}`
- `{{event.timezone}}`
- `{{decision.kind}}`
- `{{campaign.purpose}}`

Unknown placeholders fail the recipient attempt safely; they are not evaluated as code or HTML. Template content is plain text in this delivery implementation.

## Database roles and keys

The API uses two independent database pools:

- `eventor_runtime` for tenant-scoped application commands.
- `eventor_auth` for global identity lookup, password-hash verification, login throttling and opaque session storage.

The notification worker connects separately as `eventor_worker`. Do not run API or worker processes with migration/owner credentials. The worker can discover only tenant IDs and can read SMTP/contact ciphertext only through narrowly scoped delivery functions; it cannot directly select delivery configuration tables.

Configure separate, cryptographically random 32-byte keys, base64-encoded in deployment secrets:

- `EVENTOR_FIELD_ENCRYPTION_KEY`
- `EVENTOR_CONTACT_ENCRYPTION_KEY`
- `EVENTOR_DELIVERY_CREDENTIALS_KEY`
- `EVENTOR_AUTH_FINGERPRINT_KEY`

Never reuse one key for another purpose. Both API and worker require the delivery credential key; the worker also requires the contact encryption key. Key rotation requires an explicit re-encryption procedure. Replacing a key alone makes existing ciphertext unreadable.

Both database connection URLs should use TLS with certificate and hostname verification in production (for example, PostgreSQL `sslmode=verify-full` with a trusted CA). Configure database passwords outside this repository.

## Contact-value encryption contract

The contact registry stores email/phone values in `person_contact_points.encrypted_value`. Use the shared `src/contact-crypto.ts` codec:

- Format: `ECP1` magic bytes, a fresh 12-byte nonce, a 16-byte AES-256-GCM authentication tag, then ciphertext.
- Key: dedicated `EVENTOR_CONTACT_ENCRYPTION_KEY`.
- Key derivation: HMAC-SHA-256 domain separation with `eventor:contact-point-encryption:v1`.
- Authenticated context: tenant UUID and contact kind (`email`, `phone`, `postal` or `other`).

Existing ciphertext without the ECP1 envelope is legacy/unknown format and is deliberately rejected. Do not attempt fallback decryption or send it. Before enabling delivery, migrate or re-enter legacy contacts through an approved source format, verify them, and ensure consent is still `permitted`.

## Staff session security

- Passwords are verified as Argon2id PHC hashes. Successful logins rehash outdated parameters.
- The session cookie is a random 256-bit opaque token named `__Host-eventor_session`, marked `Secure`, `HttpOnly`, `SameSite=Strict` and `Path=/`. Only its SHA-256 hash is stored.
- A separate CSRF token is held in a readable `__Host-eventor_csrf` cookie and returned to the same-origin client at login. State-changing requests must send the matching `X-CSRF-Token` header.
- Sessions are bound to a specific user, organization and active membership.
- Login failures are throttled using HMAC fingerprints of normalized email and request source.
- Configure exact allow-listed origins. Do not put secrets in logs.

When behind a reverse proxy, configure `EVENTOR_TRUST_PROXY_CIDRS` with only proxy addresses/CIDRs you control. Do not trust arbitrary forwarded headers.

## Run

Build and start the API:

```sh
npm install
npm run build
npm start
```

Start the worker as a separate process:

```sh
npm run build
npm run start:worker
```

The worker requires `EVENTOR_WORKER_DATABASE_URL`, `EVENTOR_CONTACT_ENCRYPTION_KEY` and `EVENTOR_DELIVERY_CREDENTIALS_KEY`.

## Tests

From this directory:

```sh
npm install --no-package-lock
npm test
```

CI regenerates OpenAPI TypeScript declarations, runs strict TypeScript compilation and API tests, applies checksum-verified PostgreSQL migrations, and exercises tenant isolation, SMTP configuration, explicit queueing, worker claims and retry-state transitions.

## Remaining integration work

- Connect the staff frontend to login, CSRF handling, campaign review/confirmation/queueing and SMTP settings/test routes.
- Add operator UI for uncertain outcomes, permanent failures and campaign cancellation before delivery.
- Implement an SMS provider adapter only when a concrete provider is selected; keep it optional and tenant-configurable.
- Implement provider callbacks for final delivery/bounce status where supported. SMTP acceptance alone remains `sent`, not `delivered`.
- Complete the rest of the OpenAPI operations and production runbooks for backup, recovery, network egress and secret rotation.
