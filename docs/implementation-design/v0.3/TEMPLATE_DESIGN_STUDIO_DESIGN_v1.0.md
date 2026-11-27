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
