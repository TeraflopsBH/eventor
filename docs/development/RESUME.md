# Development resume — 2026-11-25

> **Current resumption guidance — 2026-11-27:** This document records a dated 2026-11-25 checkpoint, not a live assertion of branch state or pending CI. Read [project state](../PROJECT_STATE.md), [authority register](../DOCUMENTATION_AUTHORITY.md), [Codex handoff](../CODEX_HANDOFF.md) and [roadmap](../ROADMAP.md), then inspect actual checkout, ignored local checkpoint and current GitHub PR/CI state. Approved design integration #239 at `3941f872` has passed post-merge CI. Do not replay old commits, rebase published branches, discard local work or infer unpublished progress. Continue the existing #104/#112 → #105–107 → #110/#111/#108 sequence, Phase 9 final acceptance.

Verified main: `f6039be2d630b7834fe19856660a051a17db2ec9` (#229), with post-merge contracts `45671121922` and secrets `45671121975` passing. Prior receipts remain in the archive/ignored checkpoint.

## Current slice

`codex/booking-collaboration-proposals` adds migration 201 and a dedicated managed-booking proposal API. Both organization collaboration management and organization/exact-booking management are required. Scope/action/projection are fixed to this booking, `booking.event.link` and `{}`. Purpose, recipient and validity are explicit; nullable expiry is intentional. Existing proposal/revision/audit/name capture remain unchanged, recipient acceptance is separate and source booking/event facts do not change.

Full application/fresh PostgreSQL upgrade/migration/RLS/concurrency/auth-role and real API concurrent proposal→recipient review/acceptance→link tests passed (`booking-proposal-*`). Concurrent retries create one proposal/revision/audit; removing either source permission denies cached replies. UUIDs/purpose/time representations normalize. Creation replies are historical receipts; grant detail provides current lifecycle.

Parent #230 selector merged at `807378fc9e82fc1abe5a9590ea1b0218bc708ee5`, identical to checked head `bef6da065a76b086724999eba6504069ed550cd7` after all five checks/CLEAN. Post-merge verification is pending. Its full/fresh SQL/API/browser/mobile/screenshot acceptance passed. Inspect post-merge workflows and commit/rebase only unpublished proposal child commits onto merged main before publication. Never rewrite published history.

Owner reports ~6% weekly allowance. Reuse completed receipts and focused checks. Next: staff proposal controls/recipient discovery and cross-organization notice publication; production installers/deployed acceptance remain open.

The owner has a pending delegation-policy question: may organization administrators grant only permissions they hold, or any tenant permission? Do not implement organization-wide role grants until that answer arrives. Other independent #104 work can continue.

## Interactive preview

http://localhost:15173, API 18080. Its reserved database is recorded in `.eventor-dev/user-preview.json`; the original disposable container has now been removed on shutdown. Recreate a future preview with a persistent named volume; do not reset or reseed it while the user explores. The retained build targets migration 187. Source fixtures remain available, but the original exploratory database edits and Demo VIP Guest are no longer preserved. `ci-b@example.invalid` is the normal single-workspace demo. `organizer@demo.eventor.invalid` has two memberships. `admin@demo.eventor.invalid` is an explicitly provisioned synthetic platform administrator. The existing public CI fixture password is used only in this disposable local data. Acceptance runs separately on 15174/18081 with its own databases.

The preview is served from an ignored build snapshot so unfinished source edits do not disrupt it. Its API and web are stopped at the owner’s request. The database used `--rm` and was removed by Docker on stop; the build remains, but exploratory database edits were not retained. Consult the JSON receipt/logs before restarting. The optional production worker is not running in this local preview.

## First resume actions

1. Inspect Git status, fetch origin, inspect the exact PR head and required checks. Use the latest ignored checkpoint for receipts recorded after this tracked handoff. Rebase only while unpublished, with explicit Git identity and stop-on-error shell behavior. Never reapply older backup stashes: their changes are merged.
2. Merge only after all five required checks pass and GitHub reports CLEAN. Squash using the exact checked head.
3. Fast-forward main, inspect post-merge contracts and secret-history runs, then reconcile the active handoff/ignored verified receipt.
4. Continue #104: relationship conflict/correction and remaining linked-record/initial-merge conflicts and broader user/member onboarding, event settings and remaining roster controls. Then #112 and #105–#108 in roadmap order. These slices do not complete the full product or production installers.

## Workstation

The chat path `/home/nedim/coding/eventor` is a symlink to `/home/nedim/Development/eventor`. Docker works. Native PostgreSQL regression uses ignored local PG18 binaries. Reuse this checkout, keep detailed logs ignored, and keep active project state concise. User authorization for development, testing, PR creation and verified squash merges persists.
