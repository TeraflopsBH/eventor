# Eventor project state

Updated 2026-11-24. This page is the current development handoff. Detailed historical entries and older CI receipts are preserved in the [state archive](PROJECT_STATE_HISTORY_2026-11-23.md).

## Verified integration baseline

GitHub `main` is at `7f6bcdcc0fedec5944af6764465516201683ba3c`, after [reviewed current-state Registry restoration, PR #206](https://github.com/TeraflopsBH/eventor/pull/206). Its post-merge [contracts/PostgreSQL](https://github.com/TeraflopsBH/eventor/actions/runs/45404712081) and [secret history](https://github.com/TeraflopsBH/eventor/actions/runs/45404712074) checks passed.

This includes source-reference transfers with preserved encryption identity (#205), reviewed contact transfers (#204), public cancellation isolation (#203), the concise handoff (#202), provider notices (#201) and UUID compatibility (#200). Detailed receipts are in the linked archive.

## Current work

Bulk roster group add/remove is implemented on `feat/event-guest-bulk-groups` with migration 185, OpenAPI/API and bilingual UI. Existing group roles and unrelated memberships are preserved; new assignments receive the member role. Retired groups can be removed. Every selected revision must match or the entire batch rolls back. Full application, native PostgreSQL, fresh Docker database and Chromium/Firefox acceptance passed locally. Exact-head CI and merge verification remain pending. See [resume details](development/RESUME.md).

## Implemented workflows

- **Bookings:** public configurable inquiries, staff inquiry-to-draft review, allocation availability/alternatives, versioned offers, customer decisions, approval, confirmation, pinned pricing/tax/policy snapshots, communications and delivery worker. Cancellation includes staff review/execution, eligible reservation release, and separate customer request/status capabilities. Requests, booking cancellation and event cancellation remain separate decisions. Commercial settlement remains manual.
- **Provider disruptions:** permitted-booking search and append-only notice recording/history with public summaries and optional affected UTC times. Projections omit operational summaries. Recording does not send notifications or change booking/event status. Delivery, acknowledgement and event resolution remain open under #112.
- **Organizer events:** bilingual creation, revision-checked editing, archival, planning, approval, publication, start and close. Sessions support listing, creation, timing/title edits, scheduling, start, completion and confirmed cancellation. Event guest capabilities are optional.
- **Registry:** persistent profile search/edit/archive, permission-filtered participation history, encrypted contacts and source references, contact verification and relationships. Supervised reversible merges cover unlinked profiles, non-overlapping closed-event history and explicitly reviewed non-conflicting contact and supported source-reference transfers. IDs, encrypted values, consent, primary status, verification evidence and reference encryption identity are preserved. Restoration can return unchanged transferred records or explicitly reviewed current records while keeping unselected records at the destination and removed references deleted. Stale reviews require a fresh review. Initial contact conflicts and other linked/overlapping cases remain open; see ADR 0013.
- **Guest lists:** Registry links with pinned event identity and guest references; participant status, categories, internal/restricted tags, group hierarchy, roles, placement preferences/rules, relationships, encrypted custom fields and staff notes. Personal saved views and transactional bulk changes are available. Name/status/category/tag/group filters apply to exports; CSV/XLSX exports include guest references.
- **Imports:** mapped CSV/XLSX review with worksheet/header selection, encrypted staging, separate profiles, matched reuse/update and exact source-reference matching. Authorized staff can review unmatched references before creating profiles; diagnostics and exports are permission-filtered.
- **Access administration:** member name search, scoped-grant/permission inspection, reusable event role presets, grant/revocation and member suspension/restoration. Suspension revokes the affected member's sessions. Organization name, operating profile and default time zone use revision checks; new events use the organization time zone. Broader account onboarding/administration remains open.
- **Invitation/RSVP foundation:** opaque scoped invitation capabilities, guest response flow, staff-recorded responses/corrections/history and delivery processing. RSVP remains separate from physical attendance.

Authenticated browser tests verify that a venue-provider session cannot read organizer guests. An event-scoped member grant exposes only that roster and does not grant Registry access. Revocation removes roster access while leaving the member session active.

Canonical UUID validation accepts identifiers already stored in PostgreSQL, including legacy version/variant bits. Tenant authorization and authenticated encryption retain their boundaries; see [ADR 0011](decisions/0011-database-uuid-compatibility.md).

## Next work, in roadmap order

1. Continue [#104](https://github.com/TeraflopsBH/eventor/issues/104): broader organization/user/member administration and event settings; initial-merge conflict resolution for contacts and unsupported identifiers, active relationships and open/overlapping event history; remaining configurable roster/bulk controls. Audit existing commands before adding aggregates.
2. Complete collaboration/disruption work under [#112](https://github.com/TeraflopsBH/eventor/issues/112): provider-to-organizer delivery, acknowledgement, linked-event resolution and booking amendment/postponement acceptance. Provider notice recording alone does not complete this issue.
3. Implement venue geometry/editor [#105](https://github.com/TeraflopsBH/eventor/issues/105), advisory allocation [#106](https://github.com/TeraflopsBH/eventor/issues/106), then admission/check-in and operations cockpit [#107](https://github.com/TeraflopsBH/eventor/issues/107).
4. Complete both secure native Linux and production Docker Compose installers under [#108](https://github.com/TeraflopsBH/eventor/issues/108), including bootstrap, configuration, health, upgrade and recovery.
5. Run final integrated acceptance on the acceptance VM after the release candidate and both installers are complete. Production readiness and deployed-host acceptance remain unverified.

The [roadmap](ROADMAP.md) and [blueprint gap analysis](BLUEPRINT_TO_REPOSITORY_GAP_ANALYSIS_v1.0.md) retain the broader backlog. Public customer-cancellation browser acceptance covers submission, idempotent retry, cookie omission, fragment cleanup, reusable scoped status, unchanged booking confirmation and bilingual revoked-link errors. Both cancellation routes skip staff-session restoration, preserving the link locale even when staff cookies are present. Full organizer/venue collaboration acceptance remains a follow-up.

## Development and verification

Read this page, [AGENTS.md](../AGENTS.md), the relevant [design](implementation-design/v0.3/) and [decisions](decisions/) before editing. The [local guide](development/LOCAL_DEVELOPMENT.md) describes setup, focused checks and logs. Use the existing checkout and inspect local changes before switching or pulling.

```bash
./scripts/dev/doctor.sh                 # read-only workstation checks
./scripts/dev/check.sh quick            # contracts, API types, staff tests/types
./scripts/dev/check.sh api 'test name'  # focused API regression
./scripts/dev/check.sh web              # staff tests and build
./scripts/dev/check.sh full             # full application checks before PR
```

Full application checks are distinct from CI. Exact-head CI also runs dependency audits, PostgreSQL 18.6 migration/upgrade/RLS/concurrency and browser integration, systemd verification and reachable-history secret scanning. Live HTTPS/SMTP probes are optional and skipped without configured targets; a skip is not a pass. Check the exact PR SHA and required checks before merging, then inspect post-merge workflows.

Docker is optional for development PostgreSQL; the native regression runner can use installed PostgreSQL 18 binaries. [Development Compose](../compose.dev.yaml), role bootstrap/migration scripts and [systemd templates](../deploy/systemd/README.md) exist. These are foundations for the two release installers, not evidence that installation or recovery acceptance is complete.

## Product boundaries

Keep the API-first modular monolith, tenant/field-level permissions, immutable commercial/event history and optional event capabilities. Venue providers do not gain organizer guest access through booking ownership. Solver proposals require human review/commit. Configurable policies, venue measurements and reference-deployment operational/legal facts require evidence rather than assumptions. The [blueprint](blueprint/v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md), [architecture](ARCHITECTURE.md) and accepted ADRs own the detailed rules.
