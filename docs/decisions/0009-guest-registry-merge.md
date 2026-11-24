# ADR 0009: Reversible Guest Registry merge

- **Status:** Accepted
- **Date:** 2026-11-17
- **Related:** [Issue #104](https://github.com/TeraflopsBH/eventor/issues/104), Technical Blueprint v1.2 §33.4

## Decision

Registry managers with `guest.registry.merge` can review two active profiles within one organization. The operator selects the destination, compares both profiles and confirms that the source is a duplicate. Commit requires a review recorded for the current actor, checks the reviewed revisions and uses the destination names as the resolved fields.

The initial implementation required an eligible source to have zero event participations, contact points, identifiers and incoming merge references. Later accepted extensions preserve closed-event references and permit the reviewed contact transfer described below. The command preserves the source row, marks it merged and records the identity references and resolution. Event snapshots stay associated with their existing participation records. The merge history records staff attribution, the reason and the timestamps.

A reviewer can restore the source from merge history. Restoration reactivates the source with its own name values and records the correction. A stale or externally altered source requires investigation before it can be restored through this workflow.

Merge planning for linked profiles requires explicit resolution of event, contact and identifier conflicts, with a correction workflow for each affected record.

## Reviewed non-conflicting contact transfer — 2026-11-24

A reviewer with both Registry merge and contact-management authority can explicitly move every supported email/phone contact from the duplicate source to the destination. The review displays both contact sets and requires a separate transfer confirmation. Contact IDs, encrypted values, normalized fingerprints, consent, primary flags and verification evidence are preserved. Encryption remains bound to the same organization and contact kind, so ownership reassignment does not require decryption or re-encryption in SQL.

Competing primary contacts, duplicate values and unsupported legacy contact kinds require separate resolution and block this command. Identifiers, active relationships, open/overlapping event history and incoming merge references retain their existing guards. No contact is discarded, deduplicated or given more permissive consent by a merge.

Both parent profiles are locked in stable order. Review evidence binds the exact source and destination contact IDs/revisions as well as profile and historical-event revisions. The existing name/history transition is reused through private helpers; runtime callers cannot bypass the transfer boundary. An append-only, tenant-scoped transfer journal records only merge/contact references and expected transferred revisions. API idempotent retries recheck contact-management authority.

Restoration requires the same additional authority and atomically returns the transferred contacts, with their original IDs and protected facts, to the reactivated source. Contact revisions advance on transfer and restoration. If any transferred contact has subsequently changed, restoration refuses to overwrite or reassign that changed record; the merge, current contact facts and journal remain intact. A separate reviewed correction is required for that case. Do not reset revisions or alter the journal to force restoration. This extension does not complete the broader linked-record conflict-resolution scope of #104.
