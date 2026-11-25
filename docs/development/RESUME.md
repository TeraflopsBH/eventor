# Development resume — 2026-11-25

Verified main: `594468b7cee4294aa57faa46d72ac243c31ce5cb` (#220), with post-merge contracts `45576797145` and secrets `45576797109` passing. Prior receipts remain in the archive/ignored checkpoint.

## Current slice

`codex/registry-classification-filters` adds migration 193 and the ADR 0014 extension: Registry search and CSV/XLSX export intersect an optional classification ID with name and active/archived state before pagination/limits. Read-only metadata includes retired options; unknown/foreign IDs return no matches. Separate Registry/export authority and public projection boundaries remain unchanged. Full application, fresh PostgreSQL migration/upgrade/RLS/concurrency/role, API and Chromium/Firefox acceptance passed locally (`label-filter-*` logs), including a 20,001-unrelated-profile export-cap case. Exact-head CI remains required.

Existing-account onboarding (#220/ADR 0020) merged at `594468b7cee4294aa57faa46d72ac243c31ce5cb`, matching checked head `76a7ff88dad20e1bbb4e1bcf70895215b5feb905` after all five required checks passed. Post-merge contracts `45576797145` and secrets `45576797109` passed. The successor filter branch is unpublished on that PR parent; rebase only its own commits onto resulting main before publication. Never rewrite published history.

The owner has a pending delegation-policy question: may organization administrators grant only permissions they hold, or any tenant permission? Do not implement organization-wide role grants until that answer arrives. Other independent #104 work can continue.

## Interactive preview

http://localhost:15173, API 18080. Its reserved database is recorded in `.eventor-dev/user-preview.json`; the original disposable container has now been removed on shutdown. Recreate a future preview with a persistent named volume; do not reset or reseed it while the user explores. The retained build targets migration 187. Source fixtures remain available, but the original exploratory database edits and Demo VIP Guest are no longer preserved. `ci-b@example.invalid` is the normal single-workspace demo. `organizer@demo.eventor.invalid` has two memberships. `admin@demo.eventor.invalid` is an explicitly provisioned synthetic platform administrator. The existing public CI fixture password is used only in this disposable local data. Acceptance runs separately on 15174/18081 with its own databases.

The preview is served from an ignored build snapshot so unfinished source edits do not disrupt it. Its API and web are stopped at the owner’s request. The database used `--rm` and was removed by Docker on stop; the build remains, but exploratory database edits were not retained. Consult the JSON receipt/logs before restarting. The optional production worker is not running in this local preview.

## First resume actions

1. Inspect Git status, fetch origin, inspect the exact PR head and required checks. The current slice follows integrated #220; inspect its post-merge receipts too. Rebase only while unpublished, with explicit Git identity and stop-on-error shell behavior. Never reapply older backup stashes: their changes are merged.
2. Merge only after all five required checks pass and GitHub reports CLEAN. Squash using the exact checked head.
3. Fast-forward main, inspect post-merge contracts and secret-history runs, then reconcile the active handoff/ignored verified receipt.
4. Continue #104: relationship conflict/correction and remaining linked-record/initial-merge conflicts and broader user/member onboarding, event settings and remaining roster controls. Then #112 and #105–#108 in roadmap order. These slices do not complete the full product or production installers.

## Workstation

The chat path `/home/nedim/coding/eventor` is a symlink to `/home/nedim/Development/eventor`. Docker works. Native PostgreSQL regression uses ignored local PG18 binaries. Reuse this checkout, keep detailed logs ignored, and keep active project state concise. User authorization for development, testing, PR creation and verified squash merges persists.
