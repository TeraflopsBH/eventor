-- Scoped task execution and audited lifecycle transitions for delegated links/shares.
BEGIN;

-- Permission checked by the booking reservation release command.
INSERT INTO eogp.permissions (code, description, scope_kind, is_sensitive)
VALUES
  ('task.perform','Perform an explicitly assigned event responsibility task','task',true)
ON CONFLICT (code) DO NOTHING;

-- Status changes must identify the actor and a machine-readable reason.
ALTER TABLE eogp.booking_event_links
  ADD COLUMN status_changed_by_membership_id uuid,
  ADD COLUMN status_change_reason_code text,
  ADD CONSTRAINT booking_event_links_status_actor_fk
    FOREIGN KEY (organization_id, status_changed_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id),
  ADD CONSTRAINT booking_event_links_status_actor_pair_ck
    CHECK (
      (status = 'active' AND status_changed_by_membership_id IS NULL
                         AND status_change_reason_code IS NULL)
      OR
      (status IN ('ended','revoked') AND status_changed_by_membership_id IS NOT NULL
                                     AND status_change_reason_code IS NOT NULL
                                     AND length(btrim(status_change_reason_code)) > 0)
    );

ALTER TABLE eogp.venue_snapshot_shares
  ADD COLUMN status_changed_by_membership_id uuid,
  ADD COLUMN status_change_reason_code text,
  ADD CONSTRAINT venue_snapshot_shares_status_actor_fk
    FOREIGN KEY (organization_id, status_changed_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id),
  ADD CONSTRAINT venue_snapshot_shares_status_actor_pair_ck
    CHECK (
      (status = 'active' AND status_changed_by_membership_id IS NULL
                         AND status_change_reason_code IS NULL)
      OR
      (status IN ('revoked','expired') AND status_changed_by_membership_id IS NOT NULL
                                        AND status_change_reason_code IS NOT NULL
                                        AND length(btrim(status_change_reason_code)) > 0)
    );

CREATE OR REPLACE FUNCTION eogp.enforce_booking_event_link_grant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_organization_id uuid := eogp.current_organization_id();
  v_member_status text;
  v_grant_status text;
  v_scope_kind text;
  v_scope_booking_id uuid;
  v_valid_from timestamptz;
  v_valid_until timestamptz;
  v_allowed_actions text[];
BEGIN
  IF v_organization_id IS NULL OR NEW.organization_id <> v_organization_id THEN
    RAISE EXCEPTION 'event-owner tenant context is required for a booking-event link'
      USING ERRCODE = '42501';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'active'
       OR NEW.status_changed_by_membership_id IS NOT NULL
       OR NEW.status_change_reason_code IS NOT NULL THEN
      RAISE EXCEPTION 'new booking-event links must start active without a status-change actor'
        USING ERRCODE = '23514';
    END IF;
  ELSE
    IF OLD.status <> 'active'
       OR NEW.status NOT IN ('ended','revoked')
       OR (to_jsonb(NEW) - 'status' - 'status_changed_by_membership_id' - 'status_change_reason_code')
          IS DISTINCT FROM
          (to_jsonb(OLD) - 'status' - 'status_changed_by_membership_id' - 'status_change_reason_code') THEN
      RAISE EXCEPTION 'booking-event links are immutable except for one-way, attributed ending/revocation'
        USING ERRCODE = '55000';
    END IF;

    IF NEW.status_changed_by_membership_id IS NULL
       OR NEW.status_change_reason_code IS NULL
       OR length(btrim(NEW.status_change_reason_code)) = 0 THEN
      RAISE EXCEPTION 'booking-event link status change requires actor and reason'
        USING ERRCODE = '22023';
    END IF;

    SELECT status INTO v_member_status
      FROM eogp.organization_memberships
     WHERE organization_id = v_organization_id
       AND id = NEW.status_changed_by_membership_id
     FOR SHARE;
    IF NOT FOUND OR v_member_status <> 'active' THEN
      RAISE EXCEPTION 'active event-owner membership is required to change booking-event link status'
        USING ERRCODE = '42501';
    END IF;

    INSERT INTO eogp.audit_events (
      organization_id, actor_organization_id, actor_membership_id, actor_kind,
      authorization_grant_owner_organization_id, authorization_grant_id,
      action, aggregate_type, aggregate_id, reason_code, safe_metadata
    ) VALUES (
      NEW.organization_id, NEW.organization_id, NEW.status_changed_by_membership_id, 'membership',
      NEW.grant_owner_organization_id, NEW.collaboration_grant_id,
      CASE NEW.status WHEN 'ended' THEN 'booking.event.link.ended'
                      ELSE 'booking.event.link.revoked' END,
      'booking_event_link', NEW.id, NEW.status_change_reason_code,
      jsonb_build_object(
        'bookingOwnerOrganizationId', NEW.booking_owner_organization_id,
        'bookingId', NEW.booking_id,
        'eventId', NEW.event_id
      )
    );
    RETURN NEW;
  END IF;

  SELECT status INTO v_member_status
    FROM eogp.organization_memberships
   WHERE organization_id = v_organization_id
     AND id = NEW.created_by_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_member_status <> 'active' THEN
    RAISE EXCEPTION 'active event-owner membership is required to create a booking-event link'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.organization_id = NEW.booking_owner_organization_id THEN
    IF NEW.collaboration_grant_id IS NOT NULL
       OR NEW.grant_owner_organization_id IS NOT NULL THEN
      RAISE EXCEPTION 'same-tenant booking-event links must not carry a collaboration grant'
        USING ERRCODE = '23514';
    END IF;
  ELSE
    SELECT status, scope_kind, scope_booking_id, valid_from, valid_until, allowed_actions
      INTO v_grant_status, v_scope_kind, v_scope_booking_id,
           v_valid_from, v_valid_until, v_allowed_actions
      FROM eogp.collaboration_grants
     WHERE organization_id = NEW.booking_owner_organization_id
       AND grantee_organization_id = NEW.organization_id
       AND id = NEW.collaboration_grant_id
     FOR UPDATE;

    IF NOT FOUND
       OR v_grant_status <> 'active'
       OR v_valid_from > clock_timestamp()
       OR (v_valid_until IS NOT NULL AND v_valid_until <= clock_timestamp())
       OR v_scope_kind <> 'booking'
       OR v_scope_booking_id IS DISTINCT FROM NEW.booking_id
       OR NOT (v_allowed_actions @> ARRAY['booking.event.link']::text[]) THEN
      RAISE EXCEPTION 'an active booking-scoped booking.event.link grant is required'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    authorization_grant_owner_organization_id, authorization_grant_id,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    NEW.organization_id, NEW.organization_id, NEW.created_by_membership_id, 'membership',
    NEW.grant_owner_organization_id, NEW.collaboration_grant_id,
    'booking.event.linked', 'booking_event_link', NEW.id,
    jsonb_build_object(
      'bookingOwnerOrganizationId', NEW.booking_owner_organization_id,
      'bookingId', NEW.booking_id,
      'eventId', NEW.event_id,
      'relationshipKind', NEW.relationship_kind
    )
  );

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.enforce_venue_snapshot_share_grant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_member_status text;
  v_grant_status text;
  v_scope_kind text;
  v_scope_venue_id uuid;
  v_scope_space_id uuid;
  v_valid_from timestamptz;
  v_valid_until timestamptz;
  v_revision_space_id uuid;
  v_revision_hash text;
  v_revision_published_at timestamptz;
  v_venue_id uuid;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF OLD.status <> 'active'
       OR NEW.status NOT IN ('revoked','expired')
       OR (to_jsonb(NEW) - 'status' - 'status_changed_by_membership_id' - 'status_change_reason_code')
          IS DISTINCT FROM
          (to_jsonb(OLD) - 'status' - 'status_changed_by_membership_id' - 'status_change_reason_code') THEN
      RAISE EXCEPTION 'venue snapshot shares are immutable except for attributed one-way revocation/expiry'
        USING ERRCODE = '55000';
    END IF;

    IF NEW.status_changed_by_membership_id IS NULL
       OR NEW.status_change_reason_code IS NULL
       OR length(btrim(NEW.status_change_reason_code)) = 0 THEN
      RAISE EXCEPTION 'venue snapshot share status change requires actor and reason'
        USING ERRCODE = '22023';
    END IF;

    SELECT status INTO v_member_status
      FROM eogp.organization_memberships
     WHERE organization_id = NEW.organization_id
       AND id = NEW.status_changed_by_membership_id
     FOR SHARE;
    IF NOT FOUND OR v_member_status <> 'active'
       OR eogp.current_organization_id() IS DISTINCT FROM NEW.organization_id THEN
      RAISE EXCEPTION 'active provider membership and provider tenant context are required to change share status'
        USING ERRCODE = '42501';
    END IF;

    INSERT INTO eogp.audit_events (
      organization_id, actor_organization_id, actor_membership_id, actor_kind,
      action, aggregate_type, aggregate_id, reason_code, safe_metadata
    ) VALUES (
      NEW.organization_id, NEW.organization_id, NEW.status_changed_by_membership_id, 'membership',
      CASE NEW.status WHEN 'revoked' THEN 'venue.snapshot.share.revoked'
                      ELSE 'venue.snapshot.share.expired' END,
      'venue_snapshot_share', NEW.id, NEW.status_change_reason_code,
      jsonb_build_object(
        'eventOwnerOrganizationId', NEW.event_owner_organization_id,
        'eventId', NEW.event_id,
        'collaborationGrantId', NEW.collaboration_grant_id,
        'venueSpaceRevisionId', NEW.venue_space_revision_id
      )
    );
    RETURN NEW;
  END IF;

  IF NEW.status <> 'active'
     OR NEW.status_changed_by_membership_id IS NOT NULL
     OR NEW.status_change_reason_code IS NOT NULL
     OR jsonb_typeof(NEW.approved_layers) IS DISTINCT FROM 'array'
     OR jsonb_typeof(NEW.approved_resources) IS DISTINCT FROM 'array'
     OR NEW.approved_at > clock_timestamp() THEN
    RAISE EXCEPTION 'new venue snapshot shares must be active with array projections and no status-change actor'
      USING ERRCODE = '22023';
  END IF;

  SELECT status, scope_kind, scope_venue_id, scope_space_id,
         valid_from, valid_until
    INTO v_grant_status, v_scope_kind, v_scope_venue_id, v_scope_space_id,
         v_valid_from, v_valid_until
    FROM eogp.collaboration_grants
   WHERE organization_id = NEW.organization_id
     AND grantee_organization_id = NEW.event_owner_organization_id
     AND id = NEW.collaboration_grant_id
   FOR UPDATE;

  IF NOT FOUND
     OR v_grant_status <> 'active'
     OR NEW.approved_at < v_valid_from
     OR (v_valid_until IS NOT NULL AND NEW.approved_at >= v_valid_until) THEN
    RAISE EXCEPTION 'an active grant covering the venue-space revision is required'
      USING ERRCODE = '42501';
  END IF;

  SELECT status INTO v_member_status
    FROM eogp.organization_memberships
   WHERE organization_id = NEW.organization_id
     AND id = NEW.approved_by_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_member_status <> 'active' THEN
    RAISE EXCEPTION 'active venue-provider membership is required to approve a snapshot share'
      USING ERRCODE = '42501';
  END IF;

  SELECT revision.venue_space_id, revision.content_sha256,
         revision.published_at, space.venue_id
    INTO v_revision_space_id, v_revision_hash,
         v_revision_published_at, v_venue_id
    FROM eogp.venue_space_revisions AS revision
    JOIN eogp.venue_spaces AS space
      ON space.organization_id = revision.organization_id
     AND space.id = revision.venue_space_id
   WHERE revision.organization_id = NEW.organization_id
     AND revision.id = NEW.venue_space_revision_id
   FOR SHARE OF revision, space;

  IF NOT FOUND
     OR v_revision_published_at IS NULL
     OR v_revision_hash <> NEW.source_content_sha256 THEN
    RAISE EXCEPTION 'snapshot share must reference the exact published source revision and hash'
      USING ERRCODE = '23514';
  END IF;

  IF NOT (
    (v_scope_kind = 'venue' AND v_scope_venue_id = v_venue_id)
    OR
    (v_scope_kind = 'space' AND v_scope_space_id = v_revision_space_id)
  ) THEN
    RAISE EXCEPTION 'collaboration grant scope does not cover the requested venue-space revision'
      USING ERRCODE = '42501';
  END IF;

  IF v_valid_until IS NOT NULL
     AND (NEW.expires_at IS NULL OR NEW.expires_at > v_valid_until) THEN
    RAISE EXCEPTION 'snapshot share cannot outlive its collaboration grant'
      USING ERRCODE = '22023';
  END IF;

  IF NEW.expires_at IS NOT NULL AND NEW.expires_at <= NEW.approved_at THEN
    RAISE EXCEPTION 'snapshot share expiry must follow approval'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    NEW.organization_id, NEW.organization_id, NEW.approved_by_membership_id, 'membership',
    'venue.snapshot.shared', 'venue_snapshot_share', NEW.id,
    jsonb_build_object(
      'eventOwnerOrganizationId', NEW.event_owner_organization_id,
      'eventId', NEW.event_id,
      'collaborationGrantId', NEW.collaboration_grant_id,
      'venueSpaceRevisionId', NEW.venue_space_revision_id,
      'sourceContentSha256', NEW.source_content_sha256
    )
  );

  RETURN NEW;
END;
$function$;

-- Replace the release command with an explicit booking-scoped permission
-- check. An active membership alone is not sufficient authority.
CREATE OR REPLACE FUNCTION eogp.release_booking_reservations(
  p_organization_id uuid,
  p_booking_id uuid,
  p_actor_membership_id uuid,
  p_reason_code text
) RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_booking_status text;
  v_member_status text;
  v_resource_count bigint := 0;
  v_space_count bigint := 0;
BEGIN
  IF nullif(current_setting('app.organization_id', true), '')::uuid
     IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;
  IF p_reason_code IS NULL OR length(btrim(p_reason_code)) = 0 THEN
    RAISE EXCEPTION 'release reason is required' USING ERRCODE = '22023';
  END IF;

  SELECT status INTO v_booking_status
    FROM eogp.booking_records
   WHERE organization_id = p_organization_id
     AND id = p_booking_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_booking_status <> 'cancelled' THEN
    RAISE EXCEPTION 'reservations can be released only after booking cancellation'
      USING ERRCODE = '55000';
  END IF;

  SELECT status INTO v_member_status
    FROM eogp.organization_memberships
   WHERE organization_id = p_organization_id
     AND id = p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_member_status <> 'active' THEN
    RAISE EXCEPTION 'active booking-owner membership is required'
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM eogp.user_role_grants AS user_grant
      JOIN eogp.role_permissions AS role_permission
        ON role_permission.organization_id = user_grant.organization_id
       AND role_permission.role_id = user_grant.role_id
     WHERE user_grant.organization_id = p_organization_id
       AND user_grant.membership_id = p_actor_membership_id
       AND user_grant.revoked_at IS NULL
       AND (user_grant.expires_at IS NULL OR user_grant.expires_at > clock_timestamp())
       AND role_permission.permission_code = 'booking.cancellation.execute'
       AND (
         user_grant.scope_kind = 'organization'
         OR (user_grant.scope_kind = 'booking'
             AND user_grant.scope_booking_id = p_booking_id)
       )
  ) THEN
    RAISE EXCEPTION 'booking.cancellation.execute permission is required for this booking'
      USING ERRCODE = '42501';
  END IF;

  UPDATE eogp.resource_reservations
     SET status = 'released'
   WHERE organization_id = p_organization_id
     AND booking_id = p_booking_id
     AND status IN ('held','confirmed')
     AND ends_at > clock_timestamp();
  GET DIAGNOSTICS v_resource_count = ROW_COUNT;

  UPDATE eogp.venue_space_time_blocks
     SET status = 'released',
         updated_at = clock_timestamp()
   WHERE organization_id = p_organization_id
     AND booking_id = p_booking_id
     AND status = 'confirmed'
     AND ends_at > clock_timestamp();
  GET DIAGNOSTICS v_space_count = ROW_COUNT;

  IF v_resource_count + v_space_count > 0 THEN
    INSERT INTO eogp.audit_events (
      organization_id, actor_organization_id, actor_membership_id,
      actor_kind, action, aggregate_type, aggregate_id, reason_code,
      safe_metadata
    ) VALUES (
      p_organization_id, p_organization_id, p_actor_membership_id,
      'membership', 'booking.reservations.released', 'booking',
      p_booking_id, p_reason_code,
      jsonb_build_object(
        'resourceReservationsReleased', v_resource_count,
        'spaceReservationsReleased', v_space_count
      )
    );
  END IF;

  RETURN v_resource_count + v_space_count;
END;
$function$;

-- Delegated performers get a narrow task projection and an audited status
-- command. The collaboration grant must explicitly name the task ID in its
-- projection and include event.task.perform; no guest/RSVP/event registry
-- rows are read or exposed by these commands.
CREATE FUNCTION eogp.get_assigned_task_projection(
  p_assignment_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_assignment eogp.event_responsibility_assignments%ROWTYPE;
  v_member_status text;
BEGIN
  SELECT * INTO v_assignment
    FROM eogp.event_responsibility_assignments
   WHERE id = p_assignment_id
     AND performing_party_kind = 'organization'
     AND performing_organization_id = eogp.current_organization_id();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'assigned task not found for this performing organization'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT status INTO v_member_status
    FROM eogp.organization_memberships
   WHERE organization_id = v_assignment.performing_organization_id
     AND id = p_actor_membership_id;
  IF NOT FOUND OR v_member_status <> 'active'
     OR (v_assignment.performing_membership_id IS NOT NULL
         AND v_assignment.performing_membership_id <> p_actor_membership_id) THEN
    RAISE EXCEPTION 'active assigned performer membership is required'
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM eogp.collaboration_grants AS grant_row
     WHERE grant_row.organization_id = v_assignment.grant_owner_organization_id
       AND grant_row.grantee_organization_id = v_assignment.performing_organization_id
       AND grant_row.id = v_assignment.collaboration_grant_id
       AND grant_row.status = 'active'
       AND grant_row.valid_from <= statement_timestamp()
       AND (grant_row.valid_until IS NULL OR grant_row.valid_until > statement_timestamp())
       AND grant_row.allowed_actions @> ARRAY['event.task.perform']::text[]
       AND grant_row.projection -> 'taskIds' @> jsonb_build_array(v_assignment.id::text)
  ) THEN
    RAISE EXCEPTION 'active task-specific event.task.perform grant is required'
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM eogp.user_role_grants AS user_grant
      JOIN eogp.role_permissions AS role_permission
        ON role_permission.organization_id = user_grant.organization_id
       AND role_permission.role_id = user_grant.role_id
     WHERE user_grant.organization_id = v_assignment.performing_organization_id
       AND user_grant.membership_id = p_actor_membership_id
       AND user_grant.revoked_at IS NULL
       AND (user_grant.expires_at IS NULL OR user_grant.expires_at > clock_timestamp())
       AND role_permission.permission_code = 'task.perform'
       AND (
         user_grant.scope_kind = 'organization'
         OR (user_grant.scope_kind = 'task'
             AND user_grant.scope_task_event_id = v_assignment.event_id
             AND user_grant.scope_task_id = v_assignment.id)
       )
  ) THEN
    RAISE EXCEPTION 'task.perform permission is required for this assignment'
      USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'taskId', v_assignment.id,
    'taskCode', v_assignment.task_code,
    'taskLabel', v_assignment.task_label,
    'status', v_assignment.status,
    'dueAt', v_assignment.due_at,
    'permittedProjection', v_assignment.permitted_projection
  );
END;
$function$;

CREATE FUNCTION eogp.update_assigned_task_status(
  p_assignment_id uuid,
  p_actor_membership_id uuid,
  p_new_status text,
  p_reason_code text,
  p_evidence_reference jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_assignment eogp.event_responsibility_assignments%ROWTYPE;
  v_member_status text;
  v_new_status text := p_new_status;
BEGIN
  SELECT * INTO v_assignment
    FROM eogp.event_responsibility_assignments
   WHERE id = p_assignment_id
   FOR UPDATE;

  IF NOT FOUND
     OR v_assignment.performing_party_kind <> 'organization'
     OR v_assignment.performing_organization_id IS DISTINCT FROM eogp.current_organization_id() THEN
    RAISE EXCEPTION 'assigned task not found for this performing organization'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT status INTO v_member_status
    FROM eogp.organization_memberships
   WHERE organization_id = v_assignment.performing_organization_id
     AND id = p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_member_status <> 'active'
     OR (v_assignment.performing_membership_id IS NOT NULL
         AND v_assignment.performing_membership_id <> p_actor_membership_id) THEN
    RAISE EXCEPTION 'active assigned performer membership is required'
      USING ERRCODE = '42501';
  END IF;

  IF p_reason_code IS NULL OR length(btrim(p_reason_code)) = 0
     OR jsonb_typeof(p_evidence_reference) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'task status update requires a reason and JSON object evidence reference'
      USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM eogp.collaboration_grants AS grant_row
     WHERE grant_row.organization_id = v_assignment.grant_owner_organization_id
       AND grant_row.grantee_organization_id = v_assignment.performing_organization_id
       AND grant_row.id = v_assignment.collaboration_grant_id
       AND grant_row.status = 'active'
       AND grant_row.valid_from <= statement_timestamp()
       AND (grant_row.valid_until IS NULL OR grant_row.valid_until > statement_timestamp())
       AND grant_row.allowed_actions @> ARRAY['event.task.perform']::text[]
       AND grant_row.projection -> 'taskIds' @> jsonb_build_array(v_assignment.id::text)
     FOR SHARE
  ) THEN
    RAISE EXCEPTION 'active task-specific event.task.perform grant is required'
      USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM eogp.user_role_grants AS user_grant
      JOIN eogp.role_permissions AS role_permission
        ON role_permission.organization_id = user_grant.organization_id
       AND role_permission.role_id = user_grant.role_id
     WHERE user_grant.organization_id = v_assignment.performing_organization_id
       AND user_grant.membership_id = p_actor_membership_id
       AND user_grant.revoked_at IS NULL
       AND (user_grant.expires_at IS NULL OR user_grant.expires_at > clock_timestamp())
       AND role_permission.permission_code = 'task.perform'
       AND (
         user_grant.scope_kind = 'organization'
         OR (user_grant.scope_kind = 'task'
             AND user_grant.scope_task_event_id = v_assignment.event_id
             AND user_grant.scope_task_id = v_assignment.id)
       )
  ) THEN
    RAISE EXCEPTION 'task.perform permission is required for this assignment'
      USING ERRCODE = '42501';
  END IF;

  IF NOT (
    (v_assignment.status = 'not_started' AND v_new_status IN ('in_progress','blocked','cancelled','waived'))
    OR (v_assignment.status = 'in_progress' AND v_new_status IN ('blocked','completed','cancelled'))
    OR (v_assignment.status = 'blocked' AND v_new_status IN ('in_progress','completed','cancelled'))
  ) THEN
    RAISE EXCEPTION 'invalid delegated task status transition from % to %',
      v_assignment.status, v_new_status
      USING ERRCODE = '55000';
  END IF;

  UPDATE eogp.event_responsibility_assignments
     SET status = v_new_status,
         evidence_reference = p_evidence_reference,
         updated_at = clock_timestamp()
   WHERE organization_id = v_assignment.organization_id
     AND id = v_assignment.id;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    authorization_grant_owner_organization_id, authorization_grant_id,
    action, aggregate_type, aggregate_id, reason_code, safe_metadata
  ) VALUES (
    v_assignment.organization_id,
    v_assignment.performing_organization_id,
    p_actor_membership_id,
    'membership',
    v_assignment.grant_owner_organization_id,
    v_assignment.collaboration_grant_id,
    'event.task.status.changed',
    'event_responsibility_assignment',
    v_assignment.id,
    p_reason_code,
    jsonb_build_object(
      'eventId', v_assignment.event_id,
      'taskCode', v_assignment.task_code,
      'previousStatus', v_assignment.status,
      'newStatus', v_new_status
    )
  );

  RETURN jsonb_build_object(
    'taskId', v_assignment.id,
    'taskCode', v_assignment.task_code,
    'taskLabel', v_assignment.task_label,
    'status', v_new_status,
    'dueAt', v_assignment.due_at
  );
END;
$function$;

-- RLS admits a delegated performer only when an active grant names this
-- exact task and the performer has a task-scoped/organization task.perform
-- role. Direct table access is column-limited; status changes go through the
-- audited command above.
CREATE POLICY event_responsibility_performer_select
  ON eogp.event_responsibility_assignments
  FOR SELECT TO eventor_owner, eventor_runtime
  USING (
    organization_id <> eogp.current_organization_id()
    AND performing_party_kind = 'organization'
    AND performing_organization_id = eogp.current_organization_id()
    AND EXISTS (
      SELECT 1
        FROM eogp.collaboration_grants AS grant_row
       WHERE grant_row.organization_id = event_responsibility_assignments.grant_owner_organization_id
         AND grant_row.grantee_organization_id = event_responsibility_assignments.performing_organization_id
         AND grant_row.id = event_responsibility_assignments.collaboration_grant_id
         AND grant_row.status = 'active'
         AND grant_row.valid_from <= statement_timestamp()
         AND (grant_row.valid_until IS NULL OR grant_row.valid_until > statement_timestamp())
         AND grant_row.allowed_actions @> ARRAY['event.task.perform']::text[]
         AND grant_row.projection -> 'taskIds' @> jsonb_build_array(event_responsibility_assignments.id::text)
    )
    AND EXISTS (
      SELECT 1
        FROM eogp.user_role_grants AS user_grant
        JOIN eogp.role_permissions AS role_permission
          ON role_permission.organization_id = user_grant.organization_id
         AND role_permission.role_id = user_grant.role_id
       WHERE user_grant.organization_id = event_responsibility_assignments.performing_organization_id
         AND user_grant.revoked_at IS NULL
         AND (user_grant.expires_at IS NULL OR user_grant.expires_at > clock_timestamp())
         AND role_permission.permission_code = 'task.perform'
         AND (
           user_grant.scope_kind = 'organization'
           OR (user_grant.scope_kind = 'task'
               AND user_grant.scope_task_event_id = event_responsibility_assignments.event_id
               AND user_grant.scope_task_id = event_responsibility_assignments.id)
         )
    )
  );

CREATE POLICY event_responsibility_performer_update
  ON eogp.event_responsibility_assignments
  FOR UPDATE TO eventor_owner, eventor_runtime
  USING (
    organization_id <> eogp.current_organization_id()
    AND performing_party_kind = 'organization'
    AND performing_organization_id = eogp.current_organization_id()
    AND EXISTS (
      SELECT 1
        FROM eogp.collaboration_grants AS grant_row
       WHERE grant_row.organization_id = event_responsibility_assignments.grant_owner_organization_id
         AND grant_row.grantee_organization_id = event_responsibility_assignments.performing_organization_id
         AND grant_row.id = event_responsibility_assignments.collaboration_grant_id
         AND grant_row.status = 'active'
         AND grant_row.valid_from <= statement_timestamp()
         AND (grant_row.valid_until IS NULL OR grant_row.valid_until > statement_timestamp())
         AND grant_row.allowed_actions @> ARRAY['event.task.perform']::text[]
         AND grant_row.projection -> 'taskIds' @> jsonb_build_array(event_responsibility_assignments.id::text)
    )
    AND EXISTS (
      SELECT 1
        FROM eogp.user_role_grants AS user_grant
        JOIN eogp.role_permissions AS role_permission
          ON role_permission.organization_id = user_grant.organization_id
         AND role_permission.role_id = user_grant.role_id
       WHERE user_grant.organization_id = event_responsibility_assignments.performing_organization_id
         AND user_grant.revoked_at IS NULL
         AND (user_grant.expires_at IS NULL OR user_grant.expires_at > clock_timestamp())
         AND role_permission.permission_code = 'task.perform'
         AND (
           user_grant.scope_kind = 'organization'
           OR (user_grant.scope_kind = 'task'
               AND user_grant.scope_task_event_id = event_responsibility_assignments.event_id
               AND user_grant.scope_task_id = event_responsibility_assignments.id)
         )
    )
  )
  WITH CHECK (
    performing_party_kind = 'organization'
    AND performing_organization_id = eogp.current_organization_id()
  );

-- Do not expose private operational metadata or full task records through
-- ordinary SELECT. The security-definer projection function returns a fixed
-- allowlisted payload; updates are exclusively through update_assigned_task_status.
REVOKE SELECT, INSERT, UPDATE, DELETE
  ON eogp.event_responsibility_assignments
  FROM eventor_runtime;
GRANT SELECT (
  organization_id, event_id, id, task_code, task_label,
  accountable_party_kind, performing_party_kind,
  performing_organization_id, performing_membership_id,
  due_at, status, updated_at
) ON eogp.event_responsibility_assignments TO eventor_runtime;

-- The delegated status command writes the audit row in the event owner's
-- tenant while the authenticated transaction remains in the performing
-- tenant. Permit only that exact task/grant/action tuple.
CREATE POLICY event_task_delegated_audit_insert
  ON eogp.audit_events
  FOR INSERT TO eventor_owner, eventor_runtime
  WITH CHECK (
    action = 'event.task.status.changed'
    AND aggregate_type = 'event_responsibility_assignment'
    AND actor_kind = 'membership'
    AND actor_organization_id = eogp.current_organization_id()
    AND authorization_grant_owner_organization_id = organization_id
    AND EXISTS (
      SELECT 1
        FROM eogp.event_responsibility_assignments AS assignment
       WHERE assignment.organization_id = eogp.audit_events.organization_id
         AND assignment.id = eogp.audit_events.aggregate_id
         AND assignment.performing_party_kind = 'organization'
         AND assignment.performing_organization_id = eogp.current_organization_id()
         AND assignment.collaboration_grant_id = eogp.audit_events.authorization_grant_id
         AND assignment.grant_owner_organization_id = eogp.audit_events.authorization_grant_owner_organization_id
    )
  );

REVOKE ALL ON FUNCTION eogp.get_assigned_task_projection(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.update_assigned_task_status(uuid,uuid,text,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.get_assigned_task_projection(uuid,uuid),
  eogp.update_assigned_task_status(uuid,uuid,text,text,jsonb) TO eventor_runtime;

REVOKE ALL ON FUNCTION eogp.release_booking_reservations(uuid,uuid,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.release_booking_reservations(uuid,uuid,uuid,text)
  TO eventor_runtime;

COMMIT;
