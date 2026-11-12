# Project state

**Status:** accepted product/domain design baseline; 67-migration PostgreSQL 18 implementation with tax calculation and end-to-end commercial snapshot fixtures, canonical OpenAPI v0.3, Fastify staff API/workers and Vue 3 staff web across stacked draft PRs #26–#36; PostgreSQL 18.6, OpenAPI, API and staff-web CI validation configured; SMTP delivery worker and explicit campaign queue/cancel lifecycle implemented; production-readiness review remains open  
**Last updated:** 2026-11-12  
**Implementation status:** PR #28 adds the commercial offer lifecycle; stacked PR #29 adds organization price-list management; stacked PR #30 adds organization cancellation-policy management; stacked PR #31 adds versioned organization tax configuration; PR #32 adds pinned-profile tax calculation; PR #33 adds explicit per-adjustment tax classification and allocation; PR #34 adds PostgreSQL calculation fixtures for inclusive/exclusive bases, mixed tax codes, residual-cent allocation, configured rounding methods, manual overrides and not-applicable profiles; PR #35 adds runtime-role regression guards for offer tax/adjustment snapshots, the customer-safe offer projection, approval evidence and booking confirmation snapshot propagation; PR #36 adds a rollback-only transactional offer-to-acceptance-to-approval-to-confirmation fixture with successor price-list, tax-profile, cancellation-policy and approval-policy revisions; PR #62 adds persisted organization/customer locales and locale-aware booking-offer email delivery; the locale-settings slice adds permission-checked organization defaults and global staff-user language preferences. CI is intentionally deferred while the monthly GitHub Actions allowance is exhausted; no current-head CI pass or production database deployment is claimed.

## Product

Eventor is a reusable, self-hosted platform that can operate as a venue booking/resource system, a full event operations platform, or a configurable combination. GHB Sarajevo is the first reference organization/venue, not the product's only intended deployment.

## Established direction

- API-first modular monolith.
- Vue 3 + TypeScript + Vite staff and guest-facing applications.
- Fastify + TypeScript API and background workers.
- PostgreSQL as the authoritative datastore.
- SVG-based spatial editor and map rendering.
- WebSockets with transactional outbox.
- C++ OR-Tools CP-SAT optimization worker/service.
- Self-hosted Linux deployment; Docker is optional, not mandatory.

## Agreed domain behavior

### Operating scope and party responsibilities

- A venue provider is not automatically the event organizer. Venue booking and venue-side service delivery are distinct from organizing the renter's event.
- Organization-level operating profiles establish defaults: venue provider, event organizer or hybrid. They are configuration presets, not product/license tiers.
- Booking/event-level scope can override organization defaults and independently activate only the modules required for that booking/event.
- A booking can be completed without creating an operational event or collecting guest-level data.
- Distinguish venue provider, booking requester/customer, contracting party, event organizer and operational operator; these roles may belong to different entities.
- Organizer-side guest management, invitation/RSVP, seating, check-in, external prerequisites and live event cockpit are optional for venue-provider-only workflows.
- Task/module responsibility and scoped collaboration must be explicit. A booking customer does not automatically become a tenant/member or gain access to the venue provider's workspace.
- Accepted cross-organization model: venue and booking data remain provider-owned; operational event and guest data remain organizer-owned; collaboration uses explicit grants and immutable, revision-pinned venue-space snapshots. See [Cross-Organization Collaboration v0.3](implementation-design/v0.3/CROSS_ORGANIZATION_COLLABORATION_DESIGN_v0.3.md) and [ADR 0006](decisions/0006-cross-organization-collaboration.md). The initial migration implementation is present in draft PR #26; broader authority/tenant review remains open.
- The venue provider retains its own venue/facility and contracted service responsibilities. Eventor records assigned operational ownership; it does not transfer duties or make legal determinations.

### Optional event capabilities

- An operational event is created only when the booking/event scope requires it; confirmed venue booking alone does not create one.
- Guest Registry, invitations/RSVP, seating, check-in, external prerequisites and event-day cockpit are independently optional capabilities.
- Capability activation and task responsibility are explicit; module defaults may be overridden for an individual event.
- The organizer's guest data is not made visible to the venue provider solely because it supplies the space. Cross-party access is task-specific and explicitly granted.
- See [RSVP and Invitation Design v0.3](implementation-design/v0.3/RSVP_AND_INVITATION_DESIGN_v0.3.md) and [ADR 0005](decisions/0005-separate-invitations-rsvp-attendance.md).

### Booking

- Public inquiry is a relatively simple intake, not a complex booking configuration exercise.
- Staff review an inquiry and may create a separate editable booking draft prepopulated from it.
- Drafts can change dates, spaces, resources, services and prices without changing the original inquiry.
- Offer/approval and explicit confirmation are distinct workflow stages.
- Staff can also create bookings without an inquiry.
- Preserve original requested values, offered/approved values and delivered/actual values separately.
- Rehearsals are separately schedulable reservations with their own date, time and duration.
- Historical records pin the form and catalogue revisions and retain the labels/answers shown at the time.
- Customer language is explicit interaction data, not inferred from a name, nationality or location. A public inquiry may submit a validated `customerLocale`; otherwise it inherits the organization's persisted `default_locale`. The resolved locale is retained on the inquiry and carried to the capability-protected offer projection and queued offer email. Initial supported locales are `bs-BA` and `en`; staff-user language preferences are global across organizations, while organization default changes require `organization.manage`; user preference overrides organization fallback.
- Organization price lists reuse the existing versioned price-list schema. Staff can create lists, author draft revisions and line items, and explicitly publish immutable revisions through permission-checked database commands. Offers pin exact published revision IDs. See [Price-list Management Design v0.3](implementation-design/v0.3/PRICE_LIST_MANAGEMENT_DESIGN_v0.3.md).


### Invitations, RSVP and attendance

- Invitations, delivery attempts, invitation-link validity, RSVP answers, participation/waitlist eligibility and physical attendance are separate lifecycle dimensions.
- Guest self-service RSVP uses a high-entropy, opaque, revocable invitation link; no guest account is required by default.
- Email is the initial delivery channel; channels, templates and reminder cadence are configurable.
- Staff can record responses received in person, by telephone, email, written communication, a representative or another configured channel, without requiring a guest link or email address.
- Capture source, response-received time, server-recorded time, authenticated operator and optional restricted notes/reason.
- Response history is append-only. Changes/corrections add a new record and do not erase the prior response.
- RSVP choices, deadline, event timezone, reminder policy and response-change rules are versioned event configuration.
- No response remains unanswered; it is not an automatic decline. Invitation delivery failure does not change RSVP state.
- RSVP response and physical attendance/check-in are separate. Accepting an invitation never creates attendance.
- Guest operations are optional and assigned to the organizer or explicitly contracted operating party; a venue-only booking requires no guest records, invitations or RSVP.

### Guest registry

- Persistent person records are separate from event-specific participation.
- Reuse profiles across events; support duplicate detection and supervised merge.
- Support custom fields, attachments, import/export and history with permissions and audit.

### Spatial model and seating

- Model venues, buildings, floors, rooms, zones, rows, positions, physical features and count-based capacity pools as distinct concepts.
- Do not interpret every numeral or colored region in a source plan as an individual seat.
- Support both zone-only allocation and precise zone/row/position allocation.
- Seating constraints include together/avoid, preferences, exclusions by table/row/zone/room/building/distance/session, hard and soft rules, locked assignments and scoped reruns.
- Support manual, category-based, hybrid and solver-assisted allocation.
- Solver output is a proposal with diagnostics and preview; a person explicitly commits it.

### Guest portal and operations

- Personalized portal/QR shows only the relevant guest's permitted information and a sanitized public map.
- No public guest directory or internal security information.
- Staff cockpit is role-configurable and shows live status, map, counts, alerts, history and permitted controls.
- Role-specific workspaces expose only required data.

### Configuration and branding

- Admins can add, modify, retire, reorder and publish forms, fields, options, catalogues, services, equipment, prices and workflow rules without code changes.
- Support dependencies/conditional visibility where needed, but do not impose elaborate conditional forms without a validated requirement.
- Version and publish configuration; support rollback. Retire referenced options rather than deleting them or changing their meaning.
- Branding inherits Organization → Venue → Event, with versioned snapshots for invitations, portal, QR/guest cards, maps, signage and reports.

### External prerequisites

- Model external coordination (for example, police coordination when required) as a configurable event-readiness checklist.
- Track requirement, responsible authority, internal coordinator, submission/scheduled/completed status, dates, references and restricted attachments.
- Do not build internal law-enforcement methods, findings or inspection management. Cockpit shows only appropriate readiness status.

## Reference deployment cautions

- GHB room capacities, venue descriptions, current rates, discounts, operating hours and rental policies require confirmation by GHB before enforcement.
- Existing GHB form options are reference data, not hardcoded product behavior.
- The supplied mosque workbook is a grid-like spatial drawing. Preserve the source and map approved objects deliberately; do not blindly convert cells/numbers into seats.
- The source venue workbook and sensitive operational details must not be committed unless explicitly reviewed and sanitized.

## Operating model

See [Operating Model](OPERATING_MODEL.md) and [ADR 0004](decisions/0004-optional-event-operations-scope.md). This accepted product requirement is reflected in the successor v0.3 designs and implementation draft; historical Blueprint v1.2 and Implementation Design v0.2 files remain unchanged snapshots.

## Cancellation and event disruption

The accepted v0.3 design covers customer/organizer-initiated booking cancellation, venue-provider-initiated booking cancellation, organizer-owned event cancellation/postponement, guest notification campaigns and cross-organization disruption handling. Booking and event outcomes remain independent; invitation, RSVP and attendance history is preserved. The workflow is tracked in [Issue #21](https://github.com/TeraflopsBH/eventor/issues/21) and documented in [Cancellation and Event Disruption Design v0.3](implementation-design/v0.3/CANCELLATION_AND_EVENT_DISRUPTION_DESIGN_v0.3.md). Initial schema and API contract coverage is included in draft PR #26. GHB-specific commercial terms, approval thresholds and operational policies still require confirmation.

## Successor database and API baseline

The accepted successor logical model and API design derive from ADRs 0004–0006, the RSVP/invitation and cancellation designs, and the venue-first MVP/role model. The database integrity baseline was merged in PR #24 and the aligned logical schema/API design in PR #25. The executable migration and OpenAPI baseline is PR #26; the separate remediation branch in PR #27 adds migrations 000022–000046 for reviewed integrity findings, database-backed staff sessions, the notification campaign-preparation worker, audited campaign review/confirmation, the private public-organization route directory, rate-limited/idempotent public inquiry submission, and permissioned staff inquiry projections/commands with assignment and immutable history; PR #27 also contains the Fastify API/worker bootstraps and the public intake/staff inquiry routes. Both remain draft/unmerged and require review.

## Executable schema and API contract draft

The accepted executable database/API baseline is split across two stacked drafts:

- [PR #26](https://github.com/TeraflopsBH/eventor/pull/26) contains the initial 21 ordered PostgreSQL 18 migrations, least-privilege role bootstrap, checksum-verified migration runner, database integrity/RLS tests and the canonical OpenAPI v0.3 contract.
- [PR #27](https://github.com/TeraflopsBH/eventor/pull/27) is a separate remediation draft based on PR #26. It adds migrations **000022–000046**, database-backed staff sessions, Fastify command routes, notification preparation/delivery workers, tenant-owned SMTP configuration, the audited campaign review/confirmation/queue/cancellation lifecycle, delivery reconciliation, optional Resend callbacks, a private public-organization route directory and a published public booking-form projection, plus the initial Vue staff workspace.

- Migration **000043** adds `eogp.get_public_booking_form_revision(...)`, a constrained projection of the exact requested revision of an active form. The API validates answers against that immutable revision before encryption and the database submission command rechecks that the same revision remains published.
- Migration **000044** adds `eogp.get_booking_inquiry_capabilities(...)` and `eogp.list_booking_inquiry_assignees(...)`. The capabilities projection requires inquiry read permission and returns only separate action flags; the roster requires assignment permission and returns only active same-organization membership IDs and display names. No colleague email/contact data is exposed.
- Migration **000045** adds `eogp.convert_booking_inquiry_to_draft(...)`, a permission-gated, idempotent atomic conversion command. It creates a separate booking draft with immutable revision 1, preserves the original ECP1-encrypted submission inside a ciphertext wrapper, changes the inquiry to `converted`, and appends attributed status history and an audit event. Direct runtime table access to booking drafts/revisions is revoked.
- Migration **000046** adds `booking.draft.read` and `booking.draft.manage`, both restricted to active organization-scope grants while a draft has no booking record. It adds permission-checked current-draft/revision-history projection and an optimistic-concurrency successor-revision command. Values stay in ECP1 ciphertext in the database and are decrypted by the API after authorization; successor revisions preserve the pinned source form revision, validate the dynamic answer schema, append space/resource lines and audit an attributed revision event. Stale revision numbers, invalid/retired space/resource references, and active holds on the previous revision are rejected. Runtime direct access to draft/revision/child/offer tables remains revoked.
- Public field-schema v1 is documented in `docs/product/PUBLIC_BOOKING_FORM_SCHEMA_v1.md`; it supports typed text/number/date/time/choice/checkbox fields, required values, lengths/ranges, pinned option membership and unknown-key rejection. Unsupported schema versions and properties fail closed.

The PR #27 branch now includes migrations 000040–000046, public booking-form retrieval, encrypted/rate-limited inquiry submission, permissioned staff inquiry inbox/detail/assignment/status/annotation APIs, exact published-revision lookup, and server-side field-schema v1 answer validation before encryption. Migration 000044 adds a restricted assignee roster and per-membership inquiry capability projection. Migration 000045 adds atomic inquiry-to-draft conversion with immutable revision 1 and an encrypted submission snapshot. Migration 000046 adds protected draft reads and immutable successor revisions with ECP1 encryption and concurrency/hold safeguards. The Vue staff workspace includes a permission-aware inquiry inbox, detail view, assignment, review status, internal notes, status/assignment histories, inquiry conversion and a permission-aware booking-draft editor with immutable successor revisions. The latest fully green three-job validation is [run #43027314682](https://github.com/TeraflopsBH/eventor/actions/runs/43027314682) on the earlier head `8c19c51b37a67f1cb1faf6f158d5db32e8c32d9e`; it predates migrations 000039–000046 and the subsequent SMTP/Resend/public-intake/staff-inquiry changes. The latest observed Actions attempt, [#43118342383](https://github.com/TeraflopsBH/eventor/actions/runs/43118342383) (run #1117), ran on the earlier commit `77bcfa7a1cad1710cef5ffc075329f35110c65f9` and failed before any job step started. All three jobs (staff-web build, OpenAPI contract, PostgreSQL migrations/RLS) had empty step lists and no downloadable logs; retrying the failed jobs produced the same result. No test, build, OpenAPI or migration command ran. Later commits, including current head `e180aa53b4fd5ad4f4ce52ac194a0e2bdf94139e`, have no successful CI result, so the current branch remains **not yet CI-validated**. This is a runner/startup failure, not a reported code/test failure.

The current OpenAPI v0.3 contract contains **259 paths and 299 operations**. It is validated with the repository's structural/security checks, a pinned OpenAPI 3.1 validator and Redocly in CI, but the current head's final validation is still pending. The API implements staff authentication/session lifecycle, selected booking-reservation release, organizer event-change commands, notification campaign review/confirmation/queue/cancel/reporting/reconciliation, tenant SMTP configuration/test, optional signed Resend callbacks, and two narrowly allow-listed anonymous public intake operations: GET of an active organization's latest published booking form and POST of an encrypted, idempotent inquiry submission with a durable ten-per-source-per-UTC-hour rate limit. Staff inquiry operations include a permission-filtered inbox, decrypted detail with form schema, internal annotations, assignment and status histories, assignment/unassignment, controlled review-status transitions and append-only internal notes. Inquiry source/history tables are not directly selectable by the runtime role. Submitted answers are validated against the exact immutable published revision using field-schema v1 before encryption; unsupported schemas and unknown answer keys fail closed. Attachment references are currently rejected. The Vue staff workspace now also includes the commercial offer lifecycle, approval policies, organization price lists, cancellation policies and tax-profile configuration. The wider venue administration, guest, spatial and event workspaces remain incomplete.

No production database has been migrated. The commercial workflow, price-list management, cancellation-policy management and tax configuration and tax calculation remain stacked draft PRs pending code review, fresh CI validation when allowance is available, upgrade/recovery testing, and production security/operational review.

## Database schema review and remaining validation

The initial [Database Review v0.2](database/DATABASE_REVIEW_v0.2.md) records findings in the historical 86-table starter schema. Earlier v0.3 migrations were executed successfully against PostgreSQL 18.6 in CI. The later commercial migrations 000058–000063 have not yet been executed or validated on the current stacked PR heads; CI is intentionally deferred until the monthly allowance resets. Issue #2 and related schema issues remain open for deeper DDL/RLS/authority review, broader constraint-matrix coverage, migration upgrade testing and backup/restore validation. The v0.2 SQL remains a historical reference rather than the executable successor schema.

## Accepted MVP boundary

The recommended first production release is **venue booking and venue operations** for the GHB reference deployment, with GHB acting as venue provider by default. It is complete without an operational event or guest-level records. Guest registry, invitations/RSVP, seating, guest portal, admission/check-in, organizer prerequisites and full event cockpit are later optional capabilities; an organization/event can activate them when it is responsible for those tasks.

The accepted initial scope and acceptance scenarios are in [MVP Scope v0.1](product/MVP_SCOPE_v0.1.md); the baseline role and permission model is in [User Roles and Permissions v0.1](product/USER_ROLES_AND_PERMISSIONS_v0.1.md). Organization-specific assignments, approval thresholds and GHB capacities, service inventory, prices and operating policies still require validation before production configuration.

## API contract review

The imported OpenAPI v0.2 contract passed YAML parsing and local structural checks (36 paths, 46 operations, unique operation IDs, 172 resolved local references); that historical check was not a full OpenAPI semantic validation. The canonical v0.3 contract is [`docs/api/openapi.v0.3.yaml`](api/openapi.v0.3.yaml) and is validated in CI by the strict Eventor structural/security validator, the pinned OpenAPI 3.1.1 validator and Redocly lint. It currently contains 120 paths and 138 operations. The first API command routes, database-backed Argon2id staff sessions, CSRF/origin validation, OpenAPI TypeScript declaration generation, route tests and tenant-aware notification preparation/delivery workers are implemented on PR #27. An initial Vue 3 + TypeScript + Vite staff workspace now provides login/session restoration/logout, tenant SMTP configuration with write-only credentials and test email, and campaign review/confirmation/queue/pre-send cancellation. The staff UI now provides permission-filtered campaign listing, campaign progress and paginated delivery reports, plus audited operator reconciliation and separate authorized retries. API permission checks remain authoritative. Remaining OpenAPI operations, broader staff application workflows and production readiness remain open under Issues #3, #17 and #21. Email delivery uses each organization's own configurable SMTP server by default; no third-party delivery service is required. Resend is an optional SMTP/callback choice only for organizations that select it; signed delivery/bounce callbacks and migration 000039's stable pre-submission Message-ID correlation can resolve uncertain Resend outcomes without resending. Other providers and SMS remain unimplemented. Campaign confirmation remains distinct from queueing.

## Imported design artifacts and reconciliation

The working design sources are now in the repository:
- [Technical Blueprint v1.2](blueprint/v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md).
- [Implementation Design v0.2](implementation-design/v0.2/Event_Operations_Implementation_Design_v0.2.md).
- [Consolidated PostgreSQL schema starter](implementation-design/v0.2/eogp_schema_v0.2.sql) — 86 table definitions (64 core + 22 booking/configuration).
- [OpenAPI v0.2 draft](implementation-design/v0.2/eogp_openapi_v0.2.yaml).
- [64-item backlog](implementation-design/v0.2/EOGP_Backlog_v0.2.csv) and [GHB rental-form capture](implementation-design/v0.2/GHB_Rental_Form_Reference_v0.2.csv).
- [Design reconciliation report](DESIGN_RECONCILIATION_v0.2.md).

The separate v0.2 booking SQL addendum duplicates all 22 booking/configuration table definitions already present in the consolidated schema and is therefore not included as an additional executable schema file. The source workbook, rendered workbook image and spatial observations register remain outside GitHub pending venue-owner review.

## Immediate next steps

1. Review the stacked commercial PRs in order. Tax configuration is implemented in PR #31 as an organization-owned, versioned profile catalogue; automatic percentage calculation now consumes the exact pinned tax-profile revision in PR #32; statutory interpretation and full invoice/tax workflows remain validation gates.
2. Expand PostgreSQL functional/concurrency fixtures across migrations 000058–000064 and the complete offer/approval/confirmation workflow. Runtime-role snapshot consistency guards and a rollback-only transactional commercial lifecycle fixture now cover offer preparation, customer acceptance, independent approval, confirmation, pinned tax/price/cancellation/approval revisions and snapshot integrity. The lifecycle fixture also proves that missing and expired exact space holds block confirmation, then verifies that a live hold converts to confirmed booking occupancy without changing the commercial snapshot. It exercises resource preflight for missing and expired pooled/discrete holds, rejects a partially covered pooled quantity, and verifies split pooled holds plus a discrete-unit hold convert to the matching confirmed booking resource lines. PostgreSQL execution and CI validation remain outstanding. CI remains intentionally deferred while the monthly GitHub Actions allowance is exhausted; do not spend further runs until the allowance resets.
3. Establish internationalization before staff and customer-facing UI expansion. [ADR 0007](decisions/0007-internationalization.md) defines locale precedence, content translation, formatting and communication rules. The initial reference locales are Bosnian (Bosnia and Herzegovina, `bs-BA`) and English (`en`). The staff client now has a Vue i18n runtime, separate language catalogues, locale-aware formatting helpers and an initial localized workspace shell; user/organization locale persistence and the remaining workflow translations are pending.
4. Keep the staff frontend modular and feature-oriented. [ADR 0008](decisions/0008-modular-staff-frontend.md) establishes the extraction direction; the existing large `App.vue` is to be decomposed incrementally without an all-at-once rewrite.
5. Review offer preparation's effective-period checks against the new price-list revision model, and ensure the staff UI can explicitly select the exact published revision.
6. Expand venue, building, space and resource administration workspaces after the commercial configuration layer is complete.
7. Keep production deployment blocked until GHB validates inventory, capacities, prices, tax treatment, cancellation terms and approval authority.

## Open questions / validation gates

- Confirm GHB capacities, room/resource inventory, pricing and current rental policy.
- Validate actual approval/offer stages and who is authorized to approve/confirm.
- Confirm RSVP deadline, reminder schedule, response-change policy and guest contact-channel requirements.
- Confirm which guest and staff data fields are mandatory and who may view them.
- Review the venue spatial drawing with an authorized venue representative.
- Confirm public deployment hostname, reverse-proxy boundaries, email delivery and retention requirements.


## Internationalization architecture

[ADR 0007](decisions/0007-internationalization.md) is the accepted cross-cutting direction for i18n. Eventor will use stable locale-independent identifiers and translation keys; organization defaults and staff preferences determine the staff interface locale, while customer-facing flows may resolve an explicit customer language preference or request before falling back to the organization default. Missing translations fall back predictably to the configured fallback locale and are never replaced by machine-translated text at runtime.

Locale is distinct from timezone and currency. Date/time rendering must use the event or booking timezone where the domain requires it, with locale controlling presentation only. Monetary values retain their ISO currency code and exact stored amount; locale affects formatting, not calculation. Customer-facing communications and vendor-authored translatable content must resolve language explicitly and preserve the exact rendered wording in issued/historical snapshots where that wording forms part of an accepted commercial record.

The first implementation slice is intentionally architectural: no locale columns, API behavior or UI translation framework are added until the existing user/membership/session and content revision boundaries are incorporated into a reviewed implementation plan. Initial supported locales: `bs-BA` and `en`.


## Staff frontend structure

The i18n foundation is organized under `apps/staff-web/src/i18n/`: language catalogues are separate from runtime setup and locale-aware formatting helpers. The root application currently consumes the runtime and translates the shared authentication/workspace shell. The legacy workflow implementation remains in `App.vue`; future work must extract feature views, composables and shared components incrementally under ADR 0008 rather than adding more unrelated workflow logic to the root component.


The first legacy workflow extraction is now represented by `apps/staff-web/src/features/booking-inquiries/presentation.ts`. Inquiry answer display, assignee-name resolution, inquiry date display and booking-money display helpers have been moved out of `App.vue` into a feature-owned presentation module, with the existing behavior retained. This is an intentionally small first boundary; inquiry state/API orchestration and the large workflow template remain in the root component for subsequent composable/view extraction. The extracted money/date helpers currently preserve the prior default-locale behavior and should be aligned with the explicit i18n formatting context as those workflows are migrated.


The booking-inquiry workflow now has a feature-owned composable at `apps/staff-web/src/features/booking-inquiries/useBookingInquiries.ts`. It owns inquiry list/detail state, filters, capability-derived actions, answer view-model generation, loading/refresh, assignment, status changes, conversion and internal annotations. The root component supplies shared session/busy/message/error and booking-draft cleanup dependencies, and retains the existing template bindings. Authorization remains enforced by server APIs; UI capability checks remain in place. This is an incremental extraction: the inquiry template and booking-draft/offer sub-workflows remain in `App.vue` for later slices.


The booking-inquiry workflow now has a feature-owned composable at `apps/staff-web/src/features/booking-inquiries/useBookingInquiries.ts`. It owns inquiry list/detail state, filters, capability-derived actions, answer view-model generation, loading/refresh, assignment, status changes, conversion and internal annotations. The root component supplies shared session, busy/message/error and booking-draft cleanup dependencies while retaining the existing template bindings. Authorization remains server-enforced; client capability checks remain presentation/interaction gates. The inquiry template and booking-draft/offer sub-workflows remain in `App.vue` for later extraction.


The booking-inquiry workspace presentation is now isolated in `apps/staff-web/src/features/booking-inquiries/BookingInquiryView.vue`. The feature view owns the inbox, filters, pagination, inquiry detail, assignment/status/conversion actions, internal notes and history. It receives the existing composable state/actions as an explicit workspace contract and emits the booking-draft open action. The booking-draft editor and commercial offer/approval/confirmation presentation remain composed by `App.vue` through named slots; their state, API orchestration and behavior were not moved in this slice. The root component now retains only inquiry state bindings needed by those adjacent booking-draft operations and navigation/session lifecycle.


Booking-draft state and commands are now isolated in `apps/staff-web/src/features/booking-drafts/useBookingDraft.ts`. The composable owns the loaded draft, editor fields, capability-derived editability, loading, revision refresh, immutable revision creation and reset behavior. It receives the shared API client, busy/message/error state and inquiry-refresh callback explicitly. `App.vue` retains only the small coordination handler that supplies the selected inquiry's draft reference and read capability, while commercial-offer state and commands remain separate for a subsequent extraction. Sign-out/session reset clears the draft composable through the existing inquiry lifecycle callback.

The commercial booking-offer workflow is now isolated in `apps/staff-web/src/features/booking-offers/useBookingOffers.ts`. It owns offer preparation and successor revisions, issue/idempotency state, customer capability handling, organization SMTP email queueing and delivery reconciliation/retry, approval decisions, eligibility checks and explicit booking confirmation. The root composition layer supplies the API/session/draft dependencies and continues to own the adjacent price-list, cancellation-policy and tax-profile administration workflows. Server-side authorization, immutable revision semantics and transactional final availability checks remain authoritative.

The staff commercial-configuration workflows are now separated into four feature composables: `features/booking-prices/useBookingPriceLists.ts`, `features/booking-taxes/useBookingTaxProfiles.ts`, `features/booking-approvals/useBookingApprovalPolicies.ts`, and `features/booking-cancellations/useBookingCancellationPolicies.ts`. Each owns its own editor state, selection/computed revision state, loading, validation, create/save/successor-revision and explicit publish commands. Price-list configuration receives the published tax-profile revision projection as an explicit dependency; this keeps tax-profile ownership separate while allowing compatible revisions to be selected. `App.vue` now composes these modules and retains the existing workspace templates and shared session/message/busy state.


The four organization-level commercial configuration workspaces are now isolated as feature-owned Vue views: `BookingPriceListsView.vue`, `BookingTaxProfilesView.vue`, `BookingApprovalPoliciesView.vue` and `BookingCancellationPoliciesView.vue`. Each receives its matching feature composable as an explicit workspace contract plus the shared busy state, and imports the existing inquiry date formatter rather than duplicating formatting logic. `App.vue` now selects and composes these views; it retains the tax-profile published-revision projection needed to supply compatible tax revisions to the price-list feature. The views preserve the existing forms, revision histories, validation guidance and explicit publication actions without changing API behavior.


Campaign review and delivery operations are now a feature module under `src/features/campaigns/`. `useCampaigns.ts` owns campaign lookup/list pagination, review and delivery progress state, delivery-attempt filtering, audited reconciliation, separate retry authorization, and confirm/queue/cancel commands. `CampaignWorkspaceView.vue` owns the corresponding presentation and receives the composable workspace plus shared busy and SMTP-readiness state. The root composes the feature and delegates its sign-out/session-reset behavior; campaign API contracts and server-side authorization are unchanged.


The organization email-delivery workspace is now a feature module under `apps/staff-web/src/features/email-delivery/`. `useEmailDelivery.ts` owns SMTP configuration editing, credential-retention/clearing behavior, configuration revision testing, and the optional Resend signed-callback setup. `EmailDeliveryView.vue` owns the SMTP readiness and callback presentation. The root composes this feature and exposes its configuration readiness to campaign operations. SMTP remains vendor-configurable and provider-agnostic; Resend is only an optional callback integration when the configured SMTP host is Resend. API contracts and server-side credential encryption/signature verification are unchanged.


The staff application shell and authentication lifecycle are now separated into `src/features/application-shell/`. `useStaffSession.ts` owns session restoration, sign-in/out, principal and organization display state, and centralized API error handling; it receives a reset callback so feature state is cleared on authorization expiry and sign-out. `StaffApplicationShell.vue` owns the authenticated shell, language selector, login presentation, navigation, shared notices and footer. The public customer offer route is independently rendered by `src/features/public-booking-offers/PublicBookingOfferPage.vue`, which owns the customer capability-link review and accept/reject interaction. `App.vue` now composes these boundaries with the existing staff feature workspaces.


The booking-draft editor and commercial offer/approval/delivery/confirmation presentation are now extracted into `apps/staff-web/src/features/booking-drafts/CommercialBookingWorkspaceView.vue`. The view has two explicit presentation modes for the existing inquiry-view slots and receives the draft and offer composable state/actions through a typed workspace contract. `App.vue` retains only composition: it wires the booking-draft state into the offer composable, provides the combined workspace, and preserves the inquiry view's open-draft event. The draft and offer composables remain the owners of their respective state, validation, authorization gates, API orchestration, idempotency and reset behavior. No API contracts or server-side commercial rules changed.


Booking inquiry and commercial configuration date/currency presentation now follows the active staff locale. Pure helpers in `features/booking-inquiries/presentation.ts` require explicit locale inputs; date formatting additionally requires an explicit timezone and localized empty-value label. The feature-owned `useInquiryPresentation.ts` composable bridges Vue I18n's active locale and the browser-resolved local timezone into those helpers. Booking inquiry, booking draft/offer, price-list, tax-profile, approval-policy and cancellation-policy views now use this shared formatter. Locale changes affect presentation only; stored timestamps, ISO currency codes, monetary values and commercial calculations are unchanged.


The booking inquiry and commercial booking workspaces now use feature-scoped `bookingInquiry` and `commercialBooking` translation namespaces in both English and Bosnian (`bs-BA`). Inquiry lifecycle enum values are mapped to localized labels for presentation while their API values remain unchanged. Booking draft, offer preparation, delivery reconciliation, approval and confirmation wording is translated at the view boundary; identifiers, policy codes, tax allocation tokens, currency codes, stored values and customer-entered content remain domain data. The locale catalogue remains the single source for visible workflow copy.


The public customer booking-offer page now uses the `publicOffer` English/Bosnian catalogue and provides an explicit language choice. Date and number formatting follow that selected locale. Customer-entered names/notes, organization-authored cancellation terms, currency codes, tax basis values and API/domain values remain unchanged.


Booking inquiry, draft and offer composables now receive the active locale translator from the application composition layer. Inquiry assignment/status/conversion/annotation confirmations and feedback, draft JSON/revision validation and notices, and offer preparation/issuance/email reconciliation/retry/approval/booking confirmation messages are localized through the `bookingInquiry` and `commercialBooking` catalogues. Workflow commands, domain enum values, API payloads, idempotency, immutable revision behavior and server-enforced availability/authorization remain unchanged. Server-originated API error messages are still displayed as returned; this change localizes client-owned workflow messages.

The four commercial-configuration workflow composables now receive the active locale translator from `App.vue`. Price-list, tax-profile, approval-policy and cancellation-policy client-owned validation errors, JSON parsing feedback, create/revision/publication confirmations and success notices use the `commercialConfiguration` namespace in both English and Bosnian (`bs-BA`). Dynamic revision/count values are interpolation parameters; domain codes, currency/tax values, statuses, identifiers, API payloads and server-originated errors remain unchanged. Static configuration-view copy is localized in the follow-up presentation slice.

The four commercial-configuration views now use the active Vue I18n locale for their headings, labels, descriptions, help text, placeholders, option labels, revision history and displayed status/tax/cancellation-mode values. The `priceView`, `taxView`, `approvalView` and `cancelView` namespaces are present in both English and Bosnian (`bs-BA`), with shared display-value labels. Stored status values, enum values, identifiers, codes, customer-authored terms, JSON examples and API payloads remain unchanged; only their presentation labels are localized. Together with the workflow-composable messages added immediately before this slice, the four configuration workspaces now have localized static copy and client-owned validation/confirmation/notice feedback.

The staff campaign-review and email-delivery workspaces now use feature-scoped Vue I18n catalogues in English and Bosnian (`bs-BA`). Campaign UI copy includes campaign review, authorization, delivery progress, audited reconciliation, separate retry warnings, privacy notes and display-only status labels; campaign timestamps use the selected locale. SMTP UI copy includes configuration fields, readiness/test states, write-only credential guidance, and the optional Resend callback setup. Their composables receive the same typed translator from the App composition boundary for validation, confirmation prompts and success/error feedback. Provider event identifiers, SMTP configuration values, campaign purpose/audience values, IDs, statuses in API models, and all request payloads remain unchanged.

The staff application shell and session composable now use the selected locale for shell accessibility/navigation labels, language selection, footer copy, session-expiry and permission-denied feedback, generic unexpected-error fallback, and sign-in/sign-out notices. The typed translator is injected from `App.vue`; server-provided API error details remain intact and are interpolated into the localized permission-denied prefix.

Staff API error presentation now maps the stable API problem `code` values (including authentication/session codes) to the active English or Bosnian (`bs-BA`) catalogue. The staff session's shared `showError` path uses this formatter, so booking, campaign and email-delivery workspaces receive localized known errors without duplicating mappings. The public booking-offer capability page uses the same formatter. Unknown/future codes retain the server-provided title and code as a fallback; HTTP status, request ID, server messages, authorization behavior and API response contracts are unchanged. The catalogue covers the API and session-auth error codes present in the current implementation.


A focused localization audit of the commercial booking workspace found remaining hardcoded presentation copy in draft-change and offer-preparation headings/actions, explanatory placeholders, offer reference labels, and the tax summary caption. These are now resolved through the existing `commercialBooking` English/Bosnian catalogue; existing shared keys are reused for delivery reconciliation and approval placeholders. JSON examples, ISO timestamp examples, currency codes and protocol identifiers remain literal technical examples. No workflow state, API payload, domain value or server behavior changes.


A staff-frontend residual-copy and accessibility audit found one remaining untranslated operational fallback in the booking inquiry list: the missing requested-date label. The view now uses the existing `bookingInquiry.dateNotSpecified` English/Bosnian catalogue entry. Other inspected staff views use translated accessible names for navigation/home controls, and their visible button/input labels provide accessible names; the public offer brand label is the product name. Required/email/URL/number constraints rely on native HTML constraint validation, whose browser-generated messages follow the browser locale rather than application copy, so no custom validity behavior was introduced. No API, form semantics, workflow or domain behavior changed.


## Customer locale persistence (PR #62)

Migration 000065 adds an organization-level `default_locale` (initially `en`) and a required `customer_locale` on booking inquiries. Existing inquiries inherit their organization's default locale. Public inquiry submission accepts an optional validated `customerLocale`; omission inherits the organization default. The database command preserves the existing idempotent submission function for compatibility and applies the explicit locale through a narrowly granted wrapper.

The capability-protected public offer projection exposes only the resolved locale alongside the existing customer-safe terms. The public offer page initializes its Vue I18n locale from that projection. The booking-offer email claim projection carries the same locale to the worker, which localizes its subject, body and currency formatting in English or Bosnian. Commercial terms, currency codes, timestamps, offer capabilities and workflow values are unchanged. Organization-default locale administration, customer preference across separate inquiries, reusable versioned email templates and staff-user locale persistence remain follow-up work.


### Locale preference administration

Migration 000066 adds an optional global `users.locale_preference` for `bs-BA` and `en`, with narrowly scoped `eventor_auth` column privileges. The authenticated staff principal exposes the user's saved preference and the active organization's default locale. On sign-in/refresh, the client resolves user preference → organization default → English. The language selector saves to the global user account.

The organization settings view reads the tenant default and whether the active membership has `organization.manage`. Changing the default uses a SECURITY DEFINER command that rechecks that permission, validates the supported locale, and records an audit event only when the value changes. It does not overwrite staff preferences or historical inquiry locales. The organization default is a customer-language fallback, not a forced staff UI locale.


## Public booking form locale experience

The customer-facing booking inquiry form is now available as a dedicated public Vue page at `/book/{organizationSlug}/{formCode}`, separate from the authenticated staff shell and the capability-protected offer page. It loads the safe published-form projection, initializes the interface language from the organization's persisted `default_locale`, and allows an explicit Bosnian (`bs-BA`) or English (`en`) selection. The selected locale is included in the idempotent public inquiry submission and is persisted by the existing migration 000065 locale-aware submission command.

Migration 000067 extends the safe public form projection with `defaultLocale`. The existing `locale` field continues to identify the language of vendor-authored labels/options in the immutable published form revision; it is not silently overwritten by the customer's interface choice. When those languages differ, the page identifies the authored-content language. The form renderer supports the existing v1 field types and delegates authoritative answer validation to the API against the exact published revision. Requester details and answers continue to use the existing encrypted submission path, rate limiting and idempotency controls.

The public page and customer-owned chrome are translated in English and Bosnian. Vendor-authored field labels, descriptions and option labels remain unchanged. Date-time fields require an ISO 8601 value with an explicit UTC offset, matching the existing API validation contract. Public booking form UI has not yet been browser-tested; migration execution, typecheck, unit tests and production build remain pending due to the unavailable local toolchain and exhausted GitHub Actions allowance.
