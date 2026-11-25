# Development resume — 2026-11-25

Verified main: `ce17be1e3245a7f2dcac5d3ba5d7198058263cc5`, after PRs #212/#213; post-merge contracts `45514104215` and secret history `45514104208` passed. The current state archive retains older receipts.

## Current slice

PR #214 is merged at `a12b65b8ee9b00ec2ea4ff169987c156cf21a63f` after exact-head CI passed (`d963ca982360da1c57dae2ee49c099d6110c6ae3`, contracts `45517205943`, secrets `45517205714`). Post-merge contracts `45517906890` and secrets `45517906960` must be inspected before calling that baseline post-merge verified.

`codex/bulk-roster-name-reset` is rebased onto the merged #214 tree. Migration 190 adds only an atomic wrapper around the existing audited per-row reset. The bilingual UI confirms selection count and explains Registry/snapshot preservation. Full application, fresh PostgreSQL upgrade/migration/RLS/concurrency/auth and Chromium/Firefox checks passed; logs are `bulk-name-reset-*`. Exact-head CI is required before integration. No published history was rewritten.

Migration 189/ADR 0016 RSVP settings are integrated. Broader account onboarding, linked-record merge conflicts and remaining event/roster controls remain open under #104.

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
