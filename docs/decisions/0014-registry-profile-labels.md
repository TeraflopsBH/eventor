# ADR 0014 — Internal labels on persistent Registry profiles

- Status: accepted.
- Date: 2026-11-24.
- Related: #104 and the product owner's preview feedback requesting VIP and similar classifications.

Organizations can define reusable named Registry labels and assign several to an active persistent profile. Labels have stable UUIDs; users do not invent technical codes. Labels are internal Registry data, governed by Registry read/manage permissions. They appear in authorized Registry directory/profile reads and are not added to event or public guest projections. Event-specific guest categories remain separate.

Labels can be retired without deleting existing assignments or repurposing their identity. Retired labels cannot be newly assigned. Assignment changes require the current person revision and preserve an audit trail of label IDs. Runtime callers have no direct table access; tenant RLS, actor context and server authorization protect the command boundary.

The initial implementation blocked merging a source profile with labels. Staff must separately review its classifications; a merge must never silently hide, discard or combine these linked facts. Destination classifications are preserved. The reviewed, non-overlapping transfer extension is defined in [ADR 0018](0018-reviewed-registry-label-merges.md); overlapping and subsequently changed assignments retain explicit guards.

## Classification filters — 2026-11-25

Registry readers can list their organization's active and retired classification options, then filter the directory by one stable label ID. The filter intersects with the existing name and active/archived profile filters before pagination. Unknown or foreign label IDs return no matches without disclosing another organization's definitions. Retired assignments remain searchable.

CSV/XLSX exports use the applied directory filters and retain their separate export permission and row limit. Filtered reads/exports record the selected ID in internal audit evidence; contact details and unrelated private fields remain excluded. This does not assign classifications, change merge rules, add event categories or change public guest projections. Migration 193 adds a label-first assignment index and compatibility overloads for existing SQL callers.
