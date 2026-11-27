# Eventor User Experience and Navigation
## Shared application experience contract v1.0

**Status:** Proposed for product-owner review; no implementation or repository integration authorized.  
**Date:** 2026-11-27. **Inspected main:** `0c5e7a2ddf0a676a89bb75faef1265438dc2ae45`.  
**Proposed destination:** `docs/implementation-design/v0.3/EVENTOR_USER_EXPERIENCE_AND_NAVIGATION_v1.0.md`.  
**Companions:** [OAC technical specification](ORGANIZATION_ADMINISTRATION_CENTER_DESIGN_v1.0.md), [Organization Lifecycle Acceptance](ORGANIZATION_LIFECYCLE_ACCEPTANCE_SCENARIOS_v1.0.md). This document governs presentation and navigation; domain commands, privacy, permissions and lifecycle remain authoritative. All layouts, names, routes and role examples below are proposals, not implemented screenshots or real customer data.

## 1. Objective and design principles (UX-01)

Eventor should feel like one coherent application from initial provisioning through daily administration and the event day. Users should know where they are, what they may do, what requires attention and what will happen if they take an action. The interface MUST guide an authorized user to complete their job without requiring familiarity with the database, deployment internals or source code. It MUST not use a single unrestricted dashboard for every role.

Principles: explicit context; accessible and localized interactions; predictable visual hierarchy; meaningful empty and error states; permissions and readiness reflected but never enforced by the UI alone; safe review before consequential actions; honest freshness and status; independent venue-only operation; reuse owning domain workflows rather than duplicated forms. Avoid navigation overload, giant all-purpose screens, decorative widgets without a task, unbounded lists, modal chains, mandatory setup for irrelevant features or silent defaults. A user should be able to return to the previous task without losing valid draft work, subject to security/expiry and explicit context changes.

## 2. Reconciliation and source hierarchy

| Source | UX contract |
|---|---|
| [Blueprint v1.2](../../blueprint/v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md) §§4,5,21,25–26,35,41,46 | Permission-scoped interface, operational cockpit, branding, guest-safe projections and accessibility |
| [ADR 0001](../../decisions/0001-modular-monolith.md), [0008](../../decisions/0008-modular-staff-frontend.md) | Thin root and modular Vue features, composables and shared primitives; incremental transition, no rewrite |
| [ADR 0003](../../decisions/0003-human-approved-allocation.md), [0004](../../decisions/0004-optional-event-operations-scope.md), [0005](../../decisions/0005-separate-invitations-rsvp-attendance.md), [0006](../../decisions/0006-cross-organization-collaboration.md) | Review/commit, optional profiles, separate credential facts and cross-party ownership |
| [ADR 0007](../../decisions/0007-internationalization.md) | bs-BA/en, stable domain identifiers, locale preference and explicit timezone |
| [ADR 0010](../../decisions/0010-organization-membership-access.md), [0015](../../decisions/0015-email-first-login-and-platform-administration.md), [0017](../../decisions/0017-host-staff-account-bootstrap.md), [0020](../../decisions/0020-host-existing-staff-membership.md) | Credential-first entry, safe membership switching and host provisioning boundaries |
| [ADR 0016](../../decisions/0016-event-rsvp-policy-settings.md), [0021](../../decisions/0021-booking-event-association-commands.md), [0022](../../decisions/0022-event-disruption-publication-and-acknowledgement.md), [0023](../../decisions/0023-permissioned-collaboration-grant-lifecycle.md), [0024](../../decisions/0024-shared-party-names-and-reviewed-grant-acceptance.md) | Versioned RSVP settings, explicit associations, separate notice acknowledgement, reviewed partner access |
| [PAC](PLATFORM_ADMINISTRATION_CENTER_DESIGN_v1.0.md), [TDS](TEMPLATE_DESIGN_STUDIO_DESIGN_v1.0.md), [OAC](ORGANIZATION_ADMINISTRATION_CENTER_DESIGN_v1.0.md) | Distinct management contexts, shared identity/brand/assets and editor, onboarding and organization home |
| [Operating Model](../../OPERATING_MODEL.md), [Roles](../../product/USER_ROLES_AND_PERMISSIONS_v0.1.md), [Roadmap](../../ROADMAP.md) | Provider/organizer/hybrid, role duties, existing milestones |

Current source `apps/staff-web/src/features/application-shell/StaffApplicationShell.vue` and `apps/api/src/staff-workspaces.ts` establish a bilingual header, credential-first login, membership switch and allowed tabs; `App.vue` selects Events when authorized, otherwise a permitted section. The proposed home, responsive shell, global search and setup wizard are additions, not claims of current implementation. Existing contract `/me/workspaces` hints and all server-side grants remain valid. PAC's proposed narrower managed access requires successor review; UX cannot imply owner visibility into restricted records. Do not modify accepted ADRs or v0.2 contract snapshots to achieve visual consistency.

## 3. Workspace taxonomy and context transitions (UX-02)

```text
Installation (PAC: explicitly privileged context)
  └── Organization selection → OAC home (active selected tenant)
       ├── Provider: booking / venue / resource / fulfilment work
       ├── Organizer: events / Registry / invitations / operational work
       ├── Shared: staff / settings / collaboration / reporting / TDS
       └── Authorized event → EOC (event context)
            ├── Planning, sessions, rosters, allocation, readiness
            └── Live: arrival, stations, tasks, alerts and corrections
Separate purpose-scoped entry points: customer, guest, vendor, station, display
```

Hierarchy is context, not authority inheritance. An event-scoped user can enter an allowed event without OAC administration or Registry permission. A provider may only manage venue-side tasks even in hybrid collaboration. External surfaces have distinct credentials/projections and do not expose the staff shell. PAC remains separate management context; normal organization users cannot see a PAC link or global navigation. Enter tenant from PAC only through approved scoped transition under actual actor, with visible grant/expiry banner if support; never impersonate. Return to PAC requires current privileged authority and appropriate authentication, not browser history replay. No implicit switch when following a foreign-tenant URL; ask to select an authorized membership, then resolve with current permission; deny without naming unauthorized tenant/resource.

## 4. Sign-in, first run and organization setup (UX-03)

### Entry decision table

| Condition | Landing behavior |
|---|---|
| Unauthenticated staff | Safe platform brand/login; locale selector; no tenant enumeration, no public organization list from email |
| Pending staff invite | Purpose-bound enrollment surface; verify recipient and identity, accept explicit organization membership; no password reset of existing user through invite |
| Valid credentials, one active membership | Direct selected tenant, subject to required MFA and current session policy |
| Valid credentials, multiple active memberships | Display authorized named choices only after verification; selection completes sign-in; no credentials in browser storage |
| Active account, no active membership | Safe access-unavailable/support guidance; no unauthorized names or registration-as-admin |
| New/partially configured tenant + setup authority | OAC home with guided resumable checklist and actionable missing prerequisites |
| Existing configured tenant + overview authority | Profile-aware organization dashboard; optional setup/reconfiguration accessible in Settings |
| Event/task-only or no overview grant | Most relevant permitted task/event, or safe list/Settings; no empty unauthorized dashboard |
| Authorized explicit deep link | Resolve after current auth/context; show target or safe denial; never bypass setup-dependent command checks |
| Platform-only identity | PAC only when its auth/context requirements met; not a fabricated tenant membership |

Proposed login, enrollment and MFA UX integrates PAC shared identity; keep host bootstrap fallback and ADR 0015 session expiry. Initial GHB administrator need not know UUIDs, tenant slugs or database commands. Sign-in failures non-enumerating; allow paste/password managers, keyboard and proper autocomplete, clear errors without secret echo. Do not enforce arbitrary client-side credential limits that conflict with actual accepted server contract. Never store password, session, MFA recovery code or invitation token in local storage/URL query/logs. Use existing fragment/capability handling where applicable, clear safe URL after redemption. Session expiry preserves no sensitive local draft; guide sign-in and authorized recovery. Onboarding invitation send is explicit; no automatic role based on email domain or existing name.

### Setup wizard wireflow

```text
Welcome → Organization profile → Capabilities → Identity/branding
        → Facilities/resources (if applicable) → Commercial policies (if applicable)
        → Communications/forms/templates → People/responsibilities
        → Review readiness → Explicit relevant service activation → OAC home
```

Steps adapt to profile and permissions, can be resumed or completed in domain screens. Show `Not applicable`, `Required`, `Optional`, `Needs attention`, `Ready` with reason; progress denominator = applicable steps, not a false universal completion score. Branding may inherit safe default; non-email workflows can continue without SMTP; missing seating never blocks booking/RSVP. Owner can proceed to available work while setup incomplete. Each step links to existing owning editor; no duplicate form/config models. Save/back/skip optional/exit, accessible progress and focus; concurrency conflict reload and compare. Readiness checks derived from current server facts; review shows dependencies, affected audience/public links and warnings; activation has explicit separate action. Don't silently publish public forms or create live credentials. Existing customer settings remain intact; no forced reset on upgrade. Setup screen never asks tenant admin for host secrets or platform credentials.

## 5. Canonical navigation (UX-04)

Desktop staff shell: compact header with approved organization brand, tenant name/switch (only multiple authorized memberships), current context, locale/theme, scoped search, notifications, account/support/sign out. Collapsible sidebar with stable grouped items, breadcrumb and page title/action toolbar. Tablet adapts to drawer/compact rail; phone uses accessible drawer and focused task views. Preserve visible organization/event/station name even when space limited. Event and tenant switch are distinct. Use accessible semantic nav/main/header landmarks. Do not render unavailable/unauthorized modules as misleading active links. If a permitted module is not configured, show setup reason and permitted link rather than hiding a legitimate task. Installed but not delivered features never look operational; show explicit unavailable only where useful to administrator. Order not rigid for personal favorites; stable canonical route IDs.

| Group / proposed route ID | Provider default | Organizer default | Hybrid | Owning feature / notes |
|---|---|---|---|---|
| `org.home` Overview | Yes | Yes | Yes | OAC authorized metrics/queue |
| `org.setup` Setup & readiness | Admin | Admin | Admin | OAC readiness |
| `org.calendar` Calendar | Yes | Yes | Yes | Authorized owned resources/assigned events, no source leak |
| `org.bookings` Bookings / inquiries / offers | Yes | Optional | Yes | Existing booking feature, commercial decisions |
| `org.venues` Venues & spaces | Yes | Optional owned venues | Yes | #105 source geometry and versions |
| `org.resources` Resources & services | Yes | Optional | Yes | Owned catalogues/fulfilment |
| `org.events` Events portfolio | Optional | Yes | Yes | #104 events/session/lifecycle |
| `org.registry` Guest Registry | Optional | Yes | Yes | Only organization-scoped Registry grants |
| `event.roster` Guest list | Optional per event | Optional | Optional | Event-specific; Registry separate |
| `event.invitations` Invitations & RSVP | Optional | Optional | Optional | #104/111 and invitation/RSVP grants |
| `event.allocation` Seating & plans | Optional | Optional | Optional | #106, map/approval |
| `event.operations` Operations cockpit | Optional | Optional | Optional | #107 and owning event grants |
| `org.partners` Collaboration & vendor tasks | As needed | As needed | As needed | #110/#112; explicit grant and projection |
| `org.studio` Design Studio & assets | As needed | As needed | As needed | TDS modes/purposes, no implicit send |
| `org.communications` Forms, delivery & campaigns | As needed | As needed | As needed | Existing owning workflows; SMTP under Settings or dedicated authorized subpage |
| `org.reports` Reports/exports | Authorized | Authorized | Authorized | Bounded read/export permissions |
| `org.admin` Administration | Authorized | Authorized | Authorized | Profile, modules, staff/access, policy, brand, governance, audit/support |

These defaults do not restrict cross-profile operation. Venue-only admin may enable event services if deployment supports and policy allows; organizer may manage an owned venue or approved partner projection. Both still require correct role/scope. A limited user sees only authorized navigation, with no unauthorized counts, links, names or disabled controls hinting at restricted records. Use task-focused shortcuts; no UI permission via profile. For OAC and EOC, use a consistent back-to-organization action and breadcrumb (organization → event → subtask). EOC may expose full event planning and live tabs subject to event capability and task role; don't require EOC to perform basic organizer work. Reception/gate operators may go straight to station workspace, with separate station identity and restricted context.

## 6. Role-based landing and task composition (UX-05)

| Example role | Default landing and priority actions | Do not show by default |
|---|---|---|
| GHB organization admin | OAC home, readiness, admin queues, member management, allowed operations | PAC, other tenants, restricted data without grant |
| Director/finance approver | Authorized KPIs, pending decisions with financial context and approved detail | Guest notes/Registry or unrelated account management |
| Booking manager | Inquiries needing review, today's availability, drafts/offers | Organizer confidential data and global policy |
| Venue coordinator | Calendar, venue readiness, reservations/service tasks | Guest list and pricing if ungranted |
| Event manager | Events portfolio / assigned event, programme and readiness | Unassigned events, Registry without explicit scope |
| Registry/guest coordinator | Authorized Registry or assigned event roster, imports and RSVP exceptions | Other tenant profiles, admission by RSVP alone |
| Communications operator | Approved campaigns, TDS if allowed, delivery queue | Forbidden recipient fields, send if only designer |
| Seating manager | Assigned event map, constraints and proposed changes | Unapproved plan publish or unrelated guest history |
| Reception/station | Camera scan/manual lookup, arrivals and safe feedback | Full guest list, bulk export, global dashboard |
| Vendor/task operator | Assigned tasks/deliverables and permitted context | Broad tenant navigation |
| Auditor | Scoped evidence and approved reports | Write actions |

Actual landing derived from current server hints, selected context, capability, role and optional last valid route; unknown or unauthorized route falls back safely. Never store a sensitive last record in shared browser preference. Empty granted scope = no assigned work, not a permission failure; denied = safe access explanation; unavailable = explicit system/configuration reason. Role-specific action toolbar uses allowed operation hints for discoverability only. Authority checked again on each API call and websocket subscription.

## 7. Dashboard and work-item design (UX-06)

Use focused summary cards and prioritized queues, not a wall of counts. OAC overview starts with the user's current organization, date/window/timezone, readiness/alerts, then authorized modules. Provider: open inquiries, awaiting decisions, today/next bookings, venue conflicts/closure, fulfilment. Organizer: upcoming events, sessions, RSVP/guest/plan/task status within authorized scope. Hybrid: both, clearly labeled, no mixing reservation counts and events. Management financial metrics explicit definition and currency; no false revenue from pending offers. Widgets provide current source/time and drill-down with filters. No exposed small sensitive cohorts or inferred forbidden counts. Zero only when actual known zero. Skeleton during load, stale observation badge after disconnect, not-applicable and unknown states distinct; partial widget failure does not make all home unavailable. No simulated counts on production screen. User preferences choose only permitted widgets; role and policy changes re-evaluate. Server provides bounded aggregates, not whole tenant data pulled into browser.

Work-item pattern: status/priority (business-defined), object/owner context, due time, reason, permitted next action, last update and link. Filters and pagination; keyboard and mobile readable. Acknowledgement/read status never constitutes business approval, sending, completion, notice resolution or acceptance of grant. Dashboard actions invoke owning workflow with current data/revision and confirmation when required. Dismiss a noncritical reminder only; do not silently resolve safety/booking conflicts. Task deadlines and alert thresholds approved by tenant/event policy, not guessed.

## 8. Common screen patterns and component system (UX-07)

| Pattern | Required behavior |
|---|---|
| Page header | Context breadcrumb, title, short purpose, current status and primary permitted action; back navigation and safe help |
| List/table | Search, stable filters/sort, pagination/cursor, columns with units and scoped count; selection count, no implicit "all pages" bulk action |
| Detail | Overview, activity/history, related authorized references, actions; immutable snapshot marked and no direct edit |
| Form/editor | Labels/help/required indicator, field validation and summary, draft state, save/cancel, revision/conflict handling, unsaved changes |
| Wizard | Resumable step, actual readiness, dependencies, optional skip, review; no duplicate domain writes |
| Review/approval | Exact target, before/after, impact, revision/digest and policy; explicit choice/reason, actor authority, stale conflict requires rereview |
| Bulk action | Filter/selected IDs and count, affected scope/operation, preview invalid rows, atomic or documented per-item result, explicit confirmation, receipt |
| Import | Select file/worksheet/header, map fields, validation and duplicate review; commit reviewed set; row errors and protected report |
| Export | Scope/filters/columns/format, warnings, approval if required, job progress, safe private download, expiry and audit |
| Timeline/audit | Actual actor, timestamp/timezone, action/result and permitted history; separate notes vs audit; never editable history |
| Map/editor | Scaled zoom, legend/layers, accessible list/numeric alternative, lock/read-only/published indicators, exact revision, no guest source layers |
| Job/receipt | Pending/running/succeeded/failed/cancelled/uncertain distinguished; correlation ID, safe retry/reconcile, never fake success |

Shared tokens: semantic text/surface/border/action/focus/critical/warning/success, typographic scale, spacing, elevation and responsive breakpoints. Use TDS/PAC brand profile as source; no hardcoded GHB identity or logo. Shared controls include buttons, inputs, labels, field errors, dialog, drawer, table, badges, toast/live region, tabs, stepper and focus management. Reserve primary action for task, secondary for alternatives, destructive style for irreversible/high-impact actions. Do not rely on color alone. Keyboard accessible reorder and drag/resize alternatives for email/graphical/venue/seating editors. No requirement for a specific UI library until reviewed M0. Keep feature-level logic out of shared components; use composables and typed API client. No global root orchestration of every command.

## 9. Search, notification and personal workspace (UX-08)

Global search within selected context and effective scope; grouped by permitted resource kinds (booking, event, venue, guest if Registry grant or specifically permitted roster projection, task). Bounded terms/results, debounce and cancel stale request, safe pagination, no unauthorized autocomplete/suggestions/counts/highlights. Search index, if necessary, uses owning authorization at read time; no global unrestricted index or persistent client copy. Deep links carry stable resource reference, not secrets or confidential labels. Recents/favorites store safe route refs and revalidate; remove/deny inaccessible references on revoke/context switch. No cross-org search by default. Search of booking-only organization cannot reveal organizer guests.

Notifications: in-app inbox for scoped pending actions, assigned tasks, system/tenant notices and permitted alerts. Server-derived safe title/context, timestamp, read/ack state; no raw guest contact or sensitive content in toast/browser push. Open reauthorizes; expiry/revoke clears private data. Real-time updates if supported, poll/refresh fallback; read acknowledgement distinct from business decision. External communication from campaign/booking worker remains separate and explicit. No automatic email to all users from dashboard action. Preferences for locale, theme, density, saved view/favorites and optional notice channels are per actual actor/scope, do not alter brand/policy. Sensitive draft data only server-authorized encrypted storage where needed; never local storage of credentials or unrestricted exports.

## 10. Branding, themes and localization (UX-09)

Platform login default and PAC shell use approved platform identity; known public organization/event link may use explicitly approved public brand projection (no membership enumeration); authenticated OAC uses organization identity; EOC resolves event/authorized venue/organization/platform precedence. Mark event branding and owning party clearly, including partner venue not organizer. Guest/customer/display artifacts use pinned published brand and template, not operator's dark mode. User preference light/dark/system/high contrast separate from brand, accessible focus/contrast baseline cannot be overridden. Safe fallback if asset unavailable, invalid theme or storage degraded; never make login/security notice unreadable. Approved logo variants, semantic tokens, fonts/licensed fallback, localized names/contact/legal/footer; no arbitrary CSS/JS/remote asset fetch. TDS owns editing/rendering, PAC governs platform policies, OAC administers tenant properties. Preview/publish with actual revision. Do not invent GHB palette as requirement.

Use `bs-BA` and `en`, ADR 0007 precedence for staff preference → selected org default → deployment fallback en. Locale picker independent of timezone; user changes persisted by existing preference command; offer/RSVP/invitation uses explicit recipient/content locale and approved fallback, no automatic translation of authoritative legal/commercial text. Date/time explicit event/booking timezone, UTC storage, DST ambiguous time handled visibly; Bosnian `DD.MM.YYYY HH:mm` where appropriate per existing feedback; use Intl for number/currency/plural and correct diacritics ČĆŽŠĐ/čćžšđ. No translated strings as enum or key. Localize validation/status/empty states/help, plural, accessible labels, PDF/email where applicable. Missing translation fallback UI with tooling; missing mandatory authored variant blocks or clearly approved alternative. Test long labels and wrap, no clipped text. Future languages supported by architecture, no unverified RTL claim.

## 11. Consequential actions and truthful status (UX-10)

Review/confirmation matrix:

| Action | Preview evidence | Commit outcome |
|---|---|---|
| Publish form/brand/template | Resolved scope/version, locale/validation, public exposure and impacted new outputs | New published revision; never send or issue |
| Offer/confirm booking | Exact request, resource/time, pinned price/tax/policy, authority and conflict recheck | Owning booking receipt; no automatic event |
| Booking/event cancellation or postponement | Correct lifecycle, impact on reservations, commercial consequences, affected party and approved notice | Separate domain transition; no inferred refunds or other party event cancellation |
| Merge Registry | Source/destination, field conflicts, linked records and reviewed correction | Audited command, protected identity/history |
| Plan publish/solver commit | Input version, conflicts/hard rules, diff, approval and explicit human acceptance | New approved revision; no automatic application |
| Issue/send campaign | Exact audience, locale/template/policy versions, digest, recipient count and delivery channel | Explicit authorized issue/queue, acceptance/delivered not conflated |
| Revoke grant/session/credential | Exact scope, effect, reason, expiry and affected tasks | Owning revocation receipt, no unrelated change |
| Support/emergency | Actual actor, exact scope, purpose, expiry/approval and permitted intervention | Audited limited action; no impersonation |
| Suspend/archive/purge | Affected obligations, holds, history, access, drain/recovery and export | Reviewed domain/PAC lifecycle; no silent data loss |

Confirmations must state what changes and what does not; avoid generic "Are you sure?" for high impact. Approval/validation != execution; preview != publication; RSVP != attendance; offer != confirmed booking; notice != effective cancellation/acknowledgement != resolution; queue/provider acceptance != delivery; backup created != restore tested; readiness != authorization. Stale revisions and changed scope require fresh review; no automatic retries of ambiguous mutations. Disable double-click locally but use server idempotency. After timeout show uncertain state with receipt lookup/reconcile path. Separate reason and actual actor from target. Show safe problem code and correlation ID, not raw SQL/network secrets. Audit details accessible only if granted. No UI generic override.

## 12. Specialized public and operational surfaces (UX-11)

| Surface | User experience and boundary |
|---|---|
| Public booking | Branded published form, localized help/validation, submit receipt, scoped offer/cancellation link and status; no staff menu or internal notes, no account required by default |
| Guest invitation/RSVP | Verified purpose-bound access, own event details and response, approved policy/deadline and safe confirmation; no other guests/Registry; invitation not admission |
| Guest Portal | Own approved allocation/wayfinding, sanitized map, guest-safe programme/help, current published revision, access revoked/expired states; no internal layers |
| Gate/station | Explicit assigned station/event, QR camera permission/manual alternative, minimal guest details, large clear duplicate/revoked/accepted feedback, offline queue status; never RSVP as attendance |
| Vendor | Own task/deliverable/due date and approved evidence submission, limited contact/venue projection; no staff navigation or unrelated tasks |
| Display | Read-only sanitized published content, timestamp/revision and safe fallback; no guest directory or admin controls, no confidential layers |
| TDS | Shared library by owner/purpose, rich text/email/graphical editor, keyboard alternatives, preview/review/publish; synthetic default, never issue/send from preview |

Each uses separate credential and purpose validation; authorized links opaque, no secrets in URL query, referer, analytics or logs. Public pages have clear expiry/support path without disclosing forbidden record existence. Offline and reconnect show last synchronized state and pending/error count; no unsupported offline mutation promised. Gate conflicting scans reconciled visibly under domain rules. A public internet outage should not prevent supported LAN operations. EOC live views mark stale data and actual status. QR print/layout subject to TDS readability/security checks.

## 13. Responsive layout, accessibility and assistive technology (UX-12)

Target WCAG 2.2 AA for applicable web surfaces, verified with keyboard, screen reader and manual review plus automated checks. Logical DOM and focus order, skip link, visible focus, keyboard-operable controls, meaningful aria names, semantic headings/tables/landmarks, status announced without disruptive repeated live alerts. Error summary links to invalid fields, instructions not color-only, sufficient contrast, usable zoom/reflow, targets at least WCAG minimum with larger mobile task controls. Avoid hover-only actions, pointer-only drag, tiny scan buttons, animation without reduced-motion preference. Numeric/list controls provide equivalent create/move/reorder/resize/assign functions. Modal focus trap/return and escape, confirmation can be cancelled without side effect. Tables responsive by priority columns and accessible detail/card view, not hidden essential information; horizontal scroll only intrinsically large data/geometry with alternative. Mobile station and vendor tasks use focused screen, camera denial manual path; tablet and desktop full planning. Print styles and PDF accessible semantic content when supported; record limitations rather than claim PDF/UA. Representative viewport acceptance proposed 360, 768, 1280 and 1920 CSS px plus 200% zoom; no clipping/overlap for core workflow. Test Chromium/Firefox and actual supported mobile/device during final acceptance. No mandatory browser-specific API without fallback.

## 14. State, routing and API integration (UX-13)

Illustrative stable route pattern (not existing URLs): `/staff/org/:orgId/home`, `/staff/org/:orgId/bookings/:id`, `/staff/org/:orgId/events/:eventId/overview`, `/.../operations`, `/.../admin/access`, `/.../studio`; distinct private `/platform/...` and public purpose paths. Existing public capability paths and staff tabs remain supported until deliberate compatibility migration; no broken issued links. Route IDs independent of translated labels. Server validates path/selected membership and exact object scope; URL never grants authority. Unknown route safe not-found, foreign authorized membership prompts explicit switch, unauthorized existence not confirmed. Account/session/context changes cancel pending requests, close websocket, clear all tenant data/cache, reset selected event/dialog and refetch allowed navigation; actual session expiry preserved. Existing ADR 0015 page replacement is safe baseline. Never accept URL/open redirect or untrusted actionRef. Save durable drafts through owning authorized service, not local storage of PII. Unsaved state warning before route/context switch only where safe; revoke/expiry clears regardless. Back/forward history reauthorizes; no stale data flash.

| Proposed shared contract | Fields / behavior |
|---|---|
| Session context | Actor ID, selected organization/membership, locale, authorized workspaces, expiry, scope hints; PAC/elevation separately scoped and visible |
| Navigation manifest | Stable route/feature ID, labelKey, context type, available/ready/action hints, child IDs; generated from authorized capabilities; not permission token |
| Readiness | OAC derived per-capability status/reason, owning route ref, source revision and observed time |
| Overview / search | Authorized bounded projections, safe resourceRef and definition/time, no unauthorized count or arbitrary URL |
| Work items / alerts | Typed owning kind/ref, safe title, state/dueAt/time, actionHint and revision |
| Command receipt | Request/correlation ID, target/safe state, current revision, result/uncertainty and next allowed action; actual server outcome |
| Preferences | Actor-scoped locale/theme/density/saved route IDs, no restricted payload; existing saved views reused |

Extend `/me/workspaces` compatibly; API for OAC home/readiness/search/queues as OAC §9. Shared component state is derived from typed response; client cache keyed by actor/context and current authority, no shared global cache across organizations. Read authorization includes subscriptions and downloads, not only route visibility. Transport errors standardized, request ID surfaced for support, optional feature failure isolated. Keep `App.vue` thin; feature routes/composables and shared design system (ADR 0008). No independent UX domain database; persisted preferences/readiness facts only if OAC/PAC owning model requires. No runtime API/schema changes in documentation PR.

## 15. Incremental implementation and dependencies

| Package | Deliverable | Scheduled track |
|---|---|---|
| UX-M0 | Inventory current screen/route/capability mapping, shared design tokens, accessibility and interaction review; no rewrite | OAC-M0 / #104 when scheduled |
| UX-M1 | Incremental shell/context/home and readiness primitives, role landing, shared error/empty/list patterns, secure onboarding UX | #104, PAC shared identity |
| UX-M2 | Provider calendar/booking and venue/resource navigation, map accessibility patterns | Phase 1/#105/#112 |
| UX-M3 | Event portfolio/EOC, seating and guest/station/vendor/display role flows | #104/#106/#107/#110 |
| UX-M4 | Shared brand/locale/theme, TDS and forms, search/reports/preferences | #111/TDS/PAC |
| UX-M5 | Release integration, responsive/manual accessibility and full journeys | #108/Phase 9, OLA |

**Codex continuity:** #104/#112 current work then #105–107, unchanged. UX is a contract for new work and touched features, not a demand to refactor everything now or block existing domain PRs. Preserve existing links, grants, authentication and accepted ADRs. No implementation solely on merge of docs. No environment publication or early acceptance VM. Existing issue requirements remain; use cross-references instead of duplicate UX issues. Later ADR/engineering review selects UI library, routes and performance budgets.

## 16. Measurable UX acceptance criteria

Each test is proposed, not currently passed. Use synthetic fixtures and actual authorized contexts; run API/DB negative cases as well as browser behavior. Cross-reference OLA scenarios.

| ID | Observable outcome | Evidence |
|---|---|---|
| UX-AC-01 | Known/unrecognized credentials do not expose workspace names before verified sign-in; correct one/multi/no-membership outcomes | OLA-02; API/browser |
| UX-AC-02 | Switch tenant/context rotates session per ADR, preserves expiry/actor, clears prior state/streams; unauthorized deep links cannot flash data | OLA-06; browser/concurrency |
| UX-AC-03 | First-login setup resumable and profile-specific; optional skip and blocked prerequisite reason; no forced guest modules | OLA-03 |
| UX-AC-04 | Correct provider/organizer/hybrid navigation and role landing; PAC not visible/accessible to tenant | OLA-04/06 |
| UX-AC-05 | Authorized overview counts/time/filters match fixture; unknown/stale/empty distinguished, partial failure isolated | OLA-04/14 |
| UX-AC-06 | Search/favorites/notifications never expose unauthorized names/counts or old tenant refs after revoke | OLA-06/11 |
| UX-AC-07 | List filter, sort/page, selection and bulk preview accurately represent affected set; stale/invalid review rejected | OLA-07/09/13 |
| UX-AC-08 | Reviewed commands show exact version/impact/reason, actual outcome and safe uncertainty recovery; cancel no side effect | OLA-07–12 |
| UX-AC-09 | Platform/org/venue/event brand preview/publish/fallback works, personal theme independent; previous artifact unchanged | OLA-05 |
| UX-AC-10 | bs-BA/en labels, diacritics, timezone/DST and locale-formatted dates/amounts; mandatory authored translation policy | OLA-03/05/14 |
| UX-AC-11 | Public booking, guest, station, vendor, display limited to own projection; no staff navigation or data leak | OLA-07/09/10 |
| UX-AC-12 | QR camera denial/manual path, duplicate/revoked/queued/reconciled state explicit; RSVP never attendance | OLA-09 |
| UX-AC-13 | Keyboard-only core workflows, focus/error/contrast/labels and map/editor nondrag alternatives; manual assistive tech evidence | OLA-14 |
| UX-AC-14 | 360/768/1280/1920 viewport and 200% zoom representative journeys usable, no inaccessible essential actions | OLA-14 |
| UX-AC-15 | Expired/revoked access clears data and actions; safe error/support receipt, no secrets in browser storage/logs | OLA-06/11/14 |
| UX-AC-16 | Incremental migration preserves existing accepted public links/feature routes and user grants; exact-head regression tests pass | OLA-14/15 |

## 17. Open design decisions and integration

Proposed shell patterns and route names are not binding visual mockups. Validate user research, branding assets, mobile browser/scanner support, library license/accessibility, route compatibility, actual role presets and operational needs. No real GHB assets, venue geometry or data inferred. Navigation profiles are defaults not paywalls. Acceptance thresholds are proposed and must be measured, not claims. Integrate with OAC and OLA after approval via additive design index, architecture, operating model, roadmap, gap analysis and appropriate issue references; preserve Blueprint v1.2 historical snapshot and accepted ADRs. No repository modifications, runtime tests or feature implementation during preparation.

## Approved AGIS specialized station UX — 2026-11-27

[AGIS v1.0](ADMISSION_GUEST_INFORMATION_AND_STATION_MANAGEMENT_DESIGN_v1.0.md) refines UX-02/04/05/07/09/10/11/12/13. OAC exposes scoped station/profile/device administration; EOC exposes event station status/assignment and permitted interventions. The active station has one mode/context: large rapid gate scanner with explicit result and accessible manual path; self-service Info Pult with verified minimal personal view, approved map/text directions, no attendance mutation, privacy timeout and neutral reset; staffed help/seating with permitted lookup and separate reviewed corrections; printing with explicit document/reissue confirmation; passive public display with no personal lookup/action. Mode switching clears old context and data; do not use hidden UI controls as authorization. Distinguish pending, locally provisional, server-confirmed, stale, revoked and disconnected states without relying only on color; preserve bs-BA/en, accessible touch/keyboard and no browser history/cache leakage. Station Designer is constrained, revisioned and shares TDS brand/assets, not an unrestricted script/editor. Original UX-AC-01–16 remain required. This is an approved scope clarification, not a runtime implementation claim or instruction to interrupt the existing #104/#112 → #105–107 sequence. Preserve accepted ADRs, historical Blueprint v1.2, existing domain commands and issue criteria; final integrated acceptance remains Phase 9.
