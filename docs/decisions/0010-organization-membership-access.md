# ADR 0010 — Organization membership access

- Status is accepted.
- Date is 2026-11-23.
- Related work is [Issue #104](https://github.com/TeraflopsBH/eventor/issues/104).

## Decision

Organization managers can suspend and restore organization memberships through an audited, revision-checked command. The command supports active and suspended memberships. Existing invitation and revocation states retain their own workflows.

Suspension revokes all current sessions for the selected membership in that organization. Restoring access preserves the member's role grants and requires a fresh login and an active global user. Other memberships for the same user retain their sessions.

Administrative writes use the existing organization access lock. Suspending a member requires another active user with an active organization-wide organization.manage grant. This preserves an administrator who can restore access. The UI confirms session revocation before suspension.

## Verification

Synthetic tests cover tenant and actor boundaries, revisions, session revocation, restoration, retained role grants and preservation of an active administrator. Browser acceptance exercises the manager's confirmation and the resulting member state.
