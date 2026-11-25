# Development resume — 2026-11-25

Verified main: `1d6a585bbe83a800ac90aeb0196fcd52ae1ec919` (#225), with post-merge contracts `45625280596` and secrets `45625280632` passing. Prior receipts remain in the archive/ignored checkpoint.

## Current slice

`codex/end-event-booking-links` adds migration 197 and confirmed bilingual ending of an event-owned association. Exact event management is sufficient; the source booking/grant is not mutated. The existing trigger retains original actor/reason/audit and immutable relation. Ended retries return original metadata; revoked links cannot be relabelled. New publication through terminal links is refused while historical receipts remain. Cached API retries recheck event scope.

Full application/fresh PostgreSQL upgrade/migration/RLS/concurrency/auth-role tests and Chromium/Firefox creation/cancelled-ending/confirmed-ending/denial flows passed (`end-booking-link-*`). Final SQL includes exact scope, suspension and source-revoked partner ending. Publication/ending races test both lock orders; duplicate ending concurrency is also covered. No booking/event/reservation/grant or prior notice decision changes.

Parent UI #226 merged at `13f323190aceeb3d301632418b31035e167489e1`, identical to checked head `dc57cc615ccf0c5f72c9fa4f02a623a4362dbb93` after all five checks/CLEAN. Post-merge contracts `45626497026` and secrets `45626497096` are pending. API #225 integrated at `1d6a585bbe83a800ac90aeb0196fcd52ae1ec919`, identical to checked `b7b7df823049abb7affdbaeb129832c48389043d`; all five checks/CLEAN passed. Post-merge contracts `45625280596` and secrets `45625280632` passed.

Inspect #226 post-merge runs. Commit/rebase only unpublished ending child commits onto the merged main before publication; never rewrite published history. Next: #112 explicit scoped partner setup/delivery and reviewed resolution/amendment/postponement workflows; do not interpret inbox publication as SMTP delivery or acknowledgement as resolution.

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
