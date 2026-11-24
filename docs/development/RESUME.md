# Development resume — 2026-11-24

The previous stop is reconciled. PR #206 and #207 are merged. The last recorded verified baseline is `789696636d5d70bae1af083075c244b7b4af359c`; post-merge contracts/PostgreSQL run `45406989186` and secret-history run `45406989335` passed. See [current state](../PROJECT_STATE.md) and its archive for receipts.

## Current slice

Branch `fix/staff-language-and-workspace-feedback` fixes anonymous language persistence, interrupted account preference saves, permission-aware navigation and stale cross-tab error messages. The new `/me/workspaces` endpoint returns current navigation hints, while each data endpoint retains its scoped checks. Full app checks, fresh isolated PostgreSQL acceptance and Chromium/Firefox staff shell tests passed locally. Logs use `staff-feedback-*`.

The user's interactive preview is on http://localhost:15173 with API 18080. Its database is reserved for exploration; `.eventor-dev/user-preview.json` records the container and fixed connection directory. Do not reset or reseed that database. Fresh acceptance used separate ports 15174/18081 and a separate database.

Next requested: email/password-only sign-in; automatic workspace selection for a single membership, a named selector for multiple memberships, audited switching, and an explicit platform superadmin role. Do not grant ordinary organization managers cross-tenant access.

## Resume procedure

1. Inspect Git status and fetch origin. Inspect the exact PR head for the current branch; never infer CI success from local tests. Do not apply the older backup stashes: their work is already merged.
2. Merge only after all five required checks pass and GitHub reports CLEAN. Squash using the exact checked head; never force-push published history.
3. Fast-forward local main, verify post-merge contracts and secret-history workflows, then reconcile the active state.
4. Continue #104: remaining initial-merge conflicts, active relationships and open/overlapping event history, broader organization/user administration and event settings. These incremental changes do not complete that issue. Continue #112 and #105–#108 in roadmap order afterwards.

## Workstation

`/home/nedim/coding/eventor` is a symlink to `/home/nedim/Development/eventor`. Docker works; the doctor last reported 23 passes without warnings/failures. Optional native PostgreSQL regression uses ignored local PG18 binaries. Both release installers and final acceptance VM validation remain future work. User authorization for routine development, testing, PR creation and verified squash merges persists.
