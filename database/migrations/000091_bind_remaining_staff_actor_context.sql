-- Extend authenticated actor binding to commercial, reservation and delegated-task authorization.

CREATE OR REPLACE FUNCTION eogp.propose_collaboration_grant(
  p_grant_id uuid,
  p_grantee_organization_id uuid,
  p_scope_kind text,
  p_scope_venue_id uuid,
  p_scope_space_id uuid,
  p_scope_booking_id uuid,
  p_purpose text,
  p_projection jsonb,
  p_allowed_actions text[],
  p_valid_from timestamptz,
  p_valid_until timestamptz,
  p_actor_membership_id uuid
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_organization_id uuid := eogp.current_organization_id();
  v_member_status text;
  v_grant_id uuid := coalesce(p_grant_id, gen_random_uuid());
BEGIN
  IF nullif(current_setting('app.actor_membership_id', true), '')::uuid
       IS DISTINCT FROM p_actor_membership_id THEN
    RAISE EXCEPTION 'staff actor context mismatch' USING ERRCODE = '42501';
  END IF;
  IF v_organization_id IS NULL OR p_grantee_organization_id IS NULL
     OR p_grantee_organization_id = v_organization_id THEN
    RAISE EXCEPTION 'grantor tenant and a different grantee tenant are required'
      USING ERRCODE = '22023';
  END IF;

  IF nullif(btrim(p_purpose), '') IS NULL
     OR p_projection IS NULL
     OR jsonb_typeof(p_projection) <> 'object'
     OR p_allowed_actions IS NULL
     OR cardinality(p_allowed_actions) = 0
     OR EXISTS (
       SELECT 1 FROM unnest(p_allowed_actions) AS a(action_code)
        WHERE action_code IS NULL OR nullif(btrim(action_code), '') IS NULL
     )
     OR p_valid_from IS NULL
     OR (p_valid_until IS NOT NULL AND p_valid_until <= p_valid_from) THEN
    RAISE EXCEPTION 'grant purpose, projection, actions and validity are invalid'
      USING ERRCODE = '22023';
  END IF;

  SELECT status
    INTO v_member_status
    FROM eogp.organization_memberships
   WHERE organization_id = v_organization_id
     AND id = p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_member_status <> 'active' THEN
    RAISE EXCEPTION 'active grantor membership is required'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO eogp.collaboration_grants (
    id, organization_id, grantee_organization_id, scope_kind,
    scope_venue_id, scope_space_id, scope_booking_id, purpose,
    projection, allowed_actions, status, valid_from, valid_until,
    proposed_by_membership_id
  ) VALUES (
    v_grant_id, v_organization_id, p_grantee_organization_id, p_scope_kind,
    p_scope_venue_id, p_scope_space_id, p_scope_booking_id, btrim(p_purpose),
    p_projection, p_allowed_actions, 'proposed', p_valid_from, p_valid_until,
    p_actor_membership_id
  );

  INSERT INTO eogp.collaboration_grant_revisions (
    organization_id, grant_id, revision_number, projection,
    allowed_actions, changed_by_membership_id
  ) VALUES (
    v_organization_id, v_grant_id, 1, p_projection,
    p_allowed_actions, p_actor_membership_id
  );

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id,
    actor_kind, action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    v_organization_id, v_organization_id, p_actor_membership_id,
    'membership', 'collaboration.grant.proposed',
    'collaboration_grant', v_grant_id,
    jsonb_build_object(
      'granteeOrganizationId', p_grantee_organization_id,
      'scopeKind', p_scope_kind
    )
  );

  RETURN v_grant_id;
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.get_assigned_task_projection(
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
  IF nullif(current_setting('app.actor_membership_id', true), '')::uuid
       IS DISTINCT FROM p_actor_membership_id THEN
    RAISE EXCEPTION 'staff actor context mismatch' USING ERRCODE = '42501';
  END IF;
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
       AND (grant_row.projection -> 'taskIds') @> jsonb_build_array(v_assignment.id::text)
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

CREATE OR REPLACE FUNCTION eogp.update_assigned_task_status(
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
  IF nullif(current_setting('app.actor_membership_id', true), '')::uuid
       IS DISTINCT FROM p_actor_membership_id THEN
    RAISE EXCEPTION 'staff actor context mismatch' USING ERRCODE = '42501';
  END IF;
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

  PERFORM 1
    FROM eogp.collaboration_grants AS grant_row
   WHERE grant_row.organization_id = v_assignment.grant_owner_organization_id
     AND grant_row.grantee_organization_id = v_assignment.performing_organization_id
     AND grant_row.id = v_assignment.collaboration_grant_id
     AND grant_row.status = 'active'
     AND grant_row.valid_from <= statement_timestamp()
     AND (grant_row.valid_until IS NULL OR grant_row.valid_until > statement_timestamp())
     AND grant_row.allowed_actions @> ARRAY['event.task.perform']::text[]
     AND (grant_row.projection -> 'taskIds') @> jsonb_build_array(v_assignment.id::text)
   FOR SHARE;
  IF NOT FOUND THEN
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

CREATE OR REPLACE FUNCTION eogp.confirm_booking_reservations(
  p_organization_id uuid,
  p_booking_draft_revision_id uuid,
  p_booking_id uuid,
  p_actor_membership_id uuid,
  p_reason_code text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_booking_status text;
  v_offer_revision_id uuid;
  v_offer_draft_revision_id uuid;
  v_offer_state text;
  v_snapshot_offer_revision_id uuid;
  v_member_status text;
  v_resource eogp.resource_reservations%ROWTYPE;
  v_source_line eogp.booking_resource_lines%ROWTYPE;
  v_booking_line_ids uuid[];
  v_booking_line_id uuid;
  v_resource_count bigint := 0;
  v_space_count bigint := 0;
  v_expired_resource_count bigint := 0;
  v_expired_space_count bigint := 0;
BEGIN
  IF nullif(current_setting('app.organization_id', true), '')::uuid
     IS DISTINCT FROM p_organization_id
     OR nullif(current_setting('app.actor_membership_id', true), '')::uuid
          IS DISTINCT FROM p_actor_membership_id THEN
    RAISE EXCEPTION 'organization or staff actor context mismatch' USING ERRCODE = '42501';
  END IF;
  IF p_reason_code IS NULL OR length(btrim(p_reason_code)) = 0 THEN
    RAISE EXCEPTION 'booking confirmation reason is required' USING ERRCODE = '22023';
  END IF;

  SELECT status, source_offer_revision_id
    INTO v_booking_status, v_offer_revision_id
    FROM eogp.booking_records
   WHERE organization_id = p_organization_id AND id = p_booking_id
   FOR UPDATE;
  IF NOT FOUND OR v_booking_status <> 'confirmed' THEN
    RAISE EXCEPTION 'a confirmed booking is required for reservation conversion'
      USING ERRCODE = '55000';
  END IF;

  SELECT draft_revision_id, state
    INTO v_offer_draft_revision_id, v_offer_state
    FROM eogp.booking_offer_revisions
   WHERE organization_id = p_organization_id AND id = v_offer_revision_id
   FOR SHARE;
  IF NOT FOUND
     OR v_offer_draft_revision_id IS DISTINCT FROM p_booking_draft_revision_id
     OR v_offer_state <> 'accepted' THEN
    RAISE EXCEPTION 'booking must originate from the accepted offer revision for this draft'
      USING ERRCODE = '23514';
  END IF;

  SELECT offer_revision_id INTO v_snapshot_offer_revision_id
    FROM eogp.booking_confirmed_snapshots
   WHERE organization_id = p_organization_id AND booking_id = p_booking_id
   FOR SHARE;
  IF NOT FOUND OR v_snapshot_offer_revision_id IS DISTINCT FROM v_offer_revision_id THEN
    RAISE EXCEPTION 'booking confirmed snapshot must pin the source offer revision'
      USING ERRCODE = '23514';
  END IF;

  SELECT status INTO v_member_status
    FROM eogp.organization_memberships
   WHERE organization_id = p_organization_id AND id = p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_member_status <> 'active' THEN
    RAISE EXCEPTION 'active booking-owner membership is required'
      USING ERRCODE = '42501';
  END IF;

  PERFORM 1
    FROM eogp.user_role_grants AS user_grant
    JOIN eogp.role_permissions AS role_permission
      ON role_permission.organization_id = user_grant.organization_id
     AND role_permission.role_id = user_grant.role_id
   WHERE user_grant.organization_id = p_organization_id
     AND user_grant.membership_id = p_actor_membership_id
     AND user_grant.revoked_at IS NULL
     AND (user_grant.expires_at IS NULL OR user_grant.expires_at > clock_timestamp())
     AND role_permission.permission_code = 'booking.confirm'
     AND (user_grant.scope_kind = 'organization'
       OR (user_grant.scope_kind = 'booking' AND user_grant.scope_booking_id = p_booking_id))
   FOR SHARE OF user_grant, role_permission;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking.confirm permission is required for this booking'
      USING ERRCODE = '42501';
  END IF;

  UPDATE eogp.resource_reservations
     SET status = 'expired'
   WHERE organization_id = p_organization_id
     AND booking_draft_revision_id = p_booking_draft_revision_id
     AND status = 'held' AND expires_at <= clock_timestamp();
  GET DIAGNOSTICS v_expired_resource_count = ROW_COUNT;

  UPDATE eogp.venue_space_time_blocks
     SET status = 'expired', updated_at = clock_timestamp()
   WHERE organization_id = p_organization_id
     AND booking_draft_revision_id = p_booking_draft_revision_id
     AND status = 'held' AND expires_at <= clock_timestamp();
  GET DIAGNOSTICS v_expired_space_count = ROW_COUNT;

  FOR v_resource IN
    SELECT reservation.*
      FROM eogp.resource_reservations AS reservation
     WHERE reservation.organization_id = p_organization_id
       AND reservation.booking_draft_revision_id = p_booking_draft_revision_id
       AND reservation.status = 'held'
       AND reservation.expires_at > clock_timestamp()
     ORDER BY reservation.resource_pool_id NULLS LAST,
              reservation.resource_unit_id NULLS LAST, reservation.id
     FOR UPDATE OF reservation
  LOOP
    v_booking_line_id := NULL;

    IF v_resource.booking_resource_line_id IS NOT NULL THEN
      SELECT * INTO v_source_line
        FROM eogp.booking_resource_lines
       WHERE organization_id = p_organization_id
         AND id = v_resource.booking_resource_line_id
         AND draft_revision_id = p_booking_draft_revision_id
       FOR SHARE;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'draft reservation resource line does not belong to the confirmed draft'
          USING ERRCODE = '23503';
      END IF;

      SELECT array_agg(line.id ORDER BY line.id) INTO v_booking_line_ids
        FROM eogp.booking_resource_lines AS line
       WHERE line.organization_id = p_organization_id
         AND line.booking_id = p_booking_id
         AND line.draft_revision_id IS NULL
         AND line.resource_type_id = v_source_line.resource_type_id
         AND line.line_code = v_source_line.line_code;
      IF coalesce(cardinality(v_booking_line_ids), 0) <> 1 THEN
        RAISE EXCEPTION 'draft resource line must map to exactly one booking resource line'
          USING ERRCODE = '23514',
                DETAIL = format('draft line %s maps to %s booking lines',
                  v_source_line.id, coalesce(cardinality(v_booking_line_ids), 0));
      END IF;
      v_booking_line_id := v_booking_line_ids[1];
    END IF;

    UPDATE eogp.resource_reservations SET status = 'released'
     WHERE organization_id = p_organization_id AND id = v_resource.id AND status = 'held';

    IF v_resource.resource_pool_id IS NOT NULL THEN
      PERFORM eogp.reserve_pooled_resource(
        p_organization_id, v_resource.resource_pool_id, NULL, p_booking_id,
        v_booking_line_id, v_resource.starts_at, v_resource.ends_at,
        v_resource.quantity, NULL, 'confirm-' || v_resource.id::text
      );
    ELSE
      PERFORM eogp.reserve_resource_unit(
        p_organization_id, v_resource.resource_unit_id, NULL, p_booking_id,
        NULL, v_booking_line_id, v_resource.starts_at, v_resource.ends_at,
        NULL, 'confirm-' || v_resource.id::text
      );
    END IF;
    v_resource_count := v_resource_count + 1;
  END LOOP;

  UPDATE eogp.venue_space_time_blocks
     SET reservation_kind = 'booking',
         booking_draft_revision_id = NULL,
         booking_id = p_booking_id,
         status = 'confirmed',
         expires_at = NULL,
         updated_at = clock_timestamp()
   WHERE organization_id = p_organization_id
     AND booking_draft_revision_id = p_booking_draft_revision_id
     AND status = 'held' AND expires_at > clock_timestamp();
  GET DIAGNOSTICS v_space_count = ROW_COUNT;

  IF v_resource_count + v_space_count > 0 THEN
    INSERT INTO eogp.audit_events (
      organization_id, actor_organization_id, actor_membership_id, actor_kind,
      action, aggregate_type, aggregate_id, reason_code, safe_metadata
    ) VALUES (
      p_organization_id, p_organization_id, p_actor_membership_id, 'membership',
      'booking.reservations.confirmed', 'booking', p_booking_id, p_reason_code,
      jsonb_build_object(
        'resourceReservationsConfirmed', v_resource_count,
        'spaceReservationsConfirmed', v_space_count,
        'expiredResourceHolds', v_expired_resource_count,
        'expiredSpaceHolds', v_expired_space_count
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'bookingId', p_booking_id,
    'resourceReservationsConfirmed', v_resource_count,
    'spaceReservationsConfirmed', v_space_count,
    'expiredResourceHolds', v_expired_resource_count,
    'expiredSpaceHolds', v_expired_space_count,
    'changed', (v_resource_count + v_space_count + v_expired_resource_count + v_expired_space_count) > 0
  );
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.release_booking_reservations(
  p_organization_id uuid,
  p_booking_id uuid,
  p_reservation_ids uuid[],
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
  v_unique_id_count bigint;
  v_owned_id_count bigint;
  v_resource_count bigint := 0;
  v_space_count bigint := 0;
  v_resource_ids uuid[] := ARRAY[]::uuid[];
  v_space_ids uuid[] := ARRAY[]::uuid[];
BEGIN
  IF nullif(current_setting('app.organization_id', true), '')::uuid
     IS DISTINCT FROM p_organization_id
     OR nullif(current_setting('app.actor_membership_id', true), '')::uuid
          IS DISTINCT FROM p_actor_membership_id THEN
    RAISE EXCEPTION 'organization or staff actor context mismatch' USING ERRCODE = '42501';
  END IF;

  -- Mirror the request contract: at least one UUID, one-dimensional, unique,
  -- and no NULL elements. The API also enforces these constraints.
  IF p_reservation_ids IS NULL
     OR cardinality(p_reservation_ids) = 0
     OR coalesce(array_ndims(p_reservation_ids), 1) <> 1
     OR array_position(p_reservation_ids, NULL::uuid) IS NOT NULL THEN
    RAISE EXCEPTION 'one or more non-null reservation IDs are required'
      USING ERRCODE = '22023';
  END IF;

  SELECT count(DISTINCT requested.reservation_id)
    INTO v_unique_id_count
    FROM unnest(p_reservation_ids) AS requested(reservation_id);
  IF v_unique_id_count <> cardinality(p_reservation_ids) THEN
    RAISE EXCEPTION 'reservation IDs must be unique'
      USING ERRCODE = '22023';
  END IF;

  IF p_reason_code IS NULL
     OR length(btrim(p_reason_code)) < 3
     OR length(p_reason_code) > 1000 THEN
    RAISE EXCEPTION 'release reason must contain between 3 and 1000 characters'
      USING ERRCODE = '22023';
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

  -- The same booking-scoped authorization used by the prior command is
  -- retained. Lock both grant and permission rows while the command runs.
  PERFORM 1
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
   FOR SHARE OF user_grant, role_permission;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking.cancellation.execute permission is required for this booking'
      USING ERRCODE = '42501';
  END IF;

  -- IDs may identify either a resource reservation or a venue-space time
  -- block. Validate the entire request before changing anything. This keeps
  -- foreign/nonexistent IDs from producing a misleading partial success.
  SELECT count(DISTINCT requested.reservation_id)
    INTO v_owned_id_count
    FROM unnest(p_reservation_ids) AS requested(reservation_id)
   WHERE EXISTS (
     SELECT 1
       FROM eogp.resource_reservations AS resource_reservation
      WHERE resource_reservation.organization_id = p_organization_id
        AND resource_reservation.booking_id = p_booking_id
        AND resource_reservation.id = requested.reservation_id
   )
      OR EXISTS (
     SELECT 1
       FROM eogp.venue_space_time_blocks AS space_reservation
      WHERE space_reservation.organization_id = p_organization_id
        AND space_reservation.booking_id = p_booking_id
        AND space_reservation.id = requested.reservation_id
   );

  IF v_owned_id_count <> cardinality(p_reservation_ids) THEN
    RAISE EXCEPTION 'every reservation ID must belong to the specified booking'
      USING ERRCODE = '42501';
  END IF;

  WITH released AS (
    UPDATE eogp.resource_reservations
       SET status = 'released'
     WHERE organization_id = p_organization_id
       AND booking_id = p_booking_id
       AND id = ANY(p_reservation_ids)
       AND status IN ('held','confirmed')
       AND ends_at > clock_timestamp()
     RETURNING id
  )
  SELECT count(*), coalesce(array_agg(id ORDER BY id), ARRAY[]::uuid[])
    INTO v_resource_count, v_resource_ids
    FROM released;

  WITH released AS (
    UPDATE eogp.venue_space_time_blocks
       SET status = 'released',
           updated_at = clock_timestamp()
     WHERE organization_id = p_organization_id
       AND booking_id = p_booking_id
       AND id = ANY(p_reservation_ids)
       AND status = 'confirmed'
       AND ends_at > clock_timestamp()
     RETURNING id
  )
  SELECT count(*), coalesce(array_agg(id ORDER BY id), ARRAY[]::uuid[])
    INTO v_space_count, v_space_ids
    FROM released;

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
        'spaceReservationsReleased', v_space_count,
        'resourceReservationIdsReleased', v_resource_ids,
        'spaceReservationIdsReleased', v_space_ids
      )
    );
  END IF;

  -- A retry, or a request containing only ineligible/past/terminal rows,
  -- changes no rows and emits no additional audit event.
  RETURN v_resource_count + v_space_count;
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.assert_booking_commercial_permission(
  p_organization_id uuid,
  p_actor_membership_id uuid,
  p_permission_codes text[]
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_status text;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id
     OR nullif(current_setting('app.actor_membership_id', true), '')::uuid
          IS DISTINCT FROM p_actor_membership_id THEN
    RAISE EXCEPTION 'organization or staff actor context mismatch' USING ERRCODE = '42501';
  END IF;
  IF p_permission_codes IS NULL OR cardinality(p_permission_codes) = 0
     OR NOT p_permission_codes <@ ARRAY['booking.manage','booking.approve','booking.confirm']::text[] THEN
    RAISE EXCEPTION 'unsupported booking commercial permission' USING ERRCODE = '22023';
  END IF;

  SELECT membership.status INTO v_status
    FROM eogp.organization_memberships membership
   WHERE membership.organization_id = p_organization_id
     AND membership.id = p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_status <> 'active' THEN
    RAISE EXCEPTION 'active organization membership is required' USING ERRCODE = '42501';
  END IF;

  PERFORM 1
    FROM eogp.user_role_grants user_grant
    JOIN eogp.role_permissions role_permission
      ON role_permission.organization_id = user_grant.organization_id
     AND role_permission.role_id = user_grant.role_id
   WHERE user_grant.organization_id = p_organization_id
     AND user_grant.membership_id = p_actor_membership_id
     AND user_grant.scope_kind = 'organization'
     AND user_grant.revoked_at IS NULL
     AND (user_grant.expires_at IS NULL OR user_grant.expires_at > clock_timestamp())
     AND role_permission.permission_code = ANY(p_permission_codes)
   FOR SHARE OF user_grant, role_permission;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking commercial permission is required' USING ERRCODE = '42501';
  END IF;
END;
$function$;
