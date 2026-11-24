# Development resume — 2026-11-25

The interruption is reconciled. PR #209–#211 are merged. Last recorded verified main: `58e4c95e1c6923b437ea80cc1364e3ada80e8eb3`, with post-merge contracts `45507846026` and secret history `45507846531` passing. Current state and its linked archive retain the prior receipts.

## Current slice

`codex/platform-member-controls` adds a scoped `hostManaged` member-directory flag and bilingual host-management labels, omitting unsupported tenant suspension controls. Migration 188 unifies directory projections; the existing server guard remains unchanged. Full application and fresh PostgreSQL checks passed, plus Chromium/Firefox staff-shell, Registry-label and focused workspace/member-control checks. Exact-head CI remains required before integration.

Previous completed slice:

`feat/email-first-workspace-access` implements email/password-only sign-in, named choices for multiple active memberships, audited atomic workspace switching with original session expiry, and explicit host-managed platform administration. Migration 187 and ADR 0015 define its boundaries. Existing organization managers retain tenant limits; auth/runtime cannot set the global flag. Host CLI: `scripts/admin/platform-admin.sh`.

Full application, native PostgreSQL, fresh Docker upgrade/RLS/concurrency/auth checks and Chromium/Firefox staff-shell/Registry-label/workspace journeys passed. Final browser execution was resumed after the limit interruption. Logs: `.eventor-dev/logs/workspace-access-full.log`, `workspace-access-native.log`, `workspace-access-browser.log`, and `staff-shell-compose-tests.log`. Exact-head CI must be checked before merging. Do not rewrite published history.

## Interactive preview

http://localhost:15173, API 18080. Its reserved database is recorded in `.eventor-dev/user-preview.json`; the original disposable container has now been removed on shutdown. Recreate a future preview with a persistent named volume; do not reset or reseed it while the user explores. The retained build targets migration 187. Source fixtures remain available, but the original exploratory database edits and Demo VIP Guest are no longer preserved. `ci-b@example.invalid` is the normal single-workspace demo. `organizer@demo.eventor.invalid` has two memberships. `admin@demo.eventor.invalid` is an explicitly provisioned synthetic platform administrator. The existing public CI fixture password is used only in this disposable local data. Acceptance runs separately on 15174/18081 with its own databases.

The preview is served from an ignored build snapshot so unfinished source edits do not disrupt it. Its API and web are stopped at the owner’s request. The database used `--rm` and was removed by Docker on stop; the build remains, but exploratory database edits were not retained. Consult the JSON receipt/logs before restarting. The optional production worker is not running in this local preview.

## First resume actions

1. Inspect Git status, fetch origin, inspect the exact PR head and required checks. The current branch follows the verified #211 tree. Rebase only while unpublished, with explicit Git identity and stop-on-error shell behavior. Never reapply older backup stashes: their changes are merged.
2. Merge only after all five required checks pass and GitHub reports CLEAN. Squash using the exact checked head.
3. Fast-forward main, inspect post-merge contracts and secret-history runs, then reconcile the active handoff/ignored verified receipt.
4. Continue #104: remaining linked-record/initial-merge conflicts and broader user/member onboarding, event settings and remaining roster controls. Then #112 and #105–#108 in roadmap order. These slices do not complete the full product or production installers.

## Workstation

The chat path `/home/nedim/coding/eventor` is a symlink to `/home/nedim/Development/eventor`. Docker works. Native PostgreSQL regression uses ignored local PG18 binaries. Reuse this checkout, keep detailed logs ignored, and keep active project state concise. User authorization for development, testing, PR creation and verified squash merges persists.
