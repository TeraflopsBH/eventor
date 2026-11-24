# ADR 0013 — Reviewed restoration using current Registry records

- Status is accepted.
- Date is 2026-11-24.
- Related: [ADR 0009](0009-guest-registry-merge.md), [ADR 0012](0012-reference-encryption-identity.md), [#104](https://github.com/TeraflopsBH/eventor/issues/104).

## Decision

Keep the existing unchanged-record restoration command. Add a separate reviewed correction path for an active merge whose transferred contacts or source references were subsequently edited or removed.

The authorized reviewer sees current source/destination identities and the transferred records, with changed/removed indicators. Each existing contact/reference can explicitly return to the source or remain at the destination. Current consent, primary flags, verification evidence, reference values and encryption identity are preserved. Removed references cannot be selected for return and require explicit acknowledgement that they remain removed. No original private values are copied into correction evidence or recreated from transfer journals.

Review and application require Registry merge authority plus the contact/reference management grants required by the original transfer journals, even when the reviewer keeps records at the destination. A review is bound to the actor, merge, both current profile revisions and current transferred-record state. The apply command locks the merge, both parents in stable order and current transferred rows, then revalidates that evidence and the selected subsets. Changed state requires a new review. A source identity changed outside the supported merge lifecycle or records moved to an unexpected owner remain blocked.

Application reactivates the original source and returns only selected records. Kept records stay at the destination. Removed references stay absent. Source revision advances once; destination reference editors are invalidated when references return. All steps, the existing restoration audit and a private append-only correction record commit atomically. Replayed API commands recheck current authority. The UI retains its idempotency key for retries of unchanged choices.

Correction evidence contains actor/review/merge references and returned/kept/removed record IDs, without copying contact values, consent snapshots or reference ciphertext. Merge history distinguishes reviewed correction from unchanged-record restoration. Event participation IDs, event identity snapshots, invitations and responses are not rewritten.

## API and UI boundary

A POST restoration preview returns a review ID, both profile projections, contact IDs/current revisions/changed flags, and reference IDs/changed/removed flags. The client obtains current values through the existing separately authorized contact/reference APIs.

A separate idempotent restore-reviewed command requires the review ID, explicit arrays of contact/reference IDs to return, removed-reference acknowledgement and the constant resolution `return_selected_current_records`. Unknown, duplicate or removed selected IDs are rejected. Unselected existing records remain at the destination. The UI requires a review acknowledgement and a count-based confirmation before applying the choices.
