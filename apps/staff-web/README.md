# Eventor staff web

Vue 3 + TypeScript + Vite staff workspace for authentication, organization email delivery and event-notification operations.

## Development

Use Node.js 22.16.0 or a compatible Node 22 release.

```sh
cd apps/staff-web
npm install
npm run dev
```

The Vite development server listens on port 5173. Requests to `/api/*` are proxied to `http://127.0.0.1:8080` by default, with the `/api` prefix removed. Set `EVENTOR_API_PROXY_TARGET` to override the API origin.

For a different same-origin API prefix or reverse-proxy path at build/runtime, set `VITE_API_BASE_URL` (default: `/api`). Deploy the staff UI and API behind the same HTTPS origin so the API's `__Host-` Secure session and CSRF cookies work as designed. The API's `EVENTOR_ALLOWED_ORIGINS` must include the staff UI origin exactly.

## Implemented UI

- Staff sign-in, session restoration through `GET /me`, and server-side logout.
- Organization SMTP settings with write-only credentials, configuration revision status and explicit test email.
- Permission-filtered, paginated campaign list with event, purpose, status and recipient counts.
- Campaign review with recipient/channel/exclusion counts and immutable template snapshot, explicit confirmation, separate queue authorization and pre-send cancellation.
- Campaign progress aggregates and a paginated, status-filterable delivery-attempt report with retry indicators, safe failure codes and timestamps.
- Operator reconciliation for uncertain/permanent failed attempts with an explicit verified outcome and mandatory audit reason.
- Separate operator-authorized retries for eligible failed attempts; the API creates a new attempt and enforces permissions and retry limits.
- API-enforced event permission and CSRF checks; the UI does not make security decisions. Delivery projections never expose recipient contact values or provider message references.

Campaigns are listed only when the current membership has event-scoped preview permission. The database has a provider-neutral normalized callback inbox, but a provider-specific signature-verifying adapter is still required before callbacks can be accepted in production. SMTP acceptance remains distinct from confirmed delivery.

## Delivery semantics

A successful SMTP test enables only the configuration revision tested. Saving a new revision requires a new test. Campaign confirmation does not queue or send. Queueing is a separate explicit action. Cancellation is possible only while a campaign is still queued and before the first worker claim. SMTP `sent` records server acceptance, not inbox delivery. SMS is not configured and remains suppressed. Uncertain submissions are never automatically retried; an operator must reconcile the outcome before any retry.
