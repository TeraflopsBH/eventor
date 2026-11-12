# Eventor staff web

Vue 3 + TypeScript + Vite staff workspace for authentication, organization email delivery, event-notification operations and venue booking inquiry review.

## Development

Use Node.js 22.16.0 or a compatible Node 22 release.

```sh
cd apps/staff-web
npm install
npm run dev
```

The Vite development server listens on port 5173. Requests to `/api/*` are proxied to `http://127.0.0.1:8080` by default, with the `/api` prefix removed. Set `EVENTOR_API_PROXY_TARGET` to override the API origin.

For a different same-origin API prefix or reverse-proxy path at build/runtime, set `VITE_API_BASE_URL` (default: `/api`). Deploy the staff UI and API behind the same HTTPS origin so the API's `__Host-` Secure session and CSRF cookies work as designed. The API's `EVENTOR_ALLOWED_ORIGINS` must include the staff UI origin exactly.

## Testing

The staff-web package uses Node.js's built-in test runner and native TypeScript type stripping; no additional test framework or runtime dependency is required. With Node.js 22.16.0 installed:

```sh
cd apps/staff-web
npm test
```

The focused suites cover booking-form schema validation, field ordering, translation-key migration, canonical/base-language editing, translation read purity, completeness counts, save/publication validation gates, and the public booking workflow: translated content with per-field fallback, translation completeness warnings, multi-select initialization/toggling/bounds, number normalization, requester cleanup, and submission pinned to the exact loaded published revision. Schema-aware draft coverage verifies required fields, text lengths, numeric bounds/integer constraints, checkbox acceptance, select/multi-select option membership, multi-select bounds, numeric normalization and retention of unknown legacy answer keys. Conversion coverage verifies that decrypted draft values are presented with labels and select-option text from the exact source form revision, including visibility of unknown legacy answer keys. They import feature modules directly, so they do not require a browser or running API. API-side answer validation, stale-revision rejection and encrypted inquiry persistence are covered separately by the API test suite.

## Implemented UI

- Staff sign-in, session restoration through `GET /me`, and server-side logout.
- Organization SMTP settings with write-only credentials, configuration revision status and explicit test email.
- Optional Resend callback setup: prepare the public endpoint, activate the encrypted Svix signing secret, and process signed delivered/bounced events.
- Permission-filtered, paginated campaign list with event, purpose, status and recipient counts.
- Campaign review with recipient/channel/exclusion counts and immutable template snapshot, explicit confirmation, separate queue authorization and pre-send cancellation.
- Campaign progress aggregates and a paginated, status-filterable delivery-attempt report with retry indicators, safe failure codes and timestamps.
- Operator reconciliation for uncertain/permanent failed attempts with an explicit verified outcome and mandatory audit reason.
- Separate operator-authorized retries for eligible failed attempts; the API creates a new attempt and enforces permissions and retry limits.
- Permission-aware booking inquiry inbox with status and assignee filters, pagination and requester/request summaries.
- Inquiry detail showing decrypted requester information, requested booking times/spaces, answers from the pinned form schema, internal notes and immutable status/assignment history.
- Assignment to an active same-organization member, controlled review status transitions with audit reasons, and append-only internal note creation. Declined/spam inquiries are terminal and cannot be reopened or reassigned.
- Inquiry action controls are shown from a permission projection; the backend database commands remain authoritative. The assignee roster returns only active membership IDs and display names, never colleague email/contact information.
- Authorized staff can convert a received/under-review inquiry into a separate booking draft. Conversion preserves the source inquiry and creates immutable revision 1 with the submitted values retained as an ECP1 ciphertext wrapper; it does not issue an offer or reserve/confirm availability.
- Authorized draft readers can open the linked draft, inspect its current decrypted revision and revision history, and authorized draft managers can create successor revisions. Values, space lines and resource lines are submitted through the API; values are ECP1-encrypted before storage, every revision is append-only, stale revision writes are rejected, and active holds on the current revision must expire or be released before the draft can be edited.
- API-enforced organization scope, inquiry permissions and CSRF checks; the UI does not make security decisions. Delivery projections never expose recipient contact values or provider message references.

Campaigns are listed only when the current membership has event-scoped preview permission. Resend callbacks are accepted only after the signing secret has been activated and the exact raw-body Svix signature passes verification. SMTP acceptance remains distinct from recipient-mail-server delivery and inbox placement.

## Delivery semantics

A successful SMTP test enables only the configuration revision tested. Saving a new revision requires a new test. Campaign confirmation does not queue or send. Queueing is a separate explicit action. Cancellation is possible only while a campaign is still queued and before the first worker claim. SMTP `sent` records server acceptance, not inbox delivery. SMS is not configured and remains suppressed. Uncertain submissions are never automatically retried. A verified Resend callback can resolve an ambiguous submission from its pre-submission Message-ID; otherwise an operator must reconcile it before any retry. Resend's `email.delivery_delayed` event is intentionally non-terminal while the provider continues its own retries.


## Booking draft allocation editor

The staff-web booking-draft workspace loads the active organization allocation catalogue through the authenticated, draft-read-authorized API. Structured space rows select an active venue space and capture usage phase, start/end timestamps and optional expected attendance. Resource rows select a reservable resource type and capture requested quantity. The API's catalogue capacity is explicitly distinguished from live availability; server-side allocation and final booking confirmation checks remain authoritative.

Run the focused helper tests with npm test from apps/staff-web; the new booking-draft-allocations.test.mjs covers catalogue membership, interval/offset validation, capacity bounds, duplicate prevention and normalization. This slice is in draft PR #74, stacked on PR #73. Local tests, typecheck, production build, migration execution and browser validation remain pending; CI was not triggered while the monthly Actions allowance is exhausted.


## Booking allocation availability preview

The booking-draft allocation editor includes an explicit availability check. It reports overlapping active space holds, confirmed bookings and maintenance blocks for each proposed space interval, and estimates available pooled-resource quantities over the overall requested booking interval. Results are invalidated when the draft, dates or allocation rows change. Resource capacity is not checked until both overall booking dates are supplied.

The preview is read-only and advisory. It does not reserve inventory and cannot guarantee that availability remains unchanged; the existing server-side revision and final booking-confirmation checks remain authoritative. API route coverage is included in apps/api/test/server.test.ts.


When a space conflicts, the preview can offer other conflict-free spaces in the same venue that meet the line's requested capacity. Staff explicitly apply an alternative; doing so invalidates the prior preview and requires another check. Resource results also show estimated available quantity per active pool, helping staff understand where supply exists. Pool rows are informational rather than assignments: the current booking resource-line model allocates by resource type, not by a pinned pool.
