-- Invitation issuance, secure invitation links, RSVP policy and append-only response history.
CREATE TABLE eogp.rsvp_policies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    code text NOT NULL,
    name text NOT NULL,
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_id, id),
    UNIQUE (organization_id, event_id, code),
    FOREIGN KEY (organization_id, event_id) REFERENCES eogp.events(organization_id, id)
);

CREATE TABLE eogp.rsvp_policy_revisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    policy_id uuid NOT NULL,
    revision_number integer NOT NULL CHECK (revision_number > 0),
    allowed_responses jsonb NOT NULL DEFAULT '["accepted","declined","tentative"]'::jsonb,
    response_deadline timestamptz,
    event_timezone text NOT NULL,
    response_change_allowed boolean NOT NULL DEFAULT true,
    late_change_requires_staff boolean NOT NULL DEFAULT true,
    reminder_policy jsonb NOT NULL DEFAULT '{}'::jsonb,
    state text NOT NULL DEFAULT 'draft' CHECK (state IN ('draft','published','retired')),
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_id, policy_id, id),
    UNIQUE (organization_id, policy_id, revision_number),
    FOREIGN KEY (organization_id, event_id, policy_id)
      REFERENCES eogp.rsvp_policies(organization_id, event_id, id),
    CHECK (jsonb_typeof(allowed_responses) = 'array')
);

CREATE TABLE eogp.invitations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    participation_id uuid NOT NULL,
    status text NOT NULL DEFAULT 'draft'
      CHECK (status IN ('draft','active','revoked','replaced','withdrawn','suppressed','expired')),
    current_revision_number integer NOT NULL DEFAULT 0 CHECK (current_revision_number >= 0),
    issued_at timestamptz,
    revoked_at timestamptz,
    created_by_membership_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id, participation_id)
      REFERENCES eogp.event_participations(organization_id, event_id, id),
    FOREIGN KEY (organization_id, created_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    CHECK ((status = 'revoked') = (revoked_at IS NOT NULL)),
    CHECK (status = 'draft' OR issued_at IS NOT NULL)
);
CREATE INDEX invitations_event_active_idx
  ON eogp.invitations (organization_id, event_id, status);

CREATE TABLE eogp.invitation_revisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    invitation_id uuid NOT NULL,
    revision_number integer NOT NULL CHECK (revision_number > 0),
    schedule_revision_id uuid NOT NULL,
    rsvp_policy_revision_id uuid NOT NULL,
    template_revision_id uuid,
    locale text NOT NULL DEFAULT 'bs-BA',
    presentation_snapshot jsonb NOT NULL,
    issued_at timestamptz,
    created_by_membership_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_id, invitation_id, id),
    UNIQUE (organization_id, invitation_id, revision_number),
    FOREIGN KEY (organization_id, event_id, invitation_id)
      REFERENCES eogp.invitations(organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id, schedule_revision_id)
      REFERENCES eogp.event_schedule_revisions(organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id, rsvp_policy_revision_id)
      REFERENCES eogp.rsvp_policy_revisions(organization_id, event_id, id),
    FOREIGN KEY (organization_id, created_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);

CREATE TABLE eogp.invitation_links (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    invitation_id uuid NOT NULL,
    invitation_revision_id uuid NOT NULL,
    token_sha256 text NOT NULL UNIQUE CHECK (token_sha256 ~ '^[0-9a-f]{64}$'),
    issued_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    replaced_by_link_id uuid,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, event_id, invitation_id)
      REFERENCES eogp.invitations(organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id, invitation_id, invitation_revision_id)
      REFERENCES eogp.invitation_revisions(organization_id, event_id, invitation_id, id),
    FOREIGN KEY (organization_id, replaced_by_link_id)
      REFERENCES eogp.invitation_links(organization_id, id),
    CHECK (expires_at > issued_at),
    CHECK (replaced_by_link_id IS NULL OR replaced_by_link_id <> id)
);
CREATE INDEX invitation_links_active_idx
  ON eogp.invitation_links (organization_id, event_id, invitation_id, expires_at)
  WHERE revoked_at IS NULL;

CREATE TABLE eogp.invitation_deliveries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    invitation_id uuid NOT NULL,
    invitation_revision_id uuid NOT NULL,
    channel text NOT NULL CHECK (channel IN ('email','sms','other')),
    destination_ciphertext bytea NOT NULL,
    destination_hash text NOT NULL,
    status text NOT NULL DEFAULT 'queued'
      CHECK (status IN ('queued','sending','sent','delivered','bounced','failed','suppressed')),
    provider_name text,
    provider_message_reference text,
    queued_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    sent_at timestamptz,
    delivered_at timestamptz,
    failed_at timestamptz,
    failure_code text,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, event_id, invitation_id, invitation_revision_id)
      REFERENCES eogp.invitation_revisions(organization_id, event_id, invitation_id, id)
);
CREATE INDEX invitation_deliveries_pending_idx
  ON eogp.invitation_deliveries (organization_id, queued_at)
  WHERE status IN ('queued','failed');

CREATE TABLE eogp.rsvp_responses (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    participation_id uuid NOT NULL,
    invitation_id uuid,
    invitation_revision_id uuid,
    schedule_revision_id uuid NOT NULL,
    sequence_number integer NOT NULL CHECK (sequence_number > 0),
    response text NOT NULL CHECK (response IN ('accepted','declined','tentative')),
    source_channel text NOT NULL
      CHECK (source_channel IN ('invitation_link','phone','in_person','email','written','representative','staff_entry','other')),
    respondent_kind text NOT NULL CHECK (respondent_kind IN ('guest','representative','staff')),
    received_at timestamptz NOT NULL,
    recorded_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    actor_membership_id uuid,
    invitation_link_id uuid,
    correction_of_response_id uuid,
    correction_reason text,
    notes_restricted text,
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_id, participation_id, id),
    UNIQUE (organization_id, participation_id, sequence_number),
    FOREIGN KEY (organization_id, event_id, participation_id)
      REFERENCES eogp.event_participations(organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id, invitation_id)
      REFERENCES eogp.invitations(organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id, invitation_id, invitation_revision_id)
      REFERENCES eogp.invitation_revisions(organization_id, event_id, invitation_id, id),
    FOREIGN KEY (organization_id, event_id, schedule_revision_id)
      REFERENCES eogp.event_schedule_revisions(organization_id, event_id, id),
    FOREIGN KEY (organization_id, actor_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    FOREIGN KEY (organization_id, event_id, invitation_link_id)
      REFERENCES eogp.invitation_links(organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id, participation_id, correction_of_response_id)
      REFERENCES eogp.rsvp_responses(organization_id, event_id, participation_id, id),
    CHECK ((source_channel = 'invitation_link' AND respondent_kind = 'guest'
            AND invitation_link_id IS NOT NULL AND actor_membership_id IS NULL)
       OR (source_channel <> 'invitation_link' AND respondent_kind IN ('representative','staff')
            AND actor_membership_id IS NOT NULL AND invitation_link_id IS NULL)),
    CHECK ((correction_of_response_id IS NULL) = (correction_reason IS NULL)),
    CHECK (received_at <= recorded_at)
);
CREATE INDEX rsvp_responses_latest_idx
  ON eogp.rsvp_responses (organization_id, event_id, participation_id, sequence_number DESC);
