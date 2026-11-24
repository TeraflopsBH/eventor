# Resume checkpoint — 2026-11-24

The user requested a stop after the current task. Do not start another feature before reconciling this checkpoint.

## Verified main

`main` includes PR #205, commit `5f757c887e604d1f1886884249f3a06405956cdb`. Post-merge contracts/PostgreSQL run `45362411313` and secret-history run `45362411321` passed. This includes public cancellation isolation, reviewed contact transfers and source-reference transfers with preserved encryption identity.

## Current task saved for review

Branch: `feat/reviewed-merge-restoration-corrections`.

Reviewed restoration is implemented in migration `000184`, API/OpenAPI, the bilingual Registry UI and tests. A reviewer chooses which current contacts/references return to the source; unselected records remain at the destination, and removed references remain removed. Actor-bound state evidence, current permissions, stale-review rejection, idempotent retries and immutable correction evidence protect the operation. History identifies reviewed restorations. See ADR 0013.

Validation on the final implementation passed: full application checks and fresh Docker PostgreSQL migrations/upgrades/RLS/constraints/concurrency/auth-role checks; Chromium and Firefox completed the reviewed correction with edited contact facts, an edited reference retaining its encryption identity, a removed reference kept deleted, and successful idempotent replay. Native PostgreSQL checks also passed during development, before the final evidence-hash column was added; the final Docker run covers that addition.

Local logs are under `.eventor-dev/logs/`: `reviewed-restoration-full.log`, `reviewed-restoration-acceptance.log`, `reviewed-restoration-compose-tests.log`, and `reviewed-restoration-native.log`. The latest local receipt `.eventor-dev/STOP_CHECKPOINT.json` records the saved head/PR when available. These ignored files are workstation evidence, not portable repository dependencies.

## First actions on resume

1. Inspect `git status --short --branch`, fetch `origin`, and inspect the PR for this exact branch/head. Do not reapply the older backup stashes: their contact/provider work is already merged.
2. Inspect required CI on the saved PR head. Fix failures if any; merge only after all five required checks pass and GitHub reports a clean merge. Squash using the exact checked head. Do not force-push published history.
3. Fast-forward local `main`, verify post-merge contracts and secret-history runs, and reconcile `docs/PROJECT_STATE.md` with that evidence.
4. Continue #104 with remaining initial-merge conflict resolution, active relationships, open/overlapping event history and broader organization/user administration. Do not count the whole issue complete from these contact/reference slices. Follow the roadmap for #112 and #105–#108 afterwards.

## Workstation

The chat path `/home/nedim/coding/eventor` is a symlink to the existing checkout `/home/nedim/Development/eventor`. Docker works for the current user; the doctor last reported 23 passes and no warnings/failures. Both release installers and final acceptance VM validation remain future roadmap work. User authorization for routine development, testing, PR creation and verified squash merges persists; no repeated permission questions are needed.
