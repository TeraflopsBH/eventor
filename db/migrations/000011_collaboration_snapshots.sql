-- Eventor migration 000011: 000011_collaboration_snapshots.sql
-- Apply only through scripts/db/apply-migrations.sh so the checksum ledger is updated.
BEGIN;
SET LOCAL search_path TO eogp, public;

SET LOCAL search_path TO eogp, public;

CREATE TABLE eogp.collaboration_grants (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id) ON DELETE RESTRICT,
  grantee_organization_id uuid NOT NULL REFERENCES eogp.organizations(id) ON DELETE RESTRICT,
  purpose_code    text NOT NULL,
  scope_json      jsonb NOT NULL,
  projection_json jsonb NOT NULL,
  status          text NOT NULL DEFAULT 'proposed'
                  CHECK (status IN ('proposed','invited','accepted','active','expired','revoked','completed')),
  valid_from      timestamptz,
  valid_until     timestamptz,
  issued_by_membership_id uuid NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, grantee_organization_id, id),
  FOREIGN KEY (organization_id, issued_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT,
  CHECK (organization_id <> grantee_organization_id),
  CHECK (valid_until IS NULL OR valid_from IS NULL OR valid_until > valid_from)
);

CREATE TABLE eogp.collaboration_grant_revisions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  grantee_organization_id uuid NOT NULL,
  grant_id        uuid NOT NULL,
  revision_no     integer NOT NULL CHECK (revision_no > 0),
  scope_json      jsonb NOT NULL,
  projection_json jsonb NOT NULL,
  status          text NOT NULL,
  actor_membership_id uuid NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, grant_id, id),
  UNIQUE (organization_id, grant_id, revision_no),
  FOREIGN KEY (organization_id, grantee_organization_id, grant_id)
    REFERENCES eogp.collaboration_grants(organization_id, grantee_organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, actor_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.venue_snapshot_shares (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  grantee_organization_id uuid NOT NULL,
  venue_id        uuid NOT NULL,
  space_revision_id uuid NOT NULL,
  collaboration_grant_id uuid NOT NULL,
  allowed_layers  jsonb NOT NULL,
  allowed_resources jsonb NOT NULL DEFAULT '[]'::jsonb,
  status          text NOT NULL DEFAULT 'approved' CHECK (status IN ('approved','revoked','expired')),
  approved_by_membership_id uuid NOT NULL,
  approved_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, grantee_organization_id, id),
  FOREIGN KEY (organization_id, venue_id)
    REFERENCES eogp.venues(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, space_revision_id)
    REFERENCES eogp.venue_space_revisions(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, grantee_organization_id, collaboration_grant_id)
    REFERENCES eogp.collaboration_grants(organization_id, grantee_organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, approved_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.event_venue_snapshots (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  source_organization_id uuid NOT NULL,
  source_space_revision_id uuid NOT NULL,
  source_revision_hash text NOT NULL CHECK (source_revision_hash ~ '^[0-9a-f]{64}$'),
  collaboration_grant_id uuid NOT NULL,
  source_share_id uuid NOT NULL,
  snapshot_json   jsonb NOT NULL,
  captured_by_membership_id uuid NOT NULL,
  captured_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, event_id, id),
  FOREIGN KEY (organization_id, event_id)
    REFERENCES eogp.events(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (source_organization_id, organization_id, collaboration_grant_id)
    REFERENCES eogp.collaboration_grants(organization_id, grantee_organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (source_organization_id, organization_id, source_share_id)
    REFERENCES eogp.venue_snapshot_shares(organization_id, grantee_organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, captured_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.event_venue_snapshot_layers (
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  snapshot_id     uuid NOT NULL,
  layer_code      text NOT NULL,
  visibility      text NOT NULL CHECK (visibility IN ('operational','guest_safe')),
  objects_json    jsonb NOT NULL,
  PRIMARY KEY (organization_id, snapshot_id, layer_code),
  FOREIGN KEY (organization_id, event_id, snapshot_id)
    REFERENCES eogp.event_venue_snapshots(organization_id, event_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.booking_event_links (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  booking_owner_organization_id uuid NOT NULL,
  booking_id      uuid NOT NULL,
  collaboration_grant_id uuid NOT NULL,
  link_status     text NOT NULL DEFAULT 'active' CHECK (link_status IN ('proposed','active','suspended','revoked','completed')),
  created_by_membership_id uuid NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, event_id, id),
  UNIQUE (organization_id, event_id, booking_owner_organization_id, booking_id),
  FOREIGN KEY (organization_id, event_id)
    REFERENCES eogp.events(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (booking_owner_organization_id, booking_id)
    REFERENCES eogp.booking_records(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (booking_owner_organization_id, organization_id, collaboration_grant_id)
    REFERENCES eogp.collaboration_grants(organization_id, grantee_organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT,
  CHECK (booking_owner_organization_id <> organization_id)
);

CREATE TABLE eogp.event_session_spaces (
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  session_id      uuid NOT NULL,
  snapshot_id     uuid NOT NULL,
  snapshot_layer_code text NOT NULL,
  PRIMARY KEY (organization_id, session_id, snapshot_id, snapshot_layer_code),
  FOREIGN KEY (organization_id, event_id, session_id)
    REFERENCES eogp.event_sessions(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, event_id, snapshot_id)
    REFERENCES eogp.event_venue_snapshots(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, snapshot_id, snapshot_layer_code)
    REFERENCES eogp.event_venue_snapshot_layers(organization_id, snapshot_id, layer_code) ON DELETE RESTRICT
);

INSERT INTO eogp.schema_migrations(version, filename, checksum_sha256)
VALUES ('000011', '000011_collaboration_snapshots.sql', :'migration_checksum');
COMMIT;
