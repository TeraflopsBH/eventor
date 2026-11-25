# Development resume — 2026-11-25

Verified main: `fe5cec3df1a970c14eec609a80f15141d565e3ec` (#224), with post-merge contracts `45623757322` and secrets `45623757442` passing. Prior receipts remain in the archive/ignored checkpoint.

## Current slice

`codex/event-disruption-inbox-workspace` adds the bilingual Events inbox, explicit public-source preview/publication confirmation, event-only receipt acknowledgement and scoped source controls. The heading receives focus when opened. Public text is escaped, date/summary text identifies source choices, and authorization failure clears private panel data. All event/booking/guest decisions remain separate.

The API parent #225 merged at `1d6a585bbe83a800ac90aeb0196fcd52ae1ec919`, matching checked head `b7b7df823049abb7affdbaeb129832c48389043d` after all five checks/CLEAN. Post-merge verification is pending. It adds migration 196/ADR 0022 over the existing receipt aggregate; full application/final fresh PostgreSQL/API concurrency acceptance passed. The staff slice adds no further migration/API change. Full application, Chromium/Firefox flow and inspected synthetic desktop/mobile screenshots passed locally; final source-choice wording was rechecked with staff build/browser runs. Exact-head CI remains required.

Inspect #225 post-merge runs; commit/rebase only unpublished UI child commits onto that main before publication. Never rewrite published history. Next #112 work: explicitly scoped cross-organization partner setup/delivery and reviewed resolution/amendment/postponement flows; do not treat inbox publication as SMTP delivery or acknowledgement as resolution.

The owner has a pending delegation-policy question: may organization administrators grant only permissions they hold, or any tenant permission? Do not implement organization-wide role grants until that answer arrives. Other independent #104 work can continue.

## Interactive preview

http://localhost:15173, API 18080. Its reserved database is recorded in `.eventor-dev/user-preview.json`; the original disposable container has now been removed on shutdown. Recreate a future preview with a persistent named volume; do not reset or reseed it while the user explores. The retained build targets migration 187. Source fixtures remain available, but the original exploratory database edits and Demo VIP Guest are no longer preserved. `ci-b@example.invalid` is the normal single-workspace demo. `organizer@demo.eventor.invalid` has two memberships. `admin@demo.eventor.invalid` is an explicitly provisioned synthetic platform administrator. The existing public CI fixture password is used only in this disposable local data. Acceptance runs separately on 15174/18081 with its own databases.

The preview is served from an ignored build snapshot so unfinished source edits do not disrupt it. Its API and web are stopped at the owner’s request. The database used `--rm` and was removed by Docker on stop; the build remains, but exploratory database edits were not retained. Consult the JSON receipt/logs before restarting. The optional production worker is not running in this local preview.

## First resume actions

1. Inspect Git status, fetch origin, inspect the exact PR head and required checks. The current slice follows integrated #223; inspect its post-merge receipts too. Rebase only while unpublished, with explicit Git identity and stop-on-error shell behavior. Never reapply older backup stashes: their changes are merged.
2. Merge only after all five required checks pass and GitHub reports CLEAN. Squash using the exact checked head.
3. Fast-forward main, inspect post-merge contracts and secret-history runs, then reconcile the active handoff/ignored verified receipt.
4. Continue #104: relationship conflict/correction and remaining linked-record/initial-merge conflicts and broader user/member onboarding, event settings and remaining roster controls. Then #112 and #105–#108 in roadmap order. These slices do not complete the full product or production installers.

## Workstation

The chat path `/home/nedim/coding/eventor` is a symlink to `/home/nedim/Development/eventor`. Docker works. Native PostgreSQL regression uses ignored local PG18 binaries. Reuse this checkout, keep detailed logs ignored, and keep active project state concise. User authorization for development, testing, PR creation and verified squash merges persists.
