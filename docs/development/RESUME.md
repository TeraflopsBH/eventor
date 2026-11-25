# Development resume — 2026-11-25

Verified main: `f4fc051e29210855145bb748d60dd4dce823d999` (#215), with post-merge contracts `45518780190` and secrets `45518783619` passing. PR #216 is merged at `cb1d15831f4a9a51536a8e74c308f0249ad4fa6b`; inspect its post-merge runs before claiming that baseline verified.

## Current slice

`codex/dev-database-backup-shutdown` adds protected local backups and a persistent-container guard before `scripts/dev/db.sh down`. A full archive read must pass before stopping; the named volume is retained. Isolated project/state/port overrides support acceptance without touching the default database. The lifecycle test verifies stop/restart retention, an actual restore and failed-backup refusal; local logs/receipts are in `database-lifecycle-acceptance.log` and its printed ignored directory. Shell syntax and real isolated acceptance passed. Exact-head CI is required.

The slice was rebased while unpublished onto merged #216 main. Exact-head CI remains required before integration. No published history should be rewritten. Host staff bootstrap (#216/ADR 0017), RSVP settings (#214/migration 189/ADR 0016) and bulk recorded-name restoration (#215/migration 190) are integrated. Broader tenant onboarding, linked-record merge conflicts and remaining event/roster controls remain open under #104.

## Interactive preview

http://localhost:15173, API 18080. Its reserved database is recorded in `.eventor-dev/user-preview.json`; the original disposable container has now been removed on shutdown. Recreate a future preview with a persistent named volume; do not reset or reseed it while the user explores. The retained build targets migration 187. Source fixtures remain available, but the original exploratory database edits and Demo VIP Guest are no longer preserved. `ci-b@example.invalid` is the normal single-workspace demo. `organizer@demo.eventor.invalid` has two memberships. `admin@demo.eventor.invalid` is an explicitly provisioned synthetic platform administrator. The existing public CI fixture password is used only in this disposable local data. Acceptance runs separately on 15174/18081 with its own databases.

The preview is served from an ignored build snapshot so unfinished source edits do not disrupt it. Its API and web are stopped at the owner’s request. The database used `--rm` and was removed by Docker on stop; the build remains, but exploratory database edits were not retained. Consult the JSON receipt/logs before restarting. The optional production worker is not running in this local preview.

## First resume actions

1. Inspect Git status, fetch origin, inspect the exact PR head and required checks. The current slice follows checked #216. Rebase only while unpublished, with explicit Git identity and stop-on-error shell behavior. Never reapply older backup stashes: their changes are merged.
2. Merge only after all five required checks pass and GitHub reports CLEAN. Squash using the exact checked head.
3. Fast-forward main, inspect post-merge contracts and secret-history runs, then reconcile the active handoff/ignored verified receipt.
4. Continue #104: remaining linked-record/initial-merge conflicts and broader user/member onboarding, event settings and remaining roster controls. Then #112 and #105–#108 in roadmap order. These slices do not complete the full product or production installers.

## Workstation

The chat path `/home/nedim/coding/eventor` is a symlink to `/home/nedim/Development/eventor`. Docker works. Native PostgreSQL regression uses ignored local PG18 binaries. Reuse this checkout, keep detailed logs ignored, and keep active project state concise. User authorization for development, testing, PR creation and verified squash merges persists.
