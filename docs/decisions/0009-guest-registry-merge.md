# ADR 0009: Reversible Guest Registry merge

- **Status:** Accepted
- **Date:** 2026-11-17
- **Related:** [Issue #104](https://github.com/TeraflopsBH/eventor/issues/104), Technical Blueprint v1.2 §33.4

## Decision

Registry managers with `guest.registry.merge` can review two active profiles within one organization. The operator selects the destination, compares both profiles and confirms that the source is a duplicate. Commit requires a review recorded for the current actor, checks the reviewed revisions and uses the destination names as the resolved fields.

An eligible source has zero event participations, contact points, identifiers and incoming merge references. The command preserves the source row, marks it merged and records the identity references and resolution. Event snapshots stay associated with their existing participation records. The merge history records staff attribution, the reason and the timestamps.

A reviewer can restore the source from merge history. Restoration reactivates the source with its own name values and records the correction. A stale or externally altered source requires investigation before it can be restored through this workflow.

Merge planning for linked profiles requires explicit resolution of event, contact and identifier conflicts, with a correction workflow for each affected record.
