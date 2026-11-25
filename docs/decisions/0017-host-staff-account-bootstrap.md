# ADR 0017 — Host-only initial staff account provisioning

- Status: accepted.
- Date: 2026-11-25.
- Related: #104 and ADR 0015; later installer bootstrap under #108.

## Decision

Provide an explicit host-owner command for a new staff account before broader invitation/account administration is implemented. It accepts an email, display name, an operator reason and an optional active organization ID. The initial password comes only from hidden terminal entry or stdin, never a command argument or exported password variable. The built API's existing Argon2id dependency hashes it before storage. This tool requires a nonblank password of 12–1024 UTF-8 bytes; this is a host-bootstrap input boundary, not a change to existing account authentication.

A privileged migration connection selects `eventor_owner`. One transaction inserts the active account, optionally an active membership and an append-only host provisioning receipt. Existing case-insensitive email identities are refused; no upsert, password reset, account reactivation or privilege repair is attempted. An unavailable/inactive organization or audit failure rolls back the operation. The new account explicitly has no platform-admin flag, no email-verification assertion and no role grants. A membership alone does not authorize application data. Organization administrators assign permitted roles separately; platform authority requires the distinct host-admin grant command from ADR 0015.

Reuse the private `platform_admin_audit` host control-plane journal with action `staff_account_provisioned`, the affected account, optional selected organization, operator reason and the real `session_user` database principal. Do not fabricate a membership actor for a host operation. This journal already covers host provisioning of accounts' platform access and remains inaccessible to runtime/auth/worker table queries. No tenant API, new table, authorization grant or OpenAPI route is introduced.

The CLI prints only created identifiers and explicit false role/platform flags. Errors are sanitized so password hashes, database connection details and SQL parameter values are not emitted. Tests use synthetic disposable data. Operators must communicate initial credentials securely; the command does not send email or prove mailbox ownership.

## Limits

This is an initial host bootstrap and recovery-environment prerequisite, not a tenant invitation, password-change/reset, email-verification or full global account-management workflow. A global account without memberships cannot enter an ordinary workspace until explicitly provisioned. Existing users must be handled through separate reviewed administration; rerunning this command never overwrites them.
