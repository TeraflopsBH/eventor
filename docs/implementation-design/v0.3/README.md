# Implementation Design v0.3 — RSVP and invitation addendum

**Status:** proposed detailed domain/API design; schema migration and implementation remain open.

This directory contains the successor design addendum for invitation and RSVP behavior. It is intentionally separate from the historical v0.2 design snapshot.

## Contents

- [RSVP and Invitation Design v0.3](RSVP_AND_INVITATION_DESIGN_v0.3.md) — state separation, event policy, secure links, guest self-service, staff capture, proposed data model, API routes, access control, operating scope and acceptance scenarios.

## Parent documents and decisions

- [Technical Blueprint v1.2](../../blueprint/v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md)
- [Implementation Design v0.2](../v0.2/Event_Operations_Implementation_Design_v0.2.md) — historical design snapshot
- [Operating Model](../../OPERATING_MODEL.md)
- [ADR 0004: Optional event operations scope](../../decisions/0004-optional-event-operations-scope.md)
- [ADR 0005: Separate invitations, RSVP and attendance](../../decisions/0005-separate-invitations-rsvp-attendance.md)

## Implementation handoff

The next implementation work is tracked in [Issue #10](https://github.com/TeraflopsBH/eventor/issues/10). Do not alter the v0.2 SQL/OpenAPI snapshots to implement this design. The schema migration and OpenAPI contract must be issued as reviewed successor artifacts and validated against PostgreSQL/OpenAPI tooling.
