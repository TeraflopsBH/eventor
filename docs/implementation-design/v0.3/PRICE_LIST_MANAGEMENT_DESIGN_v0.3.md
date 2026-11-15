# Price-list management design v0.3

**Status:** implementation slice on `feat/booking-price-list-management`, stacked on PR #28  
**Scope:** organization-owned price lists, draft revisions, line-item authoring and explicit publication

## Goals

Provide the organization with a controlled way to author the prices used by booking offers. Reuse the existing `booking_price_lists`, `booking_price_list_revisions` and `booking_price_items` tables created in migration 000004. Do not introduce a parallel pricing model.

## Aggregate and lifecycle

- A price list has a stable organization-scoped code, display name, scope and active/retired lifecycle.
- Creating a price list creates revision 1 in draft state.
- Only one latest draft may exist for a price list. The latest draft can be corrected in place; after publication, changes require a successor revision.
- A revision defines currency, tax basis and optional effective-from/effective-until bounds.
- A revision contains up to 500 billable items. Each item has a stable code within that revision, customer-facing label, unit, non-negative unit amount, optional tax code and quantity bounds.
- A draft save replaces the complete item set atomically. Empty drafts may be saved but cannot be published.
- Publication is explicit and requires at least one item. Published revisions and their items are immutable.
- Offers select and pin an exact published revision. Later publication never changes existing offer terms.

## Security and audit

- All commands require the active organization context and `booking.manage`.
- The API runtime role has no direct table read/write access to price-list tables. Reads and mutations go through permission-checked SECURITY DEFINER functions.
- Tenant RLS and FORCE RLS remain enabled on the existing tables.
- Create, revision creation, draft replacement and publication each append an actor-attributed audit event.
- No GHB prices, tax rates, item catalogue, currency or tax treatment are seeded or inferred.

## Effective periods

Effective bounds are eligibility metadata on each revision. They do not act as a unique key: overlapping windows are permitted because published revisions cannot be edited to close a previous open-ended period. Offer preparation must continue to reference the exact selected revision and enforce the applicable effective-bound rules for the requested booking period. Staff must choose the intended revision explicitly.

## API

- `GET /organization/booking-price-lists`
- `POST /organization/booking-price-lists`
- `POST /booking-price-lists/{priceListId}/revisions`
- `PUT /booking-price-lists/{priceListId}/revisions/{revisionId}`
- `POST /booking-price-lists/{priceListId}/revisions/{revisionId}/publish`

All mutations use the existing session, CSRF, origin and idempotency controls. OpenAPI v0.3 is the contract source.

## Validation still required

- Execute migration 000060 on PostgreSQL 18 and run the commercial schema smoke test.
- Add PostgreSQL functional tests for cross-tenant IDs, permission denial, duplicate item codes, invalid quantities, empty publication, draft correction, successor creation, publication immutability and concurrent publish/revision creation.
- Run API and staff-web typecheck/build/test suites when a local PostgreSQL-capable validation environment or CI allowance is available.
- Verify the offer preparation effective-period checks against this revision model before production use.
