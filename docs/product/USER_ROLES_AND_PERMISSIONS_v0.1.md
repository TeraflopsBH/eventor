# Eventor user roles and permission model — v0.1

**Status:** accepted baseline role and permission model; organization-specific assignments and thresholds remain subject to validation  
**Date:** 2026-11-10  
**Related:** [MVP Scope v0.1](MVP_SCOPE_v0.1.md), ADR 0004 and ADR 0006

Roles are permission bundles, not hardcoded job titles. An organization may create role presets, but the underlying permission catalogue and server-side checks remain authoritative. A user may hold different roles in different organizations or events. UI visibility alone never grants permission.

## 1. Principals and operating parties

Distinguish:
- Platform operator/administrator.
- Organization member.
- Venue provider.
- Booking customer/requester (may be an external contact with no account).
- Contracting party/payer (may differ from requester).
- Event organizer (may be an external party or a separate Eventor organization).
- External party/authority/vendor with no Eventor account.
- Service principal/background worker.

An external renter does not need a user account to submit an inquiry, accept a public offer through a scoped link if that workflow is enabled, or receive booking communications.

## 2. Proposed Release-1 roles

| Role | Typical permissions | Restrictions |
|---|---|---|
| Platform administrator | Platform configuration, tenant lifecycle, system health and platform-level support | Technical administration does not automatically grant guest-record, confidential-note or commercial-data access |
| Organization owner | Organization settings, memberships, operating profile, policy and high-level configuration | Cannot bypass audit or scope rules |
| Organization administrator | Staff/roles, venue configuration, published forms/catalogues and organization workflows | Sensitive operations may require additional approval |
| Booking manager | Inquiry inbox, clarification, booking drafts, quotes/offers, amendments and booking communication; review/coordinate cancellation requests and execute approved booking cancellations where granted | Cannot approve own restricted discount/exception or cancellation request unless policy explicitly permits |
| Booking approver / finance | Approve offers, discounts, exceptions and financial commitments within configured limits; approve/reject booking cancellation requests and their commercial consequences within assigned authority | No general access to guest/event operations unless separately assigned |
| Venue coordinator | Space calendar, setup/rehearsal/teardown, venue task assignments, readiness and issue handling; may initiate a venue-side cancellation for facility/service unavailability when explicitly granted | Only venue-side operational and booking data; cannot independently waive fees/refund terms unless separately authorised |
| Resource / technical coordinator | Equipment/personnel availability, service preparation, technical fulfilment and issue status | No unrelated commercial or personal data |
| Management read-only | Approved dashboards, aggregate reports and booking status | No write actions; field-filtered data |
| Auditor / compliance read-only | Permissioned audit and configuration history | Restricted, logged, read-only |
| External booking requester | Public inquiry, explicitly allowed offer/booking actions, submit a permitted cancellation request and view its limited status through a scoped secure action link | No tenant membership, approval authority, immediate cancellation right unless the pinned booking policy explicitly allows it, or access to internal notes/resources |

## 3. Later organizer/event roles

These roles are not required for a venue-only Release 1. They become available when the organization activates event operations:

| Role | Typical permissions |
|---|---|
| Event owner / event administrator | Event scope, capability activation, event policies and responsibility assignment; initiate/approve/execute event cancellation or postponement only with the corresponding scoped permissions |
| Guest coordinator | Guest Registry linkage, event participation, import, invitations and RSVP administration; prepare cancellation audience previews and communications when assigned |
| RSVP operator / reception | Staff-record response entry and permissioned response lookup |
| Seating coordinator | Venue snapshot use, allocation rules and manual/solver proposal review |
| Check-in operator | Admission validation and attendance recording using minimum necessary guest fields |
| Zone/floor coordinator | Only assigned operational map layers, zones and guest/task data |
| Event communications operator | Prepare/send event and cancellation notifications only for assigned events/audiences under an explicit task grant |
| Event operations manager | Cockpit, event alerts, task coordination and authorized interventions |
| External collaborator | Only the booking/event/task projection granted to its organization and role |

## 4. Permission design requirements

- Enforce permissions on every server operation and data query.
- Scope permissions by organization, venue, booking, event, space, station or assigned task where appropriate.
- Separate read/list, create, update, archive, approve, publish, export, grant/revoke and override permissions.
- Require explicit permissions for price/discount overrides, booking confirmation, guest export, RSVP deadline override, allocation approval/publication and attendance correction.
- Distinguish a user's organization membership from permission to perform a particular action.
- A collaboration grant authorizes only the named external organization/scope/projection; the user's membership and role in the grantee organization are still checked.
- External customer/organizer contact data stored in a booking does not grant access to the underlying tenant.
- Read/export of confidential or restricted information is audited as configured.
- Service jobs use a service principal identity and narrowly scoped permissions, not a shared human administrator account.

## 4.1 Cancellation authority is explicit

Role presets are defaults; the permission catalogue and booking/event policy determine actual authority.

| Scope | Initiate/request | Approve/reject | Execute/send |
|---|---|---|---|
| Booking customer | Authorised external contact may submit a cancellation request through a scoped action link | No authority by default | No direct effective cancellation unless the booking's pinned policy explicitly enables self-service |
| Venue booking | Venue coordinator or booking manager may initiate when granted | Booking approver/finance or configured authority | Designated booking manager/service after approval; emergency execution is a separate explicit permission and requires review |
| Organizer event | Event owner/admin may initiate cancellation or postponement | Event approver/owner under organizer policy | Designated event operator; guest campaign send permission is separately checked |
| Delegated guest communications | Named collaborator/operator may prepare the assigned campaign | Organizer's policy/approval rules still apply unless explicitly delegated | Only the assigned event/audience/action projection; no general guest-list access |

Suggested fine-grained permissions (names to align with the successor catalogue) include `booking.cancellation.request`, `booking.cancellation.review`, `booking.cancellation.approve`, `booking.cancellation.execute`, `booking.cancellation.override`, `event.cancellation.initiate`, `event.cancellation.approve`, `event.cancellation.execute`, `event.postponement.manage` and `event.cancellation.notifications.send`.

Approval and execution may be separated to enforce dual control. Self-approval is disallowed for configured high-risk cancellation or commercial exceptions unless a documented organization policy explicitly permits it. Technical platform administration does not imply business cancellation authority.

## 5. Approval authority

The platform should support configurable approval chains and thresholds. Proposed defaults for a venue-provider deployment:
- Booking manager prepares the draft/offer.
- Authorized booking approver confirms pricing/discount exceptions.
- An authorized booking confirmer commits the reservation after availability is rechecked.
- A separate venue/resource coordinator owns setup and fulfilment task status.
- Self-approval is disallowed for configurable high-risk actions unless a documented organization policy permits it.

The actual GHB role names, limits, approval chains and separation-of-duties requirements must be confirmed by GHB. These are not assumed policies.

## 6. Test cases

- User in organization A cannot list/read/write organization B resources without an active scoped grant.
- Organization member with no booking permission cannot approve or confirm a booking.
- Booking manager cannot apply a discount beyond their threshold.
- Management read-only cannot mutate a booking.
- Platform technical administrator cannot read restricted guest notes merely by virtue of technical administration.
- Venue coordinator cannot access organizer guest lists or RSVP responses by default.
- External collaborator can access only the projection and task scope granted to its organization.
- Revoking a grant prevents new operations immediately; historical audit remains available to authorized owners.
- Service principal cannot invoke human-only approval actions unless a specific machine permission is granted and the workflow explicitly permits it.
