# Development resume — 2026-11-24

The previous stop is reconciled. PR #206 and #207 are merged. The last recorded verified baseline is `789696636d5d70bae1af083075c244b7b4af359c`; post-merge contracts/PostgreSQL run `45406989186` and secret-history run `45406989335` passed. See [current state](../PROJECT_STATE.md) and its archive for receipts.

## Current slice

`fix/staff-language-and-workspace-feedback` (PR #209) contains language persistence, interrupted-save recovery, permission-aware navigation and tab error isolation. Its browser fixtures were updated to grant the event authority they exercise and to expect revoked workspaces to disappear. Check its latest exact head before integration.

Unpublished `feat/staff-preview-polish` follows that branch with Bosnian numeric 24-hour date formatting, optional generated reference codes, preferred-name help, SMTP inside Settings and persistent internal Registry labels (migration 186, ADR 0014). Labels appear in directory/profile reads, support revision-checked assignment/retirement and block source merges until separately resolved. Full app, native PostgreSQL, fresh Docker and both-browser checks passed locally; logs use `preview-polish-*`. Finish its PR/CI after #209 is merged, rebasing only this unpublished branch onto verified main.

The user's preview remains http://localhost:15173 (API 18080), with a reserved database recorded in `.eventor-dev/user-preview.json`. It now has the tested polish build and migration 186, plus a clearly synthetic Demo VIP Guest. Do not reset or reseed that database. Acceptance uses separate ports 15174/18081 and separate fresh databases.

Next requested: email/password-only sign-in; automatic workspace selection for one membership, a named selector for several, audited switching, and explicit platform superadmin access. Ordinary organization managers must retain tenant boundaries. The empty unpublished `feat/email-first-workspace-access` branch was created before polish feedback and contains no authentication changes.

## Resume procedure

1. Inspect Git status and fetch origin. Inspect the exact PR head for the current branch; never infer CI success from local tests. Do not apply the older backup stashes: their work is already merged.
2. Merge only after all five required checks pass and GitHub reports CLEAN. Squash using the exact checked head; never force-push published history.
3. Fast-forward local main, verify post-merge contracts and secret-history workflows, then reconcile the active state.
4. Continue #104: remaining initial-merge conflicts, active relationships and open/overlapping event history, broader organization/user administration and event settings. These incremental changes do not complete that issue. Continue #112 and #105–#108 in roadmap order afterwards.

## Workstation

`/home/nedim/coding/eventor` is a symlink to `/home/nedim/Development/eventor`. Docker works; the doctor last reported 23 passes without warnings/failures. Optional native PostgreSQL regression uses ignored local PG18 binaries. Both release installers and final acceptance VM validation remain future work. User authorization for routine development, testing, PR creation and verified squash merges persists.
