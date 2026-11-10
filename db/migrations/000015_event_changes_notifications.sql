-- Eventor migration 000015: 000015_event_changes_notifications.sql
-- Apply only through scripts/db/apply-migrations.sh so the checksum ledger is updated.
BEGIN;
SET LOCAL search_path TO eogp, public;

SET LOCAL search_path TO eogp, public;

CREATE TABLE eogp.event_change_requests (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  change_kind     text NOT NULL CHECK (change_kind IN ('cancel','postpone','reschedule')),
  expected_event_revision_id uuid,
  reason_code     text NOT NULL,
  internal_explanation text,
  proposed_public_notice text,
  proposed_schedule_json jsonb,
  status          text NOT NULL DEFAULT 'submitted'
                  CHECK (status IN ('submitted','under_review','awaiting_clarification','approved','rejected','withdrawn','executed')),
  requested_by_membership_id uuid NOT NULL,
  requested_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, event_id, id),
  FOREIGN KEY (organization_id, event_id)
    REFERENCES eogp.events(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, event_id, expected_event_revision_id)
    REFERENCES eogp.event_schedule_revisions(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, requested_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.event_change_approval_decisions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  change_request_id uuid NOT NULL,
  decision        text NOT NULL CHECK (decision IN ('approved','rejected','returned_for_changes')),
  reason          text NOT NULL,
  actor_membership_id uuid NOT NULL,
  decided_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (organization_id, event_id, change_request_id)
    REFERENCES eogp.event_change_requests(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, actor_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, id)
);

CREATE TABLE eogp.event_decisions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  change_request_id uuid NOT NULL,
  decision_kind   text NOT NULL CHECK (decision_kind IN ('cancelled','postponed','rescheduled')),
  previous_schedule_revision_id uuid,
  replacement_schedule_revision_id uuid,
  internal_reason text NOT NULL,
  public_notice   text,
  executed_by_membership_id uuid NOT NULL,
  effective_at    timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, event_id, id),
  UNIQUE (organization_id, change_request_id),
  FOREIGN KEY (organization_id, event_id, change_request_id)
    REFERENCES eogp.event_change_requests(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, event_id, previous_schedule_revision_id)
    REFERENCES eogp.event_schedule_revisions(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, event_id, replacement_schedule_revision_id)
    REFERENCES eogp.event_schedule_revisions(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, executed_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT,
  CHECK (
    (decision_kind='rescheduled' AND replacement_schedule_revision_id IS NOT NULL)
    OR (decision_kind IN ('cancelled','postponed'))
  )
);

CREATE TABLE eogp.event_decision_sessions (
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  decision_id     uuid NOT NULL,
  session_id      uuid NOT NULL,
  effect_code     text NOT NULL CHECK (effect_code IN ('cancel','reschedule','retain','reconfirm')),
  PRIMARY KEY (organization_id, decision_id, session_id),
  FOREIGN KEY (organization_id, event_id, decision_id)
    REFERENCES eogp.event_decisions(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, event_id, session_id)
    REFERENCES eogp.event_sessions(organization_id, event_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.event_notification_templates (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id) ON DELETE RESTRICT,
  template_code   text NOT NULL,
  purpose_code    text NOT NULL CHECK (purpose_code IN ('event_cancellation','event_postponement','schedule_update','rsvp_reconfirmation')),
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, template_code)
);

CREATE TABLE eogp.event_notification_template_revisions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  template_id     uuid NOT NULL,
  revision_no     integer NOT NULL CHECK (revision_no > 0),
  locale          text NOT NULL,
  subject_template text NOT NULL,
  body_template   text NOT NULL,
  published_at    timestamptz,
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, template_id, id),
  UNIQUE (organization_id, template_id, revision_no, locale),
  FOREIGN KEY (organization_id, template_id)
    REFERENCES eogp.event_notification_templates(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.event_notification_campaigns (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  event_decision_id uuid NOT NULL,
  template_revision_id uuid NOT NULL,
  purpose_code    text NOT NULL CHECK (purpose_code IN ('event_cancellation','event_postponement','schedule_update','rsvp_reconfirmation')),
  audience_code   text NOT NULL CHECK (audience_code IN ('accepted_tentative','active_invitees','all_previously_invited','custom')),
  audience_snapshot_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  status          text NOT NULL DEFAULT 'prepared' CHECK (status IN ('prepared','queued','sending','completed','completed_with_failures','cancelled')),
  created_by_membership_id uuid NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, event_id, id),
  FOREIGN KEY (organization_id, event_id, event_decision_id)
    REFERENCES eogp.event_decisions(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, template_revision_id)
    REFERENCES eogp.event_notification_template_revisions(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.event_notification_recipients (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  campaign_id     uuid NOT NULL,
  event_id        uuid NOT NULL,
  participation_id uuid NOT NULL,
  channel         text NOT NULL CHECK (channel IN ('email','sms','other')),
  qualification_code text NOT NULL,
  contact_snapshot_ciphertext bytea NOT NULL,
  contact_snapshot_key_id text NOT NULL,
  locale          text NOT NULL,
  status          text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','queued','sent','delivered','failed','suppressed','excluded')),
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, campaign_id, participation_id, channel),
  FOREIGN KEY (organization_id, event_id, campaign_id)
    REFERENCES eogp.event_notification_campaigns(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, event_id, participation_id)
    REFERENCES eogp.event_participations(organization_id, event_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.event_notification_delivery_attempts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  recipient_id    uuid NOT NULL,
  attempt_no      integer NOT NULL CHECK (attempt_no > 0),
  status          text NOT NULL CHECK (status IN ('queued','sent','delivered','failed','suppressed')),
  provider_code   text,
  provider_reference text,
  attempted_at    timestamptz,
  delivered_at    timestamptz,
  safe_error_code text,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (organization_id, recipient_id)
    REFERENCES eogp.event_notification_recipients(organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, recipient_id, attempt_no),
  UNIQUE (organization_id, id)
);

INSERT INTO eogp.schema_migrations(version, filename, checksum_sha256)
VALUES ('000015', '000015_event_changes_notifications.sql', :'migration_checksum');
COMMIT;
