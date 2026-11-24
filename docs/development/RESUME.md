# Development resume — 2026-11-24

The previous stop is reconciled. PR #206 merged at `7f6bcdcc0fedec5944af6764465516201683ba3c`; post-merge contracts/PostgreSQL run `45404712081` and secret-history run `45404712074` passed. See [current state](../PROJECT_STATE.md) and its linked archive for behavior and historical receipts.

## Current slice

Branch `feat/event-guest-bulk-groups` adds bulk roster group add/remove (migration 185, API/OpenAPI and bilingual staff UI). Existing group roles and unrelated memberships remain intact; new assignments receive the member role. Retired memberships can be removed. Every selected revision must match, with atomic rollback on any failure. Replays recheck current event authority.

Local full application checks, native PostgreSQL migrations/upgrades/RLS/concurrency/auth checks, fresh Docker database acceptance and Chromium/Firefox workflows passed. Logs: `.eventor-dev/logs/bulk-groups-full.log`, `bulk-groups-native.log`, `bulk-groups-compose-tests.log` and `bulk-groups-acceptance.log`. These ignored logs are local evidence, not portable repository dependencies.

## Resume procedure

1. Inspect Git status and fetch origin. Inspect the exact PR head for the current branch; never infer CI success from local tests. Do not apply the older backup stashes: their work is already merged.
2. Merge only after all five required checks pass and GitHub reports CLEAN. Squash using the exact checked head; never force-push published history.
3. Fast-forward local main, verify post-merge contracts and secret-history workflows, then reconcile the active state.
4. Continue #104: remaining initial-merge conflicts, active relationships and open/overlapping event history, broader organization/user administration and event settings. Group bulk changes do not complete that issue. Continue #112 and #105–#108 in roadmap order afterwards.

## Workstation

`/home/nedim/coding/eventor` is a symlink to `/home/nedim/Development/eventor`. Docker works; the doctor last reported 23 passes without warnings/failures. Optional native PostgreSQL regression uses ignored local PG18 binaries. Both release installers and final acceptance VM validation remain future work. User authorization for routine development, testing, PR creation and verified squash merges persists.
