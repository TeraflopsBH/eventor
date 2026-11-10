# Implementation Design v0.2 — imported source set

**Status:** historical design snapshot imported for review; not an approved production implementation contract.

This directory contains the v0.2 working design and its text-based engineering companion artifacts. The source Markdown documents are retained as versioned references. Follow-up corrections should be made in a new design revision, not by silently rewriting this snapshot.

## Contents

| File | Purpose |
|---|---|
| `Event_Operations_Implementation_Design_v0.2.md` | Detailed implementation design, derived from Blueprint v1.2 |
| `eogp_schema_v0.2.sql` | Consolidated PostgreSQL schema starter/reference |
| `eogp_openapi_v0.2.yaml` | OpenAPI 3.1.1 first contract draft |
| `EOGP_Backlog_v0.2.csv` | 64-item implementation backlog |
| `GHB_Rental_Form_Reference_v0.2.csv` | 21 captured public form controls/fields and option lists |

The full technical product baseline is in [Blueprint v1.2](../../blueprint/v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md).

## Important schema packaging note

The consolidated `eogp_schema_v0.2.sql` contains **86 table definitions**: 64 core tables plus 22 booking/configuration tables.

The original package also included `eogp_booking_schema_addendum_v0.2.sql`. All 22 table definitions in that addendum are already present in the consolidated file (22/22 overlap). Therefore, the separate addendum is intentionally not copied here as an executable companion: applying it after the consolidated schema would fail on duplicate table names. Its original SHA-256 is recorded in [the reconciliation report](../../../DESIGN_RECONCILIATION_v0.2.md).

The consolidated schema file header still labels the starter as v0.1 and describes the booking extension in a second transaction. This historical labeling will be corrected in a reviewed schema revision; the imported source is not silently modified.

## Validation state

- OpenAPI YAML parsed with PyYAML 6.0.3: 36 paths, 46 operations, 46 unique `operationId` values. This is syntax/structure validation only, not full OpenAPI 3.1.1 semantic validation.
- Backlog CSV: 64 data rows.
- GHB rental-form reference CSV: 21 data rows.
- SQL: 86 consolidated table definitions; statically inspected only. It has **not** been executed against PostgreSQL.
- PostgreSQL RLS policies and immutability triggers are not active in this schema starter; the source includes implementation notes/comments for these controls.

## Reference-data caution

The GHB form capture was taken from the public-facing page on 10 November 2026. It is a reference snapshot, not an approved GHB specification. The captured HTML `required` property is false for all 21 fields. The event start field was a text input in the observed DOM. Revalidate current labels, options, validation and conditional behavior before seeding a production form.

GHB-specific capacities, room inventory, current prices, discounts and operating policies are not treated as authoritative by this repository.

## Excluded source material

The source GHB mosque workbook, its rendered worksheet image and the plan-observation CSV are deliberately excluded from this repository import pending venue-owner review. The spatial observations are provisional and must not be used to publish geometry or seating capacity without approval. DOCX/PDF render copies are also omitted; the editable Markdown sources are retained here.
