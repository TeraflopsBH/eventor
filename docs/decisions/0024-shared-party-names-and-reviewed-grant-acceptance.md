# ADR 0024 — Shared party names and reviewed grant acceptance

- Status: accepted.
- Date: 2026-11-25.
- Related: #104/#112, ADR 0006/0023.

## Context

Partner-access controls need recognizable party names and a complete grant review. Looking up another tenant's organization row to display a name would widen the tenant boundary. A user must also avoid accepting a different scope/configuration after its review changes.

## Decision

Each party publishes its own existing organization name through the grant lifecycle. Proposal captures the grantor's name in the grantor context; valid acceptance captures the recipient's name in its context. Names remain immutable on the grant despite later organization renames or revocation. Migration 199 leaves historical unknown names null without backfill or invented original names. No organization directory policy, cross-tenant context switch or source-record permission is added. Legacy/unaccepted counterparts use a reference fallback.

Detailed review returns a SHA-256 fingerprint of party identities, scope, purpose, allowed actions, shared configuration and validity. Lifecycle/actor/timestamp metadata is excluded so genuine acceptance retries remain stable. Timestamp inputs use epoch values to avoid session-time-zone differences. Interactive acceptance supplies that fingerprint. The server locks/rechecks the grant, compares current meaning and accepts atomically; stale reviews are refused, including cached replies. The fingerprint is concurrency evidence, not a credential or authorization grant. Existing programmatic acceptance without a fingerprint and its original idempotency representation remain compatible.

`/me/workspaces` includes an organization-scoped collaboration-management navigation hint. Settings displays Partner access only with that hint. Grant metadata supplies current party/state/window action hints; each command independently rechecks authority. Staff review scope, configured actions and deliberately shared configuration before native confirmation. Revocation requires a bounded reason and confirmation. Conflicts clear the stale review and require a fresh read; authorization failure clears private list/detail state. Dates use the selected language, and grant names describe the names shared at proposal/acceptance rather than an unverified current directory entry.

## Consequences and limits

This adds no provider booking, event, guest or commercial data to shared access. Accepting a grant does not create broad tenant membership or perform downstream booking/event decisions. New proposal creation/discovery and partner booking/notice workflows remain separate. Host maintenance can still correct source configuration; interactive retries will not silently approve changed meaning. Any future runtime grant-revision workflow must preserve explicit versioned meaning and downstream authority.

Populated 198-to-199 rehearsal verifies unchanged legacy grant facts and null uncaptured names. SQL/API and real PostgreSQL tests cover immutable names, unchanged directory isolation, stale/renewed reviews, cached retries and timezone-independent fingerprints. Chromium/Firefox cover names, escaped configuration, cancelled/confirmed actions, stale-review recovery, unaccepted revocation, source-data denial, Bosnian dates, mobile containment and permission cleanup. Live SMTP/HTTPS and production installation acceptance remain separate.
