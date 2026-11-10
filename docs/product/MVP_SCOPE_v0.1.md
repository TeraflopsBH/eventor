# Eventor MVP scope — v0.1

**Status:** proposed product scope for review  
**Date:** 2026-11-10  
**Reference deployment:** Gazi Husrev-beg's Library (GHB), Sarajevo  
**Related:** [Issue #4](https://github.com/TeraflopsBH/eventor/issues/4), ADR 0004, ADR 0006

## 1. Product position

Eventor is one platform with two distinct but composable product capabilities:

1. **Venue booking and resource management** — a venue provider receives inquiries, prices/approves requests, books spaces/resources and delivers venue-side services.
2. **Event organization and operations** — an event organizer manages participants, invitations/RSVP, seating, check-in and event-day work.

A deployment may use either capability or both. A particular booking does not automatically become a full operational event. An organization profile is a default, not a rigid product edition. Capabilities can be activated per booking/event and task ownership is explicit.

For the GHB reference deployment, the safest MVP assumption is that GHB acts primarily as a **venue provider**. Its renter remains the event organizer unless GHB explicitly accepts an organizer/operations service. The booking workflow must be useful and complete without collecting the renter's guest list.

## 2. Recommended release boundary

### Release 1 — Venue booking and venue operations

This is the first production-capable GHB workflow.

#### Included

**Organization and access**
- Organization and venue-provider configuration.
- Staff authentication, organization membership, scoped roles/permissions and audit.
- Configurable approval authorities and staff assignments.

**Venue/resource registry**
- Venue, building, level, space and approved space revision.
- Space availability calendar and operational time blocks for setup, rehearsal, event and teardown.
- Venue-owned bookable resources: equipment, staff/services, ancillary spaces and count-based pools.
- Capacity and resource inventory must be approved and revisioned.
- Venue configuration is not hardcoded to GHB; GHB data is a tenant's configuration.

**Public inquiry**
- Public form with organization/venue branding.
- Configurable fields, options, localization, validation and published revisions.
- Simple request intake: requester/customer, contracting details where needed, actual event organizer contact where known, event title/type, preferred date/time/duration, requested space, expected attendance if needed for venue rules, requested equipment/services, rehearsal/setup/teardown and notes.
- No guest-level attendee list, invitation data, RSVP answers or admission information.
- No account required for initial inquiry; public endpoint has abuse controls and rate limits.

**Booking administration**
- Inquiry inbox, triage, clarifications and internal notes.
- Separate editable booking draft prepopulated from the inquiry.
- Original request remains immutable.
- Configurable offer, internal approval and organizer-acceptance steps.
- Explicit authorized confirmation with atomic space/resource reservation.
- Manual booking creation without a public inquiry.
- Cancellation, withdrawal, expiry, rescheduling and controlled amendment/change order.
- Requested, approved and delivered resource/service values remain distinct.

**Commercial configuration**
- Versioned service/equipment catalogues and effective-dated price lists.
- Configurable duration/quantity/add-on/discount/surcharge/tax rules.
- Immutable quotation/offer snapshots.
- Prices and policies are organization-owned configuration. Historical GHB prices are not treated as current policy until confirmed.

**Venue fulfilment**
- Venue-side preparation/fulfilment tasks for booked resources and services.
- Rehearsal, setup and teardown schedule blocks.
- Venue-side status, issues and completion confirmation.
- Task ownership and assignment to venue staff/teams.
- Booking confirmation and operational communications by email through a provider abstraction.

**Operational foundation**
- Audit trail, notifications and background jobs.
- Booking/resource availability conflict protection at database and service layers.
- Backups, restore procedure, health checks and deployment runbook before production use.

#### Explicitly excluded from Release 1 by default

- Guest Registry and event attendee records.
- Guest invitation campaigns, personalized RSVP links and response history.
- Seating plans and guest-to-seat/zone allocation.
- Guest portal and guest-facing wayfinding.
- Admission QR credentials and check-in/attendance scanning.
- Organizer-side external protocol/permit coordination records.
- Full event-day organizer cockpit and guest/staff operational workspaces.
- Ticket sales/payment processing.
- Digital signatures and legal contract automation unless separately required.

These are not permanently excluded from Eventor. They are optional capabilities planned for later releases and may be enabled for a particular event when the relevant organization has responsibility and a clear use case.

### Release 2 — Organizer event workspace

Release 2 adds an operational event that can be created independently or linked to a confirmed venue booking.

- Organization-owned events/sessions and optional event capabilities.
- Persistent Guest Registry and event participation records.
- Event-specific imports, duplicate review and supervised merge.
- Invitation issuance/delivery and secure invitation-link lifecycle.
- Guest self-service and staff-recorded RSVP.
- RSVP deadlines, reminders and append-only response history.
- Booking-event linking under explicit cross-organization collaboration.
- Approved venue-space snapshots, event-owned allocation resources and provenance.
- Optional event responsibilities and external prerequisites.

The organizer can run this capability in its own organization. A venue provider sees only booking/venue information and explicitly shared task projections.

### Release 3 — Seating, admission and live operations

- SVG floor-plan editor and versioned event-space maps.
- Manual, category-based and solver-assisted seating/allocation.
- Hard/soft constraints, locks, proposals, diagnostics and human-approved commits.
- Guest-safe map and wayfinding projections.
- Admission QR credentials distinct from invitation links.
- Check-in PWA, attendance corrections and station management.
- Live Event Operations Cockpit and role-specific staff workspaces.
- Realtime outbox/WebSocket delivery, alerts, activity timeline and reports.

### Later capabilities

Offline check-in, advanced analytics, additional notification channels, expanded integrations, advanced scheduling/resource optimization and other capabilities can follow after the operational baseline is stable.

## 3. Core release-1 data boundary

A venue booking may store:
- Booking requester/customer identity and business contact.
- Contracting party and payer snapshots where required.
- Actual event organizer name/contact where supplied and needed for the venue contract.
- Event title/type, requested date/time/duration and expected attendance where relevant.
- Requested venue/services/resources, approved commitment, quote and delivery status.
- Venue-side operational notes and restricted commercial information.

It does **not** need:
- Attendee names and contact points.
- Invitation URLs/tokens or delivery history.
- RSVP answers or response notes.
- Individual seating assignments or guest category/relationship data.
- Admission QR credentials or check-in history.
- Organizer-only documents and external protocol details.

Collect additional information only when needed for a configured venue service or validated contractual/facility rule. The platform must distinguish a venue's operational need (for example expected aggregate attendance) from organizer event-management data.

## 4. Release-1 workflow acceptance scenarios

1. A visitor submits a venue inquiry without creating an account or supplying a guest list.
2. A booking administrator reviews the inquiry and creates a separate editable draft. Original inquiry values remain unchanged.
3. Staff map requested choices to approved venue resource/service lines; a form selection alone does not reserve inventory or create a charge.
4. The system calculates a quote from a published price revision; later price changes do not rewrite the issued offer.
5. An authorized approver issues/approves the offer and the organizer accepts if configured.
6. Confirmation atomically reserves all required spaces and resources. A conflict commits none of the booking/reservation changes.
7. Setup, rehearsal, event and teardown can occupy separately scheduled time blocks.
8. Venue staff fulfill only the venue-side tasks assigned to them; every important state change is auditable.
9. Booking can be cancelled, amended or rescheduled without overwriting the original confirmed snapshot.
10. The complete booking flow succeeds with no operational-event, event-guest, invitation, RSVP, allocation, credential or check-in records.
11. The booking's organizer/customer does not automatically receive a user account or tenant membership.
12. If an organizer later uses Eventor, a separate operational event can be explicitly linked through a scoped collaboration grant and immutable venue-space snapshot.
13. Guest, invitation, RSVP and organizer-only prerequisite data remain inaccessible to the venue provider unless a narrowly scoped task grant explicitly permits a required projection.

## 5. GHB validation gates

Before Release 1 is configured for production, GHB must confirm:
- Which rooms/spaces may be publicly rented and their approved capacities.
- Space/ancillary-room relationships and access limitations.
- Current equipment and service inventory and what is included in base rent.
- Current price list, taxes, discounts and weekend/holiday rules.
- Current opening/service hours, setup/rehearsal/teardown constraints and booking lead times.
- Who can prepare offers, approve discounts and confirm bookings.
- Which information the venue legitimately needs from the organizer and how long it should be retained.
- Public form labels, options, mandatory fields and conditional behavior.
- Email sender/domain, reverse proxy/public hostname and data-retention policy.

Do not seed unconfirmed historical prices, capacities or protocols as enforced production rules.

## 6. Technical sequencing

1. Resolve accepted organization ownership, collaboration and database integrity designs (ADR 0006; Issues #12/#13).
2. Produce the first executable PostgreSQL migrations and validate them against a supported PostgreSQL version (Issue #2).
3. Complete OpenAPI v0.3 contract coverage and validation (Issues #3/#17).
4. Agree Release-1 role/permission matrix and approval authority.
5. Build foundation: auth, organization membership, configuration, audit, API contracts and test harness.
6. Build booking/resource workflows in vertical slices.
7. Run a GHB pilot using synthetic/demo data, then perform approved production onboarding.
8. Implement organizer event operations and guest capabilities as independently activatable follow-on releases.

The existing v0.2 backlog remains a source list; its phase labels need remapping to this release boundary after the MVP scope is approved.
