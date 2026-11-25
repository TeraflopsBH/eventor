# Eventor project state

Updated 2026-11-25. This page is the current development handoff. Detailed historical entries and older CI receipts are preserved in the [state archive](PROJECT_STATE_HISTORY_2026-11-23.md).

## Verified integration baseline

`main` was verified at `fe5cec3df1a970c14eec609a80f15141d565e3ec`, after [the Events linked-booking selector #224](https://github.com/TeraflopsBH/eventor/pull/224). Post-merge [contracts/PostgreSQL](https://github.com/TeraflopsBH/eventor/actions/runs/45623757322) and [secret history](https://github.com/TeraflopsBH/eventor/actions/runs/45623757442) passed. This includes association APIs (#223), contextual headings (#222), classification filters (#221), membership onboarding (#220), reviewed relationship/classification transfers (#219/#218), RSVP settings (#214), bulk name restoration (#215), host bootstrap (#216) and safe database shutdown (#217).

This includes reviewed current-state restoration (#206), source-reference transfers with preserved encryption identity (#205), reviewed contact transfers (#204), public cancellation isolation (#203), the concise handoff (#202), provider notices (#201) and UUID compatibility (#200). Detailed receipts are in the linked archive.

## Latest implementation slice

The current #112 staff slice adds a bilingual disruption inbox to Events. Authorized staff preview a local linked booking's public notice and confirm publication. Event-only managers can read and acknowledge intentionally published receipts without reading source bookings or publishing. Controls retain original receipts on repeat publication, escape public text, focus the opened heading, contain mobile content and clear private rows after denial. Notice choices show issuance time and summary text.

The API foundation (#225/migration 196/ADR 0022) merged at `1d6a585bbe83a800ac90aeb0196fcd52ae1ec919`, matching checked head `b7b7df823049abb7affdbaeb129832c48389043d` after all five checks/CLEAN. Post-merge verification is pending. It reuses the existing receipt aggregate, preserves immutable provenance and the first acknowledgement, and changes no booking/event/resource/guest facts. Full application/fresh PostgreSQL/API concurrency checks passed locally. The staff UI passed full application checks, Chromium/Firefox acceptance and synthetic desktop/mobile screenshot inspection. Exact-head CI remains required before integration. Cross-organization delivery, email, association correction and disruption resolution remain open; acknowledgement is receipt only.

The linked-booking selector (#224/migration 195) passed all five checks/CLEAN at `2d3603a44ab70a6d44bea1900bcad56233fe31bc`; squash main and both post-merge receipts are recorded above. Local browser acceptance covers cancelled confirmation, unchanged event capabilities, Bosnian dates and permission cleanup. Partner setup remains separate.

Classification filtering (#221/migration 193) merged at `946410af4ef2e4a621954ca613cd6fd6b32b8d02`; post-merge contracts `45616192807` and secrets `45616192184` passed. Contextual bilingual headings (#222) merged at `b6a3c94000fe26831f9997935fd0bcb9a07d33e3`, matching checked head `b99fbf6e7fa51244bccb32adcef4574d828ffb46` after all five checks passed. Post-merge contracts `45617577494` and secrets `45617577661` passed.

Integrated foundations include RSVP policy publication (#214/migration 189), bulk roster-name restoration (#215/migration 190), host account bootstrap (#216/ADR 0017), protected development database shutdown (#217), and email-first/scoped workspace access (#211/#212). All passed exact-head CI and post-merge verification. Production installers and full account onboarding remain open.

The interactive preview was stopped at the owner’s request. Its disposable `--rm` database container was removed on stop: source, fixtures and build remain, but exploratory database edits were not retained. Recreate the next interactive preview with a persistent named volume and a local backup before shutdown.

Preview feedback already includes persistent language selection, permission-aware tabs/error isolation, `DD.MM.YYYY HH:mm` Bosnian dates, optional generated codes, preferred-name help, SMTP under Settings and persistent Registry label badges such as VIP.

## Implemented workflows

- **Bookings:** public configurable inquiries, staff inquiry-to-draft review, allocation availability/alternatives, versioned offers, customer decisions, approval, confirmation, pinned pricing/tax/policy snapshots, communications and delivery worker. Cancellation includes staff review/execution, eligible reservation release, and separate customer request/status capabilities. Requests, booking cancellation and event cancellation remain separate decisions. Commercial settlement remains manual.
- **Provider disruptions:** permitted-booking search and append-only notice recording/history with public summaries and optional affected UTC times. Projections omit operational summaries. Recording does not send notifications or change booking/event status. The current local event-inbox publication/acknowledgement slices are awaiting integration; partner delivery and event resolution remain open under #112.
- **Organizer events:** bilingual creation, revision-checked editing, archival, planning, approval, publication, start and close. Sessions support listing, creation, timing/title edits, scheduling, start, completion and confirmed cancellation. Scoped managers can publish versioned RSVP settings while preserving issued invitation policies. Event guest capabilities are optional.
- **Registry:** persistent profile search/edit/archive, classification-filtered search/export, permission-filtered participation history, encrypted contacts and source references, contact verification, relationships and internal configurable labels. Supervised reversible merges cover unlinked profiles, non-overlapping closed-event history and explicitly reviewed non-conflicting contact, supported source-reference and non-overlapping classification transfers and non-conflicting active relationship transfers. IDs, encrypted values, consent, primary status, verification evidence and reference encryption identity are preserved. Restoration can return unchanged transferred records or explicitly reviewed current records while keeping unselected records at the destination and removed references deleted. Stale reviews require a fresh review. Initial contact conflicts, overlapping/edited classification correction, changed relationship correction and other linked/overlapping cases remain open; see ADR 0013/0018/0019.
- **Guest lists:** Registry links with pinned event identity and guest references; participant status, categories, internal/restricted tags, group hierarchy, roles, placement preferences/rules, relationships, encrypted custom fields and staff notes. Personal saved views and transactional bulk category/status/tag/group changes and recorded-name restoration are available. Bulk group changes preserve existing roles and unrelated memberships; retired groups remain removable. Name/status/category/tag/group filters apply to exports; CSV/XLSX exports include guest references.
- **Imports:** mapped CSV/XLSX review with worksheet/header selection, encrypted staging, separate profiles, matched reuse/update and exact source-reference matching. Authorized staff can review unmatched references before creating profiles; diagnostics and exports are permission-filtered.
- **Access administration:** member name search, scoped-grant/permission inspection, reusable event role presets, grant/revocation and member suspension/restoration. Suspension revokes the affected member's sessions. Organization name, operating profile and default time zone use revision checks; new events use the organization time zone. Email-first sign-in, membership switching and explicit host-managed platform administration are implemented; host-only initial-account and existing-account membership commands are available; broader tenant onboarding and a complete global account-management console remain open.
- **Invitation/RSVP foundation:** opaque scoped invitation capabilities, guest response flow, staff-recorded responses/corrections/history and delivery processing. RSVP remains separate from physical attendance.

Authenticated browser tests verify that a venue-provider session cannot read organizer guests. An event-scoped member grant exposes only that roster and does not grant Registry access. Revocation removes roster access while leaving the member session active.

Canonical UUID validation accepts identifiers already stored in PostgreSQL, including legacy version/variant bits. Tenant authorization and authenticated encryption retain their boundaries; see [ADR 0011](decisions/0011-database-uuid-compatibility.md).

## Next work, in roadmap order

1. Continue [#104](https://github.com/TeraflopsBH/eventor/issues/104): broader organization/user/member administration and event settings; initial-merge conflict resolution for contacts and unsupported identifiers, relationship conflict/correction and open/overlapping event history; remaining configurable roster/bulk controls. Audit existing commands before adding aggregates.
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
