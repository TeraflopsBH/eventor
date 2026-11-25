# Eventor project state

Updated 2026-11-25. This page is the current development handoff. Detailed historical entries and older CI receipts are preserved in the [state archive](PROJECT_STATE_HISTORY_2026-11-23.md).

## Verified integration baseline

`main` was verified at `a12b65b8ee9b00ec2ea4ff169987c156cf21a63f`, after [event RSVP settings #214](https://github.com/TeraflopsBH/eventor/pull/214). Post-merge [contracts/PostgreSQL](https://github.com/TeraflopsBH/eventor/actions/runs/45517906890) and [secret history](https://github.com/TeraflopsBH/eventor/actions/runs/45517906960) passed. Bulk roster-name reset [#215](https://github.com/TeraflopsBH/eventor/pull/215) is merged at `f4fc051e29210855145bb748d60dd4dce823d999`; its post-merge checks are running.

This includes reviewed current-state restoration (#206), source-reference transfers with preserved encryption identity (#205), reviewed contact transfers (#204), public cancellation isolation (#203), the concise handoff (#202), provider notices (#201) and UUID compatibility (#200). Detailed receipts are in the linked archive.

## Latest implementation slice

Staff sign-in now starts with email/password. A single active workspace opens directly; several return named choices only after password verification. The header switches between permitted memberships with fresh session/CSRF cookies, atomic revocation of the old session and a user-attributed audit, preserving the original expiry. A page replacement clears old workspace state. Slugs remain supported for legacy API clients; ordinary users do not enter one.

Migration 187 adds an explicit, host-managed platform administrator flag (default false) with tracked memberships/system grants for active organizations. Private global provisioning/audit records and narrow auth-only helpers preserve the normal selected-tenant RLS/runtime boundary. Ordinary organization managers gain no cross-tenant authority. Host revocation removes managed privileges and affected sessions while retaining independent membership/grant facts (ADR 0015). Global account provisioning and inactive-organization recovery remain host operations.

Full application, native PostgreSQL, fresh isolated Docker database and Chromium/Firefox checks passed locally, including password-before-workspace disclosure, session rotation/lifetime, CSRF, normal tenant limits, explicit platform access and revocation. The live preview was verified separately. PR #211 passed exact-head CI and post-merge verification.

Host-managed member controls (#212, migration 188) are integrated and verified. Both member-directory paths identify host-managed platform access, with bilingual explanations instead of unsupported suspension controls. The database guard remains authoritative.

The current slice adds event-level RSVP settings under scoped `event.manage`: allowed answers, optional deadline in the effective event time zone, and response-change permission. Publication creates a new immutable policy revision, checks the expected policy/time zone, and audits the actor. Existing invitations retain pinned revisions. No other event modules or messages are activated. Migration 189 and ADR 0016 define the boundary. Full application checks, a fresh PostgreSQL upgrade/migration/RLS/concurrency/auth-role suite and Chromium/Firefox RSVP journeys passed locally. Tests cover pinned invitation history, stale policy/time-zone edits, retirement, tenant permissions, CSRF, idempotent retries and unchanged deadline precision. PR #214 passed exact-head and post-merge verification.

The following #104 slice adds a confirmed bulk restoration of selected guests’ recorded display names. It reuses the existing single-row reset, guest-management authority, per-row revision checks and audit. Registry identities and recorded event snapshots are preserved; partial batches are rejected. Migration 190 adds only the command wrapper. Full application, fresh PostgreSQL migration/upgrade/RLS/concurrency/auth-role and Chromium/Firefox checks passed locally, covering cancelled confirmation, unchanged snapshots/Registry names, idempotent retries and stale selection. PR #215 passed exact-head CI and is merged; post-merge checks are running.

Host-only staff bootstrap is the next #104 slice: hidden/stdin password entry, Argon2id, optional active membership, duplicate refusal and actual database-operator audit. It grants no roles/platform access and does not claim email verification. No HTTP endpoint or schema change is introduced; ADR 0017 records the boundary. Full application checks, focused validation/audit-rollback tests and a real PostgreSQL/CLI acceptance run passed locally, including normal login, hash verification, duplicate refusal, no implicit grants, host attribution and runtime-role denial. Exact-head CI remains required.

The interactive preview was stopped at the owner’s request. Its disposable `--rm` database container was removed on stop: source, fixtures and build remain, but exploratory database edits were not retained. Recreate the next interactive preview with a persistent named volume and a local backup before shutdown.

Preview feedback already includes persistent language selection, permission-aware tabs/error isolation, `DD.MM.YYYY HH:mm` Bosnian dates, optional generated codes, preferred-name help, SMTP under Settings and persistent Registry label badges such as VIP.

## Implemented workflows

- **Bookings:** public configurable inquiries, staff inquiry-to-draft review, allocation availability/alternatives, versioned offers, customer decisions, approval, confirmation, pinned pricing/tax/policy snapshots, communications and delivery worker. Cancellation includes staff review/execution, eligible reservation release, and separate customer request/status capabilities. Requests, booking cancellation and event cancellation remain separate decisions. Commercial settlement remains manual.
- **Provider disruptions:** permitted-booking search and append-only notice recording/history with public summaries and optional affected UTC times. Projections omit operational summaries. Recording does not send notifications or change booking/event status. Delivery, acknowledgement and event resolution remain open under #112.
- **Organizer events:** bilingual creation, revision-checked editing, archival, planning, approval, publication, start and close. Sessions support listing, creation, timing/title edits, scheduling, start, completion and confirmed cancellation. Event guest capabilities are optional.
- **Registry:** persistent profile search/edit/archive, permission-filtered participation history, encrypted contacts and source references, contact verification, relationships and internal configurable labels. Supervised reversible merges cover unlinked profiles, non-overlapping closed-event history and explicitly reviewed non-conflicting contact and supported source-reference transfers. IDs, encrypted values, consent, primary status, verification evidence and reference encryption identity are preserved. Restoration can return unchanged transferred records or explicitly reviewed current records while keeping unselected records at the destination and removed references deleted. Stale reviews require a fresh review. Initial contact conflicts and other linked/overlapping cases remain open; see ADR 0013.
- **Guest lists:** Registry links with pinned event identity and guest references; participant status, categories, internal/restricted tags, group hierarchy, roles, placement preferences/rules, relationships, encrypted custom fields and staff notes. Personal saved views and transactional bulk category/status/tag/group changes are available. Bulk group changes preserve existing roles and unrelated memberships; retired groups remain removable. Name/status/category/tag/group filters apply to exports; CSV/XLSX exports include guest references.
- **Imports:** mapped CSV/XLSX review with worksheet/header selection, encrypted staging, separate profiles, matched reuse/update and exact source-reference matching. Authorized staff can review unmatched references before creating profiles; diagnostics and exports are permission-filtered.
- **Access administration:** member name search, scoped-grant/permission inspection, reusable event role presets, grant/revocation and member suspension/restoration. Suspension revokes the affected member's sessions. Organization name, operating profile and default time zone use revision checks; new events use the organization time zone. Email-first sign-in, membership switching and explicit host-managed platform administration are implemented; broader account onboarding and a complete global account-management console remain open.
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
