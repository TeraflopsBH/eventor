-- Organizer-owned person registry and event-specific participation.
CREATE TABLE eogp.persons (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    first_name text NOT NULL,
    last_name text NOT NULL,
    display_name text,
    preferred_name text,
    merged_into_person_id uuid,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','merged','archived')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    created_by_membership_id uuid NOT NULL,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, merged_into_person_id)
      REFERENCES eogp.persons(organization_id, id),
    FOREIGN KEY (organization_id, created_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    CHECK ((status = 'merged') = (merged_into_person_id IS NOT NULL)),
    CHECK (merged_into_person_id IS NULL OR merged_into_person_id <> id)
);
CREATE INDEX persons_name_search_idx
  ON eogp.persons (organization_id, lower(last_name), lower(first_name))
  WHERE status = 'active';

CREATE TABLE eogp.person_contact_points (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    person_id uuid NOT NULL,
    contact_kind text NOT NULL CHECK (contact_kind IN ('email','phone','postal','other')),
    normalized_value_hash text NOT NULL,
    encrypted_value bytea NOT NULL,
    is_primary boolean NOT NULL DEFAULT false,
    is_verified boolean NOT NULL DEFAULT false,
    contact_consent text NOT NULL DEFAULT 'unknown'
      CHECK (contact_consent IN ('unknown','permitted','restricted','withdrawn')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, person_id) REFERENCES eogp.persons(organization_id, id),
    CHECK (normalized_value <> '')
);
CREATE INDEX person_contact_points_lookup_idx
  ON eogp.person_contact_points (organization_id, contact_kind, normalized_value_hash);

CREATE TABLE eogp.person_identifiers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    person_id uuid NOT NULL,
    identifier_kind text NOT NULL,
    identifier_hash text NOT NULL,
    encrypted_value bytea NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, identifier_kind, identifier_hash),
    FOREIGN KEY (organization_id, person_id) REFERENCES eogp.persons(organization_id, id)
);

CREATE TABLE eogp.event_participations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    person_id uuid NOT NULL,
    participation_code text,
    category_code text,
    status text NOT NULL DEFAULT 'eligible'
      CHECK (status IN ('eligible','waitlisted','withdrawn','cancelled','ineligible')),
    added_by_membership_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_id, person_id),
    UNIQUE (organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id) REFERENCES eogp.events(organization_id, id),
    FOREIGN KEY (organization_id, person_id) REFERENCES eogp.persons(organization_id, id),
    FOREIGN KEY (organization_id, added_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);
CREATE INDEX event_participations_status_idx
  ON eogp.event_participations (organization_id, event_id, status);

CREATE TABLE eogp.participation_status_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    participation_id uuid NOT NULL,
    previous_status text,
    new_status text NOT NULL,
    actor_membership_id uuid,
    reason_code text,
    occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, event_id, participation_id)
      REFERENCES eogp.event_participations(organization_id, event_id, id),
    FOREIGN KEY (organization_id, actor_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);

CREATE TABLE eogp.guest_groups (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    group_code text NOT NULL,
    name text NOT NULL,
    group_kind text NOT NULL DEFAULT 'custom',
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_id, id),
    UNIQUE (organization_id, event_id, group_code),
    FOREIGN KEY (organization_id, event_id) REFERENCES eogp.events(organization_id, id)
);

CREATE TABLE eogp.guest_group_memberships (
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    group_id uuid NOT NULL,
    participation_id uuid NOT NULL,
    membership_kind text NOT NULL DEFAULT 'member',
    added_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (organization_id, group_id, participation_id),
    FOREIGN KEY (organization_id, event_id, group_id)
      REFERENCES eogp.guest_groups(organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id, participation_id)
      REFERENCES eogp.event_participations(organization_id, event_id, id)
);

CREATE TABLE eogp.guest_relationships (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    from_participation_id uuid NOT NULL,
    to_participation_id uuid NOT NULL,
    relationship_kind text NOT NULL,
    directionality text NOT NULL DEFAULT 'mutual' CHECK (directionality IN ('mutual','directed')),
    notes_restricted text,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, event_id, from_participation_id)
      REFERENCES eogp.event_participations(organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id, to_participation_id)
      REFERENCES eogp.event_participations(organization_id, event_id, id),
    CHECK (from_participation_id <> to_participation_id)
);

CREATE TABLE eogp.guest_notes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    participation_id uuid NOT NULL,
    note_ciphertext bytea NOT NULL,
    sensitivity text NOT NULL DEFAULT 'restricted'
      CHECK (sensitivity IN ('internal','restricted','highly_restricted')),
    created_by_membership_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, event_id, participation_id)
      REFERENCES eogp.event_participations(organization_id, event_id, id),
    FOREIGN KEY (organization_id, created_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);

CREATE TABLE eogp.guest_custom_field_definitions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    field_code text NOT NULL,
    label text NOT NULL,
    value_schema jsonb NOT NULL,
    sensitivity text NOT NULL DEFAULT 'internal'
      CHECK (sensitivity IN ('public','internal','restricted','highly_restricted')),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_id, id),
    UNIQUE (organization_id, event_id, field_code),
    FOREIGN KEY (organization_id, event_id) REFERENCES eogp.events(organization_id, id),
    CHECK (jsonb_typeof(value_schema) = 'object')
);

CREATE TABLE eogp.guest_custom_field_values (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    participation_id uuid NOT NULL,
    field_definition_id uuid NOT NULL,
    value jsonb NOT NULL,
    updated_by_membership_id uuid NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, participation_id, field_definition_id),
    FOREIGN KEY (organization_id, event_id, participation_id)
      REFERENCES eogp.event_participations(organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id, field_definition_id)
      REFERENCES eogp.guest_custom_field_definitions(organization_id, event_id, id),
    FOREIGN KEY (organization_id, updated_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);

CREATE TABLE eogp.guest_tags (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    tag_code text NOT NULL,
    label text NOT NULL,
    sensitivity text NOT NULL DEFAULT 'internal'
      CHECK (sensitivity IN ('public','internal','restricted')),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_id, id),
    UNIQUE (organization_id, event_id, tag_code),
    FOREIGN KEY (organization_id, event_id) REFERENCES eogp.events(organization_id, id)
);

CREATE TABLE eogp.event_participation_tags (
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    participation_id uuid NOT NULL,
    tag_id uuid NOT NULL,
    added_by_membership_id uuid NOT NULL,
    added_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (organization_id, participation_id, tag_id),
    FOREIGN KEY (organization_id, event_id, participation_id)
      REFERENCES eogp.event_participations(organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id, tag_id) REFERENCES eogp.guest_tags(organization_id, event_id, id),
    FOREIGN KEY (organization_id, added_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);

CREATE TABLE eogp.guest_import_batches (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    state text NOT NULL DEFAULT 'uploaded'
      CHECK (state IN ('uploaded','previewing','ready','committed','failed','cancelled')),
    source_filename text NOT NULL,
    source_sha256 text NOT NULL CHECK (source_sha256 ~ '^[0-9a-f]{64}$'),
    mapping_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by_membership_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    committed_at timestamptz,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, event_id) REFERENCES eogp.events(organization_id, id),
    FOREIGN KEY (organization_id, created_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);

CREATE TABLE eogp.guest_import_rows (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    batch_id uuid NOT NULL,
    row_number integer NOT NULL CHECK (row_number > 0),
    source_values_ciphertext bytea NOT NULL,
    normalized_values jsonb,
    validation_errors jsonb NOT NULL DEFAULT '[]'::jsonb,
    duplicate_candidates jsonb NOT NULL DEFAULT '[]'::jsonb,
    committed_participation_id uuid,
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, batch_id, row_number),
    FOREIGN KEY (organization_id, batch_id) REFERENCES eogp.guest_import_batches(organization_id, id),
    FOREIGN KEY (organization_id, committed_participation_id)
      REFERENCES eogp.event_participations(organization_id, id)
);
