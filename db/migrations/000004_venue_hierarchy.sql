-- Eventor migration 000004: 000004_venue_hierarchy.sql
-- Apply only through scripts/db/apply-migrations.sh so the checksum ledger is updated.
BEGIN;
SET LOCAL search_path TO eogp, public;

SET LOCAL search_path TO eogp, public;

CREATE TABLE eogp.venues (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id) ON DELETE RESTRICT,
  code            text NOT NULL,
  name            text NOT NULL,
  address_json    jsonb NOT NULL DEFAULT '{}'::jsonb,
  status          text NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive','archived')),
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, code)
);

CREATE TABLE eogp.venue_buildings (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  venue_id        uuid NOT NULL,
  name            text NOT NULL,
  sort_order      integer NOT NULL DEFAULT 0,
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, venue_id, id),
  FOREIGN KEY (organization_id, venue_id)
    REFERENCES eogp.venues(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.venue_levels (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  building_id     uuid NOT NULL,
  name            text NOT NULL,
  level_code      text,
  sort_order      integer NOT NULL DEFAULT 0,
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, building_id, id),
  FOREIGN KEY (organization_id, building_id)
    REFERENCES eogp.venue_buildings(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.venue_spaces (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  venue_id        uuid NOT NULL,
  building_id     uuid,
  level_id        uuid,
  parent_space_id uuid,
  code            text NOT NULL,
  name            text NOT NULL,
  space_kind      text NOT NULL DEFAULT 'room',
  capacity        integer CHECK (capacity IS NULL OR capacity >= 0),
  status          text NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive','archived')),
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, venue_id, id),
  UNIQUE (organization_id, venue_id, code),
  FOREIGN KEY (organization_id, venue_id)
    REFERENCES eogp.venues(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, venue_id, building_id)
    REFERENCES eogp.venue_buildings(organization_id, venue_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, building_id, level_id)
    REFERENCES eogp.venue_levels(organization_id, building_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, venue_id, parent_space_id)
    REFERENCES eogp.venue_spaces(organization_id, venue_id, id) ON DELETE RESTRICT,
  CHECK (level_id IS NULL OR building_id IS NOT NULL)
);

CREATE TABLE eogp.venue_space_revisions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  venue_id        uuid NOT NULL,
  space_id        uuid NOT NULL,
  revision_no     integer NOT NULL CHECK (revision_no > 0),
  revision_hash   text NOT NULL CHECK (revision_hash ~ '^[0-9a-f]{64}$'),
  status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','approved','retired')),
  captured_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, space_id, id),
  UNIQUE (organization_id, space_id, revision_no),
  FOREIGN KEY (organization_id, venue_id, space_id)
    REFERENCES eogp.venue_spaces(organization_id, venue_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.floor_plan_assets (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  space_revision_id uuid NOT NULL,
  storage_key     text NOT NULL,
  media_type      text NOT NULL,
  sha256          text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  visibility      text NOT NULL DEFAULT 'staff' CHECK (visibility IN ('staff','operational','guest_safe')),
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (organization_id, space_revision_id)
    REFERENCES eogp.venue_space_revisions(organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, id)
);

CREATE TABLE eogp.spatial_layers (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  space_revision_id uuid NOT NULL,
  layer_code      text NOT NULL,
  name            text NOT NULL,
  visibility      text NOT NULL DEFAULT 'staff' CHECK (visibility IN ('staff','operational','guest_safe')),
  sort_order      integer NOT NULL DEFAULT 0,
  UNIQUE (organization_id, space_revision_id, id),
  UNIQUE (organization_id, space_revision_id, layer_code),
  FOREIGN KEY (organization_id, space_revision_id)
    REFERENCES eogp.venue_space_revisions(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.spatial_objects (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  space_revision_id uuid NOT NULL,
  layer_id        uuid NOT NULL,
  object_code     text,
  object_kind     text NOT NULL,
  geometry_json   jsonb NOT NULL,
  attributes_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (organization_id, space_revision_id, id),
  FOREIGN KEY (organization_id, space_revision_id)
    REFERENCES eogp.venue_space_revisions(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, space_revision_id, layer_id)
    REFERENCES eogp.spatial_layers(organization_id, space_revision_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.source_plan_artifacts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  venue_id        uuid NOT NULL,
  space_id        uuid,
  storage_key     text NOT NULL,
  source_type     text NOT NULL CHECK (source_type IN ('xlsx','pdf','image','svg','cad_export','other')),
  sha256          text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  uploaded_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (organization_id, venue_id)
    REFERENCES eogp.venues(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, venue_id, space_id)
    REFERENCES eogp.venue_spaces(organization_id, venue_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, id)
);

CREATE TABLE eogp.maintenance_windows (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  venue_space_id  uuid NOT NULL,
  starts_at       timestamptz NOT NULL,
  ends_at         timestamptz NOT NULL,
  reason_code     text NOT NULL,
  status          text NOT NULL DEFAULT 'active' CHECK (status IN ('active','cancelled','completed')),
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  CHECK (ends_at > starts_at),
  UNIQUE (organization_id, id),
  FOREIGN KEY (organization_id, venue_space_id)
    REFERENCES eogp.venue_spaces(organization_id, id) ON DELETE RESTRICT
);

ALTER TABLE eogp.user_role_grants
  ADD CONSTRAINT user_role_grants_venue_fk FOREIGN KEY (organization_id, scope_venue_id)
    REFERENCES eogp.venues(organization_id, id) ON DELETE RESTRICT,
  ADD CONSTRAINT user_role_grants_space_fk FOREIGN KEY (organization_id, scope_space_id)
    REFERENCES eogp.venue_spaces(organization_id, id) ON DELETE RESTRICT;

ALTER TABLE eogp.config_catalogues
  ADD CONSTRAINT config_catalogues_venue_fk FOREIGN KEY (organization_id, scope_venue_id)
    REFERENCES eogp.venues(organization_id, id) ON DELETE RESTRICT,
  ADD CONSTRAINT config_catalogues_space_fk FOREIGN KEY (organization_id, scope_space_id)
    REFERENCES eogp.venue_spaces(organization_id, id) ON DELETE RESTRICT;

ALTER TABLE eogp.booking_form_definitions
  ADD CONSTRAINT booking_forms_venue_fk FOREIGN KEY (organization_id, scope_venue_id)
    REFERENCES eogp.venues(organization_id, id) ON DELETE RESTRICT,
  ADD CONSTRAINT booking_forms_space_fk FOREIGN KEY (organization_id, scope_space_id)
    REFERENCES eogp.venue_spaces(organization_id, id) ON DELETE RESTRICT;

ALTER TABLE eogp.booking_price_lists
  ADD CONSTRAINT booking_price_lists_venue_fk FOREIGN KEY (organization_id, scope_venue_id)
    REFERENCES eogp.venues(organization_id, id) ON DELETE RESTRICT,
  ADD CONSTRAINT booking_price_lists_space_fk FOREIGN KEY (organization_id, scope_space_id)
    REFERENCES eogp.venue_spaces(organization_id, id) ON DELETE RESTRICT;

ALTER TABLE eogp.brand_profiles
  ADD CONSTRAINT brand_profiles_venue_fk FOREIGN KEY (organization_id, scope_venue_id)
    REFERENCES eogp.venues(organization_id, id) ON DELETE RESTRICT;

INSERT INTO eogp.schema_migrations(version, filename, checksum_sha256)
VALUES ('000004', '000004_venue_hierarchy.sql', :'migration_checksum');
COMMIT;
