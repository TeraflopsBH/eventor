# Event invitations and RSVP — design addendum v0.3

**Status:** proposed domain/API design, ready for schema and contract review  
**Date:** 2026-11-10  
**Parent design:** Implementation Design v0.2  
**Related decisions:** ADR 0004 (optional, responsibility-scoped event operations); ADR 0005 (invitation, RSVP and attendance are separate lifecycles)  
**Related issue:** [#6 — Specify invitation and RSVP lifecycle](https://github.com/TeraflopsBH/eventor/issues/6)

This document extends the historical v0.2 design without rewriting it. It specifies the agreed invitation/RSVP behavior and incorporates the venue-provider/event-organizer operating model. It is not yet a production SQL migration or validated OpenAPI contract.

## 1. Product boundary: RSVP is an optional event capability

A venue booking does not require an operational event, a guest registry, invitations or RSVP.

The following records and behavior exist only when the applicable event/guest capabilities are enabled:
- Event and event-session records, where needed.
- Event guest participation records.
- Invitation records and invitation access links.
- RSVP policy and response history.
- Guest portal surfaces.

A venue-provider-only workflow remains complete with the booking/customer contacts and venue-side service requirements. It must not create attendee/guest records simply to represent a booking contact, nor require the venue provider to collect the renter's guest data.

For a hybrid event, the organizer may own guest operations while the venue provider handles venue-side tasks. Guest operations may be assigned to the venue provider only when it has explicitly accepted that contracted responsibility. The party responsible for guest data is the operating organization assigned to that module/task, not automatically the venue provider.

### 1.1 Capability dependencies

| Capability | Requires | Does not require |
|---|---|---|
| Venue booking | Booking customer/contact and venue/resource model | Event, event guests, invitations, RSVP, check-in |
| Event guest registry | Operational event with guest participation enabled | Invitations, RSVP, seating or check-in |
| Staff-recorded RSVP | Event guest and RSVP capability enabled | Guest email, invitation link, guest account, admission QR |
| Guest self-service RSVP | Event guest, RSVP capability, invitation link and guest-facing route | Guest account, seating, admission QR or check-in |
| Seating/allocation | Event participants or another explicit allocation subject set, plus spatial model | Invitation delivery or RSVP |
| Check-in | Admission/attendance subject and authorized scan/manual workflow | RSVP confirmation or seating |
| External prerequisite coordination | Event/task scope with an explicitly assigned responsible party | Guest Registry, invitations or RSVP |

Dependencies must be explicit and minimal. Enabling one capability must not silently activate every other event module.

## 2. Keep four independent state dimensions

The current v0.2 `event_guests.rsvp_status` combines different concepts (`pending`, `invited`, `confirmed`, `declined`, `waitlisted`, `not_required`). These must be separated in the successor schema.

### 2.1 Invitation lifecycle

Invitation issuance and delivery describe whether an invitation was prepared and communicated. They do not say whether the guest accepted.

Recommended concepts:
- Invitation record: draft/prepared, active, revoked, expired or cancelled.
- Delivery attempt: queued, sent, delivered, failed, bounced or suppressed.
- Access link: active, revoked, expired or replaced.

A guest may have an active invitation but no response. Delivery may fail while staff later record a phone confirmation. Resending an invitation must not erase an existing response.

### 2.2 RSVP response

RSVP describes the guest's stated intention, not the invitation's delivery state or actual arrival.

Initial semantic response codes:
- `accepted` — intends to attend.
- `declined` — will not attend.
- `tentative` — cannot yet confirm, when this response is enabled for the event.

The semantic choices and their display labels are event configuration. An organization may localize labels and enable/disable tentative response. A custom option must map to an explicit system meaning so that reporting and readiness logic remain deterministic; a free-form label must not silently acquire acceptance semantics.

No response is a state of `pending`; it is not an implicit decline. Whether RSVP is required, optional or not applicable is a separate policy, not an answer. A waitlist/admission decision is also separate and must not be represented as an RSVP response.

### 2.3 Participation / invitation eligibility

Whether a person is active in the event, cancelled, archived, invited, waitlisted or otherwise eligible is not the RSVP answer. Keep participation and admission eligibility as independent state dimensions.

### 2.4 Attendance

Attendance is a physical operational fact recorded by check-in or an authorized manual attendance workflow. An accepted RSVP does not mean the guest arrived; a declined or missing RSVP does not itself create a check-in. The current `guest_session_attendance` and append-only check-in records remain separate from RSVP history.

## 3. RSVP policy and timing

Each event that enables RSVP has a versioned policy snapshot. It should include:

- Whether RSVP is enabled.
- Whether a response is required, optional or not applicable by default.
- Enabled response options and their stable semantic codes / localized labels.
- Response deadline as an absolute `timestamptz`; display and entry use the event's configured IANA timezone.
- Whether a guest may change their response before the deadline.
- Whether staff may record a response after the deadline, and which role may authorize an override.
- Reminder schedule, maximum reminder count and quiet-hour rules.
- Permitted delivery channels and selected invitation template revision.
- Optional secondary verification policy for sensitive/high-profile events.
- Optional event-specific follow-up questions, independently versioned and validated.

The deadline is a response cutoff, not an automatic response. At cutoff, unanswered guests remain unanswered; dashboards may show them as overdue/unconfirmed. Do not convert them to declined automatically.

Policy changes after invitations have been sent must be versioned and auditable. The event must retain the policy revision used for each issued invitation/response. A policy update must not silently reinterpret previous answers. The effective deadline shown to each guest must be clear.

For normal self-service, guests may change an answer until the configured deadline when the policy permits it. After cutoff, guest self-service is closed. An authorized staff member may still record a late response or correction using an explicit override permission and reason; the original response and override remain in the history.

## 4. Guest self-service flow

### 4.1 Invitation issue

1. An authorized operator selects event guests and an approved contact point for each.
2. The application creates invitation records using the event's published invitation/template/policy revisions.
3. It creates or reuses the current valid invitation access link for each guest.
4. It queues a notification delivery attempt (email is the initial channel).
5. The delivery worker records provider reference, timestamps and safe delivery status/error information.
6. The guest list shows invitation and delivery state separately from RSVP response state.

Batching and reminders are operational conveniences. Each invitation, delivery attempt and response remains traceable to its event guest and the relevant configuration revisions.

### 4.2 Link security

The invitation URL contains a high-entropy, opaque bearer secret (at least 256 bits from a cryptographically secure random generator). The raw secret is never stored in the database, logs, analytics or audit payloads; only a one-way token hash is stored.

Invitation access is:
- Bound to exactly one invitation/event-guest record and one event.
- Purpose-limited to reading that guest's invitation context and submitting that guest's RSVP.
- Separate from admission QR credentials and check-in.
- Revocable and replaceable. Reissue revokes the previous link before a new link becomes active.
- Time-limited. Expiry is configured independently from the RSVP deadline; an expired link cannot submit a response.
- Rate-limited and protected against token enumeration.

The public endpoint must not mutate the invitation or response merely because a browser or email-security scanner performs a GET. Link resolution is a non-destructive POST exchange. The preferred web-link pattern places the secret in the URL fragment so it is not sent in the initial HTTP request; the first-party client then submits it over TLS to the resolve endpoint. No third-party analytics/assets should receive the secret. Use `Referrer-Policy: no-referrer`, avoid token-bearing redirect URLs and redact request bodies/headers in logs.

Resolving a link establishes a narrowly scoped guest session. The guest explicitly selects and confirms a response. The link must not be a one-click RSVP decision. Link resolution itself does not count as a response and should be idempotent so security scanners do not consume it.

A secondary verification step may be enabled for selected events, but a full guest account is not the default. The token is a bearer credential: the interface should warn guests not to forward it, and staff can revoke/reissue it.

### 4.3 Guest-visible information

The guest view may show only:
- The event name and approved guest-facing description/date/time/location.
- The invitation/RSVP prompt, deadline and allowed answers.
- The guest's own current response and confirmation.
- Optional event-specific response questions.
- Other personal event information only when separately enabled and approved, such as the guest's own seating locator.

It must not expose other guests, internal notes, restricted prerequisites, staff/organizer contacts not designated for public use, allocation rules, private floor-plan layers or venue internal operations data.

### 4.4 Response submission

1. The guest opens the invitation and resolves the link.
2. The application presents the currently valid policy and response choices.
3. The guest explicitly selects and submits an answer.
4. The server checks event/module state, link scope/revocation/expiry, response deadline and change policy.
5. It appends a response-history record and updates the event-guest current-response projection in one transaction.
6. It returns a confirmation and, if enabled, queues a confirmation notification.

The browser is never authoritative for the response status. Duplicate submissions must be idempotent; concurrent submissions must not silently overwrite one another. If the guest submits a new answer, preserve the previous answer as history.

## 5. Staff-recorded responses

Staff must be able to record a response received outside the portal, including:
- Telephone.
- In person.
- Email.
- Written communication.
- Assistant or representative.
- Import or another explicitly configured source.

The staff command records:
- The selected RSVP answer.
- Source/method.
- When the response was received (the reported/observed time).
- When the record was entered (server-generated timestamp).
- The authenticated operator who entered it.
- Optional respondent/representative detail where necessary.
- Optional brief note/reason, under appropriate classification and permissions.
- Whether it was late or an override was used, including the authorizing actor and reason.

The operator identity is mandatory for staff capture. Do not allow an API client to supply or impersonate the operator ID; derive it from the authenticated session. A staff-recorded response does not require an invitation link or guest email address.

Staff correction is append-only: add a new response-history record that supersedes the previous effective response, with reason and actor. Do not edit/delete the previous response. A staff override after the deadline must use a dedicated permission and be audited.

## 6. Proposed data model for the next schema revision

The following is a logical model, not final SQL. Exact keys, tenant foreign keys, indexes and constraints will be resolved in the schema-review issue.

### 6.1 `event_invitations`

One invitation instance for one event guest, with:
- Organization, event and event-guest foreign keys.
- Invitation purpose/type and lifecycle state.
- Selected contact-point reference and a minimal recipient snapshot needed to explain what was sent.
- Invitation/template revision and RSVP-policy revision snapshots.
- Created/issued/revoked/expired metadata.
- Actor responsible for issuing/revoking.
- Optional batch/campaign reference.

Do not copy every person contact field into a general-purpose event record. Store the minimum needed, classify it and enforce retention.

### 6.2 `event_invitation_links`

One row per invitation-link issuance/reissue:
- Invitation ID and organization/event scope.
- Token hash (unique; never raw token).
- Issued, expiry, revocation and replacement metadata.
- Status and optional last successful resolution timestamp.
- No response fields; link resolution is not a response.

A replacement creates a new row and marks the old one replaced/revoked. The previous hash remains only as needed to reject replay and prove lifecycle/audit history; remove according to retention policy.

### 6.3 `event_guest_rsvp_responses`

Append-only response history:
- Organization, event, event-guest and optional invitation IDs.
- Stable semantic response code and response-option revision/label snapshot.
- Source code (guest portal, telephone, in person, email, written, representative, import or other).
- Respondent kind (guest, assistant, representative or staff-recorded on behalf of guest).
- `response_received_at` — when the response was communicated, where known.
- `recorded_at` — server-generated timestamp when Eventor captured it.
- `recorded_by_user_id` — required for staff/import actions; null for guest self-service.
- Optional classified note/reason and request/idempotency identifier.
- Optional `supersedes_response_id` for corrections/changed answers.

Rows are never updated or deleted by ordinary application workflows. A correction appends a new row. The current response is either a validated projection on `event_guests` or a view derived from the latest effective history record; it must never be the only retained copy.

### 6.4 RSVP policy revisions

A published, versioned RSVP policy is bound to the event and invitations. It contains the enabled response semantics, deadline, change policy, reminder schedule, locale and guest-facing copy. A policy publication creates a new revision; previously issued invitations and response snapshots remain interpretable.

### 6.5 Existing schema reuse and changes

- `event_guests.rsvp_status` in v0.2 is a denormalized legacy field. In the successor revision, separate it from invitation status and admission/waitlist status. A compatibility mapping for existing values must be defined in the migration.
- `guest_credentials` currently mixes `admission_qr`, `guest_portal` and `staff_assist`. Do not use an admission QR as an invitation link. Decide in the successor schema whether `guest_portal` represents only an established short-lived portal session or is replaced by a distinct session/token construct.
- `notification_deliveries` already tracks channel, template revision, status and provider reference, but it needs a reliable invitation relation/message-purpose field or an equivalent normalized invitation-delivery table. A generic delivery row must not be the sole invitation record.
- `guest_session_attendance` and check-in records remain independent.
- `event_prerequisites` remain optional and responsibility-scoped; they are not a prerequisite for RSVP or guest participation unless a separately configured business rule explicitly establishes a dependency.

## 7. API contract proposal

These routes are proposed names/shapes to be normalized during OpenAPI v0.3 review. They are not yet added to the historical v0.2 OpenAPI file.

### Guest-facing routes

- `POST /public/invitations/resolve` — exchange the invitation secret for a short-lived, narrowly scoped guest session and safe invitation context. No response change occurs.
- `GET /guest-portal/me/invitation` — read the current guest-facing invitation and RSVP policy.
- `GET /guest-portal/me/rsvp` — read the guest's own current response.
- `POST /guest-portal/me/rsvp-responses` — explicitly submit/change an answer, with idempotency key and server-side deadline/policy enforcement.

Guest-facing responses must be purpose-built projections and must not contain event guest IDs or internal database identifiers unless strictly required by the client.

### Staff routes

- `POST /events/{eventId}/invitations` — issue invitations for selected event guests; accepts the published template/policy or explicit approved revisions.
- `POST /events/{eventId}/guests/{eventGuestId}/invitations/{invitationId}/resend` — queue a new delivery attempt without changing RSVP.
- `POST /events/{eventId}/guests/{eventGuestId}/invitations/{invitationId}/reissue-link` — revoke the old invitation link and create a new link.
- `POST /events/{eventId}/guests/{eventGuestId}/rsvp-responses` — staff-record a response from an outside channel.
- `GET /events/{eventId}/guests/{eventGuestId}/rsvp-responses` — permissioned response history.
- `POST /events/{eventId}/guests/{eventGuestId}/rsvp-responses/{responseId}/corrections` — append a correcting response with reason; never mutate the original row.

All staff routes require event-scoped permissions. Public routes are enabled only when the event has guest participation and guest self-service RSVP enabled.

## 8. Permissions and responsibility

Suggested permissions (exact naming is subject to the authorization catalogue):
- `event.guests.read`
- `event.invitations.issue`
- `event.invitations.resend`
- `event.invitations.revoke`
- `event.rsvp.read`
- `event.rsvp.record`
- `event.rsvp.override_deadline`
- `event.rsvp.export`
- `event.rsvp.policy.manage`

The module/task owner is explicit. The venue provider can see only its booking and venue-service fields unless it has been assigned the relevant guest-operation task and granted scoped access. An event organizer can operate RSVP for the event it owns. A third-party registration contractor may receive a restricted task-specific role. A booking relationship alone grants no guest-data access.

If the organizer operates invitations through its own system, the venue provider may retain a booking-only record and receive only the venue service information needed to perform its obligations. There is no requirement to synchronize the organizer's entire guest list into a venue-provider Eventor deployment.

## 9. Operational UI behavior

When guest participation or RSVP is disabled:
- Hide guest list, invitations, RSVP panels and guest portal routes from that event workspace.
- Do not show empty RSVP statistics as if an RSVP operation were expected.
- Do not require guest contact fields on the venue booking form.
- Keep booking contacts separate from event guests.

When RSVP is enabled:
- Event guest list shows independent columns for participation, invitation/delivery, RSVP response and attendance.
- Show invitation delivery failure separately from pending response.
- Provide filters for no response/overdue, accepted, declined, tentative (if enabled), no invitation and delivery failure.
- Show the effective deadline and timezone.
- Provide bulk issue/reminder/resend only with preview and scoped permission.
- Display response history and source/operator on the staff detail view.
- Use an explicit correction/late-override workflow, not inline edits that erase history.

## 10. Security, privacy and retention

- Token material is generated with a CSPRNG; only a one-way hash is retained.
- Token scope is one event guest and invitation purpose.
- Admission credentials and invitation credentials are distinct.
- No public guest directory/search endpoint exists.
- Guest responses are isolated by organization/event and are never exposed to the venue merely because it provided the space.
- Public event details and response options are an allow-listed projection.
- Rate-limit resolve and response endpoints; use generic failure messages to reduce token enumeration.
- Do not store bearer tokens, full invitation URLs or raw request bodies in logs, analytics, traces or audit events.
- Use TLS, secure cookies, CSRF protection for cookie-authenticated writes, strict response schemas and a no-referrer policy.
- Minimize IP/user-agent retention; any abuse/security metadata is separate, access-controlled and retention-limited.
- Guest export, access, correction and deletion/retention requests follow organization policy and applicable law. Eventor does not invent universal retention periods.

## 11. Acceptance scenarios

1. A venue-provider-only booking is created, quoted, confirmed and fulfilled without an operational event, event guest, invitation, RSVP or attendee contact list.
2. An organizer creates an operational event and enables guest participation but disables invitations/RSVP; staff may still manage event guests for seating or check-in.
3. An organizer enables RSVP and emails a personalized invite. The guest can resolve the link, read only their own approved context and submit an answer without creating an account.
4. A security scanner performs GET on the invitation URL; no response is recorded and the link remains usable.
5. The guest changes an answer before the configured deadline; both answers remain in history and the latest effective answer is shown.
6. The deadline passes; guest self-service changes are rejected according to policy while the previous answer remains intact.
7. An authorized staff member records a telephone/in-person/email/written/representative response without an invitation. The source, received time, recorded time, operator and note/reason are retained.
8. A correction appends a new response; the original response remains auditable.
9. A staff member without late-override permission cannot record a late response as an ordinary change.
10. Invitation delivery fails but a staff member later records a confirmation; delivery failure and RSVP confirmation remain separate.
11. A revoked, expired or replaced link cannot resolve or submit a response.
12. The invitation link cannot authenticate an admission QR scan or access another guest.
13. RSVP acceptance does not create attendance. Check-in is a separate authorized action and can differ from RSVP.
14. GHB acting only as venue provider sees booking/service data but no organizer guest list, invitation history, RSVP answers or organizer-only prerequisites.
15. In a hybrid operation, the venue team sees only the subset of guest/service data explicitly assigned to its task; the organizer retains control of its guest records.

## 12. Decisions still needed before implementation

The domain architecture is specified, but event owners must confirm operational defaults:
- Whether tentative response is enabled by default or disabled per event.
- Default response deadline and reminder cadence.
- Whether secondary verification is required for any class of events.
- Whether invitation delivery is email-only in MVP or allows additional channels.
- Whether guests may update RSVP after first submission until deadline (recommended default: yes).
- Whether RSVP can be recorded for a representative and which details are necessary.
- Event-specific response questions (for example meal requirements) and data retention for answers.

These are configuration/organization-policy choices where possible, not hardcoded global assumptions. Only questions that affect security, access control, schema semantics or contractual workflow need to block the technical design.
