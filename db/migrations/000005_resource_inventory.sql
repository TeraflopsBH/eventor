-- Eventor migration 000005: 000005_resource_inventory.sql
-- Apply only through scripts/db/apply-migrations.sh so the checksum ledger is updated.
BEGIN;
SET LOCAL search_path TO eogp, public;

SET LOCAL search_path TO eogp, public;

CREATE TABLE eogp.resource_types (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id) ON DELETE RESTRICT,
  code            text NOT NULL,
  name            text NOT NULL,
  resource_kind   text NOT NULL CHECK (resource_kind IN ('equipment','personnel','furniture','service_capacity','other')),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, code)
);

CREATE TABLE eogp.resource_pools (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  venue_id        uuid NOT NULL,
  resource_type_id uuid NOT NULL,
  code            text NOT NULL,
  name            text NOT NULL,
  reservation_mode text NOT NULL CHECK (reservation_mode IN ('pooled','discrete')),
  capacity_quantity numeric(14,3) NOT NULL CHECK (capacity_quantity > 0),
  unit_code       text NOT NULL DEFAULT 'item',
  status          text NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive','retired')),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, code),
  FOREIGN KEY (organization_id, venue_id)
    REFERENCES eogp.venues(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, resource_type_id)
    REFERENCES eogp.resource_types(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.resource_units (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  resource_pool_id uuid NOT NULL,
  unit_code       text NOT NULL,
  display_name    text NOT NULL,
  status          text NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive','retired')),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, resource_pool_id, id),
  UNIQUE (organization_id, resource_pool_id, unit_code),
  FOREIGN KEY (organization_id, resource_pool_id)
    REFERENCES eogp.resource_pools(organization_id, id) ON DELETE RESTRICT
);

INSERT INTO eogp.schema_migrations(version, filename, checksum_sha256)
VALUES ('000005', '000005_resource_inventory.sql', :'migration_checksum');
COMMIT;
