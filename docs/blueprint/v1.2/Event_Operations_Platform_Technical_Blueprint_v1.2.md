---
title: "Event Operations & Guest Logistics Platform"
subtitle: "Technical Specification and Engineering Blueprint"
author: "Solution Architecture Baseline"
date: "9 November 2026"
version: "1.2"
status: "Extended architectural baseline for detailed design and implementation planning"
---

# Document control

| Item | Value |
|---|---|
| Document | Event Operations & Guest Logistics Platform - Technical Blueprint |
| Version | 1.2 |
| Date | 9 November 2026 |
| Status | Extended architectural baseline; suitable as the starting point for detailed design and implementation planning |
| Product type | Self-hosted, multi-event, web-based operational platform |
| Primary deployment | Private server / intranet, with controlled internet access when required |
| Intended readers | Product owner, solution architect, developers, event administrators, venue coordinators and authorized security personnel |

## Revision history

| Version | Date | Description |
|---|---|---|
| 1.0 | 2026-11-09 | Initial consolidated technical blueprint incorporating the agreed functional scope and additional requirements. |
| 1.1 | 2026-11-09 | Added the persistent Guest Registry, event participation model, guest self-service portal and wayfinding, live Event Operations Cockpit, role-specific staff workspaces, and their data, API, real-time, security, testing and delivery implications. |
| 1.2 | 2026-11-09 | Added organization/venue/event branding inheritance, tenant-aware brand assets and templates, GHB reference venue configuration, generalized floor-position and spatial-feature modelling, spreadsheet-based plan onboarding, and simplified CDI into externally performed prerequisite coordination. |

## How to use this blueprint

This document establishes the product boundary, core domain model, architecture, operational workflows, security model and implementation sequence. Version 1.2 adds configurable organization/venue/event branding, a GHB reference venue portfolio, non-chair spatial allocation for prayer-row and numbered floor positions, an assisted workflow for converting the supplied Excel seating plan into native venue geometry, and a simplified CDI prerequisite record for coordination with the external police authority. It also clarifies that CDI is not an inspection subsystem operated by the platform. Sections 41-46 are controlling for these v1.2 additions and supersede conflicting earlier wording. The blueprint is not yet a database migration set, pixel-perfect UI specification or final API contract; those should be derived during detailed design.

The words **MUST**, **SHOULD** and **MAY** are used in their usual requirements sense:

- **MUST** means required for a correct and safe implementation.
- **SHOULD** means strongly recommended; a deviation needs an explicit reason.
- **MAY** means optional or extensible capability.

# Contents

1. Executive summary
2. Product principles and domain rules
3. Scope and functional modules
4. User roles and permission model
5. Event lifecycle and configuration
6. Guest management specification
7. Venue, room and floor-plan model
8. Allocation and seating engine
9. Allocation resources and assignment data model
10. Plan revisions, approval and distribution
11. Guest cards, invitations and QR credentials
12. RSVP and guest-facing portal
13. Arrival, scanning and check-in
14. Event operations dashboard
15. External prerequisites and CDI coordination
16. Dynamic event-day operations
17. Data model - logical entities
18. Application architecture
19. API design baseline
20. Realtime event contract
21. Security, privacy and audit
22. Non-functional requirements
23. Intranet, internet and resilience model
24. Backup, restore, monitoring and maintenance
25. User interface and navigation map
26. Reporting and export requirements
27. Testing and quality strategy
28. Implementation roadmap and release gates
29. Acceptance criteria for the first production-capable release
30. Key decisions and items to validate before coding
31. Risks and mitigations
32. Requirement traceability summary
33. Persistent Guest Registry and cross-event identity
34. Guest Portal and venue wayfinding
35. Event Operations Cockpit and role-specific staff workspaces
36. Extended domain model and API contracts
37. Real-time synchronization, notifications and consistency
38. Security, privacy and access-control extensions
39. Delivery plan, testing and acceptance updates
40. Technical references
41. Organization, venue and event branding
42. GHB reference venue portfolio
43. Generalized spatial allocation model
44. Spreadsheet floor-plan onboarding
45. External prerequisites and CDI coordination
46. v1.2 data, API, security, delivery and acceptance updates

**Appendices:** A. Example separation-rule language; B. Example live reflow scenario; C. Example event data and operating modes; D. Glossary; E. Guest Registry lifecycle example; F. Guest Portal and wayfinding example; G. Cockpit alert and intervention example; H. GHB reference-plan interpretation notes; I. Branding inheritance example.

# 1. Executive summary

The proposed product is an **Event Operations & Guest Logistics Platform (EOGP)**: a self-hosted application for planning, coordinating and operating events with complex guest lists, venues, seating or zone assignments, controlled guest access, staff-facing plans and arrival tracking.

It is not merely an invitation system and it is not limited to banquet seating. It must model different physical event layouts:

- Banquet rooms with tables and individual seats.
- Theatres and cinemas with fixed rows and numbered seats.
- Conference rooms with classroom, boardroom or cabaret layouts.
- Standing receptions with zones and capacity limits but no individual seats.
- Mixed venues containing several room types, buildings, levels and outdoor areas.

The core rule is that **guest identity, venue geometry, allocation, approved plan revisions, guest credentials and check-in records are distinct but linked domain objects**. A change to a guest or allocation must propagate through the relevant views and generated material without silently corrupting prior approvals or historical records.

The system must support manual work, automated work and a hybrid workflow. Its allocation engine must understand both positive relationships (people who should be together) and negative relationships (people who must not be placed together). Where a conflict arises, an administrator must be able to ask the engine to rearrange affected allocations while preserving locked or unaffected assignments where possible.

CDI is an externally performed prerequisite: the platform records whether coordination is required, who the external authority is, request/scheduling milestones and an authorized completion confirmation. The platform does not perform, prescribe or manage the police inspection itself.

The platform supports an organization/tenant-specific visual identity with controlled venue and event overrides. The brand profile governs the administration shell where appropriate, Guest Portal, invitations, email templates, guest cards, QR passes, signage, printed plans and reports.

The initial reference deployment is Gazi Husrev-beg’s Library (GHB) and its configured event-space portfolio: large, medium and small halls, plus a separately configured mosque/prayer space where operationally relevant. The supplied mosque seating workbook is treated as a source/reference artifact for configuring native geometry, not as a live allocation database.

The platform supports manual, automated and hybrid allocation across tables, fixed seats, rows, coloured zones, numbered floor positions and general capacity pools.

Version 1.1 established three additional platform capabilities as first-class architectural domains. First, a persistent organization-level Guest Registry stores reusable person profiles, while each event has its own participation record and historical snapshot. Second, an optional guest-facing portal allows a verified guest to view their own current allocation on a sanitized interactive venue map and obtain appropriate wayfinding information. Third, the administrator experience is an Event Operations Cockpit: a live, actionable command interface with visual venue status, operational metrics, alerts, activity timeline and role-specific staff workspaces. These capabilities share the same authoritative event data but expose different, permission-controlled projections.

## 1.1 Product goals

1. Maintain a reliable source of truth for events, guests, groups, venues, allocations, access credentials and attendance.
2. Allow guest records to be created, read, updated and deleted or archived through the application, as well as imported and exported in bulk.
3. Model physical spaces and capacities without assuming that every room contains tables.
4. Provide a precise visual floor-plan editor and staff-friendly plan viewer.
5. Perform constrained allocation automatically, manually or through a hybrid workflow.
6. Support live operational changes, including targeted reallocation during an event.
7. Generate branded, configurable guest cards and unique QR credentials.
8. Provide fast, reliable check-in across multiple operator devices.
9. Publish approved plan revisions and make the current approved information easy to view and print.
10. Track externally performed prerequisites such as CDI, including request, scheduling and completion confirmation, without implementing the external authority's inspection procedures.
11. Operate on an intranet by default and be deployable behind a controlled internet-facing reverse proxy when needed.
12. Preserve an audit trail of material changes and approvals.
13. Maintain persistent person profiles that can be reused across events without confusing organization-level identity data with event-specific participation or historical records.
14. Offer an event-configurable guest portal with privacy-filtered seating presentation and venue wayfinding.
15. Provide a live operational cockpit and tailored workspaces so authorized staff can monitor, investigate and act without leaving their working context.
16. Apply organization branding consistently across applications, venues, events, invitations, guest passes and printed outputs, with controlled inheritance and versioning.
17. Reuse versioned venue/space templates and support table, fixed-seat, zone, prayer-row and numbered floor-position allocation.
18. Convert existing spreadsheet floor plans into validated, editable native venue geometry without assuming the workbook itself is the live source of truth.

## 1.2 Non-goals for the first implementation

The following are not prerequisites for the first usable release:

- A full ticket marketplace or payment processor.
- Hotel, flight, transport or vendor procurement systems.
- A full emergency-response or physical-security command system.
- A public social network or guest-to-guest messaging service.
- AI-based identity recognition, face recognition or biometric processing.
- Automatic discovery of security vulnerabilities or automated counter-surveillance procedures.
- Native iOS or Android applications; the initial operator and guest interfaces should be responsive web applications/PWAs.
- Indoor positioning or continuously tracked guest location; initial wayfinding is based on approved static maps, directions and known public entry points.
- Cross-organization/federated Guest Registry sharing; the initial Registry is organization-scoped.

The architecture must not prevent future integrations, but these capabilities should not delay the core product. The platform does not implement police inspection methods, operational security procedures or an internal CDI findings/clearance system.

# 2. Product principles and domain rules

## 2.1 One canonical record, multiple views

A guest is created once and may appear in guest lists, category filters, allocation screens, floor plans, guest cards, reports and check-in screens. These views must never become separate, manually maintained copies of the same data.

## 2.2 Identity is independent of seating

Every guest receives a permanent internal ID. A guest's name, category, organization, RSVP or seat may change without changing the identity record. A QR credential is also distinct from the guest ID and can be revoked and reissued.

## 2.3 Location is hierarchical and typed

A guest's location must be expressible at the level that makes sense for the room type:

- Building / venue.
- Level or floor.
- Room or outdoor area.
- Zone.
- Table, row, seat or admission group, when applicable.

A standing reception guest may have a zone allocation and no seat. A cinema guest may have a row and fixed seat without a table. A banquet guest may have both table and seat.

## 2.4 Allocation is a versioned plan, not a mutable spreadsheet

The system must preserve proposed, approved, published and superseded plan versions. Approved information is immutable as a historical snapshot. A change after approval creates a new revision; it does not silently rewrite the prior approved plan.

## 2.5 Automation proposes; authorized people decide

Automatic allocation must be explainable. The administrator can inspect changes, constraints satisfied, constraints relaxed (where permitted), unassigned guests and solver status before accepting a proposed arrangement.

## 2.6 Safety and operational invariants are stronger than preferences

Capacity, uniqueness and access-control invariants cannot be violated by the optimizer. Preference rules can be traded off according to weights. A user must be told when a requested arrangement is impossible under the current constraints.

## 2.7 Security information is compartmentalized

The public invitation, guest pass, staff seating plan and external-prerequisite coordination record are different information products with different audiences. The application must not assume that everyone who can view the seating plan may view internal guest notes or restricted correspondence.


## 2.8 Person identity and event participation are separate

The persistent person record is owned by the organization-level Guest Registry. Event participation is an event-scoped record linked to that person. Event-specific category, RSVP, attendance, seating, notes, credential and communication state must not be written back into the master profile as if they were universal facts. Each event retains a historical snapshot of the data and decisions applicable at the time.

## 2.9 Guest-facing data is a deliberate projection

The guest portal must never expose the administrator's full floor plan or internal guest records by default. A dedicated guest-visible projection contains only approved public navigation geometry, the authenticated guest's own allocation and event information approved for guest display. Staff and restricted security layers remain separate.

## 2.10 The cockpit is an operational workspace, not a passive report

The Event Operations Cockpit combines live indicators, maps, alerts, timeline and authorized controls. It must show data freshness and operational state, support drill-down, and allow intervention through validated workflows. It must not turn a dashboard shortcut into a bypass of permissions, approvals or audit requirements.

## 2.11 Role-specific views share one source of truth

Administrators, coordinators, operators and guests may receive different interfaces and data projections, but all changes must be validated and committed by the same backend domain services. Realtime updates must be scoped to the recipient's permissions and must not leak fields simply because the client is subscribed to an event channel.

## 2.12 Brand is inherited, scoped and versioned

Organization branding is the default identity for the tenant. A venue may override selected brand properties, and an event may apply an approved event-specific override. The precedence is event override -> venue profile -> organization profile -> platform default. Every generated or published artifact pins the brand revision used, so a later rebrand does not silently change invitations already sent, passes already issued or historical plan PDFs. Personal UI preferences (for example, light/dark mode) never alter the organization's external brand outputs.

# 3. Scope and functional modules

The solution is composed of the following logical modules. They may be implemented within one deployable application and one primary database, with a separate optimization worker where justified. Logical separation is required even when modules share a deployment.

| Module | Responsibility |
|---|---|
| Organization and event administration | Organizations, users, roles, event creation, event settings and lifecycle. |
| Branding and template management | Organization brand profiles, venue overrides, event overrides, asset library, template revisions and branded output generation. |
| Persistent Guest Registry | Organization-level person profiles, identity resolution, deduplication, relationships, profile history and controlled reuse across events. |
| Event guest participation | Event-specific guest membership, category, RSVP, attendance, event overrides, group membership and historical snapshot. |
| Guest management | CRUD, custom fields, tags, groups, relationships, bulk editing, import, export and event-scoped search. |
| Venue and floor plans | Reusable venues, buildings, levels, rooms, zones, floor-plan backgrounds and spatial objects. |
| Capacity and allocation | Tables, seats, rows, zones, capacity pools, reservations and assignments. |
| Seating/allocation engine | Hard constraints, soft preferences, optimization, preview, reflow and solver diagnostics. |
| Plan approval and publication | Review, sign-off, immutable plan snapshots, distribution, print packages and supersession. |
| Guest credentials | Invitation and pass templates, admission QR tokens, portal access tokens, revocation and reissue. |
| Guest Portal and wayfinding | Optional per-event guest self-service, personal allocation view, guest-safe map projection, directions and accessibility-aware navigation. |
| Arrival and check-in | Scanning, manual lookup, attendance, duplicate detection, station management and live status. |
| Event Operations Cockpit | Live event overview, operational map layers, metrics, alerts, intervention controls, activity timeline and health indicators. |
| Staff workspaces | Role-specific dashboards and task queues for reception, seating, venue, check-in, prerequisite coordination and management staff. |
| Notifications and communications | Controlled guest/staff messages, change notifications, delivery status and channel preferences. |
| External prerequisites and coordination | Event tasks performed by external parties, including CDI request/scheduling/completion tracking. No police inspection execution or methodology. |
| Audit and administration | Audit trail, configuration, retention, backup status, monitoring and system administration. |

The Guest Registry, Guest Portal and Cockpit are first-class product domains. The portal may be disabled per event; the Registry and Cockpit remain foundational platform capabilities. Branding is resolved through organization, venue and event inheritance. The v1.2 GHB configuration is a reference dataset, not a GHB-only code path.

# 4. User roles and permission model

Access is role-based, event-scoped and optionally further restricted by zone or information classification. Roles are permission bundles; permissions must be checked by the backend for every protected action. Hiding a button is not authorization.

## 4.1 Proposed roles

The role catalogue is a set of assignable permission bundles; organizations may add event-specific role presets without bypassing the underlying permission checks.

| Role | Typical access |
|---|---|
| Platform administrator | System configuration, organization management, user provisioning, backups and technical administration. Does not automatically receive access to restricted guest/operational data solely by virtue of technical administration. |
| Organization administrator | Manage organization-wide settings, reusable venues, users and events. |
| Event administrator | Full operational control over assigned events, guests, venues, allocations, publication and check-in. |
| Guest-list manager | Guest CRUD, categories, groups, imports, exports and RSVP management. |
| Venue/floor-plan manager | Venue structure, drawings, spatial objects, room capacities and floor-plan revisions. |
| Allocation manager | Manual allocation, rule configuration, optimization runs and allocation approval requests. |
| Plan approver | Review and approve defined plan revisions; cannot alter the plan being approved without creating a new revision. |
| Check-in supervisor | Manage stations, operators, exceptions and attendance corrections. |
| Check-in operator | Scan passes, search limited guest details and record arrival; no general guest export. |
| Floor/zone coordinator | View assigned approved plans and limited guest-location information for assigned areas. |
| Read-only event viewer | View explicitly granted event information and approved plans. |
| Event prerequisite coordinator | Records external requirements, coordinates requests and scheduling, and records authorized completion confirmations. Does not perform or certify the external authority's work. |
| Auditor | Read audit and approval evidence according to assigned scope; no ordinary editing. |
| Guest (portal user) | Access only to their own event-specific portal view using a dedicated, verified portal session; no access to the guest registry or other guests. |
| Guest support operator | Resolve guest lookup and portal access issues using a minimal, event-scoped view; no unrestricted cross-event registry access. |
| Cockpit viewer / management | View selected operational widgets, reports and alerts for explicitly assigned events; no implicit permission to perform interventions. |
| Notification operator | Prepare or dispatch approved event/guest communications within assigned event and channel scope. |

## 4.2 Permission requirements

- Permissions MUST be evaluated against organization, event and module scope.
- Restricted prerequisite attachments or correspondence, if retained at all, MUST have explicit access controls and retention rules.
- A platform administrator MUST NOT automatically inherit access to restricted guest notes or event-specific confidential documents merely because the role can administer the server.
- High-impact actions (publish, approve, revoke credentials, override a constraint, change prerequisite status, correct attendance) MUST be auditable.
- Access to sensitive records SHOULD support step-up authentication or re-authentication.
- The system SHOULD support two-person approval for selected high-impact actions.
- User accounts must be disabled without deleting their historical actions.
- Guest portal access MUST use a guest-specific authorization context and MUST NOT inherit staff roles.
- Registry search, profile viewing, profile export, record merge and attachment access MUST have separately grantable permissions.
- Cockpit widgets, alert details, action controls and realtime subscriptions MUST be permission-filtered server-side.
- A staff workspace is a presentation configuration, not a permission grant; permissions remain independently enforced.

# 5. Event lifecycle and configuration

An event is the top-level operational container. It references one or more venues and may use venue templates, but it owns its own guest list, allocation plans, credential set, check-in sessions, publication revisions and audit context.

## 5.1 Event fields

Minimum fields:

- Event name, code and description.
- Event date/time and configured timezone.
- Organization brand profile, venue brand profile(s), optional event-specific brand override and pinned brand revision for generated materials.
- Event status: Draft, Planning, Ready for Approval, Approved, Published, Live, Closed, Archived, Cancelled.
- Organization/owner and responsible event administrator.
- One or more venue references and session-specific space assignments.
- Resolved organization/venue/event brand profile and pinned brand revision.
- Guest-facing RSVP settings, where enabled.
- Default guest-card template and language.
- Check-in window and configured entrances/stations.
- Operational contacts and optional event-specific notes.
- Data classification and retention profile.

## 5.2 Event state transitions

A status transition must have permission, timestamp and actor. The system should prevent nonsensical transitions, such as moving directly from Draft to Closed. A live event can remain editable, but changes must create new plan revisions or operational change records as appropriate.

# 6. Guest management specification

## 6.1 Guest record

The term “guest” is used in the event workflow, but the persistent identity model distinguishes a **Person** in the organization-level Guest Registry from an **Event Guest** (participation record) linked to that person. The event participation record carries event-specific category, RSVP, status, seating, attendance, event notes and credential references. The master profile carries reusable identity and contact information. A person may exist in the Registry without being invited to any current event. The detailed rules are specified in Section 33.

A guest/event participation record should support:

- Immutable guest UUID and human-readable guest reference.
- First name, last name, display name and optional title/salutation.
- Organization, institution or delegation.
- Category and subcategory.
- Configurable tags and custom fields.
- Gender, where legitimately required for planning, with optional/unknown values and tightly controlled visibility.
- Language and communication preference.
- Contact channels (email, telephone) where collected.
- RSVP status and response timestamps.
- Attendance status (derived from check-in events, not manually treated as RSVP).
- Accessibility or service requirements, with restricted visibility.
- Guest priority and allocation preferences.
- Relationship/group memberships.
- Administrative notes and data provenance.
- Record status: Active, Archived, Deleted/Anonymized (subject to retention policy).

Not every field must be mandatory. Event administrators can configure which fields appear in their forms, lists and exports. Sensitive attributes should be collected only where the event has a genuine operational need.

## 6.2 Full CRUD interface

The application MUST provide native guest creation, viewing, editing and deletion/archive workflows. Importing a spreadsheet is only one data-entry method.

Required interface functions:

- Add a single guest.
- Edit a guest without changing the immutable ID.
- Duplicate a guest record as a starting point while generating a new ID.
- Archive/deactivate a guest while preserving audit history.
- Delete or anonymize a record where policy and retention rules allow it.
- Bulk edit selected records.
- Bulk category/tag assignment.
- Bulk archive and controlled bulk delete.
- Search across configured fields.
- Filter, sort, group and save views.
- Detect likely duplicate guests and merge them through an audited workflow.
- Show data source and last-modified information.

An import must not create an untouchable or special class of record. Imported and manually entered guests use the same schema and can be edited identically. Import matching must distinguish a possible Registry Person match from an existing Event Guest match; the operator must explicitly choose whether to reuse a person, create a new person, or link an existing person to the event. See Section 33.

## 6.3 Import workflow

Supported initial formats: XLSX, CSV and UTF-8 CSV. Additional formats can be added through adapters.

Import steps:

1. Upload file into a quarantine/staging area.
2. Select worksheet and header row where applicable.
3. Map source columns to guest fields.
4. Preview parsed values and data types.
5. Validate required fields, duplicates, categories and malformed values.
6. Choose import behavior: create only, update matched records, or create and update.
7. Choose matching keys (guest reference, external source ID, or carefully configured composite fields).
8. Review conflict summary.
9. Commit import as one controlled batch or in clearly reported batches.
10. Produce a downloadable import report with created, updated, skipped and failed rows.

The system MUST NOT silently assume that two people are the same because their names match. Duplicate matching must be configurable and uncertain matches must be presented for human resolution.

## 6.4 Groups and relationships

Groups are first-class records. Examples include families, couples, delegations, official parties, work teams and organizations.

A group can have:

- Name, type, category and parent group.
- Members and membership roles (lead, member, assistant, partner, security liaison, etc.).
- Group size and allocation preferences.
- Preferred and prohibited co-location relationships with other groups.
- A default allocation scope (same table, same zone, nearby, separate areas, etc.).

Individual guest-to-guest and group-to-group relationships must be supported. Relationship rules must have an explicit scope and priority.

# 7. Venue, room and floor-plan model

## 7.1 Venue hierarchy

Recommended hierarchy:

```text
Organization
  └── Venue (reusable template or event-specific venue)
       └── Building / Site (optional)
            └── Level / Floor / Outdoor level (optional)
                 └── Room / Area
                      ├── Zone(s)
                      ├── Capacity model
                      ├── Spatial objects
                      └── Allocation resources
```

The hierarchy must not force every venue to have a building or every room to have zones. It must support simple single-room events as well as multi-building complexes. A venue portfolio may also group distinct physical sites (for example, the library halls and an associated mosque) under one organization without assuming they share a building or floor.

## 7.2 Room layout types

A room or area has a configurable layout type. The type controls which allocation resources are available, not which visual objects can be drawn.

| Layout type | Allocation model | Examples |
|---|---|---|
| Banquet | Tables containing individual seats | Gala dinner, formal reception |
| Fixed theatre/cinema | Rows and fixed numbered seats | Theatre, cinema, auditorium |
| Classroom | Rows or blocks of desks/seats | Training, conference |
| Boardroom | Table with defined positions/seats | Executive meeting |
| Cabaret | Tables with a subset of seats | Conference dinner |
| Standing/general admission | Zones with maximum capacities; no individual seat required | Reception, standing event |
| Open seating | Capacity pool or optional seat map | Flexible seating |
| Mixed | Multiple resource types and zones in one area | Large mixed-use hall |
| Floor-based / prayer-row | Coloured zones, row segments and optional numbered floor positions; no chair required | Mosque or other floor-seated gathering |
| Numbered floor-position | Discrete non-chair positions grouped by zone/row/section | Assigned places on a carpeted floor |
| Custom | Configurable resource types | Unusual or temporary venue |

A theatre room does not need tables. A standing zone does not need seats. A prayer-row area does not need chairs: it can expose numbered floor positions or only row/zone capacity. A room may have visual objects that are not allocatable resources; visual geometry and assignable capacity are separate concepts.

## 7.3 Capacity model

Each room/zone can define one or more capacity controls:

- Physical maximum occupancy.
- Allocatable individual seats.
- General admission capacity.
- Reserved capacity (staff, performers, media, accessibility, late arrivals, etc.).
- Temporarily unavailable capacity.
- Operational limit lower than physical capacity.

Capacity validation MUST use the strictest applicable limit. A standing zone with capacity 120 can host up to 120 allocated guests without creating 120 seat records. A fixed theatre with 300 fixed seats must not allocate the same seat twice.

## 7.4 Floor-plan import and drawing

Supported background/import formats for the initial release:

- PDF (rendered through PDF.js for browser-side viewing/selection).
- PNG and JPEG.
- SVG as a background/vector asset where safe and supported.

The native editor should also allow creating simple plans without an imported drawing.

The imported floor plan is a background/reference layer. Tables, seats, zones, labels, exits and other operational objects are separate native application objects placed on top. The system must not treat a flattened image as the data model.

## 7.5 Floor-plan editor functions

- Set and change scale using a known measurement.
- Pan, zoom, fit-to-screen and navigate between levels.
- Add, select, move, resize, rotate, copy and delete objects.
- Draw rooms, boundaries, coloured zones, prayer rows, row segments, numbered floor positions and non-allocatable areas.
- Add tables, rows, fixed seats, chairs, stages, minber/lectern, pillars, entrances, exits, footwear areas, doors, service areas, check-in desks and labels.
- Group and lock objects.
- Snap to grid, align and distribute objects.
- Duplicate a table/row/block with automatic unique IDs.
- Configure table shape, seat count, seat numbering direction and orientation.
- Configure row/seat numbering and accessibility positions.
- Show object IDs, capacity, occupancy and allocation status.
- Toggle layers (background, architecture, seating, zones, operations, annotations).
- Import/export a native plan package.
- Compare revisions and show changed objects.
- Validate overlapping seat/resource coordinates and out-of-bound objects.

## 7.6 Coordinate model

Use a normalized logical coordinate system independent of monitor resolution. Store plan-space coordinates and dimensions, not browser pixel coordinates. Each background asset has its own source dimensions and scale calibration. The rendering layer transforms plan-space coordinates to screen coordinates.

Use a stable coordinate unit (for example, millimetres after calibration) for distances and distance-based separation constraints. Store the transform and calibration metadata with the floor-plan revision.

## 7.7 Spatial object types

At minimum:

- Background/image layer.
- Room/area boundary.
- Zone polygon or region.
- Table (round, rectangular, oval, custom polygon).
- Seat/chair.
- Row and fixed-seat block.
- Floor-based row segment and numbered floor position (not necessarily a chair).
- Standing capacity pool.
- Stage/platform.
- Entrance/exit/door (for staff wayfinding only).
- Check-in point.
- Service/support area.
- Annotation/label.
- Restricted/hidden annotation layer (permission controlled).

A spatial object has a type, geometry, layer, stable identifier, optional capacity/resource link, visibility rules and revision metadata.

## 7.8 Non-chair floor positions and prayer-row layouts

A place assignment is a logical allocation unit; it is not required to represent a physical chair. The model MUST support carpeted/floor-seated spaces with coloured zone polygons, optional row/row-segment geometry, optional numbered floor positions, zone-only assignment, row-only assignment and capacity-only assignment. A prayer-row zone can therefore operate without creating chair records.

Visible numbering is scoped to its parent zone/row/section. The label “1” may legitimately appear in more than one place; the internal resource ID remains unique. A human-readable locator is composed from its hierarchy, for example `BLUE / ROW 04 / POSITION 12`.

## 7.9 Non-allocatable features and special areas

The editor must distinguish assignable resources from physical/operational features such as pillars, walls, minber/lectern, ćurs or presentation point, entrances, exits, footwear areas, passages/aisles, service areas and reserved/special-use regions. These features must not be counted as seats. A region can be allocatable, reserved, staff-only, restricted or unavailable. Visibility differs by administrator, staff and guest map projection.

## 7.10 Venue templates and event snapshots

Venue configurations are reusable, versioned templates. An event selects a specific venue/space revision or an event-specific working copy. Updating a master venue template must not silently alter an event already approved or live. An organization can maintain several halls and related spaces even when they are in different physical buildings or sites.

# 8. Allocation and seating engine

This is a core product capability and must be designed as a standalone domain service behind a stable interface.

## 8.1 Allocation modes

1. **Fully manual:** staff select guests/groups and assign them to a resource or zone.
2. **Fully automatic:** the engine allocates eligible guests according to all active constraints and weighted preferences.
3. **Automatic with locks:** administrators lock chosen guests, groups, seats, tables or zones; the engine solves the remaining problem without moving locked assignments.
4. **Category-driven:** allocate selected categories or tags into selected rooms/zones/capacity pools.
5. **Hybrid:** run the optimizer, manually adjust results, lock selected decisions and re-run an affected subset.
6. **Targeted reflow:** reallocate around an operational change while preserving unaffected assignments as far as possible.

## 8.2 Hard constraints

Hard constraints are non-negotiable unless an authorized administrator changes the underlying rule before running the solver. Some invariants are never overrideable.

Non-overrideable invariants:

- One allocatable resource cannot be assigned to more than one guest at the same time.
- One guest cannot have conflicting active allocations for the same event/session.
- Capacity limits cannot be exceeded.
- Inactive, blocked or unavailable resources cannot be allocated.
- The same guest cannot be allocated twice in overlapping sessions unless explicitly modelled as a multi-participant or staff role.
- Allocation must reference a valid event, room and resource.

Configurable hard constraints:

- Guest must be in a specified building, level, room or zone.
- Guest must not be in a specified building, level, room or zone.
- Guest or group must be allocated within a permitted resource set.
- Must-sit-together group members must share the required scope (same table, row block, zone or other configured scope).
- Must-not-be-together relationships must be respected at a configured scope.
- A guest/group must be separated from a person/group at a configured scope.
- Accessibility requirements must be met by suitable resources.
- Reserved capacity must remain unused by ordinary guests.
- Locked assignments must not move during a solver run.

The system must distinguish an immutable system invariant from a user-configured hard constraint that may be edited by someone with the correct permission. An override action must be deliberate, justified and audited; it must never silently bypass an invariant.

## 8.3 Negative relationships: separation and exclusion rules

The engine MUST support instructions such as “Person A and Person B must not be at the same place” and “Members of Group X must be distributed across different zones.”

A separation rule must define:

- Subject: one guest, a set of guests, a group or a category query.
- Target: another guest, group or selection.
- Scope: same seat/resource, same table, same row/block, same zone, same room, same level, same building/site, or minimum physical distance.
- Strength: hard prohibition or soft preference.
- Effective period/session, if relevant.
- Priority/weight for soft rules.
- Reason and visibility classification.
- Whether the rule applies symmetrically (normally yes) or directionally (only where explicitly needed).

Example: “A and B must not be at the same table” is different from “A and B must not be in the same room.” The interface must require the administrator to select the intended scope rather than interpreting the phrase “not together” ambiguously.

For a group of N people that must be separated, the rule can require all members to occupy distinct zones, distinct tables, or a configured minimum count of distinct resources. It must not merely create arbitrary pairwise entries without showing the effective group-level requirement.

The solver must proactively rearrange other guests as necessary to satisfy a new hard separation rule. It must show all proposed moves and state whether the target is feasible. A conflict must not be “solved” by leaving the new rule marked active while retaining a violating allocation.

## 8.4 Soft preferences

Examples:

- Keep couples/families/delegations together.
- Prefer guests from the same organization to sit together or nearby.
- Prefer a particular zone, room, table or row.
- Distribute categories across tables or zones.
- Balance gender distribution where explicitly required and appropriately authorized.
- Keep VIPs in preferred positions.
- Spread VIP guests instead of clustering them.
- Minimize walking distance or movement between rooms.
- Avoid leaving isolated single seats where possible.
- Fill tables efficiently while preserving social/group rules.
- Maintain a preferred ratio or target composition per table/zone.

Each soft preference should have a weight and a visible explanation. Weights are relative scoring factors, not guarantees. The system must show a score breakdown rather than one opaque “AI score.”

## 8.5 Rule priority and conflict resolution

Priority order:

1. Non-overrideable system invariants.
2. Active hard constraints.
3. Locked assignments and protected plan objects.
4. Weighted soft preferences.
5. Tie-breakers (minimize changes, preserve current arrangement, balance occupancy, deterministic ordering).

If hard constraints conflict, the solver returns INFEASIBLE with a useful conflict report. It must not silently downgrade a hard rule. The administrator can revise or deactivate a rule, unlock an assignment or provide more capacity, then run the solver again.

## 8.6 Targeted reflow and live reallocation

The allocation engine must support reflow requests triggered by:

- A new guest or cancellation.
- A VIP or delegation change.
- A new “must not be together” rule.
- A blocked table, seat, row or zone.
- A room/area becoming unavailable.
- A capacity adjustment.
- A late arrival or guest replacement.
- An operational incident requiring a seating change.

Reflow behavior:

1. Capture the current published/working allocation version.
2. Identify affected guests, resources and constraints.
3. Allow the operator to lock unaffected allocations or choose a limited impact scope.
4. Run feasibility checks and optimization.
5. Produce a before/after diff with reason codes.
6. Show guests moved, unchanged, unassigned and any rule conflicts.
7. Require authorized acceptance.
8. Commit atomically as a new allocation revision.
9. Update staff views and, where configured, reissue credentials/cards.
10. Preserve prior revisions and record the actor/reason.

There must be a fast manual override path for an authorized operator, but it must still validate capacity and uniqueness and create an audit event. A quick manual move is not an excuse to leave the system in an internally inconsistent state.

## 8.7 Solver implementation

Recommended first solver: **Google OR-Tools CP-SAT using its C++ interface**, invoked as a controlled optimization worker/job by the Node.js application. This avoids a long-running Python daemon and keeps the solver independent of the main API process.

The optimizer receives a versioned JSON model containing guests/groups, resources, rules, weights, current assignments and lock state. It returns candidate assignments, solver status, objective breakdown, conflict diagnostics and runtime metadata.

Required solver statuses:

- OPTIMAL: best solution found and proven optimal within configured search.
- FEASIBLE: valid solution found, but optimality not proven.
- INFEASIBLE: no valid allocation exists under the active hard constraints.
- UNKNOWN/TIMEOUT: no conclusion within configured limits.
- INVALID: model/input validation failed.

The UI must distinguish FEASIBLE from OPTIMAL. A timeout must not be presented as “no solution.” Solver versions, deterministic seed, time limit and model version must be recorded for reproducibility.

A solver adapter interface must allow a future solver to be substituted without changing guest or venue domain logic.

# 9. Allocation resources and assignment data model

The allocation model must not be tied to one furniture shape.

## 9.1 Resource types

- Individual chair/seat.
- Numbered floor position (a logical assignable place, not a physical chair).
- Row segment or position block.
- Table (as a container of seats, not itself a seat unless configured for open seating).
- Fixed theatre/cinema seat.
- Seat block or row group.
- General-admission zone capacity.
- Standing capacity pool.
- Reserved/accessible capacity pool.
- Custom allocatable resource.

## 9.2 Allocation record

An allocation links a guest or group to one resource or capacity pool for an event/session and plan revision. It should include:

- Allocation ID.
- Event and session.
- Guest ID or group ID.
- Resource/zone ID.
- Allocation status (proposed, confirmed, locked, checked-in, cancelled, superseded).
- Assignment method (manual, automatic, imported, reflow).
- Lock flag and lock reason.
- Rule/solver run reference.
- Effective period.
- Revision ID.
- Created/updated actor and timestamps.

For a zone capacity assignment, the system may allocate a guest to the zone without assigning an exact coordinate or seat. Occupancy counters must be transactionally updated or computed safely to prevent over-allocation during simultaneous changes.

# 10. Plan revisions, approval and distribution

## 10.1 Revision lifecycle

Proposed lifecycle:

`Draft -> Submitted for Review -> Approved -> Published -> Superseded -> Archived`

A plan may be returned for changes or rejected with comments. Approval and publication are distinct: approval confirms the content; publication makes a specific revision available to operational staff and any enabled guest-facing channel.

## 10.2 Approved plan snapshot

An approved plan revision must capture:

- Venue hierarchy and relevant room/zone geometry.
- Background assets and scale metadata.
- Allocatable resource definitions and capacities.
- Guest allocations and display fields appropriate to the plan's audience.
- Rule-set version and solver run reference, where applicable.
- Approval records and comments.
- Document generation settings and output hashes.

Once approved, that snapshot is immutable. Any later edit creates a new revision linked to its parent.

## 10.3 Staff plan viewer

The application must include a dedicated staff viewer that is faster and simpler than the editor.

Capabilities:

- View approved plans by venue/building/level/room/zone.
- Search guest name or guest reference according to role permissions.
- Select a guest and highlight their assigned location.
- Highlight a table, row, seat or zone.
- Show occupancy and arrival state, where authorized.
- Navigate between levels and buildings.
- View current revision, publication timestamp and status.
- Clearly mark a plan as superseded or out of date.
- Print the current approved view.

The viewer must never silently present an older cached plan as current. If offline, it must show the downloaded revision identifier and last synchronization time.

## 10.4 Printing and export

The system should generate:

- Full venue/floor plan PDFs.
- Per-building, per-level and per-room plans.
- Zone-specific coordinator plans.
- Table/seat assignment lists.
- Alphabetical guest-to-seat lists.
- Category/delegation lists.
- Check-in station lists.
- Change summaries between plan revisions.

Print settings should include page size, orientation, scale, margins, legend, labels, color/monochrome mode, audience and revision footer. Sensitive notes or restricted annotations must be excluded from ordinary print templates.

## 10.5 Publication and notification

A publication action creates a distribution record indicating which roles/devices/groups can access the revision. Notifications may be shown in-app and, later, sent through configured channels. Publication must not depend on email or external messaging being available.

# 11. Guest cards, invitations and QR credentials

## 11.1 Template-driven document generation

Guest cards, invitations, signage and printable operational outputs must be template-driven and brand-aware. Administrators can configure:

- Inherited organization, venue and event logo/brand profile and selected brand revision.
- Card dimensions and print layout.
- Guest name, title, category, guest reference.
- Building, level, room, zone, table, row and seat fields as applicable.
- Arrival entrance or instruction fields where authorized.
- Language, typography, colors, background and decorative elements.
- QR code size and placement.
- Optional event-specific text and legal notices.

A guest card must not display a field that does not apply. A standing guest receives a zone/capacity assignment, not an invented seat number.

## 11.2 QR token security

The QR code MUST contain an opaque, cryptographically random credential token or a short opaque lookup reference backed by server-side validation. It MUST NOT contain the guest's name, contact details, category, table number, security notes or other personal data in readable form.

Recommended design:

- Generate a high-entropy random token per credential.
- Store only a token hash or keyed digest where practical.
- Bind credential to guest, event and credential status.
- Support issued, active, revoked, expired and replaced states.
- Allow revocation and reissue without changing guest identity.
- Rate-limit public validation endpoints.
- Do not expose an endpoint that allows enumeration of guest IDs.

A QR credential is a bearer credential; physical possession may permit another person to present it. It does not prove the identity of the presenter. Where identity verification is required, the event's authorized staff must perform that separately according to event policy.

## 11.3 Card generation and revision changes

The system should support individual PDF cards, bulk PDF packs, A4 multi-card sheets, badge formats and reprints. If a guest's seating changes after card issue, the system must mark the old card as potentially stale and support reissue/revocation rules configured by the event. The check-in screen must always retrieve the current allocation from the server rather than trusting the seat printed on the card. The card, invitation, portal and any generated print output must use the event's resolved brand snapshot, while retaining the revision used for reproducibility.

# 12. RSVP and guest-facing portal

RSVP and the Guest Portal are separate capabilities that may be enabled independently per event. RSVP manages the guest's response. The Guest Portal provides a verified, guest-specific view of event information and, when enabled, their current seating/location information and wayfinding.

RSVP minimum capabilities:

- Secure invitation link or token.
- Accept, decline or pending response.
- Confirm attendance for an allowed number of accompanying guests.
- Capture permitted dietary/accessibility requirements.
- Update response until a configured deadline.
- Prevent duplicate or unauthorized responses.
- Provide confirmation or updated pass after approval.

Guest Portal capabilities when enabled:

- Mobile-first web experience/PWA; no mandatory native application or guest account creation.
- Access by a dedicated portal link/token, invitation workflow or supervised kiosk flow.
- Display the authenticated guest's own event details, current location and permitted information only.
- Present an interactive guest-safe floor plan with their own seat/row/zone highlighted.
- Provide building, level, room, entrance, zone, table, row and seat details as applicable to the room layout.
- Provide approved directions and accessibility-aware route options where venue data supports them.
- Refresh when a new allocation revision is published and show when seating information changed.
- Support event-selected languages, inherited tenant/venue branding and approved event-specific content overrides.

Public RSVP and portal pages must not expose the guest list, other guests' details, internal map annotations, staff-only information or restricted operational/security information. Public views must use a sanitized guest-visible venue projection rather than the administrator's working floor plan. RSVP updates can be subject to administrator approval before they affect allocation. Full portal access, token separation, wayfinding and publication behavior are defined in Section 34.

# 13. Arrival, scanning and check-in

## 13.1 Check-in stations

Multiple tablets/phones/laptops can operate as check-in stations at the same time. Each station should be registered or assigned a station identity, entrance, operator and event.

The scanning UI should be optimized for rapid operation, large text, obvious status colors and minimal taps.

## 13.2 Check-in workflow

1. Operator selects event and station/entrance.
2. Operator scans a guest QR credential or searches manually.
3. Server validates credential status and event association.
4. Server retrieves current guest and allocation information permitted for that operator.
5. UI displays valid/invalid/revoked/expired/already checked-in status.
6. Operator confirms arrival where required by event policy.
7. Check-in is recorded with server timestamp, station, entrance, operator and credential reference.
8. Relevant live dashboard and staff views update.

## 13.3 Check-in exceptions

- Unknown credential.
- Credential belongs to another event.
- Revoked or expired credential.
- Credential already used.
- Guest RSVP declined or pending.
- Guest has no allocation.
- Guest's allocation has changed.
- Guest has arrived at the wrong entrance/zone.
- Manual identity lookup required.
- Offline station cannot validate a token immediately.

Every exception must have an explicit response path. Duplicate scans must not create duplicate attendance records. Corrections must be auditable and should use compensating records rather than deleting history.

## 13.4 Offline check-in

Offline support should be a planned capability, not an afterthought. The first online release may require a live server connection, but the architecture should support a later PWA mode that downloads a limited, encrypted, time-bounded event check-in package to an authorized device.

Offline package requirements:

- Contains only the minimum fields needed at that station.
- Has event ID, plan revision, generated time and expiry.
- Is encrypted at rest on the device where platform support permits.
- Does not contain prerequisite coordination data or unrelated guest records.
- Uses locally recorded scan events with unique IDs.
- Syncs when connectivity returns.
- Detects duplicate/conflicting scans across stations and resolves them for supervisor review.
- Can be remotely invalidated when the device reconnects.

Offline mode must clearly identify that validation is local and may not reflect changes made after the package was downloaded.

# 14. Event operations dashboard

The administrator dashboard is the **Event Operations Cockpit** and the default operational landing workspace for authorized event administrators. It is an interactive command interface, not merely an analytics page. It combines an at-a-glance event picture, live venue map, operational indicators, alerts, activity timeline, task queues and context-aware controls. The Cockpit must render the active organization/venue/event brand profile. It may show a restricted, non-sensitive prerequisite status but not external inspection procedures or confidential reports.

## 14.1 Core indicators

- Total guests and RSVP status distribution.
- Allocated / unallocated guests and allocation exceptions.
- Capacity, occupancy and remaining capacity by venue, building, level, room and zone.
- Checked-in / not arrived / exception counts and arrival trend.
- Guest arrivals by entrance and scanner station health.
- Plan revision, approval and publication status.
- Portal access and guest seating-change notification status, where enabled.
- Outstanding operational changes, unresolved alerts and overdue tasks.
- External-prerequisite status summary (for example, CDI request pending or completion recorded), without exposing restricted correspondence or attachments.

## 14.2 Search and navigation

A global event search should locate a guest, table, seat, zone, room, allocation, alert, task or check-in record within the user's permissions. Selecting an item opens a contextual panel with permitted details and available actions. Registry-wide person search is a separate permission and must not be inferred from event search access.

## 14.3 Live updates

The UI should receive server-pushed updates for changes such as allocation accepted, plan published, guest checked in, capacity changed, portal assignment changed, alert raised/resolved and station exception raised. Realtime events are notifications to refresh authorized data; the client must not treat pushed payloads as a replacement for backend authorization.

The full cockpit layout, role-specific workspaces, alert lifecycle, safe intervention controls, stale-data indicators and operating procedures are defined in Section 35.

# 15. External prerequisites and CDI coordination

## 15.1 Purpose and boundary

CDI is an externally performed task carried out by the competent police force when the event organizer or relevant authority determines that it is required. The platform is not the inspecting authority and does not execute, supervise or prescribe the inspection. The application provides a lightweight prerequisite record so the event team can plan, request, schedule and confirm completion.

CDI is one example of a broader **External Prerequisites & Coordination** capability. Other examples may include external permits, venue approvals, authority notifications, contractor certifications or other pre-event requirements. The event organization configures which task types apply.

## 15.2 CDI requirement determination

- An authorized event administrator or prerequisite coordinator records whether CDI is required for the event.
- The application MAY show an advisory prompt based on configured event attributes (for example, expected attendance or VIP profile), but it MUST NOT independently declare a legal or police requirement.
- The requirement decision, its author, date and optional rationale are auditable.
- If CDI is not required, the event record may be marked “Not required” with an optional reason/reference.
- If CDI is required, it may be configured as a readiness gate that prevents the event from reaching the configured “Ready” state until completion is recorded or an authorized exception is documented.

## 15.3 Coordination lifecycle

Suggested statuses:

`Not assessed -> Not required | Required -> Request pending -> Request submitted -> Scheduled -> Completed`

Additional statuses: `Delayed`, `Cancelled` and `Exception approved`. Status transitions require permission, timestamp, actor and optional note. The system should allow a request to be recorded as submitted without assuming the police have acknowledged or accepted it.

Minimum fields:

- Event and optional venue/space reference.
- Prerequisite type and configured label (for example, CDI).
- Mandatory/readiness-gate flag.
- Responsible external authority/organization (for CDI, the competent police force).
- Internal coordination owner.
- Request submission date and optional external reference number.
- Scheduled date/time, if provided by the authority.
- Completion date/time.
- Completion confirmation source/actor and a minimal reference.
- Status history, notes and optional restricted supporting document reference.

No external police account or integration is assumed. A future integration may be added only where an official interface is available and authorized.

## 15.4 Data minimization and permissions

The platform SHOULD retain the minimum coordination metadata needed to demonstrate that the prerequisite was requested, scheduled and marked completed. It SHOULD NOT collect police operational methods, inspection checklists, sensitive findings, tactical information, device/location details or full confidential reports as ordinary EOGP data.

If an organization has a legitimate and approved reason to retain a completion document, the file must be stored in restricted storage, with explicit access, retention and download auditing. A status-only completion record is the preferred default.

General event staff may see only the high-level status needed for event readiness. The Cockpit may display “Required / request submitted / scheduled / completion recorded” without exposing correspondence. Guest cards, QR codes and the Guest Portal MUST NOT contain prerequisite or police information.

## 15.5 Readiness and responsibility

The application records that an authorized organizer has received or recorded confirmation of completion. It does not certify the adequacy, scope or result of the external inspection. The responsible police authority retains full responsibility for the inspection and any formal decision. Event readiness rules must clearly distinguish “completion recorded” from a legal or security guarantee.

## 15.6 Explicit exclusions

The CDI capability does not include police personnel assignment, internal inspection execution, sensitive inspection procedures, detection methods, findings management, technical counter-diversion instructions or an approval workflow purporting to replace the police. Such procedures remain with the competent external authority.

# 16. Dynamic event-day operations

A live event is expected to change. The platform must support changes without losing the approved baseline or confusing staff about which plan is current.

## 16.1 Operational change record

Every material event-day adjustment should create a change record containing:

- Change ID and event.
- Initiator and timestamp.
- Reason/category (guest change, capacity, room issue, safety, security instruction, accessibility, operational correction, other).
- Affected guests/resources/areas.
- Before and after allocation references.
- Proposed and accepted by.
- Impacted card/print/staff-plan outputs.
- Status (Raised, Assessing, Proposed, Approved, Applied, Rejected, Closed).

Sensitive reason descriptions can be restricted; ordinary staff may see only the action they need to perform.

## 16.2 Live reallocation rules

- Keep unaffected guest assignments locked by default for targeted reflow.
- Clearly indicate if a requested change would move other guests.
- Prevent conflicting simultaneous modifications using revision checks/optimistic concurrency.
- Require a reason for emergency override actions.
- Publish a new current revision when a change affects staff operational plans.
- Mark old printed plans as superseded where possible.
- Ensure check-in always displays the latest server-side allocation.
- Provide a “what changed since last approved plan” view.

## 16.3 Incident/issue board

A lightweight event issue board should record operational issues and actions. It is not a replacement for a dedicated incident command system. Issues may link to affected rooms, plans, guests or seating changes. Access to security-sensitive incident details is permission controlled.

# 17. Data model - logical entities

The following is the initial logical model. Physical tables, indexes and exact normalization will be designed in database design.

## 17.1 Organization, branding and access

- `organizations`
- `brand_profiles`
- `brand_profile_revisions`
- `brand_assets`
- `brand_template_assignments`
- `event_brand_snapshots`
- `venue_brand_overrides`
- `event_brand_overrides`
- `users`
- `user_credentials` or external identity references
- `roles`
- `permissions`
- `role_permissions`
- `user_role_assignments` (scoped to organization/event/module)
- `service_devices` / `operator_stations`

## 17.2 Events

- `events`
- `event_sessions`
- `event_settings`
- `event_contacts`- `event_status_history`

## 17.3 Guests and relationships

- `guests`
- `guest_custom_field_definitions`
- `guest_custom_field_values`
- `guest_categories`
- `guest_tags`
- `guest_tag_assignments`
- `guest_groups`
- `guest_group_members`
- `guest_relationships`
- `guest_import_batches`
- `guest_import_rows`
- `guest_notes` (permission controlled)
- `guest_contacts` (permission controlled)
- `rsvp_responses`

## 17.4 Venue and floor plans

- `venues`
- `venue_buildings`
- `venue_levels`
- `venue_rooms`
- `venue_zones`
- `floor_plan_revisions`
- `floor_plan_assets`
- `spatial_objects`
- `spatial_object_groups`
- `spatial_features` (non-allocatable landmarks/obstacles)
- `spatial_regions` (zones, reserved areas, polygons)
- `spatial_rows` / `row_segments`
- `source_plan_artifacts` (original XLSX/PDF/image plus hashes and provenance)
- `source_plan_mappings` (source worksheet/cell/region to native object mapping)
- `allocation_resource_definitions`
- `allocation_resources` (actual seats, rows, capacity pools, tables where allocatable)
- `resource_capacity_limits`

## 17.5 Rules and allocation

- `allocation_rules`
- `allocation_rule_subjects`
- `allocation_rule_targets`
- `allocation_rule_scopes`
- `allocation_runs`
- `allocation_run_diagnostics`
- `allocation_revisions`
- `guest_allocations`
- `allocation_locks`
- `allocation_change_records`

## 17.6 Publication and documents

- `plan_approvals`
- `plan_publications`
- `plan_distribution_targets`
- `document_templates`
- `generated_documents`
- `document_generation_jobs`

## 17.7 Credentials and arrival

- `guest_credentials`
- `credential_events` (issued, revoked, replaced, expired)
- `checkin_stations`
- `checkin_sessions`
- `checkin_records`
- `checkin_corrections`
- `offline_sync_batches`
- `offline_sync_conflicts`

## 17.8 External prerequisites and audit

- `event_prerequisites`
- `prerequisite_status_history`
- `external_parties` (optional reusable police/authority directory; no external account is assumed)
- `prerequisite_references` (minimal reference metadata; restricted attachments are optional and should be avoided unless policy requires them)
- `audit_events`
- `security_events`
- `retention_policies`

## 17.9 Key relationship notes

Version 1.2 extends this baseline with tenant/organization/venue brand profiles, brand asset and template revisions, generalized spatial features and non-chair allocation resources, event prerequisites and spreadsheet source-plan artifacts. The complete additions and relationship constraints are defined in Sections 41-46.

- A guest belongs to an organization and can be associated with one or more events through an event guest membership, allowing guest data to be reused without forcing every event to share RSVP or allocation status.
- A guest's event-specific data (category overrides, RSVP, event notes, permissions and allocation) belongs to the event membership, not the global person record.
- A venue can be reused across events, but each event uses a specific venue/floor-plan revision or event-specific copy.
- An allocation points to a resource or capacity pool and an immutable allocation revision.
- A guest credential points to a guest/event membership and is not the guest's primary key.
- Check-in records are append-only events; corrections create compensating records.
- External prerequisite records reference events and optionally venues/sessions. They store coordination metadata and completion confirmation, not the external authority's inspection procedures or findings.
- Every mutable domain object should carry created/updated timestamps and actor references; immutable history is stored separately.

# 18. Application architecture

## 18.1 Recommended deployment style


Version 1.1 adds separate application workspaces for administration/cockpit, staff operations, guest portal and check-in. The Guest Registry is organization-scoped; event participation is event-scoped. Guest-facing pages use a constrained API and sanitized venue projection. See Sections 33-38.
Use a **modular monolith** for the primary application. The modules have clear boundaries and interfaces, but run as one main API/application deployment. Add separate worker processes for asynchronous work and the optimization engine where needed. This is simpler to deploy, back up and operate than starting with many microservices.

**Client tier:** Desktop browsers, tablets and phones connect over HTTPS. The application is responsive and PWA-capable.

**Edge tier:** A reverse proxy terminates TLS, applies security headers and rate limits, and routes intranet or public hostnames to the application. Public and staff routes can be separated by hostname and policy.

**Web tier:** Vue 3 + TypeScript provides the event administration, floor-plan editor, staff plan viewer, guest portal and check-in interfaces.

**Application tier:** A Fastify API exposes REST endpoints and authorized WebSocket events. Its modular domains cover authentication, tenant/organization configuration, branding, guests, venues, floor plans, allocation, plans, credentials, check-in, operations, external prerequisites and audit.

**Data tier:** PostgreSQL stores the transactional domain data. A PostgreSQL-backed job queue handles imports, PDF/card generation, reports, notifications and offline-package preparation. Private local/NAS storage holds uploaded floor-plan assets and generated documents.

**Optimization path:** Allocation jobs are passed to an OR-Tools CP-SAT C++ worker. The worker returns a candidate solution and diagnostics; the API validates the result against the current revision before showing a preview or allowing a commit.

This keeps the main application deployable as a small number of Linux services while isolating CPU-intensive or failure-prone work from request handling.

## 18.2 Proposed technology baseline

The following baseline is recommended for the initial GHB deployment and remains replaceable where validation identifies a better fit.

| Layer | Proposed technology | Reason |
|---|---|---|
| Frontend | Vue 3 + TypeScript + Vite | Fits the existing development skill set; strong component model and TypeScript support. |
| UI styling | Tailwind CSS with a consistent component layer | Fast, maintainable responsive UI; avoid ad-hoc styling per screen. |
| Backend | Node.js + Fastify + TypeScript | Lightweight API framework with TypeScript support and schema validation. |
| Database | PostgreSQL | Strong relational integrity, transactions, concurrency control and mature backup/restore tooling. |
| Data access | SQL migrations + typed query layer such as Kysely | Keep schema changes explicit and queries type-aware without hiding SQL behavior. |
| Realtime | WebSockets, with server-side authorization on every subscription | Live event dashboards, allocation changes and check-in updates. |
| Background jobs | PostgreSQL-backed queue initially | Avoid adding a mandatory Redis/Valkey dependency for the first deployment. |
| Floor plan | Native SVG-based editor/viewer | Precise coordinate-based objects, zoom, selection and scalable rendering. |
| PDF background | Mozilla PDF.js | Browser-side rendering of imported floor-plan PDFs. |
| QR scanning | `@zxing/browser` or equivalent maintained browser scanner | Camera-based QR decoding in a web application. |
| QR generation | Node-compatible QR generator | Generate opaque-token QR images for cards. |
| Optimization | Google OR-Tools CP-SAT in C++ worker | Constraint programming for allocation and reallocation problems. |
| Documents | Server-side HTML/CSS-to-PDF pipeline | Reproducible guest cards, reports and plan printouts. |
| File storage | Local filesystem or NAS with private paths | Self-hosted file ownership, retention and backup. |
| Deployment | Linux system services behind reverse proxy | No container requirement; simple service supervision and logs. |

Exact package versions must be pinned during implementation after compatibility review. The architecture should not depend on a hosted SaaS database or proprietary cloud-only functionality.

## 18.3 Backend module boundaries

Recommended modules:

- `auth` - login, sessions, MFA, identity provider integration.
- `authorization` - permissions and scope evaluation.
- `organizations` - organizations and reusable settings.
- `events` - event lifecycle and sessions.
- `guests` - guests, memberships, categories, groups, relationships and imports.
- `venues` - venue hierarchy and room configuration.
- `floorplans` - assets, revisions and spatial geometry.
- `resources` - seats, rows, tables, capacity pools and availability.
- `allocation` - rules, runs, proposals, reflow and commits.
- `plans` - approvals, publication and staff distribution.
- `documents` - templates, PDF generation and print jobs.
- `credentials` - QR issuance, validation, revocation and reissue.
- `checkin` - station/session/attendance workflows.
- `operations` - dashboard and event-day change/issue records.
- `branding` - brand profiles, asset governance, template inheritance and event brand snapshots.
- `prerequisites` - externally performed event tasks, including CDI coordination.
- `audit` - append-only audit events and sensitive access records.
- `admin` - configuration, health, retention and backups.

Modules should communicate through application services and domain events, not by importing another module's database internals.

## 18.4 Concurrency and transaction model

PostgreSQL is the source of truth. Critical operations must use database transactions and appropriate locking/uniqueness constraints.

Examples:

- Allocation commit must prevent two concurrent users from assigning the same seat.
- Zone capacity updates must prevent concurrent over-allocation.
- Check-in must enforce a unique active attendance record per guest/event/session unless multiple entry/exit cycles are explicitly configured.
- Plan publication must atomically publish one revision and supersede the previous current revision.
- A reflow commit must fail cleanly if its source allocation revision has changed since the solver began.

Use optimistic concurrency with revision numbers for most editing. Use row/advisory locks or serializable transactions only for the critical commit paths where required. Do not hold a database transaction open while a solver or PDF job runs.

## 18.5 Background work

Long-running work must be asynchronous and trackable. Jobs need status, progress where practical, retry policy, error details and actor/event context.

Job types include imports, large exports, solver runs, PDF/card generation, plan rendering, offline package preparation, reports and notification dispatch.

## 18.6 File storage

Store uploaded assets outside publicly served application directories. Database records hold metadata, hashes, storage keys, access classification, retention and revision links. File access must be mediated by an authorized API or short-lived signed route; do not expose predictable paths.

# 19. API design baseline

The API surface must now include organization-scoped Registry APIs, event participation APIs, guest portal APIs, public venue projection/wayfinding APIs, cockpit snapshot/alert/timeline APIs, and role-scoped workspace configuration. The detailed endpoint families and authorization boundaries are defined in Section 36.

The API is versioned from the beginning, for example `/api/v1`. Use JSON request/response schemas, consistent error envelopes, pagination and correlation IDs. Do not expose internal database IDs where an opaque public identifier is more appropriate.

Representative endpoint groups (illustrative, not final contract):

| Area | Example routes |
|---|---|
| Organizations / branding | `GET/PATCH /api/v1/organizations/{organizationId}/brand-profile`, `POST /api/v1/brand-assets` |
| Venue branding | `GET/PATCH /api/v1/venues/{venueId}/brand-profile` |
| Event brand override | `GET/PATCH /api/v1/events/{eventId}/brand-override` |
| Templates | `GET/POST /api/v1/organizations/{organizationId}/templates`, `POST /api/v1/templates/{templateId}/revisions` |
| Events | `GET/POST /api/v1/events`, `GET/PATCH /api/v1/events/{eventId}` |
| Guests | `GET/POST /api/v1/events/{eventId}/guests`, `GET/PATCH/DELETE /api/v1/guests/{guestId}` |
| Imports | `POST /api/v1/events/{eventId}/guest-imports`, `GET /api/v1/imports/{jobId}` |
| Groups | `GET/POST /api/v1/events/{eventId}/groups`, `POST /api/v1/groups/{groupId}/members` |
| Venues | `GET/POST /api/v1/venues`, `GET/PATCH /api/v1/venues/{venueId}` |
| Floor plans | `POST /api/v1/rooms/{roomId}/floorplan-revisions`, `GET /api/v1/floorplans/{revisionId}` |
| Resources | `GET/POST /api/v1/rooms/{roomId}/resources`, `PATCH /api/v1/resources/{resourceId}` |
| Source plans | `POST /api/v1/rooms/{roomId}/source-plan-artifacts`, `POST /api/v1/source-plans/{artifactId}/conversion-jobs` |
| Prerequisites | `GET/POST /api/v1/events/{eventId}/prerequisites`, `PATCH /api/v1/prerequisites/{prerequisiteId}`, `POST /api/v1/prerequisites/{prerequisiteId}/record-completion` |
| Rules | `GET/POST /api/v1/events/{eventId}/allocation-rules`, `PATCH /api/v1/allocation-rules/{ruleId}` |
| Solver | `POST /api/v1/events/{eventId}/allocation-runs`, `GET /api/v1/allocation-runs/{runId}` |
| Allocations | `GET /api/v1/events/{eventId}/allocations`, `POST /api/v1/allocation-runs/{runId}/accept` |
| Reflow | `POST /api/v1/events/{eventId}/reflow-requests` |
| Plans | `POST /api/v1/allocation-revisions/{revisionId}/submit`, `POST /api/v1/plan-approvals/{approvalId}/approve`, `POST /api/v1/plans/{revisionId}/publish` |
| Documents | `POST /api/v1/events/{eventId}/document-jobs`, `GET /api/v1/document-jobs/{jobId}` |
| Credentials | `POST /api/v1/guests/{guestId}/credentials`, `POST /api/v1/credentials/{credentialId}/revoke` |
| Check-in | `POST /api/v1/checkin/scan`, `POST /api/v1/checkin/manual`, `GET /api/v1/events/{eventId}/attendance` |
| Audit | `GET /api/v1/events/{eventId}/audit` (permission restricted) |

Important API rules:

- Use `POST` for commands that create jobs or produce state transitions.
- Use `PATCH` for partial updates and `DELETE` only where deletion is permitted.
- Use idempotency keys for retryable commands such as check-in and plan publication.
- Include `expectedRevision` or an ETag/If-Match token when committing changes based on a known version.
- Return machine-readable validation and conflict details.
- Never trust event IDs, role claims or guest IDs supplied by the client without server-side scope validation.

# 20. Realtime event contract

The event contract is extended to include Registry-profile changes (only for authorized Registry subscribers), event participation changes, portal-visible allocation updates, wayfinding/publication revisions, cockpit indicators, alert lifecycle changes, staff task changes, scanner health and notification delivery state. The transactional outbox and event payload rules are defined in Section 37.

WebSocket messages should be small invalidation/event notifications. The client then reloads the relevant authorized data.

Proposed event names:

- `guest.updated`
- `guest.rsvp.changed`
- `allocation.proposed`
- `allocation.accepted`
- `allocation.changed`
- `resource.blocked`
- `capacity.changed`
- `plan.submitted`
- `plan.approved`
- `plan.published`
- `credential.revoked`
- `checkin.recorded`
- `checkin.exception`
- `operation.issue.updated`
- `prerequisite.status.changed` (permitted event administrators and cockpit views; no confidential external content)

Realtime subscriptions must be authorized by organization, event and scope. Prerequisite events carry only status/reference changes and must not carry confidential external reports or inspection details.

# 21. Security, privacy and audit

Version 1.2 increases the sensitivity of the platform because it stores reusable person profiles and provides guest-facing access. Cross-event Registry authorization, purpose limitation, profile access auditing, dedicated portal credentials, map projection controls and cockpit field-level filtering are mandatory. Detailed additions are in Section 38.

## 21.1 Authentication

- Strong password hashing using a modern password-hashing algorithm.
- MFA for administrators and users with sensitive permissions.
- Secure, HTTP-only, same-site session cookies for browser sessions.
- Session expiry, rotation and revocation.
- Optional OIDC/LDAP/Active Directory integration later; local accounts remain available for isolated intranet deployments.
- Rate limits and lockout/risk controls for authentication and public endpoints.

## 21.2 Authorization

- Backend authorization on every API action and WebSocket subscription.
- Least privilege by default.
- Event-scoped roles and module-specific grants.
- Tenant/organization isolation and separate permissions for Registry fields, restricted guest notes and prerequisite attachments.
- No direct browser-to-database access.
- Default deny for unknown permissions.

## 21.3 Network deployment

Intranet mode:

- Bind services to private interfaces or localhost behind a reverse proxy.
- Use internal DNS and TLS where feasible.
- Restrict database and file storage ports to the application host/network.
- Keep administrative access on a separate management path where possible.

Internet mode:

- Expose only the reverse proxy over HTTPS.
- Keep database, worker and storage services private.
- Use MFA for privileged accounts.
- Apply strict rate limiting, request-size limits and security headers.
- Restrict public routes to invitation/RSVP and credential validation functions.
- Do not expose administrative routes or unrestricted file access publicly.
- Consider VPN or identity-aware access for staff administration, particularly for high-profile events.

## 21.4 Data protection

- Encrypt network traffic with TLS.
- Encrypt backups and sensitive file storage.
- Keep secrets out of source control and logs.
- Redact access tokens and personal data from application logs.
- Provide configurable retention and deletion/anonymization policies.
- Keep restricted guest notes and any prerequisite confirmation attachments separate from ordinary event records; do not store police inspection findings or tactical material.
- Record exports and downloads of sensitive information.
- Minimize data collected and displayed on check-in screens.

## 21.5 Audit trail

Audit events should be append-only and include actor, timestamp, event scope, action, object reference, before/after summary, reason, source device/session and correlation ID. Sensitive records should have a separate access audit that records views and downloads, not only modifications.

Audit logs should be protected from ordinary application editing. Retention and export policies must be configurable. A tamper-evident strategy (for example, chained hashes or periodic signed exports) is recommended for high-assurance deployments, but must not be advertised as tamper-proof without a verified design.

# 22. Non-functional requirements

Additional provisional targets for the Registry, Guest Portal and Cockpit are specified in Section 38. They must be validated against expected event sizes, concurrent users, network conditions and hosting capacity during Phase 0 before being treated as production service-level commitments.

Initial targets below are planning targets and must be validated with realistic datasets and hardware during performance testing.

| ID | Requirement | Initial target |
|---|---|---|
| NFR-01 | Guest list responsiveness | Filter/search 10,000 guest records with typical filters in under 2 seconds on an adequately sized local server. |
| NFR-02 | Concurrent users | Support at least 50 simultaneous authenticated staff users in initial production sizing; design to scale higher. |
| NFR-03 | Check-in throughput | Support multiple scanning stations and avoid duplicate processing; validate sustained throughput with representative devices. |
| NFR-04 | Allocation scale | Support 1,000 guests and several thousand resources/rules in an initial benchmark; solver time limit configurable. |
| NFR-05 | Availability | Target 99.5% service availability during planned event windows, excluding infrastructure/network failure outside the application. |
| NFR-06 | Recovery | Document and test database/file restore; target RPO/RTO must be set per deployment. |
| NFR-07 | Audit | Material changes and sensitive access are traceable. |
| NFR-08 | Accessibility | Admin and check-in interfaces support keyboard navigation, readable contrast and scalable text. |
| NFR-09 | Browser support | Current supported Firefox, Chromium-based browsers and Safari where practical; test camera permissions on target mobile devices. |
| NFR-10 | Localization | UTF-8 throughout; support localized labels, guest names and printable templates. |
| NFR-11 | Deployment | Installable on a conventional Linux server without mandatory Docker, Redis or SaaS dependencies. |
| NFR-12 | Maintainability | Module boundaries, automated tests, migrations, documented APIs and structured logs. |

# 23. Intranet, internet and resilience model

In internet-enabled deployments, the Guest Portal is the only public guest-facing application surface by default. Administrative cockpit, Registry management, staff workspaces, check-in controls and internal prerequisite records remain on private networks or behind explicit authenticated access controls. Public exposure is configured per event and per endpoint family; it is never enabled simply by publishing the main application hostname.

The same application build should support both operating modes.

## 23.1 Intranet-first mode

- Staff use a private DNS name and local network.
- All core workflows operate without external services.
- Public RSVP/invitation routes may be disabled.
- Local file storage, database, job workers and notifications operate inside the LAN.

## 23.2 Internet-enabled mode

- Same application and database.
- Public DNS and TLS reverse proxy.
- Explicitly enabled public RSVP and credential routes.
- Staff administration protected by VPN, identity-aware proxy or strong MFA.
- Public and staff routes separated by policy and preferably hostnames.

## 23.3 Failure modes

The system should define operator behavior for:

- Internet uplink unavailable while intranet remains available.
- Local network outage.
- Database unavailable.
- File storage unavailable.
- Worker/solver unavailable.
- Check-in device offline.
- A stale floor-plan revision open on a staff device.

A solver or PDF worker failure should not prevent manual seating edits or guest lookup. A public internet outage should not disable LAN operations. Check-in offline mode, when implemented, must communicate its limitations clearly.

# 24. Backup, restore, monitoring and maintenance

Backups must include the persistent Guest Registry, brand profiles and asset revisions, venue templates, event participation records, source floor-plan artifacts, native spatial revisions, guest-visible map projections, cockpit configurations, operational alerts, prerequisite status history and audit history. Each data class follows its configured retention and access policy. Monitoring must include portal availability, realtime connection health, notification delivery and Cockpit data freshness.

- Automated PostgreSQL backups with point-in-time recovery where feasible.
- File assets backed up consistently with database references.
- Encrypted off-host backup copy for disaster recovery.
- Regular restore tests, not merely backup-success checks.
- Documented recovery steps and service startup order.
- Health endpoints for API, database, queue, storage and solver worker.
- Structured logs with correlation IDs.
- Metrics for API latency, job queue age, solver duration/status, check-in rate, WebSocket connections and error rates.
- Capacity monitoring for database, filesystem and backup targets.
- Maintenance mode for migrations or planned upgrades.
- Versioned database migrations and rollback/forward-fix plan.

# 25. User interface and navigation map

Proposed main navigation (items are shown or hidden according to the user's permissions and active organization):

1. Dashboard / Event Operations Cockpit
2. Events and sessions
3. Guest lists
4. Guest Registry
5. Groups and relationships
6. Venues and space templates
7. Floor plans and spatial editor
8. Allocation workspace
9. Plans, approvals and publication
10. Guest cards and credentials
11. Check-in
12. Operations and issues
13. External prerequisites (coordinator access)
14. Branding and templates
15. Reports and exports
16. Administration and access control

Important screens:

- Event overview.
- Guest list with saved views and bulk operations.
- Guest profile with event memberships, relationships, RSVP, allocation, credential and attendance timeline.
- Group editor and relationship matrix.
- Venue hierarchy manager.
- Floor-plan editor.
- Floor-plan staff viewer.
- Allocation rule builder.
- Allocation preview/diff screen.
- Manual drag-and-drop assignment workspace.
- Plan approval and revision comparison screen.
- Card template designer and print preview.
- Check-in station screen.
- Live operations dashboard.
- External prerequisite task list and completion status.

The allocation workspace should display a guest list, resource/zone list, current plan and conflicts together. It must support keyboard-accessible alternatives to drag and drop.

# 26. Reporting and export requirements

Additional report families include Registry profile/duplicate review, cross-event participation history (permission-controlled), guest portal access and seating-change delivery, cockpit alert volume/resolution, operational timeline, and zone/entrance arrival trends. Reports must distinguish master-person attributes from event-snapshot attributes and must not accidentally export restricted fields.

Initial reports:

- Master guest register.
- Guest register by category, organization, delegation or tag.
- RSVP status report.
- Allocation list by guest.
- Table/row/seat list.
- Zone and capacity report.
- Unallocated guest report.
- Constraint conflict report.
- Guest card issuance/reissue report.
- Check-in/attendance report by time and entrance.
- No-show and exception report.
- Plan revision/change report.
- Staff assignment/area coordination plan.
- External prerequisite status report for authorized coordinators.
- Non-sensitive readiness summary for authorized event managers.

Exports must apply the same permission filtering as the screen. Sensitive fields must not leak through “export all” functions. CSV exports should protect against spreadsheet formula injection.

# 27. Testing and quality strategy

The test strategy must additionally cover cross-event identity reuse, duplicate resolution and merge rollback, snapshot immutability, tenant branding inheritance and isolation, branded output snapshots, GHB venue-template reuse, row/zone/floor-position allocation, repeated visible numbering, spreadsheet source-plan traceability, portal authorization and map sanitization, realtime cockpit consistency, prerequisite status tracking and permission-filtered workspaces. Expanded acceptance tests are included in Sections 39 and 46.

## 27.1 Unit tests

- Guest validation and duplicate detection.
- Guest group membership rules.
- Resource capacity calculations.
- Allocation hard/soft constraint compilation.
- Separation scope semantics.
- Permission checks.
- QR token generation, hashing and revocation.
- Check-in idempotency and duplicate handling.
- Plan revision state transitions.
- Tenant data isolation and branded asset access controls.
- External prerequisite status transitions and audit records.

## 27.2 Integration tests

- Import XLSX/CSV and verify CRUD afterward.
- Concurrent assignment attempts for the same seat.
- Concurrent general-admission allocation against capacity.
- Solver run, preview, commit and revision conflict.
- New hard separation rule causing successful rearrangement.
- Infeasible separation rule producing clear diagnostics.
- Live reflow preserving locked assignments.
- Publish a plan and ensure viewers receive the correct revision.
- Revoke a QR code and reject subsequent scans.
- Multiple check-in stations scanning the same credential.
- Restricted prerequisite coordination records cannot be accessed by unauthorized roles; no internal police inspection workflow is exposed.

## 27.3 End-to-end tests

- Create event, import guests, edit a guest, create a group and assign categories.
- Build a banquet room and allocate tables/seats.
- Build a theatre with fixed rows/seats.
- Build a standing reception with zone capacities and no seat records.
- Apply “must not be at the same table” and “must not be in the same room” rules.
- Publish an approved plan, print it and open it on a staff device.
- Perform an event-day room blockage and targeted reflow.
- Generate a guest card, scan it and verify the current allocation.
- Record a CDI requirement, request submission, scheduling and completion confirmation by an authorized internal coordinator; confirm the system does not represent this as performing the police inspection.

## 27.4 Solver test fixtures

Maintain deterministic scenario fixtures:

- Small banquet with a family group.
- VIP and delegation preferences.
- Two-person separation at table scope.
- Group-level separation across zones.
- Same-room prohibition.
- Fixed/locked seating with one new guest.
- Blocked table during live operations.
- Insufficient capacity.
- Conflicting hard rules.
- Theatre fixed seats with accessibility resources.
- Standing zone with mixed category ratios.

Every solver change must run regression fixtures and compare feasibility and score behavior.

# 28. Implementation roadmap and release gates

Version 1.2 changes the sequencing: the person-centric Guest Registry and event participation split belong in the foundation, not as a later bolt-on; the Cockpit shell and role-scoped navigation must also be established early. Guest Portal access and guest-safe map projection should be implemented after plan publication and credential flows are stable. The revised phase gates are in Section 39.

Build in vertical slices so each milestone produces a usable and testable product.

## Phase 0 - Product discovery and technical spikes

Deliverables:

- Confirm event workflows and role model.
- Validate venue and room types with real sample plans.
- Define separation rule vocabulary and conflict semantics.
- Prototype SVG floor-plan editor with scale calibration and object selection.
- Prototype OR-Tools model for table/zone allocation and negative relationships.
- Confirm PDF rendering and QR scanning on target browsers/devices.
- Confirm installation, backup and restore on the intended Linux server.

Exit gate: no unresolved architectural blocker in floor-plan geometry, non-chair allocation semantics, tenant/brand inheritance or external prerequisite boundaries.

## Phase 1 - Foundation and manual operations

Deliverables:

- Authentication, organization/event CRUD and role permissions.
- Guest CRUD, custom fields, categories, groups and relationships.
- CSV/XLSX import, validation, update and export.
- Venue/building/level/room/zone management.
- Floor-plan import, native objects and staff viewer.
- Table, row, seat and capacity-pool resources.
- Manual allocation and basic validation.
- Audit trail and database backup.

Exit gate: users can create an event, import and edit guests, define a mixed venue and manually allocate without violating capacity or uniqueness.

## Phase 2 - Rules and optimization

Deliverables:

- Rule builder for hard constraints and soft preferences.
- Positive and negative guest/group relationships.
- Scope-aware “must not be together” rules.
- OR-Tools worker and solver status reporting.
- Locking, candidate preview, score breakdown and conflict diagnostics.
- Targeted reflow and allocation revision history.

Exit gate: deterministic tests show the solver can move other guests to satisfy new separation rules while preserving locked assignments, and returns explicit infeasibility when no solution exists.

## Phase 3 - Publication, cards and check-in

Deliverables:

- Plan submission, approval, publication and superseding revisions.
- PDF floor plans and staff reports.
- Guest card templates and bulk generation.
- QR issue/revoke/reissue.
- Multi-station online scanning and check-in.
- Live dashboard and staff plan updates.

Exit gate: approved plans can be distributed/printed, and a guest credential can be scanned at multiple stations without duplicate attendance.

## Phase 4 - Event-day operations and external prerequisites

Deliverables:

- Operational issue/change records.
- Fast manual changes and targeted live reallocation.
- Superseded-plan warnings and live plan change summaries.
- External prerequisite coordination, due dates, completion confirmation and event-readiness gate.
- Sensitive access audit and separate readiness reporting.
- Role-specific staff views.

Exit gate: event-day changes remain consistent across allocations, staff plans, guest portal and check-in; external prerequisite statuses are auditable and do not imply that the platform performed the external task.

## Phase 5 - Resilience and advanced capabilities

Deliverables:

- Offline check-in package and reconciliation.
- Public RSVP portal.
- Optional email/SMS integrations.
- Advanced reporting and reusable templates.
- External identity provider integration.
- Optional multi-organization/tenant hardening and additional deployment replicas.

Exit gate: offline reconciliation and security review pass; integrations can be enabled without compromising intranet operation.

# 29. Acceptance criteria for the first production-capable release

The original acceptance baseline remains applicable. The additional v1.1 criteria for reusable person profiles, the guest-facing portal and wayfinding, and the operational Cockpit are defined in Section 39. The v1.2 acceptance criteria for organization/venue/event branding, the GHB reference portfolio, prayer-row/floor-position allocation, workbook onboarding and external prerequisites are defined in Section 46. All applicable criteria must be included in the release acceptance suite.

The first production-capable release is accepted only when all of the following are demonstrated:

1. An administrator can create an event and manage users/permissions.
2. Guests can be added, edited, archived and searched directly in the interface.
3. Guests can be imported, mapped, validated, updated and exported without losing editability.
4. Guest groups and pairwise/group-level relationships can be maintained.
5. A venue can contain multiple buildings, levels, rooms and zones.
6. A banquet room can model tables and individual seats.
7. A theatre/cinema room can model rows and fixed seats without tables.
8. A standing reception can allocate guests to zones with capacity limits and no individual seat assignments.
9. The floor-plan editor can import a background, calibrate scale and position native spatial objects.
10. Administrators can manually assign guests and the system prevents duplicate resource allocation and capacity overrun.
11. A hard separation rule can be applied at a clearly defined scope, and the optimizer can rearrange other guests to satisfy it when feasible.
12. Group-level separation rules can distribute group members across specified distinct resources/zones.
13. The solver shows infeasible/timeout/feasible/optimal outcomes accurately and provides useful diagnostics.
14. Locked assignments remain unchanged during a solver run unless explicitly unlocked by an authorized user.
15. An approved plan is immutable; subsequent changes create a new revision.
16. Staff can view and print the current approved plan and identify its revision.
17. Guest cards can be generated in bulk with a QR credential that contains no readable personal data.
18. Revoked credentials are rejected; duplicate check-ins are handled safely.
19. Multiple check-in stations update attendance without duplicate active records.
20. A live operational change can trigger targeted reflow and publish an updated staff plan.
21. Externally performed prerequisites such as CDI can be recorded, coordinated and marked complete by an authorized internal coordinator, with an audit trail and no internal inspection methodology.
22. Backups can be restored in a tested procedure.
23. The application operates fully on a private intranet and can be exposed through a reverse proxy without exposing the database or private storage.

# 30. Key decisions and items to validate before coding

This blueprint recommends defaults so implementation can proceed without redesigning the architecture. The following items still need confirmation during Phase 0:

| Topic | Recommended default | Why it matters |
|---|---|---|
| Product name | Event Operations & Guest Logistics Platform (working title) | Branding can be changed without architecture impact. |
| Guest ownership | Organization-level Person record + event-specific Event Guest participation and immutable event snapshot | Supports repeat guests across events without mixing event-specific status or rewriting history. |
| Multi-tenancy | Single organization per installation initially; schema supports organization scope | Avoids unnecessary SaaS complexity while leaving room to grow. |
| Venue reuse | Reusable venue template, copied/revision-pinned into each event | Prevents later venue edits from silently changing an active event. |
| Seating rule semantics | Explicit scope required for every separation rule | “Not together” is ambiguous unless same table/room/zone/distance is specified. |
| Physical distance | Calibrated plan-space distance; optional feature after basic hierarchy scopes | Requires reliable scale calibration and well-defined geometry. |
| Allocation solver | OR-Tools CP-SAT C++ worker | Fits complex constraints and avoids a Python daemon. |
| Job queue | PostgreSQL-backed queue | Avoids mandatory Redis/Valkey dependency initially. |
| Check-in mode | Online first; offline package in a later phase | Online consistency is simpler; offline support remains in the design. |
| External prerequisites | Minimal event-scoped records, controlled optional attachments and status history | Tracks coordination without becoming an internal police-inspection system. |
| Public access | Disabled by default; enable RSVP and Guest Portal endpoints per event and expose only a guest-safe projection | Intranet-first and safer for high-profile events. |
| Guest access credential | Dedicated portal access token/session separate from admission QR credential | Prevents the admission QR from becoming a general-purpose profile access token. |
| Cockpit model | One command-centre shell with permission-filtered role workspaces | Provides a shared operational picture without making every operator a global administrator. |
| Guest data retention | Configurable per organization/event, with legal/policy review | Requirements differ by event and jurisdiction. |

# 31. Risks and mitigations

The principal delivery and operational risks, together with their practical mitigations, are summarized below.

| Risk | Impact | Mitigation |
|---|---|---|
| Ambiguous “not together” requirements | Wrong or infeasible seating | Force explicit separation scope and show examples in rule UI. |
| Solver cannot find a feasible arrangement | Event planning delay | Feasibility pre-check, useful diagnostics, manual fallback and capacity review. |
| Live changes create stale printed plans | Staff act on obsolete information | Revision IDs, superseded watermark, live viewer and change summary. |
| Concurrent operators overwrite assignments | Double-booking or lost changes | Optimistic revisions and atomic commit validation. |
| Imported records create duplicates | Incorrect guest totals and passes | Staging, match review and audited merge workflow. |
| Floor-plan scale is inaccurate | Incorrect distances and poor visualization | Explicit calibration, scale validation and visual reference checks. |
| General-admission capacity is overrun | Operational/safety concern | Transactional capacity validation and blocked-resource support. |
| QR token copied or shared | Unauthorized pass presentation | Random opaque tokens, revocation, scan logging and optional separate identity check. |
| Confidential external correspondence is over-retained or exposed | Privacy/security risk | Store only minimal status/reference data; restrict any necessary attachments and apply retention controls. |
| Internet failure during event | Reduced operational visibility | LAN-first architecture and planned offline check-in. |
| Feature scope grows without control | Delayed delivery | Phase gates, traceable requirements and change control. |
| Master Registry exposes data across events | Privacy breach and loss of trust | Separate Registry permission, event scope, field classification, audit and purpose limitation. |
| Guest portal token is shared or forwarded | Unintended disclosure of guest-specific information | Dedicated portal token, optional step-up verification, revocation, short session lifetime and minimal data. |
| Public map reveals internal venue details | Exposure of staff-only or sensitive areas | Build a sanitized guest-visible map projection with explicit publication review. |
| Cockpit receives stale or incomplete realtime data | Incorrect operational decisions | Show data freshness, connection status, server timestamps and refresh-on-reconnect behavior. |
| Too many alerts reduce operator attention | Important exception missed | Severity levels, deduplication, assignment, acknowledgement, escalation and tuned thresholds. |

# 32. Requirement traceability summary

The following table maps the requirements that drove this blueprint to the design location where they are addressed.

| User requirement | Specification sections |
|---|---|
| Two or more people must not be placed together; engine rearranges others | 8.2-8.7, 27.4, 29.11-29.13, Appendix A-B |
| Guest CRUD in application; imported guests editable | 6.1-6.3, 29.2-29.3 |
| Tableless cinema/theatre/zone-based rooms | 7.2-7.3, 9, 29.6-29.8 |
| Dynamic pre-event and during-event seating changes | 8.6, 16, 29.20, Appendix B |
| Approved plans printable and viewable by staff | 10, 14, 29.15-29.16 |
| Server-based, intranet and optional internet | 18, 21.3, 23, 29.22-29.23 |
| CDI performed by police when required | 15, 45-46; event prerequisite acceptance criteria |
| Organization/venue/event branding with inheritance and versioned outputs | 5.1, 6, 11-14, 18-19, 21, 25-26, 41, 46; Appendix I |
| GHB portfolio and supplied mosque seating workbook as source reference | 7, 9-10, 18, 23-24, 42-44, 46; Appendix H |
| Prayer-row, numbered floor-position and non-chair spatial allocation | 7-10, 16-17, 27-29, 42-44, 46 |
| External prerequisite coordination rather than internal CDI execution | 1, 3, 4, 14-15, 17-21, 25, 28-32, 45-46 |
| Persistent guest profiles reused across future events | 6, 17, 21, 24, 33, 36, 38-39 |
| Duplicate detection, person merge and historical event snapshots | 6.3, 17, 33, 36, 38-39 |
| Optional portal for guests to see their own seat on a venue map | 12, 19-23, 34, 36-39 |
| Guest-specific wayfinding by building, level, room, zone, row and seat | 7, 9, 12, 34, 36-39 |
| Live command-centre dashboard with visual overview and controls | 14, 16, 20, 35-39 |
| Role-specific staff dashboards and task views | 4, 14, 21, 25, 35, 38-39 |
| Controlled updates to guests and staff after a seating change | 10-14, 16, 20, 34-37 |
| Broad feature set, systematically planned | Entire document; especially 28-30 and 33-39 |

# 33. Persistent Guest Registry and cross-event identity

## 33.1 Purpose and domain boundary

The platform MUST maintain a persistent, organization-scoped Guest Registry so a person can be reused across multiple events. The Registry is a long-lived identity and contact store, not an event guest list. It must not contain event-specific seating, attendance or RSVP state as if those values applied universally.

The data model MUST distinguish:

- **Person**: the persistent human identity record managed by an organization.
- **Person identifiers**: optional organization-approved identifiers or source-system references used to help match records. Sensitive identifiers are subject to additional classification and are not required by default.
- **Person contact points**: contact channels with verification and preference metadata.
- **Event Guest**: an event-scoped participation record linking one Person to one Event.
- **Event snapshot**: an immutable snapshot of the person fields and event-specific values relied upon by an invitation, credential, approved plan or historical report.

A Person may exist without any event participation. A Person may participate in many events. An Event Guest must belong to exactly one event and reference one Registry Person, subject to an explicitly supported temporary/unresolved-person workflow for emergency or walk-in registration.

## 33.2 Registry profile structure

The master profile should support configurable fields grouped into sections:

| Profile group | Examples |
|---|---|
| Identity | Legal/display name, preferred name, title/salutation, pronunciation guidance where supplied |
| Organization | Organization, institution, department, role/position, delegation affiliation |
| Contact | Email, telephone, postal address, preferred communication channel and language |
| Relationships | Household/family links, assistant/delegate relationships, organization and delegation membership |
| Classification | Organization-defined profile classifications and tags, with access restrictions |
| Preferences | Reusable preferences that the person has explicitly supplied and that remain relevant across events |
| Attachments | Approved profile documents, with type, owner, classification, retention and access policy |
| Provenance | Source, created/updated timestamps, responsible actor, verification status and change history |

The Registry MUST support custom fields, field types, validation rules, visibility classification and organization-level defaults. Event administrators may configure event-specific fields without changing the master schema. Sensitive or special-category information MUST NOT be collected simply because a field type exists; collection needs a documented purpose, authorization and retention policy.

## 33.3 Adding people to an event

An event administrator may add participants using any of these workflows:

1. Select one or more existing people from the Registry.
2. Search the Registry using permitted fields and saved views.
3. Import a file and match rows to existing people or create new Registry profiles.
4. Create a person directly in the Registry and immediately add them to the event.
5. Create an event participant in an unresolved state for an operational walk-in, then reconcile it to a Registry Person under controlled review.

Adding a person to an event creates an Event Guest participation record. It does not copy the entire Registry as an uncontrolled duplicate. The event participation record stores event-specific values, including category, invitation status, RSVP, allocation, attendance, event group membership, event notes, credential status and event-specific requirements.

## 33.4 Identity resolution, duplicates and merging

The application MUST provide assisted duplicate detection. Matching may use configured combinations of name, organization, email, telephone, source-system ID and other approved identifiers. A matching score may rank candidates, but the system MUST NOT automatically merge people based solely on a matching name or an opaque score.

The resolution workflow must:

- Display candidate profiles and the fields that match or differ.
- Show event participation history and the consequences of reuse/merge to an authorized reviewer.
- Allow reuse of an existing Person, creation of a new Person, or deferral for review.
- Prevent a merge from combining unrelated event participations or overwriting event snapshots.
- Record source and destination Person IDs, fields retained, fields discarded or superseded, reason, actor, timestamp and approval where required.
- Support a controlled reversal/compensating operation where technically and legally possible; do not promise that every merge can be perfectly undone after downstream use.
- Preserve the original identity references in the audit trail.

## 33.5 Historical snapshots and event overrides

When a person is added to an event, the system creates an event-specific snapshot of the identity fields required for event operations. The snapshot is refreshed only through an explicit action or configured synchronization policy before a defined freeze/approval point. After a credential or approved plan is published, a master profile edit MUST NOT silently change the event's printed materials or historical record.

The event may override an individual display name, salutation, organization label, language or other permitted field for that event. The override is stored on the Event Guest record and does not change the master Person profile. Reports must clearly identify whether a field came from the master profile, event override or frozen event snapshot.

Historical event records must remain readable according to retention policy even if the current master profile is later corrected, archived or anonymized. Where a deletion/anonymization request affects historical records, the application applies the approved retention policy and keeps only the minimum audit evidence legally/policy permitted.

## 33.6 Registry access, ownership and lifecycle

Registry permissions are separate from event permissions. A user may be allowed to manage an event guest list but not to browse the full organization Registry or export all person profiles. Required capabilities include:

- Registry search and profile viewing.
- Create/edit/archive/anonymize profile.
- View profile history and attachments.
- Add/remove a person from an event, without deleting the master person.
- Merge/reconcile duplicate people.
- Export Registry records under a separately granted permission.
- Apply retention, legal hold and data-subject request workflows where applicable.

The organization owns Registry configuration and retention policy. Event owners control event-specific participation and event snapshots within the organization policy. Cross-organization reuse is out of scope for the initial product unless a future explicit federation model is designed.

## 33.7 Guest Registry user experience

The Registry interface should include:

- Search-first people directory with configurable columns and saved filters.
- Profile view with separate tabs for identity, contact, relationships, event history, attachments, notes, access history and audit.
- Create/edit forms with field-level validation and visibility cues.
- Multi-select and bulk update for authorized fields.
- Duplicate review queue and side-by-side comparison.
- Event participation history with clear separation of past, current and upcoming events.
- “Add to event” action that opens an event-scoped participation workflow.
- Clear warnings before archive, anonymize, merge or bulk changes.

## 33.8 Registry acceptance requirements

The Registry is acceptable only when a person can be created once, linked to multiple events, edited under permission, imported with duplicate review, merged under audit, and reused without changing previous event snapshots or exposing information to unauthorized event users. See Section 39 for test cases.

# 34. Guest Portal and venue wayfinding

## 34.1 Purpose and event-level configuration

The Guest Portal is an optional guest-facing application surface enabled per event. It is intended to reduce arrival confusion and help a guest find their own assigned location. It is not an invitation list, staff map or general-purpose venue directory.

Per-event settings MUST control:

- Portal enabled/disabled state and publication window.
- Allowed access methods and verification strength.
- Languages, branding and event information.
- Which location fields are shown for each room/layout type.
- Whether an interactive map, textual directions or both are available.
- Whether a guest can view accompanying guests' assignments (default: no; allow only where an explicit event policy and relationship/authorization model permit it).
- Whether seating-change notifications are sent and through which approved channels.
- Whether kiosk mode is enabled and which fields it displays.

## 34.2 Access channels and credential separation

The Guest Portal MUST support a responsive browser-based experience, preferably installable as a PWA. Native mobile applications are not required for the initial release.

Supported access patterns may include:

1. A dedicated portal link issued to the guest.
2. A QR code or link on a guest communication that opens a portal verification flow.
3. A supervised venue kiosk where a guest presents a pass and completes a minimal verification step.
4. A short, manually entered reference plus a separate verification factor where configured.

The portal access credential MUST be distinct from the admission/check-in QR credential. Admission QR is a bearer credential used by an authorized scanner; it MUST NOT automatically become an unrestricted profile-access token. Portal links should use high-entropy, opaque tokens stored hashed server-side or an equivalent secure, revocable mechanism. For higher-risk events, the organization may require a second factor (for example, a one-time code to a verified contact channel), short session duration or staff-assisted kiosk access.

Portal sessions must be event-scoped, revocable, rate-limited and protected against enumeration. A portal response must never confirm whether arbitrary person references belong to an event. No guest list endpoint is exposed publicly.

## 34.3 Guest home and personal allocation view

After authorization, the guest sees only the event information approved for them. The default personal view includes:

- Event name, date, permitted schedule and arrival instructions.
- Guest display name and a non-sensitive event reference if useful.
- Current assigned building/site, entrance, level, room/area and zone.
- Table/section, row and seat when applicable.
- A visual marker for the guest's own seat or allocated area.
- A concise textual fallback for accessibility and low-bandwidth use.
- Relevant public event notices and contact/help information.

The view must adapt to the allocation resource type. A banquet guest may see table and seat; a theatre guest sees section, row and seat; a standing-reception guest sees an area/zone and entry point; a conference guest may see a room/session and desk/seat where applicable. The interface must not invent a seat for a capacity-pool allocation.

## 34.4 Guest-visible venue map projection

The administrator's source floor plan contains working layers, internal annotations, capacity data, staff locations and potentially restricted objects. The Guest Portal MUST NOT render that source document directly.

Instead, publication creates a separate **Guest-Visible Venue Projection** containing only approved geometry and content, such as:

- Public entrances and exits intended for guests.
- Public corridors and circulation areas.
- Guest-accessible lifts, stairs and accessible routes.
- Public rooms, zones, sections and navigation labels.
- Guest-facing facilities and help points where approved.
- The current guest's own target location.

The projection must omit internal staff routes, restricted rooms, sensitive annotations, security posts, confidential external correspondence, private capacity details and other guests' identities/seat markers. Map objects have an explicit visibility classification and publication approval. The server must apply the same filter to vector data, images, map tiles, API responses, printouts and cached PWA content.

## 34.5 Wayfinding model

Wayfinding may begin as a highlighted destination and short textual instructions, then evolve to graph-based routing. The model should represent navigable nodes (entrances, junctions, lifts, stairs, room doors and destination areas) and edges (corridors, ramps, stairs, lift connections) with attributes such as level, direction, accessibility, temporary closure and guest-visible status.

A route is calculated from a selected public entrance or kiosk location to the guest's destination. The route service must respect approved public access paths, accessible route preferences and temporary closures. If a safe/accessible path cannot be confirmed from the venue data, the portal must provide a non-misleading fallback such as “ask venue staff” rather than inventing directions.

For the first release, route calculation may be limited to manually authored paths and static instructions. Indoor positioning, live blue-dot tracking, GPS-based room-level navigation and automatic map recognition are not prerequisites.

## 34.6 Seating changes and guest notifications

When a new approved plan changes a guest's location:

1. The prior published allocation is retained as history.
2. The new approved/published allocation becomes authoritative.
3. The Guest Portal resolves the current location from the server.
4. The portal indicates that the assignment was updated and shows the update time where useful.
5. The notification engine creates a delivery task if the event's notification policy requires it.
6. Affected staff workspaces and the Cockpit receive the appropriate update.

A portal token remains associated with the guest/event, not with a particular seat, so a seating change does not require a new identity token. Printed cards may need reissue according to event policy. Guest communication must avoid disclosing other guests' movements or the reason for a sensitive reassignment.

## 34.7 Kiosk and staff-assisted access

Kiosk mode must clear guest-specific data after a short inactivity period, prevent browser navigation to administrative routes, avoid retaining credentials in browser history, and return to a neutral start screen. Kiosk audit should record session start/end and access outcome without retaining unnecessary personal data. Staff-assisted lookup must show only fields necessary to guide the guest.

## 34.8 Accessibility, localization and resilience

The portal should support keyboard access, screen readers, high contrast, scalable text and non-map textual directions. Labels and map legends must be localizable. Map assets may be cached only if the cached data is guest-safe and time-bounded; the interface must display when content is stale/offline and must not claim a cached seating assignment is current. The portal must gracefully degrade to textual directions when maps fail to load.

## 34.9 Guest Portal acceptance requirements

A guest must be able to access their own current approved location from a supported mobile browser, view a sanitized map with their own destination highlighted, understand the location without relying solely on color, and receive updated information after an approved move. Attempts to enumerate or view another guest, an internal map layer or external-prerequisite information must fail. See Section 39.

# 35. Event Operations Cockpit and role-specific staff workspaces

## 35.1 Cockpit purpose and default landing page

The Cockpit is the primary live command interface for event administrators and authorized operational leads. It should answer, at a glance:

- What is the current operational state of this event?
- Where are capacity, arrival or allocation issues occurring?
- Which alerts need attention, who owns them and what is their age?
- Which plan revision is currently approved and published?
- Which staff stations or connected components are degraded?
- What actions can this user safely take now?

The Cockpit is a composable workspace over shared event services. It must not duplicate business logic or become a separate source of truth.

## 35.2 Cockpit layout and visual hierarchy

The default event cockpit should support configurable panels arranged around these areas:

1. **Event header:** event name, current phase/status, local event time, active plan revision, publication status and data freshness.
2. **Operational KPI strip:** invited/confirmed guests, allocated/unallocated, checked-in/not arrived, current occupancy, capacity remaining and open alert count.
3. **Interactive venue overview:** selectable building/level/room/zone map with authorized layers for occupancy, arrival, allocation exceptions, accessibility or other operational states.
4. **Alert and exception queue:** prioritized unresolved conditions with owner, age, severity and next action.
5. **Operational timeline:** recent important changes, check-ins, plan publications, approvals, station failures and alert state transitions.
6. **Task and readiness panel:** outstanding approvals, venue tasks, staff tasks and external prerequisite summary as permitted.
7. **Quick actions:** common authorized actions such as open guest search, move guest, start targeted reflow, publish a new revision, manage a station or acknowledge an alert.

Panels must be configurable by role and event type. A standing reception may emphasize zone occupancy and entry flow; a banquet may emphasize tables and seating; a cinema may emphasize sections, rows and seat availability.

## 35.3 Operational indicators and drill-down

Each metric must define its source, calculation, timestamp and event/venue scope. Clicking a KPI or map region opens a filtered list or contextual detail. The UI must distinguish:

- Registered people in the master Registry.
- Event guests/invitees.
- RSVP-confirmed guests.
- Guests with a current allocation.
- Guests physically checked in.
- Current estimated occupancy (if the system has a valid basis for this value).

The Cockpit must not label a plan assignment as physical presence. Occupancy derived from check-in is an attendance proxy and must be labelled accordingly; capacity-pool counts must respect the room's capacity model.

## 35.4 Alert and exception lifecycle

Operational alerts are structured records, not transient toast messages. Each alert should contain:

- Event and resource scope.
- Alert type and stable deduplication key.
- Severity (informational, low, medium, high, critical) with configurable mapping.
- Status (new, acknowledged, assigned, in progress, resolved, dismissed, reopened).
- Creation/update timestamps and source event.
- Assigned owner/team and due/escalation time where applicable.
- Description, permitted context and suggested response.
- Resolution code, comments and evidence reference where appropriate.

Examples include over-capacity warnings, unassigned VIP, changed seating not yet republished, stale print pack, repeated invalid scans, scanner offline, check-in duplicate, allocation rule conflict, guest portal publication failure and pending approval. Alerts should be deduplicated, grouped and rate-limited so one underlying issue does not flood the interface.

Acknowledging an alert does not resolve it. High-impact alert dismissal or resolution may require a reason or supervisor authority. Critical alerts may trigger escalation according to event policy. The platform should record alert ownership and response times for after-action reporting.

## 35.5 Controlled interventions and command actions

The Cockpit may initiate an operation, but all changes must pass through the same domain services and validation used by their dedicated modules. Examples:

- Open a guest profile or event participation record.
- Move a guest or group to a different valid resource.
- Launch targeted or zone-wide reallocation with current locks and constraints.
- Mark a room/resource unavailable and start a reflow preview.
- Publish an approved plan revision.
- Revoke/reissue a credential under permission.
- Open or disable a check-in station.
- Assign/escalate an alert or operational task.
- Send an approved guest/staff notification.

Actions that can affect guest placement, credentials, public information or event readiness require a preview/confirmation where appropriate. The Cockpit must display the impact scope before commit, including affected guests, resources, print documents, portal views and notifications. It must never bypass approval requirements or hard constraints for speed.

## 35.6 Role-specific workspaces

A workspace is a role-tailored arrangement of panels, queues and shortcuts. Initial workspace profiles:

| Workspace | Primary information and actions |
|---|---|
| Event director | Overall readiness, attendance, alerts, capacity, timeline, plan status and high-level interventions. |
| Event administrator | Guest/Registry search, RSVP, allocation exceptions, publication, communications and event configuration. |
| Seating coordinator | Floor plan, live allocation, locks, solver previews, changed guests and assignment conflicts. |
| Venue coordinator | Buildings, rooms, zone capacity, resource availability, closures, accessibility paths and staff tasks. |
| Reception manager | Entrance status, queue/arrival trend, scanner station health, check-in exceptions and manual lookup. |
| Check-in operator | Scanner, minimal guest identity, current destination, admission result and supervisor escalation. |
| Floor/zone staff | Approved assigned-area plan, guest destination lookup and relevant changes. |
| Communications operator | Approved recipient segment, message templates, delivery queue and failed notifications. |
| Security coordinator | Restricted security/readiness tasks and approvals; only a minimal readiness summary may appear elsewhere. |
| Management viewer | Read-only KPIs, event status, published plan and selected timeline/alerts. |

Workspace configuration MUST NOT grant permissions. The backend enforces the underlying permissions independently for each query and command. Users may have multiple roles; their workspace must show only the union of permissions explicitly granted to them.

## 35.7 Real-time behavior and data freshness

The Cockpit should update without manual refresh for material event changes. Each panel should have a last-updated timestamp or a shared event-stream health indicator. On reconnect, the client must request a fresh authorized snapshot and then resume incremental updates from a cursor/version. If the stream is delayed or unavailable, the UI must show a stale/degraded state rather than presenting old data as live.

The Cockpit should support an operator-configurable refresh fallback. A pushed message should carry identifiers and revision/cursor metadata; for sensitive records, the client should fetch current permitted details through the API rather than receiving the entire record in a broadcast payload.

## 35.8 Activity timeline and audit distinction

The operational timeline is a human-readable projection of selected domain events. It is not the authoritative audit ledger. The immutable audit log remains the evidence source for security-sensitive and high-impact actions. Timeline entries can be filtered by event, venue, category, resource, actor and time window, subject to permissions.

## 35.9 Cockpit acceptance requirements
An authorized administrator must be able to see live KPIs, inspect an interactive authorized venue view, manage alerts, inspect a chronological event timeline and launch controlled actions. Different staff roles must receive different workspaces and must not gain additional access through dashboard configuration. A disconnected or stale client must visibly identify its state and reconcile on reconnect. See Section 39.

# 36. Extended domain model and API contracts

## 36.1 Additional logical entities

The logical data model must include at least these entities or equivalent structures:

| Entity | Purpose and key relationships |
|---|---|
| `Person` | Organization-scoped persistent human identity; primary key is an opaque UUID. |
| `PersonIdentifier` | Optional source-system or organization-approved identifier; classified and permission controlled. |
| `PersonContact` | Email, phone or other contact point, with verification and communication preference metadata. |
| `PersonRelationship` | Relationship between people or a person and organization/group; typed, scoped and auditable. |
| `PersonAttachment` | Registry profile attachment with storage reference, classification, retention and access policy. |
| `PersonProfileRevision` | Historical profile-change record or immutable version reference. |
| `PersonMergeRecord` | Source/destination person references, review, field resolution and audit evidence for merges. |
| `EventGuest` | Event-scoped participation linked to exactly one Person and one Event. |
| `EventGuestSnapshot` | Immutable snapshot of selected identity/profile fields used at a defined event revision or issue point. |
| `EventGuestFieldOverride` | Event-specific display or contact field override, with reason and actor where appropriate. |
| `GuestPortalAccess` | Event-scoped portal token/session metadata, expiry, revocation and last-use metadata; store token hashes, not raw tokens. |
| `GuestVisibleVenueProjection` | Published sanitized map and navigation data derived from a specific approved venue/plan revision. |
| `GuestVisibleMapObject` | Publicly renderable entrance, corridor, room, zone, node or destination geometry. |
| `WayfindingNode` / `WayfindingEdge` | Optional graph model for public route planning, accessibility and closures. |
| `CockpitLayout` | Role/event-specific panel layout and display preferences; does not grant access. |
| `CockpitWidgetPreference` | Widget configuration, filters and thresholds permitted for a user/workspace. |
| `OperationalAlert` | Structured alert with severity, lifecycle, deduplication key, event/resource scope and owner. |
| `OperationalAlertAction` | Acknowledgement, assignment, escalation, resolution or dismissal history. |
| `OperationalTimelineEntry` | Human-readable projection of a selected domain event. |
| `StaffWorkspace` | Role-oriented workspace profile and permitted navigation configuration. |
| `Notification` | Message intent, recipient reference, channel, template/version and delivery state. |
| `RealtimeOutbox` | Transactional outbox row committed with a domain change and later published to realtime subscribers. |

## 36.2 Core relationship constraints

- One Person may have zero or many Event Guest records.
- One Event Guest belongs to exactly one event and one Person (except explicitly unresolved temporary records pending reconciliation).
- Event Guest and Event Guest Snapshot records must preserve event context even if the Person profile changes.
- A portal access session references one Event Guest and one event; it is not a cross-event credential.
- A guest-visible venue projection is pinned to an approved source plan revision and may be published independently of internal map data.
- Cockpit layouts and widget preferences are scoped to user/role and event, but all data access is independently permission checked.
- OperationalAlert actions are append-only history; changing alert status does not erase prior acknowledgement/assignment events.
- Notification delivery attempts are distinct from notification intent and must be traceable.
- RealtimeOutbox entries are committed in the same database transaction as the domain change they represent.

## 36.3 API conventions

The API remains versioned and resource-oriented. All Registry endpoints require explicit organization scope and Registry permissions. All event participation, portal, cockpit and staff endpoints require event scope. Public guest endpoints accept only the dedicated portal authorization context and return a strict response schema. Do not serialize internal ORM/database entities directly to clients.

## 36.4 Registry and event participation endpoint families

These endpoints illustrate the separation between organization-scoped person records and event-scoped participation records.

| Method and path | Purpose | Access boundary |
|---|---|---|
| `GET /api/v1/registry/people` | Search/list Registry people with pagination and filters | Registry search permission; field filtering |
| `POST /api/v1/registry/people` | Create a Person | Registry create permission |
| `GET /api/v1/registry/people/{personId}` | Retrieve permitted profile fields and history | Registry profile permission |
| `PATCH /api/v1/registry/people/{personId}` | Update profile with concurrency/version check | Registry edit permission |
| `POST /api/v1/registry/people/duplicate-review` | Request candidate duplicate matches | Registry duplicate-review permission |
| `POST /api/v1/registry/people/merge-preview` | Preview merge consequences | Registry merge permission |
| `POST /api/v1/registry/people/merge` | Commit approved merge | Elevated merge permission and audit |
| `POST /api/v1/events/{eventId}/guests` | Add an existing/new Person as an Event Guest | Event guest management plus Registry access required for chosen operation |
| `GET /api/v1/events/{eventId}/guests` | Search event participants | Event guest-list permission; no Registry-wide access implied |
| `PATCH /api/v1/events/{eventId}/guests/{eventGuestId}` | Edit event-specific participation fields | Event guest edit permission |
| `POST /api/v1/events/{eventId}/guests/{eventGuestId}/refresh-snapshot` | Refresh selected profile snapshot with impact preview | Explicit event permission and pre-publication policy |

## 36.5 Guest Portal and public venue endpoint families

The public-facing endpoint family is intentionally narrow and returns only the authenticated guest’s event-specific projection.

| Method and path | Purpose | Access boundary |
|---|---|---|
| `POST /api/v1/portal/access/exchange` | Exchange a one-time/opaque portal token for a scoped session | Public rate-limited endpoint; token validation |
| `POST /api/v1/portal/access/verify` | Complete configured second-factor verification | Public rate-limited endpoint |
| `GET /api/v1/portal/me` | Retrieve current guest-visible event information | Portal session only; one Event Guest |
| `GET /api/v1/portal/me/location` | Retrieve current permitted allocation and display labels | Portal session only |
| `GET /api/v1/portal/me/map` | Retrieve guest-visible venue projection and own destination marker | Portal session only; sanitized projection |
| `GET /api/v1/portal/me/directions` | Retrieve approved directions to current destination | Portal session only |
| `POST /api/v1/portal/access/revoke` | Revoke a portal session/token | Staff/admin permission or authorized self-service policy |
| `GET /api/v1/public/events/{eventPublicId}/information` | Retrieve explicitly public event information | Public allowlist; no guest-specific data |

No public endpoint may accept an arbitrary guest ID and return a guest profile or seat. The portal session resolves the event participant server-side.

## 36.6 Cockpit and workspace endpoint families

Cockpit and workspace endpoints return permission-filtered widgets and commands; the interface layout itself grants no authority.

| Method and path | Purpose | Access boundary |
|---|---|---|
| `GET /api/v1/events/{eventId}/cockpit/snapshot` | Retrieve authorized cockpit snapshot and revision cursors | Event cockpit view permission; field-filtered |
| `GET /api/v1/events/{eventId}/cockpit/widgets` | Retrieve available/assigned widgets | Workspace configuration permission |
| `PATCH /api/v1/events/{eventId}/cockpit/layout` | Save permitted layout preferences | User/workspace ownership; no access grant |
| `GET /api/v1/events/{eventId}/alerts` | Search/filter operational alerts | Alert view permission and scope |
| `POST /api/v1/events/{eventId}/alerts/{alertId}/acknowledge` | Acknowledge alert | Alert action permission |
| `POST /api/v1/events/{eventId}/alerts/{alertId}/assign` | Assign alert owner/team | Alert management permission |
| `POST /api/v1/events/{eventId}/alerts/{alertId}/resolve` | Resolve with code/comment/evidence reference | Resolution permission and audit |
| `GET /api/v1/events/{eventId}/timeline` | Retrieve permitted operational timeline | Event timeline permission; sensitive events filtered |
| `GET /api/v1/events/{eventId}/workspaces/me` | Retrieve current user's permitted workspace | Authenticated user; server-calculated effective roles |

Commands launched from the Cockpit must call the same application services as commands launched from dedicated modules. They must use the same validation, concurrency, approval and audit rules.

# 37. Real-time synchronization, notifications and consistency

## 37.1 Transactional event publication

The platform should use a transactional outbox pattern for important domain events. The domain transaction writes both the business change and an outbox entry. A publisher then delivers the event to authorized realtime channels. This avoids the case where a database commit succeeds but the notification is lost because the application process stopped before publishing.

Outbox delivery is at-least-once. Consumers must tolerate duplicates using event IDs and aggregate revision cursors. Ordering should be guaranteed per aggregate where required, not assumed globally across the entire platform.

## 37.2 Realtime event families

Examples of domain events include:

- `person.profile.updated` (Registry-authorized subscribers only; never broadcast organization-wide profile fields by default).
- `event.guest.added`, `event.guest.updated`, `event.guest.archived`.
- `event.guest.snapshot.refreshed`.
- `allocation.candidate.created`, `allocation.committed`, `allocation.reflowed`.
- `plan.approved`, `plan.published`, `plan.superseded`.
- `guest.location.changed` (event staff and the affected guest portal session only, according to policy).
- `guest.portal.access.revoked`.
- `venue.public_projection.published`.
- `checkin.recorded`, `checkin.exception.raised`, `station.health.changed`.
- `operational.alert.created`, `operational.alert.acknowledged`, `operational.alert.assigned`, `operational.alert.resolved`.
- `notification.queued`, `notification.delivered`, `notification.failed`.
- `prerequisite.status.changed` (minimal status projection for permitted Cockpit roles; no confidential external content).

The exact names are illustrative contracts and must be frozen in the detailed API/event design. Events should include event ID, aggregate ID, event ID, aggregate revision, timestamp, correlation ID and minimal metadata. Avoid sensitive fields and full guest profile payloads in broadcast messages.

## 37.3 Client synchronization contract

Every realtime-enabled client should:

1. Fetch an authorized initial snapshot with a server-issued cursor/revision.
2. Subscribe to the authorized channel using its authenticated context.
3. Apply duplicate-safe events only when the aggregate/revision sequence is valid.
4. Re-fetch the affected resource if an event indicates an unknown revision or missed gap.
5. Re-fetch a fresh authorized snapshot after reconnect or prolonged inactivity.
6. Show a visible stale/degraded indicator when it cannot confirm current state.

The Cockpit must never infer that a guest is physically present solely because an allocation changed. Attendance is sourced from check-in records. Similarly, an alert notification does not constitute acknowledgement or resolution.

## 37.4 Notification engine

Notification intent is separate from transport. The platform should support pluggable channels (initially email and downloadable/printable output; SMS or messaging integrations may be added later). The notification subsystem must provide:

- Templates with versioning, localization and event branding.
- Recipient selection from an approved event audience, not arbitrary unfiltered Registry export.
- Preview, test send and approval policy for mass communication.
- Idempotency keys, rate limiting and suppression of duplicate sends.
- Delivery state, retries, bounce/failure capture and operator review.
- Preference, consent and communication-policy enforcement.
- A clear distinction between message queued, accepted by provider, delivered (where verifiable) and read (only where the channel supports it).

A seating change should create a notification task only when the event communication policy requires it. The system must not disclose other guests' locations or sensitive reasons for the change.

## 37.5 Atomic seating change workflow

An approved live reallocation/publish operation should coordinate these effects:

1. Validate hard constraints, capacity, locks and current plan revision.
2. Commit the new assignment and new immutable plan revision transactionally.
3. Mark prior related print artifacts as superseded or stale.
4. Invalidate or refresh the guest-visible map projection as required.
5. Write outbox events for staff/Cockpit updates and affected guest portal views.
6. Queue configured guest/staff notifications with idempotency keys.
7. Record the operator, reason, approval and impact summary.

If an external notification provider is unavailable, the seating plan commit must not be rolled back solely because a message could not be delivered. The notification remains queued/failed for retry and visible to authorized operators.

# 38. Security, privacy and access-control extensions

## 38.1 Separate access domains

The platform has at least four access domains:

- **Registry domain:** persistent person profiles and cross-event identity.
- **Event operations domain:** event guest participation, venue, seating, approval, check-in and cockpit.
- **Guest portal domain:** a guest's own event-specific approved information and map projection.
- **External prerequisite coordination:** event-scoped request, scheduling and completion metadata; not the police inspection record.

A role in one domain does not automatically grant access to another. The guest portal never receives prerequisite coordination access. A check-in operator does not receive Registry-wide search or export rights by default. A Cockpit layout does not widen underlying permissions.

## 38.2 Guest Registry privacy controls

- Use organization-scoped access and explicit purpose-based permission for cross-event search.
- Apply field-level classification and redact fields in search results, exports and audit views unless authorized.
- Log profile access, export, merge, attachment download and sensitive edits.
- Support configurable retention, archive and anonymization workflows.
- Separate contact preferences and communication permission from event attendance state.
- Do not treat historical participation as permission to contact a person for a future event.
- Minimize duplicate identity attributes and avoid storing highly sensitive official identifiers unless specifically required and approved.
- Encrypt transport and backups; consider encryption-at-rest controls appropriate to the deployment and threat model.

## 38.3 Guest portal controls

- Use high-entropy portal tokens with expiry/revocation, hashed storage and rate-limited verification.
- Keep portal token, admission/check-in credential and staff session separate.
- Prevent guest enumeration and use non-oracular error responses.
- Apply CSRF/session protections appropriate to the authentication design, secure cookies where used, and strict origin/CORS policy.
- Use a dedicated response schema and API boundary; never expose internal ORM records.
- Restrict cached data to sanitized maps and the minimum guest-specific data; set cache expiry and clear guest kiosk state.
- Avoid third-party analytics, trackers or externally hosted map tiles that could disclose guest access patterns unless explicitly reviewed and approved.
- Ensure map images, vector layers, print assets and generated URLs cannot reveal staff-only layers or predictable internal object IDs.
- Record portal access and token revocation without collecting unnecessary browsing telemetry.

## 38.4 Cockpit and staff controls

- Check permissions server-side for every widget data request, alert detail, timeline entry, map layer and command.
- Distinguish read-only panels from executable controls.
- Require re-authentication/step-up confirmation for high-impact actions where configured.
- Show the user's effective scope and event context to reduce wrong-event actions.
- Apply audit records for allocation changes, plan publication, credential revocation, mass notification, attendance correction and sensitive state transitions.
- Prevent stale browser tabs from committing commands against outdated plan versions; require revision checks and conflict resolution.

## 38.5 Provisional service targets

These are initial engineering targets for validation, not external service-level promises:

| Area | Provisional target | Measurement note |
|---|---|---|
| Simple Registry/event search | p95 under 500 ms on the target LAN at agreed test load | Excludes large exports and expensive fuzzy-match jobs |
| Cockpit incremental update | p95 visible within 2 seconds of committed event on a healthy LAN | Measure server commit to authorized client update |
| Guest portal initial view | Usable main content within 3 seconds on agreed mobile-network profile | Map may load progressively; provide text fallback |
| Online QR resolution | p95 under 2 seconds on target network | Includes token validation and permitted guest location retrieval |
| Reconnect recovery | Fresh snapshot obtained within 5 seconds after stable reconnection | Depends on network and event data size |
| Availability | Set per event and deployment profile | Do not promise internet-grade availability for a single LAN server without redundancy |

Phase 0 must test expected peak users, concurrent scanners, registry size, event size, venue map complexity and worst-case connectivity. Targets may be adjusted based on measured results.

# 39. Delivery plan, testing and acceptance updates

## 39.1 Revised implementation sequence

The existing roadmap remains, with the following adjustments to keep architectural dependencies in the correct order:

| Phase | Required additions and exit gate |
|---|---|
| Phase 0 - Product discovery and technical spikes | Confirm Person vs Event Guest data ownership; field classification and retention; identity matching/merge workflow; guest portal access and credential separation; public map projection; Cockpit wireframes and widget priorities; expected concurrency and performance profile. Exit only when the data boundary and access model are approved. |
| Phase 1 - Foundation and manual operations | Build organization-scoped Person Registry and event-scoped participation records from the start; full guest CRUD and import/duplicate review; event/venue model; role permissions; Cockpit shell with snapshot panels; manual allocation and audit. Exit with one person reused across events without historical record corruption. |
| Phase 2 - Rules and optimization | Implement constraints and reflow; add live cockpit allocation/exception panels and controlled intervention entry points; preserve assignment history and concurrency checks. |
| Phase 3 - Publication, cards and check-in | Plan revisions, guest cards, separate admission credentials, online multi-station check-in, printed staff plans and published venue maps. Exit with current plan resolvable from staff interfaces. |
| Phase 4 - Guest Portal and event-day operations | Guest Portal access, sanitized map projection, personal seating view, basic wayfinding, seating-change updates, Cockpit alerts/timeline and role-specific workspaces. External prerequisite coordination remains separately permissioned where needed. |
| Phase 5 - Resilience and advanced capabilities | Offline PWA check-in/portal fallback where safe, route graph enhancements, advanced notification channels, cockpit customization, analytics and integrations. |

The Registry and Cockpit foundations are not deferred to a later phase. Advanced cockpit analytics, sophisticated wayfinding and additional notification channels may be phased.

## 39.2 Additional unit tests

- Person creation, profile edit, archive and retention state.
- Event Guest creation and one-person/many-event relation.
- Event snapshot creation, refresh and immutability after publication.
- Duplicate candidate generation, reviewer decision and merge audit.
- Field-level Registry authorization and export redaction.
- Portal token generation, hashing, expiry, revocation and event scoping.
- Guest-visible map projection allowlist and restricted-object omission.
- Wayfinding route graph, inaccessible edges and closed-path behavior.
- Cockpit alert deduplication, state transitions and ownership.
- Workspace configuration that does not change effective permissions.
- Realtime outbox duplicate delivery and idempotent consumers.
- Notification retry, suppression and delivery-state transitions.

## 39.3 Additional integration and end-to-end tests

- Reuse one person in two events and verify event-specific RSVP, allocation and attendance remain independent.
- Update a master profile and verify historical event snapshots and previously approved documents are unchanged.
- Attempt to search the Registry using an event-only account and verify denial/redaction.
- Merge duplicate records and verify event participation links and audit history remain correct.
- Open a Guest Portal session, view only the current guest's map/location, then attempt guest enumeration and direct object-ID substitution.
- Publish a seating change and verify the portal, affected staff workspace and Cockpit show the new revision while stale print artifacts are marked.
- Verify a guest-visible map never exposes restricted map objects or prerequisite coordination records, including through cached assets.
- Simulate a portal token leak, revoke it and verify subsequent access fails.
- Run concurrent cockpit operators against the same plan revision and verify stale writes are rejected and reconciled.
- Disconnect a Cockpit client, make changes, reconnect and verify full snapshot reconciliation with stale-state warning.
- Verify a check-in operator sees enough location data to guide the guest but cannot access Registry-wide details.
- Verify an alert can be acknowledged, assigned and resolved only by permitted roles and the history remains intact.
- Verify notification failure does not roll back a committed seating plan and the failed delivery remains visible for retry.

## 39.4 Additional acceptance criteria

The first production-capable release must also demonstrate:

1. A Registry Person can be added to multiple events without duplicating the person's master identity.
2. Each event can maintain its own RSVP, category, group, allocation, credential and attendance status.
3. A master profile change does not silently rewrite an approved or historical event snapshot.
4. Duplicate candidates can be reviewed and merged under an auditable workflow.
5. Event-only permissions do not imply cross-event Registry access.
6. The Guest Portal can be enabled/disabled per event without affecting staff operations.
7. A guest can securely view their own location and a sanitized floor plan on a mobile browser.
8. Guest location is rendered correctly for banquet, theatre/cinema and tableless capacity-zone layouts.
9. The Guest Portal does not reveal other guests, staff-only map layers or external prerequisite information.
10. A seating change updates the guest's current portal view after publication and creates configured notification tasks.
11. The Cockpit presents live, permission-filtered KPIs, map layers, alerts and timeline entries.
12. Cockpit controls use the same validation, approval and audit services as dedicated module screens.
13. Staff roles receive distinct workspaces without permissions being inferred from workspace layout.
14. The Cockpit visibly indicates stale data and recovers from a dropped realtime connection.
15. An operational alert can be acknowledged, assigned, escalated and resolved with full history.
16. Registry, portal, cockpit and notification data are included in backup/restore and retention tests.

## 39.5 Decisions to validate before implementation

The following decisions should be confirmed during discovery, with the recommended defaults used unless the responsible organization specifies otherwise.

| Topic | Recommended default | Why it matters |
|---|---|---|
| Registry ownership | One organization-level Person per human, with event-scoped Event Guest records | Prevents repeat-event duplication and event data leakage. |
| Person matching | Human-reviewed duplicate resolution; automatic merge disabled | Name similarity is not reliable identity proof. |
| Event snapshot | Snapshot when added and at controlled issue/approval points | Preserves historical accuracy. |
| Guest Portal | Responsive PWA, optional per event | Broad device support without native app maintenance. |
| Portal credential | Dedicated revocable portal token/session separate from admission QR | Limits bearer-token exposure. |
| Guest-facing map | Explicitly published sanitized projection | Prevents internal venue detail exposure. |
| Wayfinding scope | Static/textual route first; graph-based route next; indoor positioning out of scope | Delivers value without overengineering. |
| Cockpit | Default admin landing page, configurable panels, shared backend services | Keeps operations centralized and consistent. |
| Role workspaces | Role-based templates; individual permission enforcement | Tailors information without creating privilege escalation. |
| Realtime | Transactional outbox and revision/cursor-based client synchronization | Avoids missed updates and stale dashboards. |
| Notifications | Separate queue and delivery state; plan commit is independent of delivery success | Prevents external provider failure from undoing event operations. |

## 39.6 Additional risks and mitigations

The v1.1 extension adds the following risks to the baseline risk register.

| Risk | Impact | Mitigation |
|---|---|---|
| Registry treated as a flat global address book | Cross-event privacy exposure | Organization scope, distinct Registry permissions, data classification and auditing. |
| Duplicate person merged incorrectly | Incorrect history, invitations or personal data | Human review, merge preview, audit and controlled compensating workflow. |
| Event snapshots silently follow master edits | Historical cards/reports become inaccurate | Immutable snapshots and explicit refresh action. |
| Admission QR doubles as portal login | Anyone holding a pass may browse personal data | Separate tokens, separate session boundary and optional second factor. |
| Guest-facing map exposes internal geometry | Sensitive venue information disclosed | Sanitized projection, allowlist and publication review. |
| Portal displays stale seating | Guest goes to obsolete seat | Server-resolved current assignment, revision/time display and stale warnings. |
| Cockpit dashboard overload | Important alerts are missed | Role tailoring, panel priorities, deduplication and severity policy. |
| Realtime connection silently stops | Decisions based on stale state | Heartbeat, timestamp, stale indicator and snapshot reconciliation. |
| Workspace customization grants excess access | Privilege escalation | Workspace layout is presentation-only; backend authorization per request. |
| Notification delivery fails after a seating move | Guest may not receive update | Durable retry queue, visible failed state and alternate contact procedure. |

# 40. Technical references

These are upstream technical references for the proposed implementation choices. They are not a commitment to a specific package version; versions must be pinned during Phase 0/implementation.

1. Vue - Using Vue with TypeScript: https://vuejs.org/guide/typescript/overview
2. Fastify - TypeScript documentation: https://fastify.dev/docs/latest/Reference/TypeScript/
3. PostgreSQL - Row Security Policies: https://www.postgresql.org/docs/current/ddl-rowsecurity.html
4. PostgreSQL - Transactions and Locking: https://www.postgresql.org/docs/current/xact-locking.html
5. Google OR-Tools - CP-SAT Solver: https://developers.google.com/optimization/cp/cp_solver
6. Google OR-Tools - C++ getting started: https://developers.google.com/optimization/introduction/cpp
7. Mozilla PDF.js: https://mozilla.github.io/pdf.js/
8. ZXing browser layer: https://github.com/zxing-js/browser

---


These are upstream technical references for the proposed implementation choices. They are not a commitment to a specific package version; versions must be pinned during Phase 0/implementation.

1. Vue - Using Vue with TypeScript: https://vuejs.org/guide/typescript/overview
2. Fastify - TypeScript documentation: https://fastify.dev/docs/latest/Reference/TypeScript/
3. PostgreSQL - Row Security Policies: https://www.postgresql.org/docs/current/ddl-rowsecurity.html
4. PostgreSQL - Transactions and Locking: https://www.postgresql.org/docs/current/xact-locking.html
5. Google OR-Tools - CP-SAT Solver: https://developers.google.com/optimization/cp/cp_solver
6. Google OR-Tools - C++ getting started: https://developers.google.com/optimization/introduction/cpp
7. Mozilla PDF.js: https://mozilla.github.io/pdf.js/
8. ZXing browser layer: https://github.com/zxing-js/browser

---

# Appendix A - Example separation-rule language

The rule builder should translate plain operational intent into an explicit, testable constraint. Examples:

| Administrator intent | Rule model |
|---|---|
| A and B must not share a table | Pair separation; scope = same table; strength = hard |
| A and B should be in different rooms | Pair separation; scope = same room; strength = soft or hard |
| All members of Delegation X must be distributed across at least 3 zones | Group distribution; minimum distinct zones = 3; strength = hard |
| Members of Group Y must remain together | Group cohesion; scope = same table; strength = hard or soft |
| A must be near the stage | Preferred area/zone; scope = configured distance or zone; strength = soft |
| A cannot use stairs | Accessibility requirement; permitted levels/resources only; strength = hard |
| Keep two rival delegations in separate buildings | Group-to-group separation; scope = same building; strength = hard |

The UI should show a human-readable sentence and the exact structured interpretation before saving the rule.

# Appendix B - Example live reflow scenario

Scenario: a room becomes unavailable after the approved plan has been issued.

1. An authorized operator marks the room unavailable and records a reason.
2. The platform identifies all affected allocations and the current published revision.
3. The operator chooses whether to preserve all unaffected assignments (default) or allow a wider reallocation.
4. The solver evaluates remaining capacity and hard/soft rules.
5. If feasible, the preview shows every moved guest and destination.
6. If infeasible, the platform reports the limiting constraints and affected guest count; it does not silently force an invalid plan.
7. An authorized administrator accepts the candidate.
8. The platform creates a new allocation/plan revision, updates live staff views and marks prior print outputs superseded.
9. Guest cards are flagged for reissue where their printed allocation fields changed.
10. Check-in resolves the current location from the server, not from stale printed card text.

# Appendix C - Example event data and operating modes

The examples below show how the same event and guest model produces different location outputs for different physical allocation types.

| Example | Venue | Allocation resource | Guest location output |
|---|---|---|---|
| Formal gala | Multi-zone banquet hall | Table + individual seat | Building, level, room, zone, table, seat |
| Ambassador reception | Mixed hall and VIP rooms | Standing zone capacity + reserved seats | Building, level, zone; seat only where applicable |
| Cinema screening | Auditorium | Fixed row/seat | Building, level, room, row, seat |
| Conference | Multiple rooms | Classroom seats and standing networking zone | Building, room, zone, row/seat where applicable |
| Outdoor event | Outdoor zones | Capacity pool | Site, area, zone; no seat required |


# Appendix D - Glossary

Key terms used throughout the architecture and requirements are defined below.

| Term | Definition |
|---|---|
| Allocation | The assignment of an event guest/group to a seat, table, row, zone or capacity pool. |
| Person | A persistent organization-scoped human identity in the Guest Registry. |
| Event Guest | An event-scoped participation record linked to a Registry Person. |
| Event snapshot | An immutable capture of profile/event values used by an event at a defined point in time. |
| Guest Registry | Persistent directory of people reusable across events under organization-level permissions. |
| Guest Portal | Optional guest-facing application view showing only the authenticated guest's permitted event information. |
| Guest-visible venue projection | Sanitized, published subset of venue geometry and navigation data approved for guest display. |
| Wayfinding | Presentation of approved directions from a guest entry point to an assigned location. |
| Event Operations Cockpit | Live command interface for authorized event monitoring, alerts, timeline and interventions. |
| Operational alert | Structured, actionable exception with severity, owner, lifecycle and history. |
| Staff workspace | Role-tailored panel/navigation configuration that does not itself grant permissions. |
| Transactional outbox | Durable record committed with a domain change and published asynchronously to realtime consumers. |
| Allocation revision | A versioned set of assignments and associated allocation context. |
| CDI | An inspection performed by the competent external police authority; the platform records only whether it is required, requested, scheduled and completion-confirmed. |
| Capacity pool | A bounded number of admissions in an area without individually numbered seats. |
| Hard constraint | A condition that a valid allocation must satisfy. |
| Soft preference | A desirable condition that contributes to an optimization score but may be traded off. |
| Separation scope | The physical/logical level at which two guests/groups must not be co-located. |
| Reflow | Recalculation of some or all assignments in response to a change, usually preserving unaffected/locked assignments. |
| Plan revision | An immutable snapshot of a floor plan, resources, allocations and approval context. |
| Staff plan viewer | A simplified read-only view of a published plan for authorized event staff. |
| Guest credential | A revocable QR/bearer token associated with a guest and event; not the guest's identity itself. |
| Check-in record | An auditable record that a guest presented a credential or was manually registered as arrived. |


# Appendix E - Guest Registry lifecycle example

1. An administrator imports a new event list.
2. The import preview identifies 420 likely existing Registry people, 35 uncertain matches and 45 new people.
3. An authorized reviewer confirms matches, resolves uncertain cases and creates new profiles for the remaining people.
4. The selected people are linked to the event through Event Guest records.
5. The event stores category, RSVP, allocation and event-specific overrides independently from the Registry.
6. A master contact correction later updates the Registry, but the published event snapshot remains unchanged until an authorized refresh is approved.
7. The next event can reuse the same Person records while creating fresh event participation records.

# Appendix F - Guest Portal and wayfinding example

1. An administrator enables the portal for an event and publishes a guest-visible projection of the approved floor plan.
2. A guest opens their dedicated portal link and completes the configured verification step.
3. The portal resolves the current Event Guest from the session and displays only that person's approved location.
4. A cinema guest sees section, row and seat; a reception guest sees a zone and entrance; a banquet guest sees table and seat.
5. The administrator moves one guest and publishes a new revision.
6. The guest portal displays the new location and update time; configured notification tasks are queued.
7. The prior map projection and printed artifacts are retained as historical/superseded versions, not silently overwritten.

# Appendix G - Cockpit alert and intervention example

Scenario: a room becomes unavailable while the event is live.

1. The venue coordinator records the room closure with a reason.
2. The Cockpit creates or updates a high-severity operational alert and shows affected capacity and guests.
3. The seating coordinator opens a targeted reallocation preview from the alert.
4. The solver proposes changes while preserving locked and unaffected assignments where possible.
5. The Cockpit displays affected guests, destination resources, constraints and downstream effects.
6. An authorized administrator approves the new plan revision.
7. Staff workspaces and the Guest Portal receive permission-filtered updates; stale print artifacts are marked.
8. The alert remains open until the responsible user confirms the operational issue is resolved.

---

**End of blueprint - Version 1.2**


# 41. Organization, venue and event branding

## 41.1 Branding is a platform capability

The application MUST support an organization-specific visual identity. A deployment configured for GHB should look and behave as a GHB-branded system in the authorized administration shell, staff workspaces, Guest Portal and generated materials. A second organization using the same software must be able to use its own identity without affecting GHB.

Branding is attached to the organization/tenant and optionally overridden by a venue or event. It is not tied to an individual staff account. Individual users may choose accessibility or interface preferences (for example, light/dark mode), but those preferences MUST NOT change the organization’s invitations, passes, reports or public presentation.

## 41.2 Inheritance and precedence

Brand resolution uses this precedence:

`Event override -> Venue brand profile -> Organization brand profile -> Platform default`

Each layer may override selected properties rather than requiring a complete brand definition. Missing values inherit from the next level. The resolved brand is materialized as a versioned snapshot when an event template or generated artifact is published.

Examples:

- Organization: GHB logo, primary colours, typography, graphic style and default templates.
- Venue: optional venue-specific location mark, room motif or venue-specific directions/signage.
- Event: optional anniversary/conference sub-brand, event title graphic, special accent or event-specific image.

A venue or event override MUST NOT mutate the underlying organization profile. Authorized users can preview the resolved brand before publication.

## 41.3 Brand profile contents

A brand profile should support:

- Primary, secondary, accent, neutral and status colour tokens.
- Light-background and dark-background logo variants (SVG/PNG, with safe sanitization).
- Optional wordmark, emblem, seal, sponsor marks and partner logos with display rules.
- Typography choices and approved fallback fonts.
- Header/footer treatments, backgrounds, patterns and image assets.
- Icon/illustration style and optional venue/event graphics.
- Document margins, visual hierarchy and template-specific display rules.
- Language-specific organization name, address, contact and footer text.
- Optional display name and sender identity metadata for approved communication channels.

Brand assets are uploaded to private, tenant-scoped storage, validated for file type/size and referenced by immutable asset IDs. SVG assets must be sanitized before use. The system must not load arbitrary remote assets into sensitive interfaces or documents.

## 41.4 Surfaces that inherit the brand

The resolved brand may apply to:

- Login/organization selection and authorized application shell.
- Admin Cockpit and staff workspaces.
- Guest Portal and event landing page.
- Digital invitations, RSVP pages and confirmation messages.
- Guest cards, badges and admission passes.
- QR-code framing and credential print layouts (the token itself remains opaque).
- Seating plans, venue maps, zone legends and wayfinding sheets.
- Reception signage and coordinator printouts.
- Reports, exports and event summary PDFs.
- Approved email templates and other configured communication channels.

Branding must never override information classification. A restricted attachment or internal-only note must not become guest-visible because it is placed in a branded template.

## 41.5 Templates and revision control

Templates are scoped to organization, venue or event and have their own revisions. A generated invitation, card or report records the template revision and resolved brand revision used. A later brand change MUST NOT silently alter previously generated or distributed material. Reissue/re-render is an explicit operation.

Template categories include invitation, RSVP, guest card, QR pass, seating plan, zone plan, wayfinding sheet, check-in sign, report and operational summary. Templates support field bindings to approved data, conditional blocks, language variants, print dimensions and preview data. Template editing is permission-controlled and changes are previewed before publishing.

## 41.6 Multi-tenant and deployment model

The initial GHB deployment may run as a single-organization installation. The data model MUST remain tenant-aware: every organization-owned entity carries an organization/tenant scope, and every query/write is validated against that scope. A shared multi-organization deployment may be enabled later only after tenant isolation tests, storage isolation and permission review pass.

Organization branding, assets, templates, Guest Registry people and venue templates are isolated by tenant. A user belonging to multiple organizations selects an active organization context; the server validates this context for each request. A venue belongs to an organization, while an event may reference one or more venues belonging to the same organization or to explicitly authorized partner organizations.

## 41.7 Acceptance criteria

- GHB branding appears consistently across the configured application, portal, invitations, passes and print templates.
- A second organization can use a different logo, palette and templates without cross-contamination.
- Venue and event overrides can change selected tokens while inheriting the rest.
- A published artifact retains the exact brand/template revisions used to generate it.
- Rebranding does not silently modify already-issued passes or sent invitations.
- Brand asset URLs and template records cannot be accessed across tenant boundaries.

# 42. GHB reference venue portfolio

## 42.1 Reference deployment, not a hardcoded product assumption

Gazi Husrev-beg’s Library (GHB) is the first reference organization/tenant for discovery and initial configuration. The platform remains a general-purpose product. GHB names, brand assets, room names, capacities and layouts must be stored as organization data and venue templates, not embedded as application constants.

The initial GHB reference portfolio should include:

- Large hall.
- Medium hall.
- Small hall.
- Mosque/prayer-space configuration used for selected events or event sessions.

The mosque/prayer space may be registered as a separate venue/site or as a related space under the GHB organization, depending on the actual operational and ownership structure. The software must not assume that it is physically part of the Library building. The hierarchy can represent a venue portfolio with distinct sites.

## 42.2 Reusable space templates

Each hall or space has a versioned template containing:

- Physical/site identity and hierarchy.
- Floor-plan background and calibration.
- Room boundary and usable areas.
- Zones and their visual styles.
- Spatial features and non-allocatable regions.
- Tables, fixed seats, rows, floor-position resources or capacity pools.
- Approved capacities and source/approval metadata.
- Entrances and public/staff navigation points.
- Layer visibility and audience projections.
- Default allocation model and numbering scheme.

An event session references an immutable venue-template revision. Changes to a master template do not silently change an event already in planning, approved or live.

## 42.3 Supplied mosque seating workbook - observed reference

The supplied workbook, `plan begove džamije menšura.xlsx`, contains one worksheet and a cell-formatted visual plan. It is a practical reference for the way the venue is currently organized. The workbook is not a relational guest list and should not be treated as a direct source of live guest allocations.

The visible plan includes the following annotations (all values require confirmation by the venue coordinator before becoming authoritative system capacity values):

| Workbook annotation | What the platform should represent |
|---|---|
| CRVENA ZONA = 74 | Red zone polygon/region with a proposed capacity annotation of 74. |
| ZELENA ZONA = 150 | Green zone polygon/region with a proposed capacity annotation of 150. |
| PLAVA ZONA = 140 | Blue zone polygon/region with a proposed capacity annotation of 140. |
| MAHFIL DONJI = 14 | Named special area with a proposed capacity annotation of 14. |
| MAHFIL GORNJI = 10 | Named special area with a proposed capacity annotation of 10. |
| MAKSURA LIJEVA = 10 | Named left-side special area with a proposed capacity annotation of 10. |
| MAKSURA DESNA = 10 | Named right-side special area with a proposed capacity annotation of 10. |

The drawing also labels or depicts a minber, pillars (`STUB`), a passage (`STUB I PROLAZ`), an entrance (`ULAZ`) and footwear areas (`OBUĆA`), alongside numbered blocks/rows. These are important venue features and must be represented as their correct spatial types rather than being interpreted as seats.

## 42.4 Numbering and labels

The workbook shows visible numbering sequences repeated in different blocks/rows/areas. The same display number can occur in more than one place. Therefore:

- A display number is not a globally unique identifier.
- Each place receives an immutable internal resource ID.
- The visible locator is composed from its parents, such as `BLUE / ROW 04 / POSITION 12` or `MAHFIL DONJI / POSITION 03`.
- Numbering schemes are configurable by zone, row, block or special area.
- The interface and exports must make the scope explicit so two different “Seat 1” or “Position 1” labels are never ambiguous.

## 42.5 Capacity confirmation

The annotated numbers in the workbook are source values, not automatically approved occupancy limits. Before activation, an authorized venue representative must confirm:

- Whether each annotation is a seat/position count, a recommended allocation limit or another planning figure.
- Whether the named special areas overlap or are included in the coloured-zone values.
- Which spaces are allocatable, reserved or non-allocatable.
- Whether a row/position is suitable for individual assignment or should remain zone-only.
- The operational limit to use for each event configuration.

Do not sum overlapping annotations or calculate a total capacity until their relationship is confirmed.

# 43. Generalized spatial allocation model

## 43.1 Four separate concepts

The v1.2 spatial model distinguishes four concepts that must not be collapsed into a single “seat” table:

1. **Spatial feature:** a physical object or landmark, such as a pillar, wall, minber, entrance, footwear area, passage or stage. Usually not assignable.
2. **Spatial region:** a polygon or boundary, such as a room, coloured zone, reserved area or no-allocation area.
3. **Allocation resource:** an individually assignable unit, such as a chair, numbered theatre seat, floor position, desk position or row segment.
4. **Capacity pool:** a quantity limit for an area where individual positions are not assigned, such as general admission or a zone-only allocation.

A visual object can exist without an allocation resource. A capacity pool can exist without individually drawn positions.

## 43.2 Allocation modes

A space can enable one or more modes:

- `individual_seat`: one guest per physical chair/seat.
- `numbered_floor_position`: one guest per logical position on a floor/carpet, with no chair implied.
- `row_or_segment`: assign a guest/group to a row or bounded segment without choosing a precise position.
- `zone_capacity`: assign a guest/group to a zone and decrement its approved capacity.
- `unassigned_open`: no individual placement; attendance is counted at a broader level, subject to event policy.

The allocation engine must know which mode applies to each resource/space. It must not invent seat objects in a zone-only layout.

## 43.3 Numbering scopes

Each resource may have a visible label and a numbering scheme. Numbering scope can be:

- Venue-wide.
- Space/room-wide.
- Zone-wide.
- Section/block-wide.
- Row-wide.
- Parent resource-specific (for example, seat numbers within a table).

The internal resource ID remains globally unique within the tenant. The composed locator is generated from the hierarchy and can be localized/formatted for cards, portal and printouts.

## 43.4 Spatial geometry and operational features

The native editor should support:

- Points for individual positions, entrances and landmarks.
- Lines/poly-lines for rows, aisles, paths and boundaries.
- Polygons for rooms, zones, reserved areas, special areas and restricted regions.
- Rotated rectangles/circles/custom shapes for furniture and obstacles.
- Layers and audience-specific visibility.

The map must support explicit orientation, labels, a legend and accessible non-colour identifiers. Colour coding is useful but MUST NOT be the only way to distinguish a zone; every zone also needs a name/code/pattern or other readable identifier.

## 43.5 Position allocation and group placement

For a prayer-row layout, an administrator may allocate:

- A guest to a zone only.
- A guest to a zone and row.
- A guest to a specific numbered floor position.
- A family/delegation to a contiguous range or group of positions, where supported by rules and capacity.

The engine should preserve contiguous group placements when requested, support explicit separation across zones/rows, and report when a group cannot fit within the available contiguous capacity. It must not assume that a row's positions are physically identical to cinema seats; the spatial resource type carries the distinction.

## 43.6 Capacity validation

The capacity model supports both explicit resource counts and manually approved zone limits. The system may display counts derived from configured resources, but an authorized venue representative must approve the operational limit. The strictest applicable approved limit is used. The editor must show the source and approval date for capacity values.

# 44. Spreadsheet floor-plan onboarding

## 44.1 Treat the workbook as a reference artifact

The supplied Excel map is a cell-formatted drawing with grid boundaries, labels, colours and visible numbering. It is not a structured GIS/CAD object model and it is not a guest allocation database. The application must preserve the original workbook as an immutable source artifact and must not assume that every cell containing a number represents an independently assignable place.

## 44.2 Import workflow

1. Upload the original XLSX into a private source-artifact store and calculate a content hash.
2. Select worksheet(s) and import the workbook as a read-only reference.
3. Render the selected sheet to PDF/image using a controlled server-side conversion process; preserve the original workbook unchanged.
4. Display the rendered plan in the native floor-plan editor as a locked background layer.
5. Set orientation, crop, scale and a known measurement where available.
6. Trace/define room boundaries, coloured zones, special areas and non-allocatable features.
7. Create rows, row segments and optional numbered floor-position resources; import readable labels/numbers as suggestions where extraction is reliable.
8. Map source regions/labels to native spatial objects, retaining the source worksheet and cell/region references where feasible.
9. Validate numbering scopes, duplicate display labels, capacities, overlaps, entrances, passages and no-allocation areas.
10. Compare the native reconstruction side-by-side with the source workbook and have an authorized venue coordinator review it.
11. Approve and version the native venue template; record approver, date, source hash and any assumptions.

## 44.3 Automation boundaries

The application MAY extract text, cell values, merged ranges, formatting, borders and fill colours to assist the conversion. Such extraction is advisory. It MUST NOT infer that every numeric cell is a seat, that each colour is a capacity zone, or that numeric annotations are validated capacities without review. The initial release should prioritize a reliable reference-background-plus-trace workflow over fragile automatic reconstruction of arbitrary Excel artwork.

## 44.4 Source-to-native traceability

Each native object created from the source plan may carry a source reference: workbook hash, worksheet name, source cell/range or visual region, extraction method and reviewer. When the native plan changes, the source remains immutable and can be reopened for comparison. A future revision may be imported as a new source artifact and compared against the current native plan.

## 44.5 Conversion acceptance criteria

- The original workbook is retained and downloadable only by authorized venue/floor-plan users.
- The source is rendered consistently for visual comparison.
- The editor can overlay editable zones, spatial features and positions.
- Repeated display numbers are accepted when their parent scopes differ.
- Duplicate internal resource IDs are impossible.
- Position and capacity counts are reviewed before approval.
- The approved native plan can be published to staff and a sanitized guest-visible projection can be generated separately.

# 45. External prerequisites and CDI coordination

Section 15 is the authoritative functional definition. This section records the v1.2 boundary for data, API, cockpit and acceptance design.

## 45.1 Data and API

Use an `event_prerequisites` record with fields such as `event_id`, `prerequisite_type`, `display_label`, `required`, `readiness_gate`, `external_party_name/reference`, `internal_owner_user_id`, `status`, `request_submitted_at`, `external_reference`, `scheduled_at`, `completion_recorded_at`, `completion_recorded_by`, `completion_reference`, `notes` and timestamps. Keep a `prerequisite_status_history` table for transitions. Optional supporting documents must use restricted storage and retention.

Representative routes:

- `GET /api/v1/events/{eventId}/prerequisites`
- `POST /api/v1/events/{eventId}/prerequisites`
- `PATCH /api/v1/prerequisites/{prerequisiteId}`
- `POST /api/v1/prerequisites/{prerequisiteId}/record-completion`
- `GET /api/v1/prerequisites/{prerequisiteId}/history`

These are illustrative route names, not final OpenAPI definitions.

## 45.2 Cockpit integration

The Cockpit may show the prerequisite label, required/not-required state, current coordination status, due date and internal owner. It must not expose inspection methods, confidential correspondence or external authority reports to general event staff. A readiness gate is a workflow rule configured by the organization, not an independent legal determination by the software.

## 45.3 Acceptance criteria

- An administrator can mark CDI as required or not required and record who made the decision.
- An internal coordinator can record request submission, reference, scheduled time and completion confirmation.
- Status changes are timestamped and auditable.
- If configured as a required gate, the event cannot enter the configured Ready state until completion is recorded or an authorized exception is applied.
- The interface clearly states that the police perform the inspection.
- No internal inspection checklist, findings-management or inspection-methodology feature is implemented.

# 46. v1.2 data, API, security, delivery and acceptance updates

## 46.1 Data-model additions and refinements

Add or formalize:

- `brand_profiles`, `brand_profile_revisions`, `brand_assets`, `brand_template_assignments`, `venue_brand_overrides`, `event_brand_overrides`, `event_brand_snapshots`.
- `source_plan_artifacts`, `source_plan_mappings`, `spatial_features`, `spatial_regions`, `spatial_rows`/`row_segments` and typed `allocation_resources` for chairs, floor positions and capacity pools.
- `event_prerequisites`, `external_parties` and `prerequisite_status_history`.
- Tenant/organization scope on brand assets, templates, venue templates, Guest Registry records and generated documents.

The physical schema must preserve the four-way distinction between a non-allocatable spatial feature, a spatial region, an assignable resource and a capacity pool.

## 46.2 API surface additions

In addition to the endpoint families in Section 19, provide:

| Domain | Illustrative endpoints |
|---|---|
| Organization brand | `GET/PATCH /api/v1/organizations/{organizationId}/brand-profile` |
| Brand assets | `POST /api/v1/organizations/{organizationId}/brand-assets`, `GET/DELETE /api/v1/brand-assets/{assetId}` |
| Venue brand | `GET/PATCH /api/v1/venues/{venueId}/brand-profile` |
| Event brand override | `GET/PATCH /api/v1/events/{eventId}/brand-override` |
| Template revisions | `POST /api/v1/templates/{templateId}/revisions`, `POST /api/v1/templates/{templateId}/publish` |
| Source plan | `POST /api/v1/rooms/{roomId}/source-plan-artifacts`, `POST /api/v1/source-plans/{artifactId}/conversion-jobs` |
| Native spatial objects | `GET/POST /api/v1/floorplans/{revisionId}/spatial-objects`, `PATCH /api/v1/spatial-objects/{objectId}` |
| Floor-position resources | `GET/POST /api/v1/rooms/{roomId}/resources` with typed resource payloads |
| External prerequisites | `GET/POST /api/v1/events/{eventId}/prerequisites`, `PATCH /api/v1/prerequisites/{prerequisiteId}`, `POST /api/v1/prerequisites/{prerequisiteId}/record-completion` |

Every endpoint validates tenant, event and venue scope server-side. A brand profile or template cannot be fetched using an ID belonging to another tenant.

## 46.3 Security and privacy

- Tenant isolation applies to API queries, database relations, file storage, cache keys, WebSocket subscriptions, jobs and exports.
- Brand assets and templates are tenant-scoped; public asset delivery is allowed only for assets explicitly published for a guest-facing surface.
- Event/venue map projections remain audience-specific. A branded map is not automatically a public map.
- Guest-facing outputs expose only approved names/locators and approved map layers.
- Source workbooks may contain internal venue geometry; they are not public assets by default.
- Prerequisite records contain coordination metadata only; optional documents are separately classified and access-audited.
- Any organization-shared deployment must pass cross-tenant access tests before use with multiple organizations.

## 46.4 Revised implementation sequence

**Phase 0 - GHB discovery and reference-plan validation**

- Confirm GHB organization/tenant naming and brand assets.
- Inventory large, medium and small halls and the mosque/prayer-space relationship.
- Confirm physical hierarchy and ownership/management boundaries.
- Validate the supplied workbook's zone names, annotated capacities, position numbering, special areas, entrances and non-allocatable features with venue representatives.
- Decide which mosque areas require zone-only, row-only or numbered floor-position allocation.
- Agree whether CDI is a readiness gate for relevant event profiles and who records completion.

**Phase 1 - Multi-tenant/organization foundation and branding**

- Organization, user and permission model with tenant scope.
- Brand profiles, asset library, inheritance, revisions and basic branded app shell.
- Venue registry and versioned venue templates.
- Guest Registry and event participation model.

**Phase 2 - Spatial editor and allocation foundation**

- PDF/image/XLSX source artifact onboarding.
- Native room/zone/feature/row/resource model.
- Table, fixed-seat, capacity-zone and numbered floor-position modes.
- GHB large/medium/small hall templates and reviewed mosque template.
- Manual/hybrid allocation, constraints and solver preview.

**Phase 3 - Plans, documents, portal and staff operations**

- Branded invitations, guest cards, QR credentials and reports.
- Plan approval, publication, staff viewers and print outputs.
- Guest Portal with guest-safe map projection and venue-type-aware locator.
- Check-in, Cockpit panels, alerts and realtime updates.

**Phase 4 - Event-day coordination and resilience**

- Dynamic reflow and change notifications.
- External prerequisite coordination including CDI.
- Offline check-in, backups, restore rehearsal, monitoring and production hardening.

## 46.5 Revised production acceptance criteria

- A GHB organization profile can be configured with logo, palette, graphics, typography and templates.
- A venue/event can inherit the organization brand or override selected properties.
- Brand revisions used by invitations/cards/reports are recorded and reproducible.
- The four GHB reference spaces can be configured without hardcoded GHB-specific code.
- The mosque plan can represent red/green/blue zones, special areas, rows, numbered floor positions, pillars, minber, entrance, footwear area and passages as separate spatial objects.
- Repeated visible position numbers in different rows/zones do not collide because internal IDs and parent scopes are distinct.
- A guest can be allocated at zone, row or exact floor-position precision according to event policy.
- A tableless prayer-row layout can be allocated without creating chair records.
- The source Excel workbook remains available for comparison; native objects can be traced back to source cells/regions where feasible.
- Annotated capacities are not treated as approved until a venue representative confirms them.
- CDI can be represented as an external prerequisite, with request/schedule/completion tracking and an optional readiness gate, without implementing internal inspection activities.
- Tenant branding, files, templates, guest profiles and venue assets cannot leak between organizations.

## 46.6 Decisions confirmed for v1.2

These are the decisions now incorporated into the v1.2 baseline; operational details that require venue confirmation remain explicitly marked for Phase 0.

| Decision | v1.2 position |
|---|---|
| Branding | Organization brand is the default; venue and event overrides are supported; generated artifacts pin the resolved brand revision. |
| GHB | First reference organization/tenant and configuration dataset, not a hardcoded application branch. |
| Venue portfolio | Large, medium and small halls plus a separately modelled mosque/prayer space; physical hierarchy to be validated. |
| Mosque allocation | Coloured zones, special areas, rows/segments and optional numbered floor positions; zone-only allocation remains available. |
| Excel plan | Immutable source artifact, rendered reference background and assisted native tracing/validation; no blind automatic conversion. |
| CDI | Externally performed by police; application records coordination and completion status only. |
| Capacity | Workbook annotations are provisional until venue-approved. |
| Tenant deployment | Single-organization GHB installation is acceptable initially; schema and access model remain tenant-aware for future shared deployment. |

# Appendix H - GHB reference-plan interpretation notes

This appendix records what was read from the supplied workbook for product discovery, not a certified venue plan. The single worksheet shows an arrangement drawn with spreadsheet grid structure, borders, colour fills and labels. The visible colour zones and capacity annotations are red 74, green 150 and blue 140. It also labels mahfil lower/upper and left/right maksura areas with numerical annotations, and marks physical/navigation features such as minber, pillars, passage, entrance and footwear area. Numbered sequences repeat in separate rows/blocks. All terms, counts and geometry must be confirmed with the venue before the native template is approved.

The workbook is best treated as a **source drawing**. The production system should convert it into a layered native model with spatial regions, non-allocatable features, row/segment objects and optional numbered floor positions. It should not simply convert every spreadsheet cell or number into a seat.

# Appendix I - Branding inheritance example

The following illustrates how organization identity is inherited and selectively overridden for a venue or event.

```text
PLATFORM DEFAULT
  └── ORGANIZATION / TENANT: GHB
       ├── GHB logo, palette, typography and graphic library
       ├── GHB invitation / guest-card / report templates
       │
       ├── VENUE: LARGE HALL
       │    └── Optional venue-specific directions or mark
       ├── VENUE: MEDIUM HALL
       ├── VENUE: SMALL HALL
       └── VENUE / SPACE: MOSQUE
            └── Optional location-specific zone map theme

EVENT: Conference / Gala / Ceremony
  └── Optional event-specific campaign graphic or accent
      (inherits all unspecified properties)
```

The brand resolver produces a versioned brand snapshot used by every generated artifact. User-specific display preferences are separate from organization-facing brand identity.