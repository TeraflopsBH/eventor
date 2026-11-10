-- Eventor migration 000001: 000001_platform_core.sql
-- Apply only through scripts/db/apply-migrations.sh so the checksum ledger is updated.
BEGIN;
SET LOCAL search_path TO eogp, public;

CREATE EXTENSION btree_gist WITH SCHEMA public;
CREATE SCHEMA eogp AUTHORIZATION CURRENT_USER;
SET LOCAL search_path TO eogp, public;

DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'eogp_runtime') THEN
    CREATE ROLE eogp_runtime NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'eogp_worker') THEN
    CREATE ROLE eogp_worker NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'eogp_readonly') THEN
    CREATE ROLE eogp_readonly NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT;
  END IF;
END
$roles$;

CREATE TABLE eogp.schema_migrations (
  version         text PRIMARY KEY,
  filename        text NOT NULL UNIQUE,
  checksum_sha256 text NOT NULL CHECK (checksum_sha256 ~ '^[0-9a-f]{64}$'),
  applied_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  execution_ms    integer,
  runner_identity text NOT NULL DEFAULT current_user
);

CREATE TABLE eogp.organizations (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug              text NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9][a-z0-9-]{1,78}[a-z0-9]$'),
  name              text NOT NULL CHECK (length(trim(name)) BETWEEN 2 AND 200),
  operating_profile text NOT NULL DEFAULT 'hybrid'
                    CHECK (operating_profile IN ('venue_provider','event_organizer','hybrid')),
  timezone_name     text NOT NULL DEFAULT 'Europe/Sarajevo',
  status            text NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','archived')),
  created_at        timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at        timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (id)
);

CREATE TABLE eogp.users (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email        text NOT NULL UNIQUE,
  display_name text NOT NULL CHECK (length(trim(display_name)) BETWEEN 1 AND 200),
  password_hash text,
  status       text NOT NULL DEFAULT 'active' CHECK (status IN ('active','disabled','pending')),
  created_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at   timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE eogp.organization_memberships (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id) ON DELETE RESTRICT,
  user_id         uuid NOT NULL REFERENCES eogp.users(id) ON DELETE RESTRICT,
  status          text NOT NULL DEFAULT 'active' CHECK (status IN ('invited','active','suspended','revoked')),
  display_label  text,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, user_id)
);

CREATE TABLE eogp.service_principals (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id) ON DELETE RESTRICT,
  code            text NOT NULL CHECK (code ~ '^[a-z][a-z0-9_.-]{1,99}$'),
  display_name    text NOT NULL,
  purpose         text NOT NULL,
  status          text NOT NULL DEFAULT 'active' CHECK (status IN ('active','disabled')),
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, code)
);

CREATE TABLE eogp.audit_events (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id          uuid NOT NULL REFERENCES eogp.organizations(id) ON DELETE RESTRICT,
  actor_kind               text NOT NULL CHECK (actor_kind IN ('member','service','external')),
  actor_membership_id      uuid,
  actor_service_principal_id uuid,
  actor_external_capability_id uuid,
  action_code              text NOT NULL,
  entity_type              text NOT NULL,
  entity_id                uuid,
  request_id               text,
  reason                   text,
  safe_metadata            jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at              timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (organization_id, actor_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, actor_service_principal_id)
    REFERENCES eogp.service_principals(organization_id, id) ON DELETE RESTRICT,
  CHECK (
    (actor_kind = 'member' AND actor_membership_id IS NOT NULL
      AND actor_service_principal_id IS NULL AND actor_external_capability_id IS NULL)
    OR
    (actor_kind = 'service' AND actor_membership_id IS NULL
      AND actor_service_principal_id IS NOT NULL AND actor_external_capability_id IS NULL)
    OR
    (actor_kind = 'external' AND actor_membership_id IS NULL
      AND actor_service_principal_id IS NULL AND actor_external_capability_id IS NOT NULL)
  )
);

CREATE TABLE eogp.outbox_events (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id) ON DELETE RESTRICT,
  event_code      text NOT NULL,
  aggregate_type  text NOT NULL,
  aggregate_id    uuid NOT NULL,
  payload         jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  available_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  published_at    timestamptz,
  attempt_count   integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  last_error_code text,
  UNIQUE (organization_id, id)
);

CREATE TABLE eogp.background_jobs (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id) ON DELETE RESTRICT,
  job_code        text NOT NULL,
  payload         jsonb NOT NULL DEFAULT '{}'::jsonb,
  status          text NOT NULL DEFAULT 'queued' CHECK (status IN ('queued','running','succeeded','failed','cancelled')),
  available_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  started_at      timestamptz,
  finished_at     timestamptz,
  attempt_count   integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
  last_error_code text,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id)
);

CREATE TABLE eogp.idempotency_records (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id) ON DELETE RESTRICT,
  idempotency_key text NOT NULL CHECK (length(idempotency_key) BETWEEN 8 AND 200),
  operation_code  text NOT NULL,
  request_hash    text NOT NULL CHECK (request_hash ~ '^[0-9a-f]{64}$'),
  response_status integer,
  response_body   jsonb,
  completed_at    timestamptz,
  expires_at      timestamptz NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, idempotency_key)
);

INSERT INTO eogp.schema_migrations(version, filename, checksum_sha256)
VALUES ('000001', '000001_platform_core.sql', :'migration_checksum');
COMMIT;
