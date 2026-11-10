# PostgreSQL integrity and concurrency test matrix — v0.3

This matrix tracks executable PostgreSQL integration coverage and remaining gaps for the v0.3 successor schema. A checked item has a corresponding assertion in the current CI suite; unchecked items remain future test work. API authorization cases require route-level tests and are not proven by database constraints alone.

## Tenant relationships
- [x] Same-organization person merge target accepted.
- [x] Cross-organization person merge target rejected.
- [ ] Same-organization credential replacement accepted.
- [ ] Cross-organization credential replacement rejected.
- [x] User actor with active membership in owning organization accepted.
- [ ] User with no membership in owning organization rejected.
- [ ] Member without operation permission rejected by API authorization.
- [ ] Cross-organization delegated action succeeds only with active, matching grant and task scope.
- [ ] Expired/revoked grant blocks new access without erasing historical records.

## Venue hierarchy
- [ ] Valid organization → venue → building → level → space accepted.
- [ ] Space pointing to a building from a different venue rejected.
- [x] Space pointing to a level from another building rejected.
- [x] Space with a level but no building rejected.
- [x] Cross-organization hierarchy reference rejected.

## Configuration integrity
- [x] Catalogue revision includes option and the option's own revision.
- [x] Option revision belonging to another stable option rejected.
- [x] Option from a different catalogue revision rejected.
- [ ] Retired option remains historically readable but cannot be newly selected where policy forbids it.
- [ ] Published form/catalogue revision cannot be mutated through runtime permissions.

## Space reservations
- [x] Adjacent half-open intervals (10:00–11:00 and 11:00–12:00) both succeed.
- [x] Identical/overlapping intervals for the same room cannot both be active.
- [ ] Overlap is rejected even when one claim originated as a temporary hold and the other as a booking reservation.
- [ ] Released/cancelled/expired interval no longer blocks a new reservation.
- [ ] Hold extension that creates a conflict is rejected atomically.
- [ ] Booking with multiple spaces/times commits all or none.
- [ ] Concurrent overlapping transactions using separate database connections result in at most one active reservation.
- [ ] Reschedule conflict leaves the prior confirmed schedule unchanged.

- [ ] A space-time block has exactly one typed, tenant-safe origin reference.
- [ ] A hold-to-booking conversion retains continuous exclusion protection under concurrent confirmation/expiry.
- [ ] Expiry worker and reservation command serialize on the same space lock; no stale held row can block indefinitely.

## Equipment/personnel
- [ ] Same discrete unit cannot be reserved for overlapping time.
- [ ] Different units in a pool can be reserved concurrently when capacity allows.
- [x] Pooled capacity is never exceeded under concurrent requests.
- [ ] Disjoint sub-interval reservations that both intersect a long requested interval are evaluated by peak simultaneous quantity, not incorrectly summed across the entire interval.
- [x] Adjacent half-open pool intervals do not count as simultaneous.
- [ ] Expired holds do not permanently consume capacity.
- [ ] Resource line request/approval/delivery values remain separate from actual reservation records.

## Optional modules and responsibility
- [ ] New event has no guest/invitation/RSVP/check-in/prerequisite/cockpit modules unless explicitly enabled by its event preset or configuration.
- [ ] Booking-only flow is possible with no event/guest records.
- [ ] Module-specific routes return a safe disabled/not-enabled error when capability is off.
- [ ] RSVP does not depend on check-in or seating.
- [ ] Check-in does not require accepted RSVP.
- [ ] Each assigned task has accountable/performed party and scoped visibility.
- [ ] Venue provider cannot read organizer guest/RSVP data through booking or task links unless a narrowly scoped grant authorizes the exact projection.

## Execution requirements
Run against the supported PostgreSQL version with the non-owner application role. Concurrency tests must use multiple independent connections/processes. Record migration version, server version, test command and output in CI artifacts.
