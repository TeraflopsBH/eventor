# OpenAPI contract review — v0.2

**Review date:** 2026-11-10  
**Status:** YAML and structural checks passed; full OpenAPI semantic validation and domain-contract alignment remain open  
**Source:** `docs/implementation-design/v0.2/eogp_openapi_v0.2.yaml`  
**Related:** [Issue #3](https://github.com/TeraflopsBH/eventor/issues/3), [Issue #17](https://github.com/TeraflopsBH/eventor/issues/17)

## 1. Static validation performed

The source file was parsed with PyYAML 6.0.3 and checked with a local structural validation script.

| Check | Result |
|---|---:|
| OpenAPI version | 3.1.1 |
| Paths | 36 |
| HTTP operations | 46 |
| Unique operation IDs | 46 / 46 |
| Local JSON Reference occurrences | 172 |
| Unresolved local references | 0 |
| Path-template parameters declared/resolved | 100% |
| Operations with response declarations | 46 / 46 |
| Invalid response-code keys detected | 0 |
| YAML parse errors | 0 |

The first pass of the custom path-parameter checker did not dereference shared component parameters and reported false positives. The checker was corrected to resolve local component parameter references; the corrected run passed. No unresolved references or missing path parameter declarations remained.

**Limit:** these are YAML and structural checks, not a full OpenAPI 3.1.1 semantic validator. No OpenAPI validator/CLI or generated client contract test has been run. The file must still be checked with a pinned validator in CI and tested against actual route implementations before Issue #3 can close.

## 2. Security baseline

The contract defines:
- `sessionCookie`: staff session cookie, applied globally by default.
- `guestToken`: separate guest access token for the personal guest allocation operation.
- Explicit `security: []` on public login, invitation-token resolution and public booking inquiry/form operations.

This is a sensible starting separation. The successor contract must preserve explicit route allow-listing. Public routes must not inherit staff authentication accidentally; guest routes must not accept a staff cookie as a substitute for a guest capability; staff routes must not accept the guest token.

Actual server-side permission checks, CSRF protections, cookie attributes, rate limits and response serialization still require implementation tests.

## 3. Domain coverage gaps

The 46 v0.2 operations cover a first slice of staff authentication, people, events/guests, venues/spatial objects, allocation, guest allocation portal, check-in, prerequisites, booking inquiry/draft/offer/confirmation and catalogue/form publication.

The v0.2 contract does **not** yet provide the commands/projections required by accepted successor design decisions:

### 3.1 RSVP and invitation design v0.3

Missing:
- Issue invitations and track invitation lifecycle separately from delivery.
- Resend, revoke and reissue invitation links.
- Non-destructive invitation-link resolution context.
- Read own invitation and RSVP policy.
- Submit/change own RSVP.
- Staff-record response from external channels, response history and append-only correction.
- RSVP deadline override with explicit permission/reason.
- Invitation delivery-to-invitation association.

See [RSVP and Invitation Design v0.3](../implementation-design/v0.3/RSVP_AND_INVITATION_DESIGN_v0.3.md) and [Issue #10](https://github.com/TeraflopsBH/eventor).

### 3.2 Cross-organization collaboration (accepted ADR 0006)

Missing:
- Create/offer/accept/revoke scoped collaboration grants.
- Explicit booking-event association with distinct owner organization IDs.
- Share an approved venue-space revision as an immutable event-owned snapshot.
- Inspect snapshot provenance, revision/hash, granted layers/resources and revocation status.
- Bind event sessions and allocations to the event-owned snapshot.
- Scoped operational task delegation and external collaborator data projections.

See [Cross-Organization Collaboration Design v0.3](../implementation-design/v0.3/CROSS_ORGANIZATION_COLLABORATION_DESIGN_v0.3.md) and [ADR 0006](../decisions/0006-cross-organization-collaboration.md).

### 3.3 Optional modules and task responsibility

Missing:
- Read/publish event module capability revisions and per-event overrides.
- Define/list/update responsibility assignments, accountable/performed/approving/informed parties and task data scopes.
- Ensure a booking-only operation does not require operational-event or guest endpoints.
- Return a consistent disabled-capability response when an optional module is not enabled.

### 3.4 Booking and resources

v0.2 covers inquiry, draft revisions, offers and confirmation at a basic level. The next contract must align with the integrity model for:
- Unified space-time holds/reservations and availability conflicts.
- Discrete equipment/personnel unit reservations and pooled capacity.
- Booking-event links with separate owner organizations.
- Cross-organization venue-plan snapshots and venue capacity projections.

## 4. Recommended contract structure

Keep the API as one versioned contract for the modular monolith, grouped by domain tags:
- Auth / identity.
- Organization and membership.
- Booking / venue resources.
- Event and capabilities.
- Collaboration / shared venue plans.
- Guest Registry / participation.
- Invitations / RSVP.
- Spatial plans / allocation.
- Check-in / attendance.
- Responsibility / prerequisites.
- Cockpit / notifications / audit.

Use purpose-specific request/response schemas. Public guest operations should return a personal projection, never a general event-guest schema. Cross-organization endpoints should express the acting organization, target owner, grant scope and data projection explicitly; a booking ID alone must never grant access.

## 5. Next validation gates

1. Generate the successor OpenAPI v0.3 draft from accepted ADR 0004/0005/0006 and the v0.3 domain designs.
2. Pin a full OpenAPI 3.1.1 validator in CI; record tool/version and fail on unresolved references or invalid schemas.
3. Add request/response schema and operation ID uniqueness checks.
4. Add authentication matrix tests for staff cookie, guest token and unauthenticated/public routes.
5. Add contract tests for RSVP deadlines, idempotency, collaboration grant revocation, booking-only mode and module-disabled responses.
6. Generate TypeScript client/types or runtime validation artifacts from the contract and test that process reproducibly.
7. Do not close Issue #3 until the validator and contract tests run in CI.
