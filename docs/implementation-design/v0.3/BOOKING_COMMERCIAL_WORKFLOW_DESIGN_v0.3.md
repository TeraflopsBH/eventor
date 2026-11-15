# Booking commercial workflow design v0.3

**Status:** implementation contract for the next venue-booking vertical slice  
**Branch:** `feat/booking-commercial-workflow` (stacked on PR #27)  
**Scope:** booking offers, customer decisions, approval policy and explicit booking confirmation

## 1. Scope and invariants

This workflow starts with an existing booking draft and one immutable draft revision. It is a venue-booking workflow and must not require an operational event, guest registry, invitations, RSVP, seating or attendance records.

The following are distinct business facts and must never be collapsed into one status:

1. A staff member prepared and issued commercial terms.
2. A customer accepted or rejected one exact issued offer revision.
3. The organization satisfied its approval policy for that exact revision.
4. An authorized staff member explicitly confirmed the booking.
5. The database successfully converted the exact draft revision's active holds into booking reservations after rechecking availability.

An offer acceptance is not a booking confirmation. An approval is not a booking confirmation. A successful advisory availability query is not a reservation.

All writes are tenant-scoped, permission-checked in database commands, idempotent and audited. Customer decisions use opaque, purpose-bound capabilities; raw tokens are returned only at issuance and only token hashes are stored. Issued offer terms and all decision/approval history are immutable. Revisions are successors, never in-place edits.

## 2. Aggregate and revision model

The existing `booking_drafts`, `booking_draft_revisions`, `booking_offers` and `booking_offer_revisions` tables remain canonical.

- One draft may have one offer aggregate with multiple offer revisions.
- Every offer revision pins exactly one immutable `draft_revision_id`.
- A new draft revision invalidates the ability to issue a new offer from an older draft revision; existing issued offers remain historical records and must be explicitly withdrawn/superseded where appropriate.
- A successor offer revision is created from the current draft revision. It snapshots every customer-visible commercial term, line, quantity, amount, tax basis, currency, selected price-list revision, cancellation-policy revision and validity deadline.
- An issued revision is immutable except for one terminal customer decision: accepted, rejected, expired or withdrawn. Superseding an offer is represented by a controlled lifecycle transition and an immutable audit/history record.
- A decision applies only to the exact offer revision named by the capability. A link for an earlier revision can never accept a successor revision.

## 3. Offer lifecycle

Staff create a prepared offer revision with an explicit price-list revision, cancellation-policy revision, currency, tax basis, validity deadline and structured adjustments. The server calculates totals from pinned price data and validated draft lines; clients cannot submit authoritative subtotal, tax or total values.

The offer preview is returned before issue. Issuance is a separate explicit command so staff can review the final snapshot. Issuance checks:
- the draft remains editable and the requested draft revision is still current;
- referenced price-list and cancellation-policy revisions belong to the same organization and are published/effective for the offer period;
- currency and tax basis agree with the selected price-list revision unless a documented override permission and reason are present;
- all line quantities and adjustments are valid and bounded;
- the validity deadline is in the future;
- required resource holds, if configured for this offer stage, have not expired;
- the actor has the appropriate booking-management permission.

Issuance creates a one-use or otherwise explicitly bounded `offer_accept` capability for that exact offer revision. Only the token hash is persisted. The notification/delivery integration must use the organization's configured SMTP transport; no provider is mandatory. If email delivery cannot be prepared or submitted, the offer remains issued and its delivery state is separately visible—mail failure must not rewrite the customer's decision state.

A later change to price, quantity, schedule, cancellation terms or any customer-visible term creates a successor offer revision. It never updates an issued revision.

## 4. Customer acceptance and rejection

Customer acceptance and rejection are separate public commands protected by an `offer_accept` capability and idempotency key. The capability is resolved and consumed atomically with the decision. The command verifies:
- token hash, action code, exact offer revision, expiry, revocation and remaining use count;
- offer revision is still issued and its validity deadline has not passed;
- offer has not already reached a terminal decision;
- no newer issued revision has superseded it;
- the request is not a conflicting replay.

Acceptance stores the optional customer acceptance name/note and server timestamp. Rejection stores a bounded reason/category and optional note. Both append actor-kind/external-capability audit events and immutable decision history. A replay with the same idempotency key and payload returns the original result; a different payload conflicts. Expiry is a deterministic state transition and must not be mistaken for rejection.

The existing capability schema's `offer_accept` action is retained. No customer account is required.

## 5. Approval policy

Approval requirements are organization-configured, versioned and published. The offer pins the exact policy revision used to evaluate it, plus the evaluated requirements snapshot. Editing or publishing a later policy must not change an already issued offer.

The policy engine supports explicit, auditable conditions such as:
- offer total at/above a configured amount;
- discount/adjustment above an absolute or percentage threshold;
- use of a non-standard cancellation term or commercial exception;
- a manually requested approval.

Each matching rule declares the number/type of approvals, required permission and whether the approver must differ from the offer creator. No GHB thresholds or commercial values are to be invented in code or migrations; they must be supplied by an authorized organization administrator before production use.

Approval decisions are append-only and tied to the exact offer revision. A decision records the approver membership, decision, reason and time. The database enforces active membership, organization context, relevant permission, rule satisfaction, no duplicate decision and separation-of-duties constraints. Rejection or return-for-changes prevents confirmation; changing the offer requires a successor revision and a fresh evaluation. Customer acceptance and approval may occur in either order, but confirmation requires both.

## 6. Explicit confirmation and final availability

Confirmation is a distinct staff command requiring:
- exact accepted offer revision and exact pinned draft revision;
- all required approval rules satisfied with no rejection/return-for-changes;
- active membership and `booking.confirm` permission at organization or booking scope as appropriate;
- valid customer acceptance capability/decision provenance;
- current draft and offer state, with no conflicting terminal transition;
- all requested spaces and resources represented by valid reservation holds, or a separately approved no-hold policy for a resource class;
- all holds still active at the time of confirmation.

The command creates the booking record, immutable confirmed commercial/price/cancellation snapshots, booking party contact snapshot(s), booking status history and audit event in one transaction. It then invokes the existing `eogp.confirm_booking_reservations(...)` command in that same transaction. That command expires stale holds and atomically converts live space/resource holds to booking reservations. Exclusion/capacity conflicts abort the entire transaction; no partially confirmed booking is allowed.

The command must not treat an advisory availability result as authoritative. The final reservation conversion is the serialization point. If any required hold is missing, expired or cannot be converted, confirmation fails with a conflict and leaves no booking record or partial reservation conversion.

After success, the source draft becomes confirmed and cannot be edited. Duplicate confirmation with the same idempotency key returns the same booking; a different request against an already confirmed draft returns the existing booking only when it names the exact same accepted offer revision, otherwise it conflicts.

## 7. Permissions and separation of duties

The implementation uses the existing permission catalogue as its starting point:
- `booking.manage`: create/prepare/revise/issue offers;
- `booking.approve`: decide approval requirements;
- `booking.confirm`: explicitly confirm an accepted and approved offer.

Permissions are evaluated against active organization membership and current, non-revoked, non-expired grants. Sensitive actions are audited. Customer capabilities authorize only their exact external action and never confer staff access.

Offer creators should not satisfy a rule requiring an independent approver. Confirmation is separately permission-gated; a policy may additionally require a confirming actor different from the offer creator/approver.

## 8. API/UI sequence

The canonical OpenAPI v0.3 contract already reserves:
- `POST /booking-draft-revisions/{revisionId}/offers`
- `GET /booking-offers/{offerId}`
- `POST /booking-offers/{offerId}/accept`
- `POST /booking-draft-revisions/{revisionId}/confirm`

Before implementation, verify whether a rejection operation and offer issue/revision operations are already represented elsewhere in the contract. Extend the existing contract rather than duplicating paths or operation IDs. Keep public customer routes narrowly scoped and separate from staff session authentication.

The staff UI will expose offer preparation/preview, explicit issue, approval queue/decision and explicit confirmation. It must show the customer decision, approval status, validity deadline, pinned draft revision and reservation outcome independently. The customer-facing offer page must show only the exact offer's permitted terms and actions.

## 9. Acceptance and regression tests

At minimum:
- cross-tenant offer, draft, policy and capability IDs are rejected;
- offer cannot be issued from a stale/non-current draft revision;
- published price/policy revisions are required and snapshots remain unchanged after later publication;
- client-supplied totals are ignored/rejected; calculation uses server-side pinned items and adjustments;
- issued terms cannot be updated/deleted; successor revision leaves old terms intact;
- expired, revoked, wrong-purpose, wrong-revision, exhausted and superseded capabilities cannot decide an offer;
- accept/reject race results in exactly one terminal decision;
- idempotent replay returns the same decision; changed payload conflicts;
- policy evaluation and approval counts are deterministic and pinned;
- creator cannot self-approve when separation of duties is required;
- approval for another offer revision does not satisfy this revision;
- rejected/returned approvals block confirmation;
- acceptance without required approval cannot confirm; approval without acceptance cannot confirm;
- confirmation without active space/resource holds fails atomically;
- concurrent resource demand cannot overbook during final confirmation;
- failed confirmation leaves no booking record, confirmed snapshot or partial reservation conversion;
- successful confirmation creates exactly one booking and converts every eligible hold once;
- retry after a committed confirmation returns the original booking;
- no event, guest, invitation or RSVP rows are required for a venue-only booking.

## 10. Configuration and production gates

GHB-specific pricing, tax treatment, cancellation wording, approval thresholds, approver roles, booking validity periods and inventory policies must be confirmed by GHB. The schema and policy engine support those settings, but migrations must not seed guessed commercial rules. Production offer issuance remains disabled until the organization has published the required price-list, cancellation-policy and approval-policy revisions and verified venue/resource inventory.
