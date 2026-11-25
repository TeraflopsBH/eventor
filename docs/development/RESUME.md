# Development resume — 2026-11-25

Verified main: `13f323190aceeb3d301632418b31035e167489e1` (#226), with post-merge contracts `45626497026` and secrets `45626497096` passing. Prior receipts remain in the archive/ignored checkpoint.

## Current slice

`codex/collaboration-grant-lifecycle-commands` adds migration 198/ADR 0023: party-scoped list/detail and recipient acceptance/grantor revocation APIs over existing commands. Organization-scoped collaboration management is required. Metadata is allowlisted; detailed review adds deliberately shared scope configuration. Raw runtime table reads are revoked. Cached acceptance rechecks current role, party, state/window and accepting actor; cached revocation rechecks grantor authority.

The migration reconciles the existing proposed-grant revocation command with its acceptance constraint. Never-accepted proposals retain null acceptance facts; active/expired grants still require actual acceptance. The pre-fix failure was reproduced. Full application/fresh PostgreSQL upgrade/migration/RLS/concurrency/auth-role checks and real runtime/API acceptance-revocation races in both orders passed (`collaboration-lifecycle-*`, `collaboration-proposal-*`). Exact-head CI remains required. Staff controls, new proposal creation/discovery and partner notice publication remain follow-ups.

#227 attributed link ending integrated at `8c32544ab9714c9c8861fd1b945b765c1289d223`, identical to checked `f76f429ff487d03149113fd528cfa262b0e78d93` after all five checks/CLEAN. Post-merge contracts `45628197700` is pending; secrets `45628197752` passed. Commit/rebase only unpublished collaboration child commits onto merged main before publication; never rewrite published history. Inspect post-merge checks and continue staff grant review/accept/revoke controls before proposal/partner discovery and cross-organization notice delivery.

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
