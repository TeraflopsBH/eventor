# Eventor API module

This package implements the first Fastify command routes for the v0.3 API contract. It is a route module, not a deployable service by itself: no staff login/session store, database provisioning, worker process or production deployment has been introduced.

## Commands implemented

- `POST /bookings/{bookingId}/reservations/release`
- `POST /events/{eventId}/change-requests`
- `POST /event-change-requests/{requestId}/approve`
- `POST /event-change-requests/{requestId}/reject`
- `POST /event-change-requests/{requestId}/execute`

The handlers call permission-gated PostgreSQL functions. They do not directly update event, reservation or audit tables.

## Host integration boundary

The host application must provide:

- A `pg.Pool` connected as `eventor_runtime`.
- `authenticateStaff`, which validates a signed server-side session, resolves the selected active membership and returns its user, organization and membership UUIDs. It must not derive these values from request headers or request bodies.
- `verifyMutationOrigin`, which verifies the cookie-authenticated mutation's CSRF token and trusted origin.
- A 32-byte AES-256 key when the API accepts `reasonInternal`. The Node adapter encrypts this value before storing it in the migration's `bytea` field. The versioned ciphertext envelope is `EV1 | 12-byte nonce | 16-byte GCM tag | ciphertext`.

Example composition (the authentication/session implementation is intentionally supplied by the host):

```ts
const api = buildApi({
  pool,
  authenticateStaff: staffSessionAuthenticator,
  verifyMutationOrigin: csrfAndOriginVerifier,
  privateFieldEncryptionKey: Buffer.from(process.env.EVENTOR_FIELD_ENCRYPTION_KEY!, "base64"),
});
```

Fail closed when no validated session or trusted mutation origin exists. The active membership and scoped permission are checked again by the database command, after the trusted organization context has been set transaction-locally.

## Idempotency and transactions

Every mutating endpoint requires `Idempotency-Key`. The API stores a canonical JSON SHA-256 request hash and the completed response in `eogp.idempotency_records` in the same transaction as the command. Same-key/same-payload retries replay the stored response; same-key/different-payload requests return 409. The tenant setting is transaction-local and comes only from the validated session principal.

SQLSTATEs are mapped to the API's safe error envelope. Raw database messages and private field values are not returned to clients.

## Generated contract types and tests

From this directory:

```sh
npm install --no-package-lock
npm run typecheck
npm test
```

`npm run generate:openapi` generates the TypeScript declarations in `src/generated/openapi.d.ts` from the canonical `docs/api/openapi.v0.3.yaml`. Build and tests regenerate the declarations before compilation. The generated declaration is a build artifact and is not hand-maintained.

## Deliberate remaining boundary

Executing an event change may insert a transactional outbox record with topic `event.change.notification_requested`. This means dispatch was requested and durably queued; it does **not** mean a guest campaign was created or a message was delivered. The audience-resolution/campaign preparation and delivery worker remain separate implementation work. Provider-side booking disruption notices also remain separate from organizer-owned event decisions.
