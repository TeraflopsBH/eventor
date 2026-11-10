-- Eventor migration 000016: 000016_spatial_attendance.sql
-- Apply only through scripts/db/apply-migrations.sh so the checksum ledger is updated.
BEGIN;
SET LOCAL search_path TO eogp, public;

SET LOCAL search_path TO eogp, public;

CREATE TABLE eogp.allocation_revisions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  session_id      uuid NOT NULL,
  venue_snapshot_id uuid NOT NULL,
  revision_no     integer NOT NULL CHECK (revision_no > 0),
  status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','proposed','approved','published','superseded')),
  objective_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by_membership_id uuid NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, event_id, id),
  UNIQUE (organization_id, session_id, revision_no),
  FOREIGN KEY (organization_id, event_id, session_id)
    REFERENCES eogp.event_sessions(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, event_id, venue_snapshot_id)
    REFERENCES eogp.event_venue_snapshots(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.allocation_runs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  session_id      uuid NOT NULL,
  input_revision_id uuid NOT NULL,
  state           text NOT NULL DEFAULT 'queued' CHECK (state IN ('queued','running','succeeded','failed','cancelled')),
  diagnostics_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  result_json     jsonb,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  finished_at     timestamptz,
  UNIQUE (organization_id, id),
  FOREIGN KEY (organization_id, event_id, session_id)
    REFERENCES eogp.event_sessions(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, event_id, input_revision_id)
    REFERENCES eogp.allocation_revisions(organization_id, event_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.guest_allocations (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  session_id      uuid NOT NULL,
  allocation_revision_id uuid NOT NULL,
  participation_id uuid NOT NULL,
  venue_snapshot_id uuid NOT NULL,
  spatial_object_id uuid,
  allocation_code text,
  status          text NOT NULL DEFAULT 'proposed' CHECK (status IN ('proposed','committed','released')),
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  FOREIGN KEY (organization_id, event_id, session_id)
    REFERENCES eogp.event_sessions(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, event_id, allocation_revision_id)
    REFERENCES eogp.allocation_revisions(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, event_id, participation_id)
    REFERENCES eogp.event_participations(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, event_id, venue_snapshot_id)
    REFERENCES eogp.event_venue_snapshots(organization_id, event_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.admission_credentials (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  participation_id uuid NOT NULL,
  token_hash      bytea NOT NULL UNIQUE CHECK (octet_length(token_hash) = 32),
  status          text NOT NULL DEFAULT 'active' CHECK (status IN ('active','revoked','replaced','expired')),
  expires_at      timestamptz,
  replaced_by_credential_id uuid,
  issued_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  revoked_at      timestamptz,
  UNIQUE (organization_id, id),
  FOREIGN KEY (organization_id, event_id, participation_id)
    REFERENCES eogp.event_participations(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, replaced_by_credential_id)
    REFERENCES eogp.admission_credentials(organization_id, id) ON DELETE RESTRICT,
  CHECK ((status='replaced') = (replaced_by_credential_id IS NOT NULL)),
  CHECK (replaced_by_credential_id IS NULL OR replaced_by_credential_id <> id)
);

CREATE TABLE eogp.checkin_stations (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  station_code    text NOT NULL,
  name            text NOT NULL,
  status          text NOT NULL DEFAULT 'active' CHECK (status IN ('active','disabled')),
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, event_id, id),
  UNIQUE (organization_id, event_id, station_code),
  FOREIGN KEY (organization_id, event_id)
    REFERENCES eogp.events(organization_id, id) ON DELETE RESTRICT
);

ALTER TABLE eogp.user_role_grants
  ADD CONSTRAINT user_role_grants_station_fk FOREIGN KEY (organization_id, scope_station_id)
    REFERENCES eogp.checkin_stations(organization_id, id) ON DELETE RESTRICT;

CREATE TABLE eogp.attendance_records (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  session_id      uuid,
  participation_id uuid NOT NULL,
  station_id      uuid NOT NULL,
  action_code     text NOT NULL CHECK (action_code IN ('checked_in','checked_out','reversed')),
  credential_id   uuid,
  actor_membership_id uuid NOT NULL,
  occurred_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  reason          text,
  FOREIGN KEY (organization_id, event_id, participation_id)
    REFERENCES eogp.event_participations(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, event_id, session_id)
    REFERENCES eogp.event_sessions(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, event_id, station_id)
    REFERENCES eogp.checkin_stations(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, credential_id)
    REFERENCES eogp.admission_credentials(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, actor_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, id)
);

CREATE TABLE eogp.checkin_scan_records (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  station_id      uuid NOT NULL,
  device_id       text NOT NULL,
  device_sequence bigint NOT NULL CHECK (device_sequence >= 0),
  credential_hash bytea,
  result_code     text NOT NULL CHECK (result_code IN ('accepted','duplicate','rejected','invalid','expired','revoked')),
  attendance_record_id uuid,
  scanned_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, station_id, device_id, device_sequence),
  FOREIGN KEY (organization_id, event_id, station_id)
    REFERENCES eogp.checkin_stations(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, attendance_record_id)
    REFERENCES eogp.attendance_records(organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, id)
);

INSERT INTO eogp.schema_migrations(version, filename, checksum_sha256)
VALUES ('000016', '000016_spatial_attendance.sql', :'migration_checksum');
COMMIT;
