# ADR 0011 — Database UUID compatibility

- Status is accepted.
- Date is 2026-11-23.

## Decision

UUID identifiers use canonical hexadecimal text with the 8-4-4-4-12 grouping accepted by the existing PostgreSQL schema. API, client input and cryptographic tenant-context validation accept persisted identifiers whose version or variant bits differ from newly generated version-4 UUIDs.

Authentication continues to derive the principal from an active database session, user, membership and organization. Permission checks continue to bind every operation to that principal. Contact and delivery encryption continue to authenticate the complete normalized organization identifier.

## Evidence

A synthetic provider account could log in successfully but its next authenticated request returned 401 because its existing database UUIDs used zero version and variant bits. Tests cover authenticated route access for those identifiers, malformed-path rejection, organization scope and cross-tenant encryption failure.
