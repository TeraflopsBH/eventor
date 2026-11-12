# Booking cancellation policy management — implementation design v0.3

## Purpose

Provide organization-owned, versioned cancellation policies that can be selected when preparing booking offers. Policy authoring is independent of any particular venue, jurisdiction or provider. No GHB-specific refund percentage, notice period, deposit, fee, tax treatment or legal wording is seeded.

## Existing schema reused

Migration 000004 already defines:

- `eogp.cancellation_policies`: organization-owned policy identity, unique code, name and active/retired status.
- `eogp.cancellation_policy_revisions`: immutable-after-publication revisions with `customer_mode`, `approval_rules`, `commercial_rules`, `notice_rules`, `public_terms`, state and publication timestamp.

Migration 000020 already attaches the generic published-revision immutability guard. Migration 000048 requires an active published cancellation-policy revision when an offer revision is saved and pins its revision ID and terms. Migration 000051 carries that exact revision ID into the confirmed booking snapshot. This implementation does not alter those snapshot relationships.

## Commands and authorization

Migration 000061 adds:

- `get_booking_cancellation_policies`
- `create_booking_cancellation_policy`
- `create_booking_cancellation_policy_revision`
- `update_booking_cancellation_policy_draft_revision`
- `publish_booking_cancellation_policy_revision`

All commands require matching transaction-local organization context and `booking.manage`. Mutations write audit events. Runtime direct table access is revoked; the API uses narrowly granted SECURITY DEFINER commands. The revision validator requires the supported customer mode, non-empty bounded public terms, and three bounded JSON objects. Rule-object semantics remain organization-defined until the cancellation decision engine's formal rule vocabulary is specified.

A policy can have only one latest draft. A successor is created only after the preceding revision is published. Only the latest draft can be updated and only the latest draft can be published. Published revisions cannot be edited or deleted.

## API

The staff API exposes organization-scoped list/create operations plus revision create/update/publish commands. Mutations follow the existing idempotency and CSRF/session conventions. OpenAPI v0.3 documents the routes and payloads.

## Snapshot and lifecycle guarantees

- Offers must reference a published active cancellation-policy revision.
- Issued offer revisions preserve the exact policy revision reference and public terms snapshot.
- Confirmed booking snapshots preserve the same policy revision ID and customer terms.
- Publishing a later revision does not rewrite existing offer or booking snapshots.
- Policy management does not itself execute refunds, fees, credits, deposits or cancellation decisions. Those remain explicit, audited booking-cancellation workflow operations.

## Validation status

Static inspection only. CI is intentionally deferred while the monthly GitHub Actions allowance is exhausted. No PostgreSQL migration execution, API tests, TypeScript build or browser tests were run for this change.
