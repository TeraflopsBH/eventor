# ADR 0004: Event operations are optional and responsibility-scoped

- **Status:** Accepted
- **Date:** 2026-11-10
- **Related:** [Issue #8](https://github.com/TeraflopsBH/eventor/issues/8)

## Context

Eventor serves more than one organizational operating model. A venue provider (for example, GHB when renting a hall to an independent conference organizer) may only need to receive and process inquiries, reserve spaces/resources, issue offers, confirm bookings and prepare the venue. The renter is ordinarily responsible for organizing the event itself.

A venue-provider deployment should not be forced to collect guest lists, issue invitations, operate RSVP, assign guests to seats, scan admission QR codes, manage organizer-side protocols or run a full event-day cockpit simply because a customer booked a venue.

The product must also support organizations that are themselves event organizers, as well as cases where venue and organizer explicitly share or delegate operational work.

Implementation Design v0.2 already establishes an important foundation: a confirmed venue booking is not automatically an operational event, and conversion is optional. This ADR makes the operating-scope distinction explicit across the product.

## Decision

### 1. Separate venue booking from event organization

Keep these concepts distinct, even when the same legal entity performs more than one role:

- **Venue provider:** makes the venue and its own resources/services available.
- **Booking customer/requester:** submits or manages the booking inquiry.
- **Contracting party:** entity that enters into the venue agreement and may be responsible for payment.
- **Event organizer:** entity actually organizing the event.
- **Operational operator:** party or parties performing specific event tasks.

Do not assume these roles are the same organization or person. A booking-only record may exist without an Eventor operational-event record.

### 2. Operating profiles are defaults, not rigid product tiers

Each organization has a configurable default operating profile:

- **Venue provider:** booking and venue-side service delivery are the default scope.
- **Event organizer:** event planning and operational modules may be enabled by default.
- **Hybrid:** the organization may operate as venue provider for some bookings and event organizer for others.

Profiles are configuration presets, not subscription or product tiers. An event/booking can override the organization's defaults.

### 3. Activate operational modules only when needed

Operational capabilities are independently enabled within the applicable event scope. Examples include:

- Guest registry linkage and event participation.
- Invitations and RSVP.
- Seating, spatial allocation and guest wayfinding.
- Admission credentials and check-in.
- External prerequisites and organizer coordination checklists.
- Event-day cockpit, staff workspaces, alerts and timeline.
- Event communications, reports and operational documents.

No unrelated module becomes mandatory merely because another is active. Module dependencies must be explicit and minimal. For example, RSVP requires an event participation record and a valid guest response channel; check-in requires an admission subject/credential or an explicitly supported manual lookup path. Neither should be a prerequisite for a venue booking.

### 4. Responsibility is explicit and can be delegated

For each enabled module or operational task, record who is accountable and who performs, approves or is informed. Parties may be the venue provider, organizer, an authorized collaborator or an external party. A task may also be marked not applicable or managed outside Eventor.

Avoid a vague global assumption that "the organization" is responsible for every event task. Responsibility is scoped to a booking/event and task/module, and can be overridden when the arrangement changes.

### 5. Keep data collection proportional to the venue service

For venue-provider-only use, collect only what is reasonably needed to process the inquiry, make the agreement, reserve the venue/resources and deliver the contracted venue services. Guest-level information, invitations, RSVP answers, seating assignments and organizer-side coordination records are not required by default.

If an organizer elects to use Eventor's event modules, the system may collect the additional data needed for those features under the appropriate access, privacy, retention and audit controls.

### 6. Collaboration is explicit

A booking customer or event organizer does not automatically become a tenant, organization member or user of the venue provider's Eventor installation. Cross-organization collaboration requires an explicit invitation or scoped access grant for the relevant booking/event and data projection. No broad tenant access is implied.

### 7. Preserve each party's own venue/facility duties

This operating model does not transfer, waive or determine statutory, regulatory or contractual responsibilities. The venue provider still manages its own venue, resource availability, facility constraints, house rules and contracted venue-side services. The organizer manages the event responsibilities assigned to it by the applicable arrangement. Eventor records operational ownership; it does not make legal determinations or certify compliance.

## Consequences

- A lightweight venue-provider installation can use Eventor as a booking/resource-management system without activating the guest/event-operations lifecycle.
- Organizer deployments can enable the full platform.
- Hybrid events can share work while keeping accountability and visibility explicit.
- Domain modeling must distinguish booking parties and the actual event organizer from the platform tenant.
- Event operations configuration needs organization defaults, event-level overrides, module dependencies and task-level responsibility assignments.
- Public and staff data projections must follow the minimum-necessary principle.
- The v0.2 schema and API are historical drafts and must not be extended ad hoc; a successor design revision must specify the operating-scope model before implementation.
