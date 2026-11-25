# ADR 0018 — Reviewed Registry classification transfer

- Status: accepted.
- Date: 2026-11-25.
- Related: #104, ADR 0009/0013/0014.

## Decision

Extend the existing supervised identity merge to carry non-overlapping Registry label assignments from source to destination, only after a separate explicit `move_to_destination` choice. Registry merge authority already requires Registry management, which is also the label-management boundary. Contact/reference transfers retain their separate field permissions and acknowledgements. Older merge overloads delegate to the new boundary with no label choice and therefore cannot silently move classifications.

The review shows both profiles' labels, including retirement state. The source assignments move unchanged: stable label IDs, original author membership and original assignment time are preserved. A retired assignment is historical classification evidence being reassigned with the duplicate identity, rather than a new classification selected through the ordinary editor. Existing destination assignments remain untouched. Overlapping labels and a combined total above the existing 100-assignment profile limit remain blocked; no automatic union, deletion or classification priority is invented.

Stable parent locks serialize assignment edits. Definition locks prevent concurrent retirement from changing the reviewed configuration during commit. The actor-bound review includes a hash of both assignment sets and definition-retirement timestamps; profile revisions and all existing contact/reference/history review checks still apply. The canonical v1 hash uses explicit fields and epoch timestamps, independent of session time-zone formatting; future formats must not reinterpret existing journal evidence. Destination revisions invalidate stale label editors. Existing event identity snapshots and public guest projections are unchanged.

An append-only, tenant-RLS transfer journal records merge/label references and the transferred assignment-state hash, without copying label names or reconstructable deleted assignments. The merge record identifies the actual operator and its resolution. The journal deliberately does not reference a current assignment row, so later authorized removal remains possible. Runtime/auth/worker cannot query or mutate this journal directly; private implementation helpers are not executable by application roles.

## Restoration

Both ordinary unchanged-record restoration and the reviewed current-contact/reference correction path first validate the transferred labels. Unchanged assignments return to the reactivated source with their original metadata; unrelated destination labels stay in place. The correction preview lists the returning classifications read-only, separately from selectable contacts/references. Confirmation explains this automatic return. Contact/reference edits can be reviewed through ADR 0013 while the labels remain unchanged.

An edited, removed or removed-and-re-added transferred assignment produces `MERGE_LABELS_CHANGED` before any profile/contact/reference state is restored. A later label-definition retirement alone does not discard historical assignments or prevent their return. A separate label correction workflow is required for changed assignments; no journal rewrite, metadata reset or ghost assignment recreation is allowed. All permission checks precede private-state disclosure, including idempotent replay.

## Migration and limits

Migration 191 adds the private journal and composes the existing merge/restoration implementations through guarded wrappers. It adds no backfill and changes no existing classifications or completed merge records. Existing merges without label transfers continue through their previous restoration semantics. Every compatibility overload has explicit grants; renamed implementation helpers are private. This does not complete active relationships, unsupported identifiers, overlapping event history or overlapping/edited classification correction under #104.
