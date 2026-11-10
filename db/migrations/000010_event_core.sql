-- Eventor migration 000010: 000010_event_core.sql
-- Apply only through scripts/db/apply-migrations.sh so the checksum ledger is updated.
BEGIN;
SET LOCAL search_path TO eogp, public;

SET LOCAL search_path TO eogp, public;

CREATE TABLE eogp.events (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id) ON DELETE RESTRICT,
  event_code      text NOT NULL,
  title           text NOT NULL,
  description     text,
  timezone_name   text NOT NULL,
  status          text NOT NULL DEFAULT 'planned'
                  CHECK (status IN ('planned','scheduled','active','completed','cancelled','postponed','archived')),
  created_by_membership_id uuid NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, event_code),
  FOREIGN KEY (organization_id, created_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.event_schedule_revisions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  revision_no     integer NOT NULL CHECK (revision_no > 0),
  starts_at       timestamptz NOT NULL,
  ends_at         timestamptz NOT NULL,
  timezone_name   text NOT NULL,
  guest_location_text text,
  material_change boolean NOT NULL DEFAULT false,
  created_by_membership_id uuid NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, event_id, id),
  UNIQUE (organization_id, event_id, revision_no),
  FOREIGN KEY (organization_id, event_id)
    REFERENCES eogp.events(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT,
  CHECK (ends_at > starts_at)
);

CREATE TABLE eogp.event_sessions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  session_code    text NOT NULL,
  title           text NOT NULL,
  starts_at       timestamptz NOT NULL,
  ends_at         timestamptz NOT NULL,
  status          text NOT NULL DEFAULT 'planned' CHECK (status IN ('planned','scheduled','active','completed','cancelled')),
  UNIQUE (organization_id, event_id, id),
  UNIQUE (organization_id, event_id, session_code),
  FOREIGN KEY (organization_id, event_id)
    REFERENCES eogp.events(organization_id, id) ON DELETE RESTRICT,
  CHECK (ends_at > starts_at)
);

CREATE TABLE eogp.event_capability_revisions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  revision_no     integer NOT NULL CHECK (revision_no > 0),
  published_at    timestamptz,
  created_by_membership_id uuid NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, event_id, id),
  UNIQUE (organization_id, event_id, revision_no),
  FOREIGN KEY (organization_id, event_id)
    REFERENCES eogp.events(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.event_capability_entries (
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  revision_id     uuid NOT NULL,
  capability_code text NOT NULL CHECK (capability_code IN ('guest_registry','invitations_rsvp','seating','guest_portal','check_in','prerequisites','event_cockpit')),
  enabled         boolean NOT NULL DEFAULT false,
  configuration   jsonb NOT NULL DEFAULT '{}'::jsonb,
  PRIMARY KEY (organization_id, revision_id, capability_code),
  FOREIGN KEY (organization_id, event_id, revision_id)
    REFERENCES eogp.event_capability_revisions(organization_id, event_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.event_status_history (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  from_status     text,
  to_status       text NOT NULL,
  actor_membership_id uuid,
  reason          text,
  occurred_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (organization_id, event_id)
    REFERENCES eogp.events(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, actor_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, id)
);

ALTER TABLE eogp.user_role_grants
  ADD CONSTRAINT user_role_grants_event_fk FOREIGN KEY (organization_id, scope_event_id)
    REFERENCES eogp.events(organization_id, id) ON DELETE RESTRICT;

ALTER TABLE eogp.config_catalogues
  ADD CONSTRAINT config_catalogues_event_fk FOREIGN KEY (organization_id, scope_event_id)
    REFERENCES eogp.events(organization_id, id) ON DELETE RESTRICT;

ALTER TABLE eogp.brand_profiles
  ADD CONSTRAINT brand_profiles_event_fk FOREIGN KEY (organization_id, scope_event_id)
    REFERENCES eogp.events(organization_id, id) ON DELETE RESTRICT;

INSERT INTO eogp.schema_migrations(version, filename, checksum_sha256)
VALUES ('000010', '000010_event_core.sql', :'migration_checksum');
COMMIT;
