-- Eventor migration 000003: 000003_configuration.sql
-- Apply only through scripts/db/apply-migrations.sh so the checksum ledger is updated.
BEGIN;
SET LOCAL search_path TO eogp, public;

SET LOCAL search_path TO eogp, public;

CREATE TABLE eogp.config_catalogues (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id) ON DELETE RESTRICT,
  code            text NOT NULL,
  name            text NOT NULL,
  scope_type      text NOT NULL DEFAULT 'organization'
                  CHECK (scope_type IN ('organization','venue','space','event')),
  scope_venue_id  uuid,
  scope_space_id  uuid,
  scope_event_id  uuid,
  status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','retired')),
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, code),
  CHECK (
    (scope_type='organization' AND num_nonnulls(scope_venue_id,scope_space_id,scope_event_id)=0)
    OR (scope_type='venue' AND num_nonnulls(scope_venue_id,scope_space_id,scope_event_id)=1 AND scope_venue_id IS NOT NULL)
    OR (scope_type='space' AND num_nonnulls(scope_venue_id,scope_space_id,scope_event_id)=1 AND scope_space_id IS NOT NULL)
    OR (scope_type='event' AND num_nonnulls(scope_venue_id,scope_space_id,scope_event_id)=1 AND scope_event_id IS NOT NULL)
  )
);

CREATE TABLE eogp.config_catalogue_revisions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  catalogue_id    uuid NOT NULL,
  revision_no     integer NOT NULL CHECK (revision_no > 0),
  status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','retired')),
  published_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, catalogue_id, id),
  UNIQUE (organization_id, catalogue_id, revision_no),
  FOREIGN KEY (organization_id, catalogue_id)
    REFERENCES eogp.config_catalogues(organization_id, id) ON DELETE RESTRICT,
  CHECK ((status='published') = (published_at IS NOT NULL))
);

CREATE TABLE eogp.config_catalogue_options (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  catalogue_id    uuid NOT NULL,
  stable_code     text NOT NULL,
  status          text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, catalogue_id, id),
  UNIQUE (organization_id, catalogue_id, stable_code),
  FOREIGN KEY (organization_id, catalogue_id)
    REFERENCES eogp.config_catalogues(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.config_catalogue_option_revisions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  catalogue_id    uuid NOT NULL,
  option_id       uuid NOT NULL,
  revision_no     integer NOT NULL CHECK (revision_no > 0),
  label_by_locale jsonb NOT NULL,
  value_json      jsonb NOT NULL DEFAULT '{}'::jsonb,
  status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','retired')),
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, catalogue_id, option_id, id),
  UNIQUE (organization_id, catalogue_id, option_id, revision_no),
  FOREIGN KEY (organization_id, catalogue_id, option_id)
    REFERENCES eogp.config_catalogue_options(organization_id, catalogue_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.config_catalogue_revision_options (
  organization_id       uuid NOT NULL,
  catalogue_id          uuid NOT NULL,
  catalogue_revision_id uuid NOT NULL,
  option_id             uuid NOT NULL,
  option_revision_id    uuid NOT NULL,
  sort_order            integer NOT NULL DEFAULT 0,
  PRIMARY KEY (organization_id, catalogue_revision_id, option_id),
  FOREIGN KEY (organization_id, catalogue_id, catalogue_revision_id)
    REFERENCES eogp.config_catalogue_revisions(organization_id, catalogue_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, catalogue_id, option_id, option_revision_id)
    REFERENCES eogp.config_catalogue_option_revisions(organization_id, catalogue_id, option_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.booking_form_definitions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id) ON DELETE RESTRICT,
  code            text NOT NULL,
  name            text NOT NULL,
  scope_type      text NOT NULL DEFAULT 'organization' CHECK (scope_type IN ('organization','venue','space')),
  scope_venue_id  uuid,
  scope_space_id  uuid,
  status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','retired')),
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, code),
  CHECK (
    (scope_type='organization' AND num_nonnulls(scope_venue_id,scope_space_id)=0)
    OR (scope_type='venue' AND num_nonnulls(scope_venue_id,scope_space_id)=1 AND scope_venue_id IS NOT NULL)
    OR (scope_type='space' AND num_nonnulls(scope_venue_id,scope_space_id)=1 AND scope_space_id IS NOT NULL)
  )
);

CREATE TABLE eogp.booking_form_revisions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  form_id         uuid NOT NULL,
  revision_no     integer NOT NULL CHECK (revision_no > 0),
  definition_json jsonb NOT NULL,
  status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','retired')),
  published_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, form_id, id),
  UNIQUE (organization_id, form_id, revision_no),
  UNIQUE (organization_id, id),
  FOREIGN KEY (organization_id, form_id)
    REFERENCES eogp.booking_form_definitions(organization_id, id) ON DELETE RESTRICT,
  CHECK ((status='published') = (published_at IS NOT NULL))
);

CREATE TABLE eogp.booking_form_catalogue_bindings (
  organization_id uuid NOT NULL,
  form_revision_id uuid NOT NULL,
  catalogue_id    uuid NOT NULL,
  catalogue_revision_id uuid NOT NULL,
  field_code      text NOT NULL,
  PRIMARY KEY (organization_id, form_revision_id, field_code),
  FOREIGN KEY (organization_id, form_revision_id)
    REFERENCES eogp.booking_form_revisions(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, catalogue_id, catalogue_revision_id)
    REFERENCES eogp.config_catalogue_revisions(organization_id, catalogue_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.booking_price_lists (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id) ON DELETE RESTRICT,
  code            text NOT NULL,
  name            text NOT NULL,
  scope_type      text NOT NULL DEFAULT 'organization' CHECK (scope_type IN ('organization','venue','space')),
  scope_venue_id  uuid,
  scope_space_id  uuid,
  status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','retired')),
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, code),
  CHECK (
    (scope_type='organization' AND num_nonnulls(scope_venue_id,scope_space_id)=0)
    OR (scope_type='venue' AND num_nonnulls(scope_venue_id,scope_space_id)=1 AND scope_venue_id IS NOT NULL)
    OR (scope_type='space' AND num_nonnulls(scope_venue_id,scope_space_id)=1 AND scope_space_id IS NOT NULL)
  )
);

CREATE TABLE eogp.booking_price_list_revisions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  price_list_id   uuid NOT NULL,
  revision_no     integer NOT NULL CHECK (revision_no > 0),
  currency        char(3) NOT NULL,
  tax_basis       text NOT NULL CHECK (tax_basis IN ('inclusive','exclusive','not_applicable','to_be_confirmed')),
  status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','retired')),
  published_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, price_list_id, id),
  UNIQUE (organization_id, price_list_id, revision_no),
  FOREIGN KEY (organization_id, price_list_id)
    REFERENCES eogp.booking_price_lists(organization_id, id) ON DELETE RESTRICT,
  CHECK ((status='published') = (published_at IS NOT NULL))
);

CREATE TABLE eogp.booking_price_items (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  price_list_id   uuid NOT NULL,
  price_revision_id uuid NOT NULL,
  item_code       text NOT NULL,
  label_by_locale jsonb NOT NULL,
  unit_price      numeric(14,2) NOT NULL CHECK (unit_price >= 0),
  unit_code       text NOT NULL DEFAULT 'item',
  active          boolean NOT NULL DEFAULT true,
  UNIQUE (organization_id, price_revision_id, item_code),
  FOREIGN KEY (organization_id, price_list_id, price_revision_id)
    REFERENCES eogp.booking_price_list_revisions(organization_id, price_list_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.brand_profiles (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id) ON DELETE RESTRICT,
  scope_type      text NOT NULL CHECK (scope_type IN ('organization','venue','event')),
  scope_venue_id  uuid,
  scope_event_id  uuid,
  status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','retired')),
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  CHECK (
    (scope_type='organization' AND num_nonnulls(scope_venue_id,scope_event_id)=0)
    OR (scope_type='venue' AND num_nonnulls(scope_venue_id,scope_event_id)=1 AND scope_venue_id IS NOT NULL)
    OR (scope_type='event' AND num_nonnulls(scope_venue_id,scope_event_id)=1 AND scope_event_id IS NOT NULL)
  )
);

CREATE TABLE eogp.brand_profile_revisions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  brand_profile_id uuid NOT NULL,
  revision_no     integer NOT NULL CHECK (revision_no > 0),
  tokens_json     jsonb NOT NULL,
  published_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, brand_profile_id, id),
  UNIQUE (organization_id, brand_profile_id, revision_no),
  FOREIGN KEY (organization_id, brand_profile_id)
    REFERENCES eogp.brand_profiles(organization_id, id) ON DELETE RESTRICT
);

INSERT INTO eogp.schema_migrations(version, filename, checksum_sha256)
VALUES ('000003', '000003_configuration.sql', :'migration_checksum');
COMMIT;
