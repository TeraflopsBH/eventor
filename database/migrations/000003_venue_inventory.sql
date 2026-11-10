-- Venue hierarchy, immutable spatial revisions, resource inventory and maintenance windows.
CREATE TABLE eogp.venues (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    code text NOT NULL,
    name text NOT NULL,
    timezone_name text NOT NULL DEFAULT 'Europe/Sarajevo',
    address jsonb NOT NULL DEFAULT '{}'::jsonb,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive','archived')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, code)
);

CREATE TABLE eogp.venue_buildings (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    venue_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, venue_id, id),
    UNIQUE (organization_id, venue_id, code),
    FOREIGN KEY (organization_id, venue_id) REFERENCES eogp.venues(organization_id, id)
);

CREATE TABLE eogp.venue_levels (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    building_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    sort_order integer NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, building_id, id),
    UNIQUE (organization_id, building_id, code),
    FOREIGN KEY (organization_id, building_id) REFERENCES eogp.venue_buildings(organization_id, id)
);

CREATE TABLE eogp.venue_spaces (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    venue_id uuid NOT NULL,
    building_id uuid,
    level_id uuid,
    parent_space_id uuid,
    code text NOT NULL,
    name text NOT NULL,
    space_kind text NOT NULL DEFAULT 'room'
      CHECK (space_kind IN ('building_area','level_area','room','zone','other')),
    capacity integer CHECK (capacity IS NULL OR capacity >= 0),
    area_square_metres numeric(12,2) CHECK (area_square_metres IS NULL OR area_square_metres >= 0),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive','archived')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, venue_id, id),
    UNIQUE (organization_id, venue_id, code),
    FOREIGN KEY (organization_id, venue_id) REFERENCES eogp.venues(organization_id, id),
    FOREIGN KEY (organization_id, venue_id, building_id)
      REFERENCES eogp.venue_buildings(organization_id, venue_id, id),
    FOREIGN KEY (organization_id, building_id, level_id)
      REFERENCES eogp.venue_levels(organization_id, building_id, id),
    FOREIGN KEY (organization_id, parent_space_id)
      REFERENCES eogp.venue_spaces(organization_id, id),
    CHECK (level_id IS NULL OR building_id IS NOT NULL)
);

CREATE TABLE eogp.venue_space_revisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    venue_space_id uuid NOT NULL,
    revision_number integer NOT NULL CHECK (revision_number > 0),
    source_kind text NOT NULL DEFAULT 'manual'
      CHECK (source_kind IN ('manual','imported','copied')),
    geometry jsonb NOT NULL DEFAULT '{}'::jsonb,
    semantic_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    content_sha256 text NOT NULL CHECK (content_sha256 ~ '^[0-9a-f]{64}$'),
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    created_by_membership_id uuid,
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, venue_space_id, id),
    UNIQUE (organization_id, venue_space_id, revision_number),
    FOREIGN KEY (organization_id, venue_space_id)
      REFERENCES eogp.venue_spaces(organization_id, id),
    FOREIGN KEY (organization_id, created_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);

CREATE TABLE eogp.floor_plan_assets (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    venue_space_revision_id uuid NOT NULL,
    storage_key text NOT NULL,
    media_type text NOT NULL,
    content_sha256 text NOT NULL CHECK (content_sha256 ~ '^[0-9a-f]{64}$'),
    byte_length bigint NOT NULL CHECK (byte_length >= 0),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, venue_space_revision_id)
      REFERENCES eogp.venue_space_revisions(organization_id, id)
);

CREATE TABLE eogp.spatial_layers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    venue_space_revision_id uuid NOT NULL,
    code text NOT NULL,
    label text NOT NULL,
    layer_kind text NOT NULL,
    visibility jsonb NOT NULL DEFAULT '{}'::jsonb,
    sort_order integer NOT NULL DEFAULT 0,
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, venue_space_revision_id, code),
    FOREIGN KEY (organization_id, venue_space_revision_id)
      REFERENCES eogp.venue_space_revisions(organization_id, id)
);

CREATE TABLE eogp.spatial_objects (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    layer_id uuid NOT NULL,
    object_kind text NOT NULL,
    stable_code text,
    geometry jsonb NOT NULL,
    attributes jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, layer_id)
      REFERENCES eogp.spatial_layers(organization_id, id)
);

CREATE TABLE eogp.resource_types (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    code text NOT NULL,
    name text NOT NULL,
    unit_label text NOT NULL DEFAULT 'unit',
    reservable boolean NOT NULL DEFAULT true,
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, code)
);

CREATE TABLE eogp.resource_pools (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    venue_id uuid NOT NULL,
    resource_type_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    capacity integer NOT NULL CHECK (capacity > 0),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive','retired')),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, venue_id, id),
    UNIQUE (organization_id, venue_id, code),
    FOREIGN KEY (organization_id, venue_id) REFERENCES eogp.venues(organization_id, id),
    FOREIGN KEY (organization_id, resource_type_id) REFERENCES eogp.resource_types(organization_id, id)
);

CREATE TABLE eogp.resource_units (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    resource_pool_id uuid NOT NULL,
    unit_code text NOT NULL,
    serial_reference text,
    status text NOT NULL DEFAULT 'available'
      CHECK (status IN ('available','maintenance','retired')),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, resource_pool_id, id),
    UNIQUE (organization_id, resource_pool_id, unit_code),
    FOREIGN KEY (organization_id, resource_pool_id)
      REFERENCES eogp.resource_pools(organization_id, id)
);

CREATE TABLE eogp.maintenance_windows (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    venue_space_id uuid,
    resource_unit_id uuid,
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    reason_code text NOT NULL,
    status text NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled','cancelled','completed')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    CHECK (ends_at > starts_at),
    CHECK (num_nonnulls(venue_space_id, resource_unit_id) = 1),
    FOREIGN KEY (organization_id, venue_space_id) REFERENCES eogp.venue_spaces(organization_id, id),
    FOREIGN KEY (organization_id, resource_unit_id) REFERENCES eogp.resource_units(organization_id, id)
);
CREATE INDEX maintenance_windows_space_time_idx
  ON eogp.maintenance_windows (organization_id, venue_space_id, starts_at, ends_at)
  WHERE status = 'scheduled';
