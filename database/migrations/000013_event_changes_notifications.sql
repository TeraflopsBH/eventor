-- Event changes, cancellation/postponement decisions and fixed-audience notification campaigns.
CREATE TABLE eogp.event_change_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    change_kind text NOT NULL CHECK (change_kind IN ('cancel','postpone','reschedule')),
    expected_event_revision integer NOT NULL CHECK (expected_event_revision > 0),
    reason_code text NOT NULL,
    reason_internal text,
    public_message text,
    replacement_schedule_revision_id uuid,
    status text NOT NULL DEFAULT 'submitted'
      CHECK (status IN ('submitted','under_review','approved','rejected','withdrawn','executed')),
    initiated_by_membership_id uuid NOT NULL,
    submitted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    resolved_at timestamptz,
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id) REFERENCES eogp.events(organization_id, id),
    FOREIGN KEY (organization_id, event_id, replacement_schedule_revision_id)
      REFERENCES eogp.event_schedule_revisions(organization_id, event_id, id),
    FOREIGN KEY (organization_id, initiated_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    CHECK ((status IN ('approved','rejected','withdrawn','executed')) = (resolved_at IS NOT NULL)),
    CHECK ((change_kind = 'reschedule') = (replacement_schedule_revision_id IS NOT NULL))
);

CREATE TABLE eogp.event_change_approval_decisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    change_request_id uuid NOT NULL,
    decision text NOT NULL CHECK (decision IN ('approved','rejected','returned_for_changes')),
    actor_membership_id uuid NOT NULL,
    reason text NOT NULL,
    decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, event_id, change_request_id)
      REFERENCES eogp.event_change_requests(organization_id, event_id, id),
    FOREIGN KEY (organization_id, actor_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);

CREATE TABLE eogp.event_decisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    source_change_request_id uuid NOT NULL,
    decision_kind text NOT NULL CHECK (decision_kind IN ('cancelled','postponed','rescheduled')),
    original_schedule_revision_id uuid,
    replacement_schedule_revision_id uuid,
    reason_code text NOT NULL,
    reason_internal text,
    public_message text,
    executed_by_membership_id uuid NOT NULL,
    effective_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_id, id),
    UNIQUE (organization_id, source_change_request_id),
    FOREIGN KEY (organization_id, event_id, source_change_request_id)
      REFERENCES eogp.event_change_requests(organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id, original_schedule_revision_id)
      REFERENCES eogp.event_schedule_revisions(organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id, replacement_schedule_revision_id)
      REFERENCES eogp.event_schedule_revisions(organization_id, event_id, id),
    FOREIGN KEY (organization_id, executed_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    CHECK (
      (decision_kind = 'cancelled' AND replacement_schedule_revision_id IS NULL)
      OR decision_kind = 'postponed'
      OR (decision_kind = 'rescheduled' AND replacement_schedule_revision_id IS NOT NULL)
    )
);

CREATE TABLE eogp.event_decision_sessions (
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    decision_id uuid NOT NULL,
    session_id uuid NOT NULL,
    outcome text NOT NULL CHECK (outcome IN ('cancelled','postponed','rescheduled','unaffected')),
    PRIMARY KEY (organization_id, decision_id, session_id),
    FOREIGN KEY (organization_id, event_id, decision_id)
      REFERENCES eogp.event_decisions(organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id, session_id)
      REFERENCES eogp.event_sessions(organization_id, event_id, id)
);

CREATE TABLE eogp.event_status_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    previous_status text,
    new_status text NOT NULL,
    decision_id uuid,
    actor_membership_id uuid,
    reason_code text,
    changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, event_id) REFERENCES eogp.events(organization_id, id),
    FOREIGN KEY (organization_id, event_id, decision_id)
      REFERENCES eogp.event_decisions(organization_id, event_id, id),
    FOREIGN KEY (organization_id, actor_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);

CREATE TABLE eogp.notification_templates (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    code text NOT NULL,
    purpose text NOT NULL
      CHECK (purpose IN ('booking_notice','invitation','rsvp_reminder','event_cancellation','event_postponement','schedule_update','rsvp_reconfirmation')),
    status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, code)
);

CREATE TABLE eogp.notification_template_revisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    template_id uuid NOT NULL,
    revision_number integer NOT NULL CHECK (revision_number > 0),
    locale text NOT NULL DEFAULT 'bs-BA',
    subject_template text NOT NULL,
    body_template text NOT NULL,
    state text NOT NULL DEFAULT 'draft' CHECK (state IN ('draft','published','retired')),
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, template_id, id),
    UNIQUE (organization_id, template_id, revision_number, locale),
    FOREIGN KEY (organization_id, template_id) REFERENCES eogp.notification_templates(organization_id, id)
);

ALTER TABLE eogp.invitation_revisions
  ADD CONSTRAINT invitation_revisions_template_fk
  FOREIGN KEY (organization_id, template_revision_id)
  REFERENCES eogp.notification_template_revisions(organization_id, id);

CREATE TABLE eogp.event_notification_campaigns (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    event_decision_id uuid NOT NULL,
    purpose text NOT NULL
      CHECK (purpose IN ('event_cancellation','event_postponement','schedule_update','rsvp_reconfirmation')),
    audience_kind text NOT NULL
      CHECK (audience_kind IN ('accepted_tentative','all_active_invitees','all_previously_invited','custom')),
    status text NOT NULL DEFAULT 'draft'
      CHECK (status IN ('draft','previewed','confirmed','queued','sending','completed','partial','failed','cancelled')),
    template_revision_id uuid NOT NULL,
    audience_rules_snapshot jsonb NOT NULL,
    recipient_count integer CHECK (recipient_count IS NULL OR recipient_count >= 0),
    confirmed_by_membership_id uuid,
    confirmed_at timestamptz,
    created_by_membership_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id, event_decision_id)
      REFERENCES eogp.event_decisions(organization_id, event_id, id),
    FOREIGN KEY (organization_id, template_revision_id)
      REFERENCES eogp.notification_template_revisions(organization_id, id),
    FOREIGN KEY (organization_id, confirmed_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    FOREIGN KEY (organization_id, created_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    CHECK ((confirmed_at IS NULL) = (confirmed_by_membership_id IS NULL))
);

CREATE TABLE eogp.event_notification_recipients (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    campaign_id uuid NOT NULL,
    participation_id uuid,
    invitation_id uuid,
    qualification_reason text NOT NULL,
    channel text NOT NULL CHECK (channel IN ('email','sms','other')),
    destination_ciphertext bytea NOT NULL,
    destination_hash text NOT NULL,
    status text NOT NULL DEFAULT 'pending'
      CHECK (status IN ('pending','queued','sent','delivered','failed','suppressed','excluded')),
    suppression_reason text,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, campaign_id, id),
    FOREIGN KEY (organization_id, event_id, campaign_id)
      REFERENCES eogp.event_notification_campaigns(organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id, participation_id)
      REFERENCES eogp.event_participations(organization_id, event_id, id),
    FOREIGN KEY (organization_id, event_id, invitation_id, participation_id)
      REFERENCES eogp.invitations(organization_id, event_id, id, participation_id),
    CHECK (participation_id IS NOT NULL OR invitation_id IS NOT NULL),
    CHECK (invitation_id IS NULL OR participation_id IS NOT NULL)
);
CREATE INDEX event_notification_recipients_pending_idx
  ON eogp.event_notification_recipients (organization_id, campaign_id, status);

CREATE TABLE eogp.event_notification_delivery_attempts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    campaign_id uuid NOT NULL,
    recipient_id uuid NOT NULL,
    attempt_number integer NOT NULL CHECK (attempt_number > 0),
    status text NOT NULL CHECK (status IN ('queued','sending','sent','delivered','failed','bounced','suppressed')),
    provider_name text,
    provider_message_reference text,
    attempted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    delivered_at timestamptz,
    failed_at timestamptz,
    failure_code text,
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, recipient_id, attempt_number),
    FOREIGN KEY (organization_id, campaign_id, recipient_id)
      REFERENCES eogp.event_notification_recipients(organization_id, campaign_id, id)
);
CREATE INDEX event_notification_delivery_retry_idx
  ON eogp.event_notification_delivery_attempts (organization_id, attempted_at)
  WHERE status IN ('failed','bounced');

