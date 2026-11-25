# Development resume — 2026-11-25

Verified main: `449ce2cb0ca2c22be8f711731dcf0fdcd5d4ab88` (#228), with post-merge contracts `45631105545` and secrets `45631105546` passing. Prior receipts remain in the archive/ignored checkpoint.

## Current slice

`codex/collaboration-grant-workspace` adds migration 199/ADR 0024 and Settings → Partner access. Server hints gate visibility/actions; actual commands recheck party and organization-scoped collaboration management. Staff review captured names, scope, actions, validity and shared configuration before confirmed acceptance or reasoned revocation. Interactive acceptance supplies a reviewed-meaning fingerprint; stale scope/configuration is refused on first use and cached retries. Existing unpinned programmatic acceptance/idempotency remains compatible.

Party names are published in each party's own tenant at proposal/valid acceptance and remain immutable. Legacy unknowns remain null; directory RLS is unchanged. Full application, final fresh PostgreSQL upgrade/migration/RLS/concurrency/auth-role, real reviewed API/retry, Chromium/Firefox and inspected synthetic desktop/mobile screenshots passed (`collaboration-workspace-*`). Populated 198-to-199 rehearsal now runs in the tracked upgrade script. An initial name-trigger regression masking the pre-existing missing-acceptance constraint was fixed and the final fresh suite passed.

#227 link ending merged at `8c32544ab9714c9c8861fd1b945b765c1289d223`; post-merge contracts `45628197700` and secrets `45628197752` passed. #228 lifecycle APIs merged at the verified main above, matching checked `52a6f826b952bb53cd7a42081171e95e3a483dff` after all five checks/CLEAN. Rebase only unpublished UI child commits onto that main before publication; never rewrite published history. Verify exact-head all five/CLEAN and post-merge workflows, then update the ignored receipt.

The owner reports about 9% weekly allowance remaining. Reuse these receipts and focused checks; finish this slice before starting another broad area. Next: proposal creation/discovery, scoped partner booking selection and cross-organization notice publication. None of these slices completes production installation or deployed acceptance.

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
