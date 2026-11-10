  severity text NOT NULL DEFAULT 'warning' CHECK (severity IN ('info','warning','critical')) ,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','assigned','in_progress','resolved','closed')) ,
  owner_user_id uuid REFERENCES users(id),
  raised_by uuid REFERENCES users(id),
  related_entity_type text,
  related_entity_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  FOREIGN KEY (organization_id, event_id) REFERENCES events(organization_id, id),
  UNIQUE (organization_id, id)
);

CREATE TABLE notification_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid,
  event_guest_id uuid,
  recipient_user_id uuid REFERENCES users(id),
  channel text NOT NULL CHECK (channel IN ('email','sms','web_push','in_app','other')) ,
  template_revision_id uuid,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','sent','delivered','failed','suppressed')) ,
  provider_reference text,
  safe_error_code text,
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at timestamptz,
  FOREIGN KEY (organization_id, event_id) REFERENCES events(organization_id, id),
  FOREIGN KEY (organization_id, event_guest_id) REFERENCES event_guests(organization_id, id),
  FOREIGN KEY (organization_id, template_revision_id) REFERENCES document_template_revisions(organization_id, id),
  UNIQUE (organization_id, id)
);

CREATE TABLE audit_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid,
  actor_user_id uuid REFERENCES users(id),
  actor_station_id uuid,
  action_code text NOT NULL,
  entity_type text NOT NULL,
  entity_id uuid,
  classification text NOT NULL DEFAULT 'internal' CHECK (classification IN ('internal','confidential','restricted','security')),
  request_id text,
  reason text,
  changed_fields jsonb NOT NULL DEFAULT '[]'::jsonb,
  before_digest char(64),
  after_digest char(64),
  occurred_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, event_id) REFERENCES events(organization_id, id)
);
CREATE INDEX audit_events_entity_idx ON audit_events(organization_id, entity_type, entity_id, occurred_at DESC);

CREATE TABLE outbox_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid,
  aggregate_type text NOT NULL,
  aggregate_id uuid NOT NULL,
  aggregate_revision integer,
  event_type text NOT NULL,
  audience_scope jsonb NOT NULL DEFAULT '{}'::jsonb,
  payload_minimal jsonb NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz,
  attempt_count integer NOT NULL DEFAULT 0,
  last_error text,
  FOREIGN KEY (organization_id, event_id) REFERENCES events(organization_id, id)
);
CREATE INDEX outbox_pending_idx ON outbox_events(occurred_at) WHERE published_at IS NULL;

CREATE TABLE background_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid,
  job_type text NOT NULL,
  status text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','running','completed','failed','cancelled')),
  progress_percent integer NOT NULL DEFAULT 0 CHECK (progress_percent BETWEEN 0 AND 100),
  input_reference jsonb NOT NULL DEFAULT '{}'::jsonb,
  result_reference jsonb NOT NULL DEFAULT '{}'::jsonb,
  error_code text,
  error_safe_message text,
  requested_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  completed_at timestamptz,
  FOREIGN KEY (organization_id, event_id) REFERENCES events(organization_id, id),
  UNIQUE (organization_id, id)
);
CREATE INDEX background_jobs_queue_idx ON background_jobs(status, created_at) WHERE status IN ('queued','running');

-- Operational requirements for a real deployment:
-- 1) Create separate migration-owner and runtime DB roles. Runtime must not own tables.
-- 2) Set app.organization_id transaction-locally after authentication/authorization.
-- 3) Enable and FORCE RLS on all tenant-owned tables before shared multi-tenant use.
-- 4) Create explicit USING/WITH CHECK policies on every tenant-owned table.
-- 5) Add triggers or application hooks for updated_at, audit and immutable revision enforcement.
-- 6) Add approved document retention/deletion policies and encrypted backup/storage procedures.
-- Example helper (policy rollout is intentionally not enabled by this starter):
-- CREATE FUNCTION eogp.current_organization_id() RETURNS uuid
-- LANGUAGE sql STABLE AS $$ SELECT NULLIF(current_setting('app.organization_id', true), '')::uuid $$;
-- CREATE POLICY tenant_isolation ON eogp.events
--   USING (organization_id = eogp.current_organization_id())
--   WITH CHECK (organization_id = eogp.current_organization_id());

COMMIT;

-- ================= v0.2 booking/configuration extension =================
BEGIN;
-- EOGP booking and configurable-form schema addendum v0.2
-- Intended to be appended after eogp_schema_v0.1.sql in a reviewed migration.
-- DESIGN REFERENCE ONLY: not a production migration. Validate constraints, RLS,
-- immutability triggers, indexes, retention and migration ordering before use.

SET search_path = eogp, public;

-- ---------------------------------------------------------------------------
-- Configurable catalogues and choice options
-- Stable option identity is separate from versioned, localized presentation.
-- Retire options; do not hard-delete options referenced by historical records.
-- ---------------------------------------------------------------------------
CREATE TABLE config_catalogues (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  code text NOT NULL,
  display_name text NOT NULL,
  scope_type text NOT NULL DEFAULT 'organization'
    CHECK (scope_type IN ('organization','venue','space','event')),
  scope_id uuid,
  description text,
  status text NOT NULL DEFAULT 'active'
    CHECK (status IN ('draft','active','archived')),
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((scope_type = 'organization' AND scope_id IS NULL) OR
         (scope_type <> 'organization' AND scope_id IS NOT NULL)),
  UNIQUE (organization_id, scope_type, scope_id, code),
  UNIQUE (organization_id, id)
);

CREATE TABLE config_catalogue_revisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  catalogue_id uuid NOT NULL,
  revision_no integer NOT NULL CHECK (revision_no > 0),
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','published','superseded','archived')),
  locale_defaults jsonb NOT NULL DEFAULT '{"primary":"bs-BA"}'::jsonb,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  published_by uuid REFERENCES users(id),
  published_at timestamptz,
  FOREIGN KEY (organization_id, catalogue_id)
    REFERENCES config_catalogues(organization_id, id),
  UNIQUE (catalogue_id, revision_no),
  UNIQUE (organization_id, id)
);

CREATE TABLE config_catalogue_options (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  catalogue_id uuid NOT NULL,
  option_code text NOT NULL,
  semantic_status text NOT NULL DEFAULT 'active'
    CHECK (semantic_status IN ('active','retired')),
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  retired_by uuid REFERENCES users(id),
  retired_at timestamptz,
  retirement_reason text,
  FOREIGN KEY (organization_id, catalogue_id)
    REFERENCES config_catalogues(organization_id, id),
  UNIQUE (catalogue_id, option_code),
  UNIQUE (organization_id, id),
  CHECK ((semantic_status = 'active' AND retired_at IS NULL) OR
         (semantic_status = 'retired' AND retired_at IS NOT NULL))
);

CREATE TABLE config_catalogue_option_revisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  option_id uuid NOT NULL,
  revision_no integer NOT NULL CHECK (revision_no > 0),
  label_i18n jsonb NOT NULL,
  description_i18n jsonb NOT NULL DEFAULT '{}'::jsonb,
  help_i18n jsonb NOT NULL DEFAULT '{}'::jsonb,
  sort_order integer NOT NULL DEFAULT 0,
  selectable boolean NOT NULL DEFAULT true,
  presentation_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  resource_service_mapping jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, option_id)
    REFERENCES config_catalogue_options(organization_id, id),
  UNIQUE (option_id, revision_no),
  UNIQUE (organization_id, id),
  CHECK (jsonb_typeof(label_i18n) = 'object')
);

CREATE TABLE config_catalogue_revision_options (
  organization_id uuid NOT NULL,
  catalogue_revision_id uuid NOT NULL,
  option_id uuid NOT NULL,
  option_revision_id uuid NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  PRIMARY KEY (catalogue_revision_id, option_id),
  FOREIGN KEY (organization_id, catalogue_revision_id)
    REFERENCES config_catalogue_revisions(organization_id, id),
  FOREIGN KEY (organization_id, option_id)
    REFERENCES config_catalogue_options(organization_id, id),
  FOREIGN KEY (organization_id, option_revision_id)
    REFERENCES config_catalogue_option_revisions(organization_id, id)
);

-- ---------------------------------------------------------------------------
-- Versioned public booking forms. Schema JSON is a constrained declarative DSL;
-- it MUST NOT contain executable JavaScript, SQL, eval, or arbitrary expressions.
-- ---------------------------------------------------------------------------
CREATE TABLE booking_form_definitions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  code text NOT NULL,
  display_name text NOT NULL,
  description text,
  scope_type text NOT NULL DEFAULT 'organization'
    CHECK (scope_type IN ('organization','venue','space')),
  scope_id uuid,
  booking_type text NOT NULL DEFAULT 'venue_inquiry',
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','active','archived')),
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((scope_type = 'organization' AND scope_id IS NULL) OR
         (scope_type <> 'organization' AND scope_id IS NOT NULL)),
  UNIQUE (organization_id, scope_type, scope_id, code),
  UNIQUE (organization_id, id)
);

CREATE TABLE booking_form_revisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  form_definition_id uuid NOT NULL,
  revision_no integer NOT NULL CHECK (revision_no > 0),
  schema_version text NOT NULL DEFAULT 'eogp-form-1',
  schema_json jsonb NOT NULL,
  supported_locales text[] NOT NULL DEFAULT ARRAY['bs-BA']::text[],
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','published','superseded','archived')),
  content_sha256 char(64),
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  published_by uuid REFERENCES users(id),
  published_at timestamptz,
  FOREIGN KEY (organization_id, form_definition_id)
    REFERENCES booking_form_definitions(organization_id, id),
  UNIQUE (form_definition_id, revision_no),
  UNIQUE (organization_id, id),
  CHECK (jsonb_typeof(schema_json) = 'object')
);

CREATE TABLE booking_form_catalogue_bindings (
  organization_id uuid NOT NULL,
  form_revision_id uuid NOT NULL,
  field_key text NOT NULL,
  catalogue_revision_id uuid NOT NULL,
  PRIMARY KEY (form_revision_id, field_key),
  FOREIGN KEY (organization_id, form_revision_id)
    REFERENCES booking_form_revisions(organization_id, id),
  FOREIGN KEY (organization_id, catalogue_revision_id)
    REFERENCES config_catalogue_revisions(organization_id, id)
);

-- ---------------------------------------------------------------------------
-- Public inquiries are immutable records of what was actually submitted.
-- The payload stores the form, catalogue, labels and option presentation snapshot.
-- ---------------------------------------------------------------------------
CREATE TABLE booking_inquiries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  inquiry_code text NOT NULL,
  public_reference_hash char(64) NOT NULL,
  form_revision_id uuid NOT NULL,
  source_channel text NOT NULL DEFAULT 'public_web'
    CHECK (source_channel IN ('public_web','staff_entered','api','migration')),
  lifecycle_status text NOT NULL DEFAULT 'received'
    CHECK (lifecycle_status IN ('received','triage','needs_information','draft_created','rejected','withdrawn','closed')),
  organizer_name text,
  contact_name text,
  contact_email text,
  contact_phone text,
  preferred_start_at timestamptz,
  preferred_end_at timestamptz,
  locale text NOT NULL DEFAULT 'bs-BA',
  form_snapshot jsonb NOT NULL,
  submitted_payload jsonb NOT NULL,
  submitted_option_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  submission_ip_hash char(64),
  received_at timestamptz NOT NULL DEFAULT now(),
  assigned_to uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, form_revision_id)
    REFERENCES booking_form_revisions(organization_id, id),
  UNIQUE (organization_id, inquiry_code),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, public_reference_hash),
  CHECK (jsonb_typeof(form_snapshot) = 'object'),
  CHECK (jsonb_typeof(submitted_payload) = 'object'),
  CHECK (jsonb_typeof(submitted_option_snapshot) = 'object'),
  CHECK (preferred_end_at IS NULL OR preferred_start_at IS NULL OR preferred_end_at > preferred_start_at)
);
CREATE INDEX booking_inquiries_inbox_idx
  ON booking_inquiries(organization_id, lifecycle_status, received_at DESC);
CREATE INDEX booking_inquiries_start_idx
  ON booking_inquiries(organization_id, preferred_start_at)
  WHERE preferred_start_at IS NOT NULL;

CREATE TABLE booking_inquiry_attachments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  inquiry_id uuid NOT NULL,
  storage_key text NOT NULL,
  original_filename text NOT NULL,
  media_type text NOT NULL,
  file_size_bytes bigint NOT NULL CHECK (file_size_bytes > 0),
  sha256_hex char(64) NOT NULL,
  scan_status text NOT NULL DEFAULT 'quarantined'
    CHECK (scan_status IN ('quarantined','clean','rejected','scan_error')),
  classification text NOT NULL DEFAULT 'personal'
    CHECK (classification IN ('public','internal','personal','confidential','restricted')),
  uploaded_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, inquiry_id)
    REFERENCES booking_inquiries(organization_id, id),
  UNIQUE (organization_id, id)
);

CREATE TABLE booking_inquiry_annotations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  inquiry_id uuid NOT NULL,
  annotation_type text NOT NULL
    CHECK (annotation_type IN ('internal_note','clarification_request','contact_log','triage_note')),
  body text NOT NULL,
  classification text NOT NULL DEFAULT 'internal'
    CHECK (classification IN ('internal','confidential','restricted')),
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, inquiry_id)
    REFERENCES booking_inquiries(organization_id, id),
  UNIQUE (organization_id, id)
);

-- ---------------------------------------------------------------------------
-- Drafts and revisions. A draft can originate from an inquiry or be created
-- manually. Every edit produces a new immutable revision snapshot.
-- ---------------------------------------------------------------------------
CREATE TABLE booking_drafts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  draft_code text NOT NULL,
  source_inquiry_id uuid,
  lifecycle_status text NOT NULL DEFAULT 'draft'
    CHECK (lifecycle_status IN ('draft','in_review','offer_pending','approved','rejected','converted','abandoned')),
  owner_user_id uuid REFERENCES users(id),
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, source_inquiry_id)
    REFERENCES booking_inquiries(organization_id, id),
  UNIQUE (organization_id, draft_code),
  UNIQUE (organization_id, id)
);

CREATE TABLE booking_draft_revisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  draft_id uuid NOT NULL,
  revision_no integer NOT NULL CHECK (revision_no > 0),
  source_inquiry_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  working_payload jsonb NOT NULL,
  requested_approved_delivered jsonb NOT NULL DEFAULT '{}'::jsonb,
  pricing_preview jsonb NOT NULL DEFAULT '{}'::jsonb,
  change_reason text,
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, draft_id)
    REFERENCES booking_drafts(organization_id, id),
  UNIQUE (draft_id, revision_no),
  UNIQUE (organization_id, id),
  CHECK (jsonb_typeof(working_payload) = 'object')
);

-- ---------------------------------------------------------------------------
-- Effective-dated price lists and immutable rule revisions.
-- ---------------------------------------------------------------------------
CREATE TABLE booking_price_lists (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  code text NOT NULL,
  display_name text NOT NULL,
  scope_type text NOT NULL DEFAULT 'organization'
    CHECK (scope_type IN ('organization','venue','space')),
  scope_id uuid,
  currency char(3) NOT NULL DEFAULT 'BAM',
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','active','archived')),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((scope_type = 'organization' AND scope_id IS NULL) OR
         (scope_type <> 'organization' AND scope_id IS NOT NULL)),
  UNIQUE (organization_id, scope_type, scope_id, code),
  UNIQUE (organization_id, id)
);

CREATE TABLE booking_price_list_revisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  price_list_id uuid NOT NULL,
  revision_no integer NOT NULL CHECK (revision_no > 0),
  effective_from date NOT NULL,
  effective_until date,
  rules_snapshot jsonb NOT NULL,
  status text NOT NULL DEFAULT 'draft'
    CHECK (status IN ('draft','published','superseded','archived')),
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  published_by uuid REFERENCES users(id),
  published_at timestamptz,
  FOREIGN KEY (organization_id, price_list_id)
    REFERENCES booking_price_lists(organization_id, id),
  UNIQUE (price_list_id, revision_no),
  UNIQUE (organization_id, id),
  CHECK (effective_until IS NULL OR effective_until >= effective_from)
);

-- ---------------------------------------------------------------------------
-- Offers, confirmed bookings, reservations and resource/service lines.
-- ---------------------------------------------------------------------------
CREATE TABLE booking_offers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  draft_revision_id uuid NOT NULL,
  offer_code text NOT NULL,
  offer_revision integer NOT NULL DEFAULT 1 CHECK (offer_revision > 0),
  price_list_revision_id uuid,
  lifecycle_status text NOT NULL DEFAULT 'draft'
    CHECK (lifecycle_status IN ('draft','issued','accepted','declined','expired','superseded','withdrawn')),
  currency char(3) NOT NULL DEFAULT 'BAM',
  subtotal numeric(14,2) NOT NULL DEFAULT 0,
  tax_amount numeric(14,2) NOT NULL DEFAULT 0,
  total_amount numeric(14,2) NOT NULL DEFAULT 0,
  tax_basis text NOT NULL DEFAULT 'exclusive'
    CHECK (tax_basis IN ('inclusive','exclusive','not_applicable','to_be_confirmed')),
  offer_snapshot jsonb NOT NULL,
  valid_until timestamptz,
  issued_at timestamptz,
  accepted_at timestamptz,
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, draft_revision_id)
    REFERENCES booking_draft_revisions(organization_id, id),
  FOREIGN KEY (organization_id, price_list_revision_id)
    REFERENCES booking_price_list_revisions(organization_id, id),
  UNIQUE (organization_id, offer_code, offer_revision),
  UNIQUE (organization_id, id)
);

CREATE TABLE booking_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  booking_code text NOT NULL,
  source_inquiry_id uuid,
  source_draft_revision_id uuid NOT NULL,
  accepted_offer_id uuid,
  linked_event_id uuid,
  lifecycle_status text NOT NULL DEFAULT 'confirmed'
    CHECK (lifecycle_status IN ('confirmed','in_progress','completed','cancelled','amended')),
  booking_title text NOT NULL,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  confirmed_snapshot jsonb NOT NULL,
  confirmed_by uuid REFERENCES users(id),
  confirmed_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, source_inquiry_id)
    REFERENCES booking_inquiries(organization_id, id),
  FOREIGN KEY (organization_id, source_draft_revision_id)
    REFERENCES booking_draft_revisions(organization_id, id),
  FOREIGN KEY (organization_id, accepted_offer_id)
    REFERENCES booking_offers(organization_id, id),
  FOREIGN KEY (organization_id, linked_event_id)
    REFERENCES events(organization_id, id),
  UNIQUE (organization_id, booking_code),
  UNIQUE (organization_id, id),
  CHECK (ends_at > starts_at),
  CHECK (jsonb_typeof(confirmed_snapshot) = 'object')
);

CREATE TABLE booking_space_reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  booking_id uuid NOT NULL,
  venue_space_id uuid NOT NULL,
  reservation_kind text NOT NULL DEFAULT 'event'
    CHECK (reservation_kind IN ('setup','rehearsal','event','teardown','buffer','ancillary')),
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'confirmed'
    CHECK (status IN ('held','confirmed','released','cancelled')),
  source_draft_revision_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, booking_id)
    REFERENCES booking_records(organization_id, id),
  FOREIGN KEY (organization_id, venue_space_id)
    REFERENCES venue_spaces(organization_id, id),
  FOREIGN KEY (organization_id, source_draft_revision_id)
    REFERENCES booking_draft_revisions(organization_id, id),
  UNIQUE (organization_id, id),
  CHECK (ends_at > starts_at)
);
CREATE INDEX booking_space_reservations_overlap_idx
  ON booking_space_reservations(organization_id, venue_space_id, starts_at, ends_at)
  WHERE status IN ('held','confirmed');

CREATE TABLE booking_resource_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  booking_id uuid NOT NULL,
  source_option_revision_id uuid,
  line_code text NOT NULL,
  line_kind text NOT NULL
    CHECK (line_kind IN ('equipment','personnel','catering','technical_service','facility','fee','discount','other')),
  description_snapshot jsonb NOT NULL,
  requested_value jsonb NOT NULL DEFAULT '{}'::jsonb,
  approved_value jsonb NOT NULL DEFAULT '{}'::jsonb,
  delivered_value jsonb NOT NULL DEFAULT '{}'::jsonb,
  requested_quantity numeric(12,3),
  approved_quantity numeric(12,3),
  delivered_quantity numeric(12,3),
  unit_label text,
  unit_price numeric(14,2),
  line_total numeric(14,2),
  currency char(3) NOT NULL DEFAULT 'BAM',
  tax_treatment text NOT NULL DEFAULT 'to_be_confirmed'
    CHECK (tax_treatment IN ('inclusive','exclusive','exempt','not_applicable','to_be_confirmed')),
  fulfillment_status text NOT NULL DEFAULT 'pending'
    CHECK (fulfillment_status IN ('pending','approved','scheduled','delivered','partially_delivered','not_delivered','cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, booking_id)
    REFERENCES booking_records(organization_id, id),
  FOREIGN KEY (organization_id, source_option_revision_id)
    REFERENCES config_catalogue_option_revisions(organization_id, id),
  UNIQUE (organization_id, id)
);

CREATE TABLE booking_holds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  venue_space_id uuid NOT NULL,
  inquiry_id uuid,
  draft_id uuid,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  hold_status text NOT NULL DEFAULT 'active'
    CHECK (hold_status IN ('active','consumed','expired','released')),
  expires_at timestamptz NOT NULL,
  held_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, venue_space_id)
    REFERENCES venue_spaces(organization_id, id),
  FOREIGN KEY (organization_id, inquiry_id)
    REFERENCES booking_inquiries(organization_id, id),
  FOREIGN KEY (organization_id, draft_id)
    REFERENCES booking_drafts(organization_id, id),
  UNIQUE (organization_id, id),
  CHECK (ends_at > starts_at),
  CHECK (expires_at > created_at)
);
CREATE INDEX booking_holds_expiry_idx ON booking_holds(organization_id, expires_at)
  WHERE hold_status = 'active';

CREATE TABLE booking_approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  draft_revision_id uuid NOT NULL,
  approval_stage_code text NOT NULL,
  approver_user_id uuid REFERENCES users(id),
  decision text NOT NULL DEFAULT 'pending'
    CHECK (decision IN ('pending','approved','rejected','returned_for_changes','skipped')),
  decision_note text,
  decided_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, draft_revision_id)
    REFERENCES booking_draft_revisions(organization_id, id),
  UNIQUE (organization_id, id)
);

CREATE TABLE booking_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  aggregate_type text NOT NULL
    CHECK (aggregate_type IN ('inquiry','draft','offer','booking')),
  aggregate_id uuid NOT NULL,
  from_status text,
  to_status text NOT NULL,
  reason text,
  actor_user_id uuid REFERENCES users(id),
  occurred_at timestamptz NOT NULL DEFAULT now(),
  request_id text
);
CREATE INDEX booking_status_history_aggregate_idx
  ON booking_status_history(organization_id, aggregate_type, aggregate_id, occurred_at);

-- Required implementation controls (not encoded as ordinary CHECK constraints):
-- 1) Enforce tenant RLS on every new organization-owned table and test as runtime role.
-- 2) Published form/catalogue/price revisions and inquiry snapshots are immutable.
--    Implement DB triggers or restrict UPDATE/DELETE privileges, plus service checks.
-- 3) Do not hard-delete catalogue options referenced by form, inquiry, draft, offer or booking.
-- 4) Changing option meaning requires a new option identity; label-only changes create a revision.
-- 5) Server validates conditional-form rules using a safe declarative DSL; never eval executable code.
-- 6) Inquiry form/option snapshots must preserve localized display labels as submitted.
-- 7) Booking confirmation must lock/check all time ranges and resource capacities atomically.
-- 8) Add equivalent reservations for shared equipment/personnel before those calendars are enabled.
-- 9) Add booking record revision/change-order tables before allowing post-confirmation amendments.
-- 10) Retention, erasure and public-reference hashing policies must be approved before production.
COMMIT;