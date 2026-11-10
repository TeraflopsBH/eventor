-- Explicit cross-organization grants and event-owned immutable venue-plan snapshots.
CREATE TABLE eogp.collaboration_grants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    grantee_organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    scope_kind text NOT NULL CHECK (scope_kind IN ('venue','space','booking')),
    scope_venue_id uuid,
    scope_space_id uuid,
    scope_booking_id uuid,
    purpose text NOT NULL,
    projection jsonb NOT NULL DEFAULT '{}'::jsonb,
    allowed_actions text[] NOT NULL DEFAULT ARRAY[]::text[],
    status text NOT NULL DEFAULT 'proposed'
      CHECK (status IN ('proposed','active','expired','revoked','declined')),
    valid_from timestamptz NOT NULL DEFAULT clock_timestamp(),
    valid_until timestamptz,
    proposed_by_membership_id uuid NOT NULL,
    accepted_by_membership_id uuid,
    accepted_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, grantee_organization_id, id),
    CHECK (organization_id <> grantee_organization_id),
    CHECK (
      (scope_kind = 'venue' AND scope_venue_id IS NOT NULL AND scope_space_id IS NULL AND scope_booking_id IS NULL)
      OR (scope_kind = 'space' AND scope_venue_id IS NULL AND scope_space_id IS NOT NULL AND scope_booking_id IS NULL)
      OR (scope_kind = 'booking' AND scope_venue_id IS NULL AND scope_space_id IS NULL AND scope_booking_id IS NOT NULL)
    ),
    FOREIGN KEY (organization_id, scope_venue_id) REFERENCES eogp.venues(organization_id, id),
    FOREIGN KEY (organization_id, scope_space_id) REFERENCES eogp.venue_spaces(organization_id, id),
    FOREIGN KEY (organization_id, scope_booking_id) REFERENCES eogp.booking_records(organization_id, id),
    FOREIGN KEY (organization_id, proposed_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    FOREIGN KEY (grantee_organization_id, accepted_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    CHECK (valid_until IS NULL OR valid_until > valid_from),
    CHECK ((accepted_at IS NULL) = (accepted_by_membership_id IS NULL)),
    CHECK (status <> 'proposed' OR (accepted_at IS NULL AND accepted_by_membership_id IS NULL)),
    CHECK (status NOT IN ('active','revoked','expired') OR (accepted_at IS NOT NULL AND accepted_by_membership_id IS NOT NULL)),
    CHECK ((status = 'revoked') = (revoked_at IS NOT NULL))
);
CREATE INDEX collaboration_grants_grantee_idx
  ON eogp.collaboration_grants (grantee_organization_id, status, valid_from, valid_until);

CREATE TABLE eogp.collaboration_grant_revisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    grant_id uuid NOT NULL,
    revision_number integer NOT NULL CHECK (revision_number > 0),
    projection jsonb NOT NULL,
    allowed_actions text[] NOT NULL,
    changed_by_membership_id uuid NOT NULL,
    changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, grant_id, revision_number),
    FOREIGN KEY (organization_id, grant_id) REFERENCES eogp.collaboration_grants(organization_id, id),
    FOREIGN KEY (organization_id, changed_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);

CREATE TABLE eogp.venue_snapshot_shares (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    venue_space_revision_id uuid NOT NULL,
    event_owner_organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    collaboration_grant_id uuid NOT NULL,
    approved_layers jsonb NOT NULL DEFAULT '[]'::jsonb,
    approved_resources jsonb NOT NULL DEFAULT '[]'::jsonb,
    source_content_sha256 text NOT NULL CHECK (source_content_sha256 ~ '^[0-9a-f]{64}$'),
    expires_at timestamptz,
    approved_by_membership_id uuid NOT NULL,
    approved_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','revoked','expired')),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_owner_organization_id, event_id, id, venue_space_revision_id, source_content_sha256),
    FOREIGN KEY (organization_id, venue_space_revision_id)
      REFERENCES eogp.venue_space_revisions(organization_id, id),
    FOREIGN KEY (event_owner_organization_id, event_id)
      REFERENCES eogp.events(organization_id, id),
    FOREIGN KEY (organization_id, event_owner_organization_id, collaboration_grant_id)
      REFERENCES eogp.collaboration_grants(organization_id, grantee_organization_id, id),
    FOREIGN KEY (organization_id, approved_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    CHECK (organization_id <> event_owner_organization_id),
    CHECK (expires_at IS NULL OR expires_at > approved_at)
);

CREATE TABLE eogp.event_venue_snapshots (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    share_owner_organization_id uuid NOT NULL,
    snapshot_share_id uuid NOT NULL,
    source_organization_id uuid NOT NULL,
    source_space_revision_id uuid NOT NULL,
    source_content_sha256 text NOT NULL CHECK (source_content_sha256 ~ '^[0-9a-f]{64}$'),
    snapshot_content jsonb NOT NULL,
    copied_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id) REFERENCES eogp.events(organization_id, id),
    FOREIGN KEY (share_owner_organization_id, organization_id, event_id, snapshot_share_id, source_space_revision_id, source_content_sha256)
      REFERENCES eogp.venue_snapshot_shares(organization_id, event_owner_organization_id, event_id, id, venue_space_revision_id, source_content_sha256),
    FOREIGN KEY (source_organization_id, source_space_revision_id)
      REFERENCES eogp.venue_space_revisions(organization_id, id),
    CHECK (source_organization_id = share_owner_organization_id)
);

CREATE TABLE eogp.event_venue_snapshot_layers (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    snapshot_id uuid NOT NULL,
    source_layer_id uuid,
    layer_code text NOT NULL,
    layer_snapshot jsonb NOT NULL,
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, snapshot_id, layer_code),
    UNIQUE (organization_id, snapshot_id, id),
    FOREIGN KEY (organization_id, event_id, snapshot_id)
      REFERENCES eogp.event_venue_snapshots(organization_id, event_id, id)
);

CREATE TABLE eogp.event_venue_snapshot_objects (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    snapshot_id uuid NOT NULL,
    snapshot_layer_id uuid NOT NULL,
    source_object_id uuid,
    object_kind text NOT NULL,
    object_snapshot jsonb NOT NULL,
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, snapshot_id, id),
    FOREIGN KEY (organization_id, snapshot_id, snapshot_layer_id)
      REFERENCES eogp.event_venue_snapshot_layers(organization_id, snapshot_id, id)
);

CREATE TABLE eogp.event_venue_snapshot_resources (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    snapshot_id uuid NOT NULL,
    source_resource_unit_id uuid,
    source_resource_pool_id uuid,
    resource_snapshot jsonb NOT NULL,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, event_id, snapshot_id)
      REFERENCES eogp.event_venue_snapshots(organization_id, event_id, id),
    CHECK (num_nonnulls(source_resource_unit_id, source_resource_pool_id) = 1)
);

CREATE TABLE eogp.booking_event_links (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    booking_owner_organization_id uuid NOT NULL,
    booking_id uuid NOT NULL,
    event_id uuid NOT NULL,
    grant_owner_organization_id uuid,
    collaboration_grant_id uuid,
    relationship_kind text NOT NULL DEFAULT 'venue_for_event'
      CHECK (relationship_kind IN ('venue_for_event','service_for_event','other')),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','ended','revoked')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, booking_owner_organization_id, booking_id, event_id),
    FOREIGN KEY (organization_id, event_id) REFERENCES eogp.events(organization_id, id),
    FOREIGN KEY (booking_owner_organization_id, booking_id)
      REFERENCES eogp.booking_records(organization_id, id),
    FOREIGN KEY (grant_owner_organization_id, organization_id, collaboration_grant_id)
      REFERENCES eogp.collaboration_grants(organization_id, grantee_organization_id, id),
    CHECK (
      (organization_id = booking_owner_organization_id AND collaboration_grant_id IS NULL AND grant_owner_organization_id IS NULL)
      OR (organization_id <> booking_owner_organization_id AND collaboration_grant_id IS NOT NULL
          AND grant_owner_organization_id = booking_owner_organization_id)
    ),
    CHECK ((collaboration_grant_id IS NULL) = (grant_owner_organization_id IS NULL))
);

CREATE TABLE eogp.event_session_spaces (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    session_id uuid NOT NULL,
    event_venue_snapshot_id uuid NOT NULL,
    snapshot_object_id uuid,
    allocation_mode text NOT NULL DEFAULT 'zone'
      CHECK (allocation_mode IN ('zone','precise_position','capacity_pool')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, event_id, session_id)
      REFERENCES eogp.event_sessions(organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id, event_venue_snapshot_id)
      REFERENCES eogp.event_venue_snapshots(organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_venue_snapshot_id, snapshot_object_id)
      REFERENCES eogp.event_venue_snapshot_objects(organization_id, snapshot_id, id)
);

