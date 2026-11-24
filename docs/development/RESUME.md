# Development resume — 2026-11-24

The previous stop is reconciled. PR #206 and #207 are merged. The last recorded verified baseline is `789696636d5d70bae1af083075c244b7b4af359c`; post-merge contracts/PostgreSQL run `45406989186` and secret-history run `45406989335` passed. See [current state](../PROJECT_STATE.md) and its archive for receipts.

## Current slice

Branch `feat/registry-primary-contact-conflict-review` improves the blocked Registry merge comparison. Authorized staff can compare conflicting contacts and explicitly clear a competing primary flag through the existing audited, revision-checked editor, then receive a fresh merge preview. Values, consent and verification remain intact. A stale edit does not overwrite newer consent. The ordinary separate merge confirmation and server guards remain in force. This independent contact edit is preserved by a later merge restoration. No API/schema change.

Full application checks and the contact-only, reference/contact and reviewed-restoration browser journeys passed in Chromium and Firefox against the existing local PostgreSQL database. Local logs: `.eventor-dev/logs/primary-conflict-full.log`, `primary-conflict-contact-browser.log`, `primary-conflict-reference-browser.log`, `primary-conflict-acceptance.log`. Native/fresh Docker database checks passed for the preceding migration 185 slice; this UI-only slice did not repeat them. Ignored logs are workstation evidence, not portable dependencies.

## Resume procedure

1. Inspect Git status and fetch origin. Inspect the exact PR head for the current branch; never infer CI success from local tests. Do not apply the older backup stashes: their work is already merged.
2. Merge only after all five required checks pass and GitHub reports CLEAN. Squash using the exact checked head; never force-push published history.
3. Fast-forward local main, verify post-merge contracts and secret-history workflows, then reconcile the active state.
4. Continue #104: remaining initial-merge conflicts, active relationships and open/overlapping event history, broader organization/user administration and event settings. These incremental changes do not complete that issue. Continue #112 and #105–#108 in roadmap order afterwards.

## Workstation

`/home/nedim/coding/eventor` is a symlink to `/home/nedim/Development/eventor`. Docker works; the doctor last reported 23 passes without warnings/failures. Optional native PostgreSQL regression uses ignored local PG18 binaries. Both release installers and final acceptance VM validation remain future work. User authorization for routine development, testing, PR creation and verified squash merges persists.
