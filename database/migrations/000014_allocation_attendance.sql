-- Optional seating/allocation, admission credentials, check-in and attendance records.
CREATE TABLE eogp.event_allocation_revisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    session_id uuid NOT NULL,
    revision_number integer NOT NULL CHECK (revision_number > 0),
    event_venue_snapshot_id uuid NOT NULL,
    rules_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    state text NOT NULL DEFAULT 'draft'
      CHECK (state IN ('draft','proposed','approved','published','superseded','withdrawn')),
    created_by_membership_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_id, session_id, id),
    UNIQUE (organization_id, event_id, session_id, revision_number),
    UNIQUE (organization_id, event_id, session_id, id, event_venue_snapshot_id),
    FOREIGN KEY (organization_id, event_id, session_id)
      REFERENCES eogp.event_sessions(organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id, event_venue_snapshot_id)
      REFERENCES eogp.event_venue_snapshots(organization_id, event_id, id),
    FOREIGN KEY (organization_id, created_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);

CREATE TABLE eogp.event_allocation_runs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    session_id uuid NOT NULL,
    allocation_revision_id uuid NOT NULL,
    solver_name text NOT NULL,
    solver_version text,
    input_sha256 text NOT NULL CHECK (input_sha256 ~ '^[0-9a-f]{64}$'),
    status text NOT NULL DEFAULT 'queued'
      CHECK (status IN ('queued','running','succeeded','infeasible','failed','cancelled')),
    objective_value numeric,
    diagnostics jsonb NOT NULL DEFAULT '{}'::jsonb,
    output_snapshot jsonb,
    started_at timestamptz,
    finished_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, event_id, session_id, allocation_revision_id)
      REFERENCES eogp.event_allocation_revisions(organization_id, event_id, session_id, id),
    CHECK ((status = 'running') = (started_at IS NOT NULL AND finished_at IS NULL)),
    CHECK ((status IN ('succeeded','infeasible','failed','cancelled')) = (finished_at IS NOT NULL))
);

CREATE TABLE eogp.event_allocations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    session_id uuid NOT NULL,
    allocation_revision_id uuid NOT NULL,
    event_venue_snapshot_id uuid NOT NULL,
    participation_id uuid NOT NULL,
    snapshot_object_id uuid,
    zone_code text,
    seat_label text,
    allocation_kind text NOT NULL DEFAULT 'zone'
      CHECK (allocation_kind IN ('zone','position','capacity_pool','manual')),
    assignment_state text NOT NULL DEFAULT 'proposed'
      CHECK (assignment_state IN ('proposed','committed','locked','released')),
    constraints_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, allocation_revision_id, participation_id),
    FOREIGN KEY (organization_id, event_id, session_id, allocation_revision_id, event_venue_snapshot_id)
      REFERENCES eogp.event_allocation_revisions(organization_id, event_id, session_id, id, event_venue_snapshot_id),
    FOREIGN KEY (organization_id, event_id, participation_id)
      REFERENCES eogp.event_participations(organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_venue_snapshot_id, snapshot_object_id)
      REFERENCES eogp.event_venue_snapshot_objects(organization_id, snapshot_id, id),
    CHECK (snapshot_object_id IS NOT NULL OR zone_code IS NOT NULL)
);
CREATE INDEX event_allocations_session_idx
  ON eogp.event_allocations (organization_id, event_id, session_id, assignment_state);

CREATE TABLE eogp.event_allocation_locks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    session_id uuid NOT NULL,
    participation_id uuid NOT NULL,
    locked_by_membership_id uuid NOT NULL,
    lock_reason text,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    released_at timestamptz,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, event_id, participation_id)
      REFERENCES eogp.event_participations(organization_id, event_id, id),
    FOREIGN KEY (organization_id, locked_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    CHECK (released_at IS NULL OR released_at >= created_at)
);
CREATE UNIQUE INDEX event_allocation_one_active_lock_uq
  ON eogp.event_allocation_locks (organization_id, event_id, session_id, participation_id)
  WHERE released_at IS NULL;

CREATE TABLE eogp.admission_credentials (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    participation_id uuid NOT NULL,
    credential_kind text NOT NULL DEFAULT 'admission_qr'
      CHECK (credential_kind IN ('admission_qr','staff_badge','other')),
    token_sha256 text NOT NULL UNIQUE CHECK (token_sha256 ~ '^[0-9a-f]{64}$'),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','revoked','expired')),
    issued_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    expires_at timestamptz,
    revoked_at timestamptz,
    issued_by_membership_id uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, event_id, participation_id)
      REFERENCES eogp.event_participations(organization_id, event_id, id),
    FOREIGN KEY (organization_id, issued_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    CHECK (expires_at IS NULL OR expires_at > issued_at),
    CHECK ((status = 'revoked') = (revoked_at IS NOT NULL))
);
CREATE UNIQUE INDEX admission_credentials_one_active_uq
  ON eogp.admission_credentials (organization_id, event_id, participation_id)
  WHERE status = 'active';

CREATE TABLE eogp.checkin_stations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    session_id uuid NOT NULL,
    station_code text NOT NULL,
    display_name text NOT NULL,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','disabled','retired')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_id, id),
    UNIQUE (organization_id, event_id, station_code),
    FOREIGN KEY (organization_id, event_id, session_id)
      REFERENCES eogp.event_sessions(organization_id, event_id, id)
);

CREATE TABLE eogp.checkin_attempts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    session_id uuid NOT NULL,
    station_id uuid NOT NULL,
    admission_credential_id uuid,
    safe_token_fingerprint text,
    outcome text NOT NULL CHECK (outcome IN ('accepted','duplicate','rejected','invalid','event_cancelled','capability_disabled')),
    idempotency_key text NOT NULL,
    actor_membership_id uuid NOT NULL,
    attempted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    safe_result jsonb NOT NULL DEFAULT '{}'::jsonb,
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_id, session_id, id),
    UNIQUE (organization_id, station_id, idempotency_key),
    FOREIGN KEY (organization_id, event_id, session_id)
      REFERENCES eogp.event_sessions(organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id, station_id)
      REFERENCES eogp.checkin_stations(organization_id, event_id, id),
    FOREIGN KEY (organization_id, admission_credential_id)
      REFERENCES eogp.admission_credentials(organization_id, id),
    FOREIGN KEY (organization_id, actor_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);
CREATE INDEX checkin_attempts_event_idx
  ON eogp.checkin_attempts (organization_id, event_id, attempted_at DESC);

CREATE TABLE eogp.attendance_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    session_id uuid NOT NULL,
    participation_id uuid NOT NULL,
    checkin_attempt_id uuid,
    attendance_action text NOT NULL CHECK (attendance_action IN ('arrived','departed','manual_arrival','correction')),
    attendance_state text NOT NULL CHECK (attendance_state IN ('present','not_present')),
    actor_membership_id uuid,
    reason text,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    corrects_attendance_record_id uuid,
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_id, session_id, participation_id, id),
    FOREIGN KEY (organization_id, event_id, participation_id)
      REFERENCES eogp.event_participations(organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id, session_id, checkin_attempt_id)
      REFERENCES eogp.checkin_attempts(organization_id, event_id, session_id, id),
    FOREIGN KEY (organization_id, actor_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    FOREIGN KEY (organization_id, event_id, session_id, participation_id, corrects_attendance_record_id)
      REFERENCES eogp.attendance_records(organization_id, event_id, session_id, participation_id, id)
);

CREATE TABLE eogp.event_prerequisite_status_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    prerequisite_id uuid NOT NULL,
    previous_status text,
    new_status text NOT NULL,
    actor_membership_id uuid,
    reason text,
    occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, prerequisite_id)
      REFERENCES eogp.event_prerequisites(organization_id, id),
    FOREIGN KEY (organization_id, actor_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);

CREATE TABLE eogp.operational_alerts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    alert_code text NOT NULL,
    severity text NOT NULL CHECK (severity IN ('info','warning','critical')),
    summary text NOT NULL,
    details_restricted jsonb NOT NULL DEFAULT '{}'::jsonb,
    status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','acknowledged','resolved','dismissed')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    resolved_at timestamptz,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, event_id) REFERENCES eogp.events(organization_id, id)
);
CREATE INDEX operational_alerts_open_idx
  ON eogp.operational_alerts (organization_id, event_id, severity, created_at DESC)
  WHERE status = 'open';
