# Development resume — 2026-11-25

The interruption is reconciled. PR #209 and #210 are merged. Last recorded verified main: `28f37fe5566e53e68476e686766f9e61ba3b274c`, with post-merge contracts `45421323539` and secret history `45421323442` passing. Current state and its linked archive retain the prior receipts.

## Current slice

`feat/email-first-workspace-access` implements email/password-only sign-in, named choices for multiple active memberships, audited atomic workspace switching with original session expiry, and explicit host-managed platform administration. Migration 187 and ADR 0015 define its boundaries. Existing organization managers retain tenant limits; auth/runtime cannot set the global flag. Host CLI: `scripts/admin/platform-admin.sh`.

Full application, native PostgreSQL, fresh Docker upgrade/RLS/concurrency/auth checks and Chromium/Firefox staff-shell/Registry-label/workspace journeys passed. Final browser execution was resumed after the limit interruption. Logs: `.eventor-dev/logs/workspace-access-full.log`, `workspace-access-native.log`, `workspace-access-browser.log`, and `staff-shell-compose-tests.log`. Exact-head CI must be checked before merging. Do not rewrite published history.

## Interactive preview

http://localhost:15173, API 18080. Its reserved database is recorded in `.eventor-dev/user-preview.json`; never reset or reseed it while the user explores. It has migration 187 and the tested workspace build, preserving previous data and Demo VIP Guest. `ci-b@example.invalid` is the normal single-workspace demo. `organizer@demo.eventor.invalid` has two memberships. `admin@demo.eventor.invalid` is an explicitly provisioned synthetic platform administrator. The existing public CI fixture password is used only in this disposable local data. Acceptance runs separately on 15174/18081 with its own databases.

The preview is served from an ignored build snapshot so unfinished source edits do not disrupt it. Its API and web processes were restarted after interruption; consult the JSON receipt/logs before starting duplicates. The optional production worker is not running in this local preview.

## First resume actions

1. Inspect Git status, fetch origin, inspect the exact PR head and required checks. The current branch follows the already-tested #210 tree. Rebase only while unpublished, with explicit Git identity and stop-on-error shell behavior. Never reapply older backup stashes: their changes are merged.
2. Merge only after all five required checks pass and GitHub reports CLEAN. Squash using the exact checked head.
3. Fast-forward main, inspect post-merge contracts and secret-history runs, then reconcile the active handoff/ignored verified receipt.
4. Continue #104: remaining linked-record/initial-merge conflicts and broader user/member onboarding, event settings and remaining roster controls. Then #112 and #105–#108 in roadmap order. These slices do not complete the full product or production installers.

## Workstation

The chat path `/home/nedim/coding/eventor` is a symlink to `/home/nedim/Development/eventor`. Docker works. Native PostgreSQL regression uses ignored local PG18 binaries. Reuse this checkout, keep detailed logs ignored, and keep active project state concise. User authorization for development, testing, PR creation and verified squash merges persists.
