-- Platform foundation: tenant roots, identities, migration ledger, audit and outbox.
-- Executed by scripts/db/migrate.sh inside one transaction as eventor_owner.

CREATE TABLE eogp.organizations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    slug text NOT NULL,
    name text NOT NULL,
    operating_profile text NOT NULL DEFAULT 'venue_provider'
        CHECK (operating_profile IN ('venue_provider','event_organizer','hybrid')),
    status text NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','suspended','archived')),
    default_timezone text NOT NULL DEFAULT 'Europe/Sarajevo',
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (id),
    UNIQUE (slug)
);

CREATE TABLE eogp.users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email text,
    display_name text NOT NULL,
    password_hash text,
    status text NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','invited','disabled','locked')),
    email_verified_at timestamptz,
    last_authenticated_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
CREATE UNIQUE INDEX users_email_ci_uq ON eogp.users (lower(email)) WHERE email IS NOT NULL;

CREATE TABLE eogp.organization_memberships (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    user_id uuid NOT NULL REFERENCES eogp.users(id),
    status text NOT NULL DEFAULT 'active'
        CHECK (status IN ('invited','active','suspended','revoked')),
    joined_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, user_id),
    CHECK ((status = 'revoked') = (revoked_at IS NOT NULL))
);

CREATE TABLE eogp.service_principals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    code text NOT NULL,
    display_name text NOT NULL,
    purpose text NOT NULL,
    status text NOT NULL DEFAULT 'active'
        CHECK (status IN ('active','disabled','revoked')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, code)
);


CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA eogp;

CREATE FUNCTION eogp.current_organization_id()
RETURNS uuid
LANGUAGE sql
STABLE
PARALLEL SAFE
SET search_path = pg_catalog
AS $function$
  SELECT nullif(current_setting('app.organization_id', true), '')::uuid
$function$;

COMMENT ON FUNCTION eogp.current_organization_id() IS
  'Returns transaction-local tenant context. The API must set it only after authorizing the active membership; it is not a replacement for application authorization.';

CREATE TABLE eogp.audit_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    actor_organization_id uuid,
    actor_membership_id uuid,
    actor_service_principal_id uuid,
    actor_external_capability_id uuid,
    authorization_grant_owner_organization_id uuid,
    authorization_grant_id uuid,
    actor_kind text NOT NULL CHECK (actor_kind IN ('membership','service_principal','external_capability')),
    action text NOT NULL,
    aggregate_type text NOT NULL,
    aggregate_id uuid,
    request_id text,
    correlation_id uuid,
    reason_code text,
    safe_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
    occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    CHECK (
      (actor_kind = 'membership' AND actor_organization_id IS NOT NULL AND actor_membership_id IS NOT NULL AND actor_service_principal_id IS NULL AND actor_external_capability_id IS NULL)
      OR
      (actor_kind = 'service_principal' AND actor_organization_id IS NOT NULL AND actor_membership_id IS NULL AND actor_service_principal_id IS NOT NULL AND actor_external_capability_id IS NULL)
      OR
      (actor_kind = 'external_capability' AND actor_organization_id IS NULL AND actor_membership_id IS NULL AND actor_service_principal_id IS NULL AND actor_external_capability_id IS NOT NULL)
    ),
    CHECK ((authorization_grant_id IS NULL) = (authorization_grant_owner_organization_id IS NULL)),
    FOREIGN KEY (actor_organization_id, actor_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    FOREIGN KEY (actor_organization_id, actor_service_principal_id)
      REFERENCES eogp.service_principals(organization_id, id)
);
CREATE INDEX audit_events_aggregate_idx
    ON eogp.audit_events (organization_id, aggregate_type, aggregate_id, occurred_at DESC);
CREATE INDEX audit_events_occurred_idx
    ON eogp.audit_events (organization_id, occurred_at DESC);

CREATE TABLE eogp.outbox_events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    topic text NOT NULL,
    aggregate_type text NOT NULL,
    aggregate_id uuid NOT NULL,
    payload jsonb NOT NULL,
    idempotency_key text NOT NULL,
    occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    available_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    claimed_at timestamptz,
    published_at timestamptz,
    attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    last_error_code text,
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, idempotency_key)
);
CREATE INDEX outbox_ready_idx ON eogp.outbox_events (available_at, occurred_at)
    WHERE published_at IS NULL;

CREATE TABLE eogp.background_jobs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    job_type text NOT NULL,
    payload jsonb NOT NULL,
    state text NOT NULL DEFAULT 'queued'
        CHECK (state IN ('queued','running','succeeded','failed','cancelled')),
    idempotency_key text NOT NULL,
    available_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    started_at timestamptz,
    finished_at timestamptz,
    attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
    last_error_code text,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, job_type, idempotency_key),
    CHECK ((state = 'running') = (started_at IS NOT NULL AND finished_at IS NULL)),
    CHECK ((state IN ('succeeded','failed','cancelled')) = (finished_at IS NOT NULL))
);
CREATE INDEX background_jobs_ready_idx ON eogp.background_jobs (available_at)
    WHERE state IN ('queued','failed');

CREATE TABLE eogp.idempotency_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    principal_kind text NOT NULL CHECK (principal_kind IN ('membership','service_principal','external_capability')),
    principal_id uuid NOT NULL,
    operation_id text NOT NULL,
    idempotency_key text NOT NULL,
    request_sha256 text NOT NULL CHECK (request_sha256 ~ '^[0-9a-f]{64}$'),
    response_status integer,
    response_body jsonb,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    expires_at timestamptz NOT NULL,
    UNIQUE (organization_id, principal_kind, principal_id, operation_id, idempotency_key),
    CHECK (expires_at > created_at),
    CHECK ((response_status IS NULL) = (response_body IS NULL))
);
CREATE INDEX idempotency_expiry_idx ON eogp.idempotency_records (expires_at);
