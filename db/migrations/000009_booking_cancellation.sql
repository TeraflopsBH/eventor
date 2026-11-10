-- Eventor migration 000009: 000009_booking_cancellation.sql
-- Apply only through scripts/db/apply-migrations.sh so the checksum ledger is updated.
BEGIN;
SET LOCAL search_path TO eogp, public;

SET LOCAL search_path TO eogp, public;

CREATE TABLE eogp.cancellation_policies (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id) ON DELETE RESTRICT,
  code            text NOT NULL,
  name            text NOT NULL,
  status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','retired')),
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, code)
);

CREATE TABLE eogp.cancellation_policy_revisions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  policy_id       uuid NOT NULL,
  revision_no     integer NOT NULL CHECK (revision_no > 0),
  policy_json     jsonb NOT NULL,
  customer_terms  text NOT NULL,
  status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','retired')),
  published_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, policy_id, id),
  UNIQUE (organization_id, policy_id, revision_no),
  FOREIGN KEY (organization_id, policy_id)
    REFERENCES eogp.cancellation_policies(organization_id, id) ON DELETE RESTRICT,
  CHECK ((status='published') = (published_at IS NOT NULL))
);

ALTER TABLE eogp.booking_records
  ADD COLUMN cancellation_policy_revision_id uuid,
  ADD CONSTRAINT booking_cancellation_policy_fk
    FOREIGN KEY (organization_id, cancellation_policy_revision_id)
    REFERENCES eogp.cancellation_policy_revisions(organization_id, id) ON DELETE RESTRICT;

CREATE TABLE eogp.external_booking_action_capabilities (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  booking_id      uuid NOT NULL,
  booking_contact_id uuid NOT NULL,
  token_hash      bytea NOT NULL UNIQUE CHECK (octet_length(token_hash) = 32),
  allowed_actions text[] NOT NULL CHECK (cardinality(allowed_actions) > 0),
  expires_at      timestamptz NOT NULL,
  revoked_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  last_used_at    timestamptz,
  UNIQUE (organization_id, id),
  FOREIGN KEY (organization_id, booking_id)
    REFERENCES eogp.booking_records(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, booking_contact_id)
    REFERENCES eogp.booking_party_contacts(organization_id, id) ON DELETE RESTRICT,
  CHECK (NOT ('booking.cancellation.approve' = ANY(allowed_actions))),
  CHECK (NOT ('booking.cancellation.execute' = ANY(allowed_actions)))
);

ALTER TABLE eogp.audit_events
  ADD CONSTRAINT audit_events_external_capability_fk
  FOREIGN KEY (organization_id, actor_external_capability_id)
  REFERENCES eogp.external_booking_action_capabilities(organization_id, id) ON DELETE RESTRICT;

CREATE TABLE eogp.booking_cancellation_requests (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  booking_id      uuid NOT NULL,
  requester_kind  text NOT NULL CHECK (requester_kind IN ('booking_contact','venue_member','system')),
  booking_contact_id uuid,
  requester_membership_id uuid,
  external_capability_id uuid,
  reason_code     text NOT NULL,
  explanation     text,
  status          text NOT NULL DEFAULT 'submitted'
                  CHECK (status IN ('submitted','under_review','awaiting_clarification','approved','rejected','withdrawn','expired','executed')),
  submitted_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  FOREIGN KEY (organization_id, booking_id)
    REFERENCES eogp.booking_records(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, booking_contact_id)
    REFERENCES eogp.booking_party_contacts(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, requester_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, external_capability_id)
    REFERENCES eogp.external_booking_action_capabilities(organization_id, id) ON DELETE RESTRICT,
  CHECK (
    (requester_kind='booking_contact' AND booking_contact_id IS NOT NULL AND requester_membership_id IS NULL AND external_capability_id IS NOT NULL)
    OR (requester_kind='venue_member' AND booking_contact_id IS NULL AND requester_membership_id IS NOT NULL AND external_capability_id IS NULL)
    OR (requester_kind='system' AND booking_contact_id IS NULL AND requester_membership_id IS NULL AND external_capability_id IS NULL)
  )
);

CREATE UNIQUE INDEX booking_one_open_cancellation_request
  ON eogp.booking_cancellation_requests(organization_id, booking_id)
  WHERE status IN ('submitted','under_review','awaiting_clarification');

CREATE TABLE eogp.booking_cancellation_decisions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  request_id      uuid NOT NULL,
  decision        text NOT NULL CHECK (decision IN ('approved','rejected','returned_for_changes')),
  actor_membership_id uuid NOT NULL,
  reason          text NOT NULL,
  decided_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (organization_id, request_id)
    REFERENCES eogp.booking_cancellation_requests(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, actor_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, id)
);

CREATE TABLE eogp.booking_cancellation_effects (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  booking_id      uuid NOT NULL,
  request_id      uuid NOT NULL,
  effective_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  commercial_consequence_snapshot jsonb NOT NULL,
  resource_release_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
  executed_by_membership_id uuid NOT NULL,
  UNIQUE (organization_id, booking_id),
  UNIQUE (organization_id, request_id),
  FOREIGN KEY (organization_id, booking_id)
    REFERENCES eogp.booking_records(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, request_id)
    REFERENCES eogp.booking_cancellation_requests(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, executed_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.booking_cancellation_followups (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  cancellation_effect_id uuid NOT NULL,
  followup_kind   text NOT NULL CHECK (followup_kind IN ('deposit_review','refund_review','credit_review','balance_review','customer_contact','venue_task')),
  status          text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','in_progress','completed','not_required')),
  amount          numeric(14,2) CHECK (amount IS NULL OR amount >= 0),
  currency        char(3),
  note            text,
  updated_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (organization_id, cancellation_effect_id)
    REFERENCES eogp.booking_cancellation_effects(organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, id)
);

CREATE TABLE eogp.booking_disruption_notices (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  booking_id      uuid NOT NULL,
  notice_code     text NOT NULL,
  reason_code     text NOT NULL,
  safe_summary    text NOT NULL,
  affected_from   timestamptz,
  affected_to     timestamptz,
  issued_by_membership_id uuid NOT NULL,
  issued_at       timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (organization_id, booking_id)
    REFERENCES eogp.booking_records(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, issued_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, id),
  CHECK (affected_to IS NULL OR affected_from IS NULL OR affected_to > affected_from)
);

INSERT INTO eogp.schema_migrations(version, filename, checksum_sha256)
VALUES ('000009', '000009_booking_cancellation.sql', :'migration_checksum');
COMMIT;
