-- Eventor migration 000013: 000013_guest_registry.sql
-- Apply only through scripts/db/apply-migrations.sh so the checksum ledger is updated.
BEGIN;
SET LOCAL search_path TO eogp, public;

SET LOCAL search_path TO eogp, public;

CREATE TABLE eogp.persons (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id) ON DELETE RESTRICT,
  display_name    text NOT NULL CHECK (length(trim(display_name)) BETWEEN 1 AND 250),
  merged_into_person_id uuid,
  status          text NOT NULL DEFAULT 'active' CHECK (status IN ('active','merged','archived')),
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  FOREIGN KEY (organization_id, merged_into_person_id)
    REFERENCES eogp.persons(organization_id, id) ON DELETE RESTRICT,
  CHECK ((status='merged') = (merged_into_person_id IS NOT NULL)),
  CHECK (merged_into_person_id IS NULL OR merged_into_person_id <> id)
);

CREATE TABLE eogp.person_contact_points (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  person_id       uuid NOT NULL,
  contact_kind    text NOT NULL CHECK (contact_kind IN ('email','phone','postal','other')),
  contact_value   text NOT NULL,
  normalized_value text,
  is_primary      boolean NOT NULL DEFAULT false,
  verified_at     timestamptz,
  status          text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired','suppressed')),
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (organization_id, person_id)
    REFERENCES eogp.persons(organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, id)
);

CREATE UNIQUE INDEX person_primary_contact_kind_uq
  ON eogp.person_contact_points(organization_id, person_id, contact_kind)
  WHERE is_primary AND status='active';

CREATE TABLE eogp.person_identifiers (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  person_id       uuid NOT NULL,
  identifier_type text NOT NULL,
  identifier_hash text NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (organization_id, person_id)
    REFERENCES eogp.persons(organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, identifier_type, identifier_hash),
  UNIQUE (organization_id, id)
);

CREATE TABLE eogp.event_participations (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  person_id       uuid NOT NULL,
  participation_code text NOT NULL,
  status          text NOT NULL DEFAULT 'eligible'
                  CHECK (status IN ('eligible','waitlisted','withdrawn','cancelled','removed')),
  category_code   text,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, event_id, id),
  UNIQUE (organization_id, event_id, participation_code),
  UNIQUE (organization_id, event_id, person_id),
  FOREIGN KEY (organization_id, event_id)
    REFERENCES eogp.events(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, person_id)
    REFERENCES eogp.persons(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.guest_groups (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  group_code      text NOT NULL,
  label           text NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, event_id, id),
  UNIQUE (organization_id, event_id, group_code),
  FOREIGN KEY (organization_id, event_id)
    REFERENCES eogp.events(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.guest_group_memberships (
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  group_id        uuid NOT NULL,
  participation_id uuid NOT NULL,
  added_at        timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (organization_id, group_id, participation_id),
  FOREIGN KEY (organization_id, event_id, group_id)
    REFERENCES eogp.guest_groups(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, event_id, participation_id)
    REFERENCES eogp.event_participations(organization_id, event_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.guest_notes (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  participation_id uuid NOT NULL,
  note_classification text NOT NULL DEFAULT 'restricted' CHECK (note_classification IN ('internal','restricted')),
  note_text       text NOT NULL,
  created_by_membership_id uuid NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (organization_id, event_id, participation_id)
    REFERENCES eogp.event_participations(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, id)
);

CREATE TABLE eogp.guest_custom_field_definitions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  field_code      text NOT NULL,
  label_by_locale jsonb NOT NULL,
  value_type      text NOT NULL CHECK (value_type IN ('text','number','boolean','date','select','multi_select')),
  status          text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  UNIQUE (organization_id, event_id, id),
  UNIQUE (organization_id, event_id, field_code),
  FOREIGN KEY (organization_id, event_id)
    REFERENCES eogp.events(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.guest_custom_field_values (
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  definition_id   uuid NOT NULL,
  participation_id uuid NOT NULL,
  value_json      jsonb NOT NULL,
  updated_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (organization_id, definition_id, participation_id),
  FOREIGN KEY (organization_id, event_id, definition_id)
    REFERENCES eogp.guest_custom_field_definitions(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, event_id, participation_id)
    REFERENCES eogp.event_participations(organization_id, event_id, id) ON DELETE RESTRICT
);

INSERT INTO eogp.schema_migrations(version, filename, checksum_sha256)
VALUES ('000013', '000013_guest_registry.sql', :'migration_checksum');
COMMIT;
