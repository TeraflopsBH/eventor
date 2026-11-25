# Development resume — 2026-11-25

Verified main: `25bb314ab3ca09c2c766bb593cd98dfa45fe47fc` (#217), with post-merge contracts `45521624367` and secrets `45521624406` passing. PRs #214–#217 are integrated and verified; the ignored checkpoint/archive retain prior receipts.

## Current slice

`codex/reviewed-registry-label-merges` adds migration 191/ADR 0018: actor-reviewed, explicit transfer of non-overlapping classification assignments with their original metadata. Overlaps and the existing 100-label limit remain guarded. A private append-only journal protects both strict and reviewed current-contact/reference restoration. The correction preview shows returning labels read-only; edited/removed assignments block all restoration paths without partial effects. Legacy merge overloads cannot bypass label acknowledgement, and renamed helpers remain private.

Full application, fresh PostgreSQL upgrade/migration/RLS/concurrency/role and Chromium/Firefox acceptance passed locally. The suite includes retired assignments, stale definition reviews, metadata preservation, combined contact/reference transfer, edited-contact/reference correction, changed-label refusal, old overloads, permission revocation and journal immutability. Logs are `registry-label-merge-*` and `label-merge-compose-tests.log`; exact-head CI remains required before merging. Inspect Git status before switching. Never rewrite published history.

## Interactive preview

http://localhost:15173, API 18080. Its reserved database is recorded in `.eventor-dev/user-preview.json`; the original disposable container has now been removed on shutdown. Recreate a future preview with a persistent named volume; do not reset or reseed it while the user explores. The retained build targets migration 187. Source fixtures remain available, but the original exploratory database edits and Demo VIP Guest are no longer preserved. `ci-b@example.invalid` is the normal single-workspace demo. `organizer@demo.eventor.invalid` has two memberships. `admin@demo.eventor.invalid` is an explicitly provisioned synthetic platform administrator. The existing public CI fixture password is used only in this disposable local data. Acceptance runs separately on 15174/18081 with its own databases.

The preview is served from an ignored build snapshot so unfinished source edits do not disrupt it. Its API and web are stopped at the owner’s request. The database used `--rm` and was removed by Docker on stop; the build remains, but exploratory database edits were not retained. Consult the JSON receipt/logs before restarting. The optional production worker is not running in this local preview.

## First resume actions

1. Inspect Git status, fetch origin, inspect the exact PR head and required checks. The current slice follows verified #217. Rebase only while unpublished, with explicit Git identity and stop-on-error shell behavior. Never reapply older backup stashes: their changes are merged.
2. Merge only after all five required checks pass and GitHub reports CLEAN. Squash using the exact checked head.
3. Fast-forward main, inspect post-merge contracts and secret-history runs, then reconcile the active handoff/ignored verified receipt.
4. Continue #104: remaining linked-record/initial-merge conflicts and broader user/member onboarding, event settings and remaining roster controls. Then #112 and #105–#108 in roadmap order. These slices do not complete the full product or production installers.

## Workstation

The chat path `/home/nedim/coding/eventor` is a symlink to `/home/nedim/Development/eventor`. Docker works. Native PostgreSQL regression uses ignored local PG18 binaries. Reuse this checkout, keep detailed logs ignored, and keep active project state concise. User authorization for development, testing, PR creation and verified squash merges persists.
