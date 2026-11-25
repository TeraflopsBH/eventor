# Development resume — 2026-11-25

Verified main: `ce17be1e3245a7f2dcac5d3ba5d7198058263cc5`, after PRs #212/#213; post-merge contracts `45514104215` and secret history `45514104208` passed. The current state archive retains older receipts.

## Current slice

PR #214 (`codex/event-rsvp-settings`) is published and awaiting exact-head CI after correcting an older policy fixture's role. Current unpublished `codex/bulk-roster-name-reset` is based on that tested feature head and adds migration 190 plus a confirmed atomic bulk reset of event-local display names. Rebase only this unpublished slice onto the merged #214 main before publishing. Do not rewrite #214's published history. Bulk checks are in `bulk-name-reset-*` ignored logs.


`codex/event-rsvp-settings` adds event-level RSVP policy read/publication using existing policy tables. Migration 189 and ADR 0016 define scoped `event.manage`, immutable revisions, pinned historical invitations, stale policy/time-zone rejection and explicit publication. The bilingual event UI shares the scheduler's local-time conversion. No notifications or other modules are enabled. Full application checks and fresh PostgreSQL migration/upgrade/RLS/concurrency/auth checks passed. Chromium/Firefox verified publication, local deadlines, refresh, idempotent retry, stale revisions, CSRF and permissions, including unchanged deadline precision. Inspect ignored `rsvp-settings-*` logs and Git status before resuming. Exact-head CI remains required.

PR #211 email-first access and #212 host-managed member controls are already merged and verified. Never reapply their old changes or rewrite published history.

## Interactive preview

http://localhost:15173, API 18080. Its reserved database is recorded in `.eventor-dev/user-preview.json`; the original disposable container has now been removed on shutdown. Recreate a future preview with a persistent named volume; do not reset or reseed it while the user explores. The retained build targets migration 187. Source fixtures remain available, but the original exploratory database edits and Demo VIP Guest are no longer preserved. `ci-b@example.invalid` is the normal single-workspace demo. `organizer@demo.eventor.invalid` has two memberships. `admin@demo.eventor.invalid` is an explicitly provisioned synthetic platform administrator. The existing public CI fixture password is used only in this disposable local data. Acceptance runs separately on 15174/18081 with its own databases.

The preview is served from an ignored build snapshot so unfinished source edits do not disrupt it. Its API and web are stopped at the owner’s request. The database used `--rm` and was removed by Docker on stop; the build remains, but exploratory database edits were not retained. Consult the JSON receipt/logs before restarting. The optional production worker is not running in this local preview.

## First resume actions

1. Inspect Git status, fetch origin, inspect the exact PR head and required checks. The current branch follows verified #213. Rebase only while unpublished, with explicit Git identity and stop-on-error shell behavior. Never reapply older backup stashes: their changes are merged.
2. Merge only after all five required checks pass and GitHub reports CLEAN. Squash using the exact checked head.
3. Fast-forward main, inspect post-merge contracts and secret-history runs, then reconcile the active handoff/ignored verified receipt.
4. Continue #104: remaining linked-record/initial-merge conflicts and broader user/member onboarding, event settings and remaining roster controls. Then #112 and #105–#108 in roadmap order. These slices do not complete the full product or production installers.

## Workstation

The chat path `/home/nedim/coding/eventor` is a symlink to `/home/nedim/Development/eventor`. Docker works. Native PostgreSQL regression uses ignored local PG18 binaries. Reuse this checkout, keep detailed logs ignored, and keep active project state concise. User authorization for development, testing, PR creation and verified squash merges persists.
