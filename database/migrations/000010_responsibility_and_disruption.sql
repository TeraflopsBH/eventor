-- Explicit task accountability, delegated performance, scoped role assignments and event-side disruption handling.
CREATE TABLE eogp.event_responsibility_assignments (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    task_code text NOT NULL,
    task_label text NOT NULL,
    accountable_party_kind text NOT NULL
      CHECK (accountable_party_kind IN ('event_owner','organization','external_party')),
    accountable_organization_id uuid,
    accountable_external_party text,
    performing_party_kind text NOT NULL
      CHECK (performing_party_kind IN ('event_owner','organization','external_party')),
    performing_organization_id uuid,
    performing_membership_id uuid,
    performing_external_party text,
    grant_owner_organization_id uuid,
    collaboration_grant_id uuid,
    approver_organization_id uuid,
    approver_membership_id uuid,
    informed_parties jsonb NOT NULL DEFAULT '[]'::jsonb,
    permitted_projection jsonb NOT NULL DEFAULT '{}'::jsonb,
    due_at timestamptz,
    status text NOT NULL DEFAULT 'not_started'
      CHECK (status IN ('not_started','in_progress','blocked','completed','cancelled','waived')),
    evidence_reference jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_by_membership_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, event_id) REFERENCES eogp.events(organization_id, id),
    FOREIGN KEY (accountable_organization_id) REFERENCES eogp.organizations(id),
    FOREIGN KEY (performing_organization_id) REFERENCES eogp.organizations(id),
    FOREIGN KEY (performing_organization_id, performing_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    FOREIGN KEY (grant_owner_organization_id, performing_organization_id, collaboration_grant_id)
      REFERENCES eogp.collaboration_grants(organization_id, grantee_organization_id, id),
    FOREIGN KEY (approver_organization_id, approver_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    FOREIGN KEY (organization_id, created_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    CHECK (
      (accountable_party_kind = 'event_owner' AND accountable_organization_id IS NULL AND accountable_external_party IS NULL)
      OR (accountable_party_kind = 'organization' AND accountable_organization_id IS NOT NULL AND accountable_external_party IS NULL)
      OR (accountable_party_kind = 'external_party' AND accountable_organization_id IS NULL AND accountable_external_party IS NOT NULL)
    ),
    CHECK (
      (performing_party_kind = 'event_owner' AND performing_organization_id IS NULL AND performing_membership_id IS NULL AND performing_external_party IS NULL)
      OR (performing_party_kind = 'organization' AND performing_organization_id IS NOT NULL AND performing_external_party IS NULL)
      OR (performing_party_kind = 'external_party' AND performing_organization_id IS NULL AND performing_membership_id IS NULL AND performing_external_party IS NOT NULL)
    ),
    CHECK ((collaboration_grant_id IS NULL) = (grant_owner_organization_id IS NULL)),
    CHECK ((approver_membership_id IS NULL) = (approver_organization_id IS NULL))
);
CREATE INDEX event_responsibilities_event_idx
  ON eogp.event_responsibility_assignments (organization_id, event_id, status, due_at);

CREATE TABLE eogp.event_disruption_resolutions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    source_provider_organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    source_booking_notice_id uuid NOT NULL,
    source_notice_snapshot jsonb NOT NULL,
    resolution_kind text NOT NULL DEFAULT 'unresolved'
      CHECK (resolution_kind IN ('relocate','amend_booking','postpone','cancel_event','unresolved')),
    status text NOT NULL DEFAULT 'acknowledged'
      CHECK (status IN ('received','acknowledged','in_progress','resolved','dismissed')),
    grant_owner_organization_id uuid,
    collaboration_grant_id uuid,
    acknowledged_by_membership_id uuid,
    acknowledged_at timestamptz,
    resolved_by_membership_id uuid,
    resolved_at timestamptz,
    resolution_notes text,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, event_id) REFERENCES eogp.events(organization_id, id),
    FOREIGN KEY (grant_owner_organization_id, organization_id, collaboration_grant_id)
      REFERENCES eogp.collaboration_grants(organization_id, grantee_organization_id, id),
    FOREIGN KEY (organization_id, acknowledged_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    FOREIGN KEY (organization_id, resolved_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    CHECK ((collaboration_grant_id IS NULL) = (grant_owner_organization_id IS NULL)),
    CHECK ((acknowledged_at IS NULL) = (acknowledged_by_membership_id IS NULL)),
    CHECK ((resolved_at IS NULL) = (resolved_by_membership_id IS NULL))
);
CREATE INDEX event_disruption_resolutions_event_idx
  ON eogp.event_disruption_resolutions (organization_id, event_id, created_at DESC);

CREATE TABLE eogp.event_prerequisites (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    responsibility_assignment_id uuid NOT NULL,
    requirement_code text NOT NULL,
    title text NOT NULL,
    external_authority_label text,
    status text NOT NULL DEFAULT 'not_started'
      CHECK (status IN ('not_started','submitted','scheduled','completed','not_required','blocked','cancelled')),
    due_at timestamptz,
    reference_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, event_id) REFERENCES eogp.events(organization_id, id),
    FOREIGN KEY (organization_id, responsibility_assignment_id)
      REFERENCES eogp.event_responsibility_assignments(organization_id, id)
);

CREATE TABLE eogp.user_role_grants (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    membership_id uuid NOT NULL,
    role_id uuid NOT NULL,
    scope_kind text NOT NULL
      CHECK (scope_kind IN ('organization','venue','space','booking','event','task')),
    scope_venue_id uuid,
    scope_space_id uuid,
    scope_booking_id uuid,
    scope_event_id uuid,
    scope_task_id uuid,
    granted_by_membership_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    expires_at timestamptz,
    revoked_at timestamptz,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    FOREIGN KEY (organization_id, role_id)
      REFERENCES eogp.roles(organization_id, id),
    FOREIGN KEY (organization_id, scope_venue_id) REFERENCES eogp.venues(organization_id, id),
    FOREIGN KEY (organization_id, scope_space_id) REFERENCES eogp.venue_spaces(organization_id, id),
    FOREIGN KEY (organization_id, scope_booking_id) REFERENCES eogp.booking_records(organization_id, id),
    FOREIGN KEY (organization_id, scope_event_id) REFERENCES eogp.events(organization_id, id),
    FOREIGN KEY (organization_id, scope_task_id)
      REFERENCES eogp.event_responsibility_assignments(organization_id, id),
    FOREIGN KEY (organization_id, granted_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    CHECK (
      (scope_kind = 'organization' AND num_nonnulls(scope_venue_id,scope_space_id,scope_booking_id,scope_event_id,scope_task_id) = 0)
      OR (scope_kind = 'venue' AND scope_venue_id IS NOT NULL AND num_nonnulls(scope_space_id,scope_booking_id,scope_event_id,scope_task_id) = 0)
      OR (scope_kind = 'space' AND scope_space_id IS NOT NULL AND num_nonnulls(scope_venue_id,scope_booking_id,scope_event_id,scope_task_id) = 0)
      OR (scope_kind = 'booking' AND scope_booking_id IS NOT NULL AND num_nonnulls(scope_venue_id,scope_space_id,scope_event_id,scope_task_id) = 0)
      OR (scope_kind = 'event' AND scope_event_id IS NOT NULL AND num_nonnulls(scope_venue_id,scope_space_id,scope_booking_id,scope_task_id) = 0)
      OR (scope_kind = 'task' AND scope_task_id IS NOT NULL AND num_nonnulls(scope_venue_id,scope_space_id,scope_booking_id,scope_event_id) = 0)
    ),
    CHECK ((expires_at IS NULL OR revoked_at IS NULL) AND (expires_at IS NULL OR expires_at > created_at))
);
CREATE INDEX user_role_grants_membership_idx
  ON eogp.user_role_grants (organization_id, membership_id, scope_kind)
  WHERE revoked_at IS NULL;

COMMENT ON COLUMN eogp.event_disruption_resolutions.source_booking_notice_id IS
  'Opaque source reference: deliberately not a cross-tenant FK; notice snapshot and provider org are retained on the event-owned side.';
