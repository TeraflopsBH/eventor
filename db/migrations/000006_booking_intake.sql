-- Eventor migration 000006: 000006_booking_intake.sql
-- Apply only through scripts/db/apply-migrations.sh so the checksum ledger is updated.
BEGIN;
SET LOCAL search_path TO eogp, public;

SET LOCAL search_path TO eogp, public;

CREATE TABLE eogp.booking_inquiries (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  venue_id        uuid NOT NULL,
  public_reference_hash text NOT NULL UNIQUE,
  submitted_by_name text NOT NULL,
  submitted_by_email text NOT NULL,
  submitted_by_phone text,
  submitted_form_revision_id uuid,
  requested_data  jsonb NOT NULL,
  status          text NOT NULL DEFAULT 'received' CHECK (status IN ('received','reviewing','converted','closed','spam')),
  submitted_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  FOREIGN KEY (organization_id, venue_id)
    REFERENCES eogp.venues(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, submitted_form_revision_id)
    REFERENCES eogp.booking_form_revisions(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.booking_inquiry_attachments (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  inquiry_id      uuid NOT NULL,
  storage_key     text NOT NULL,
  media_type      text NOT NULL,
  sha256          text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  uploaded_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (organization_id, inquiry_id)
    REFERENCES eogp.booking_inquiries(organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, id)
);

CREATE TABLE eogp.booking_inquiry_annotations (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  inquiry_id      uuid NOT NULL,
  actor_membership_id uuid NOT NULL,
  annotation      text NOT NULL CHECK (length(trim(annotation)) BETWEEN 1 AND 4000),
  visibility      text NOT NULL DEFAULT 'internal' CHECK (visibility IN ('internal','customer_visible')),
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (organization_id, inquiry_id)
    REFERENCES eogp.booking_inquiries(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, actor_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, id)
);

CREATE TABLE eogp.booking_drafts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  venue_id        uuid NOT NULL,
  inquiry_id      uuid,
  status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','offered','confirmed','cancelled','archived')),
  owner_membership_id uuid NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  FOREIGN KEY (organization_id, venue_id)
    REFERENCES eogp.venues(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, inquiry_id)
    REFERENCES eogp.booking_inquiries(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, owner_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.booking_draft_revisions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  draft_id        uuid NOT NULL,
  revision_no     integer NOT NULL CHECK (revision_no > 0),
  request_snapshot jsonb NOT NULL,
  starts_at       timestamptz NOT NULL,
  ends_at         timestamptz NOT NULL,
  event_timezone  text NOT NULL,
  change_reason   text,
  actor_membership_id uuid NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, draft_id, id),
  UNIQUE (organization_id, draft_id, revision_no),
  FOREIGN KEY (organization_id, draft_id)
    REFERENCES eogp.booking_drafts(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, actor_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT,
  CHECK (ends_at > starts_at)
);

INSERT INTO eogp.schema_migrations(version, filename, checksum_sha256)
VALUES ('000006', '000006_booking_intake.sql', :'migration_checksum');
COMMIT;
