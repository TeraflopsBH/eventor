# Development resume — 2026-11-25

Verified main: `b6a3c94000fe26831f9997935fd0bcb9a07d33e3` (#222), with post-merge contracts `45617577494` and secrets `45617577661` passing. Prior receipts remain in the archive/ignored checkpoint.

## Current slice

`codex/booking-event-link-commands` adds migration 194/ADR 0021: create/list boundaries over existing associations with exact event management plus local booking management or active accepted cross-organization booking scope. Existing active identical links are reused; terminal/changed meaning is refused. Direct app-role table access is revoked. No booking/event status, snapshots or guest data change. This is an API foundation; staff selectors and disruption delivery/acknowledgement remain open.

Full application and fresh PostgreSQL upgrade/migration/RLS/concurrency/role checks passed locally (`booking-link-*`). SQL/API regressions cover grant/event/tenant scope, revocation, normalized cached retries and retained provenance. Concurrent requests produce one link/audit; real PostgreSQL API retries recheck revoked booking authority. Exact-head CI remains required. The branch was rebased onto verified #222 main before publication; never rewrite published history.

#221 is verified at `946410af4ef2e4a621954ca613cd6fd6b32b8d02` (post-merge contracts `45616192807`, secrets `45616192184`). #222 contextual headings merged at `b6a3c94000fe26831f9997935fd0bcb9a07d33e3`, matching checked head `b99fbf6e7fa51244bccb32adcef4574d828ffb46` after all five checks passed. Post-merge contracts `45617577494` and secrets `45617577661` passed.

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
