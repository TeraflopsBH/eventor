# Architectural decision status and supersession index

**Date:** 2026-11-27. All 25 decisions are accepted as design records. This index does not assert every decision is fully implemented. Actual implementation is determined by live code, contracts, migrations and verified tests. See [documentation authority](../DOCUMENTATION_AUTHORITY.md) and [Blueprint v1.3 guide](../blueprint/v1.3/README.md). Original ADR files are intentionally unchanged.

| ADR | Design status | Relationship / implementation caveat |
|---|---|---|
| [0001 — modular monolith](0001-modular-monolith.md) | Accepted | Modular monolith; no replacement recorded. |
| [0002 — self hosted deployment](0002-self-hosted-deployment.md) | Accepted | Self-hosted Linux; both native and Compose release deliverables, Docker not mandatory at runtime. |
| [0003 — human approved allocation](0003-human-approved-allocation.md) | Accepted | Human approval of allocation; no autonomous commit. |
| [0004 — optional event operations scope](0004-optional-event-operations-scope.md) | Accepted | Optional event capabilities; independent provider path. |
| [0005 — separate invitations rsvp attendance](0005-separate-invitations-rsvp-attendance.md) | Accepted | Separate invitation, RSVP and attendance facts. |
| [0006 — cross organization collaboration](0006-cross-organization-collaboration.md) | Accepted | Explicit cross-organization collaboration; see 0021, 0023, 0024. |
| [0007 — internationalization](0007-internationalization.md) | Accepted | Locale and language precedence; preserve approved fallback. |
| [0008 — modular staff frontend](0008-modular-staff-frontend.md) | Accepted | Modular staff frontend; preserve scoped navigation. |
| [0009 — guest registry merge](0009-guest-registry-merge.md) | Accepted | Reviewed Registry merges; see 0013, 0018, 0019. |
| [0010 — organization membership access](0010-organization-membership-access.md) | Accepted | Membership access; see 0015, 0020, 0025 for related boundaries. |
| [0011 — database uuid compatibility](0011-database-uuid-compatibility.md) | Accepted | Database UUID compatibility. |
| [0012 — reference encryption identity](0012-reference-encryption-identity.md) | Accepted | Reference encryption identity. |
| [0013 — reviewed merge restoration](0013-reviewed-merge-restoration.md) | Accepted | Reviewed merge restoration; complementary to 0009. |
| [0014 — registry profile labels](0014-registry-profile-labels.md) | Accepted | Registry profile labels; see 0018. |
| [0015 — email first login and platform administration](0015-email-first-login-and-platform-administration.md) | Accepted; partially superseded in future design | Current implemented platform-managed authority and email-first login. Future blanket non-platform grant provision partially superseded by 0025; other compatible provisions remain. |
| [0016 — event rsvp policy settings](0016-event-rsvp-policy-settings.md) | Accepted | Event RSVP policy settings. |
| [0017 — host staff account bootstrap](0017-host-staff-account-bootstrap.md) | Accepted | Host staff bootstrap; compatible with 0025 protected recovery. |
| [0018 — reviewed registry label merges](0018-reviewed-registry-label-merges.md) | Accepted | Reviewed Registry label merges. |
| [0019 — reviewed registry relationship merges](0019-reviewed-registry-relationship-merges.md) | Accepted | Reviewed Registry relationship merges. |
| [0020 — host existing staff membership](0020-host-existing-staff-membership.md) | Accepted | Host existing staff membership; independent grants retained under 0025. |
| [0021 — booking event association commands](0021-booking-event-association-commands.md) | Accepted | Booking/event association commands; related 0006, 0023, 0024. |
| [0022 — event disruption publication and acknowledgement](0022-event-disruption-publication-and-acknowledgement.md) | Accepted | Event disruption publication and acknowledgement; do not infer resolution from receipt. |
| [0023 — permissioned collaboration grant lifecycle](0023-permissioned-collaboration-grant-lifecycle.md) | Accepted | Permissioned collaboration grant lifecycle; related 0024. |
| [0024 — shared party names and reviewed grant acceptance](0024-shared-party-names-and-reviewed-grant-acceptance.md) | Accepted | Shared party names and reviewed grant acceptance; compatible with 0023. |
| [0025 — platform governance tenant authority](0025-platform-governance-tenant-authority.md) | Accepted successor; activation pending | Accepted future least-privilege governance; exact allowlist, effective-access inventory, owner/recovery policy, migration and activation at PAC M0/M1 remain separately reviewed. |

## Explicit transition — ADR 0015 → ADR 0025

Read both decisions. ADR 0025 is accepted and supersedes only the blanket managed non-platform permission provision of ADR 0015 as future design. Email-first authentication, actual actor, selected-tenant RLS, independent memberships, compatible host designation and workspace switching survive. Current deployed behavior is not changed by documentation: inventory effective direct and indirect access, approve exact allowlist and recovery, preserve independent roles, verify populated migration, revoke/re-evaluate affected sessions, and safely activate at PAC M0/M1. Until activation, do not pretend the new model is deployed or expand legacy grants. No other supersession inferred from a cross-reference. The 24 ADRs embedded in the approved Blueprint archive are the original pinned snapshot; ADR 0025 is a separately accepted companion, not an alteration of that snapshot.
