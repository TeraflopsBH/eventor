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
- [x] Cross-organization delegated task projection/status command succeeds only with an active grant naming the exact task ID and a local `task.perform` role permission; its audit row records the performer in the event owner’s tenant.
- [ ] Expired grant blocks new access without erasing historical records.
- [x] Revoked grant blocks new booking links, event snapshots, session bindings and snapshot child additions without deleting historical records.

## Global identity and authentication boundary
- [x] General runtime cannot SELECT, INSERT or update global user identity/password-hash rows directly.
- [x] Authentication role can resolve users and their organization memberships but cannot read venue/booking/event business data or mutate memberships.
- [x] Tenant-filtered member-profile view exposes only the active organization’s membership/profile projection.
- [x] Database-backed staff sessions store only SHA-256 hashes of opaque session/CSRF tokens, bind to one user/organization/membership tuple, expire and revoke server-side, and are hidden from runtime/worker roles.
- [x] Authentication-role CI checks cover session/rate-limit table privileges; API tests cover Argon2id login, origin allow-list, CSRF double-submit, active membership lookup and revocation.

## Cross-organization grant and RLS lifecycle
- [x] Grantor and grantee can see their own shared grant row; unrelated tenant cannot.
- [x] Only an active member of the grantor organization can propose a grant.
- [x] Proposal, first grant revision and audit event are written atomically.
- [x] Only an active member of the grantee organization can accept a grant.
- [x] Repeated acceptance by the same actor is idempotent and does not duplicate the audit record.
- [x] Booking-event link ending/revocation and venue snapshot share revocation/expiry require an active local membership plus reason code and write one lifecycle audit record.
- [x] Grantee cannot invoke the grantor-side revocation command.
- [x] Grantor can revoke; grantee retains historical visibility while the grant is marked revoked.
- [x] Revoked grant blocks new venue snapshot copies, booking-event links, session bindings and new snapshot child rows.
- [x] Venue snapshot share is constrained to grant scope, validity window and exact published source revision/content hash.
- [x] Provider-approved layer/resource IDs must belong to the exact source revision/venue; duplicates and foreign IDs are rejected.
- [x] Copied snapshot layers must match approved source layers; each copied object must map to the exact copied layer for its source object's layer; copied resources must match approved pool/unit IDs.
- [x] Recipient RLS exposes only approved source rows while the share and grant are active.
- [x] A read-only `venue.snapshot.read` grant can SELECT its approved source revision but cannot create/use an event snapshot.
- [x] Revocation hides provider-owned source rows from the recipient but retains its already-copied event-owned snapshot.

## Venue hierarchy
- [x] Valid organization → venue → building → level → space accepted.
- [ ] Space pointing to a building from a different venue rejected.
- [x] Space pointing to a level from another building rejected.
- [x] Space with a level but no building rejected.
- [x] Cross-organization hierarchy reference rejected.

## Configuration integrity
- [x] Catalogue revision includes option and the option's own revision.
- [x] Option revision belonging to another stable option rejected.
- [x] Option from a different catalogue revision rejected.
- [ ] Retired option remains historically readable but cannot be newly selected where policy forbids it.
- [x] Published catalogue and option revisions reject UPDATE/DELETE.
- [x] Published catalogue membership rejects new child rows.
- [x] Published form revisions and form-to-catalogue bindings reject mutation.
- [x] Published venue-space revisions and spatial layer/object children reject mutation or late additions.
- [x] Concurrent revision publication and child insertion use independent connections; the insert waits on the parent lock and is rejected after publication commits.
- [ ] Published price-list, cancellation-policy, RSVP-policy, notification-template and event-capability revisions have dedicated mutation regression cases.
- [x] Cancellation effects reject an unpinned policy revision and preserve the explicit NULL/no-policy booking snapshot.

## Space reservations
- [x] Adjacent half-open intervals (10:00–11:00 and 11:00–12:00) both succeed.
- [x] Identical/overlapping intervals for the same room cannot both be active.
- [x] A released space hold cannot be revived; a new hold cannot be inserted with an already-expired deadline.
- [x] Runtime and worker roles cannot UPDATE/DELETE space-time block rows directly; lifecycle changes use controlled commands.
- [x] Accepted draft resource and space holds are converted atomically to confirmed booking reservations through a permission-gated command; retries do not duplicate occupancy or audit history.
- [x] Cancelled booking reservations are released only by caller-selected IDs (resource and/or space rows); mixed invalid IDs are rejected atomically, partial release leaves unselected rows intact, and retries emit no duplicate audit.
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
- [x] Same discrete unit cannot be reserved for overlapping time.
- [ ] Different units in a pool can be reserved concurrently when capacity allows.
- [x] Pooled capacity is never exceeded under concurrent requests.
- [x] A booking resource line’s peak simultaneous quantity cannot be exceeded across separate pools.
- [x] Individually tracked unit reservations are included in the booking resource line quantity limit; a fifth overlapping unit is rejected when the requested quantity is four.
- [x] Pooled and individually tracked reservations share one aggregate pool-capacity invariant.
- [x] Pooled reservation idempotency compares the booking resource line as part of the payload.
- [x] Disjoint sub-interval reservations that both intersect a long requested interval are evaluated by peak simultaneous quantity, not incorrectly summed across the entire interval.
- [x] Adjacent half-open pool intervals do not count as simultaneous.
- [x] Expired pooled and individually tracked holds are expired by the worker; pool capacity is reclaimed and the same discrete unit can be reserved again.
- [ ] Resource line request/approval/delivery values remain separate from actual reservation records.

## Event cancellation, postponement and guest communications
- [x] Cancellation after invitations were delivered preserves invitation records, RSVP answers (accepted/tentative/declined/pending), completed-session state and attendance history.
- [x] Cancelling an event revokes outstanding invitation links, suppresses queued/failed invitation sends, preserves already delivered history, and rejects new invitation, link, delivery and RSVP activity.
- [x] Cancellation notification audience snapshots include all active invitees, including declined and unanswered invitees; queued campaign recipient sets and audience rules are immutable.
- [x] Postponement preserves original RSVP answers on the original schedule revision, retires old links/pending sends, and allows new invitation/RSVP activity only against the replacement schedule.
- [x] New postponement and reschedule requests both require a pinned replacement schedule revision; migration preflight stops rather than inventing schedule data for legacy postponed requests without one.
- [x] Postponement reconfirmation audience snapshot selects accepted/tentative invitees and excludes declined/unanswered invitees.
- [x] A provider booking-disruption notice alone does not cancel/postpone the organizer-owned event or create a guest-notification campaign; an explicit organizer decision is required.
- [x] Event decision kind must match its executed change request; notification campaign purpose and published template must match the decision.
- [x] Organizer event-change submission checks active membership, event-scoped initiation/postponement permission, current event revision and one unresolved request per event.
- [x] Approval/rejection and execution are separate permission-gated commands; execution records the decision, status history, session outcomes, audit event and transactional notification outbox atomically.
- [x] Cancellation, postponement and rescheduling commands enforce the event decision/status mapping; stale revisions, missing event scope and cross-tenant actors are rejected.
- [x] Runtime API route tests cover fail-closed staff authentication and CSRF/origin checks, private-reason encryption, Idempotency-Key replay/conflict and custom-audience input validation.
- [x] Worker-only tenant-scoped outbox processing prepares a fixed, reviewable campaign preview from accepted/tentative, active-invitee, previously-invited or custom audience rules; verified permitted contact snapshots remain encrypted and exclusions are retained.
- [x] Worker processing is idempotent, locks outbox rows with SKIP LOCKED, retries with bounded backoff and dead-letters after the configured attempt ceiling; worker tests prove no delivery attempts are created during preparation.
- [x] Organizer campaign review returns the fixed recipient snapshot, channel totals, exclusion totals and published template content without exposing encrypted contact values.
- [x] Campaign confirmation requires event-scoped send permission, a current matching event decision, a complete recipient-count snapshot and an active published template; confirmation is attributed in audit history.
- [x] Runtime cannot directly mutate campaign/recipient/exclusion/delivery tables; campaign confirmation does not queue delivery or create delivery attempts.
- [ ] Email/SMS delivery-provider adapter, callback handling and delivery retries.

## Append-only and issued business history
- [x] Runtime role lacks UPDATE/DELETE privileges on append-only history tables.
- [x] Table triggers also reject UPDATE/DELETE when executed by the table owner.
- [x] Booking draft revisions reject UPDATE/DELETE.
- [ ] Invitation revisions reject UPDATE/DELETE in a dedicated regression test.
- [x] Issued offer terms reject mutation; only one terminal offer decision transition is permitted.
- [x] Booking-event link grant provenance is written to audit history and substantive link fields cannot be rewritten.
- [x] Booking-event link and venue snapshot share lifecycle transitions are one-way and auditable.

## Optional modules and responsibility
- [ ] New event has no guest/invitation/RSVP/check-in/prerequisite/cockpit modules unless explicitly enabled by its event preset or configuration.
- [ ] Booking-only flow is possible with no event/guest records.
- [ ] Module-specific routes return a safe disabled/not-enabled error when capability is off.
- [ ] RSVP does not depend on check-in or seating.
- [ ] Check-in does not require accepted RSVP.
- [x] Delegated task projection/status operations expose only an allowlisted task view and require a task-specific cross-organization grant plus local role permission.
- [ ] Each assigned task has accountable/performed party and scoped visibility for event-owner management and every optional task projection.
- [ ] Venue provider cannot read organizer guest/RSVP data through booking or task links unless a narrowly scoped grant authorizes the exact projection.

## Execution requirements
Run against the supported PostgreSQL version with the non-owner application role. Concurrency tests must use multiple independent connections/processes. Record migration version, server version, test command and output in CI artifacts.
