# ADR 0014 — Internal labels on persistent Registry profiles

- Status: accepted.
- Date: 2026-11-24.
- Related: #104 and the product owner's preview feedback requesting VIP and similar classifications.

Organizations can define reusable named Registry labels and assign several to an active persistent profile. Labels have stable UUIDs; users do not invent technical codes. Labels are internal Registry data, governed by Registry read/manage permissions. They appear in authorized Registry directory/profile reads and are not added to event or public guest projections. Event-specific guest categories remain separate.

Labels can be retired without deleting existing assignments or repurposing their identity. Retired labels cannot be newly assigned. Assignment changes require the current person revision and preserve an audit trail of label IDs. Runtime callers have no direct table access; tenant RLS, actor context and server authorization protect the command boundary.

The initial implementation blocked merging a source profile with labels. Staff must separately review its classifications; a merge must never silently hide, discard or combine these linked facts. Destination classifications are preserved. The reviewed, non-overlapping transfer extension is defined in [ADR 0018](0018-reviewed-registry-label-merges.md); overlapping and subsequently changed assignments retain explicit guards.
