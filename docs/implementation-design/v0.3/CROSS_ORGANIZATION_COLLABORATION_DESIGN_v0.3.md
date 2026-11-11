# Cross-organization venue and event collaboration — design proposal v0.3

**Status:** accepted architecture and domain model; schema/API implementation and validation remain open  
**Date:** 2026-11-10  
**Related:** ADR 0004 (optional event operations), [Issue #12](https://github.com/TeraflopsBH/eventor/issues/12), [Database Review v0.2](../../database/DATABASE_REVIEW_v0.2.md)

This proposal addresses a core distinction in Eventor: a venue provider and the event organizer may be different organizations, with separate data ownership and operational responsibilities. It is written as a successor design note; the v0.2 schema remains an unchanged historical snapshot.

## 1. The normal operating case

Example: GHB rents a hall to an independent conference organizer.

- GHB owns the venue, room geometry, equipment/resource inventory, venue-side services and its booking record.
- The conference organizer owns the event, guest registry, invitations, RSVP responses, seating decisions, attendee communications and organizer-side external coordination.
- GHB needs the confirmed dates/times, rooms, expected capacity/aggregate attendance where appropriate, approved setup and equipment/service requirements.
- GHB does not automatically need attendee names, contact details, invitation links, RSVP answers, private seating notes or organizer coordination documents.
- The booking is complete even when no operational event is created in GHB's Eventor workspace.

The same physical venue may be used by many organizer organizations. An organizer may also use several venue providers for one event.

## 2. Ownership model

Keep the following records under their natural owner:

| Data | Owning organization |
|---|---|
| Venue, building, floor, room and master geometry | Venue provider |
| Approved venue-space revisions and master allocation-resource inventory | Venue provider |
| Booking inquiry, quote, commercial approval, confirmed booking, space reservations and venue service fulfilment | Venue provider |
| Event identity, programme, sessions and event operating configuration | Event organizer / assigned event-operating organization |
| Guest registry profiles and event participation | Organization responsible for guest management |
| Invitations, invitation links, RSVP history and guest responses | Organization responsible for invitations/RSVP |
| Seating and allocation decisions for the organizer's event | Event-operating organization |
| Check-in and attendance records | Organization assigned to operate admission/check-in |
| External prerequisite coordination records | Organization assigned to the relevant prerequisite task |
| Event-day tasks and task outcomes | Accountable organization / assigned operator, per task |

An organization may act in multiple roles, but one role must not be inferred from another. A booking customer/requester, contracting party, payer and event organizer may all differ.

### 2.1 Customer is not necessarily an Eventor tenant

A renter/customer does not need an Eventor account or tenant merely to book a venue. The venue provider can keep a minimal booking-party/contact snapshot for its booking workflow.

Only when the organizer wants to operate Eventor within the same installation does it need its own organization scope and explicit collaboration/access grants. Otherwise it can continue using its own event system; the venue provider does not import the organizer's guest list.

## 3. Relationship model

### 3.1 Booking and event are separate aggregates

A venue booking belongs to the venue provider organization. An operational event belongs to the event-operating organization.

When the organizer also uses Eventor in the same deployment, create an explicit many-to-many association (proposed `booking_event_links`) with separate owner identifiers:

- `booking_owner_organization_id` + `booking_id`.
- `event_owner_organization_id` + `event_id`.
- `collaboration_grant_id` authorizing this relationship.
- Link state, creator, acceptance and timestamps.

A booking can link to an event without transferring ownership. An event may link to multiple venue bookings (for example, multiple venues/space providers); a booking may be associated with an event series or multiple sessions where the product workflow permits it. Uniqueness and cardinality must be explicit in the successor schema.

Do not keep the v0.2 pattern where `booking_records.linked_event_id` is constrained to the same `organization_id` as the booking. That only models a same-tenant deployment.

### 3.2 Explicit collaboration grants

Create an auditable grant between a grantor/provider organization and a grantee/recipient organization. It is a scoped authorization relationship, not a shared login or general membership.

A grant should record:
- Grantor and recipient organization IDs.
- Business purpose (booking collaboration, venue plan use, operational task delegation, or similar).
- Relevant booking/event/resource scope.
- Named capability scopes and safe field projections.
- Issuer, recipient acceptance where required, status, effective period and revocation.
- Optional contract/reference identifier and internal notes with restricted access.
- Audit history of issue, acceptance, modification, use, expiry and revocation.

Candidate scope capabilities (stable codes, not hardcoded screen switches):
- View booking summary / schedule.
- View confirmed venue service lines and delivery status.
- View approved venue-space plan revision and selected map layers.
- Use an approved venue-space revision for an event session.
- View aggregate attendee count only.
- Perform registration/check-in as an assigned service.
- View only the minimum event-day data needed for an assigned task.
- Submit venue-side issue/status updates.

The grant does not make the recipient an organization member of the grantor. The recipient's own active organization members receive only those permissions explicitly granted to them.

### 3.3 Venue plan sharing: use event-owned immutable snapshots

**Preferred approach:** when a provider authorizes use of an approved venue-space revision, create an immutable, purpose-limited event-space snapshot inside the organizer's event scope.

The snapshot records:
- Provider organization ID and source venue/space/revision identifiers.
- Source revision number and content hash.
- Grant ID that authorized the share.
- Capture timestamp and actor.
- Approved display name, geometry, public/operational layers and allocation-resource inventory selected for sharing.
- Visibility classification for each included layer/object.
- Revocation/supersession state and any use/validity boundaries.

The organizer's event session binds to this shared snapshot, not directly to the provider's editable master venue tables. The organizer's allocation records reference event-owned snapshot resources. This avoids cross-tenant foreign keys into provider-owned geometry and prevents later provider edits from silently changing an approved or already-used event plan.

The provider remains owner of the master source revision. The snapshot is an authorized derived view, not a transfer of venue ownership or permission to modify the provider's master geometry.

#### Why not direct cross-tenant foreign keys?

A direct relation from an organizer's event session or guest allocation into the venue provider's resource tables would require a complex cross-tenant RLS and write boundary. It risks treating a booking relationship as broad database access. A snapshot approach gives the organizer the exact approved data it needs while preserving immutable provenance and clean tenant ownership.

Direct cross-tenant references may still be considered for narrowly controlled read-only metadata, but they should not be the default for spatial geometry, allocation resources or guest-facing maps.

### 3.4 Event/session model

In the successor schema:
- Event sessions are owned by the event-operating organization.
- A session-space relation references an event-owned shared space snapshot.
- Allocation resources used by the session belong to that snapshot and event scope.
- The source provider revision and grant remain traceable.
- The venue provider's original inventory and source layers remain unchanged.
- Provider-side capacity/availability remains authoritative for the booking; the organizer's seating/guest allocation must fit within the shared approved resource/capacity information.

Any event needing a revised plan receives a new shared snapshot and explicit event-session rebind/approval workflow. Never overwrite the snapshot used by an already-published guest plan.

## 4. Responsibility assignment

Module activation and task responsibility are distinct. An enabled module does not automatically mean the venue provider performs it.

For each module/task, the event should define:
- Accountable organization (one clear owner).
- Performing organization(s) and responsible role/team/person.
- Approver, when required.
- Informed parties.
- Allowed data projection/capability scope for each organization.
- Due time and readiness criteria, if applicable.
- Whether the task is not applicable or managed outside Eventor.

Examples:
- Venue setup: accountable/performed by GHB; organizer sees completion status.
- Invitations and RSVP: accountable/performed by organizer; GHB sees no guest details.
- Guest seating: organizer owns allocations, using a GHB-approved event-space snapshot.
- Registration desk: organizer owns guest records; GHB may perform scanning only if contracted, with a restricted check-in projection.
- External prerequisite: organizer may own coordination; GHB receives only a venue-readiness signal if explicitly agreed.
- GHB-arranged refreshments: GHB owns fulfilment details; organizer sees the approved service commitment and status.

If a third-party operator does not use Eventor, the assignment may name an external party and track confirmation without granting an account.

## 5. Information-sharing rules

### 5.1 Default deny

No collaboration grant means:
- Venue provider sees its own booking/customer/service records only.
- Organizer sees its own event and guest data only.
- Neither party receives the other's internal notes, contacts, credentials, personal data or restricted documents by default.

### 5.2 Minimum necessary projections

A grant can expose a safe projection without exposing the underlying aggregate:
- Aggregate attendance estimate/count without guest names.
- Event schedule and room usage without the full attendee database.
- Confirmed service lines without internal venue cost or price-calculation notes.
- Check-in task projection with only the minimum fields needed to identify/validate an attendee.
- Venue plan snapshot with selected approved layers, while private staff/security layers remain excluded.

For venue-plan sharing, the provider approves explicit stable source identifiers: selected spatial layer IDs from one published venue-space revision, plus optional resource-pool or discrete-unit IDs at the same venue. The organizer cannot request a different source revision or add a layer/resource to the copied projection. Objects may be copied only from the approved layers. The database validates the identifiers and enforces source-row visibility through tenant RLS while the share and use grant are active. On revocation, the recipient loses access to provider-owned source rows and cannot create new copies or operational bindings; snapshots already copied into the organizer's tenant remain immutable historical records.

The system must distinguish:
- Booking visibility.
- Venue inventory/plan visibility.
- Event operations visibility.
- Guest personal-data visibility.
- Task-specific operational visibility.

### 5.3 Guest-data ownership and access

Guest registry, contact points, RSVP responses, restricted notes and event-specific guest fields remain under the organization responsible for guest management. A venue provider cannot access them merely because it owns the hall, processed the booking or employs the staff performing a venue-side task.

Where a venue is contracted to provide registration/check-in, it receives only the task-specific data projection and permissions needed for that service. Access to contact details, RSVP history, seating notes and unrelated guest fields is not implied.

## 6. Access lifecycle

A proposed collaboration lifecycle is:

`proposed -> invited -> accepted -> active -> expired | revoked | completed`

- A grant is created by an authorized party for a specific business purpose/scope.
- The recipient accepts when the workflow requires bilateral agreement.
- Access is constrained by the grant plus the recipient user's organization membership and role permissions.
- The system records which grants authorize booking-event links, venue snapshots and task views.
- Expiry prevents new actions and new snapshots.
- Revocation immediately blocks future access and new shares. Existing event snapshots remain traceable for audit; operational use is blocked or marked as requiring reauthorization according to the event's contract/readiness policy.
- Revocation never silently deletes booking records, organizer guest records or historical event decisions.

An authorization grant is not a legal determination about data controller/processor roles or statutory responsibility. Those must be established by the organizations' contractual and legal arrangements.

## 7. Example workflows

### 7.1 Venue-provider-only booking (GHB's normal workflow)

1. Renter submits a booking inquiry with organization/contact, event title/type, date/time, expected attendance where relevant, room and service requests.
2. GHB creates an editable booking draft, offers/approvals and confirms the booking.
3. GHB reserves rooms/resources and prepares contracted venue services.
4. No operational event, guest registry, guest invitations, RSVP or check-in records are created in GHB's Eventor tenant.
5. The organizer handles its guest list, communications, protocols and attendance outside GHB's Eventor.

This is a complete product workflow, not an incomplete event.

### 7.2 Organizer also uses Eventor in the same deployment

1. GHB confirms the booking and identifies the organizer's Eventor organization.
2. GHB offers a scoped collaboration grant and shares the approved venue-space revision/resource projection.
3. The organizer accepts the grant and creates an operational event under its own organization.
4. An explicit booking-event link joins the two aggregates.
5. The organizer creates guest records, invitations/RSVP, seating and check-in as needed, under its own data ownership.
6. GHB sees booking and venue fulfilment information. It does not see guest records or RSVP unless the organizer separately grants the exact task/data projection.
7. If GHB is assigned registration or another operational task, it receives a task-specific staff view and only the necessary information.

### 7.3 Multiple venues/providers

An organizer event can link to separate bookings from multiple venue providers. Each provider receives only its own booking and the space/service/task scopes it has been granted. Providers do not see one another's commercial records or the organizer's full guest database.

## 8. Proposed successor data objects

Logical objects to review during schema v0.3+:
- `organization_collaboration_grants` and append-only grant status history.
- `booking_event_links` with distinct booking-owner and event-owner organization IDs.
- `venue_space_share_grants` or equivalent grant-scoped plan-sharing records.
- `event_space_snapshots` and `event_space_snapshot_resources` owned by the event-operating organization, with provider revision provenance/hash.
- `event_module_settings` / capability revisions.
- `event_responsibility_assignments` for accountable/performed/approving/informed parties and data scopes.
- `booking_party_snapshots` or equivalent distinct requester, contracting party, payer, representative and actual organizer references/snapshots.
- Cross-organization audit entries that record the acting organization, user, grant and source/target aggregate without exposing unrelated fields.

These are design candidates, not approved table names or final DDL.

## 9. Security and consistency requirements

- All tenant-owned records retain one clear owning organization.
- Cross-organization access requires an active, scoped grant and an authenticated user who is authorized in the grantee organization.
- No API, WebSocket, job, file or export path may infer access from a booking ID alone.
- Public guest APIs continue to expose only the authenticated guest's allowed projection.
- Shared venue plan snapshots are created only from approved revisions and are content-hashed, version-pinned and auditable.
- Guest allocations reference the event-owned snapshot, not mutable provider master resources.
- Venue-provider capacity/availability and contract status remain authoritative for the venue booking.
- Recheck collaboration grant status on protected operations; cache invalidation/revocation behavior must be explicit.
- RLS policies must preserve tenant isolation. Cross-tenant collaboration should be implemented as narrow scoped operations/projections, not by disabling RLS or using a general-purpose bypass role.

## 10. Confirmed architecture decisions and implementation details

1. **Same-instance organizer tenancy:** support an organizer organization as a separate tenant in the same Eventor deployment when it wants guest/event operations (recommended: yes).
2. **Space sharing:** use immutable event-owned snapshots of provider-approved space revisions/resources (recommended) rather than direct cross-tenant writes/references.
3. **Grant acceptance:** require recipient acceptance before the organizer can create the linked event or access shared plan data (recommended: yes).
4. **Booking/event cardinality:** support multiple booking-event links for multi-venue events and event series, with explicit rules to prevent accidental duplicate linkages (recommended: many-to-many).
5. **External organizers:** keep them as booking-party records only unless they explicitly onboard as an Eventor organization in the same installation (recommended: yes).
6. **Revocation behavior:** stop new access/snapshots immediately, preserve historical audit, and require reauthorization before further operations that need the revoked share (recommended: yes).

The product owner accepted the recommended approach on 2026-11-10: separate same-instance organizer tenancy, immutable event-owned snapshots of approved venue revisions, explicit grant acceptance, many-to-many booking/event association where needed, external customers as booking-party records unless explicitly onboarded, and immediate revocation of future access with historical traceability. These are the accepted architectural defaults. Exact table names, cardinalities, lifecycle edge cases and authorization/data-projection tests remain engineering design work.
