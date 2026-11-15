# Organization tax configuration — implementation design v0.3

## Scope

Migration 000062 adds organization-owned, versioned tax profiles. Migration 000063 adds jurisdiction-neutral calculation against the exact pinned profile revision. A profile revision records an organization-defined jurisdiction/authority identifier, tax registration identifier, currency, tax basis, rounding method and decimal scale, effective window, and an immutable tax-code catalogue.

Tax-code treatments are deliberately limited to configuration labels:

- `percentage`: requires a rate from 0 through 100.
- `zero_rated`, `exempt`, `out_of_scope`, and `manual`: rate must be null.

Codes are unique within a revision. A revision can contain up to 200 codes. No jurisdiction, registration status, legal classification, rate, exemption, rounding law, or tax advice is inferred or seeded.

## Price-list and offer linkage

A price-list revision may select one published tax-profile revision. The database requires matching currency and tax basis. When a profile is selected, every price item must have a `taxCode` present in that exact profile revision. A `not_applicable` profile has no tax-code catalogue and requires every price-item `taxCode` to be null. Publication also checks that the tax profile's effective window covers the price-list revision's effective window.

The selected revision is stored as a foreign key on the immutable price-list revision. New offer revisions automatically receive a snapshot of the selected tax profile revision and its tax-code catalogue in `terms_snapshot`. Confirmed booking snapshots already preserve the full offer terms snapshot and its hash, so subsequent tax-profile publication cannot alter existing offers or bookings.

Tax-profile selection is optional for compatibility with existing price lists. Price lists using `to_be_confirmed` cannot select a tax profile; the tax basis must be resolved first.

## Calculation boundary

This slice does **not** implement statutory tax calculation. The offer workflow calculates configured percentage treatments in PostgreSQL, or accepts an explicitly authorized manual invoice-level override. A tax profile is not a guarantee of legal correctness; statutory interpretation and jurisdiction-specific rules remain the organization's responsibility.

## Jurisdiction-neutral offer calculation

Migration 000063 adds an internal database calculation helper and extends the existing offer-save command. The helper reads only the exact published tax-profile revision referenced by the selected published price-list revision. It validates organization context, currency, tax basis, publication state and effective coverage again at offer preparation; it does not select a newer profile automatically.

For percentage treatments, the calculation uses each priced offer line's pinned price-list amount and tax code:

- Exclusive basis: tax = taxable amount × rate / 100.
- Inclusive basis: included tax = gross amount × rate / (100 + rate).
- Zero-rated, exempt and out-of-scope treatments contribute zero, while remaining distinct in the line-level calculation snapshot.
- The configured rounding method is applied as per-line, grouped by tax code, or once at invoice total, using the configured 0–4 decimal scale. The snapshot includes line-level unrounded/rounded amounts where applicable and grouped tax-code amounts for per-tax-code/invoice-total methods.
- A not-applicable profile produces zero tax and a recorded calculation method.

The offer's terms_snapshot now stores the calculation result, including the exact profile revision ID, currency/basis, rounding settings, calculation method, unrounded aggregate and line classifications. The offer revision's tax and total amount columns preserve four decimal places. Confirmed booking snapshots already hash and retain the complete offer terms snapshot.

### Explicit manual boundaries

A tax code configured as manual requires a positive invoice-level tax amount. Any positive manually supplied tax amount continues to require an internal reason and booking.approve; it is recorded as a manual override in the calculation snapshot. Manual overrides are invoice-level and are not allocated across individual lines or tax codes. This supports exceptional cases without pretending the platform knows the legal calculation.

Every manual adjustment (fee, discount or credit) must carry an explicit tax allocation when its price list pins a tax profile. Eventor never infers an adjustment's tax code from its label, kind or nearby price lines.

Two allocation methods are supported:

- `tax_code`: the adjustment supplies one `taxCode` from the exact pinned profile revision. The complete adjustment amount is assigned to that code.
- `proportional_to_lines`: the adjustment omits `taxCode`; its amount is allocated proportionally across the tax codes represented by positively priced offer lines. The allocation is grouped by tax code, ordered by code, rounded to two decimal places, and the final code receives the exact residual so allocated amounts always sum to the original adjustment. Fees, discounts and credits may use either method.

For a profile whose basis is `not_applicable`, each adjustment must explicitly use `allocationMethod: "not_applicable"` and omit `taxCode`. A profile-backed adjustment with a missing/unknown allocation method or unknown tax code is rejected. A discount or credit cannot reduce any tax-code taxable base below zero. The resulting per-adjustment allocation is stored in the immutable offer terms snapshot and contributes to the line/tax-code calculation breakdown using the configured profile rounding method.

A price list without a selected tax profile retains the legacy explicit invoice-level tax workflow and existing adjustment payload compatibility. A profile-backed adjustment using a `manual` tax treatment still requires the existing positive, audited invoice-level tax override and `booking.approve`; manual tax overrides are not falsely allocated across lines or tax codes.

The calculation engine is intentionally limited to a single configured percentage layer per price item. Compound/multi-component taxes, tax-on-tax ordering, item-level manual amounts beyond the explicit adjustment allocation methods above, exemption eligibility, reverse-charge logic, rounding-law presets, invoices, credit notes and tax reporting are not implemented. PostgreSQL fixtures exercise inclusive and exclusive calculations with adjustments, mixed tax-code allocation, deterministic residual cents, all three configured rounding methods, manual invoice overrides and not-applicable profiles. These fixtures validate arithmetic and platform behaviour; they do not establish statutory correctness. Organizations must configure and validate their own rates and classifications with their qualified tax adviser. Eventor does not determine statutory treatment.

A price list without a selected tax profile retains the legacy explicit tax amount workflow. A positive tax amount in either mode is an audited manual override; zero with a selected profile requests automatic calculation (except where the manual/adjustment boundaries above require an override).

## Authorization and audit

All commands require matching transaction-local organization context and `booking.manage`. Runtime direct table access is revoked; the API uses SECURITY DEFINER commands. Mutations append audit events. Published revisions are immutable. Only the latest draft may be edited/published, and successor revisions copy the previous tax-code catalogue so that a change is explicit rather than silently resetting the configuration.

## API and staff workspace

The staff API exposes organization tax-profile listing/creation, revision create/update/publish, and selection of a published tax-profile revision on a draft price-list revision. The staff web workspace edits profile metadata and tax codes, shows revision history, and allows price-list revisions to select a currency/tax-basis-compatible published profile revision.

## Validation status

Static inspection only. Migration 000063 has not been executed against PostgreSQL. CI is intentionally deferred while the monthly GitHub Actions allowance is exhausted. No PostgreSQL migration execution, API tests, TypeScript build, OpenAPI validation or browser tests were run for this change.
