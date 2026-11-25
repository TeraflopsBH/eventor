# Development resume — 2026-11-25

Verified main: `f6039be2d630b7834fe19856660a051a17db2ec9` (#229), with post-merge contracts `45671121922` and secrets `45671121975` passing. Prior receipts remain in the archive/ignored checkpoint.

## Current slice

`codex/partner-booking-selector` adds migration 200 and accepted partner booking choices in Events → Linked bookings. Exact event managers select captured provider/purpose and confirm without typing IDs. The server reads only incoming active/accepted/effective booking.event.link grant metadata, excludes all historical associations before pagination and audits the read. Existing creation rechecks current authority; source revocation after selection refuses linking. Provider booking records, directory/configuration, commercial/guest data and event/provider facts remain protected.

Full application, final staff tests/build, fresh PostgreSQL upgrade/migration/RLS/concurrency/auth-role, Chromium/Firefox and inspected synthetic desktop/mobile screenshots passed (`partner-selector-*`). Browser tests cover cancelled confirmation, real source revocation before commit, explicit partner-scope POST, no source/guest access, ended-link exclusion, unchanged event facts, Bosnian labels/mobile and denied reload cleanup. Exact-head CI and post-merge verification are required before considering integration verified.

#229 Partner access passed exact-head all five/CLEAN at `08b510740e630564dff339aa7e7b95a0707a9d6b`; squash main and post-merge receipts are recorded above. Never rewrite published history. The owner reports about 6% weekly allowance remaining: reuse completed receipts and focused checks. Next: new proposal creation/discovery and cross-organization notice publication; these slices do not complete production installation or deployed acceptance.

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
