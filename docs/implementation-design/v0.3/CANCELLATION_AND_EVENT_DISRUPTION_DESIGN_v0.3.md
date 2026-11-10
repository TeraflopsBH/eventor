# Cancellation and event disruption design v0.3

**Status:** proposed detailed domain/workflow design for review  
**Date:** 2026-11-10  
**Related:** ADR 0004, ADR 0005, ADR 0006; Issues #10, #13, #17 and #21; proposed MVP/roles PR #20

This document defines how Eventor should handle booking cancellation, event cancellation and postponement. It extends the accepted operating and ownership model without changing the historical v0.2 schema or OpenAPI snapshot.

> A booking cancellation and an event cancellation are separate business decisions. Either may trigger a request or follow-up involving the other, but neither silently performs the other.

Both the venue provider and organizer/customer need a legitimate, auditable way to initiate the relevant process. Authority to initiate is not automatically authority to approve every consequence, access the other party's records, waive contractual terms or send messages on the other party's behalf.

---

## 1. Goals and non-goals

### Goals

- Allow a booking customer/organizer to request cancellation of a confirmed booking without tenant membership or a full Eventor account.
- Allow the venue provider to initiate cancellation when it cannot provide the confirmed venue or contracted venue-side service.
- Allow the event owner/organizer to cancel or postpone an operational event, including after invitations have been delivered and RSVP responses recorded.
- Keep booking, event, invitation, RSVP, participation, attendance, notification and financial consequences distinct.
- Notify appropriate booking contacts, event invitees and explicitly assigned collaborators.
- Provide audience selection and a reviewable notification preview before an event cancellation is committed, except for explicitly configured emergency execution.
- Preserve original bookings, schedules, invitations, responses, messages and decisions as immutable history.
- Maintain cross-organization ownership and least-privilege access under ADR 0006.
- Make commands reliable under retries, concurrency, partial notification failure and service interruption.

### Non-goals

This design does not establish GHB's actual cancellation periods, penalties, deposit/refund policy, exceptional circumstances, force-majeure terms or legal obligations. Those require confirmation by GHB and the relevant contracting parties.

It does not introduce a payment gateway, automatic bank transfer or automatic refund execution. Eventor can calculate and record configured commercial consequences and follow-up obligations; payment/refund execution remains a separate integration or manually verified process.

It does not allow a venue provider to inspect an organizer's guest list merely because the provider owns the venue booking.

Cancellation is never deletion, and a guest RSVP decline is never an event cancellation.

---

## 2. Domain separation

| Concept | Meaning | Owner by default |
|---|---|---|
| Booking | Commercial/resource agreement for venue and approved services/time blocks | Venue provider |
| Booking cancellation request | A party's request to end a booking, awaiting any required decision | Booking workflow |
| Booking cancellation | Effective termination of the booking/reservation under configured authority and terms | Venue provider's booking record |
| Operational event | Organizer's actual programme/occasion and sessions/capabilities | Event organizer |
| Event disruption | Notice that a dependency (for example, the booked venue) is unavailable or materially changed | Affected event workspace; source retained |
| Event cancellation | Organizer's decision that the event will not take place | Event organizer |
| Postponement/reschedule | Change to event date/time/location, with explicit treatment of invitations and responses | Event organizer; linked booking changes are separate |
| Cancellation notification campaign | Purpose-specific message batch with a fixed audience and tracked delivery | Party responsible for that audience |
| RSVP response | Guest's answer in the context of an invitation/schedule | Event organizer |
| Attendance | Whether the person physically attended | Event operator/check-in workflow |

A booking can exist without an operational event. A confirmed booking does not create guest records, invitations or RSVP records. An operational event may exist independently of an Eventor-managed venue booking.

A single event may depend on multiple bookings/resources. A single booking may be associated with an event with multiple sessions. Link cardinality and ownership must not be collapsed into a single booking/event status.

---

## 3. Initiators, authority and cross-organization boundaries

### 3.1 Who may initiate

| Action | Initiator | Decision/owner |
|---|---|---|
| Request cancellation of confirmed booking | Booking customer, authorised organizer contact or contracting-party representative | Venue provider under booking policy; may be automatic where confirmed policy explicitly allows |
| Venue-initiated booking cancellation | Authorised venue-provider user | Venue approval authority; emergency authority may be configured |
| Event cancellation | Event owner or user with event-cancellation permission | Event organizer's approval policy |
| Event postponement/reschedule | Event owner or user with event-schedule permission | Event organizer's approval policy |
| Guest cancellation notice | Organizer or explicitly delegated communications operator | Party accountable for guest communications |
| Venue disruption notice | Venue provider/booking workflow | Sent to booking contacts and event liaison |

Both sides have a supported route into the process, but the target record matters:

- A booking customer may request that the booking be cancelled.
- The venue provider may initiate cancellation of its booking commitment.
- The event organizer may cancel or postpone its operational event.
- A venue provider may perform guest communications only when explicitly assigned and granted that task.

An organization may occupy multiple roles. Eventor still checks the specific scope and permission; permission in one role does not imply permission in another.

### 3.2 External booking customer without an account

A booking customer must not need tenant membership merely to submit a cancellation request.

A secure external action link may be issued to an authorised booking contact. It must be opaque, high entropy, purpose-limited, bound to one booking/action, stored as a one-way token hash, revocable, replaceable and time-limited. GET/preview must not submit a cancellation. The design must protect against referrer leakage, analytics capture, logs, token enumeration and brute force.

The link normally creates a **cancellation request**, not an unconditional cancellation. A policy pinned to the confirmed booking may permit automatic acceptance under defined circumstances, but that behavior must be configured and clear to the requester.

Distinguish requester, booking contact, contracting party and actual event organizer. A contact who can receive booking notices is not automatically authorised to waive a contract or request cancellation. Authorised cancellation contacts/roles should be captured explicitly during booking confirmation.

If the requester's authority is uncertain, keep the request pending for venue review; do not resolve ambiguity by silently treating the requester as the contracting party.

### 3.3 Collaboration boundaries

Under ADR 0006:

- Venue provider owns the booking, commercial record, venue spaces/resources and venue-side fulfilment.
- Organizer owns the operational event, guest registry, invitations, RSVP, seating decisions and attendance.
- Booking/customer identity does not create tenant membership.
- Collaboration is an explicit grant with named scope, purpose, data projection and validity.

Venue booking cancellation may create an event-facing **venue disruption notice** with only necessary facts: affected booking reference, space, time blocks, disruption category, effective time and venue contact. It must not include attendee names, guest contact details, individual RSVP data or organizer-only notes unless a separate grant permits that data.

If the venue is contracted to handle registration or guest communications, an explicit task assignment/grant may expose the minimum guest projection and permitted communication action. Revoking the grant blocks future access/actions but does not erase history.


### 3.4 Parties on separate Eventor deployments or outside Eventor

The internal booking-event association and collaboration grant described above apply when both organizations operate within the same Eventor deployment and have an approved collaboration relationship.

If the organizer operates a separate Eventor deployment or does not use Eventor:

- The venue provider still manages and cancels its own booking.
- Eventor sends the venue-disruption/cancellation notice to the authorised booking contact using the configured booking communication channel.
- The message may include a secure, purpose-limited response/reference link for the booking correspondence, but it must not imply that the venue provider can access or update the organizer's event workspace.
- The organizer handles event cancellation, postponement and guest notifications in its own system/process.
- Eventor records the outgoing notice, recipient, delivery result and any response received through the booking channel. It must not fabricate an internal event record or guest campaign.
- Any later shared operation requires an explicit supported integration or collaboration setup; it is not inferred from the booking.

This distinction prevents a deployment boundary from becoming an accidental data-sharing boundary. A booking communication can reach the organizer without granting the venue provider access to the organizer's operational records.

---

## 4. Booking cancellation

### 4.1 Confirmed-booking policy snapshot

The confirmed booking must pin the applicable cancellation-policy revision. This is versioned organization-owned configuration, not a hardcoded assumption about GHB.

It may define:

- Who may submit a request and which contacts are authorised.
- Whether customer cancellation is request-only, approval-required or self-service.
- Approval roles and thresholds.
- Notice periods and time-based cancellation charges.
- Deposit, credit, refund or outstanding-balance treatment.
- Whether venue-initiated cancellation needs a second approver and any emergency override.
- Required reason categories and supporting-document rules.
- Booking contacts/contracting parties to notify.
- Venue follow-up tasks and resource-release behavior.
- Whether amendments/rescheduling can be offered instead.

The policy revision and material terms presented to the customer must be retained with the confirmed booking. Editing current policy must not rewrite the terms of an existing booking. Legally required treatment must be validated separately.

### 4.2 Customer/organizer-initiated cancellation

1. The customer follows an authenticated staff route or secure external booking action link.
2. The requester identifies the booking and submits a cancellation request, reason category and optional explanation.
3. Eventor verifies the requester is authorised for this action.
4. Eventor evaluates the policy revision pinned to the booking.
5. If policy permits immediate self-service cancellation, the effective cancellation command is committed. Otherwise, the request enters the venue review queue.
6. The venue may approve, reject or request clarification. Decisions require an authorised actor and a recorded reason as required by policy.
7. On approval, Eventor applies cancellation effects exactly once and notifies configured booking contacts.
8. The customer sees the request/decision and a non-sensitive summary of commercial consequences. Internal notes remain private.

A rejected or withdrawn request does not release confirmed resources or mark the booking cancelled. It remains in history.

### 4.3 Venue-provider-initiated cancellation

1. An authorised venue user selects the confirmed booking and initiates venue cancellation.
2. They select a reason category (for example, venue unavailability, facility issue, safety/operational restriction, service inability or administrative correction) and provide the required explanation.
3. Policy checks authority and whether another approver is required. An emergency route may be configured with mandatory after-the-fact review.
4. Eventor previews affected spaces, setup/rehearsal/event/teardown blocks, equipment/personnel reservations, linked event references and booking contacts.
5. When authorised, the system commits booking cancellation and resource effects atomically.
6. It notifies the booking requester, authorised organizer contact and contracting party as configured.
7. If an operational event is linked, it creates a venue-disruption notice for the organizer. It does **not** cancel the event or send guest notifications unless the organizer explicitly delegated that task and data scope.

A technical administrator is not automatically a business approver.

### 4.4 Effective cancellation and resource release

Request submission is not effective cancellation.

On effective booking cancellation, one database transaction should:

- Change the booking's authoritative lifecycle projection to cancelled.
- Append the cancellation decision/effect record and audit event.
- Release future confirmed space/time-block reservations and discrete resource reservations.
- Cancel or close future venue-side preparation/fulfilment tasks as appropriate, retaining history and work already performed.
- Resolve or expire related temporary holds.
- Create notification/outbox messages for required booking contacts.
- Emit a booking-cancelled domain event for downstream consumers.

The database reservation model remains authoritative. A notification worker must never release resources.

Do not release a reservation merely because a customer submitted a request. While approval is pending, the booking remains reserved unless an explicit temporary-hold rule says otherwise.

Cancellation after the reserved period has begun or after fulfilment/completion requires a correction/exception path; do not rewrite delivered services or actual usage as if they never happened.

### 4.5 Commercial consequences

At cancellation, preserve:

- Policy revision and applicable terms snapshot.
- Initiating party, requester/actor, approver and timestamps.
- Reason code and restricted explanation.
- Original confirmed amount and deposit/payment references, where they exist.
- Calculated cancellation fee/retention, outstanding balance, credit or refund obligation, with rule/calculation snapshot.
- Consequence status (pending review, approved, due, manually settled, refunded/credited or disputed).
- Manual follow-up task and evidence/reference.

The system must not presume a refund is always due or that cancellation means no refund. Apply only the policy and approved commercial data attached to that booking. Actual money movement is out of scope unless separately designed.

---

## 5. Event cancellation

### 5.1 Initiation and impact preview

The event owner or authorised event operator selects **Cancel event**.

Before confirmation, Eventor presents:

- Event name, date/time/timezone, venue and affected sessions.
- Event owner and delegated task owners.
- Counts of invitations issued, active invitations and delivery attempts by status.
- RSVP counts by accepted, tentative, declined and unanswered; counts only, not unnecessary personal details.
- Pending invitations, scheduled reminders and queued guest communications to be suppressed.
- Assigned event tasks, external prerequisites, allocations, seating/space snapshot and admission readiness where enabled.
- Linked venue bookings and any separate booking-cancellation requirement.
- Party accountable for guest notices.
- Candidate notification audiences and delivery channels.
- Actions requiring separate approval or booking decisions.

The operator chooses a cancellation reason category and explanation. The public-facing message is prepared separately from the internal reason. Internal details must not automatically be copied into guest communications.

### 5.2 Confirmed event cancellation

Cancellation may require approval according to the event owner's configuration. A small event may allow the event owner to execute immediately; a high-impact event may require a second approver.

On confirmation, Eventor should atomically:

- Mark the operational event cancelled and record an immutable decision.
- Mark affected sessions/capabilities cancelled or no longer operational without deleting them.
- Prevent new invitations, RSVP submissions, event reminders, seating commits, admission credential issuance and check-in operations for the cancelled event.
- Suppress queued but unsent invitations, reminders and ordinary future event communications.
- Revoke admission credentials or disable validation for cancelled sessions according to the credential/session model.
- Retain issued invitations, link lifecycle and guest response history.
- Close, cancel or reassign event tasks/prerequisites according to responsibility and status, retaining completed work and references.
- Create the chosen cancellation campaign with a fixed recipient snapshot.
- Emit event-cancelled and outbox records for downstream work.

The database transaction must not wait for email/SMS provider delivery. If notification service is unavailable, the event remains cancelled and the campaign stays queued/retryable with visible status.

### 5.3 Existing invitations and RSVP

The existing RSVP design remains authoritative:

- Accepted, declined and tentative remain the guest's historical answers.
- A guest who accepted does not become declined because the event was cancelled.
- A guest with no response remains unanswered.
- Invitation issuance/delivery state is not overwritten to imply an invitation was never sent.
- Attendance remains separate. Cancellation before the event must not manufacture attendance records.
- After event cancellation, old invitation links must not accept new RSVP submissions. A guest opening an otherwise valid link sees a safe, explicit cancellation notice rather than a generic server error. It must not expose other guests or internal cancellation notes.
- New invitation sends and ordinary RSVP reminders are suppressed. Suppression is recorded, not silently deleted.

The event's current lifecycle state is authoritative for guest-facing actions. A cancellation message is not an RSVP response.

### 5.4 Who sends guest notices

The organizer is accountable for guest communications by default.

If the venue provider has explicitly been assigned and granted a guest-communications task, an authorised venue operator may perform it using the minimum permitted guest projection. The organizer remains event/data owner unless an explicit ownership arrangement says otherwise.

For venue-initiated booking cancellation, the normal path is:

1. Venue provider informs booking contacts and creates a venue-disruption notice.
2. Organizer receives the notice and decides whether to relocate, reschedule or cancel.
3. If the organizer cancels, the organizer's workflow creates the guest campaign.
4. If GHB is contracted to execute guest communications, Eventor assigns the campaign to the delegated operator and permits only the required data/actions.

A venue must not notify guests merely because it cancelled its booking.

---

## 6. Cancellation notification campaigns

A cancellation notice is its own message purpose/campaign. It is not an invitation, invitation resend, RSVP reminder or RSVP answer.

### 6.1 Audience choices

| Audience | Recipients |
|---|---|
| RSVP accepted or tentative | Guests whose latest answer for the affected schedule is accepted or tentative |
| All active invitees | Guests with an active invitation, including no-response guests; declined answers are included if the invitation remains active |
| All previously invited recipients | Anyone issued/sent an invitation for the affected event, including later revoked/withdrawn invitations and declined guests; explicit broader choice |
| Custom selection | Explicitly selected eligible recipients, subject to permissions and policy |

**Recommended default: all active invitees.** Someone who has not answered may still be planning to attend. A declined guest may also benefit from notice. The interface must explain inclusion rules.

The choice to contact all previously invited recipients should be explicit and subject to retention/contact policy. Do not infer this audience only from the current guest table; use invitation/delivery history and the configured audience semantics.

The preview shows recipient counts by relevant status and allows authorised exclusions where policy permits. Exclusions and actor/reason are retained. Do not put addresses or phone numbers in ordinary audit logs.

### 6.2 Recipient snapshot and delivery tracking

At campaign confirmation, resolve and persist the recipient set and the reason each recipient qualified. Retries must use this fixed audience even if guest/invitation state later changes.

Each recipient/delivery record should capture campaign/event, guest reference, restricted contact-point snapshot as needed, audience qualification reason, channel, template revision/locale, queue/attempt/provider/delivery/failure timestamps, safe provider reference, retry/suppression outcome and operator intervention.

Keep campaign, recipient snapshot and per-channel delivery attempts distinct. A generic delivery row must not be repurposed as an invitation or cancellation record.

### 6.3 Content and reliability

Templates must be separate from invitation templates and include a clear cancellation statement, event title and original schedule/location as appropriate, a concise optional guest-safe explanation, whether another announcement will follow, and an approved organizer contact/help channel. Do not include internal reasons, confidential booking disputes, payment details or other guest information.

Queue messages through the worker/outbox architecture. Use idempotency keys to avoid duplicate messages on retry. Track each recipient; aggregate campaign status is only a projection. Retry transient errors, expose permanent failures to authorised operators and allow manual retry/follow-up. Delivery success/failure never changes the event's cancelled state or a guest's RSVP answer. Do not claim everyone was informed merely because a campaign was created or queued.

Initially use the configured email provider abstraction. SMS or other channels can be added later without changing the domain semantics.

---

## 7. Postponement and rescheduling

Postponement is not cancellation. It is a schedule change with its own guest and booking consequences.

Support at least:

1. **Postponed, replacement date unknown.** Mark the event postponed, pause normal RSVP submissions/reminders and send a postponement notice. When a new date is established, publish a new schedule revision and decide whether guests must reconfirm.
2. **Rescheduled to a known date/time/location.** Publish a new schedule revision. Preserve the old schedule; do not rewrite history as if the original date never existed.

### 7.1 RSVP treatment

An RSVP answer is meaningful in the context of the schedule/invitation the guest saw. Preserve that context.

The reschedule policy may carry forward existing answers, require reconfirmation from accepted/tentative guests, require a fresh answer from all active invitees, or issue updated invitations to a selected audience.

**Recommended default:** a material change to date, time or venue requires reconfirmation from accepted/tentative guests. The previous answer remains in history as the answer to the old schedule; a separate reconfirmation-required/response-validity projection indicates it is not yet a commitment to the new schedule. Do not rewrite the old answer to pending or declined.

A minor correction may not need reconfirmation. Event policy must define material schedule fields and version that decision.

If a new invitation/link revision is needed, keep invitation history traceable. Reissuing must not erase the previous response.

### 7.2 Linked booking changes

If rescheduling changes a GHB booking's date, space, duration, setup, rehearsal or teardown, the organizer requests a booking amendment/change order under the booking policy. Availability is revalidated and the provider approves where configured.

Do not release the original confirmed reservation until the replacement is validated and committed, unless the parties explicitly choose to release it first. Prefer an atomic amendment where new reservations can be secured before old ones are released.

If an event is postponed indefinitely, organizer and venue must separately agree what happens to the existing booking. Avoid a permanent, ambiguous venue hold without an explicit booking decision or review task.

---

## 8. Cross-organization scenarios

### Organizer cancels after invitations were sent

Organizer owns event and guest records, confirms event cancellation, blocks further RSVP/invitation activity, suppresses reminders, chooses an audience and creates a tracked campaign. Historical RSVP answers remain unchanged. Booking cancellation is a separate linked request if organizer wants to release the venue.

### Venue provider can no longer provide the hall

Venue provider initiates booking cancellation under its authority. Venue reservations and venue-side tasks are resolved. Booking contacts are notified. Organizer receives a scoped disruption notice and chooses alternative venue, reschedule or event cancellation. Venue staff do not see the guest list or send guest messages unless granted that task.

### Organizer gets cold feet and cancels the booking

External booking contact submits a cancellation request through a secure link, or an authorised Eventor user submits it. Venue applies the pinned policy and approves/rejects or configured self-service executes. Commercial consequence is recorded; resources are released only when effective. The contact is notified. A linked event can continue elsewhere; it is not automatically cancelled.

### Venue is contracted to manage guest communications

Event responsibility assignment names the provider as task performer and defines permitted audience/data projection. Organizer retains event ownership. Venue operator can execute only the granted communication task; grant revocation blocks future operations but preserves history.

### Event uses several bookings/resources

One event cancellation may affect multiple independent bookings. Present all linked dependencies, but evaluate each booking against its own policy and authority. Event cancellation must not silently cancel several contracts. Organizer can initiate coordinated requests and track each outcome.

### Parties are on separate deployments

If the organizer uses a separate Eventor deployment or no Eventor at all, GHB sends a booking disruption notice to the authorised booking contacts. The organizer manages its own event and guest communications externally; no guest list is imported or exposed to GHB. See Section 3.4.

---

## 9. Proposed state and data model concepts

These are domain concepts, not final SQL migrations. Exact tables, keys, indexes, retention, RLS and constraints belong in the successor schema/database integrity work.

### 9.1 Booking cancellation

Keep immutable request/decision history separate from the booking's current lifecycle projection.

Conceptual attributes: booking and policy revision; initiator party/type and authenticated actor; request channel; reason code and restricted explanation; request status (submitted, under review, approved, rejected, withdrawn, expired); decision actor/time/reason; effective cancellation time; commercial-consequence snapshot; follow-up status; idempotency/correlation reference.

The booking becomes cancelled only when the effective cancellation command commits. Multiple rejected/withdrawn requests may exist, but only one effective cancellation unless a separate controlled correction/reinstatement process is designed.

### 9.2 Venue disruption notice

A typed notice links a booking disruption to an operational event or responsible organizer contact. It carries minimum permitted source facts, affected schedule/resource references, notice time, acknowledgement/response status and organizer resolution (relocate, amend/reschedule, cancel or unresolved). It is not itself event cancellation.

### 9.3 Event cancellation/postponement

Record an immutable event decision/change with event/session references, decision type (cancelled, postponed or rescheduled), initiator/approver identities and scopes, reason category, separate internal/public text, original/replacement schedule revision, material-change/reconfirmation policy, timestamps, linked disruption/booking requests and notification campaigns.

Current event lifecycle is a projection of these records. Never delete the prior schedule or rewrite past guest-visible revisions.

### 9.4 Campaigns and tenant integrity

Use explicit message purpose and normalized linkage to cancellation decision, affected event/booking and fixed audience snapshot. Keep campaign, recipient snapshot and per-channel attempts separate. Delivery is not the authority for cancellation.

Cancellation request, decision, campaign and delivery rows must have owner/tenant references consistent with aggregate ownership and active collaboration grant. Use typed FK targets where necessary; do not add unvalidated generic IDs. Actor references must prove organization membership/scope at action time and retain actor/grant context for audit. Cross-organization links preserve historical provenance after grant revocation. Enforce one effective cancellation per booking/event revision and test concurrent requests, approvals, cancellation/reschedule races and worker retries.

---

## 10. Proposed API command surface

Exact routes and schemas are for OpenAPI v0.3. These are command concepts, not a frozen contract.

**Booking:** submit cancellation request; read permitted request status; approve/reject/withdraw; initiate venue cancellation; preview effects/commercial consequences; execute effective cancellation; read history and disruption notices.

**Event:** preview cancellation effects/audiences; initiate/approve/execute cancellation; initiate postponement or publish schedule revision; configure reconfirmation policy; preview/confirm/inspect cancellation campaigns; acknowledge/resolve venue disruption and initiate linked booking amendment/cancellation request.

**Public access:** booking cancellation endpoints are scoped to a valid external action token and expose only information needed for the request. Guest invitation links remain separate and never authorise booking cancellation.

Mutating commands require an authenticated actor or narrowly scoped external action principal, server-side permission checks, relevant CSRF/origin protection, rate limiting, validation, audit and idempotency. Clients must not supply an actor identity to impersonate an authenticated operator.

---

## 11. Transactions, outbox and failure behavior

A cancellation command validates lifecycle state, actor authority, policy revision, approval requirements and affected reservations. It must use aggregate locking or equivalent concurrency control. A stale preview cannot authorise execution after the underlying booking/event changes; execute must recheck revision/state and require a fresh preview if stale.

In the same transaction as the authoritative change, persist the decision/audit event, apply internal state/resource effects, suppress future jobs and persist outbox/campaign records where applicable.

Workers process outbox events asynchronously and idempotently. Email/SMS delivery is not part of the database transaction. Failed notification does not roll back cancellation; failed resource commit prevents partial booking cancellation.

Repeated commands with the same idempotency key return the original outcome. Repeated approvals or worker jobs must not double-release reservations, double-apply fees or duplicate successful deliveries.

---

## 12. Audit, privacy and retention

Record what was cancelled/postponed and which revisions were involved; initiator, organization/scope and permission/grant; approver/decision/reason; policy revision; requested/approved/effective times; resource/task effects; notification audience rule, recipient snapshot counts, exclusions and confirming actor; delivery attempts/outcomes; external action-link issuance/revocation without raw tokens; and commercial consequence/follow-up status.

Keep internal cancellation reasons separate from guest-facing text. Restrict and audit access to private reasons, personal contact snapshots, commercial terms and attachments. Retention/deletion must follow validated organizational policy and applicable law; cancellation does not justify retaining all personal data indefinitely.

---

## 13. Permissions to add to successor catalogue

Proposed identifiers to align with the full permission catalogue:

**Booking scope:** booking.cancellation.request, booking.cancellation.read, booking.cancellation.review, booking.cancellation.approve, booking.cancellation.reject, booking.cancellation.execute, booking.cancellation.override, booking.cancellation.commercial.read.

**Event scope:** event.cancellation.preview, event.cancellation.initiate, event.cancellation.approve, event.cancellation.execute, event.cancellation.override, event.postponement.manage, event.cancellation.notifications.preview, event.cancellation.notifications.send, event.cancellation.notifications.manage.

A venue operator does not receive event-cancellation permissions merely because they can cancel a booking. A booking requester does not receive event-cancellation permissions merely because they are the event's commercial contact. A delegated communications operator receives only the minimum task grant.

---

## 14. Release and implementation sequencing

### Release 1 — Venue booking cancellation

- Confirmed-booking policy snapshot/configuration.
- External customer cancellation request without tenant membership.
- Venue-initiated cancellation with configurable authority/approval and emergency policy.
- Review, approval/rejection, reason history and customer notices.
- Effective cancellation transaction and concurrency-safe release of space/resource reservations.
- Commercial consequence snapshot and manual financial follow-up.
- Booking-contact notification tracking.
- Venue-disruption notice when a linked event exists; no guest data access/campaign required.
- Acceptance tests with no operational event or guest records.

### Release 2 — Organizer event cancellation and postponement

- Event cancellation preview/confirmation and authorization.
- Suppression of pending invitations/reminders and rejection of new RSVP after cancellation.
- Immutable cancellation decision and event/session/task lifecycle updates.
- Guest cancellation campaign with audience selection and recipient snapshots.
- Delivery tracking, retries and failure reporting.
- Venue-disruption acknowledgement and organizer resolution.
- Postponement/schedule revisions and RSVP reconfirmation.
- Delegated venue communications only through explicit task assignment/grant.

Release boundaries are priorities, not permanent product restrictions. If the reference deployment enables organizer operations earlier, deliver the corresponding workflows together rather than exposing incomplete cancellation controls.

---

## 15. Acceptance scenarios

1. A confirmed booking can be cancelled through venue-authorised action without creating an operational event or guest record.
2. An authorised external booking contact submits a request through a secure link without tenant membership; opening the link alone does not submit.
3. A request requiring approval leaves booking and reservations intact until approval.
4. Rejected/withdrawn requests preserve booking and reservation history.
5. Venue provider initiates cancellation due to hall unavailability with configured approval/emergency route and reason.
6. Effective booking cancellation releases future reservations exactly once and retains completed setup/service history.
7. Commercial effects use the booking's pinned policy; changing current policy does not alter old booking.
8. Booking cancellation informs configured contacts and does not automatically cancel a linked event.
9. Venue cancellation exposes only a scoped disruption notice; venue cannot enumerate guest records or RSVP responses.
10. Organizer cancels an event after invitations and accepted/declined/tentative/no-response states exist.
11. Event cancellation preserves prior RSVP answers and invitation/delivery records.
12. Event cancellation stops new invitations, reminders, RSVP submissions and admission operations.
13. An old invitation link shows a safe cancellation notice and cannot submit RSVP.
14. Organizer can select accepted/tentative, all active invitees, all previously invited recipients or permitted custom audience; preview and recipient snapshot are auditable.
15. Campaign can partially fail; retries do not duplicate successful deliveries and do not revert event cancellation.
16. Event cancellation does not automatically cancel venue booking; organizer can separately request booking cancellation.
17. Venue disruption does not automatically cancel event; organizer can relocate, reschedule, postpone or cancel.
18. Postponement preserves old schedule and responses; material schedule change can require reconfirmation without rewriting previous answers.
19. Rescheduling secures replacement resources before releasing original reservation when an atomic amendment is feasible.
20. Venue executes guest communications only when organizer assigned task and granted necessary scope.
21. Concurrent cancellation/approval or cancellation-reschedule race cannot create partial/contradictory outcomes.
22. Commands and worker effects are idempotent and auditable.

---

## 16. GHB validation questions

Before production policy is enabled, confirm:

- Who is contracting party for a typical booking, and can requester differ from signatory/payer?
- Which named contacts may request cancellation on behalf of organizer/client?
- Can an organizer cancel directly within a notice period, or must GHB approve every request?
- What are notice windows, fees, deposits, credits and refund rules? Do they vary by hall, event type, date or service?
- Who at GHB may initiate/approve venue-side cancellation? Is a second approver required? Which emergency cases bypass prior approval?
- What notice must GHB give if it cannot provide a confirmed space/service?
- Which booking contacts must receive cancellation notices?
- Does GHB ever contract to notify organizer guests, or is that always organizer-owned?
- Which email/SMS channels and sender identities are approved?
- Can a booking be rescheduled/amended without a new offer, and who approves?
- How should deposits and completed/partially delivered venue services be represented at cancellation?

Do not infer answers from the historical rental form or generic industry practice.

---

## 17. Related design work

- [Operating Model](../../OPERATING_MODEL.md) — venue-provider, organizer and collaborative responsibilities.
- [ADR 0004](../../decisions/0004-optional-event-operations-scope.md) — booking does not require event operations.
- [RSVP and Invitation Design v0.3](RSVP_AND_INVITATION_DESIGN_v0.3.md) — invitation, RSVP, participation and attendance remain separate.
- [ADR 0005](../../decisions/0005-separate-invitations-rsvp-attendance.md) — response and attendance separation.
- [Cross-Organization Collaboration Design v0.3](CROSS_ORGANIZATION_COLLABORATION_DESIGN_v0.3.md) — ownership, explicit grants and venue snapshots.
- [ADR 0006](../../decisions/0006-cross-organization-collaboration.md) — accepted ownership/collaboration direction.
- [Database integrity design v0.3](../../database/DATABASE_INTEGRITY_DESIGN_v0.3.md) — tenant integrity, reservations and concurrency.
- [Issue #21](https://github.com/TeraflopsBH/eventor/issues/21) — design review and successor implementation alignment.

Historical v0.2 SQL/OpenAPI remain reference snapshots. This document does not authorize applying schema changes to them. Successor schema and OpenAPI contracts must model these workflows explicitly, be reviewed together and be validated before implementation.
