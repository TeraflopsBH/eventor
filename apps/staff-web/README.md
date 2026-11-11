# Eventor staff web

Vue 3 + TypeScript + Vite staff workspace for the currently implemented authentication, organization email-delivery and event-notification campaign API routes.

## Development

Use Node.js 22.16.0 or a compatible Node 22 release.

```sh
cd apps/staff-web
npm install
npm run dev
```

The Vite development server listens on port 5173. Requests to `/api/*` are proxied to `http://127.0.0.1:8080` by default, with the `/api` prefix removed. Set `EVENTOR_API_PROXY_TARGET` to override the API origin.

For a different same-origin API prefix or reverse-proxy path at build/runtime, set `VITE_API_BASE_URL` (default: `/api`). The browser uses credentialed same-origin requests; deploy the staff UI and API behind the same HTTPS origin so the API's `__Host-` Secure session and CSRF cookies work as designed. The API's `EVENTOR_ALLOWED_ORIGINS` must include the staff UI origin exactly.

## Implemented UI

- Staff sign-in, session restoration through `GET /me`, and server-side logout.
- Organization SMTP settings with write-only credentials, configuration revision status and explicit test email.
- Campaign review by UUID, recipient/channel/exclusion counts, immutable template snapshot, explicit confirmation, separate queue authorization and pre-send cancellation.
- API-enforced authorization and CSRF checks; the UI does not make security decisions.

The API currently exposes campaign review by ID but no campaign-list endpoint. Until one is implemented, staff must obtain the campaign UUID from the authorized workflow and enter it here. The screen deliberately does not expose recipient names, email addresses or phone numbers.

## Delivery semantics

A successful SMTP test enables only the configuration revision tested. Saving a new revision requires a new test. Campaign confirmation does not queue or send. Queueing is a separate explicit action. Cancellation is possible only while a campaign is still queued and before the first worker claim. SMTP `sent` records server acceptance, not inbox delivery. SMS is not configured and remains suppressed.
