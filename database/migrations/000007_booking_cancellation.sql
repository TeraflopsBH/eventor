-- Booking cancellation requests, immutable decisions, exactly-once effects and external action capabilities.
CREATE TABLE eogp.external_action_capabilities (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    booking_id uuid,
    booking_contact_id uuid,
    offer_revision_id uuid,
    action_code text NOT NULL CHECK (action_code IN ('offer_accept','booking_cancellation_request','booking_cancellation_status')),
    token_sha256 text NOT NULL UNIQUE CHECK (token_sha256 ~ '^[0-9a-f]{64}$'),
    issued_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    expires_at timestamptz NOT NULL,
    revoked_at timestamptz,
    max_uses integer NOT NULL DEFAULT 1 CHECK (max_uses > 0),
    use_count integer NOT NULL DEFAULT 0 CHECK (use_count >= 0),
    created_by_membership_id uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, booking_id) REFERENCES eogp.booking_records(organization_id, id),
    FOREIGN KEY (organization_id, offer_revision_id) REFERENCES eogp.booking_offer_revisions(organization_id, id),
    FOREIGN KEY (organization_id, booking_contact_id) REFERENCES eogp.booking_party_contacts(organization_id, id),
    FOREIGN KEY (organization_id, created_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    CHECK (expires_at > issued_at),
    CHECK (use_count <= max_uses),
    CHECK (
      (action_code = 'offer_accept' AND offer_revision_id IS NOT NULL AND booking_id IS NULL AND booking_contact_id IS NULL)
      OR (action_code <> 'offer_accept' AND offer_revision_id IS NULL AND booking_id IS NOT NULL)
    )
);
CREATE INDEX external_action_capabilities_booking_idx
  ON eogp.external_action_capabilities (organization_id, booking_id, action_code)
  WHERE revoked_at IS NULL AND booking_id IS NOT NULL;
CREATE INDEX external_action_capabilities_offer_idx
  ON eogp.external_action_capabilities (organization_id, offer_revision_id, action_code)
  WHERE revoked_at IS NULL AND offer_revision_id IS NOT NULL;

ALTER TABLE eogp.audit_events
  ADD CONSTRAINT audit_events_external_capability_fk
  FOREIGN KEY (organization_id, actor_external_capability_id)
  REFERENCES eogp.external_action_capabilities(organization_id, id)
  DEFERRABLE INITIALLY DEFERRED;

CREATE TABLE eogp.booking_cancellation_requests (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    booking_id uuid NOT NULL,
    requester_kind text NOT NULL CHECK (requester_kind IN ('external_contact','organization_member')),
    requester_contact_id uuid,
    requester_membership_id uuid,
    external_capability_id uuid,
    reason_code text NOT NULL,
    explanation text,
    status text NOT NULL DEFAULT 'submitted'
      CHECK (status IN ('submitted','under_review','approved','rejected','withdrawn','expired','effective')),
    requested_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    resolved_at timestamptz,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, booking_id) REFERENCES eogp.booking_records(organization_id, id),
    FOREIGN KEY (organization_id, requester_contact_id)
      REFERENCES eogp.booking_party_contacts(organization_id, id),
    FOREIGN KEY (organization_id, requester_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    FOREIGN KEY (organization_id, external_capability_id)
      REFERENCES eogp.external_action_capabilities(organization_id, id),
    CHECK (
      (requester_kind = 'external_contact'
       AND requester_contact_id IS NOT NULL
       AND requester_membership_id IS NULL
       AND external_capability_id IS NOT NULL)
      OR
      (requester_kind = 'organization_member'
       AND requester_contact_id IS NULL
       AND requester_membership_id IS NOT NULL
       AND external_capability_id IS NULL)
    ),
    CHECK ((status IN ('approved','rejected','withdrawn','expired','effective')) = (resolved_at IS NOT NULL))
);
CREATE INDEX booking_cancellation_requests_open_idx
  ON eogp.booking_cancellation_requests (organization_id, booking_id, requested_at DESC)
  WHERE status IN ('submitted','under_review');

CREATE TABLE eogp.booking_cancellation_decisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    cancellation_request_id uuid NOT NULL,
    decision text NOT NULL CHECK (decision IN ('approved','rejected','returned_for_changes')),
    actor_membership_id uuid NOT NULL,
    reason text NOT NULL,
    decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, cancellation_request_id)
      REFERENCES eogp.booking_cancellation_requests(organization_id, id),
    FOREIGN KEY (organization_id, actor_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);

CREATE TABLE eogp.booking_cancellation_effects (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    booking_id uuid NOT NULL,
    cancellation_request_id uuid NOT NULL,
    policy_revision_id uuid,
    effective_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    commercial_consequence_snapshot jsonb NOT NULL,
    resource_release_completed_at timestamptz,
    executed_by_membership_id uuid NOT NULL,
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, booking_id),
    FOREIGN KEY (organization_id, booking_id) REFERENCES eogp.booking_records(organization_id, id),
    FOREIGN KEY (organization_id, cancellation_request_id)
      REFERENCES eogp.booking_cancellation_requests(organization_id, id),
    FOREIGN KEY (organization_id, policy_revision_id)
      REFERENCES eogp.cancellation_policy_revisions(organization_id, id),
    FOREIGN KEY (organization_id, executed_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);

CREATE TABLE eogp.booking_cancellation_followups (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    cancellation_effect_id uuid NOT NULL,
    followup_kind text NOT NULL CHECK (followup_kind IN ('deposit_review','refund_due','credit_due','fee_due','manual_contact','other')),
    amount numeric(14,2) CHECK (amount IS NULL OR amount >= 0),
    currency char(3),
    status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_progress','completed','waived','not_applicable')),
    due_at timestamptz,
    notes_internal text,
    completed_at timestamptz,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, cancellation_effect_id)
      REFERENCES eogp.booking_cancellation_effects(organization_id, id),
    CHECK ((amount IS NULL) = (currency IS NULL))
);

CREATE TABLE eogp.booking_disruption_notices (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    booking_id uuid NOT NULL,
    notice_code text NOT NULL,
    reason_category text NOT NULL,
    public_summary text NOT NULL,
    operational_summary text,
    affected_from timestamptz,
    affected_until timestamptz,
    issued_by_membership_id uuid NOT NULL,
    issued_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, booking_id) REFERENCES eogp.booking_records(organization_id, id),
    FOREIGN KEY (organization_id, issued_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    CHECK (affected_until IS NULL OR affected_from IS NULL OR affected_until > affected_from)
);
CREATE INDEX booking_disruption_notices_booking_idx
  ON eogp.booking_disruption_notices (organization_id, booking_id, issued_at DESC);
