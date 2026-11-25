# ADR 0020 — Host provisioning of an existing account's new membership

- Status: accepted.
- Date: 2026-11-25.
- Related: #104, ADR 0015/0017; installer bootstrap under #108.

## Decision

Provide a separate privileged host command to add an existing active staff account to an active organization. This completes the missing counterpart to initial account bootstrap without creating another identity or replacing credentials. The host operator specifies email, organization UUID and a reason. Email lookup is case-insensitive. The command creates exactly one active membership, with no role grants or platform authority. It is deliberately separate from an invitation or proof of mailbox ownership.

One owner-role transaction locks the active organization and account, refuses any existing organization/account membership, inserts the new membership and records `staff_membership_provisioned` in the existing private append-only host audit. The journal identifies the account, selected organization, operator reason and real `session_user`; the organization/account unique constraint identifies the membership. No tenant member is fabricated as the host actor. Concurrent attempts serialize on the account and can produce only one membership/audit receipt. Audit failure rolls back the insert.

Existing active, invited, suspended and revoked memberships are all refused. The command does not restore access, replace identity, change email/password/verification/platform flags, assign roles, revoke sessions or change other workspaces. Existing membership correction remains a separate authorized workflow. Normal authentication discovers the new named workspace; selected-tenant permissions still control every operation. A membership alone grants no Registry or event-data permission.

## Boundary and limitations

The built API exports the host implementation for the command and tests, not an HTTP route. The shell/Node entry points require a privileged migration connection that can select `eventor_owner`; runtime cannot execute the host operation. CLI output contains identifiers and explicit unchanged-account/no-role-grant flags. Errors omit raw SQL, connection strings and private database details. No password input is accepted.

No migration, new table, API contract or mandatory dependency is needed. Non-active accounts or organizations are refused rather than repaired. Existing accounts without usable credentials still need a separate credential workflow. This is a host onboarding tool, not self-registration, tenant invitations, password reset or a complete global account console.
