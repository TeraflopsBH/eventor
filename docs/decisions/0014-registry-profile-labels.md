# ADR 0014 — Internal labels on persistent Registry profiles

- Status: accepted.
- Date: 2026-11-24.
- Related: #104 and the product owner's preview feedback requesting VIP and similar classifications.

Organizations can define reusable named Registry labels and assign several to an active persistent profile. Labels have stable UUIDs; users do not invent technical codes. Labels are internal Registry data, governed by Registry read/manage permissions. They appear in authorized Registry directory/profile reads and are not added to event or public guest projections. Event-specific guest categories remain separate.

Labels can be retired without deleting existing assignments or repurposing their identity. Retired labels cannot be newly assigned. Assignment changes require the current person revision and preserve an audit trail of label IDs. Runtime callers have no direct table access; tenant RLS, actor context and server authorization protect the command boundary.

A source profile with labels cannot currently merge. Staff must separately review its classifications; the existing merge command cannot silently hide, discard or combine these new linked facts. Destination classifications are preserved. Label transfer during a merge remains future reviewed resolution work.
