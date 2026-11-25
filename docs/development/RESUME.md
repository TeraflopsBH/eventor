# Development resume — 2026-11-25

Verified main: `17e04c04bd11ee2099097c393dd990821faa9629` (#218), with post-merge contracts `45569418413` and secrets `45569418415` passing. Prior receipts remain in the archive/ignored checkpoint.

## Current slice

`codex/reviewed-registry-relationship-merges` adds migration 192/ADR 0019: actor-reviewed transfer of non-conflicting active Registry relationships with separate management authority and acknowledgement. Self-links/duplicates remain blocked. Original IDs, direction, kind and attribution are preserved; ended history and unrelated destination links are untouched. Both restoration paths return unchanged links, and refuse changed/ended/missing links before partial effects. Returning links are read-only in current-state correction.

Full application, fresh PostgreSQL upgrade/migration/RLS/concurrency/role and Chromium/Firefox acceptance passed locally. Deterministic concurrent-end and destination-create tests passed. Logs are `relationship-*`; exact-head CI remains required before merging. All legacy overloads route through acknowledgement; private helpers/journal are not exposed to app roles. Inspect Git status before switching; never rewrite published history.

## Interactive preview

http://localhost:15173, API 18080. Its reserved database is recorded in `.eventor-dev/user-preview.json`; the original disposable container has now been removed on shutdown. Recreate a future preview with a persistent named volume; do not reset or reseed it while the user explores. The retained build targets migration 187. Source fixtures remain available, but the original exploratory database edits and Demo VIP Guest are no longer preserved. `ci-b@example.invalid` is the normal single-workspace demo. `organizer@demo.eventor.invalid` has two memberships. `admin@demo.eventor.invalid` is an explicitly provisioned synthetic platform administrator. The existing public CI fixture password is used only in this disposable local data. Acceptance runs separately on 15174/18081 with its own databases.

The preview is served from an ignored build snapshot so unfinished source edits do not disrupt it. Its API and web are stopped at the owner’s request. The database used `--rm` and was removed by Docker on stop; the build remains, but exploratory database edits were not retained. Consult the JSON receipt/logs before restarting. The optional production worker is not running in this local preview.

## First resume actions

1. Inspect Git status, fetch origin, inspect the exact PR head and required checks. The current slice follows verified #218. Rebase only while unpublished, with explicit Git identity and stop-on-error shell behavior. Never reapply older backup stashes: their changes are merged.
2. Merge only after all five required checks pass and GitHub reports CLEAN. Squash using the exact checked head.
3. Fast-forward main, inspect post-merge contracts and secret-history runs, then reconcile the active handoff/ignored verified receipt.
4. Continue #104: relationship conflict/correction and remaining linked-record/initial-merge conflicts and broader user/member onboarding, event settings and remaining roster controls. Then #112 and #105–#108 in roadmap order. These slices do not complete the full product or production installers.

## Workstation

The chat path `/home/nedim/coding/eventor` is a symlink to `/home/nedim/Development/eventor`. Docker works. Native PostgreSQL regression uses ignored local PG18 binaries. Reuse this checkout, keep detailed logs ignored, and keep active project state concise. User authorization for development, testing, PR creation and verified squash merges persists.
