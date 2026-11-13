# Organization tax configuration — implementation design v0.3

## Scope

Migration 000062 adds organization-owned, versioned tax profiles. A profile revision records an organization-defined jurisdiction/authority identifier, tax registration identifier, currency, tax basis, rounding method and decimal scale, effective window, and an immutable tax-code catalogue.

Tax-code treatments are deliberately limited to configuration labels:

- `percentage`: requires a rate from 0 through 100.
- `zero_rated`, `exempt`, `out_of_scope`, and `manual`: rate must be null.

Codes are unique within a revision. A revision can contain up to 200 codes. No jurisdiction, registration status, legal classification, rate, exemption, rounding law, or tax advice is inferred or seeded.

## Price-list and offer linkage

A price-list revision may select one published tax-profile revision. The database requires matching currency and tax basis. When a profile is selected, every price item must have a `taxCode` present in that exact profile revision. A `not_applicable` profile has no tax-code catalogue and requires every price-item `taxCode` to be null. Publication also checks that the tax profile's effective window covers the price-list revision's effective window.

The selected revision is stored as a foreign key on the immutable price-list revision. New offer revisions automatically receive a snapshot of the selected tax profile revision and its tax-code catalogue in `terms_snapshot`. Confirmed booking snapshots already preserve the full offer terms snapshot and its hash, so subsequent tax-profile publication cannot alter existing offers or bookings.

Tax-profile selection is optional for compatibility with existing price lists. Price lists using `to_be_confirmed` cannot select a tax profile; the tax basis must be resolved first.

## Calculation boundary

This slice does **not** implement statutory tax calculation. The current offer workflow still receives an explicit tax amount and applies the existing inclusive/exclusive total rules. A tax profile is a versioned source of configuration and an immutable offer reference, not a calculation engine or a guarantee of legal correctness. Automatic calculations, jurisdiction-specific compound taxes, exemptions/eligibility logic, invoice issuance and tax reporting require separate domain design and validation.

## Authorization and audit

All commands require matching transaction-local organization context and `booking.manage`. Runtime direct table access is revoked; the API uses SECURITY DEFINER commands. Mutations append audit events. Published revisions are immutable. Only the latest draft may be edited/published, and successor revisions copy the previous tax-code catalogue so that a change is explicit rather than silently resetting the configuration.

## API and staff workspace

The staff API exposes organization tax-profile listing/creation, revision create/update/publish, and selection of a published tax-profile revision on a draft price-list revision. The staff web workspace edits profile metadata and tax codes, shows revision history, and allows price-list revisions to select a currency/tax-basis-compatible published profile revision.

## Validation status

Static inspection only. CI is intentionally deferred while the monthly GitHub Actions allowance is exhausted. No PostgreSQL migration execution, API tests, TypeScript build, OpenAPI validation or browser tests were run for this change.
