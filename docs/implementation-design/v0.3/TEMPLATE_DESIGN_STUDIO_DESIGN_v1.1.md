# Eventor — Template Design Studio technical specification v1.1

**Proposed successor review edition, not accepted yet.** 2026-11-27. Owner agreed direction of cumulative compatible requirements and least privilege. Existing v1.0 and approved Blueprint v1.3 remain in force pending review. No runtime, scope, accepted ADR or priority changes. Read with [Blueprint guide](../../blueprint/v1.3/README.md), [consistency reconciliation](../../blueprint/v1.3/DESIGN_CONSISTENCY_RECONCILIATION_v1.0.md), [engineering registers](../../blueprint/v1.3/ENGINEERING_REGISTERS_v1.0.md), [bidirectional source crosswalk](../../blueprint/v1.3/TDS_PAC_SOURCE_RECONCILIATION_v1.0.md).

## Part I — Reconciled requirements and implementation authority

The original detailed specification in Part II and integrated version plus subsequent approved clarifications in Part III constitute a source-complete proposed cumulative contract. All compatible approved requirements and detailed acceptance conditions remain mandatory; proposed choices, limits, routes, codes and examples retain their original qualifications. Apply the explicit dispositions below, accepted ADRs, DC-01–11 and current runtime compatibility. Historical status and integration instructions are provenance, not current orders. No silently dropped clause. Section-level reconciliation is not proof of every differing sentence; before declaring final semantic closure, adjudicate each remaining nonidentical clause against the existing line crosswalk, record equivalence/cumulative detail/explicit supersession or owner decision. Stop affected conflict, not unrelated work.

| Requirement | Original/integrated section | Consolidated disposition |
|---|---|---|
| 01–02 | 3–4.1 / 3 | Retain full permission, revision, review and workspace details; real preview separately authorized; published content immutable; separation of duty per policy. |
| 03–04 | 4.2–4.3 / 4 | Full rich text/block controls, office paste loss notices, explicit plain-text regenerate/compare, safe HTML subset; MIME test and image-blocked fallback. CID owns delivery. |
| 05–06 | 4.4–4.5 / 4 | Physical dimensions, imposition, decode tests, licensed assets and tenant hashes, dependency graph and sanitized imports; AGIS owns credential/printing authority. |
| 07 | 5 / 5 | Typed allowlist, purpose/field permissions, forbidden vs missing, non-live preview, approved projection; no arbitrary expressions. |
| 08–09 | 6 / 6 | Per-property event → authorized venue → org → platform; mandatory footer and approved locale fallback, exact resolved snapshot. |
| 10–11 | 7.1–7.3 / 7 | Structured versioned source and legacy text adapter; no chosen library. Retain manifest, exact permitted artifact/payload, renderer/asset versions and retention limits. |
| 12 | 7.4 / 7 | Render/publish never sends. Reuse queues and current domain/CID authority; DC-05 exact guaranteed idempotent replay only, not blind retry. |
| 13–14 | 8–9 / 8–9 | Full original model and route detail retained; current grouped APIs same intent, exact schema/code compatibility reviewed M0; no parallel notification lineage. |
| 15–16 | 10–11 / 10–11 | Cumulative security/accessibility and provisional original numerical inputs; no guaranteed SLO. Bound renderer, jobs, artifacts and licensing. |
| Milestones/AC | 12–15 / 12–15 | Both exact AC/evidence texts apply; #111 and existing roadmap. Later approved integrated clarifications remain effective. |

### Explicit resolutions
- TDS AC-24 and historical reissue wording: refresh/re-render current approved output, reprint exact artifact, physical handover and credential replacement are separate. Seat or brand change never automatically revokes a valid admission/invitation/portal capability. Revoked/expired token cannot be distributed from cached artifact. Replacement uses actual owning command, atomic revoke/issue and separate authorized distribution. Apply AGIS and CID and DC-03–06.
- Invitation without RSVP enabled may have no RSVP token. Typed QR/URL bindings only from appropriate owning domain; preview/test never issues live credentials or sends to real audience.
- TDS presentation does not own FRS schema/validation, RAI query/metrics, AGIS device/admission, CID audience/delivery, EPW task approval or HPG restricted data. Quick Start never weakens author/publish/send/data permissions. No silent fallback on missing required data/render failure.
- Original provisional targets: reference 4 vCPU/8 GiB/SSD; source ≤1 MiB, ≤2000 nodes, depth ≤24, component depth ≤8; raster ≤15 MiB/40 MP; warm preview p95 ≤3s, draft save p95 ≤500ms, debounce ~1s; initially ≤500 recipients/job with reviewed larger partitions, preview expiry 24h candidate. Validate M0 and record adjustments. Preserve original detailed conditions.
- Exact permitted historical output or canonical payload with manifest subject to retention/legal hold, not promise of byte-identical rerender after engine upgrade. Purged private values/tokens not recreated.

### Paired acceptance obligations

Both full original and integrated criterion conditions must be satisfied; no shorter paraphrase removes evidence. All 25 IDs paired; no test credited by this document. Original crosswalk retains line references. Source alias TDS-AC-n refers to original AC-n.

### TDS-AC-01

Original: AC-01 / TDS-01  /  Author creates draft, autosaves and reopens; simultaneous edit returns conflict; review/publish authorization and digest enforced; edit after approval invalidates it; historical content unchanged  /  DB/API/browser/concurrency

Integrated: AC-01 / TDS-01  /  Draft autosave/reopen; concurrent edit conflicts; authorized digest review/publish; edit invalidates approval; history unchanged  /  DB/API/browser/concurrency

### TDS-AC-02

Original: AC-02 / TDS-02  /  Library can search/filter/clone/retire with permission-gated navigation; provider cannot enumerate organizer templates or guest access  /  Browser/API/RLS

Integrated: AC-02 / TDS-02  /  Library filter/search/clone/retire and permission navigation; provider cannot enumerate organizer templates/guests  /  Browser/API/RLS

### TDS-AC-03

Original: AC-03 / TDS-03  /  Nontechnical staff builds formatted bilingual invitation with headings, text, list, image and dynamic fields; undo/paste/save/reopen; both HTML and text render; unsafe HTML rejected  /  Browser/unit/golden output

Integrated: AC-03 / TDS-03  /  Nontechnical bilingual formatted invitation with image/list/dynamic fields; undo/paste/reopen; text+HTML output; unsafe HTML rejected  /  Browser/unit/golden

### TDS-AC-04

Original: AC-04 / TDS-04  /  Build responsive email with columns, logo, RSVP button and footer using drag and keyboard; mobile stacks; MIME multipart contains expected text/HTML; image-disabled view still conveys core message  /  Browser/SMTP capture/client review

Integrated: AC-04 / TDS-04  /  Responsive column/logo/RSVP/footer by drag and keyboard, mobile stack, actual multipart text/HTML, useful with images disabled  /  Browser/SMTP capture/client

### TDS-AC-05

Original: AC-05 / TDS-05  /  Design A5 invitation with precise text/logo/shape positions; reopen unchanged; print dimensions and margins verified; overflow of long name blocks or follows approved rule  /  Browser/PDF inspection/print

Integrated: AC-05 / TDS-05  /  A5 precise text/logo/shape design reopens unchanged; margins/dimensions verified; long name overflow controlled  /  Browser/PDF/print

### TDS-AC-06

Original: AC-06 / TDS-05  /  Bulk personalized PDF and A4 multi-up layout: correct page count/order/cut margins, no clipped text, per-recipient output isolated; interrupted job resumes or reports failures safely  /  Integration/PDF/job recovery

Integrated: AC-06 / TDS-05  /  Bulk personalized PDF + A4 multi-up correct order/pages/cut/fit, recipient isolation and safe interrupted job  /  Integration/PDF/recovery

### TDS-AC-07

Original: AC-07 / TDS-05,07  /  Sample QR non-live; approved real RSVP/admission QR resolves only intended purpose; final-size decode succeeds; swapped/revoked credential rejected by corresponding domain  /  Unit/PDF/domain E2E (admission gated)

Integrated: AC-07 / TDS-05,07  /  Sample QR non-live; approved purpose-specific RSVP/admission QR decodes final size; swapped/revoked rejected by owning domain  /  Unit/PDF/domain E2E

### TDS-AC-08

Original: AC-08 / TDS-06  /  Clone/import approved template with component and assets; revision pinned; unsafe or unknown schema package rejected; component cycle/asset revoked blocks new render  /  API/DB/browser/security

Integrated: AC-08 / TDS-06  /  Clone/import with pinned components/assets; invalid package, dependency cycle and revoked asset rejected  /  API/DB/browser/security

### TDS-AC-09

Original: AC-09 / TDS-07  /  Required missing/forbidden variables fail; optional values hidden only by explicit policy; no arbitrary property traversal; wrong guest or another tenant's data never returned  /  Unit/API/RLS adversarial

Integrated: AC-09 / TDS-07  /  Missing/forbidden required values fail; optional rule explicit; no arbitrary traversal or wrong guest/tenant data  /  Unit/API/RLS

### TDS-AC-10

Original: AC-10 / TDS-07,12  /  Preview, save and publish never issue invitation, enqueue actual send, create admission credential or record attendance; real-recipient preview is authorized and non-live  /  DB/API/browser negative test

Integrated: AC-10 / TDS-07,12  /  Preview/save/publish never issue, enqueue real send, create admission or attendance; real preview authorized/non-live  /  DB/API/browser negative

### TDS-AC-11

Original: AC-11 / TDS-08  /  Organization, venue, event overrides resolved predictably and recorded; unauthorized cross-owner venue asset rejected; rebrand leaves old output unchanged  /  Unit/API/DB/golden

Integrated: AC-11 / TDS-08  /  Predictable recorded inheritance; unauthorized cross-owner asset denied; old outputs unchanged after rebrand  /  Unit/API/DB/golden

### TDS-AC-12

Original: AC-12 / TDS-09  /  Bosnian/English variants render correctly, diacritics and timezone preserved; locale choice/fallback follows ADR 0007; unavailable legal translation blocks send  /  Unit/browser/render E2E

Integrated: AC-12 / TDS-09  /  bs-BA/en diacritics/timezone/fallback per ADR 0007; missing legal translation blocks send  /  Unit/browser/render E2E

### TDS-AC-13

Original: AC-13 / TDS-10,11  /  Saved canonical source compiles consistently on server; manifest pins source/brand/asset/renderer versions; original retained output digest verifies after later rebrand/upgrade  /  Golden/integration/restore

Integrated: AC-13 / TDS-10,11  /  Server compilation and pinned manifest; retained original digest after rebrand/upgrade  /  Golden/integration/restore

### TDS-AC-14

Original: AC-14 / TDS-12  /  Test-send goes only to approved target with TEST marking/non-live links; actual issue/send requires existing permissions and explicit confirmed recipient digest  /  API/SMTP capture/browser

Integrated: AC-14 / TDS-12  /  Test only verified target, TEST marker, non-live links; real issuance requires domain permission and confirmed audience digest  /  API/SMTP/browser

### TDS-AC-15

Original: AC-15 / TDS-12  /  Duplicate render/send request idempotent; changed payload conflict; lease retry safe; uncertain provider delivery never blind resent; cancellation shows what was already sent  /  DB/concurrency/worker integration

Integrated: AC-15 / TDS-12  /  Idempotent duplicate, changed payload conflicts, lease retry safe, no blind uncertain resend; cancellation reports sent items  /  DB/concurrency/worker

### TDS-AC-16

Original: AC-16 / TDS-13  /  Populated migration preserves legacy template IDs, existing invitation/campaign FKs, queued text behavior and published historical revisions; fresh install matches constraints  /  PostgreSQL upgrade/regression

Integrated: AC-16 / TDS-13  /  Populated upgrade preserves legacy IDs/FKs/queued text/history; fresh install same constraints  /  PostgreSQL upgrade/regression

### TDS-AC-17

Original: AC-17 / TDS-14  /  OpenAPI paths, schemas and auth matrix match API; invalid source and stale revisions get safe problem response; artifact access requires current authorization  /  Contract/API/browser

Integrated: AC-17 / TDS-14  /  OpenAPI/auth matrix agrees with API, invalid/stale source safe errors, current download authority  /  Contract/API/browser

### TDS-AC-18

Original: AC-18 / TDS-15  /  Malicious paste, SVG, HTML, URL, CSS, remote image/font, path and template expressions cannot execute script, access private network or disclose data; renderer has no network/DB credentials  /  Security regression/host checks

Integrated: AC-18 / TDS-15  /  Adversarial paste/SVG/HTML/URL/CSS/fonts/images/path/expressions cannot execute/exfiltrate; renderer lacks network/DB creds  /  Security/host

### TDS-AC-19

Original: AC-19 / TDS-15  /  RLS and API checks deny cross-tenant revision/component/asset, grant expiry/revocation, unauthorized real preview/export/send; logs contain no raw tokens/recipient content  /  DB/API/log review

Integrated: AC-19 / TDS-15  /  Tenant/grant expiry/revocation deny revisions/assets/preview/export/send; logs contain no tokens/personal payload  /  DB/API/log review

### TDS-AC-20

Original: AC-20 / TDS-15  /  Keyboard-only template creation/reordering/resizing/publish; accessible labels, contrast, focus, image alternatives and semantic output; manual assistive-technology review  /  Browser/accessibility/manual

Integrated: AC-20 / TDS-15  /  Keyboard-only creation/reorder/resize/publish; labels/contrast/focus/alternatives/semantic output; assistive technology review  /  Browser/manual

### TDS-AC-21

Original: AC-21 / TDS-16  /  Bounded load and malformed/oversized inputs don't starve API; queue backpressure and recoverability observable; quotas enforced  /  Load/security/worker

Integrated: AC-21 / TDS-16  /  Oversized/malformed/load inputs bounded; API not starved; quotas/backpressure/recovery observable  /  Load/security/worker

### TDS-AC-22

Original: AC-22 / TDS-16  /  Native and Compose render same representative artifacts with same pinned versions/fonts; restore DB/assets/keys and verify digests; external SMTP accepted only with recorded real evidence  /  Installer/acceptance VM

Integrated: AC-22 / TDS-16  /  Native/Compose same representative outputs with pinned fonts/version; restore DB/assets/keys and verify digests; real external SMTP evidence only  /  Installer/acceptance VM

### TDS-AC-23

Original: AC-23 / TDS-07,12  /  Booking-only organization designs and sends permitted booking correspondence without guest/event modules; disabling optional capability rejects incompatible template  /  Integration/browser

Integrated: AC-23 / TDS-07,12  /  Booking-only template and permitted send without event/guest; disabled module rejects incompatible purpose  /  Integration/browser

### TDS-AC-24

Original: AC-24 / TDS-05,07  /  Guest-specific printable seating card uses only approved published assignment; changed plan doesn't silently re-render historical card; explicit reissue required  /  Domain E2E (#106 dependency)

Integrated: AC-24 / TDS-05,07  /  Seating card uses own approved allocation, later changes not silently applied; explicit reissue  /  Domain E2E (#106)

### TDS-AC-25

Original: AC-25 / #111 retained scope  /  Existing approved campaign flow, reminders/audience review, reports/displays and required guest/vendor form submissions pass their own criteria; Studio does not claim these merely by designing templates  /  Cross-module E2E

Integrated: AC-25 / retained #111  /  Existing campaign approval, reminders/audience review, reports/displays and required guest/vendor forms meet their own criteria  /  Cross-module E2E

# Part II — Full detailed original specification

Original TDS review source, 65004 bytes, SHA-256 7c7a460b5e9522fde6cc86ffebbf2617d318b826acc7b3c4d2a87e576f458316. Exact source begins after marker newline; original relative paths/status retained as historical source context. Use pinned manifest for navigation.

<!-- BEGIN EXACT ORIGINAL TDS bytes=65004 sha256=7c7a460b5e9522fde6cc86ffebbf2617d318b826acc7b3c4d2a87e576f458316 -->
# Eventor — Template Design Studio
## Technical specification v1.0

| Document control | Value |
|---|---|
| Status | Proposed for product-owner approval; not yet an accepted ADR or implementation claim |
| Date | 2026-11-27 |
| Repository | TeraflopsBH/eventor |
| Inspected main baseline | `e69d1c9cf86e8c4e55c4ee03f7c291830383bb2c` |
| Parent specifications | Technical Blueprint v1.2; Implementation Design v0.2; RSVP and Invitation Design v0.3; accepted ADRs |
| Tracking | Issue #111 (parent); Roadmap Phase 7, with dependencies in Phases 1, 2, 3–5 and 8–9 |
| Suggested repository location | `docs/implementation-design/v0.3/TEMPLATE_DESIGN_STUDIO_DESIGN_v1.0.md` |

Normative language: MUST/MUST NOT denotes a release requirement, SHOULD denotes a recommended default requiring documented justification for deviation, and MAY denotes an optional extension. All requirements below are proposed requirements until approved. No historical blueprint, ADR or API contract is silently superseded by this document.

## 1. Executive intent

Build a unified, self-hosted Template Design Studio that allows authorized Eventor operators to create professional, personalized, branded invitations and communications without writing code. It must support three distinct editing modes: a rich-text WYSIWYG editor for correspondence, a responsive drag-and-drop email designer, and a precision graphical designer for invitations, cards, passes and other fixed-layout print outputs. The modes share a template library, controlled variables, brand profiles, assets, versioning, review/publishing, preview/rendering and audit infrastructure. A template is not an invitation, admission credential, booking offer, recipient list or send command.

The central objective is not a subject field and an HTML textarea. A nontechnical organizer must be able to design a formal bilingual invitation with a logo, tailored salutation, formatted text, event details, image, RSVP button and optional print layout; preview synthetic and authorized recipient examples; publish a reviewed revision; and explicitly issue or send through the existing domain workflow. Booking-only tenants must be able to use correspondence templates without creating an event or Guest Registry.

### 1.1 Scope and outputs

| Purpose | Editing modes | Outputs | Authoritative owner/data source |
|---|---|---|---|
| Invitation and RSVP reminder | Rich text, visual email, graphical | Plain text, email HTML, single/print-pack PDF, optional PNG preview | Event organizer; invitation and RSVP-policy revisions |
| Booking correspondence, offer and cancellation notices | Rich text, visual email | Plain text and HTML; optional fixed-layout letter PDF | Booking owner; immutable commercial/policy projections |
| Guest admission pass, name badge, seating/place card | Graphical | PDF and printable sheets | Event organizer; distinct admission credential, published allocation where enabled |
| Welcome signage, directions and announcements | Graphical; reusable display content | PDF/image, sanitized display projection | Event/venue owner; published event/venue information |
| Staff/vendor requests and updates | Rich text, visual email | Plain text and HTML | Responsible party; narrowly scoped task projection |
| Certificates, official letters, operational summaries | Rich text, graphical | PDF; email where appropriate | Authorized owner; purpose-specific approved data |
| Reports and maps | Graphical cover/layout, controlled report components | PDF, existing CSV/XLSX exports unaffected | Report or published plan projection |

Purpose/output combinations are an allowlisted catalogue; a template cannot claim access to a new data category merely by changing its name. Multi-channel artifacts are linked through explicit template assignments, not arbitrary conversion. SMS, where enabled, uses bounded plain text only. Dynamic display scheduling, generalized form-builder workflows and report aggregation engines remain related #111 deliverables, not hidden prerequisites of the first invitation editor. No public guest directory, unrestricted report designer, arbitrary script, third-party SaaS dependency, automated mass sending, arbitrary HTML execution or pixel-perfect email-client parity is promised.

## 2. Reconciliation with current repository

| Source | Existing requirement/evidence | Studio response |
|---|---|---|
| Blueprint §11.1–11.3 | Template-driven invitations/cards/signage, brand, typography, colors, dimensions, QR placement, printed packs, revision reproducibility | Three authoring modes, physical layout model, approved assets and output snapshots |
| Blueprint §§12, 34 | Guest portal and scoped personal data | Purpose-built RSVP URL binding and safe guest projections; no general registry access |
| Blueprint §§10, 21, 26 | Approved plans, security/audit, reports | Published allocation only; export controls; immutable manifest |
| Blueprint §§41.1–41.7 | Organization → venue → event branding inheritance; template language variants, conditional blocks, field bindings, preview | Versioned brand resolution, typed catalogue and permissioned publication |
| Implementation Design v0.2, line 782 | Template designer, brand tokens, data fields, individual/batch preview, print sheets, generated-file history | Explicit acceptance scenarios across all three modes |
| RSVP/Invitation Design v0.3 | Published template and policy revisions, invitation issue/reissue/revoke, bulk preview | Existing invitation lifecycle remains authoritative; Studio supplies revision and render plan |
| ADR 0004/0005/0006 | Optional modules, separate invitation/RSVP/attendance, scoped collaboration | No dependency on guest module for booking; independent credential scopes; grant checks |
| ADR 0007 | `bs-BA` and `en`, locale precedence, authored translation revisions | Locale-specific variants and persisted rendering locale/timezone |
| ADR 0008; Architecture | Modular Vue frontend; Fastify/PostgreSQL modular monolith; asynchronous document rendering | Feature modules and isolated worker adapters within existing application/release topology |
| Gap analysis §2 and §3.4 | Rich/plain text authoring missing; campaign UI is review only | Reuse campaign infrastructure; add authoring and rendering |
| Issue #111 and Roadmap Phase 7 | Email CRUD, plain/HTML authoring, validation, preview/test-send, branding, reminders, forms, reports, displays | Expand explicitly to WYSIWYG, block email and canvas print; preserve all original obligations |

### 2.1 Actual integration baseline

`database/migrations/000013_event_changes_notifications.sql` already defines `eogp.notification_templates` (organization, code, purpose, status) and `eogp.notification_template_revisions` (locale, subject/body text, revision number, state); invitation revisions and event notification campaigns reference these revisions via tenant-composite foreign keys. Migration 000032 provides campaign review/confirmation and snapshot guards. `apps/api/src/notification-worker.ts` renders subject and text using the existing `renderNotificationTemplate` function. `apps/staff-web/src/features/campaigns/CampaignWorkspaceView.vue` presents template subject/body for review, not design. Existing invite issuance, RSVP and delivery controls must be retained. Existing booking form definitions are a separate domain, not a generic document template system.

No rich text, block email or graphical Studio runtime was identified in the inspected baseline. Existing schema and campaign review are not evidence of completed authoring. The conceptual `document_templates` in historical design is not authority to create an overlapping notification aggregate. Audit actual constraints, RLS, helper functions, published revision guards and invitation/booking send paths before migration; use forward-only compatible changes. Do not modify the historical v0.2 contract, rewrite migrations, or silently alter already queued messages.

## 3. Users, permissions and lifecycle

### 3.1 Proposed permissions (names subject to existing permission catalogue review)

| Permission | Capability | Important boundary |
|---|---|---|
| `template.read` | Browse allowed templates/revisions | No implied guest data access |
| `template.edit` | Create drafts, clone, edit localized content | Exact tenant and scope; no publish/send |
| `template.review` | Validate/review/return/reject | Cannot expand data access |
| `template.publish` | Publish reviewed revision; retire/supersede | Explicit command, current revision check |
| `template.preview.recipient` | Preview using real recipient | Also requires exact domain/field permissions and event scope |
| `template.test_send` | Deliver to verified test target | Synthetic bindings by default; separate rate limit and audit |
| `template.asset.manage` | Manage allowed assets and components | Quarantine, revision and scope rules |
| `brand.manage` / `brand.publish` | Draft or publish brand profiles | Separate brand approval; venue/event ownership checks |
| `template.export` | Export approved artifact or sanitized template package | Also requires output and data permissions |
| Existing invitation/campaign/booking permissions | Issue, approve audience, send, reissue, revoke | Never implied by template privileges |

Use existing membership, exact resource/event role and collaboration checks; do not invent parallel authorization. An organization template may be used by authorized events within that organization, but editing the organization template requires organization authority. Event managers cannot edit parent brands by default. Provider access to organizer guests is never implied by link ownership or brand/template use. Collaboration requires an explicit effective grant with purpose and resource scope; cross-tenant shared brand assets need an approved read-only copy/reference contract, not an inherited directory grant. Permission checks precede resource lookup where existing non-enumeration conventions require it. Use server-side authority and actor attribution in commands, RLS as defense in depth, and separate worker role privileges.

### 3.2 Lifecycle (TDS-01)

`draft → in_review → approved → published → superseded/retired`; review may return to draft or reject. A small tenant may configure single-operator author/publisher where authorized; optional separation of duties for regulated/high-risk purposes must be enforced when configured. Approval pins a digest of content, locale variants, schema version, dependency versions and validation result. Editing after review creates a new editable draft and invalidates approval. Published content and resolved dependencies are immutable; state transitions are audited. Retirement blocks new assignment/issuance under policy but never invalidates existing artifacts or changes previous deliveries. Revoking an unsafe asset may block new render/reissue with a visible explanation; previously distributed bytes cannot be recalled automatically.

Drafts support optimistic concurrency (`expectedVersion` or existing revision precondition convention), autosave with dirty/save status, local undo/redo, manual save, duplicate, restore draft from prior revision, compare and explicit discard. Do not use browser local storage for sensitive previews or credentials. Concurrent editors receive conflict UI with reload/compare/copy changes, never silent last-write-wins. Initial release does not require collaborative real-time text editing.

## 4. Studio UX and functional requirements

### 4.1 Template library and common workspace (TDS-02)

Staff navigation: Settings → Templates & Branding; event context → Communications → Templates; booking context → Correspondence. All routes and navigation are permission- and capability-aware. Library filters by purpose, scope, mode, locale completeness, state and updated time; search name/code; use a published starter, clone, create blank, archive/retire, view dependencies and usages. Detail shows owner, inherited/default selection, revision timeline, authors, review comments and validation. New templates select purpose, scope, primary locale, intended output and editing mode; allowed modes are purpose-driven. Workspace includes design canvas, properties, variable/asset/component libraries, preview, validation issues, revisions and save/publish actions. Keyboard navigation, visible focus, accessible labels, high contrast, zoom and non-drag alternatives are mandatory; no critical action depends on mouse gesture. Display locale independent from document locale.

### 4.2 Rich-text WYSIWYG (TDS-03)

- Create/edit formatted paragraphs, headings, bold/italic/underline/strike, font family/size from allowed catalogue, foreground/background colors, alignment, spacing, ordered/unordered lists, indentation, quotes, rules, links, images with alt text, bounded tables, merge fields and conditional sections.
- Toolbar and keyboard shortcuts, undo/redo, paste from common office applications with normalized safe formatting; strip unsupported/unsafe content and report significant losses. Provide plain-text view and editable plain-text alternative for email, with explicit regenerate/compare.
- Subject/preheader are separate single-line text fields, not rich HTML; reject CR/LF header injection. Preserve literal text, Bosnian diacritics, multiline names and Unicode. Preview long/empty values and conditional branches.
- Offer permission-controlled sanitized HTML import/edit for approved email contexts if needed to satisfy HTML authoring; show rejected constructs before save. Raw source is never served/executed directly. Initial HTML import supports a documented subset and must not silently discard or reinterpret unsafe content. Rich text source is structured JSON, not raw executable HTML.
- Render supported rich content to email-compatible HTML and plain text, or to a page-flow PDF for letter purposes. Unsupported transformations show a warning and require explicit clone/conversion; original source remains unchanged.

### 4.3 Visual responsive email designer (TDS-04)

- Drag/drop or accessible insert/move controls for sections, rows, 1–3 columns, heading, rich text, image, spacer, divider, button, logo, event summary, RSVP CTA, conditional block, footer and contact/help information. Select/edit properties, duplicate, reorder, delete, align and save reusable components.
- Responsive mobile stacking, controllable content width, padding, safe typography, link color, button contrast, preheader and plain-text alternative. Show desktop/mobile previews and warn on horizontal overflow; support email-safe layout tables where necessary, not arbitrary browser grid or CSS.
- Brand tokens and explicitly permitted local overrides; images selected from approved assets, bounded size, meaningful alt or marked decorative. Rendering uses inline CSS and conservative email markup; no JS, forms, iframes, remote CSS, tracking pixels or user-authored external image sources. Hosted images (if configured) are sanitized/public-asset-only and stable; otherwise use approved inline attachments or text fallback. No private asset URL or recipient token embedded in an image fetch.
- Test message produces actual MIME through the configured provider adapter and a controlled test recipient; render both `text/plain` and `text/html` multipart alternative as applicable. Real send is separate. Check representative clients, dark mode where practical and image-blocked fallback; acknowledge email-client rendering differences rather than claiming pixel parity.

### 4.4 Graphical invitation/card designer (TDS-05)

- Page sizes: A4, A5, common invitation/card/badge presets and bounded custom width/height in mm; portrait/landscape; front/back and bounded multipage where output supports it. Units in mm (or equivalent exact decimal physical coordinate representation) with explicit conversion to points for print. Define trim, bleed, safe margins and optional crop marks. Screen zoom must never alter saved coordinates.
- Canvas with rulers/grid/snap, select/multiselect, resize, rotate, position, arrange, align/distribute, layers, group/ungroup, lock/hide, duplicate and delete. Keyboard nudging and numeric property editing provide full alternatives. Background color/image, text box, vector shapes, lines, frame, logo, approved image, QR placeholder, dynamic field, approved map/report component. Crop/fit images non-destructively; preserve aspect ratio unless explicit stretch. No external SVG references or arbitrary SVG markup.
- Text boxes support rich formatting, wrapping, vertical/horizontal alignment, font sizing, line height and overflow policies (`error`, controlled shrink to minimum, approved wrap). Never silently clip required names, legal notices or QR. Variable measurement occurs on server with actual fonts. Design elements may be decorative or semantic; accessible reading order is editable for PDF where supported.
- QR element is typed as RSVP or admission and resolves only via the corresponding domain service. Enforce quiet zone, minimum module size/contrast, approved error correction configuration, no cropping/distortion/overlap, and decode test at final output dimensions. RSVP QR is not an admission pass. A design preview uses synthetic non-live QR and conspicuous sample label.
- Print preview, single personalized PDF, deterministic-order bulk pack, A4 imposition with configurable rows/columns/gutters/margins, optional cut/crop marks and verified fit. Output never invents seat assignments or displays inapplicable fields. Guest-facing map elements use approved sanitized projections, not operator map layers. Support optional PNG preview/export at bounded DPI; no claim of professional CMYK/PDF-X unless later validated.

### 4.5 Shared assets, starter templates and components (TDS-06)

Provide original neutral starter designs: formal invitation, compact email, RSVP reminder, booking letter, A5 print invitation, badge and pass (pass enabled only with admission domain). No hardcoded GHB branding or real guest data. Users may create reusable header/footer/CTA/layout components, duplicate templates, export/import sanitized template packages with versioned schema and dependency manifest; import creates a new draft with bindings remapped and revalidated. Components have immutable published revisions; templates pin each referenced revision. No cyclic component graph; bounded nesting and count. Assets are content-addressed within tenant boundaries, not global cross-tenant deduplication exposed to users. A published reference prevents destructive deletion until permitted by retention policy; quarantine/revocation still prevents future use. Asset picker shows owner, type, dimensions, alt text, license metadata and allowed usage. Font licensing/embedding rights are mandatory; do not ship or expose unlicensed fonts.

## 5. Dynamic data binding and personalization (TDS-07)

Use a versioned, typed, purpose-specific variable catalogue. Templates contain structured variable nodes with stable keys (notation `{{guest.display_name}}` is a UI representation, not arbitrary evaluation). Server defines resolver, type, nullability, sensitivity, allowed channel/purpose, required permissions, formatting options and example. Never expose object traversal, arbitrary JSON paths, JS, SQL, arbitrary expressions, template-engine function calls, reflection or secrets. Define contexts separately; no universal person object. Field access checks apply at preview, publication validation where possible, render and issuance. Forbidden/missing required values fail closed, not empty-substitution; optional values use explicit fallback or hide an entire optional block. Never turn a forbidden value into a presence oracle. Allowed conditions: bounded boolean combinations of allowlisted presence/enum equality predicates; no loops over arbitrary data. Lists only through separately approved bounded components.

| Example key | Type | Permitted context / note |
|---|---|---|
| `guest.display_name`, `guest.salutation`, `guest.reference` | text | Recipient's own approved event identity; not live registry dump |
| `event.title`, `event.start_at`, `event.timezone` | text/instant/zone | Published or explicitly approved effective schedule |
| `venue.name`, `venue.public_address`, `venue.arrival_instructions` | text | Public-safe venue projection |
| `rsvp.deadline`, `rsvp.url` | instant/capability URL | Invitation context only; approved effective policy |
| `admission.qr` | typed QR | Admission artifact only, separate authorized issuance |
| `allocation.public_label` | text | Recipient's own published assignment, optional |
| `booking.reference`, `booking.offer_total` | text/money | Booking/customer projection, pinned commercial revision |
| `booking.action_url` | capability URL | Purpose-bound offer/cancellation flow only |
| `brand.logo`, `brand.primary_color` | asset/color | Resolved brand snapshot |
| `task.public_due_at`, `task.public_summary` | instant/text | Explicit task/collaborator projection only |

Field names above are proposed, not promises that these exact existing API keys exist. No internal notes, restricted tags, CDI/security details, guest contact list, other recipients, raw capability database values, internal identifiers or unapproved custom fields in external templates. A staff-only report requires separate permission-filtered projection. Recipient context comes from server-owned ID and approved snapshot, not request-supplied values. Variables inserted into text are escaped for their output context; URL variables are typed link targets, not string concatenation; QR is an opaque payload from authorized domain, not arbitrary personal data. No field interpolation in HTML attributes/styles except typed, validated slots. UI shows required/optional and purpose restrictions, but server revalidates independent of editor.

Synthetic preview uses safe fixture values, no live tokens and watermark; real preview requires recipient permission, records access, creates no invitation/credential, and uses nonfunctional capability placeholders unless an already-issued authorized artifact is retrieved through its domain. Batch preview covers representative recipients, missing optional fields, locales, long names and no-seat cases; show counts and per-recipient diagnostics to authorized users only. Before real issuance confirm preview digest, selected template/brand, recipient set and policy/plan revisions; stale inputs require fresh review. Bind new invitation links only inside the existing authorized issuance transaction/job handoff; rendering must not create capability or attendance facts itself.

## 6. Branding and localization (TDS-08, TDS-09)

Brand profile revisions define approved logo variants, palette/semantic roles, fonts, spacing, image/style tokens, legal footer, contact/public web details and email/print defaults. Resolve property-by-property with precedence event override → authorized venue profile → organization profile → platform default; an absent override inherits; explicit removal is a typed allowed value, not ambiguous null. Event organizer and venue owner remain distinct; cross-organization venue brand use requires explicit published asset/brand reference and approval; no arbitrary access to venue data. Booking-only resolves applicable booking-owned or approved venue brand without event. Document explicit override rules for mandatory legal/footer text. Publish with preview, contrast/asset checks, revision digest and audit. Each render pins resolved brand values plus revision IDs/assets; later rebrand only affects new assignments/renders after explicit selection/review. Previously generated files are not automatically regenerated.

UI supports `bs-BA` and `en` immediately; BCP 47, UTF-8 and Unicode fonts. Stable template ID with locale-specific authored content variants, shared purpose/structure rules but translated layout may diverge explicitly. Staff locale does not set recipient locale. Follow ADR 0007: explicit validated interaction/communication choice → recipient preference collected for that purpose → owner default → deployment `en`, subject to available published variants and documented fallback. Show missing variant and resolved language before issuance; for required/legal/commercial text block if approved language unavailable unless operator explicitly selects an approved alternative consistent with policy. Do not infer language from identity or auto-translate. Persist resolved locale and event/booking IANA timezone; use locale-aware date/time/money/number formatting without changing domain values. Test `Č Ć Ž Š Đ` and lowercase, long text, timezone/DST, number/currency and language switching; design data supports future RTL (bidirectional text, direction properties and shaping), with full RTL quality a later validated language requirement.

## 7. Architecture and render contracts

```
Vue staff-web / Template Studio feature
    -> Fastify template, brand, asset, preview and publication commands
       -> PostgreSQL authoritative revisions / RLS / audit / outbox
       -> scoped domain projection resolvers (booking, event, invitation, allocation...)
       -> document/render job queue -> isolated render worker -> private artifact store
       -> existing invitation/campaign/booking issuance and notification worker
          -> SMTP/provider adapter (authorized delivery only)
```

Use existing modular monolith and explicit domain boundaries; no new mandatory external service or Redis. Keep authoring UI under `apps/staff-web/src/features/template-studio/` with modular rich text, block email, canvas, library, branding and preview components (exact layout subject to ADR 0008 conventions). API modules and shared contracts own schema validation, authorization, rendering inputs and compiler adapters; avoid growing the monolithic server route file with all implementation logic. Reuse PostgreSQL job/outbox patterns and existing notification worker; CPU-intensive PDF/image jobs use separately bounded process/worker role, even if deployed alongside same release. Renderer receives only sanitized immutable render input and approved assets; no DB credentials or general network access. API or a restricted orchestration worker performs authorized reads; renderer cannot issue/send/modify domain records. Queue and renderer isolation must work identically in native and Compose installation paths.

### 7.1 Canonical source and adapters (TDS-10)

One stable envelope per template output variant, with `schemaVersion`, purpose, mode, output kind, locale, content, referenced component/asset/brand revisions, variable catalogue version, validation manifest. Use discriminated, versioned JSON schemas: rich text document AST, responsive email block tree, graphical scene graph with physical bounds, stable node IDs and explicit z-order. Do not store HTML as executable canonical content; preserve existing legacy text revision as immutable format `legacy_text_v1`. Renderers compile each source to appropriate targets; no forced lossless round-trip across modes. HTML source editing/import passes through parser/allowlist to a supported email representation; reject ambiguous/unsupported constructs, retain original only in quarantined short-lived diagnostics if necessary. Never allow arbitrary CSS, scripts or remote includes. Maintain schema migrations as explicit forward transformations creating new drafts; published source remains renderable by compatible versioned adapters or retained artifacts.

Illustrative email envelope (IDs abbreviated solely for illustration; implementation uses existing validated UUID conventions):

```json
{
  "schemaVersion": 1, "mode": "email_blocks", "purpose": "invitation",
  "output": "email", "locale": "bs-BA", "subject": [
    {"type":"text","value":"Poziv na "},
    {"type":"variable","key":"event.title"}
  ],
  "body": {"type":"section","children":[
    {"type":"heading","content":[{"type":"variable","key":"event.title"}]},
    {"type":"button","label":"Potvrdite dolazak","target":{"variable":"rsvp.url"}}
  ]},
  "plainTextPolicy":"explicit_or_reviewed_generated",
  "catalogueVersion":1,"assetRevisionIds":[],"componentRevisionIds":[]
}
```

Illustrative graphical QR node: `{ "id":"n7", "type":"qr", "binding":"admission.qr", "xMm":12, "yMm":48, "widthMm":26, "heightMm":26, "rotationDeg":0 }`. Actual bounds and QR readability are validated; dimensions are examples, not a safe minimum. Use exact decimal or scaled integer coordinate representation; define rounding in adapter tests. Fixed layout should not rely on viewport pixels.

### 7.2 Technology choice gates

Do not lock an editor/renderer dependency based on a mockup. Perform bounded spikes: Vue-compatible structured rich-text library; constrained block editor with keyboard support; SVG/canvas scene editor with accessible parallel controls; HTML email compiler; PDF/vector renderer with font embedding and consistent text metrics. Prefer permissively licensed, maintained, self-hosted dependencies, no telemetry, no remote APIs, exportable neutral source, security patchability, offline install and manageable bundle size. Compare rich-text AST interoperability, paste sanitizer, email client fixture quality, SVG sanitization, PDF determinism, licensing and native/Compose behavior. Record chosen libraries and versions in a new ADR after spike; pin lockfiles and audit transitive dependencies. No requirement for commercial editor subscription. Headless browser rendering is allowed only with sandbox/process isolation, network disabled, bounded resource limits and controlled input; a vector PDF library may be preferable for precision layouts. Never disable the browser sandbox to simplify production deployment.

### 7.3 Rendering and artifact storage (TDS-11)

Server is authoritative for preview/final; local preview may be approximate. Compile sanitized source + typed resolved data + frozen brand/assets + locale/timezone + render adapter version. Validate content and dependencies, build channel-specific output, inspect layout/overflow, compute digest, persist private artifact manifest, then hand off to explicit issuance/send/export command. A render job does not send. Use synthetic sample by default. Use PDF with embedded licensed fonts, selectable/searchable text where feasible, vector shapes/QR, raster image resolution checks, correct physical page boxes and optional imposition. Validate actual printed output and QR decode. Accessibility requires readable structure/order and text alternatives; claim tagged PDF/PDF-UA only after verified support and acceptance. Do not promise byte-identical re-render across engine upgrades: retain original authorized artifact or exact canonical rendered payload where retention allows; record renderer version and digest; normalize volatile PDF metadata if byte-reproducibility is required. Any re-render under a different version is explicit and traceable.

Manifest: tenant/scope, template ID/revision/locale variant and digest, brand resolution/revision IDs, asset/component hashes, projection type and source revision references, resolved locale/timezone, renderer/schema/catalogue version, output type/dimensions/page count, hash/size, creator/job/correlation ID, status and timestamps, retention class, object reference. Store private blobs via deployment-local storage adapter (filesystem persistent volume or approved compatible private store), never public directory or guessed paths. Stream bounded downloads with authorization each request; no bearer artifact URLs in logs. Encrypt sensitive snapshots/artifacts at rest according to existing key and backup policy; never persist raw capability tokens in a new generic template/revision/manifest. If exact rendered content contains a live token, keep only within the existing tightly restricted encrypted issuance/delivery or artifact storage boundary with minimal retention; do not copy into searchable audit or preview cache. Historical snapshots can retain nonsecret inputs and token-free digests after purge. Redaction or deletion under retention/legal policy is auditable; reproducibility does not override data minimization.

### 7.4 Job reliability and delivery (TDS-12)

Use bounded asynchronous queues for bulk preview/render/pack and actual sends with separate job types, leases, retries/backoff, cancellation, progress counts, failure codes and dead-letter/operator recovery. Idempotency scoped to tenant/actor/action and canonical request fingerprint; identical retries return original result; changed payload conflicts. Distinguish render success, queued send, provider acceptance, delivery, bounce, suppressed and uncertain. Reuse current provider delivery/reconciliation semantics; never blind resend after ambiguous provider result. Before queueing actual send verify domain authority, approved revision and recipient/audience snapshot; worker rechecks applicable revocation/eligibility according to current domain rules. Explicit confirmation pins chosen recipient set and revision/locale decisions; audience changes invalidate review. Test sends use synthetic data, non-live links, verified test recipient (e.g. organization-approved sandbox address), visible TEST subject/banner, audit and rate limit. No test or preview updates RSVP/attendance or real campaign recipients. Use existing worker and SMTP provider abstractions, extend multipart HTML safely, retain text-only fallback and supported adapter capability matrix. Failure of new rendering must not mutate booking/event or send unintended legacy fallback.

## 8. Proposed data model and migration strategy (TDS-13)

These are logical entities, not approved DDL. Reconcile names and FK shapes against existing migrations before implementation. Every tenant-owned entity has `organization_id`, tenant-composite FKs, explicit resource ownership and RLS; do not use unvalidated polymorphic scope IDs. Use explicit venue/event/booking relationships or existing validated scope registry, with same-owner integrity and controlled cross-owner sharing. Use existing UUID and actor-attribution conventions. Business state mutations through restricted transactional commands; no broad runtime table writes.

| Aggregate / entity | Fields and invariants |
|---|---|
| Existing `notification_templates` | Stable ID, code/purpose/status, validated scope; preserve existing unique organization/code and tenant links. Extend or attach a common catalogue identity only after migration audit. |
| Existing `notification_template_revisions` | Keep historical locale, subject/body, state and IDs; attach versioned structured authoring payload/output metadata, review and dependency references. Maintain exact existing invitation/campaign FK semantics. Published payload immutable. |
| `template_definitions` / common catalogue (if necessary) | Stable logical identity, owner/scope, purpose, allowed modes, source locale, status; references existing notification identity rather than duplicating email revisions. A non-notification print template can exist independently. |
| `document_template_revisions` (new print-specific aggregate if needed) | Definition, revision, locale/variant, scene or rich document source, physical dimensions, renderer/catalogue versions, status, content hash, review receipt. No conflicting second email revision lineage. |
| `template_revision_dependencies` | Typed immutable references to component, asset, brand and approved projection contract versions. Tenant-aware uniqueness, no cycles. |
| `template_assignments` | Owner/scope, purpose/channel/locale, active published revision selection, revision precondition and history; optional event/venue overrides. Each issued artifact retains exact assignment/revision. |
| `template_review_decisions` | Revision digest, decision/reason, reviewer membership, grant if applicable, time; append-only. |
| `template_components` and revisions | Reusable constrained source fragments, mode compatibility, approved dependencies, draft/publish state, digest. |
| `brand_profiles` and revisions | Scope identity, property overrides, base/parent policy, asset refs, publication, revision hash; resolved snapshot separate from mutable defaults. |
| `design_assets` and revisions | Tenant, sanitized content digest, media type, dimensions, license, alt text, quarantine/approved/revoked state, private storage key; immutable approved binary. |
| `render_jobs` / `render_artifacts` | Purpose, tenant, actor, idempotency fingerprint, immutable render manifest, leased status, progress/failure/expiry, private object ref/digest. Sensitive content separately protected. |
| Existing invitations/campaigns/deliveries | Continue authoritative issuance, RSVP, recipient and delivery facts; extend with explicit output/revision/manifest references only where required. |

Constraints: valid purpose/mode/output combinations; published state requires approved digest and immutable dependency references; single active assignment per allowed scope/purpose/channel/locale unless explicitly configured; locale variants unique per logical revision; stale version/approval rejects mutation; prohibited references rejected before lookup leaks; asset deletion restricted while retained revisions reference it. Snapshot integrity tests cover linked dependencies, cross-tenant joins, actor membership and write privileges.

Migration sequence: (1) inventory existing notification purposes/variable semantics, locale rows, immutable guards, invitation issuance and delivery readers; (2) add backward-compatible version columns/sidecars and read adapters for legacy text; (3) add authoring commands, catalogue, asset/brand dependencies with explicit RLS/grants; (4) add structured format and multipart renderer opt-in; (5) migrate assignments/references only via audited reviewed commands; (6) introduce print aggregate and jobs; (7) prove fresh install and populated upgrade with queued, issued and historical legacy rows. Never force reinterpretation of legacy template strings as new AST or change existing queued render behavior. Keep old supported adapters until all retained revisions and deliveries are safely handled. Rollback plan must preserve old readers or explicitly block incompatible downgrades; migrations remain forward-only.

## 9. Proposed API surface (TDS-14)

All are conceptual operation families; align routes, problem codes, pagination, auth and schema naming with OpenAPI v0.3 and existing API conventions. Staff auth/CSRF/origin and permission gates required for state-changing commands. No generic public template API. Exact resource scope is resolved server-side. Body schemas reject unknown executable fields and enforce depth/count/size bounds. All state-changing commands include expected revision and idempotency where applicable; problem responses distinguish validation, stale revision, unavailable binding, dependency quarantine and render failure without exposing inaccessible resources.

| Method / illustrative path | Contract intent |
|---|---|
| GET `/templates?purpose=&scope=&locale=&state=&cursor=` | Permission-filtered catalogue, stable IDs and revision summaries |
| POST `/templates` | Create draft from blank/approved starter or clone; purpose and validated scope |
| GET `/templates/{id}/revisions/{revisionId}` | Authorized source, validation manifest and dependencies; no live recipient data |
| PATCH `/templates/{id}/drafts/{draftId}` | Structured source, `expectedVersion`; conflict response includes permitted current revision metadata |
| POST `/templates/{id}/drafts/{draftId}/validate` | Errors/warnings with node IDs, dependency checks, typed binding validation |
| POST `/templates/{id}/drafts/{draftId}/submit-review` | Freeze digest for review |
| POST `/templates/{id}/revisions/{revisionId}/review-decisions` | Approve/reject/return, reason and digest |
| POST `/templates/{id}/revisions/{revisionId}/publish` | Explicit current approval/digest; immutable revision receipt |
| POST `/templates/{id}/revisions/{revisionId}/retire` | Prevent new assignment under rules; preserve history |
| GET `/template-variable-catalogue?purpose=&output=&locale=` | Allowed typed definitions and synthetic samples, not a real data object |
| GET/POST/PATCH `/template-components/...` | Component draft, validate, publish, retire with same lifecycle |
| GET/POST/PATCH `/brand-profiles/...` | Scoped draft/revision lifecycle and resolved preview |
| POST `/design-assets/uploads` | Bounded staged upload; return quarantine status, not a public URL |
| GET `/design-assets/{id}/revisions/{revisionId}` | Authorized metadata/content stream with safe response headers |
| POST `/template-assignments` | Explicit published purpose/channel/locale selection with revision checks |
| POST `/template-previews` | Revision/draft digest + synthetic fixture or authorized recipient reference; output mode; no credential issuance |
| POST `/template-test-deliveries` | Test target ID, permitted content, locale; explicit synthetic-only send |
| POST `/document-render-jobs` | Authorized published source, approved projection, single/batch/print settings; no actual delivery |
| GET `/document-render-jobs/{id}` | Scoped progress, safe errors, paged item results |
| POST `/document-render-jobs/{id}/cancel` | Cancel pending work; no false promise to recall delivered artifacts |
| GET `/render-artifacts/{id}/content` | Private authorized download, restrictive caching, audit where sensitive |
| Existing invitation/campaign/booking operations | Select published assignment/revision and manifest under existing issue/send/approval rules; no Studio-owned send bypass |

Proposed response shapes: validation `{valid, errors:[{code,nodeId,path,messageKey}], warnings:[...], digest}`; preview `{id,status,resolvedLocale,sourceDigest,brandDigest,diagnostics,artifactId?}`; job `{id,status,total,processed,succeeded,failed,cancelled,createdAt,expiresAt}`. `202 Accepted` for queued jobs, `409` for stale/changed idempotency conflict, structured `422` or existing equivalent for invalid source. Error codes/localization align with existing problem schema. Recipient IDs never appear in public URLs or arbitrary user-provided render context. Downloads use restrictive content type/disposition and `Cache-Control: private, no-store` for sensitive artifacts. Maintain OpenAPI operation IDs, auth matrices, representative payload fixtures and versioned source schemas in CI.

## 10. Security, privacy and accessibility (TDS-15)

Threat model and mandatory controls:

| Threat | Required mitigation / validation |
|---|---|
| Stored/reflected XSS via paste, rich text, HTML or asset | Parse to safe AST; server allowlist; output-context escaping; sanitize markup; strict CSP; no raw HTML execution; isolated preview sandbox without scripts/same-origin privilege; `javascript:`, event attributes, active SVG, malformed HTML, CSS URL and entity obfuscation adversarial tests. |
| SSRF, data exfiltration via renderer/images/fonts | No arbitrary remote fetch; controlled asset resolver; network-denied worker; no file URI, loopback/metadata/private-network access, redirects, DNS rebinding or user-controlled paths. Validate URL schemes and external link policy without fetching. |
| Template injection | Structured variable nodes and restricted predicates; no general-purpose evaluation; allowlisted fields and context-aware escaping; bounded recursion. |
| Cross-tenant data or asset disclosure | Tenant-composite FKs/RLS, resource-specific permissions, no trust in supplied scope, no shared cache key without tenant and permission context, signed/authorized private access, non-enumerating errors. |
| Sensitive guest/booking data in preview, logs or export | Synthetic default; exact real-recipient grant; purpose-scoped projections; no raw tokens or personal payload in logs; controlled download, retention, encrypted storage and audited access. |
| Abuse of uploads | Size/dimension/pixel/page/count limits; detect type from bytes; quarantine; reject active/executable formats, decompression bombs, external refs; re-encode raster; sanitize/rasterize SVG; malware screening as deployment policy; no font upload without validation/licensing. |
| Accidental or unauthorized send | Preview/render/publish separate from issue/send; approved target/audience digest; existing domain permissions; idempotency; synthetic test links; rate limits and explicit confirmation; no delivery triggered by save or publish. |
| QR substitution, leakage or misclassification | Typed credential purposes; no real QR in samples; existing issue/revoke lifecycle; opaque payload; scan/decode tests; deny admission token in RSVP context and vice versa. |
| Resource exhaustion | JSON size/depth/node budgets, image bounds, queue quotas, CPU/memory/time limits, worker process isolation, cancellation, bounded batch size, backpressure and alerting. |
| Historical mutation | Published content/dependencies immutable; retain exact revision and output digest; brand changes require explicit new render/issue; auditable retention purge. |
| Supply chain and host compromise | Pinned dependencies/lockfiles, CI security audits, non-root worker, minimal privileges, sandbox, no mandatory network access or telemetry, documented update path. |

CSP/sandbox: preview must not run arbitrary user JS, access staff cookies/local storage or initiate network calls; sandbox HTML in isolated nonprivileged context with strict allowed assets. Email client is untrusted: emitted HTML must remain safe independent of sandbox. Do not allow CSS or image attributes that can leak recipient data via URLs. Public asset delivery, if enabled, exposes only explicitly designated non-personal logos/images and is independent of guest data; no external CDN mandatory. Public RSVP routes retain existing fragment/token rules; never append raw tokens to tracking parameters or third-party redirects. Validate user-provided links against an approved scheme/policy and prevent open redirect misuse. Render worker logs only safe job identifiers, counts and failure classes.

Accessibility: target WCAG 2.2 AA for staff Studio and guest-facing email/web outputs where applicable; use labelled controls, focus restoration, accessible reorder/resize alternatives, validation summary linked to node, keyboard-only workflows, meaningful link labels, image alternatives, readable contrast, semantic headings, responsive text and no color-only status. Allow intentional print aesthetics with documented warning/review, not silent accessibility regression. Include real keyboard and assistive-technology review; automated scans alone are insufficient. Test contrast in representative brand profiles and output text scaling. Email and print limitations documented rather than unsupported compliance claims.

## 11. Non-functional requirements and operations (TDS-16)

Initial proposed limits/SLOs are engineering starting points for a configurable self-hosted deployment, not measured commitments. Confirm on a declared reference host and adjust through performance/security review, not unbounded operator override. Suggested initial benchmark: 4 vCPU, 8 GiB RAM, SSD and local PostgreSQL; these are not final production sizing requirements.

| Item | Proposed initial policy / target |
|---|---|
| Structured template source | ≤ 1 MiB, ≤ 2,000 nodes, depth ≤ 24; component dependency depth ≤ 8 |
| Asset input | ≤ 15 MiB per raster upload and ≤ 40 megapixels decoded; stricter SVG/font budgets after spike |
| Preview | Synthetic email/print single page p95 ≤ 3 s under agreed warm reference workload; async if heavier |
| Draft save | p95 ≤ 500 ms for bounded document on local network; debounce ~1 s, expose unsaved status |
| Batch | Initially ≤ 500 recipients/job, configurable downward; larger operations partitioned with explicit review; stream outputs, avoid unbounded in-memory ZIP/PDF |
| Render execution | Bounded per-item timeout and CPU/memory, per-tenant and global concurrency; configurable conservative defaults derived from benchmark |
| Artifacts | Short-lived synthetic preview by default (suggest 24 h); sensitive actual output retention per approved organizational policy, with expiry/purge and legal-hold handling |
| Availability | API stays responsive when render workers saturated or unavailable; visible pending/error state; no silent loss |

Native/systemd and Docker Compose modes must ship the same fonts, renderer version and assets schema; non-root identities, sandbox, persistent private storage, predictable file ownership, health/readiness, worker lease recovery, safe upgrade/rollback and dependency verification. Back up PostgreSQL, artifact/assets store and encryption keys together under documented consistency and recovery procedure; rehearse restoration with manifest verification. Do not store actual guest data in Git or CI. Local mail capture and synthetic fixtures for tests; external SMTP acceptance deferred to integrated acceptance per roadmap. Metrics: render queue age/depth, duration, failure/timeout rates, worker saturation, storage usage, expired cleanup, send reconciliation; avoid guest identifiers as metric labels. Audit changes (draft save may be summarized, publish/review/assignment/real preview/export/send/test-send always attributable); correlate through request/job IDs.

## 12. Delivery sequence, dependencies and merge gates

Deliver vertical slices (migration, contract, API, UI, authorization, tests and docs together), not a single giant PR. Preserve issue #111's other requirements; each child can be independently verified, but parent remains open until all original and approved expanded criteria pass. Do not require final spatial editor/QR workflow to start basic email design; features requiring their projections stay gated.

| Milestone / proposed child issue | Deliverable | Dependencies and gate |
|---|---|---|
| TDS-M0: inventory and design decisions | Audit notification/issuance paths, choose source and render libraries, threat model, migration/ADR and performance spike | Existing main; review licence and sandbox; no schema fork |
| TDS-M1: library and rich-text email vertical | Catalogue, legacy-compatible revision model, rich text, variables, basic safe assets, preview, publish, test-send, multipart | M0, current booking/guest/invitation and auth worker; real synthetic invitation and booking-only tests |
| TDS-M2: branding and localization | Revisioned brand/assets/components, inheritance, locale variants, fallback/approval, pinned snapshots | M1; ownership/grant, historical rendering and diacritic tests |
| TDS-M3: block email editor | Responsive drag/drop + keyboard, safe HTML import/compile, accessible preview, text fallback | M1–M2; tested representative email clients, injection/SSRF suite |
| TDS-M4: graphical invitation and PDF | Precision scene, single and bulk PDF, imposition, embedded fonts, sample QR and printable invitation | M2; approved event/venue fields; native/Compose renderer parity and physical print checks |
| TDS-M5: integration and specialized outputs | Explicit template assignments in invitation/booking/campaign; approved batch preview, issue, delivery and reconciliation; admission, seating and map components when available | M1–M4; #105–107 for live allocation/QR; #110 for vendor fields; #104/#112 for event/booking projections; no invented domain facts |
| TDS-M6: full #111 closure | Reusable reports/document templates, signage/display integration, guest/vendor form workflow where required, reminders/audience controls, accessibility and ops | Relevant #107/#110 and remaining original issue criteria; #108 installer integration; Phase 9 final acceptance |

Priority recommendation: keep current #104/#112 foundation closure and #105–107 critical path intact. M0 and independent M1 can be taken as a bounded parallel/adjacent track if owner prioritizes invitations; do not shift all #111 ahead of spatial development without decision. M4 formal invitations can use safe event details without waiting for admission. QR passes and personalized seating maps wait for real domain commands. Templates are reusable with capabilities disabled; feature-gate unavailable output modes/variables, do not expose dead navigation.

Every PR: focused tests, full application checks, OpenAPI validation, PostgreSQL fresh/populated upgrade, RLS/concurrency/actor attribution tests where applicable, build/type-check, browser tests, dependency/security scan, exact-head CI and post-merge verification. No final acceptance claim from CI alone. No requirement to republish environment or use acceptance VM early.

## 13. Acceptance criteria and test traceability

The following criteria are normative upon approval; all applicable tests pass in exact-head CI or documented manual/operational evidence. Test fixtures are synthetic; no real guests, private plans, live capability tokens or credentials in repository.

| ID | Acceptance test and expected result | Primary verification |
|---|---|---|
| AC-01 / TDS-01 | Author creates draft, autosaves and reopens; simultaneous edit returns conflict; review/publish authorization and digest enforced; edit after approval invalidates it; historical content unchanged | DB/API/browser/concurrency |
| AC-02 / TDS-02 | Library can search/filter/clone/retire with permission-gated navigation; provider cannot enumerate organizer templates or guest access | Browser/API/RLS |
| AC-03 / TDS-03 | Nontechnical staff builds formatted bilingual invitation with headings, text, list, image and dynamic fields; undo/paste/save/reopen; both HTML and text render; unsafe HTML rejected | Browser/unit/golden output |
| AC-04 / TDS-04 | Build responsive email with columns, logo, RSVP button and footer using drag and keyboard; mobile stacks; MIME multipart contains expected text/HTML; image-disabled view still conveys core message | Browser/SMTP capture/client review |
| AC-05 / TDS-05 | Design A5 invitation with precise text/logo/shape positions; reopen unchanged; print dimensions and margins verified; overflow of long name blocks or follows approved rule | Browser/PDF inspection/print |
| AC-06 / TDS-05 | Bulk personalized PDF and A4 multi-up layout: correct page count/order/cut margins, no clipped text, per-recipient output isolated; interrupted job resumes or reports failures safely | Integration/PDF/job recovery |
| AC-07 / TDS-05,07 | Sample QR non-live; approved real RSVP/admission QR resolves only intended purpose; final-size decode succeeds; swapped/revoked credential rejected by corresponding domain | Unit/PDF/domain E2E (admission gated) |
| AC-08 / TDS-06 | Clone/import approved template with component and assets; revision pinned; unsafe or unknown schema package rejected; component cycle/asset revoked blocks new render | API/DB/browser/security |
| AC-09 / TDS-07 | Required missing/forbidden variables fail; optional values hidden only by explicit policy; no arbitrary property traversal; wrong guest or another tenant's data never returned | Unit/API/RLS adversarial |
| AC-10 / TDS-07,12 | Preview, save and publish never issue invitation, enqueue actual send, create admission credential or record attendance; real-recipient preview is authorized and non-live | DB/API/browser negative test |
| AC-11 / TDS-08 | Organization, venue, event overrides resolved predictably and recorded; unauthorized cross-owner venue asset rejected; rebrand leaves old output unchanged | Unit/API/DB/golden |
| AC-12 / TDS-09 | Bosnian/English variants render correctly, diacritics and timezone preserved; locale choice/fallback follows ADR 0007; unavailable legal translation blocks send | Unit/browser/render E2E |
| AC-13 / TDS-10,11 | Saved canonical source compiles consistently on server; manifest pins source/brand/asset/renderer versions; original retained output digest verifies after later rebrand/upgrade | Golden/integration/restore |
| AC-14 / TDS-12 | Test-send goes only to approved target with TEST marking/non-live links; actual issue/send requires existing permissions and explicit confirmed recipient digest | API/SMTP capture/browser |
| AC-15 / TDS-12 | Duplicate render/send request idempotent; changed payload conflict; lease retry safe; uncertain provider delivery never blind resent; cancellation shows what was already sent | DB/concurrency/worker integration |
| AC-16 / TDS-13 | Populated migration preserves legacy template IDs, existing invitation/campaign FKs, queued text behavior and published historical revisions; fresh install matches constraints | PostgreSQL upgrade/regression |
| AC-17 / TDS-14 | OpenAPI paths, schemas and auth matrix match API; invalid source and stale revisions get safe problem response; artifact access requires current authorization | Contract/API/browser |
| AC-18 / TDS-15 | Malicious paste, SVG, HTML, URL, CSS, remote image/font, path and template expressions cannot execute script, access private network or disclose data; renderer has no network/DB credentials | Security regression/host checks |
| AC-19 / TDS-15 | RLS and API checks deny cross-tenant revision/component/asset, grant expiry/revocation, unauthorized real preview/export/send; logs contain no raw tokens/recipient content | DB/API/log review |
| AC-20 / TDS-15 | Keyboard-only template creation/reordering/resizing/publish; accessible labels, contrast, focus, image alternatives and semantic output; manual assistive-technology review | Browser/accessibility/manual |
| AC-21 / TDS-16 | Bounded load and malformed/oversized inputs don't starve API; queue backpressure and recoverability observable; quotas enforced | Load/security/worker |
| AC-22 / TDS-16 | Native and Compose render same representative artifacts with same pinned versions/fonts; restore DB/assets/keys and verify digests; external SMTP accepted only with recorded real evidence | Installer/acceptance VM |
| AC-23 / TDS-07,12 | Booking-only organization designs and sends permitted booking correspondence without guest/event modules; disabling optional capability rejects incompatible template | Integration/browser |
| AC-24 / TDS-05,07 | Guest-specific printable seating card uses only approved published assignment; changed plan doesn't silently re-render historical card; explicit reissue required | Domain E2E (#106 dependency) |
| AC-25 / #111 retained scope | Existing approved campaign flow, reminders/audience review, reports/displays and required guest/vendor form submissions pass their own criteria; Studio does not claim these merely by designing templates | Cross-module E2E |

### 13.1 End-to-end owner acceptance scenario

1. Sign in as an organizer with edit permission; create a bilingual invitation from an approved starter using brand assets. Add salutation, event details, RSVP CTA, formatted copy, photo and footer. Save/reopen, translate and preview both languages with a long-name sample.
2. An authorized reviewer validates and publishes; an unauthorized editor cannot publish. Clone print variant, design A5 card with precise layout, produce one sample PDF and an A4 pack. Verify actual dimensions and scan synthetic QR only as a non-live sample.
3. Authorized issuer selects published email revision and reviewed recipients from event participation, sees locale/variable diagnostics and confirms explicit issue/send. Verify actual invitations link to correct invitation/RSVP policy, multipart delivery, no automatic attendance, existing revocation and resend behavior, and immutable historical manifest.
4. Update brand and create new revision; old email and PDF remain unchanged; new output uses newly selected brand only after review. Revoke grant and verify prior recipient previews/artifacts cannot be accessed through stale staff session.
5. Repeat booking-only example without organizer modules. Run negative tests, concurrent edits, queue recovery, native and Compose installation and final acceptance as scheduled in Phase 9.

## 14. Product-owner decisions and limitations

Recommended defaults are proposed, not prior approvals: three editing modes with explicit conversions; synthetic test send/preview by default; no arbitrary code or unrestricted HTML; configurable author/reviewer separation; neutral starters; property-level brand inheritance with explicit cross-owner sharing; private asset storage; retention, quotas and SLOs initially conservative. Confirm visual design priorities (formal invitation and email first versus full print studio), custom font policy and licensed assets, approved test recipients, publication authority, legal fallback policy, permitted public image hosting, retention and reference-host sizing. Choose editor/renderer libraries only after M0 evidence; no dependency has been selected or installed by this specification. Exact API route names and DDL require implementation reconciliation; current repo was inspected statically, not run locally. Accessibility/PDF and client compatibility claims require actual verification. GHB-specific brand assets and event policy facts must be supplied and approved separately; no assumptions about venue capacity or legal policy.

## 15. Repository integration and Issue #111 reconciliation

Recommended non-destructive change set after owner approval:

1. Add this document as `docs/implementation-design/v0.3/TEMPLATE_DESIGN_STUDIO_DESIGN_v1.0.md`; link from that directory's README and `docs/ARCHITECTURE.md`. Do not rewrite historical v0.2 design or Blueprint v1.2; add a successor addendum reference and incorporate approved changes in the next blueprint revision.
2. In `docs/ROADMAP.md`, Phase 7, expand existing email composer item into rich-text WYSIWYG, responsive block email and graphical invitation/card authoring; add common library, typed variables and safe render/print milestones. Cross-link Phases 3–5 for seating/QR and 8–9 for installers/acceptance. Keep Phase 7's original forms, reports, display, localization and bulk send requirements.
3. Update `docs/BLUEPRINT_TO_REPOSITORY_GAP_ANALYSIS_v1.0.md` through an explicit dated audit addendum or successor: distinguish missing authoring modes from existing delivery. Do not mark newly specified work implemented; update progress only on verified vertical slices.
4. Expand #111 via proposed issue addendum in companion file; create child issues only when owner approves decomposition. Link existing #104–#108, #110 and #112 as dependencies rather than duplicate their domain workflows. Keep #111 open until original and newly approved requirements complete.
5. Create ADR(s) after spike for canonical source models, rendering isolation, asset/brand retention and selected libraries. Update OpenAPI and migrations only as part of implementation PRs. Maintain CI and current integration discipline.

### Source links (repository baseline)

- [Technical Blueprint v1.2](https://github.com/TeraflopsBH/eventor/blob/e69d1c9cf86e8c4e55c4ee03f7c291830383bb2c/docs/blueprint/v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md), §§11, 12, 21, 26, 34, 41 and 46.
- [Implementation Design v0.2](https://github.com/TeraflopsBH/eventor/blob/e69d1c9cf86e8c4e55c4ee03f7c291830383bb2c/docs/implementation-design/v0.2/Event_Operations_Implementation_Design_v0.2.md#L782), historical template designer scope.
- [RSVP and Invitation Design v0.3](https://github.com/TeraflopsBH/eventor/blob/e69d1c9cf86e8c4e55c4ee03f7c291830383bb2c/docs/implementation-design/v0.3/RSVP_AND_INVITATION_DESIGN_v0.3.md).
- [Architecture](https://github.com/TeraflopsBH/eventor/blob/e69d1c9cf86e8c4e55c4ee03f7c291830383bb2c/docs/ARCHITECTURE.md); [ADR 0007](https://github.com/TeraflopsBH/eventor/blob/e69d1c9cf86e8c4e55c4ee03f7c291830383bb2c/docs/decisions/0007-internationalization.md); [accepted decisions directory](https://github.com/TeraflopsBH/eventor/tree/e69d1c9cf86e8c4e55c4ee03f7c291830383bb2c/docs/decisions).
- [Roadmap](https://github.com/TeraflopsBH/eventor/blob/e69d1c9cf86e8c4e55c4ee03f7c291830383bb2c/docs/ROADMAP.md); [gap analysis](https://github.com/TeraflopsBH/eventor/blob/e69d1c9cf86e8c4e55c4ee03f7c291830383bb2c/docs/BLUEPRINT_TO_REPOSITORY_GAP_ANALYSIS_v1.0.md); [Issue #111](https://github.com/TeraflopsBH/eventor/issues/111).
- [Migration 000013](https://github.com/TeraflopsBH/eventor/blob/e69d1c9cf86e8c4e55c4ee03f7c291830383bb2c/database/migrations/000013_event_changes_notifications.sql); [migration 000032](https://github.com/TeraflopsBH/eventor/blob/e69d1c9cf86e8c4e55c4ee03f7c291830383bb2c/database/migrations/000032_notification_campaign_review_confirmation.sql); [notification worker](https://github.com/TeraflopsBH/eventor/blob/e69d1c9cf86e8c4e55c4ee03f7c291830383bb2c/apps/api/src/notification-worker.ts); [campaign review UI](https://github.com/TeraflopsBH/eventor/blob/e69d1c9cf86e8c4e55c4ee03f7c291830383bb2c/apps/staff-web/src/features/campaigns/CampaignWorkspaceView.vue).

<!-- END EXACT ORIGINAL TDS -->

# Part III — Full integrated specification and later approved clarifications

Pinned TDS repository edition at fd993fb2d66b93fbe81ce99c5bfb50c9ec025542, 45403 bytes, SHA-256 785fe40e98d0b7b4d582e66d7d998ee18f30976d8a6e180c8f02cec4dff56bf9. Exact source begins after marker newline.

<!-- BEGIN EXACT INTEGRATED TDS bytes=45403 sha256=785fe40e98d0b7b4d582e66d7d998ee18f30976d8a6e180c8f02cec4dff56bf9 -->
# Eventor — Template Design Studio technical specification v1.0

**Status:** Product-owner-approved scope (2026-11-27); detailed engineering design and library choices remain subject to implementation review and ADRs.
**Baseline:** main at e69d1c9cf86e8c4e55c4ee03f7c291830383bb2c.
**Tracking:** [#111](https://github.com/TeraflopsBH/eventor/issues/111), Roadmap Phase 7.
**Document control:** Repository integration edition of the approved 2026-11-27 specification. Consolidates its requirements, TDS-01–16, M0–M6 and AC-01–25. No historical blueprint, accepted ADR, runtime contract or implementation status is silently superseded.

## 1. Purpose, scope and non-goals

Deliver a unified, reusable, self-hosted Template Design Studio, not merely a subject field and HTML textarea. Authorized nontechnical operators can design formal bilingual personalized invitations with branding, text, images, RSVP CTA and optional print layout; preview synthetic or authorized recipient examples; publish reviewed revisions; then explicitly issue/send through existing domain commands.

Three distinct authoring modes share the library, components, assets, branding, typed bindings, review/revisions, rendering, localization, permissions and audit. A template is not an invitation, booking offer, audience, credential, send command or attendance record.

| Purpose | Modes/outputs | Authoritative data |
|---|---|---|
| Invitations and RSVP reminders | Rich text, block email, graphical; text/HTML/PDF/print packs | Organizer; invitation and RSVP policy |
| Booking correspondence, offers and cancellations | Rich text and block email; optional letter PDF | Booking owner; pinned commercial/policy facts |
| Admission passes, badges, seating/place cards | Graphical; PDF/sheets | Organizer; distinct admission credential, published allocation when enabled |
| Welcome signage, wayfinding, announcements | Graphical; PDF/image, safe display content | Authorized event/venue owner; public projection |
| Staff/vendor correspondence | Rich text/block email | Explicitly responsible party; scoped task projection |
| Certificates, letters, summaries | Rich text/graphical; PDF/email as appropriate | Purpose-specific authorized projection |
| Reports/maps | Graphical layout and approved components | Report/published plan projection; existing CSV/XLSX exports unaffected |

Allowlist purpose/mode/output combinations. Booking-only deployments work without organizer event or guest modules; optional capabilities gate dependent variables and navigation. SMS uses bounded plain text if enabled. Multi-channel outputs are explicit linked assignments, not forced lossless conversion. Existing #111 requirements for forms, reminders, reports, displays and communication reconciliation remain separately required. No unrestricted report designer, public directory, arbitrary executable content, mandatory SaaS, automatic mass send or pixel-perfect email client parity.

## 2. Reconciliation and current implementation baseline

| Source | Alignment |
|---|---|
| [Blueprint v1.2](../../blueprint/v1.2/Event_Operations_Platform_Technical_Blueprint_v1.2.md) §§11.1–11.3 | Brand-aware templates, dimensions, typography, fields, QR placement, print packs and immutable outputs |
| Blueprint §§10,12,21,26,34,41,46 | Published allocation only; portal privacy, reports/audit, property-level inheritance, language variants, conditional blocks and preview |
| [Implementation Design v0.2](../v0.2/Event_Operations_Implementation_Design_v0.2.md) | Template designer, brand tokens/data fields, single/batch preview, print sheets, output history |
| [RSVP Design v0.3](RSVP_AND_INVITATION_DESIGN_v0.3.md) | Template and policy revisions; domain owns issue/reissue/revoke, RSVP, audience review |
| [ADR 0004](../../decisions/0004-optional-event-operations-scope.md), [0005](../../decisions/0005-separate-invitations-rsvp-attendance.md), [0006](../../decisions/0006-cross-organization-collaboration.md) | Optional modules, distinct credentials and attendance, explicit collaboration grants |
| [ADR 0007](../../decisions/0007-internationalization.md), [0008](../../decisions/0008-modular-staff-frontend.md) | BCP 47 locales, authored translations; modular staff UI |
| [Architecture](../../ARCHITECTURE.md) | API-first modular monolith; isolated asynchronous rendering |
| [Gap analysis](../../BLUEPRINT_TO_REPOSITORY_GAP_ANALYSIS_v1.0.md) / [Roadmap](../../ROADMAP.md) / [#111](https://github.com/TeraflopsBH/eventor/issues/111) | Explicit rich text, block email and precision canvas; preserve original communications, branding, forms/reports/displays and acceptance scope |

Migration [000013](../../../database/migrations/000013_event_changes_notifications.sql) defines notification_templates (owner/code/purpose/status) and notification_template_revisions (locale/subject/body/revision/state), referenced by invitation revisions and event notification campaigns through tenant-composite FKs. [000032](../../../database/migrations/000032_notification_campaign_review_confirmation.sql) adds campaign review/confirmation and snapshot guards. [Notification worker](../../../apps/api/src/notification-worker.ts) renders subject and text using renderNotificationTemplate. [Campaign workspace](../../../apps/staff-web/src/features/campaigns/CampaignWorkspaceView.vue) reviews those fields, not authors them. None of the three editors is delivered at the audit baseline. Existing form definitions are separate business aggregates.

Audit actual RLS, privileges, guards, queued message semantics, invitation/booking paths and shared contracts before implementation. Reuse and extend existing notification identities/revisions; historical conceptual document_templates is not authority for a competing email aggregate. Forward migrations only. Preserve existing IDs, queued behavior and history. Do not rewrite historical v0.2 SQL/API snapshots.

## 3. Authority, lifecycle and common workspace

### TDS-01 — Permissions and lifecycle

Proposed permission families (reconcile with existing catalogue): template.read, template.edit, template.review, template.publish, template.preview.recipient, template.test_send, template.asset.manage, brand.manage, brand.publish, template.export. No template privilege implies guest data, real issuance, campaign approval or delivery. Existing exact organization/event/booking management, field permissions, membership and grant checks remain authoritative. Parent organization templates/brands are editable only with parent authority. Provider access to organizer guests never follows from booking linkage or brand use. Cross-owner shared assets require explicit effective scoped grant and approved read-only reference/copy. Enforce non-enumeration, actor binding, RLS and separate least-privilege worker roles.

Lifecycle: draft → in_review → approved → published → superseded/retired; review may return/reject. Approval pins digest of source, variant, dependencies, schema/catalogue and validation. Edits invalidate approval; published payload immutable; retirement prevents new use per policy without rewriting history. Unsafe/revoked asset blocks new use, not automatic recall of distributed bytes. Authorized single-operator publishing may be configured; separation of duties required where policy specifies. Audit all transitions.

Draft autosave with status, manual save, undo/redo, duplicate/restore from prior version, compare and discard. Optimistic revision preconditions; conflicts offer compare/reload/copy changes, not last-write-wins. No sensitive preview/token browser-local persistence. Real-time collaborative editing not initially required.

### TDS-02 — Template library and common UX

Settings → Templates & Branding; event → Communications → Templates; booking → Correspondence, subject to permissions/capability. Search/filter by name, code, purpose, scope, mode, locale completeness, state and update time. Create blank/from approved starter, clone, retire, view dependencies, assignments and revision history. Show owner, author/reviewer, approval state, validation issues and inherited selection. Choose purpose, locale, output and mode. Workspace has canvas/content, properties, variable/asset/component pickers, preview, diagnostics and save/review/publish controls. Keyboard navigation, focus/zoom, labels and non-drag alternatives for every critical action. Staff UI locale independent of authored document locale.

## 4. Three authoring modes and shared components

### TDS-03 — Rich-text WYSIWYG

- Word-like formatted paragraphs/headings, bold/italic/underline/strike, allowed fonts/sizes/colors/highlight, alignment/spacing, lists/indent, quotes/rules, links, images with alt text, bounded tables, typed merge fields and conditional sections.
- Toolbar/keyboard shortcuts, undo/redo, normalized office paste with explicit notice of significant formatting loss. Separate single-line subject/preheader (reject CR/LF); editable plain-text alternative with explicit regenerate/compare. Unicode including Bosnian diacritics; test long and missing values.
- Safe HTML authoring/import in allowed contexts through parser and allowlist; rejected constructs reported before save. Structured canonical document, not executable raw HTML. No silent unsupported conversion. Render HTML/text for email or page-flow PDF for letters. Clone explicitly when changing mode.

### TDS-04 — Responsive drag-and-drop email

- Sections/rows, 1–3 columns, headings/rich text, logo/image, spacer/divider, CTA button, RSVP link, event summary, conditional blocks, footer/contact/help. Drag/drop or keyboard insert/move/reorder, properties, duplicate/delete and save reusable components.
- Responsive stacking, content width/padding, approved typography/link/button styling, desktop/mobile preview, overflow warnings, preheader and plain text. Conservative email markup/tables and inline CSS, no arbitrary JS, forms, iframe, remote CSS, tracking pixel or user-specified remote image fetch.
- Brand tokens/approved overrides; assets with alt/decorative flag, bounded size; explicitly public nonpersonal hosted assets if enabled or approved inline attachments/fallback. Never private URL or recipient token in asset fetch.
- Actual MIME test via provider adapter with text/plain and text/html multipart alternative; image-blocked content remains useful. Representative client compatibility and dark-mode checks where feasible; report limitations, no false pixel parity.

### TDS-05 — Graphical invitation and card designer

- A4/A5/common card and badge presets, bounded custom width/height, portrait/landscape, front/back and bounded multipage. Exact physical coordinates (mm/scaled integer/decimal), trim/bleed/safe margins/crop marks, deterministic conversion to PDF points; screen zoom does not change design.
- Rulers/grid/snap, select/multiselect, move/resize/rotate, align/distribute, layers/z-order, group/ungroup, lock/hide, duplicate/delete; numeric properties and keyboard nudging/alternatives. Text, vector shapes/lines/frame, logo, image/background, typed QR, variable, approved map/report components. Nondestructive crop/fit, aspect ratio default; no arbitrary active SVG.
- Text wrapping/alignment/line height, rich formatting, overflow error or controlled shrink/wrap with minimum readable size. Server measures actual fonts; never silently clip required name/legal text/QR. Semantic reading order and decorative elements explicit.
- QR typed RSVP or admission; use corresponding domain service. Preserve quiet zone, contrast, module readability, no stretch/crop/overlap; decode at final size. Synthetic marked non-live sample only in preview. RSVP never doubles as admission.
- Single personalized PDF, ordered bulk pack, A4 multi-up imposition, rows/columns/gutters/margins/cut marks, fit check, optional bounded DPI PNG. No invented seat label; safe published allocation/map projection only. Professional CMYK/PDF-X not promised without later validation.

### TDS-06 — Assets, reusable components and starters

Neutral synthetic starter designs (formal invitation, email, reminder, booking letter, A5 invitation, badge/pass where enabled), no real GHB brand or personal data. Reusable headers/footers/CTA/sections with immutable component revisions pinned by templates. No component cycles, bounded nesting/count. Clone and sanitized import/export versioned packages with dependency manifest, remap/revalidate bindings and permissions on import; imported source is new draft. Tenant-scoped content hashes; no cross-tenant existence oracle. Asset metadata (owner, type, dimensions, alt, license, allowed use); approved immutable binaries, quarantine and revoke. Prevent destructive deletion of retained dependencies; revoked asset blocks future use. Licensed fonts and embedding rights; no unlicensed assets or font files shipped.

## 5. TDS-07 — Typed personalization

Use a versioned purpose-specific variable catalogue, not arbitrary interpolation or generic person objects. Each definition supplies stable key, resolver, type/nullability, sensitivity, allowed purpose/channel, permission, formatting and synthetic sample. Variable nodes are structured; double-brace notation only presentation. No arbitrary traversal, SQL/JS, reflection, custom function or loops; bounded presence/enum predicates and approved bounded list components. Required missing or forbidden binding fails closed; optional permitted absence has explicit fallback/hide rule, not a forbidden-field presence oracle. Validate at preview/publish/render/issue. Escape by output context; typed validated URL/asset/QR slots, never string interpolation into arbitrary attributes/styles.

| Example proposed key | Permitted projection |
|---|---|
| guest.display_name, guest.salutation, guest.reference | Recipient's approved event identity |
| event.title, event.start_at, event.timezone | Published/approved schedule |
| venue.name, venue.public_address, venue.arrival_instructions | Public-safe venue projection |
| rsvp.deadline, rsvp.url | Invitation policy and capability |
| admission.qr | Separate admission credential |
| allocation.public_label | Own published assignment only |
| booking.reference, booking.offer_total, booking.action_url | Authorized customer/commercial snapshot and purpose-bound action |
| brand.logo, brand.primary_color | Resolved brand asset/color |
| task.public_due_at, task.public_summary | Explicit task/collaborator grant |

These names are illustrative, not existing API promises. No internal notes, restricted tags, private security/CDI data, other recipients, contact list, raw stored credentials, internal identifiers or arbitrary custom fields in external templates. Staff-only report requires distinct authorized projection. Resolve from server-owned record/snapshot, not user-submitted arbitrary data. Synthetic preview default and watermark; real preview exact recipient permission, audited, non-live placeholders; already issued artifacts through existing domain access only. Batch preview tests representative recipients/locales/missing fields/long names/no seat with scoped diagnostics. Real issue/send confirmation pins template/brand, recipient set, policy/plan and preview digest; stale inputs require review. Live link creation only through domain-authorized issue transaction/handoff. Rendering cannot create invitation/credential/attendance or change RSVP.

## 6. TDS-08/09 — Branding and localization

Revisioned logos, palette/semantic roles, typography, spacing/style, legal footer/contact and email/print defaults. Per-property precedence event → authorized venue → organization → platform default; absent inherits, explicit removal is a validated value; preserve mandatory footer policy. Venue and organizer owners distinct: explicit approved cross-owner asset/brand reference and authority, no implicit data access. Booking-only path has no event requirement. Validate preview/contrast/assets on publication and audit. Persist exact resolved values, revision IDs and assets in manifest; rebrand affects only explicitly reviewed new output, never previously issued materials.

Support bs-BA and en, BCP 47, UTF-8, licensed Unicode fonts, locale-specific authored variants under stable identity; no automatic translation. Follow ADR 0007: explicit validated interaction/communication choice → collected recipient preference → owner default → deployment en, subject to published variants and fallback policy. Show missing variant/actual language before issue; required legal/commercial text blocks send unless an approved alternative is explicitly selected consistently with policy. No inferred language from identity; staff preference not recipient locale. Persist locale and explicit IANA event/booking timezone. Locale-aware date/time/currency formatting without changing business facts. Test Č Ć Ž Š Đ and lowercase, long content, DST, numbers; accommodate future bidi/RTL shaping with full language acceptance later.

## 7. Architecture and rendering

Vue staff feature (proposed apps/staff-web/src/features/template-studio) → Fastify authorized template/brand/asset/preview/publish commands → PostgreSQL revisions/RLS/audit/outbox; scoped domain projection resolvers → render jobs → isolated render worker → private storage. Existing invitation/booking/campaign commands → existing notification worker/provider adapter for delivery only. Modular monolith, no mandatory cloud/Redis/microservice. Keep contracts explicit and avoid putting all logic in server route file. Reuse queue/outbox patterns; CPU-heavy PDF/image process separate bounded identity with no general DB credentials/network. Orchestration resolves authorized inputs; renderer receives only immutable sanitized source and approved assets and cannot mutate domain records.

### TDS-10 — Canonical source and adapters

Versioned discriminated JSON source: schemaVersion, purpose, mode, output, locale, source tree, component/asset/brand revision refs, catalogue version and validation digest. Rich document AST, responsive email block tree, fixed-layout scene graph with stable node IDs and z-order. Legacy text remains immutable legacy_text_v1 adapter, not silently parsed as new AST. HTML authoring/import normalized by parser/allowlist to supported representation; report rejected/ambiguous constructs; quarantine diagnostics only with short retention. No arbitrary CSS/scripts/includes. Explicit source transformations create drafts; published revisions remain compatible or retain original artifacts. No forced lossless round-trip between modes.

Illustrative typed email button node: {"type":"button","label":"Potvrdite dolazak","target":{"variable":"rsvp.url"}}. Example canvas QR: {"id":"n7","type":"qr","binding":"admission.qr","xMm":12,"yMm":48,"widthMm":26,"heightMm":26,"rotationDeg":0}; example size is not a validated minimum.

M0 evaluates maintained permissively licensed Vue-compatible rich text, constrained block editor, SVG/canvas scene editor, email compiler and PDF renderer (vector or sandboxed headless). Evaluate accessibility, paste sanitation, email client fixtures, source portability, fonts/metrics, determinism, licenses, security maintenance, offline native/Compose deployment, bundle size, no telemetry/remote dependency. Record decision and pinned versions in ADR; no library chosen now. Never disable sandbox for deployment convenience.

### TDS-11 — Server-authoritative rendering and private artifacts

Compile validated source + typed data + immutable brand/assets/components + locale/timezone + versioned adapter. Validate layout, overflow, dimensions/QR, digest and manifest before separate delivery/export/issue command. Browser preview may approximate, server is authoritative. PDF embeds licensed fonts, selectable text where feasible, vector shapes/QR, physical page boxes, DPI and imposition checks; print/decode evidence. Accessible reading order/alternatives; tagged PDF/PDF-UA only if actually verified. Do not promise byte-identical rerender after engine upgrades; preserve exact allowed artifact or canonical rendered payload and digest, engine/version. Explicit audited rerender; normalize volatile metadata if byte equivalence required.

Manifest: tenant/scope, template/revision/locale and source digest, brand resolution/revisions, component/asset hashes, projection type and source revisions, locale/timezone, renderer/schema/catalogue version, output/dimensions/page count/hash/size, actor/job/correlation/status/time/retention and private object ref. Private deployment-local filesystem/volume or approved store; authorize every download, bounded stream, restrictive caching. Sensitive content/snapshots encrypted per existing key policy. Never raw live token in template/revision/manifest, search index or logs; actual rendered bytes containing live token only existing restricted encrypted delivery/issuance or artifact boundary with minimum retention. Keep nonsecret digests/inputs after lawful purge; audit redaction/purge. Backup/restore must include DB, assets/artifacts and keys.

### TDS-12 — Queue and delivery

Separate bounded render/batch/print and actual delivery jobs, tenant/actor/action idempotency + canonical request fingerprint (identical retry same result; changed payload conflict), leases, backoff, cancellation, progress, safe failures and dead-letter recovery. No render/publish triggers send. Confirm actual audience/revision/locale and existing authority; worker rechecks applicable revocation/eligibility; changes invalidate review. Distinguish render, queue, provider acceptance, delivered/bounced/suppressed/uncertain. Existing reconciliation; no blind resend after ambiguous outcome. Test-send separate verified sandbox recipient, synthetic data, TEST marker and non-live link, audit/rate limit. Reuse SMTP/provider abstraction; multipart capability matrix and text fallback; render failure must not silently send legacy fallback or mutate booking/event. No test affects real recipients, RSVP or attendance.

## 8. TDS-13 — Logical schema and upgrade

Proposed logical aggregates, not DDL. Every tenant entity has organization_id, composite tenant FKs, explicit owner scope, RLS and restricted commands; no unchecked polymorphic IDs; existing actor/UUID conventions.

| Entity | Invariants |
|---|---|
| Existing notification_templates | Stable ID/code/purpose/status; extend validated scope or link common catalogue without duplicate email identity |
| Existing notification_template_revisions | Preserve historical locale/subject/body/revision/state and invitation/campaign FKs; add structured source/metadata/dependencies/review via compatible extension or sidecar |
| Common template definitions (if needed) | Stable owner/scope/purpose/mode/source locale; reference existing email lineage |
| Print document template revisions (if needed) | Independent non-email definition, locale/source/physical bounds, digest/approval and renderer version |
| Revision dependencies | Typed immutable component/asset/brand/contract refs, tenant integrity, no cycles |
| Template assignments | Explicit scope/purpose/channel/locale → active published revision; unique applicable selection, history/precondition |
| Review decisions | Append-only digest/reviewer/actor/grant/time/reason |
| Component revisions | Bounded reusable source, immutable publication/dependencies |
| Brand profiles/revisions | Approved property overrides, asset references, publication, resolved snapshot |
| Design assets/revisions | Quarantine/approved/revoked, digest/type/size/dimensions/license/alt, private object ref |
| Render jobs/artifacts | Tenant/actor/idempotency, manifest, lease/status/progress/error/expiry and protected blob |
| Existing invitation/campaign/delivery | Authoritative facts; add explicit revision/manifest references only as needed |

Validate mode/purpose/output, published digest/dependencies, unique locale variants, stale approvals, cross-tenant link denial, restricted deletion and write boundaries. Migration sequence: inventory existing purposes, variables, guards/readers; backward-compatible format metadata/read adapters; restricted authoring commands/library/brand/assets; opt-in structured multipart; explicit reviewed assignments; print aggregate/jobs. Test fresh DB and populated upgrades with issued, queued and historical legacy rows. Preserve old semantics and IDs. No forced AST interpretation. Forward-only upgrade; supported older readers or explicitly blocked incompatible downgrade, recovery documented.

## 9. TDS-14 — Illustrative API contract

Align exact routes/operation IDs/schema/error codes with OpenAPI v0.3 and existing conventions; no public generic template API. Staff auth/CSRF/origin, resource scope and operation/field permissions. Reject unknown executable fields, oversized trees; revision preconditions and idempotency as applicable. Safe non-enumerating problem responses.

| Family / proposed operations | Intent |
|---|---|
| GET/POST /templates | Scoped filtered paginated catalogue, create/clone draft |
| GET /templates/{id}/revisions/{revisionId}; PATCH /templates/{id}/drafts/{draftId} | Authorized source/dependencies, optimistic edit |
| POST draft validate/submit-review; revision review-decisions/publish/retire | Node diagnostics, digest review and immutable publication |
| GET /template-variable-catalogue | Typed permitted definitions and samples only |
| /template-components, /brand-profiles | Scoped draft/revision/preview/publish/retire |
| POST /design-assets/uploads; GET approved asset revision | Bounded quarantined upload; authorized metadata/content |
| POST /template-assignments | Published purpose/channel/locale selection and preconditions |
| POST /template-previews | Digest + synthetic fixture or authorized recipient; no issuance |
| POST /template-test-deliveries | Approved target ID, synthetic-only test, locale |
| POST/GET /document-render-jobs; POST job cancel | Scoped single/batch/print render/progress/results/cancel, no delivery |
| GET /render-artifacts/{id}/content | Current authorization, private no-store, controlled content disposition |
| Existing domain issue/approve/send operations | Choose approved assignment/revision/manifest; no bypass |

Validation response includes valid/errors/warnings (code,nodeId,path,messageKey), digest. Preview receipt includes id/status/resolvedLocale/sourceDigest/brandDigest/diagnostics/artifactId if appropriate. Job receipt includes id/status/total/processed/succeeded/failed/cancelled/createdAt/expiresAt. 202 async, 409 conflict, 422 or existing validation equivalent. No recipient ID in public URL or arbitrary context object. Maintain OpenAPI tests/auth matrix/representative fixtures.

## 10. TDS-15 — Security, privacy and accessibility

| Threat | Mandatory mitigation |
|---|---|
| XSS via paste/HTML/SVG/CSS/URL | Server allowlist AST, context escaping, reject active/event/script/javascript/obfuscated constructs, strict CSP, isolated preview without scripts/same-origin privileges |
| SSRF/exfiltration | Network-denied render worker, controlled asset resolver, no arbitrary remote fonts/images/URLs/files/paths/redirects/DNS/private-network requests; validate link scheme/policy without fetch |
| Template injection | Structured typed bindings and bounded predicates, no evaluation or arbitrary property access |
| Tenant disclosure | Composite FK/RLS and exact scope/field/operation checks, non-enumerating errors, tenant + permission cache context, current download authorization |
| Guest data/token leaks | Synthetic default, audited authorized real preview, scoped data, encrypted private outputs/minimized retention, no personal payload/raw tokens in logs/cache/metrics |
| Upload abuse | Type from bytes, quarantine, size/pixels/pages/depth limits, raster reencode, safe SVG sanitize/rasterize, reject active/executable/external refs/decompression bombs; font validation/license, malware screening per policy |
| Accidental/unauthorized send | Separate preview/render/publish vs issue/send, explicit recipient digest/confirmation, existing permissions, test marker/non-live links, rate limits and idempotency |
| QR misuse | Typed purpose, separate credentials, revocation/issue domain, final decode test, reject swapped/revoked credential |
| Resource exhaustion | Node/depth/asset budgets, bounded queues/time/CPU/memory, non-root worker, backpressure/cancel, monitoring |
| Historical mutation | Immutable revision/dependencies, exact hashes, explicit reissue, auditable purge |
| Supply chain | Pinned reviewed dependencies/security scans, process sandbox, no mandatory telemetry/network, documented updates |

Preview cannot access staff cookies/storage or arbitrary network. Email output safe independent of sandbox; no private data interpolation into image/CSS URLs. Public asset service (if enabled) only explicitly designated nonpersonal material. Preserve existing fragment-based public token handling; no raw tracking parameters/third-party redirect or open redirect. Renderer logs safe identifiers/counts/failure codes only.

Target WCAG 2.2 AA staff and guest web/email where applicable. Keyboard-only edit/reorder/resize/publish, semantic labels/headings, focus restoration, meaningful links, alternatives, contrast, visible diagnostics, responsive scaling, no color-only status. Print warnings/review where visual choices affect accessibility. Manual assistive technology and keyboard verification, not automated scans alone; disclose email/PDF support limitations.

## 11. TDS-16 — Operations, limits and proposed service targets

Initial suggested benchmark (not measured or approved production sizing): 4 vCPU, 8 GiB RAM, SSD, local DB. Suggested source ≤1 MiB/2,000 nodes/depth 24, component depth 8; raster ≤15 MiB/40 megapixels, stricter SVG/font spike limits. Warm bounded single preview p95 ≤3s, draft save p95 ≤500ms local network with debounced ~1s autosave. Initially ≤500 recipients/job, partition larger reviewed batches; stream outputs, bound CPU/memory/time and per-tenant/global concurrency. Preview expiry suggested 24h; sensitive output retention/legal hold/purge per approved policy. These are M0 benchmark inputs, not established SLOs. API responsive when renderer saturated/unavailable; visible queue/backpressure/errors.

Native/systemd and Compose same release fonts/renderer, non-root sandbox, persistent private storage, ownership, health/readiness, lease recovery, upgrade/recovery. DB/assets/artifact/key-consistent backup and restore digest tests. Local email capture, synthetic CI; external SMTP/host acceptance only with actual recorded evidence during planned Phase 9. Metrics queue age/depth, duration/failure/timeout/saturation/storage/cleanup/send reconciliation, no guest labels. Audited review/publish/assignment/real preview/export/send/test; draft save may summarize. Correlation IDs.

## 12. Work packages and dependency-safe delivery

| Package | Scope | Dependency/gate |
|---|---|---|
| TDS-M0 | Audit existing notification/issuance/schema, threat model, editor/render/asset spikes, ADR, migration and benchmarks | Current main; no schema fork |
| TDS-M1 | Library, rich-text email, typed variables, basic safe assets, preview/publish/test-send, legacy-compatible multipart | M0; booking/invitation/auth/worker; booking-only and synthetic integration |
| TDS-M2 | Brand inheritance, assets/components, locale variants and pinned snapshots | M1; ownership/grant, history, diacritic tests |
| TDS-M3 | Responsive block designer with keyboard controls, safe HTML, text fallback | M1–2; email client and injection tests |
| TDS-M4 | Graphical invitation/cards, precise PDF, embedded fonts, imposition, sample QR | M2; approved event/venue projection, physical print and native/Compose parity |
| TDS-M5 | Domain assignment/issue/send/batch/reconciliation; seating, admission, map and vendor components when supported | M1–4; #104/#112, #105–107 and #110 as applicable |
| TDS-M6 | Complete original #111 forms, reports, signage/display, reminders, audience review, accessibility and ops | Remaining domain dependencies, #108 installer integration, Phase 9 acceptance |

**Codex continuity:** this is approved Phase 7 backlog clarification, not a new immediate implementation instruction. Continue existing #104/#112 foundation closure then #105–107 critical path; do not switch tasks, recreate existing aggregates, change branch priorities or start Studio coding merely because this document lands. M0/M1 may proceed independently of seating/admission when explicitly scheduled. Formal print invitation uses approved basic event fields; actual admission/seating/map variables wait for owning commands. Do not duplicate #104–108/#110/#112. Keep #111 open through all original and expanded acceptance criteria.

Implementation PRs are reviewable vertical slices with migration, API/shared contract, frontend, authorization, audit and tests. Exact-head CI and post-merge verification; populated upgrade, RLS/concurrency/actor checks, browser, build/typecheck and dependency/security evidence. No environment republish or early acceptance VM. Do not claim production readiness from CI alone.

## 13. Acceptance criteria and traceability

All applicable criteria must pass with synthetic data and exact-head CI or recorded manual/operational evidence; never commit live credentials, personal data or sensitive plans.

| ID | Acceptance scenario | Verification |
|---|---|---|
| AC-01 / TDS-01 | Draft autosave/reopen; concurrent edit conflicts; authorized digest review/publish; edit invalidates approval; history unchanged | DB/API/browser/concurrency |
| AC-02 / TDS-02 | Library filter/search/clone/retire and permission navigation; provider cannot enumerate organizer templates/guests | Browser/API/RLS |
| AC-03 / TDS-03 | Nontechnical bilingual formatted invitation with image/list/dynamic fields; undo/paste/reopen; text+HTML output; unsafe HTML rejected | Browser/unit/golden |
| AC-04 / TDS-04 | Responsive column/logo/RSVP/footer by drag and keyboard, mobile stack, actual multipart text/HTML, useful with images disabled | Browser/SMTP capture/client |
| AC-05 / TDS-05 | A5 precise text/logo/shape design reopens unchanged; margins/dimensions verified; long name overflow controlled | Browser/PDF/print |
| AC-06 / TDS-05 | Bulk personalized PDF + A4 multi-up correct order/pages/cut/fit, recipient isolation and safe interrupted job | Integration/PDF/recovery |
| AC-07 / TDS-05,07 | Sample QR non-live; approved purpose-specific RSVP/admission QR decodes final size; swapped/revoked rejected by owning domain | Unit/PDF/domain E2E |
| AC-08 / TDS-06 | Clone/import with pinned components/assets; invalid package, dependency cycle and revoked asset rejected | API/DB/browser/security |
| AC-09 / TDS-07 | Missing/forbidden required values fail; optional rule explicit; no arbitrary traversal or wrong guest/tenant data | Unit/API/RLS |
| AC-10 / TDS-07,12 | Preview/save/publish never issue, enqueue real send, create admission or attendance; real preview authorized/non-live | DB/API/browser negative |
| AC-11 / TDS-08 | Predictable recorded inheritance; unauthorized cross-owner asset denied; old outputs unchanged after rebrand | Unit/API/DB/golden |
| AC-12 / TDS-09 | bs-BA/en diacritics/timezone/fallback per ADR 0007; missing legal translation blocks send | Unit/browser/render E2E |
| AC-13 / TDS-10,11 | Server compilation and pinned manifest; retained original digest after rebrand/upgrade | Golden/integration/restore |
| AC-14 / TDS-12 | Test only verified target, TEST marker, non-live links; real issuance requires domain permission and confirmed audience digest | API/SMTP/browser |
| AC-15 / TDS-12 | Idempotent duplicate, changed payload conflicts, lease retry safe, no blind uncertain resend; cancellation reports sent items | DB/concurrency/worker |
| AC-16 / TDS-13 | Populated upgrade preserves legacy IDs/FKs/queued text/history; fresh install same constraints | PostgreSQL upgrade/regression |
| AC-17 / TDS-14 | OpenAPI/auth matrix agrees with API, invalid/stale source safe errors, current download authority | Contract/API/browser |
| AC-18 / TDS-15 | Adversarial paste/SVG/HTML/URL/CSS/fonts/images/path/expressions cannot execute/exfiltrate; renderer lacks network/DB creds | Security/host |
| AC-19 / TDS-15 | Tenant/grant expiry/revocation deny revisions/assets/preview/export/send; logs contain no tokens/personal payload | DB/API/log review |
| AC-20 / TDS-15 | Keyboard-only creation/reorder/resize/publish; labels/contrast/focus/alternatives/semantic output; assistive technology review | Browser/manual |
| AC-21 / TDS-16 | Oversized/malformed/load inputs bounded; API not starved; quotas/backpressure/recovery observable | Load/security/worker |
| AC-22 / TDS-16 | Native/Compose same representative outputs with pinned fonts/version; restore DB/assets/keys and verify digests; real external SMTP evidence only | Installer/acceptance VM |
| AC-23 / TDS-07,12 | Booking-only template and permitted send without event/guest; disabled module rejects incompatible purpose | Integration/browser |
| AC-24 / TDS-05,07 | Seating card uses own approved allocation, later changes not silently applied; explicit reissue | Domain E2E (#106) |
| AC-25 / retained #111 | Existing campaign approval, reminders/audience review, reports/displays and required guest/vendor forms meet their own criteria | Cross-module E2E |

Owner E2E: author makes bilingual branded invitation, save/reopen and preview long-name sample; unauthorized publisher denied, reviewer publishes; clone A5 print layout and verify single/multi-up PDF and synthetic QR. Authorized issuer reviews real event recipient set and locale/field diagnostics then explicitly issues/sends through existing lifecycle; verify multipart/RSVP link/policy/revocation/resend, no attendance. Rebrand/new revision leaves historic bytes/digest unchanged; revoke grant and verify stale staff access denied. Repeat booking-only, negative/concurrent/queue recovery and final dual-mode acceptance per roadmap.

## 14. Open design decisions and limits

Approved product scope does not approve a specific dependency, DDL, endpoint name, retention, quota or performance SLO. M0 selects libraries/renderers and ADRs, validates reference host, custom font licensing, legal language policy, publication authority, test recipients, public asset policy and retention. GHB-specific assets/capacity/legal and operational facts require owner evidence. No new dependencies installed, runtime tests executed or feature completion claimed by this addendum. Accessibility, PDF/client compatibility and external deployment require actual evidence.

## 15. Integration and issue reconciliation

This addendum extends Blueprint v1.2 without rewriting its historical snapshot. Preserve v0.2 contracts and existing accepted decisions. Link in design index, architecture and Phase 7; dated gap analysis clarification distinguishes existing delivery from missing authoring. Parent #111 remains open with original obligations and these added criteria. M0–M6 are a work-package checklist; child issue creation and actual scheduling should occur when Codex reaches the relevant track, avoiding duplicate work and tracker churn. Do not alter PROJECT_STATE.md or current coding handoff solely for this specification. Source references in §2 describe the inspected baseline, not new runtime implementation.

## Approved OAC / UX integration clarification — 2026-11-27

[OAC v1.0](ORGANIZATION_ADMINISTRATION_CENTER_DESIGN_v1.0.md) and [UX v1.0](EVENTOR_USER_EXPERIENCE_AND_NAVIGATION_v1.0.md) place the tenant-scoped Design Studio, branding and communications within the organization workspace; the event context opens the same shared service for authorized event-specific design. PAC manages platform defaults; OAC manages organization defaults and allowed overrides; venue/event scope and historical pins remain as defined in TDS. Reuse exactly one brand/asset/template revision service and existing notification delivery; publishing a design never issues or sends. Follow common accessible navigation, preview/review, loading/error and scoped context patterns. [OLA v1.0](ORGANIZATION_LIFECYCLE_ACCEPTANCE_SCENARIOS_v1.0.md) integrates the branding and communication journey but does not waive AC-01–25 or remaining #111 obligations. Owner approved the three v1.0 scopes for documentation integration on 2026-11-27. The three reviewed source files are preserved verbatim, including their historical proposed-status text; this approval record governs their integration status, not approval of exact engineering decisions or immediate implementation. Existing accepted ADRs, historical Blueprint v1.2/v0.2 snapshots, issue obligations and current #104/#112 → #105–107 priorities remain unchanged. No runtime implementation or acceptance results are implied.

## Approved AGIS station design, printing and display integration — 2026-11-27

[AGIS v1.0](ADMISSION_GUEST_INFORMATION_AND_STATION_MANAGEMENT_DESIGN_v1.0.md) defines a constrained visual Station Designer with purpose-specific screen components, typed allowlisted bindings, reusable localized presets, versioned preview/review/publication, portrait/landscape and keyboard alternatives. Reuse TDS brand/assets/component and revision infrastructure; station runtime enforces mode-specific projections, permissions and actions independently. Print slips, cards, badges, replacement passes and passive signage use approved TDS graphical rendering and manifests, never a second renderer. Reprint of authorized retained artifact, rerender with current published allocation and explicit credential replacement are distinct reviewed operations. Preview/save/publish/render never issue a live credential, send, record attendance or automatically retry uncertain physical print. Browser print baseline; optional local print bridge requires reviewed least-privilege pairing, allowlisted printer/output and no host-shell access. Hardware/QR readability and privacy evidence required. All TDS-01–16 and AC-01–25 remain. This is an approved scope clarification, not a runtime implementation claim or instruction to interrupt the existing #104/#112 → #105–107 sequence. Preserve accepted ADRs, historical Blueprint v1.2, existing domain commands and issue criteria; final integrated acceptance remains Phase 9.

## Approved CID channel content and distribution integration — 2026-11-27

[CID v1.0](COMMUNICATION_INVITATION_DISTRIBUTION_AND_MULTI_CHANNEL_DELIVERY_DESIGN_v1.0.md) extends TDS typed purpose/mode/output assignments to channel-specific localized plain text, multipart email, private approved attachments, short SMS, official provider-approved WhatsApp/Viber templates, optional Telegram, opt-in push/in-app and graphical/manual/print artifacts. Reuse existing template/revision and brand/asset/render infrastructure; provider template IDs, language and approval status are mapped to immutable TDS revisions, with validated variable/media/length/segment/size limits. No arbitrary script, unreviewed conversion or provider-side content drift. Preview/save/publish/render/test with synthetic credentials never authorizes live issuance or campaign submission. CID owns reviewed routes, schedules, consent, cost reservations, retries and evidence; TDS owns content/rendering. Preserve current SMTP and all TDS-01–16/AC-01–25, original forms/reports/display obligations and AGIS print/reissue distinction. This is an approved scope clarification, not a runtime or acceptance claim. Preserve all existing requirements, accepted ADRs, historical Blueprint v1.2, current #104/#112 → #105–107 sequence and established #110/#111/#108 roadmap; no immediate implementation or environment republication. Final integrated acceptance remains Phase 9.

## Approved coordinated presentation and authoring boundaries — 2026-11-27

[AES v1.0](ADAPTIVE_EXPERIENCE_AND_SETUP_DESIGN_v1.0.md), [EPW v1.0](EVENT_PLANNING_PRODUCTION_AND_OPERATIONAL_WORKFLOWS_DESIGN_v1.0.md), [FRS v1.0](FORMS_REGISTRATION_AND_SUBMISSION_STUDIO_DESIGN_v1.0.md), [HPG v1.0](HOSPITALITY_PROTOCOL_AND_GUEST_SERVICES_DESIGN_v1.0.md), [RAI v1.0](REPORTING_ANALYTICS_AND_INTELLIGENCE_STUDIO_DESIGN_v1.0.md) share TDS brand inheritance, assets, localized component conventions and private rendering manifests. AES selects approved presets without publishing/sending; EPW produces approved schedules/checklists and HPG produces restricted service artifacts; FRS owns typed form field schema/validation, conditional logic, submission lifecycle and owning mapping (TDS owns visual presentation only); RAI owns typed report dataset/metric definitions and authorized result snapshots (TDS owns PDF/print appearance only). Reuse rendering infrastructure; no second unrestricted renderer, no arbitrary executable logic and no live credentials in synthetic previews. Approved additive scope only; retain existing requirements, accepted ADRs, Blueprint v1.2, PROJECT_STATE and the #104/#112 → #105–107 → #110/#111/#108 development sequence. No immediate implementation, unrelated closure gates, environment republication or Blueprint v1.3 consolidation. Final integrated acceptance remains Phase 9.

<!-- END EXACT INTEGRATED TDS -->
