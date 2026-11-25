# Development resume — 2026-11-25

Verified main: `745b6d4b2b73a8f643f3aa9afc999485ed6c1df2` (#223), with post-merge contracts `45620849659` and secrets `45620849359` passing. Prior receipts remain in the archive/ignored checkpoint.

## Current slice

`codex/event-disruption-inbox-commands` adds migration 196/ADR 0022. Explicit local notice publication needs exact booking/event management and an active local association; immutable public snapshots are readable/acknowledgeable by event managers. Original publication/acknowledgement audits and first timestamps are retained under concurrent duplicates. Cached retries recheck source/event authority. Internal source/receipt fields are omitted. Booking/event/resource/guest facts remain unchanged. Partner publication and staff notice controls remain follow-ups.

Full application checks, final fresh PostgreSQL upgrade/migration/RLS/concurrency/auth-role tests and real PostgreSQL concurrent command/API-revocation acceptance passed (`disruption-inbox-*`). SQL covers safe/legacy projections, pagination, immutable history, scope and unchanged aggregates. Exact-head CI remains required.

#224 linked-booking UI integrated at `fe5cec3df1a970c14eec609a80f15141d565e3ec`, matching checked head `2d3603a44ab70a6d44bea1900bcad56233fe31bc` after all five checks/CLEAN. Post-merge contracts `45623757322` and secrets `45623757442` are pending. Rebase only unpublished child commits onto this main before publication. Next: notice inbox/publication/acknowledgement staff controls with explicit confirmation and bilingual permission/failure handling. Never treat inbox publication as SMTP delivery or acknowledgement as resolution.

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
