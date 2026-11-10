# ADR 0005: Invitations, RSVP responses and attendance are separate lifecycles

- **Status:** Accepted
- **Date:** 2026-11-10
- **Related:** [Issue #6](https://github.com/TeraflopsBH/eventor/issues/6), [ADR 0004](0004-optional-event-operations-scope.md)
- **Design detail:** [RSVP and Invitation Design v0.3](../implementation-design/v0.3/RSVP_AND_INVITATION_DESIGN_v0.3.md)

## Context

The v0.2 schema stores one `rsvp_status` on `event_guests` and uses general guest credentials for portal/admission access. This is insufficient for the agreed workflows: guests can respond through personalized links, staff can record responses received by phone/in person/email/writing/representatives, and actual attendance is a separate physical event.

Eventor also serves venue providers that may not organize the event or need any guest-level information. Guest operations must therefore be enabled only within the appropriate event scope and responsibility assignment.

## Decision

1. Invitation issuance/delivery, invitation-link validity, RSVP response, event participation/eligibility and physical attendance are distinct state dimensions.
2. RSVP responses are append-only history. The current response is a projection, not the only retained record.
3. Guest self-service RSVP uses a high-entropy, opaque, revocable invitation capability scoped to one event guest. It is not an admission QR and does not require a guest account by default.
4. Link resolution is non-destructive. GET requests, preview bots and email security scanners cannot submit a response or consume the invitation.
5. Staff may record outside-channel responses without a guest link/email. Capture records source, received time, system recording time, authenticated operator and optional restricted note. Corrections append history.
6. Guest response changes are governed by a versioned event RSVP policy, deadline and permissions; late staff overrides require a reason and audit.
7. RSVP/guest capabilities are optional modules. A venue-only booking requires no operational event or guest records. Guest data belongs to the assigned event-operating organization and is not visible to a venue provider merely because it supplied the space.
8. Public responses use allow-listed personal projections; no public guest directory or cross-guest access exists.

## Consequences

- The v0.2 `event_guests.rsvp_status` field must be separated from invitation and waitlist/eligibility state in a successor schema.
- A dedicated invitation record, link-credential lifecycle and response-history model are required.
- Notification delivery records need a reliable relationship to invitations.
- Public and staff API contracts require separate commands/projections and scoped authorization.
- RSVP implementation must not be coupled to check-in, seating or venue booking.
- The current v0.2 schema and OpenAPI files remain unchanged historical drafts; changes belong in a reviewed successor revision.
