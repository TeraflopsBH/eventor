# ADR 0012 — Source-reference encryption identity during profile merges

- Status is accepted.
- Date is 2026-11-24.
- Related: [ADR 0009](0009-guest-registry-merge.md), [#104](https://github.com/TeraflopsBH/eventor/issues/104).

## Context

Source-reference keys already include organization, person ID and source system. Reassigning an identifier's logical owner without preserving its encryption identity makes the existing ciphertext unreadable. Reference fingerprints used for exact import matching are organization/source/value scoped and must remain stable.

## Decision

Keep the existing key derivation and encrypted contents. `person_identifiers.encryption_person_id` records the identity used for encryption, with a same-organization person foreign key. A trigger sets it to the current person on insertion or explicit ciphertext replacement. An ownership-only merge/restoration leaves it unchanged. The authorized service projection supplies this private binding to the API for decryption; the HTTP response continues to expose only reference ID, source and value.

Migration 000183 backfills the binding from existing ownership without changing ciphertext. The migration runner holds an atomic transaction and table lock. Owner-only RLS bypass is limited to that backfill, and forced RLS is restored before commit. A populated two-tenant upgrade rehearsal verifies both bindings, unchanged values, tenant isolation and the same-organization foreign key.

A reviewer with Registry merge and source-reference management authority may explicitly transfer supported external source references. Contact transfer requires its own authority and confirmation when contacts are also present. The review binds both reference sets; stable parent locks serialize changes. Both profiles' revision semantics continue to invalidate stale reference editors. Older merge signatures cannot bypass the new resolution requirement.

The append-only `person_merge_reference_transfers` journal stores only references and canonical v1 SHA-256 state evidence. Its hash uses explicit fields, hexadecimal bytes and epoch time, so session timezone and bytea formatting cannot change the result. The journal intentionally has no foreign key to the current identifier: an authorized later reference removal remains possible. Removed encrypted values are not copied into the journal or recreated during restoration.

Restoration returns unchanged references with their original IDs, values and encryption bindings. An edited or missing reference produces `MERGE_REFERENCES_CHANGED` before profiles or contacts partially restore. A separate correction review is required for that case; see [ADR 0013](0013-reviewed-merge-restoration.md). Unsupported identifier kinds, active relationships and open/overlapping event history retain their existing blockers. This decision does not complete the broader conflict/correction workflow under #104.

## Verification

Tests cover exact import matching before/after transfer and restoration, reference-only authority, combined contact/reference choices, older-signature refusal, stale reviews, revoked permissions on retries, canonical state hashing, changed/removed reference guards and private helper/journal access. API regression tests decrypt a transferred value with its original person binding, reject an incorrect binding and ensure ciphertext/binding metadata never appears in the HTTP projection.
