-- Eventor migration 000007: 000007_booking_confirmation.sql
-- Apply only through scripts/db/apply-migrations.sh so the checksum ledger is updated.
BEGIN;
SET LOCAL search_path TO eogp, public;

SET LOCAL search_path TO eogp, public;

CREATE TABLE eogp.booking_records (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  venue_id        uuid NOT NULL,
  confirmed_from_offer_id uuid,
  booking_code    text NOT NULL,
  status          text NOT NULL DEFAULT 'confirmed' CHECK (status IN ('confirmed','completed','cancelled','closed')),
  confirmed_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  effective_cancelled_at timestamptz,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, booking_code),
  UNIQUE (organization_id, confirmed_from_offer_id),
  FOREIGN KEY (organization_id, venue_id)
    REFERENCES eogp.venues(organization_id, id) ON DELETE RESTRICT,
  CHECK ((status='cancelled') = (effective_cancelled_at IS NOT NULL))
);

CREATE TABLE eogp.booking_offers (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  draft_revision_id uuid NOT NULL,
  revision_no     integer NOT NULL DEFAULT 1 CHECK (revision_no > 0),
  status          text NOT NULL DEFAULT 'issued' CHECK (status IN ('draft','issued','accepted','expired','withdrawn','rejected','confirmed')),
  currency        char(3) NOT NULL,
  tax_basis       text NOT NULL CHECK (tax_basis IN ('inclusive','exclusive','not_applicable','to_be_confirmed')),
  total_amount    numeric(14,2) NOT NULL CHECK (total_amount >= 0),
  terms_snapshot  jsonb NOT NULL,
  valid_until     timestamptz NOT NULL,
  issued_at       timestamptz,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, draft_revision_id, revision_no),
  FOREIGN KEY (organization_id, draft_revision_id)
    REFERENCES eogp.booking_draft_revisions(organization_id, id) ON DELETE RESTRICT,
  CHECK (valid_until > created_at),
  CHECK ((status IN ('issued','accepted','confirmed')) = (issued_at IS NOT NULL))
);

ALTER TABLE eogp.booking_records
  ADD CONSTRAINT booking_records_offer_fk
  FOREIGN KEY (organization_id, confirmed_from_offer_id)
  REFERENCES eogp.booking_offers(organization_id, id) ON DELETE RESTRICT;

CREATE TABLE eogp.booking_confirmed_snapshots (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  booking_id      uuid NOT NULL,
  offer_id        uuid NOT NULL,
  draft_revision_id uuid NOT NULL,
  snapshot_json   jsonb NOT NULL,
  confirmed_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, booking_id),
  FOREIGN KEY (organization_id, booking_id)
    REFERENCES eogp.booking_records(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, offer_id)
    REFERENCES eogp.booking_offers(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, draft_revision_id)
    REFERENCES eogp.booking_draft_revisions(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.booking_party_contacts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  booking_id      uuid NOT NULL,
  party_role      text NOT NULL CHECK (party_role IN ('requester','contracting_party','payer','organizer','authorized_cancellation_contact')),
  contact_name    text NOT NULL,
  email           text,
  phone           text,
  may_request_cancellation boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  FOREIGN KEY (organization_id, booking_id)
    REFERENCES eogp.booking_records(organization_id, id) ON DELETE RESTRICT,
  CHECK (party_role <> 'authorized_cancellation_contact' OR may_request_cancellation)
);

CREATE TABLE eogp.booking_approvals (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  offer_id        uuid NOT NULL,
  decision        text NOT NULL CHECK (decision IN ('approved','rejected','returned_for_changes')),
  actor_membership_id uuid NOT NULL,
  decision_reason text,
  decided_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (organization_id, offer_id)
    REFERENCES eogp.booking_offers(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, actor_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, id)
);

CREATE TABLE eogp.booking_status_history (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  booking_id      uuid NOT NULL,
  from_status     text,
  to_status       text NOT NULL,
  actor_membership_id uuid,
  reason          text,
  occurred_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (organization_id, booking_id)
    REFERENCES eogp.booking_records(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, actor_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, id)
);

CREATE TABLE eogp.booking_resource_lines (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  booking_id      uuid NOT NULL,
  resource_pool_id uuid,
  item_code       text NOT NULL,
  requested_quantity numeric(14,3) NOT NULL CHECK (requested_quantity >= 0),
  approved_quantity numeric(14,3) CHECK (approved_quantity IS NULL OR approved_quantity >= 0),
  delivered_quantity numeric(14,3) CHECK (delivered_quantity IS NULL OR delivered_quantity >= 0),
  unit_price      numeric(14,2) CHECK (unit_price IS NULL OR unit_price >= 0),
  line_snapshot   jsonb NOT NULL DEFAULT '{}'::jsonb,
  FOREIGN KEY (organization_id, booking_id)
    REFERENCES eogp.booking_records(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, resource_pool_id)
    REFERENCES eogp.resource_pools(organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, id),
  CHECK (approved_quantity IS NULL OR approved_quantity <= requested_quantity OR requested_quantity = 0),
  CHECK (delivered_quantity IS NULL OR approved_quantity IS NULL OR delivered_quantity <= approved_quantity)
);

INSERT INTO eogp.schema_migrations(version, filename, checksum_sha256)
VALUES ('000007', '000007_booking_confirmation.sql', :'migration_checksum');
COMMIT;
