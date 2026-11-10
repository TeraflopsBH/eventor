-- Event Operations & Guest Logistics Platform
-- PostgreSQL schema starter/reference v0.1
-- Derived from Implementation Design v0.1 (10 Nov 2026).
-- NOT a production-ready migration. Review every constraint, index, retention rule,
-- role, RLS policy and data classification before deployment.

BEGIN;
CREATE SCHEMA IF NOT EXISTS eogp;
SET search_path = eogp, public;

-- Shared convention: every tenant-owned row has organization_id.
-- IDs are UUIDs. Display codes/labels are not primary keys.

CREATE TABLE organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug text NOT NULL UNIQUE,
  display_name text NOT NULL,
  legal_name text,
  timezone text NOT NULL DEFAULT 'Europe/Sarajevo',
  default_locale text NOT NULL DEFAULT 'bs-BA',
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','archived')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email_normalized text NOT NULL UNIQUE,
  display_name text NOT NULL,
  password_hash text,
  identity_provider text,
  identity_subject text,
  account_status text NOT NULL DEFAULT 'active' CHECK (account_status IN ('invited','active','locked','disabled')),
  mfa_required boolean NOT NULL DEFAULT false,
  last_login_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK ((password_hash IS NOT NULL) OR (identity_provider IS NOT NULL AND identity_subject IS NOT NULL))
);

CREATE TABLE organization_memberships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  user_id uuid NOT NULL REFERENCES users(id),
  membership_status text NOT NULL DEFAULT 'active' CHECK (membership_status IN ('invited','active','suspended','revoked')),
  joined_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, user_id),
  UNIQUE (organization_id, id)
);

CREATE TABLE roles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  code text NOT NULL,
  name text NOT NULL,
  description text,
  scope_type text NOT NULL DEFAULT 'organization' CHECK (scope_type IN ('organization','event','venue','space','station')),
  is_system_role boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, code),
  UNIQUE (organization_id, id)
);

CREATE TABLE permissions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  description text NOT NULL
);

CREATE TABLE role_permissions (
  role_id uuid NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  permission_id uuid NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE user_role_grants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  membership_id uuid NOT NULL,
  role_id uuid NOT NULL,
  scope_type text NOT NULL DEFAULT 'organization' CHECK (scope_type IN ('organization','event','venue','space','station')),
  scope_id uuid,
  granted_by uuid REFERENCES users(id),
  granted_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  FOREIGN KEY (organization_id, membership_id) REFERENCES organization_memberships(organization_id, id),
  FOREIGN KEY (organization_id, role_id) REFERENCES roles(organization_id, id),
  CHECK ((scope_type = 'organization' AND scope_id IS NULL) OR (scope_type <> 'organization' AND scope_id IS NOT NULL))
);
CREATE INDEX user_role_grants_scope_idx ON user_role_grants(organization_id, scope_type, scope_id) WHERE revoked_at IS NULL;

-- Branding: scope_id is polymorphic by scope_type; the service validates the referenced entity.
CREATE TABLE brand_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  scope_type text NOT NULL CHECK (scope_type IN ('organization','venue','event')),
  scope_id uuid NOT NULL,
  code text NOT NULL,
  display_name text NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('draft','active','archived')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, scope_type, scope_id, code),
  UNIQUE (organization_id, id)
);

CREATE TABLE brand_profile_revisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  brand_profile_id uuid NOT NULL,
  revision_no integer NOT NULL CHECK (revision_no > 0),
  tokens jsonb NOT NULL DEFAULT '{}'::jsonb,
  asset_bindings jsonb NOT NULL DEFAULT '{}'::jsonb,
  accessibility_checks jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','superseded')),
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz,
  FOREIGN KEY (organization_id, brand_profile_id) REFERENCES brand_profiles(organization_id, id),
  UNIQUE (brand_profile_id, revision_no),
  UNIQUE (organization_id, id)
);

CREATE TABLE brand_assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  asset_code text NOT NULL,
  display_name text NOT NULL,
  media_type text NOT NULL,
  storage_key text NOT NULL,
  sha256_hex char(64) NOT NULL,
  classification text NOT NULL DEFAULT 'internal' CHECK (classification IN ('public','internal','confidential','restricted')),
  is_guest_public boolean NOT NULL DEFAULT false,
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, asset_code),
  UNIQUE (organization_id, id)
);

CREATE TABLE document_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  code text NOT NULL,
  template_type text NOT NULL CHECK (template_type IN ('invitation','guest_card','qr_pass','seating_plan','signage','report','email')),
  display_name text NOT NULL,
  scope_type text NOT NULL DEFAULT 'organization' CHECK (scope_type IN ('organization','venue','event')),
  scope_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('draft','active','archived')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, scope_type, scope_id, code),
  UNIQUE (organization_id, id)
);

CREATE TABLE document_template_revisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  template_id uuid NOT NULL,
  revision_no integer NOT NULL CHECK (revision_no > 0),
  template_source text NOT NULL,
  supported_fields jsonb NOT NULL DEFAULT '[]'::jsonb,
  render_options jsonb NOT NULL DEFAULT '{}'::jsonb,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','superseded')),
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  published_at timestamptz,
  FOREIGN KEY (organization_id, template_id) REFERENCES document_templates(organization_id, id),
  UNIQUE (template_id, revision_no),
  UNIQUE (organization_id, id)
);

-- Venue hierarchy and immutable space revisions.
CREATE TABLE venues (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  code text NOT NULL,
  name text NOT NULL,
  description text,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive','archived')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, code),
  UNIQUE (organization_id, id)
);

CREATE TABLE venue_buildings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  venue_id uuid NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  sort_order integer NOT NULL DEFAULT 0,
  FOREIGN KEY (organization_id, venue_id) REFERENCES venues(organization_id, id),
  UNIQUE (venue_id, code),
  UNIQUE (organization_id, id)
);

CREATE TABLE venue_levels (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  building_id uuid NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  level_order integer NOT NULL DEFAULT 0,
  FOREIGN KEY (organization_id, building_id) REFERENCES venue_buildings(organization_id, id),
  UNIQUE (building_id, code),
  UNIQUE (organization_id, id)
);

CREATE TABLE venue_spaces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  venue_id uuid NOT NULL,
  building_id uuid,
  level_id uuid,
  code text NOT NULL,
  name text NOT NULL,
  space_type text NOT NULL CHECK (space_type IN ('hall','mosque','auditorium','meeting_room','outdoor','reception','other')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive','archived')),
  default_allocation_mode text NOT NULL DEFAULT 'zone_capacity' CHECK (default_allocation_mode IN ('individual_seat','numbered_floor_position','row_or_segment','zone_capacity','unassigned_open')),
  description text,
  FOREIGN KEY (organization_id, venue_id) REFERENCES venues(organization_id, id),
  FOREIGN KEY (organization_id, building_id) REFERENCES venue_buildings(organization_id, id),
  FOREIGN KEY (organization_id, level_id) REFERENCES venue_levels(organization_id, id),
  UNIQUE (venue_id, code),
  UNIQUE (organization_id, id)
);

CREATE TABLE venue_space_revisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  venue_space_id uuid NOT NULL,
  revision_no integer NOT NULL CHECK (revision_no > 0),
  coordinate_system text NOT NULL DEFAULT 'svg_viewbox_10000',
  viewbox_width integer NOT NULL DEFAULT 10000 CHECK (viewbox_width > 0),
  viewbox_height integer NOT NULL DEFAULT 10000 CHECK (viewbox_height > 0),
  physical_width_mm integer CHECK (physical_width_mm > 0),
  physical_height_mm integer CHECK (physical_height_mm > 0),
  orientation_degrees numeric(7,3) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','in_review','approved','superseded','archived')),
  capacity_status text NOT NULL DEFAULT 'unconfirmed' CHECK (capacity_status IN ('unconfirmed','partially_confirmed','confirmed')),
  approved_by uuid REFERENCES users(id),
  approved_at timestamptz,
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  notes text,
  FOREIGN KEY (organization_id, venue_space_id) REFERENCES venue_spaces(organization_id, id),
  UNIQUE (venue_space_id, revision_no),
  UNIQUE (organization_id, id)
);

CREATE TABLE floor_plan_assets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  space_revision_id uuid NOT NULL,
  asset_kind text NOT NULL CHECK (asset_kind IN ('background_pdf','background_image','background_svg','rendered_source','legend','other')),
  storage_key text NOT NULL,
  media_type text NOT NULL,
  sha256_hex char(64) NOT NULL,
  layer_order integer NOT NULL DEFAULT 0,
  is_locked boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, space_revision_id) REFERENCES venue_space_revisions(organization_id, id),
  UNIQUE (organization_id, id)
);

CREATE TABLE spatial_layers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  space_revision_id uuid NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  audience text NOT NULL DEFAULT 'staff' CHECK (audience IN ('public','guest','staff','management','restricted')),
  z_index integer NOT NULL DEFAULT 0,
  visible_by_default boolean NOT NULL DEFAULT true,
  style_defaults jsonb NOT NULL DEFAULT '{}'::jsonb,
  FOREIGN KEY (organization_id, space_revision_id) REFERENCES venue_space_revisions(organization_id, id),
  UNIQUE (space_revision_id, code),
  UNIQUE (organization_id, id)
);

CREATE TABLE spatial_objects (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  space_revision_id uuid NOT NULL,
  layer_id uuid,
  parent_object_id uuid,
  object_type text NOT NULL CHECK (object_type IN ('space_boundary','region','feature','row','row_segment','table','seat','floor_position','label','path','symbol','other')),
  code text,
  display_label text,
  geometry jsonb NOT NULL,
  transform jsonb NOT NULL DEFAULT '{}'::jsonb,
  style jsonb NOT NULL DEFAULT '{}'::jsonb,
  properties jsonb NOT NULL DEFAULT '{}'::jsonb,
  visibility text NOT NULL DEFAULT 'staff' CHECK (visibility IN ('public','guest','staff','management','restricted')),
  source_reference jsonb,
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, space_revision_id) REFERENCES venue_space_revisions(organization_id, id),
  FOREIGN KEY (organization_id, layer_id) REFERENCES spatial_layers(organization_id, id),
  FOREIGN KEY (organization_id, parent_object_id) REFERENCES spatial_objects(organization_id, id),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, space_revision_id, id)
);
CREATE INDEX spatial_objects_revision_type_idx ON spatial_objects(space_revision_id, object_type);
CREATE INDEX spatial_objects_geometry_gin_idx ON spatial_objects USING gin (geometry jsonb_path_ops);

CREATE TABLE allocation_resources (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  space_revision_id uuid NOT NULL,
  spatial_object_id uuid,
  parent_resource_id uuid,
  resource_type text NOT NULL CHECK (resource_type IN ('chair_seat','fixed_seat','floor_position','row_segment','table_position','other')),
  numbering_scope_key text NOT NULL,
  local_code text NOT NULL,
  display_label text NOT NULL,
  ordinal_in_scope integer,
  capacity integer NOT NULL DEFAULT 1 CHECK (capacity > 0),
  allocation_mode text NOT NULL CHECK (allocation_mode IN ('individual_seat','numbered_floor_position','row_or_segment')),
  status text NOT NULL DEFAULT 'available' CHECK (status IN ('available','reserved','blocked','disabled')),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  FOREIGN KEY (organization_id, space_revision_id) REFERENCES venue_space_revisions(organization_id, id),
  FOREIGN KEY (organization_id, space_revision_id, spatial_object_id) REFERENCES spatial_objects(organization_id, space_revision_id, id),
  FOREIGN KEY (organization_id, parent_resource_id) REFERENCES allocation_resources(organization_id, id),
  UNIQUE (space_revision_id, numbering_scope_key, local_code),
  UNIQUE (organization_id, id)
);
CREATE INDEX allocation_resources_scope_idx ON allocation_resources(space_revision_id, numbering_scope_key, ordinal_in_scope);

CREATE TABLE capacity_pools (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  space_revision_id uuid NOT NULL,
  spatial_object_id uuid NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  approved_capacity integer NOT NULL CHECK (approved_capacity >= 0),
  reserved_capacity integer NOT NULL DEFAULT 0 CHECK (reserved_capacity >= 0),
  approval_status text NOT NULL DEFAULT 'unconfirmed' CHECK (approval_status IN ('unconfirmed','approved','suspended')),
  approved_by uuid REFERENCES users(id),
  approved_at timestamptz,
  capacity_basis text,
  FOREIGN KEY (organization_id, space_revision_id) REFERENCES venue_space_revisions(organization_id, id),
  FOREIGN KEY (organization_id, space_revision_id, spatial_object_id) REFERENCES spatial_objects(organization_id, space_revision_id, id),
  CHECK (reserved_capacity <= approved_capacity),
  UNIQUE (space_revision_id, code),
  UNIQUE (organization_id, id)
);

CREATE TABLE source_plan_artifacts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  venue_space_id uuid NOT NULL,
  file_name text NOT NULL,
  media_type text NOT NULL,
  storage_key text NOT NULL,
  sha256_hex char(64) NOT NULL,
  source_type text NOT NULL CHECK (source_type IN ('xlsx','pdf','image','svg','cad_export','other')),
  sheet_names jsonb NOT NULL DEFAULT '[]'::jsonb,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  uploaded_by uuid REFERENCES users(id),
  uploaded_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, venue_space_id) REFERENCES venue_spaces(organization_id, id),
  UNIQUE (organization_id, id)
);

CREATE TABLE source_plan_mappings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  source_artifact_id uuid NOT NULL,
  target_space_revision_id uuid NOT NULL,
  target_spatial_object_id uuid,
  source_sheet text,
  source_range text,
  source_label text,
  mapping_type text NOT NULL CHECK (mapping_type IN ('region','feature','row','resource','capacity_annotation','label','unresolved')),
  extraction_method text NOT NULL DEFAULT 'manual' CHECK (extraction_method IN ('manual','cell_metadata','computer_vision','import_suggestion')),
  review_status text NOT NULL DEFAULT 'pending' CHECK (review_status IN ('pending','accepted','rejected','needs_clarification')),
  reviewed_by uuid REFERENCES users(id),
  reviewed_at timestamptz,
  notes text,
  FOREIGN KEY (organization_id, source_artifact_id) REFERENCES source_plan_artifacts(organization_id, id),
  FOREIGN KEY (organization_id, target_space_revision_id) REFERENCES venue_space_revisions(organization_id, id),
  FOREIGN KEY (organization_id, target_spatial_object_id) REFERENCES spatial_objects(organization_id, id),
  UNIQUE (organization_id, id)
);

-- Events, sessions and event-specific spaces.
CREATE TABLE events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  code text NOT NULL,
  name text NOT NULL,
  event_type text NOT NULL DEFAULT 'other',
  timezone text NOT NULL DEFAULT 'Europe/Sarajevo',
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  lifecycle_state text NOT NULL DEFAULT 'draft' CHECK (lifecycle_state IN ('draft','planning','ready','live','completed','cancelled','archived')),
  guest_portal_enabled boolean NOT NULL DEFAULT false,
  checkin_enabled boolean NOT NULL DEFAULT true,
  settings jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at > starts_at),
  UNIQUE (organization_id, code),
  UNIQUE (organization_id, id)
);

CREATE TABLE event_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'planned' CHECK (status IN ('planned','open','closed','cancelled')),
  allocation_policy jsonb NOT NULL DEFAULT '{}'::jsonb,
  FOREIGN KEY (organization_id, event_id) REFERENCES events(organization_id, id),
  CHECK (ends_at > starts_at),
  UNIQUE (event_id, code),
  UNIQUE (organization_id, id)
);

CREATE TABLE event_session_spaces (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  session_id uuid NOT NULL,
  space_revision_id uuid NOT NULL,
  usage_type text NOT NULL DEFAULT 'primary' CHECK (usage_type IN ('primary','overflow','reception','route','other')),
  display_order integer NOT NULL DEFAULT 0,
  FOREIGN KEY (organization_id, session_id) REFERENCES event_sessions(organization_id, id),
  FOREIGN KEY (organization_id, space_revision_id) REFERENCES venue_space_revisions(organization_id, id),
  UNIQUE (session_id, space_revision_id),
  UNIQUE (organization_id, id)
);

-- Persistent person registry and event membership.
CREATE TABLE persons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  person_code text NOT NULL,
  given_name text NOT NULL,
  family_name text NOT NULL,
  display_name text NOT NULL,
  title text,
  organization_name text,
  position_title text,
  preferred_locale text,
  profile_status text NOT NULL DEFAULT 'active' CHECK (profile_status IN ('active','inactive','archived','merged')),
  data_classification text NOT NULL DEFAULT 'personal' CHECK (data_classification IN ('public','internal','personal','confidential','restricted')),
  merged_into_person_id uuid REFERENCES persons(id),
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, person_code),
  UNIQUE (organization_id, id)
);

CREATE TABLE person_contact_points (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  person_id uuid NOT NULL,
  contact_type text NOT NULL CHECK (contact_type IN ('email','phone','address','other')),
  value_display text NOT NULL,
  value_normalized text,
  is_primary boolean NOT NULL DEFAULT false,
  visibility text NOT NULL DEFAULT 'confidential' CHECK (visibility IN ('internal','confidential','restricted')),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, person_id) REFERENCES persons(organization_id, id),
  UNIQUE (organization_id, id)
);
CREATE INDEX person_contact_lookup_idx ON person_contact_points(organization_id, contact_type, value_normalized);

CREATE TABLE person_identifiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  person_id uuid NOT NULL,
  identifier_type text NOT NULL,
  identifier_value_normalized text NOT NULL,
  issuer text,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, person_id) REFERENCES persons(organization_id, id),
  UNIQUE (organization_id, identifier_type, issuer, identifier_value_normalized),
  UNIQUE (organization_id, id)
);

CREATE TABLE guest_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  code text NOT NULL,
  name text NOT NULL,
  description text,
  default_priority integer NOT NULL DEFAULT 0,
  default_color text,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','inactive')),
  UNIQUE (organization_id, code),
  UNIQUE (organization_id, id)
);

CREATE TABLE event_guests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid NOT NULL,
  person_id uuid NOT NULL,
  event_guest_code text NOT NULL,
  category_id uuid,
  rsvp_status text NOT NULL DEFAULT 'pending' CHECK (rsvp_status IN ('pending','invited','confirmed','declined','waitlisted','not_required')),
  participation_status text NOT NULL DEFAULT 'active' CHECK (participation_status IN ('active','cancelled','archived')),
  display_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  event_fields jsonb NOT NULL DEFAULT '{}'::jsonb,
  added_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, event_id) REFERENCES events(organization_id, id),
  FOREIGN KEY (organization_id, person_id) REFERENCES persons(organization_id, id),
  FOREIGN KEY (organization_id, category_id) REFERENCES guest_categories(organization_id, id),
  UNIQUE (event_id, person_id),
  UNIQUE (event_id, event_guest_code),
  UNIQUE (organization_id, id)
);
CREATE INDEX event_guests_event_status_idx ON event_guests(event_id, rsvp_status, participation_status);

CREATE TABLE guest_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid,
  code text NOT NULL,
  name text NOT NULL,
  group_type text NOT NULL DEFAULT 'custom' CHECK (group_type IN ('family','delegation','organization','team','table_party','custom')),
  placement_policy jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, event_id) REFERENCES events(organization_id, id),
  UNIQUE (organization_id, id)
);

CREATE TABLE event_guest_group_members (
  organization_id uuid NOT NULL,
  group_id uuid NOT NULL,
  event_guest_id uuid NOT NULL,
  member_role text,
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, event_guest_id),
  FOREIGN KEY (organization_id, group_id) REFERENCES guest_groups(organization_id, id),
  FOREIGN KEY (organization_id, event_guest_id) REFERENCES event_guests(organization_id, id)
);

CREATE TABLE guest_relationships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid NOT NULL,
  source_event_guest_id uuid NOT NULL,
  target_event_guest_id uuid NOT NULL,
  relation_type text NOT NULL CHECK (relation_type IN ('must_together','prefer_together','must_not_share','prefer_apart','assistant_of','family_of','other')),
  scope_type text CHECK (scope_type IN ('same_table','same_row','same_zone','same_room','same_building','minimum_distance','same_session')),
  minimum_distance_units integer,
  severity text NOT NULL DEFAULT 'soft' CHECK (severity IN ('hard','soft')),
  weight integer NOT NULL DEFAULT 50 CHECK (weight >= 0),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, event_id) REFERENCES events(organization_id, id),
  FOREIGN KEY (organization_id, source_event_guest_id) REFERENCES event_guests(organization_id, id),
  FOREIGN KEY (organization_id, target_event_guest_id) REFERENCES event_guests(organization_id, id),
  CHECK (source_event_guest_id <> target_event_guest_id),
  CHECK ((scope_type = 'minimum_distance' AND minimum_distance_units IS NOT NULL) OR scope_type <> 'minimum_distance'),
  UNIQUE (organization_id, id)
);

CREATE TABLE guest_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_guest_id uuid NOT NULL,
  note_text text NOT NULL,
  classification text NOT NULL DEFAULT 'confidential' CHECK (classification IN ('internal','confidential','restricted')),
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, event_guest_id) REFERENCES event_guests(organization_id, id),
  UNIQUE (organization_id, id)
);

CREATE TABLE guest_import_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid NOT NULL,
  source_file_key text NOT NULL,
  source_sha256 char(64) NOT NULL,
  field_mapping jsonb NOT NULL,
  status text NOT NULL DEFAULT 'uploaded' CHECK (status IN ('uploaded','parsing','preview','committing','completed','failed','cancelled')),
  summary jsonb NOT NULL DEFAULT '{}'::jsonb,
  uploaded_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  FOREIGN KEY (organization_id, event_id) REFERENCES events(organization_id, id),
  UNIQUE (organization_id, id)
);

CREATE TABLE guest_import_rows (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  batch_id uuid NOT NULL,
  source_row_number integer NOT NULL,
  raw_data jsonb NOT NULL,
  normalized_data jsonb NOT NULL DEFAULT '{}'::jsonb,
  validation_errors jsonb NOT NULL DEFAULT '[]'::jsonb,
  duplicate_candidates jsonb NOT NULL DEFAULT '[]'::jsonb,
  resolution text NOT NULL DEFAULT 'pending' CHECK (resolution IN ('pending','create_new','link_existing','skip','merged')),
  resolved_person_id uuid,
  FOREIGN KEY (organization_id, batch_id) REFERENCES guest_import_batches(organization_id, id),
  FOREIGN KEY (organization_id, resolved_person_id) REFERENCES persons(organization_id, id),
  UNIQUE (batch_id, source_row_number)
);

-- Configurable tags and custom fields are normalized so the Registry does not become an opaque JSON store.
CREATE TABLE guest_custom_field_definitions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  field_key text NOT NULL,
  display_name text NOT NULL,
  applies_to text NOT NULL CHECK (applies_to IN ('person','event_guest')) ,
  value_type text NOT NULL CHECK (value_type IN ('text','number','boolean','date','enum','multi_enum')) ,
  classification text NOT NULL DEFAULT 'internal' CHECK (classification IN ('public','internal','personal','confidential','restricted')) ,
  options jsonb NOT NULL DEFAULT '[]'::jsonb,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (organization_id, field_key),
  UNIQUE (organization_id, id)
);

CREATE TABLE guest_custom_field_values (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  definition_id uuid NOT NULL,
  person_id uuid,
  event_guest_id uuid,
  value_json jsonb NOT NULL,
  updated_by uuid REFERENCES users(id),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, definition_id) REFERENCES guest_custom_field_definitions(organization_id, id),
  FOREIGN KEY (organization_id, person_id) REFERENCES persons(organization_id, id),
  FOREIGN KEY (organization_id, event_guest_id) REFERENCES event_guests(organization_id, id),
  CHECK ((person_id IS NOT NULL) <> (event_guest_id IS NOT NULL)),
  UNIQUE (definition_id, person_id),
  UNIQUE (definition_id, event_guest_id)
);

CREATE TABLE guest_tags (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  code text NOT NULL,
  label text NOT NULL,
  color text,
  UNIQUE (organization_id, code),
  UNIQUE (organization_id, id)
);

CREATE TABLE event_guest_tags (
  organization_id uuid NOT NULL,
  event_guest_id uuid NOT NULL,
  tag_id uuid NOT NULL,
  assigned_by uuid REFERENCES users(id),
  assigned_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (event_guest_id, tag_id),
  FOREIGN KEY (organization_id, event_guest_id) REFERENCES event_guests(organization_id, id),
  FOREIGN KEY (organization_id, tag_id) REFERENCES guest_tags(organization_id, id)
);

CREATE TABLE event_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid NOT NULL,
  from_state text,
  to_state text NOT NULL,
  changed_by uuid REFERENCES users(id),
  changed_at timestamptz NOT NULL DEFAULT now(),
  reason text,
  FOREIGN KEY (organization_id, event_id) REFERENCES events(organization_id, id)
);

-- Allocation rules, solver runs and versioned assignments.
CREATE TABLE allocation_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid NOT NULL,
  session_id uuid,
  code text NOT NULL,
  name text NOT NULL,
  rule_type text NOT NULL CHECK (rule_type IN ('must_together','prefer_together','must_not_share','prefer_apart','category_distribution','zone_preference','accessibility','capacity','manual_lock','custom')),
  severity text NOT NULL DEFAULT 'soft' CHECK (severity IN ('hard','soft')),
  scope_type text CHECK (scope_type IN ('seat','table','row','zone','room','building','distance','session')),
  weight integer NOT NULL DEFAULT 50 CHECK (weight >= 0),
  subject_selector jsonb NOT NULL DEFAULT '{}'::jsonb,
  target_selector jsonb NOT NULL DEFAULT '{}'::jsonb,
  configuration jsonb NOT NULL DEFAULT '{}'::jsonb,
  enabled boolean NOT NULL DEFAULT true,
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, event_id) REFERENCES events(organization_id, id),
  FOREIGN KEY (organization_id, session_id) REFERENCES event_sessions(organization_id, id),
  UNIQUE (event_id, code),
  UNIQUE (organization_id, id)
);

CREATE TABLE allocation_revisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid NOT NULL,
  session_id uuid NOT NULL,
  revision_no integer NOT NULL CHECK (revision_no > 0),
  based_on_revision_id uuid,
  source_run_id uuid,
  status text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','proposed','in_review','approved','published','superseded','rejected')),
  snapshot_sha256 char(64),
  change_reason text,
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  approved_by uuid REFERENCES users(id),
  approved_at timestamptz,
  published_at timestamptz,
  FOREIGN KEY (organization_id, event_id) REFERENCES events(organization_id, id),
  FOREIGN KEY (organization_id, session_id) REFERENCES event_sessions(organization_id, id),
  FOREIGN KEY (organization_id, based_on_revision_id) REFERENCES allocation_revisions(organization_id, id),
  UNIQUE (session_id, revision_no),
  UNIQUE (organization_id, id)
);

CREATE TABLE allocation_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid NOT NULL,
  session_id uuid NOT NULL,
  source_revision_id uuid,
  requested_by uuid REFERENCES users(id),
  run_mode text NOT NULL CHECK (run_mode IN ('full','category','targeted_reflow','manual_validation','what_if')),
  scope_snapshot jsonb NOT NULL,
  rule_snapshot jsonb NOT NULL,
  input_sha256 char(64) NOT NULL,
  solver_name text NOT NULL DEFAULT 'ortools-cp-sat',
  solver_version text,
  solver_parameters jsonb NOT NULL DEFAULT '{}'::jsonb,
  solver_status text NOT NULL DEFAULT 'queued' CHECK (solver_status IN ('queued','running','optimal','feasible','infeasible','model_invalid','unknown','failed','cancelled')),
  objective_values jsonb NOT NULL DEFAULT '{}'::jsonb,
  diagnostics jsonb NOT NULL DEFAULT '{}'::jsonb,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, event_id) REFERENCES events(organization_id, id),
  FOREIGN KEY (organization_id, session_id) REFERENCES event_sessions(organization_id, id),
  FOREIGN KEY (organization_id, source_revision_id) REFERENCES allocation_revisions(organization_id, id),
  UNIQUE (organization_id, id)
);

ALTER TABLE allocation_revisions
  ADD CONSTRAINT allocation_revisions_source_run_fk
  FOREIGN KEY (organization_id, source_run_id) REFERENCES allocation_runs(organization_id, id);

CREATE TABLE guest_allocations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  allocation_revision_id uuid NOT NULL,
  event_guest_id uuid NOT NULL,
  session_id uuid NOT NULL,
  allocation_resource_id uuid,
  capacity_pool_id uuid,
  assignment_kind text NOT NULL CHECK (assignment_kind IN ('seat','floor_position','row_segment','zone_capacity','open_admission')),
  target_ordinal integer,
  locked boolean NOT NULL DEFAULT false,
  assignment_source text NOT NULL DEFAULT 'manual' CHECK (assignment_source IN ('manual','solver','import','migration')),
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, allocation_revision_id) REFERENCES allocation_revisions(organization_id, id),
  FOREIGN KEY (organization_id, event_guest_id) REFERENCES event_guests(organization_id, id),
  FOREIGN KEY (organization_id, session_id) REFERENCES event_sessions(organization_id, id),
  FOREIGN KEY (organization_id, allocation_resource_id) REFERENCES allocation_resources(organization_id, id),
  FOREIGN KEY (organization_id, capacity_pool_id) REFERENCES capacity_pools(organization_id, id),
  CHECK ((allocation_resource_id IS NOT NULL) <> (capacity_pool_id IS NOT NULL)),
  UNIQUE (allocation_revision_id, event_guest_id),
  UNIQUE (organization_id, id)
);
CREATE INDEX guest_allocations_target_idx ON guest_allocations(allocation_revision_id, allocation_resource_id) WHERE allocation_resource_id IS NOT NULL;
CREATE INDEX guest_allocations_pool_idx ON guest_allocations(allocation_revision_id, capacity_pool_id) WHERE capacity_pool_id IS NOT NULL;

CREATE TABLE allocation_locks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  allocation_revision_id uuid NOT NULL,
  lock_target_type text NOT NULL CHECK (lock_target_type IN ('event_guest','group','resource','row','region')),
  lock_target_id uuid NOT NULL,
  lock_reason text,
  locked_by uuid REFERENCES users(id),
  locked_at timestamptz NOT NULL DEFAULT now(),
  unlocked_by uuid REFERENCES users(id),
  unlocked_at timestamptz,
  FOREIGN KEY (organization_id, allocation_revision_id) REFERENCES allocation_revisions(organization_id, id),
  UNIQUE (organization_id, id)
);

CREATE TABLE plan_approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  allocation_revision_id uuid NOT NULL,
  approver_id uuid NOT NULL REFERENCES users(id),
  decision text NOT NULL CHECK (decision IN ('approved','rejected','returned_for_changes')),
  comment text,
  decided_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, allocation_revision_id) REFERENCES allocation_revisions(organization_id, id),
  UNIQUE (allocation_revision_id, approver_id)
);

CREATE TABLE plan_publications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  allocation_revision_id uuid NOT NULL,
  audience text NOT NULL CHECK (audience IN ('staff','guest','print','management')),
  status text NOT NULL DEFAULT 'published' CHECK (status IN ('published','superseded','withdrawn')),
  published_by uuid REFERENCES users(id),
  published_at timestamptz NOT NULL DEFAULT now(),
  superseded_at timestamptz,
  FOREIGN KEY (organization_id, allocation_revision_id) REFERENCES allocation_revisions(organization_id, id),
  UNIQUE (organization_id, id)
);

-- Brand snapshot is resolved at event/artifact level and immutable after publication.
CREATE TABLE event_brand_snapshots (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid NOT NULL,
  resolved_brand jsonb NOT NULL,
  source_revision_ids jsonb NOT NULL,
  snapshot_sha256 char(64) NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES users(id),
  FOREIGN KEY (organization_id, event_id) REFERENCES events(organization_id, id),
  UNIQUE (organization_id, id)
);

CREATE TABLE generated_documents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid,
  event_guest_id uuid,
  template_revision_id uuid,
  brand_snapshot_id uuid,
  document_type text NOT NULL,
  storage_key text NOT NULL,
  sha256_hex char(64) NOT NULL,
  revision_label text,
  status text NOT NULL DEFAULT 'current' CHECK (status IN ('current','superseded','revoked','archived')),
  generated_by uuid REFERENCES users(id),
  generated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, event_id) REFERENCES events(organization_id, id),
  FOREIGN KEY (organization_id, event_guest_id) REFERENCES event_guests(organization_id, id),
  FOREIGN KEY (organization_id, template_revision_id) REFERENCES document_template_revisions(organization_id, id),
  FOREIGN KEY (organization_id, brand_snapshot_id) REFERENCES event_brand_snapshots(organization_id, id),
  UNIQUE (organization_id, id)
);

-- Credentials, stations and append-only check-in.
CREATE TABLE guest_credentials (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_guest_id uuid NOT NULL,
  session_id uuid,
  credential_type text NOT NULL CHECK (credential_type IN ('admission_qr','guest_portal','staff_assist')),
  token_hash char(64) NOT NULL UNIQUE,
  token_hint text,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','revoked','expired','replaced')),
  issued_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz,
  revoked_at timestamptz,
  replaced_by_credential_id uuid REFERENCES guest_credentials(id),
  issued_by uuid REFERENCES users(id),
  FOREIGN KEY (organization_id, event_guest_id) REFERENCES event_guests(organization_id, id),
  FOREIGN KEY (organization_id, session_id) REFERENCES event_sessions(organization_id, id),
  UNIQUE (organization_id, id)
);

CREATE TABLE checkin_stations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid NOT NULL,
  code text NOT NULL,
  name text NOT NULL,
  station_type text NOT NULL DEFAULT 'scanner' CHECK (station_type IN ('scanner','kiosk','manual_desk')),
  location_label text,
  device_public_key text,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','disabled','maintenance')),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, event_id) REFERENCES events(organization_id, id),
  UNIQUE (event_id, code),
  UNIQUE (organization_id, id)
);

CREATE TABLE checkin_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_guest_id uuid NOT NULL,
  session_id uuid,
  credential_id uuid,
  station_id uuid,
  operator_user_id uuid REFERENCES users(id),
  action text NOT NULL CHECK (action IN ('check_in','check_out','manual_check_in','void','correction')),
  result text NOT NULL CHECK (result IN ('accepted','duplicate','rejected','pending_sync','voided')),
  idempotency_key text NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  server_recorded_at timestamptz NOT NULL DEFAULT now(),
  correction_of_id uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  FOREIGN KEY (organization_id, event_guest_id) REFERENCES event_guests(organization_id, id),
  FOREIGN KEY (organization_id, session_id) REFERENCES event_sessions(organization_id, id),
  FOREIGN KEY (organization_id, credential_id) REFERENCES guest_credentials(organization_id, id),
  FOREIGN KEY (organization_id, station_id) REFERENCES checkin_stations(organization_id, id),
  FOREIGN KEY (organization_id, correction_of_id) REFERENCES checkin_records(organization_id, id),
  UNIQUE (organization_id, idempotency_key),
  UNIQUE (organization_id, id)
);
CREATE INDEX checkin_records_guest_time_idx ON checkin_records(event_guest_id, occurred_at DESC);

CREATE TABLE guest_session_attendance (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_guest_id uuid NOT NULL,
  session_id uuid NOT NULL,
  current_state text NOT NULL DEFAULT 'not_arrived' CHECK (current_state IN ('not_arrived','checked_in','checked_out','manual_review')),
  first_checkin_at timestamptz,
  last_change_at timestamptz NOT NULL DEFAULT now(),
  last_record_id uuid,
  FOREIGN KEY (organization_id, event_guest_id) REFERENCES event_guests(organization_id, id),
  FOREIGN KEY (organization_id, session_id) REFERENCES event_sessions(organization_id, id),
  FOREIGN KEY (organization_id, last_record_id) REFERENCES checkin_records(organization_id, id),
  UNIQUE (event_guest_id, session_id),
  UNIQUE (organization_id, id)
);

-- Externally performed event prerequisites; no internal inspection workflow.
CREATE TABLE event_prerequisites (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid NOT NULL,
  session_id uuid,
  prerequisite_type text NOT NULL CHECK (prerequisite_type IN ('cdi_police_inspection','venue_approval','authority_notification','other')),
  title text NOT NULL,
  mandatory boolean NOT NULL DEFAULT false,
  readiness_gate boolean NOT NULL DEFAULT false,
  external_party_name text,
  internal_coordinator_id uuid REFERENCES users(id),
  status text NOT NULL DEFAULT 'not_assessed' CHECK (status IN ('not_assessed','not_required','pending_request','request_submitted','scheduled','completed','delayed','cancelled','exception_approved')),
  request_date date,
  request_reference text,
  scheduled_at timestamptz,
  completed_at timestamptz,
  completion_confirmed_by uuid REFERENCES users(id),
  restricted_attachment_key text,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (organization_id, event_id) REFERENCES events(organization_id, id),
  FOREIGN KEY (organization_id, session_id) REFERENCES event_sessions(organization_id, id),
  UNIQUE (organization_id, id)
);

CREATE TABLE prerequisite_status_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  prerequisite_id uuid NOT NULL,
  from_status text,
  to_status text NOT NULL,
  changed_by uuid REFERENCES users(id),
  changed_at timestamptz NOT NULL DEFAULT now(),
  reason text,
  FOREIGN KEY (organization_id, prerequisite_id) REFERENCES event_prerequisites(organization_id, id)
);

-- Cockpit, audit, transactional outbox and worker jobs.
CREATE TABLE operational_alerts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid NOT NULL,
  alert_code text NOT NULL,
  severity text NOT NULL CHECK (severity IN ('info','warning','critical')),
  title text NOT NULL,
  detail_safe text,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','acknowledged','assigned','resolved','dismissed')),
  assigned_to uuid REFERENCES users(id),
  source_entity_type text,
  source_entity_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  acknowledged_at timestamptz,
  resolved_at timestamptz,
  FOREIGN KEY (organization_id, event_id) REFERENCES events(organization_id, id),
  UNIQUE (organization_id, id)
);

CREATE TABLE operational_issues (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid NOT NULL,
  title text NOT NULL,
  description text,  severity text NOT NULL DEFAULT 'warning' CHECK (severity IN ('info','warning','critical')) ,
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