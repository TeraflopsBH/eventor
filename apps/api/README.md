# Eventor API and notification delivery worker

This package contains the first deployable command API and a separate tenant-aware notification worker. It is an application foundation, not the complete staff product or delivery system.

## API commands

- `POST /auth/session` — Argon2id staff login bound to an active organization membership.
- `DELETE /auth/session` — revoke the current database-backed session.
- `GET /me` — return the current principal and active organization memberships.
- `GET /organizations/{organizationId}/booking-inquiries?status=&assignedToMembershipId=&limit=&offset=` — permission-filtered inquiry inbox.
- `GET /organizations/{organizationId}/booking-inquiry-capabilities` — read the active membership's assignment, status-management and annotation permission flags.
- `GET /organizations/{organizationId}/booking-inquiry-assignees` — assignment-permission-gated active membership roster with display names only; no email or contact data.
- `GET /booking-inquiries/{inquiryId}` — decrypted inquiry detail, published field schema, internal annotations and status/assignment histories.
- `POST /booking-inquiries/{inquiryId}/assignment` — assign or unassign an active organization member.
- `POST /booking-inquiries/{inquiryId}/status` — change inquiry review status with an audit reason.
- `POST /booking-inquiries/{inquiryId}/annotations` — append an internal-only staff note.
- `POST /booking-inquiries/{inquiryId}/create-draft` — atomically convert an open inquiry into a separate draft with immutable revision 1; replays return the same draft.

- `POST /booking-draft-revisions/{revisionId}/offers` — prepare a commercial offer from the exact current immutable draft revision; line prices come from a pinned published price list, and cancellation/approval policy revisions are pinned.
- `POST /booking-offers/{offerId}/revisions` — create an immutable successor offer revision; superseding a prepared/issued revision requires an explicit flag and reason.
- `GET /booking-offers/{offerId}` — read the permission-checked staff offer projection and revision/decision history.
- `POST /booking-offers/{offerId}/issue` — explicitly issue the latest prepared revision. A one-use customer capability is deterministically derived from the dedicated `EVENTOR_BOOKING_CAPABILITY_KEY`; only its SHA-256 hash is stored, and the raw token is returned to staff once (or deterministically re-derived on an idempotent replay).
- `POST /booking-offers/{offerId}/email` — explicitly queue the issued offer to the encrypted email address on its source inquiry. Requires the active customer capability returned by issue; uses the organisation's tested SMTP configuration and a separate idempotency key.
- `GET /booking-offers/{offerId}/email-deliveries` — permission-gated, paginated status/history projection. It exposes delivery IDs, safe failure codes, timestamps and retry counts, never recipient addresses or ciphertext.
- `POST /booking-offer-email-deliveries/{deliveryId}/reconcile` — record an audited `confirmed_sent` or `confirmed_not_sent` outcome for an uncertain SMTP submission. This operation never sends mail.
- `POST /booking-offer-email-deliveries/{deliveryId}/retry` — separately authorise one manual retry, only after explicit non-acceptance has been recorded and while the exact offer revision remains current and unexpired. Automatic transient retries remain capped at five.
- `GET /public/booking-offers/{offerId}` — read only the customer-visible terms using `X-External-Booking-Token`; does not consume the capability.
- The staff-web customer page is served at `/offers/{offerId}#token={capability}`. The capability is kept in the URL fragment and sent only in the `X-External-Booking-Token` header; the page uses `no-referrer` and `noindex` metadata. Static hosting must route `/offers/*` to the SPA entry point.
- `POST /booking-offers/{offerId}/accept` and `POST /booking-offers/{offerId}/reject` — customer decisions against the exact issued offer revision. Capabilities are single-use; decision payloads and customer-provided names/notes are encrypted and idempotent replay is supported.
- `GET /booking-offers/{offerId}/approvals` and `POST /booking-offers/{offerId}/approvals` — inspect the pinned approval requirements and append an authorized decision for one exact offer revision/rule. Rule counts, distinct approvers and configured separation-of-duties are enforced in PostgreSQL.
- `GET /organization/booking-approval-policies` and `POST /organization/booking-approval-policies` — list and create organization-owned approval policies (requires `booking.manage`).
- `POST /booking-approval-policies/{policyId}/revisions`, `PUT /booking-approval-policies/{policyId}/revisions/{revisionId}` and `POST /booking-approval-policies/{policyId}/revisions/{revisionId}/publish` — create or update the latest draft policy revision and explicitly publish it. Published revisions are immutable.
- `POST /booking-approval-policies/{policyId}/revisions` and `POST /booking-approval-policies/{policyId}/revisions/{revisionId}/publish` — append a validated draft rules revision, then explicitly publish the latest revision. Published policy revisions are immutable.
- `POST /booking-draft-revisions/{revisionId}/confirm` — explicitly confirm the exact accepted and approved offer; creates booking snapshots/history and converts live space/resource holds in one transaction. The final reservation command serializes capacity and interval checks; any conflict rolls the complete confirmation back.
- `GET /booking-drafts/{draftId}` — permission-checked current revision, decrypted values, field schema, space/resource lines and immutable revision history.
- `POST /booking-drafts/{draftId}/revisions` — create an immutable successor revision with expected-revision concurrency, ECP1-encrypted values and validated space/resource lines.
- `GET /public/organizations/{organizationSlug}/booking-forms/{formCode}` — public read of an active organization's latest published booking form and its versioned field schema.
- `POST /public/organizations/{organizationSlug}/booking-inquiries` — accept an encrypted, idempotent booking inquiry using the exact published form revision supplied by the visitor.
- `POST /bookings/{bookingId}/reservations/release`
- `POST /events/{eventId}/change-requests`
- `POST /event-change-requests/{requestId}/approve`
- `POST /event-change-requests/{requestId}/reject`
- `POST /event-change-requests/{requestId}/execute`
- `GET /event-notification-campaigns?status=&limit=&offset=` — paginated list of campaigns visible to the current membership's event-level `event.notifications.preview` permission.
- `GET /event-notification-campaigns/{campaignId}` — campaign delivery progress and recipient-level aggregate outcomes.
- `GET /event-notification-campaigns/{campaignId}/deliveries?status=&limit=&offset=` — paginated attempt history with channel, pseudonymous recipient reference, attempt number, status, safe failure code and timestamps; no contact data or provider message references.
- `GET /event-notification-campaigns/{campaignId}/review` — permission-gated review of recipient snapshots, channel/exclusion totals and the pinned template; contact values are never returned.
- `POST /event-notification-campaigns/{campaignId}/confirm` — explicitly confirms the fixed audience snapshot. It does not queue or send messages.
- `POST /event-notification-campaigns/{campaignId}/queue` — separate, explicit authorization to queue email delivery. Requires an enabled organization SMTP configuration and event-scoped send permission.
- `POST /event-notification-campaigns/{campaignId}/cancel` — cancel a queued campaign before any SMTP attempt starts; appends suppression events and removes its pending work.
- `GET /organization/delivery/email/configuration` — read safe SMTP settings and credential/test status; never returns credentials.
- `POST /organization/delivery/email/configuration` — create a new immutable SMTP configuration revision. Credentials are write-only.
- `POST /organization/delivery/email/test` — verify the current SMTP connection and send one explicitly requested test message to the supplied address. A successful test enables that exact configuration revision.
- `GET /organization/delivery/email/resend-webhook` — read the safe Resend callback endpoint status and public URL; never returns the signing secret.
- `POST /organization/delivery/email/resend-webhook/prepare` — prepare or replace the organization's Resend callback endpoint URL.
- `POST /organization/delivery/email/resend-webhook/activate` — encrypt and activate the Resend Svix signing secret.
- `POST /webhooks/resend/{endpointId}` — public, signed callback endpoint; staff session authentication is not used. Raw-body Svix verification is mandatory.

All mutating staff routes require an idempotency key, an authenticated session, an allow-listed browser Origin and a valid CSRF token. Database commands enforce tenant and permission checks. Public booking intake routes explicitly declare anonymous access; public booking-offer review and decision routes instead require a purpose-bound customer capability. The signed Resend webhook is separately authenticated with its provider signature.

## Public booking inquiry intake

The public form GET returns only an active organization's latest published revision. The POST requires the form code and exact revision ID, plus an `Idempotency-Key`. It resolves that revision through the constrained database projection, rather than validating against whatever revision is latest at submission time. Previously published revisions remain usable while they remain published; the database submission command rechecks that state before inserting the inquiry.

Before encryption, the API validates the answer object against the immutable revision's versioned `field_schema`. Schema v1 supports `text`, `textarea`, `email`, `phone`, `number`, `date`, `datetime`, `time`, `select`, `multiselect` and `checkbox` fields. It enforces required values, JSON types, string lengths, numeric ranges/integer constraints, date/time formats, unique choice options, option membership and unknown-key rejection. Missing `schemaVersion` is treated as v1 for legacy revisions; an explicit unknown version or unsupported schema property fails closed. Invalid answers return 422 and do not reach the database submission command or consume an inquiry rate-limit slot.

Requester name, email, phone, requested details and validated dynamic answers are stored using the tenant-bound ECP1 AES-256-GCM contact codec. Raw source IPs and raw idempotency keys are not persisted; keyed fingerprints support an organization-scoped limit of ten accepted submissions per source per UTC hour and deterministic replay handling. Idempotent replays do not consume another rate-limit slot. The field contract and example are documented in [Public Booking Form Schema v1](../../docs/product/PUBLIC_BOOKING_FORM_SCHEMA_v1.md). Attachment references are rejected until the upload workflow exists.

## Staff inquiry review

The inbox, detail, assignment, status and annotation routes require an authenticated staff session. Database SECURITY DEFINER projections and commands re-check active membership plus the `booking.inquiry.read`, `booking.inquiry.assign`, `booking.inquiry.manage` or `booking.inquiry.annotate` permission on an organization-scope role grant. Inquiries are not yet linked to a booking, so booking-specific role grants do not authorize inquiry access. Inquiry source and history tables are not directly accessible to the runtime database role. Contact fields and answers are decrypted only in the API after the permission-checked detail projection. Assignment and status changes append immutable histories and audit events. Staff annotations are append-only and internal-only; customer-visible annotations are not supported by these endpoints.

The inquiry capability projection requires `booking.inquiry.read` and reports separate `canAssign`, `canManage`, `canAnnotate`, `canConvert`, `canReadDraft` and `canManageDraft` flags. The conversion flag reflects `booking.inquiry.convert`. Draft reads require `booking.draft.read` or `booking.draft.manage`; successor revisions require `booking.draft.manage`. Because a draft has no confirmed `booking_records` row, draft permissions are currently accepted from active organization-scope grants; booking-scoped grants cannot target a draft UUID. The roster endpoint additionally requires `booking.inquiry.assign`, and returns only active same-organization membership IDs and display names. The UI hides unavailable controls, but every write continues to re-check authorization inside the database SECURITY DEFINER command.

The Vue staff workspace now provides a permission-aware inquiry inbox/detail, active-member assignment, review-status transitions, internal-note creation, status/assignment history, authorized inquiry conversion and a draft editor. The same workspace includes offer preparation/revision/issue, approval requirement review/decisions and explicit confirmation; a separate Approval policies tab provides policy creation, rules-revision authoring and publication. The draft projection decrypts values only after its database permission check; revision writes validate against the pinned source-form schema, re-encrypt values with ECP1 and create immutable successor revisions. The database rejects stale revisions and refuses edits while the previous revision has active space/resource holds. Earlier revisions remain unchanged.

## Booking offers, customer decisions and confirmation

Offer preparation pins one immutable booking draft revision, one published price-list revision, one published cancellation-policy revision and one published approval-policy revision. Line prices are calculated from the pinned price-list items in PostgreSQL; clients do not submit authoritative unit prices or line totals. Manual adjustments are explicit and reasoned. A manually supplied tax amount requires both an audit reason and `booking.approve`; no tax rate or GHB amount is hardcoded.

Offer preparation does not issue an offer. Staff must call the explicit issue command. The API derives a 256-bit customer capability from the dedicated `EVENTOR_BOOKING_CAPABILITY_KEY` using HMAC-SHA-256 over the tenant, membership, offer and idempotency key. The raw capability is not stored in the generic idempotency response or database; the database stores only its SHA-256 hash. Replaying the same issue idempotency key deterministically re-derives the same capability.

The capability is purpose-bound to one exact offer revision. The customer review projection returns only visible commercial terms (prices, requested schedule, venue-space/resource labels and cancellation terms); it excludes staff identities, internal notes and approval requirements. Accept/reject consumes the capability once. Customer name, note and rejection explanation are encrypted with ECP1. Decisions and outcomes are append-only; same-key/same-payload replay returns the original result, while changed-payload reuse conflicts. When a customer attempts a decision after the validity deadline, Eventor commits an `expired` terminal state, revokes the capability and returns HTTP 410.

Approval policy revisions contain JSON rules. Supported condition kinds are `always`, `total_at_least` (amount and currency), `discount_at_least`, and `adjustment_present` (optionally limited to fee/discount/credit). Matching requirements are evaluated at offer-revision creation and pinned to that exact immutable revision. Approvers require `booking.approve`; decisions name the exact offer revision and rule. Repeated decisions by the same membership are prevented, and a separation-of-duties requirement blocks the offer creator from approving. Rejection/return-for-changes blocks confirmation.

Final confirmation is a separate staff command requiring `booking.confirm`, customer acceptance evidence, the exact current draft/offer revision and all pinned approvals. It preflights each required space/resource hold, creates the booking and immutable customer/price/cancellation snapshots, then calls the existing reservation conversion command in the same transaction. The database serializes capacity/overlap checks at conversion. A missing, expired or conflicting hold rolls back the booking row, snapshots, history and all reservation changes. A confirmed booking is idempotently returned on retry.

The API/database and staff-web offer/approval/confirmation and approval-policy management surfaces are implemented. The staff-web SPA also serves a capability-protected customer offer page at `/offers/{offerId}`; it loads the public projection and records customer acceptance/rejection. Staff can explicitly queue an issued offer email to the source inquiry address and inspect its delivery history in the offer workspace. The worker sends it through the pinned, tested organisation SMTP revision; the encrypted capability is decrypted only in the worker and placed in the URL fragment. Temporary SMTP connection/time-out/4xx failures are retried up to five attempts; ambiguous submission is marked `uncertain` and is never automatically resent. Staff can record a verified accepted/not-accepted outcome with an audit reason; only a confirmed-not-accepted submission can receive one separately authorised manual retry, and only while its exact offer revision remains current and unexpired. SMTP acceptance is recorded as `sent`, not proof of inbox delivery. Offer email jobs do not currently use Resend delivery callbacks. PostgreSQL functional/concurrency fixtures for the full commercial workflow remain outstanding. The schema smoke test checks installation/RLS/grants; it does not replace those end-to-end tests. Price-list, cancellation-policy and tax configuration management screens also remain outstanding; current offer preparation requires administrators to supply existing published revision IDs and item codes.

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

A queued campaign continues to use the exact SMTP revision pinned when it was queued. Updating the organization's current SMTP settings affects future queue actions, not already authorized campaigns. A queued campaign can be cancelled only before the worker claims its first attempt. Once sending has started, cancellation is rejected; already accepted or uncertain SMTP messages cannot be recalled.

## Resend SMTP and signed delivery callbacks

Resend is an optional provider adapter; it does not replace organization-owned SMTP. Configure the email host as `smtp.resend.com`, port `587` with STARTTLS (or port `465` with implicit TLS), authentication mode `password`, username `resend`, and the organization's Resend API key as the SMTP password. Eventor continues sending through Nodemailer.

The staff Email Delivery panel provides a two-step callback setup:
1. Prepare the callback URL in Eventor. Configure that exact URL as a webhook in the Resend dashboard, selecting only `email.delivered` and `email.bounced`.
2. Copy the webhook's `whsec_` signing secret from Resend into Eventor and activate it. The secret is encrypted with the delivery-credential key and is never returned by the API.

Set `EVENTOR_PUBLIC_API_BASE_URL` to the externally reachable HTTPS API base URL, including any reverse-proxy API prefix (for example, `https://eventor.example.test/api`). Eventor rejects a non-HTTPS URL. Allow the public callback route through the reverse proxy; apply request-rate and body-size limits there as well.

The callback handler verifies the Svix v1 HMAC signature against the exact raw JSON body and rejects timestamps more than five minutes from server time. The endpoint UUID is a routing identifier, not a secret. Before submitting a Resend message, the worker commits an attempt-specific RFC Message-ID to append-only delivery history and passes that exact ID to Nodemailer. The signed callback's RFC `message_id` is matched against that pre-send record, even when SMTP completion was later recorded as `uncertain`. One Eventor SMTP attempt contains one recipient. The database stores only the event ID, outcome, timestamp and payload hash—not the callback body, recipient address or signing secret.

Only `email.delivered` and `email.bounced` are currently applied. Resend's delivery-delayed events leave the attempt as `sent` while Resend continues its own retry process. A delivered event means the recipient mail server accepted the message, not that it reached the inbox. A bounce is recorded as `bounced`; Eventor does not automatically resend it. Organizations using a different SMTP host continue without provider callbacks.

## Delivery reconciliation and provider events

- `POST /notification-delivery-attempts/{attemptId}/reconcile` records an event-scoped, audited operator decision for an attempt whose effective status is `uncertain` or `failed`. The operator must choose a verified outcome (`confirmed_sent`, `confirmed_not_sent`, `confirmed_delivered` or `confirmed_bounced`) and provide a reason. Reconciliation never sends a message.
- `POST /notification-delivery-attempts/{attemptId}/retry` is a separate, explicit action. It requires both delivery-management and send permissions, a reason, the latest failed attempt, and remaining retry budget. It creates a new immutable attempt; uncertain attempts cannot be retried until reconciled as not sent.
- Resend is the first optional provider-specific callback adapter. Migrations 000038–000039 provide tenant-specific encrypted Svix secrets, a signed public callback, idempotent event ingestion and stable pre-submission Message-ID correlation. The callback only updates an exact matching Resend SMTP attempt; if it arrives while the worker is still completing SMTP, the API returns a retryable response so the provider can deliver the event again.
- A verified Resend callback can resolve an `uncertain` attempt to `delivered` or `bounced` without resending it. Other organization-configured SMTP hosts continue without provider delivery/bounce callbacks. SMTP acceptance remains `sent`, not proof of inbox placement.

The worker records SMTP acceptance as `sent`; it does not claim that the recipient read or even received the message. Temporary connection and SMTP 4xx failures are retried with bounded exponential backoff (up to five attempts). Permanent 5xx and configuration/template errors are not automatically retried. If the connection fails at the SMTP DATA stage and acceptance is ambiguous, the attempt is marked `uncertain` and is not automatically resent, to avoid duplicate messages. Expired in-flight leases are also marked uncertain for operator reconciliation.

SMS recipients are recorded as suppressed with `SMS_CHANNEL_NOT_CONFIGURED`. `src/sms-transport.ts` defines a provider-neutral adapter/registry contract, but Eventor ships no vendor implementation and no SMS provider is integrated or called. A provider must be explicitly selected and its adapter installed before SMS can be enabled. SMTP acceptance and delivery attempts never modify RSVP, invitation or attendance history, and notification failure never rolls back an event cancellation or postponement.

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

The notification worker connects separately as `eventor_worker`. Do not run API or worker processes with migration/owner credentials. The worker can discover only tenant IDs and can read SMTP/contact ciphertext only through narrowly scoped delivery functions; it cannot directly select delivery configuration tables. It polls separate tenant-ID-only queues for campaign email, booking offer email and offer expiry. Offer email claims return only the exact issued revision, encrypted destination/capability, and pinned SMTP configuration; worker completion records audited outcomes and retry state.

Configure separate, cryptographically random 32-byte keys, base64-encoded in deployment secrets:

- `EVENTOR_FIELD_ENCRYPTION_KEY`
- `EVENTOR_CONTACT_ENCRYPTION_KEY`
- `EVENTOR_DELIVERY_CREDENTIALS_KEY`
- `EVENTOR_AUTH_FINGERPRINT_KEY`
- `EVENTOR_PUBLIC_INQUIRY_FINGERPRINT_KEY`
- `EVENTOR_BOOKING_CAPABILITY_KEY`

Never reuse one key for another purpose. The API requires all six keys; the notification worker requires the contact-encryption and delivery-credential keys. Set `EVENTOR_PUBLIC_APP_BASE_URL` on the worker to the externally reachable HTTPS staff-web origin (including any application path prefix) before enabling offer email delivery; without it, offer email jobs remain queued. The public inquiry API uses the contact key for tenant-bound ECP1 encryption and its dedicated public-inquiry fingerprint key for source/idempotency fingerprints. Keep `EVENTOR_BOOKING_CAPABILITY_KEY` stable while any issued customer offer links remain valid; rotating it invalidates those links and prevents deterministic capability re-derivation for an issue idempotency replay. Rotate only after outstanding capabilities have expired/revoked or after an explicit re-issue plan. Key rotation for encryption keys requires an explicit re-encryption procedure. Replacing an encryption key alone makes existing ciphertext unreadable.

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

The API requires `EVENTOR_RUNTIME_DATABASE_URL`, `EVENTOR_AUTH_DATABASE_URL`, `EVENTOR_ALLOWED_ORIGINS`, `EVENTOR_AUTH_FINGERPRINT_KEY`, `EVENTOR_FIELD_ENCRYPTION_KEY`, `EVENTOR_CONTACT_ENCRYPTION_KEY`, `EVENTOR_DELIVERY_CREDENTIALS_KEY`, `EVENTOR_PUBLIC_INQUIRY_FINGERPRINT_KEY` and `EVENTOR_BOOKING_CAPABILITY_KEY`. The worker requires `EVENTOR_WORKER_DATABASE_URL`, `EVENTOR_CONTACT_ENCRYPTION_KEY` and `EVENTOR_DELIVERY_CREDENTIALS_KEY`. Offer email delivery additionally requires the worker-only `EVENTOR_PUBLIC_APP_BASE_URL`.

## Tests

From this directory:

```sh
npm install --no-package-lock
npm test
```

CI regenerates OpenAPI TypeScript declarations, runs strict TypeScript compilation and API tests, applies checksum-verified PostgreSQL migrations, and exercises tenant isolation, SMTP configuration, explicit queueing, worker claims and retry-state transitions.

## Remaining integration work

- Add price-list, cancellation-policy and tax configuration workspaces. Current offer preparation uses explicit published revision UUIDs and price-list item codes; no GHB pricing, cancellation terms or tax rates are hardcoded.
- Add PostgreSQL end-to-end fixtures for offer/approval/confirmation, including forced overlap/capacity failures and concurrent confirmation; current added smoke coverage verifies installation, RLS, function grants and API route behavior.
- Expand the staff UI to the remaining event, booking, venue and guest workflows.
- Implement an SMS provider adapter only when a concrete provider is selected; keep it optional and tenant-configurable.
- Extend provider-specific status handling only when another concrete provider is selected. Resend's raw-body signature verification, exact Message-ID correlation and delivered/bounced callbacks are implemented. SMTP acceptance alone remains `sent`, not `delivered`.
- Complete the rest of the OpenAPI operations and production runbooks for backup, recovery, network egress and secret rotation.
\nAll campaign listing, progress, review and delivery-report projections require the event-scoped `event.notifications.preview` permission. Campaign list visibility is evaluated per event; a membership cannot enumerate campaigns for events it cannot preview. The delivery report intentionally omits recipient destination values, ciphertext, and provider message references. Pagination is bounded to 100 rows per page.