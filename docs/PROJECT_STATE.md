# Project state

**Status:** design consolidation / repository bootstrap  
**Last updated:** 2026-11-10  
**Implementation status:** no application code or production database has been established in this repository.

## Product

Eventor is a reusable, self-hosted event operations and guest logistics platform. GHB Sarajevo is the first reference organization/venue, not the product's only intended deployment.

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

### Booking

- Public inquiry is a relatively simple intake, not a complex booking configuration exercise.
- Staff review an inquiry and may create a separate editable booking draft prepopulated from it.
- Drafts can change dates, spaces, resources, services and prices without changing the original inquiry.
- Offer/approval and explicit confirmation are distinct workflow stages.
- Staff can also create bookings without an inquiry.
- Preserve original requested values, offered/approved values and delivered/actual values separately.
- Rehearsals are separately schedulable reservations with their own date, time and duration.
- Historical records pin the form and catalogue revisions and retain the labels/answers shown at the time.

### RSVP and attendance

- Guest self-service response through a personalized, secure invitation link; email is the initial delivery channel.
- No guest account is required by default.
- Staff can record a response received in person, by telephone, email, letter or another configured channel.
- Record response source, timestamp, operator and optional notes.
- Guests may change a response until the configured deadline/rule allows it.
- RSVP response and actual attendance/check-in are separate states.
- Invitation and check-in credentials must be distinct, opaque and revocable.

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

## Design artifacts from prior work

The previous working package includes:
- Technical Blueprint v1.2 (Markdown, DOCX, PDF).
- Implementation Design v0.2 (Markdown, DOCX, PDF).
- Core and booking SQL schema drafts.
- OpenAPI v0.2 draft.
- Backlog and GHB form/spatial reference CSVs.
- GHB source workbook and visual reference assets.

These are prior design artifacts, not yet imported into this repository or verified against one another in this bootstrap commit. The next documentation task is to import and reconcile the authoritative Markdown/SQL/OpenAPI/backlog artifacts, retaining source version history and recording any corrections.

## Immediate next steps

1. Import and reconcile the blueprint and implementation design.
2. Validate SQL drafts and OpenAPI syntax/semantics; establish PostgreSQL migration conventions.
3. Resolve domain model and schema inconsistencies before implementation.
4. Agree MVP boundary and acceptance criteria.
5. Establish CI checks, branch protection and contribution/review workflow.
6. Begin implementation only after the design baseline is coherent.

## Open questions / validation gates

- Confirm GHB capacities, room/resource inventory, pricing and current rental policy.
- Validate actual approval/offer stages and who is authorized to approve/confirm.
- Confirm RSVP deadline, reminder schedule, response-change policy and guest contact-channel requirements.
- Confirm which guest and staff data fields are mandatory and who may view them.
- Review the venue spatial drawing with an authorized venue representative.
- Confirm public deployment hostname, reverse-proxy boundaries, email delivery and retention requirements.
