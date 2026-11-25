# ADR 0023 — Permissioned collaboration grant review and lifecycle

- Status: accepted.
- Date: 2026-11-25.
- Related: #104/#112, ADR 0006/0021/0022, Cross-Organization Collaboration Design v0.3.

## Context

The existing proposal/acceptance/revocation commands already enforce organization-scoped collaboration management. Runtime routes and permission-filtered review were missing, while the runtime database role retained raw SELECT access to grants. The original constraint also contradicted the revoke command by requiring acceptance facts when an unaccepted proposal was withdrawn.

## Decision

Expose selected-party list/detail and acceptance/revocation commands over the existing grant aggregate. Every operation requires active organization-scoped `collaboration.manage` in the selected tenant. General organization administration or membership alone is insufficient. List/detail access is audited. The list allowlists party/scope identifiers, purpose, allowed action codes, status, validity and lifecycle timestamps; it excludes actor identities, source records, private revisions and raw projection configuration. Detailed review also returns the deliberately shared projection configuration. It does not query the provider's underlying booking, venue, guest or commercial records, and it enumerates no organization directory.

Only the recipient can accept; only the grantor can revoke. Existing functions and audit attribution remain authoritative. New wrapper commands lock the grant and revalidate party, action, state and acceptance window before executing. An already-active acceptance belongs to its original accepting actor. Cached acceptance replies recheck current role, grant state/window and accepting actor; source revocation/expiry cannot return a stale cached active response. Cached revocation replies recheck grantor authority and retain the first revocation timestamp/audit. Revocation reasons are bounded, validated and stored only through the existing grantor audit; they are omitted from shared projections.

Migration 198 revokes direct application-role table access and grants only scoped wrapper execution. It also permits a revoked proposal to retain null acceptance actor/time, matching the existing command. Active/expired grants still require genuine acceptance; acceptance actor/time and revoked-status/time pairing remain required. No acceptance is manufactured and no historical facts are backfilled. Concurrent acceptance and revocation serialize: acceptance first retains authentic acceptance under subsequent revocation; revocation first prevents acceptance.

## Limits and follow-up

This is a runtime review/lifecycle foundation. Staff controls, new proposal creation/discovery, scoped partner booking selection and cross-organization notice publication remain follow-ups. Accepting a grant changes neither booking/event status nor guest access; each downstream operation must enforce the exact capability and projection separately. Revocation blocks future protected use while retaining prior association/snapshot/audit provenance. It does not cancel provider bookings, organizer events or published receipts.

SQL/API tests cover party/context/permission boundaries, shared projections, validity, never-accepted revocation, retained accepted history, retry sanitization and authority rechecks. Real runtime-role concurrent transactions and PostgreSQL-backed API retries verify both transition orders and role/grant revocation. No live SMTP/HTTPS or deployed installation acceptance is implied.
