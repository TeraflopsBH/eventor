# ADR 0019 — Reviewed Registry relationship transfer

- Status: accepted.
- Date: 2026-11-25.
- Related: #104, ADR 0009/0013/0018, Blueprint v1.2 §33.4.

## Decision

Extend supervised duplicate-profile merging to transfer non-conflicting active Registry relationships after an explicit `relationshipResolution=move_to_destination` acknowledgement. The operator needs the existing Registry merge and relationship-management permissions. Contact/reference/label choices retain their independent boundaries. No permission is implied by a relationship or by an event participation.

The comparison lists active source and destination links only when the operator has relationship-management authority and there are source links to transfer. A permission blocker exposes no relationship rows or source count. It shows related names, relationship kind and direction. Commit preserves each relationship ID, kind, directionality, creation time and original author. Directed incoming and outgoing endpoints retain their meaning; mutual endpoints are reordered to satisfy the existing canonical UUID invariant. Ended links remain attached to their original profiles as historical facts. Unrelated destination links are untouched.

A source-to-destination link would become a self-link and remains blocked. A transfer that would duplicate an existing active destination tuple is also blocked. Neither case silently ends, combines or prioritizes links; separate reviewed correction is required. Unsupported identifiers, incoming merge chains and open/overlapping event history keep their existing guards.

## Review, concurrency and audit

The actor-bound review fingerprints the active links of both profiles, including their IDs, endpoints, kind, direction and creation/end attribution, using a versioned epoch-based hash. Ending a link does not increment the profile revision, so parent revision checks alone are insufficient. Even ending the last source link invalidates a new review. A pre-migration review can still merge profiles without active source links; it cannot authorize their transfer.

Commit locks both profiles in stable UUID order and the affected active relationship rows in stable UUID order before recomputing evidence. Existing relationship creation locks its parents, while ending a link locks its row. The boundary therefore serializes against both operations. A stale review or new conflict refuses the whole statement. Concurrent multi-profile graph operations may require retry after PostgreSQL deadlock detection; no partial transfer may commit.

Migration 192 adds a private, forced-tenant-RLS, append-only transfer journal with original endpoint IDs and the expected transferred-state hash. It deliberately has no FK to a current relationship row, so missing rows are detected rather than reconstructed. The existing merge record retains the acting operator and the explicit relationship resolution. No public guest projection, event relationship, historical event snapshot or sensitive contact value changes. Renamed helpers are private and every compatibility overload has explicit ACLs.

## Restoration and limitations

Both strict and current-contact/reference restoration first require current relationship-management authority for journalled transfers. They lock and verify the transferred rows before any profile or linked-record restoration. Unchanged relationships return with their exact original endpoints and attribution. The correction preview shows them read-only; contact/reference selection does not discard them. Unrelated destination links stay in place.

A changed, ended or missing transferred link returns `MERGE_RELATIONSHIPS_CHANGED` before partial effects. Restoration never reopens a later ended link, overwrites changed relationship facts or recreates a removed row. A separate relationship-correction workflow is required for those cases. Cached API retries also recheck current relationship authority. Existing merges without relationship transfers retain their prior behavior. This extension does not complete the full linked-record conflict workflow or #104.
