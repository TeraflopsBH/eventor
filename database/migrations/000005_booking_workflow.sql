-- Inquiry, immutable draft revisions, offers, confirmation and booking party snapshots.
CREATE TABLE eogp.booking_inquiries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    public_reference text NOT NULL,
    form_revision_id uuid,
    submitted_values_ciphertext bytea NOT NULL,
    requester_name_ciphertext bytea NOT NULL,
    requester_email_hash text,
    requester_email_ciphertext bytea,
    requester_phone_hash text,
    requester_phone_ciphertext bytea,
    requested_start timestamptz,
    requested_end timestamptz,
    requested_timezone text NOT NULL DEFAULT 'Europe/Sarajevo',
    status text NOT NULL DEFAULT 'received'
      CHECK (status IN ('received','under_review','converted','declined','withdrawn','spam')),
    submitted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, public_reference),
    FOREIGN KEY (organization_id, form_revision_id)
      REFERENCES eogp.booking_form_revisions(organization_id, id),
    CHECK (requested_end IS NULL OR requested_start IS NULL OR requested_end > requested_start)
);
CREATE INDEX booking_inquiries_inbox_idx
  ON eogp.booking_inquiries (organization_id, submitted_at DESC)
  WHERE status IN ('received','under_review');

CREATE TABLE eogp.booking_inquiry_attachments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    inquiry_id uuid NOT NULL,
    storage_key text NOT NULL,
    filename text NOT NULL,
    media_type text NOT NULL,
    content_sha256 text NOT NULL CHECK (content_sha256 ~ '^[0-9a-f]{64}$'),
    byte_length bigint NOT NULL CHECK (byte_length >= 0),
    uploaded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, inquiry_id)
      REFERENCES eogp.booking_inquiries(organization_id, id)
);

CREATE TABLE eogp.booking_inquiry_annotations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    inquiry_id uuid NOT NULL,
    actor_membership_id uuid NOT NULL,
    annotation text NOT NULL,
    visibility text NOT NULL DEFAULT 'internal'
      CHECK (visibility IN ('internal','customer_visible')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, inquiry_id)
      REFERENCES eogp.booking_inquiries(organization_id, id),
    FOREIGN KEY (organization_id, actor_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);

CREATE TABLE eogp.booking_drafts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    source_inquiry_id uuid,
    created_by_membership_id uuid NOT NULL,
    status text NOT NULL DEFAULT 'draft'
      CHECK (status IN ('draft','offered','confirmed','abandoned')),
    current_revision_number integer NOT NULL DEFAULT 0 CHECK (current_revision_number >= 0),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, source_inquiry_id)
      REFERENCES eogp.booking_inquiries(organization_id, id),
    FOREIGN KEY (organization_id, created_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);

CREATE TABLE eogp.booking_draft_revisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    draft_id uuid NOT NULL,
    revision_number integer NOT NULL CHECK (revision_number > 0),
    source_form_revision_id uuid,
    values_snapshot jsonb NOT NULL,
    requested_start timestamptz,
    requested_end timestamptz,
    timezone_name text NOT NULL DEFAULT 'Europe/Sarajevo',
    change_reason text,
    created_by_membership_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, draft_id, id),
    UNIQUE (organization_id, draft_id, revision_number),
    FOREIGN KEY (organization_id, draft_id)
      REFERENCES eogp.booking_drafts(organization_id, id),
    FOREIGN KEY (organization_id, source_form_revision_id)
      REFERENCES eogp.booking_form_revisions(organization_id, id),
    FOREIGN KEY (organization_id, created_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    CHECK (requested_end IS NULL OR requested_start IS NULL OR requested_end > requested_start)
);

CREATE TABLE eogp.booking_draft_space_lines (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    draft_revision_id uuid NOT NULL,
    venue_space_id uuid NOT NULL,
    block_kind text NOT NULL DEFAULT 'event_use'
      CHECK (block_kind IN ('setup','rehearsal','event_use','teardown','buffer')),
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    requested_capacity integer CHECK (requested_capacity IS NULL OR requested_capacity >= 0),
    notes text,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, draft_revision_id)
      REFERENCES eogp.booking_draft_revisions(organization_id, id),
    FOREIGN KEY (organization_id, venue_space_id)
      REFERENCES eogp.venue_spaces(organization_id, id),
    CHECK (ends_at > starts_at)
);

CREATE TABLE eogp.booking_offers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    draft_id uuid NOT NULL,
    status text NOT NULL DEFAULT 'prepared'
      CHECK (status IN ('prepared','issued','accepted','rejected','expired','withdrawn','superseded')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, draft_id)
      REFERENCES eogp.booking_drafts(organization_id, id)
);

CREATE TABLE eogp.booking_offer_revisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    offer_id uuid NOT NULL,
    revision_number integer NOT NULL CHECK (revision_number > 0),
    draft_revision_id uuid NOT NULL,
    price_list_revision_id uuid,
    cancellation_policy_revision_id uuid,
    terms_snapshot jsonb NOT NULL,
    currency char(3) NOT NULL,
    subtotal numeric(14,2) NOT NULL CHECK (subtotal >= 0),
    tax_amount numeric(14,2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
    total_amount numeric(14,2) NOT NULL CHECK (total_amount >= 0),
    valid_until timestamptz,
    state text NOT NULL DEFAULT 'draft'
      CHECK (state IN ('draft','issued','accepted','rejected','expired','withdrawn')),
    issued_at timestamptz,
    accepted_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, offer_id, id),
    UNIQUE (organization_id, offer_id, revision_number),
    FOREIGN KEY (organization_id, offer_id) REFERENCES eogp.booking_offers(organization_id, id),
    FOREIGN KEY (organization_id, draft_revision_id) REFERENCES eogp.booking_draft_revisions(organization_id, id),
    FOREIGN KEY (organization_id, price_list_revision_id)
      REFERENCES eogp.booking_price_list_revisions(organization_id, id),
    FOREIGN KEY (organization_id, cancellation_policy_revision_id)
      REFERENCES eogp.cancellation_policy_revisions(organization_id, id),
    CHECK (valid_until IS NULL OR issued_at IS NULL OR valid_until > issued_at)
);

CREATE TABLE eogp.booking_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    booking_code text NOT NULL,
    source_offer_revision_id uuid NOT NULL,
    status text NOT NULL DEFAULT 'confirmed'
      CHECK (status IN ('confirmed','completed','cancelled','closed')),
    revision_number integer NOT NULL DEFAULT 1 CHECK (revision_number > 0),
    confirmed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    cancelled_at timestamptz,
    completed_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, booking_code),
    FOREIGN KEY (organization_id, source_offer_revision_id)
      REFERENCES eogp.booking_offer_revisions(organization_id, id),
    CHECK ((status = 'cancelled') = (cancelled_at IS NOT NULL)),
    CHECK ((status = 'completed') = (completed_at IS NOT NULL))
);

CREATE TABLE eogp.booking_confirmed_snapshots (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    booking_id uuid NOT NULL,
    offer_revision_id uuid NOT NULL,
    cancellation_policy_revision_id uuid,
    customer_terms_snapshot jsonb NOT NULL,
    price_snapshot jsonb NOT NULL,
    confirmed_by_membership_id uuid NOT NULL,
    accepted_by_contact_label text,
    snapshot_sha256 text NOT NULL CHECK (snapshot_sha256 ~ '^[0-9a-f]{64}$'),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, booking_id),
    FOREIGN KEY (organization_id, booking_id) REFERENCES eogp.booking_records(organization_id, id),
    FOREIGN KEY (organization_id, offer_revision_id) REFERENCES eogp.booking_offer_revisions(organization_id, id),
    FOREIGN KEY (organization_id, cancellation_policy_revision_id)
      REFERENCES eogp.cancellation_policy_revisions(organization_id, id),
    FOREIGN KEY (organization_id, confirmed_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);

CREATE TABLE eogp.booking_party_contacts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    booking_id uuid NOT NULL,
    party_role text NOT NULL
      CHECK (party_role IN ('requester','organizer','contracting_party','payer','billing_contact','authorized_booking_contact')),
    display_name_ciphertext bytea NOT NULL,
    email_hash text,
    email_ciphertext bytea,
    phone_hash text,
    phone_ciphertext bytea,
    authorized_actions text[] NOT NULL DEFAULT ARRAY[]::text[],
    is_primary boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, booking_id, id),
    FOREIGN KEY (organization_id, booking_id) REFERENCES eogp.booking_records(organization_id, id),
    CHECK (email_ciphertext IS NOT NULL OR phone_ciphertext IS NOT NULL OR display_name_ciphertext IS NOT NULL),
    CHECK ((email_hash IS NULL) = (email_ciphertext IS NULL)),
    CHECK ((phone_hash IS NULL) = (phone_ciphertext IS NULL))
);
CREATE INDEX booking_party_contacts_booking_idx
  ON eogp.booking_party_contacts (organization_id, booking_id, party_role);

CREATE TABLE eogp.booking_approvals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    booking_id uuid NOT NULL,
    approval_kind text NOT NULL CHECK (approval_kind IN ('offer','discount','exception','confirmation')),
    decision text NOT NULL CHECK (decision IN ('approved','rejected','returned_for_changes')),
    actor_membership_id uuid NOT NULL,
    reason text,
    decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, booking_id) REFERENCES eogp.booking_records(organization_id, id),
    FOREIGN KEY (organization_id, actor_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);

CREATE TABLE eogp.booking_status_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    booking_id uuid NOT NULL,
    previous_status text,
    new_status text NOT NULL,
    actor_membership_id uuid,
    reason_code text,
    details jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, booking_id) REFERENCES eogp.booking_records(organization_id, id),
    FOREIGN KEY (organization_id, actor_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);

CREATE TABLE eogp.booking_resource_lines (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    booking_id uuid,
    draft_revision_id uuid,
    resource_type_id uuid NOT NULL,
    line_code text NOT NULL,
    label_snapshot text NOT NULL,
    requested_quantity numeric(12,3) NOT NULL DEFAULT 0 CHECK (requested_quantity >= 0),
    approved_quantity numeric(12,3) CHECK (approved_quantity IS NULL OR approved_quantity >= 0),
    delivered_quantity numeric(12,3) CHECK (delivered_quantity IS NULL OR delivered_quantity >= 0),
    unit_amount numeric(14,2) CHECK (unit_amount IS NULL OR unit_amount >= 0),
    line_total numeric(14,2) CHECK (line_total IS NULL OR line_total >= 0),
    value_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, booking_id) REFERENCES eogp.booking_records(organization_id, id),
    FOREIGN KEY (organization_id, draft_revision_id) REFERENCES eogp.booking_draft_revisions(organization_id, id),
    FOREIGN KEY (organization_id, resource_type_id) REFERENCES eogp.resource_types(organization_id, id),
    CHECK (num_nonnulls(booking_id, draft_revision_id) = 1),
    CHECK (approved_quantity IS NULL OR approved_quantity <= requested_quantity OR requested_quantity = 0),
    CHECK (delivered_quantity IS NULL OR approved_quantity IS NULL OR delivered_quantity <= approved_quantity)
);
CREATE INDEX booking_resource_lines_booking_idx ON eogp.booking_resource_lines (organization_id, booking_id);

