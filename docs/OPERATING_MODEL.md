# Eventor operating model

This document describes how Eventor can support venue providers, event organizers and collaborative operations without making every deployment use every module.

See [ADR 0004](decisions/0004-optional-event-operations-scope.md) and [Issue #8](https://github.com/TeraflopsBH/eventor/issues/8).

## Three common operating profiles

### Venue provider

A venue provider rents spaces and supplies venue-side services. Its normal Eventor workflow is:

1. Receive a simple inquiry.
2. Review requested date, time, venue, expected attendance where needed, equipment/services and contact details.
3. Prepare a booking draft, offer or approval.
4. Confirm the booking and reserve venue/resources.
5. Prepare and deliver the agreed venue-side services.
6. Close/cancel/amend the booking as appropriate.

This workflow does **not** require creating a full operational event. It does not require the provider to manage the renter's guest registry, invitations, RSVP, seating, admission check-in or external organizer protocols.

A provider may ask for a small amount of operational information where it is needed for its own venue services, risk controls, contractual requirements or facility rules. That is not the same as taking responsibility for organizing the event.

### Event organizer

An organizer uses Eventor to coordinate the event itself. It can enable the capabilities that apply to the event, such as guest records, invitations/RSVP, seating, check-in, prerequisite tracking, live operations, staff tasks and reporting.

The organizer does not need to enable every capability for every event. A small lecture may need registration and attendance but no assigned seating; a private meeting may need a room booking only.

### Hybrid or collaborative event

A venue provider may operate the booking and venue-side tasks while an organizer operates guest and event workflows. In other cases, the venue may provide a paid service such as registration staff or seating assistance.

Eventor should allow each task/module to have an explicit owner and participants rather than assuming all operations belong to one organization.

## Keep party identities separate

These roles must not be collapsed into a single "organization" field:

| Role | Meaning |
|---|---|
| Venue provider | Supplies the physical space and venue-side services |
| Booking customer/requester | Initiates or manages the booking request |
| Contracting party | Enters the agreement and may be the payer |
| Event organizer | Actually organizes the event and its programme |
| Operational operator | Performs one or more specific tasks |

One organization may hold several roles, but the records must allow them to differ. For example, an event agency might submit an inquiry for a client, the client may sign/pay, and a third party may organize the programme.

## Module activation and dependencies

Organization profile establishes defaults. Each booking or event can override those defaults and enable only needed capabilities.

| Capability | Venue-provider default | Organizer use |
|---|---|---|
| Inquiry, quote and booking | On | Optional |
| Venue/resource calendar | On | Optional |
| Venue setup/service delivery | On as applicable | Optional |
| Guest registry and event participation | Off | Optional/on as needed |
| Invitations and RSVP | Off | Optional/on as needed |
| Seating and guest allocation | Off | Optional/on as needed |
| Guest portal / wayfinding | Off | Optional/on as needed |
| Admission QR and check-in | Off | Optional/on as needed |
| External prerequisites | Off | Optional/on as needed |
| Live event operations cockpit | Off | Optional/on as needed |
| Event reports and communications | Off | Optional/on as needed |

These are defaults, not locked restrictions. A venue provider may activate registration/check-in as a contracted service, and an organizer may have no need for seating.

Module dependencies should remain narrow:
- Guest RSVP requires event participation and a response channel, but not seating.
- Seating can work with event participants or a deliberately modeled allocation subject set; it does not require invitation delivery.
- Check-in requires an admission/attendance subject and credential or authorized manual lookup; it does not require seating or RSVP.
- External prerequisites can exist independently of guest management and must remain optional.
- A venue booking requires no operational-event conversion.

## Responsibility assignments

For every enabled task or module, the event workspace should be able to identify:
- Accountable party.
- Performing party/person/team.
- Approver, if required.
- Informed parties.
- Scope of information each party may see.
- Due date/readiness rule, if applicable.
- Whether it is not applicable or managed outside Eventor.

The venue provider remains responsible for its own facility, resource availability, house rules and contracted venue-side services. The organizer is responsible for the event tasks assigned to it. Eventor records this division; it does not decide legal liability or replace contractual/regulatory advice.

## Example: independent conference at GHB

GHB acts only as venue provider. A conference organizer books the large hall.

**GHB needs in its booking workspace:** organizer/customer name and booking contacts, date/time and duration, selected hall, expected attendance where relevant to venue policy, requested setup/equipment/services, rehearsal/setup/teardown needs, agreed price and booking status.

**Not required for GHB's booking workflow:** attendee names, guests' emails/phones, invitation tokens, RSVP results, guest-to-seat allocations, admission scans, organizer's police coordination documents or the full conference operations cockpit.

The conference organizer can manage those independently. If the organizer later chooses Eventor, it can use its own Eventor deployment or receive explicit scoped access to agreed modules/data. That access is never automatic.

## Product boundary

Eventor is both:
- A venue booking/resource management system when that is all the customer needs.
- A configurable event operations platform when the customer is organizing or operating the event.

This is a product configuration and responsibility model, not a paywall or separate codebase.
