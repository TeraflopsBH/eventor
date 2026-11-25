# Development resume — 2026-11-25

Verified main: `594468b7cee4294aa57faa46d72ac243c31ce5cb` (#220), with post-merge contracts `45576797145` and secrets `45576797109` passing. Prior receipts remain in the archive/ignored checkpoint.

## Current slice

`codex/contextual-workspace-headings` updates the staff shell heading and help text for each selected section in both languages. No API/schema/permission behavior changes. Staff tests/build and Chromium/Firefox language/navigation/error-isolation journeys passed (`workspace-headings-*` logs). The branch was rebased onto #221 main before publication; never rewrite published history.

#221 classification filtering merged at `946410af4ef2e4a621954ca613cd6fd6b32b8d02`, matching exact checked head `655c740891073b232f66edf5d1568b85b4f9ac0b` after all five checks passed and CLEAN. The repaired CI contracts run `45615199360` and secrets `45615198961` passed. Post-merge contracts `45616192807` and secrets `45616192184` are running. Migration 193 and the richer-navigation mobile browser repair are integrated.

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
