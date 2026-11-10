# Successor PostgreSQL schema design — v0.3

**Status:** proposed logical schema baseline; not executable DDL
**Database target:** PostgreSQL 18 (latest supported 18.x minor in CI/deployment; PostgreSQL 19 remains a development release at this design date)  
**Date:** 2026-11-10  
**Depends on:** PR #19 / Issue #13, ADR 0004–0006, RSVP & Invitation Design v0.3, Cancellation & Event Disruption Design v0.3, accepted MVP and role model  
**Historical source:** `docs/implementation-design/v0.2/eogp_schema_v0.2.sql` (read-only reference)

This document defines the successor relational model before writing executable migrations. It does not alter the v0.2 snapshot and does not claim PostgreSQL validation. Names are proposed; exact column types, constraints and migration mechanics belong in the DDL review.

## 1. Non-negotiable invariants

1. Every tenant-owned row has one explicit owner `organization_id`.
2. Same-organization relationships use composite foreign keys including `organization_id`; UUID equality alone is insufficient.
3. Cross-organization collaboration is represented by explicit grants and event-owned snapshots, not by weakening tenant foreign keys.
4. A booking can complete without an operational event, guest, invitation, RSVP, allocation or check-in row.
5. A booking cancellation and an event cancellation are separate aggregates and decisions.
6. Invitation, delivery, RSVP response, participation, admission credential and attendance are distinct lifecycles.
7. Historical customer-visible values and policy revisions are snapshotted; changing current configuration cannot rewrite past agreements or responses.
8. Resource availability is protected transactionally across holds, confirmed reservations, closures, discrete assets and pooled capacity.
9. Actor attribution identifies the acting organization membership or external capability principal; authorization still occurs in the application service.
10. Notifications are asynchronous effects from a transactional outbox. Delivery failure does not reverse a committed business decision.
11. Every important command is auditable, idempotent and concurrency-aware.
12. Optional event capabilities default off and are enabled by versioned configuration, not duplicated booleans.

## 2. Ownership and key conventions

### 2.1 Tenant keys

- Primary keys: UUID.
- Tenant-owned tables: `organization_id UUID NOT NULL`.
- Candidate key: `UNIQUE (organization_id, id)` on every tenant-owned aggregate/table referenced by tenant-scoped FKs.
- Same-tenant FK shape: `FOREIGN KEY (organization_id, parent_id) REFERENCES parent(organization_id, id)`.
- Actor context: `actor_membership_id` references `organization_memberships(organization_id, id)`; system work uses a dedicated service-principal/job identity. Never invent a human actor for a worker.
- External actions use a typed principal/action reference, token hash and audit context; they are not organization memberships.

### 2.2 Cross-organization keys

The data owner remains explicit on each aggregate. A collaboration grant stores grantor organization, grantee organization, scope, purpose, projection, validity and revocation. An event-owned venue snapshot stores source organization, source venue/space revision and content hash as provenance, while the event's usable geometry/layers/resources are copied into rows owned by the event organization.

A foreign key to another tenant's master venue row is not a substitute for a snapshot. Revocation blocks future use/access but does not erase historical snapshots or decisions.

### 2.3 Common record conventions

Use `created_at`, `updated_at`, actor membership/principal, immutable revision numbers and explicit lifecycle timestamps where relevant. Avoid a generic untyped `scope_type + scope_id` when the target is a known relation. Use typed nullable FK columns plus a CHECK, or a dedicated supertype with enforced typed targets.

Use `timestamptz` for instants and explicit IANA timezone identifiers for local schedule interpretation. Time intervals are half-open `[starts_at, ends_at)`; enforce `ends_at > starts_at`.

## 3. Proposed domain table inventory

This is the logical inventory, not a requirement to create every optional table in the first deployment migration. Migration files are grouped by dependency and may create optional-domain tables without requiring their rows to exist.

### 3.1 Identity, tenancy and authorization

| Proposed relation | Purpose / key invariants |
|---|---|
| `organizations` | Tenant root and operating profile defaults |
| `users` | Global login identity; not tenant authorization |
| `organization_memberships` | User-to-organization membership; unique organization/user |
| `service_principals` | Narrow machine/job identities, owner organization and permitted purpose |
| `roles`, `permissions`, `role_permissions` | Permission catalogue and role bundles |
| `user_role_grants` | Membership-based grant with typed nullable scope FKs; exact scope/type consistency |
| `authorization_policies`, `authorization_policy_revisions` | Versioned approval/authority policy where configuration is required |
| `external_action_capabilities` | Purpose-bound external principal/action, token hash, expiry/revocation and target aggregate; never store raw token |

The accepted role catalogue is a permission baseline, not a fixed list of GHB job titles. Business authority is separate from platform technical administration. High-risk booking cancellation/commercial actions may require dual control.

### 3.2 Configuration, branding and documents

| Proposed relation | Purpose / key invariants |
|---|---|
| `brand_profiles`, `brand_profile_revisions`, `brand_assets` | Organization/venue/event typed scope; immutable published revisions |
| `document_templates`, `document_template_revisions` | Typed owner scope and immutable rendered-template revision |
| `config_catalogues`, `config_catalogue_revisions` | Typed scope; published version |
| `config_catalogue_options`, `config_catalogue_option_revisions` | Stable option identity separate from immutable label/value revisions |
| `config_catalogue_revision_options` | Composite identity ensures selected option revision belongs to selected stable option and catalogue |
| `booking_form_definitions`, `booking_form_revisions`, `booking_form_catalogue_bindings` | Versioned public/staff booking intake definitions |
| `booking_price_lists`, `booking_price_list_revisions`, `booking_price_items` | Versioned pricing; currency, tax basis and effective period explicit |
| `cancellation_policies`, `cancellation_policy_revisions` | Booking policy pinned at confirmation; customer-visible terms snapshot separately retained |

A referenced option/template/form/price revision is retired, not deleted or repurposed. Historical records preserve the labels and terms shown at the time.

### 3.3 Venue, space and resource inventory

| Proposed relation | Purpose / key invariants |
|---|---|
| `venues` | Provider-owned venue |
| `venue_buildings` | Composite key includes organization and venue |
| `venue_levels` | Composite key includes organization and building |
| `venue_spaces` | Space hierarchy FK proves venue/building/level consistency |
| `venue_space_revisions` | Immutable master spatial revision |
| `floor_plan_assets`, `spatial_layers`, `spatial_objects` | Revision-owned geometry and semantic layers |
| `source_plan_artifacts`, `source_plan_mappings` | Controlled import provenance; raw sensitive source excluded from Git |
| `resource_types`, `resource_pools`, `resource_units` | Venue-owned fungible pools and individually reservable units |
| `resource_skills` / qualifications (if personnel scheduling is enabled) | Skill/eligibility constraints, not merely commercial line items |
| `venue_space_time_blocks` | One authoritative occupancy relation for active holds, bookings and closures |
| `resource_reservations` | Discrete unit or pooled quantity reservations, tied to source commercial line and time interval |

For venue hierarchy, candidate keys and composite FKs must reject a building from another venue and a level from another building. Resource inventory belongs to the provider; organizer access is only through the approved booking projection or an event-owned snapshot.

#### Space occupancy

`venue_space_time_blocks` is the only authority for space occupancy. It contains organization, space, typed origin, kind, state, interval, optional hold expiry, and audit/idempotency fields. A GiST exclusion constraint with `btree_gist` protects active overlapping intervals for the same organization/space. Expired holds must be transitioned to expired by a worker and opportunistically before reservation commands; a volatile `now()` predicate is not used.

A hold transitioning to a confirmed booking must retain continuous exclusion protection. Confirm/release/reschedule locks affected spaces in stable sorted order and commits all required blocks atomically.

#### Resource capacity

Commercial resource/service lines and physical reservations are separate. Discrete units use per-unit overlap protection. Pooled capacity is serialized by locking the pool row; for every segment of the requested interval, the peak sum of active reservations plus requested quantity must not exceed capacity. A naive sum of every row that intersects the full requested interval is incorrect. Tests must use independent concurrent connections.

### 3.4 Booking and commercial workflow

| Proposed relation | Purpose / key invariants |
|---|---|
| `booking_inquiries` | Immutable public/staff intake; no event/guest dependency |
| `booking_inquiry_attachments`, `booking_inquiry_annotations` | Restricted attachments and staff annotations, distinct from submitted values |
| `booking_drafts`, `booking_draft_revisions` | Separate editable draft and immutable revisions derived from inquiry or staff-created |
| `booking_offers`, `booking_offer_revisions` | Immutable offer and exact customer-visible terms |
| `booking_records`, `booking_confirmed_snapshots` | Confirmed commercial agreement, policy/price/form snapshots and contracting parties |
| `booking_approvals`, `booking_status_history` | Append-only decision/history with scoped actor membership |
| `booking_resource_lines` | Requested, offered/approved and delivered quantities/values; not a reservation itself |
| `booking_party_contacts` | Explicit requester, contracting party, payer, organizer and authorised booking contacts |

A booking can be created directly without inquiry. Setup, rehearsal, event-use and teardown blocks may be separate intervals. Confirmation rechecks policy/draft revision and availability and commits booking plus all required reservations in one transaction.

### 3.5 Booking cancellation

| Proposed relation | Purpose / key invariants |
|---|---|
| `booking_cancellation_requests` | Append-only requests from authorised external booking contact or internal party; requester/principal and reason |
| `booking_cancellation_decisions` | Approval/rejection/withdrawal/expiry decisions, actor scope, time and reason |
| `booking_cancellation_effects` | Exactly-once effective cancellation result and pinned commercial consequence snapshot |
| `booking_cancellation_followups` | Refund/deposit/credit/manual financial and venue follow-up obligations; no assumed payment execution |
| `booking_disruption_notices` | Venue-side disruption facts projected to linked organizer/event or external booking contact |

A request is not an effective cancellation. Rejected/withdrawn requests do not release occupancy. The confirmed booking's policy revision is pinned; later policy edits cannot change its terms. Effective cancellation and release of future space/resource blocks occur atomically and exactly once. Completed work/history remains.

### 3.6 Event, capabilities and responsibility

| Proposed relation | Purpose / key invariants |
|---|---|
| `events` | Organizer-owned operational event; distinct from booking |
| `event_sessions`, `event_session_spaces` | Event sessions bind to event-owned venue snapshot |
| `event_capability_sets`, `event_capability_revisions`, `event_capability_overrides` | Versioned optional modules, default off; explicit dependency rules |
| `event_responsibility_assignments` | Accountable party, performing party, approver/informed parties, scope/grant and due/status; created after collaboration grant relations exist |
| `event_status_history` | Lifecycle projection history, not sole decision evidence |
| `event_change_requests` | Organizer-initiated cancellation, postponement or rescheduling request with expected event revision and lifecycle status |
| `event_change_approval_decisions` | Append-only approval/rejection/return decisions with actor, authority, time and reason |
| `event_decisions` | Immutable effective outcome created only when an approved or immediately executable change is committed |
| `event_schedule_revisions` | Immutable timezone-aware original/replacement schedule snapshots; a material change can require RSVP reconfirmation |
| `event_decision_sessions` | Sessions/capabilities affected by the effective event decision |
| `event_disruption_resolutions` | Organizer response to a provider-owned booking disruption: relocate, amend, postpone, cancel or unresolved |

No operational event is created by confirming a venue booking. Capability activation does not imply responsibility assignment. A task may be performed by a collaborator, but accountable party and grant are explicit.

### 3.7 Cross-organization collaboration and venue snapshots

| Proposed relation | Purpose / key invariants |
|---|---|
| `collaboration_grants` | Grantor/grantee org, scope, purpose, projection, actions, validity and revocation |
| `collaboration_grant_revisions` | Immutable changes to grant scope/terms |
| `venue_snapshot_shares` | Provider-approved source revision/layers/resources shared for a specific event |
| `event_venue_snapshots` | Event-owned immutable copy with source org/revision/hash/grant provenance |
| `event_venue_snapshot_layers`, `event_venue_snapshot_objects`, `event_venue_snapshot_resources` | Event-owned permitted projection; no write-through to provider master |
| `booking_event_links` | Separate-owner relationship and collaboration context; this is the only canonical booking/event association relation |

The organizer can continue to read historical event snapshot provenance after source changes/revocation, subject to retention/access policy. Revocation prevents new use or further collaboration actions, not historical audit.

### 3.8 Guest registry, invitations, RSVP and attendance

| Proposed relation | Purpose / key invariants |
|---|---|
| `persons`, `person_contact_points`, `person_identifiers` | Organizer-owned persistent person identity and contact channels |
| `event_participations` | Event-specific inclusion/eligibility; separate from person and RSVP |
| `guest_groups`, `guest_group_memberships`, `guest_relationships` | Event/organization-scoped group and relationship data |
| `guest_notes`, `guest_custom_field_definitions`, `guest_custom_field_values`, `guest_tags` | Restricted organizer data and versioned fields |
| `invitations`, `invitation_revisions` | Issuance/reissue lifecycle and schedule/policy context |
| `invitation_links` | Token hash only, purpose-bound, revocable, expiry separate from RSVP deadline |
| `invitation_deliveries` | Delivery attempts associated to an invitation; delivery failure does not change RSVP |
| `rsvp_responses` | Append-only answer history, source/channel, received/recorded timestamps, actor and correction reference |
| `rsvp_policies`, `rsvp_policy_revisions` | Versioned deadline, choices, timezone and response-change rules |
| `participation_status_history` | Eligible/waitlist/withdrawn/cancelled status separate from answer |
| `admission_credentials` | Admission-only credential lifecycle, separate from invitation link |
| `attendance_records`, `checkin_stations` | Physical arrival/check-in, correction and station history |

No response is unanswered, never an implicit decline. A cancellation or schedule revision must not overwrite old RSVP answers. Guest operations are absent when the relevant capabilities are disabled.

### 3.9 Event cancellation, postponement and communications

| Proposed relation | Purpose / key invariants |
|---|---|
| `event_notification_campaigns` | Purpose-specific event communication (cancellation, postponement, schedule update or RSVP reconfirmation) linked to an effective event decision and fixed audience semantics |
| `event_notification_recipients` | Immutable recipient snapshot and qualification reason; stores only the minimum encrypted contact-point snapshot needed for delivery/retry, under restricted access and retention |
| `event_notification_delivery_attempts` | Per-channel campaign attempt/provider result/retry/suppression, separated from invitation delivery attempts |
| `notification_templates`, `notification_template_revisions` | Separate invitation, reminder, cancellation and postponement templates |
| `outbox_events` | Transactional publication after authoritative state changes |
| `background_jobs` | Idempotent asynchronous execution and retries |

Campaign recipient snapshot is fixed at confirmation; retry must not recalculate audience. Recommended default is all active invitees, with accepted/tentative, all previously invited and permitted custom audience choices. The event cancellation commits independently of email/SMS delivery. Queued invitations/reminders are suppressed, but historical invitations/deliveries/responses remain.

A venue cancellation creates a scoped disruption notice. It does not cancel the organizer's event or create guest messages unless the organizer decides or explicitly delegates that task.

### 3.10 Audit, jobs, documents and reporting

Retain dedicated audit events for privileged actions, approvals, sensitive reads/exports and external capability use. Outbox records are not audit records; notification delivery rows are not business decisions. Create `outbox_events` and the minimum worker/job ledger in the platform foundation migration so booking/event transactions can insert outbox messages from the first workflow. Background job state is operational and cannot become the authoritative booking/event lifecycle.

## 4. State machines and transactional commands

### 4.1 Booking lifecycle

Inquiry → separate draft/revisions → offer/revisions → approved/accepted as configured → confirmed. Cancellation requests are a separate child workflow. Booking becomes cancelled only when the effective cancellation command passes policy/authority checks and commits the decision, status projection, commercial effects and reservation release atomically.

### 4.2 Event lifecycle

Draft/planned → scheduled/active → completed, cancelled or postponed (with later rescheduled schedule revision). Exact allowed transitions must be explicit and guarded by event revision/expected state. Cancellation is not deletion and is not an RSVP response.

### 4.3 Command transaction rules

- Require idempotency keys on externally retryable commands and state-changing public actions.
- Lock aggregate and affected reservation rows in deterministic order.
- Revalidate expected revision, active policy revision and permissions at commit time; a stale preview cannot authorise a changed aggregate.
- Persist decision, audit event, state projection, resource effects, suppression state and outbox event in one database transaction.
- Do not call email/SMS providers inside the transaction.
- Use transactional outbox workers with idempotent provider submission and per-recipient delivery state.
- A booking cancellation transaction must not partially release reservations.
- An event cancellation transaction must not wait for delivery, and delivery failure must not revert event state.

## 5. Row-level security and runtime roles

The v0.2 schema has no RLS. The successor must explicitly choose a defense-in-depth policy. Proposed baseline:

- Separate migration owner, runtime application role, read-only/reporting role and worker role.
- Runtime roles are not superusers, table owners or BYPASSRLS.
- Tenant tables enable and force RLS where compatible with connection pooling and service operation.
- Use transaction-local tenant/actor context; never session-persist tenant identity across pooled requests.
- Policies must validate active membership or a narrowly scoped collaboration/external capability for the requested projection/action.
- Security-definer functions are exceptional, schema-qualified, fixed-search-path and audited.
- Background jobs must carry explicit tenant and service-principal context.
- Integration tests run as the real non-owner runtime role, including cross-tenant negative tests.
- Application-level permission checks remain mandatory; RLS is not a replacement for business authorization.

Exact RLS policy layout must be reviewed alongside the connection-pool/context strategy before migrations.

## 6. Migration decomposition proposal

Use ordered immutable files, each transaction-scoped, with `SET LOCAL search_path` and schema-qualified extension/function references. No giant one-shot import of v0.2 SQL.

| Order | Migration group | Content |
|---|---|---|
| 000001 | Platform and tenancy | schemas, approved extensions, orgs, users, memberships, service principals, migration ledger, outbox and worker/job foundation |
| 000002 | Authorization and audit | permission catalogue, roles/grants, audit foundation |
| 000003 | Configuration | typed scopes, branding, templates, catalogues and revision pairing |
| 000004 | Venue hierarchy | venues/buildings/levels/spaces, spatial revisions and tenant-safe hierarchy |
| 000005 | Resource inventory | resource pools/units and qualification model |
| 000006 | Booking intake and drafts | inquiries, attachments, annotations, drafts and immutable revisions |
| 000007 | Offers and confirmation | price revisions, offers, approval, confirmed snapshots, booking contacts |
| 000008 | Occupancy and reservations | unified space-time blocks, GiST exclusion, resource reservations and pooled capacity transaction functions |
| 000009 | Booking cancellation | pinned policy, cancellation request/decision/effect/follow-up, provider-owned booking disruption notice; no cross-tenant event FK |
| 000010 | Event foundation | event, schedule revisions, sessions and event capability revisions |
| 000011 | Collaboration and snapshots | grants, grant revisions, provider share, event-owned snapshot and booking/event links; add event-side references to provider disruption notices only through scoped collaboration projections |
| 000012 | Responsibility and disruption handling | event responsibility assignments, task-party scopes, event disruption acknowledgements/resolutions with grant checks and no unvalidated cross-tenant FK |\n| 000013 | Guest registry and participation | persons, contacts, event participation, groups, custom fields and tenant-safe self-references |
| 000014 | Invitations and RSVP | invitations, token hashes, delivery, policies and append-only responses |
| 000015 | Event decisions and communications | change requests, approval decisions, effective cancellation/postponement decisions, campaigns, recipient snapshots, templates and notification attempts |
| 000016 | Spatial allocation and attendance | event allocation, admission credentials, check-in and attendance, all capability-gated |
| 000017 | Operational hardening | indexes/retention and operational job support not created in foundation migrations |
| 000018 | RLS and grants | enable/force RLS, policies and runtime grants after all referenced relations exist |

This ordering is a draft, but dependency ownership is explicit: outbox/worker foundations precede all transactions that write to them; event responsibility tables follow collaboration grants; event-side disruption acknowledgement is tenant-owned and grant-scoped. Migration boundaries should be confirmed against the actual DDL dependency graph. A clean database and an upgrade path from any deployed pre-release schema are separate test targets. No existing production data migration is assumed.

## 7. Validation gates before calling the schema implementation-ready

1. Confirm PostgreSQL major-version support and extension availability, especially `btree_gist`.
2. Complete exact entity/key/constraint review, including external actor and service-principal attribution.
3. Validate all DDL on a fresh disposable database with the pinned target PostgreSQL version.
4. Apply migrations under the actual migration role; run application tests as a non-owner runtime role.
5. Test tenant isolation, RLS, cross-org grant expiry/revocation, and typed-FK negative cases.
6. Test concurrent space overlaps and pooled capacity using independent connections.
7. Test atomic booking confirmation/cancellation and reschedule replacement-before-release.
8. Test event cancellation, fixed recipient snapshots, outbox retries and delivery partial failure.
9. Test data retention, audit access, backup/restore and upgrade/recovery behavior.
10. Generate a schema diagram and document each table's owner, retention class and sensitive fields.

Until these gates pass, the schema remains a reviewed design or draft migration set, not production-ready.

## 8. Decisions intentionally not assumed

- GHB cancellation windows, fees, deposits, refunds and approval thresholds.
- GHB room capacities, current prices and service inventory.
- Whether personnel reservations are named individuals or capacity pools in each service category.
- Public booking link expiry and identity assurance policy.
- Exact data retention/legal basis and guest contact suppression requirements.
- Whether RLS is enabled for every tenant table or a specifically justified subset; the decision must be explicit and testable.
- Exact PostgreSQL major version and deployment packaging.

These require explicit product, GHB or infrastructure validation. They must not be invented as seed configuration.
