-- Eventor migration 000014: 000014_invitations_rsvp.sql
-- Apply only through scripts/db/apply-migrations.sh so the checksum ledger is updated.
BEGIN;
SET LOCAL search_path TO eogp, public;

SET LOCAL search_path TO eogp, public;

CREATE TABLE eogp.rsvp_policy_revisions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  revision_no     integer NOT NULL CHECK (revision_no > 0),
  response_deadline timestamptz,
  event_timezone  text NOT NULL,
  allow_guest_change_before_deadline boolean NOT NULL DEFAULT true,
  allow_staff_late_record boolean NOT NULL DEFAULT true,
  enabled_answers text[] NOT NULL DEFAULT ARRAY['accepted','declined','tentative'],
  reminder_policy jsonb NOT NULL DEFAULT '{}'::jsonb,
  status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published','retired')),
  published_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, event_id, id),
  UNIQUE (organization_id, event_id, revision_no),
  FOREIGN KEY (organization_id, event_id)
    REFERENCES eogp.events(organization_id, id) ON DELETE RESTRICT,
  CHECK (cardinality(enabled_answers) > 0),
  CHECK (enabled_answers <@ ARRAY['accepted','declined','tentative']::text[]),
  CHECK ((status='published') = (published_at IS NOT NULL))
);

CREATE TABLE eogp.invitations (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  participation_id uuid NOT NULL,
  status          text NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','issued','revoked','withdrawn','superseded','cancelled')),
  issued_at       timestamptz,
  created_by_membership_id uuid NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, event_id, id),
  UNIQUE (organization_id, event_id, participation_id),
  FOREIGN KEY (organization_id, event_id, participation_id)
    REFERENCES eogp.event_participations(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, created_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT,
  CHECK ((status='draft') OR issued_at IS NOT NULL)
);

CREATE TABLE eogp.invitation_revisions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  invitation_id   uuid NOT NULL,
  revision_no     integer NOT NULL CHECK (revision_no > 0),
  schedule_revision_id uuid NOT NULL,
  rsvp_policy_revision_id uuid NOT NULL,
  template_snapshot jsonb NOT NULL,
  guest_visible_snapshot jsonb NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, invitation_id, id),
  UNIQUE (organization_id, invitation_id, revision_no),
  FOREIGN KEY (organization_id, event_id, invitation_id)
    REFERENCES eogp.invitations(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, event_id, schedule_revision_id)
    REFERENCES eogp.event_schedule_revisions(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, event_id, rsvp_policy_revision_id)
    REFERENCES eogp.rsvp_policy_revisions(organization_id, event_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.invitation_links (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  invitation_id   uuid NOT NULL,
  invitation_revision_id uuid NOT NULL,
  token_hash      bytea NOT NULL UNIQUE CHECK (octet_length(token_hash) = 32),
  purpose_code    text NOT NULL DEFAULT 'guest_rsvp' CHECK (purpose_code = 'guest_rsvp'),
  expires_at      timestamptz NOT NULL,
  revoked_at      timestamptz,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (organization_id, invitation_id)
    REFERENCES eogp.invitations(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, invitation_id, invitation_revision_id)
    REFERENCES eogp.invitation_revisions(organization_id, invitation_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, id)
);

CREATE TABLE eogp.invitation_deliveries (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  invitation_id   uuid NOT NULL,
  invitation_revision_id uuid NOT NULL,
  channel         text NOT NULL CHECK (channel IN ('email','sms','other')),
  attempt_no      integer NOT NULL CHECK (attempt_no > 0),
  status          text NOT NULL CHECK (status IN ('queued','sent','delivered','failed','suppressed')),
  provider_code   text,
  provider_reference text,
  attempted_at    timestamptz,
  delivered_at    timestamptz,
  safe_error_code text,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (organization_id, invitation_id, invitation_revision_id)
    REFERENCES eogp.invitation_revisions(organization_id, invitation_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, invitation_id, channel, attempt_no),
  UNIQUE (organization_id, id)
);

CREATE TABLE eogp.rsvp_responses (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  participation_id uuid NOT NULL,
  invitation_id   uuid,
  invitation_link_id uuid,
  answer          text NOT NULL CHECK (answer IN ('accepted','declined','tentative')),
  source_code     text NOT NULL CHECK (source_code IN ('guest_link','phone','in_person','email','written','representative','import','other')),
  actor_kind      text NOT NULL CHECK (actor_kind IN ('guest','staff','representative','import')),
  actor_membership_id uuid,
  received_at     timestamptz,
  recorded_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  supersedes_response_id uuid,
  correction_reason text,
  late_override   boolean NOT NULL DEFAULT false,
  override_reason text,
  FOREIGN KEY (organization_id, event_id, participation_id)
    REFERENCES eogp.event_participations(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, invitation_id)
    REFERENCES eogp.invitations(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, invitation_link_id)
    REFERENCES eogp.invitation_links(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, actor_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, supersedes_response_id)
    REFERENCES eogp.rsvp_responses(organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, id),
  CHECK (
    (actor_kind='staff' AND actor_membership_id IS NOT NULL)
    OR (actor_kind IN ('guest','representative','import') AND actor_membership_id IS NULL)
  ),
  CHECK (actor_kind <> 'guest' OR invitation_link_id IS NOT NULL),
  CHECK (late_override = false OR (actor_kind='staff' AND override_reason IS NOT NULL)),
  CHECK (supersedes_response_id IS NULL OR correction_reason IS NOT NULL)
);

CREATE INDEX rsvp_responses_participation_history_idx
  ON eogp.rsvp_responses(organization_id, event_id, participation_id, recorded_at DESC);

CREATE INDEX invitation_links_expiry_idx
  ON eogp.invitation_links(expires_at)
  WHERE revoked_at IS NULL;

INSERT INTO eogp.schema_migrations(version, filename, checksum_sha256)
VALUES ('000014', '000014_invitations_rsvp.sql', :'migration_checksum');
COMMIT;
