-- Lock the performing membership, task permission and collaboration grant
-- before assignment lookup/locking in delegated-task read and write paths.

CREATE OR REPLACE FUNCTION eogp.get_assigned_task_projection(
  p_assignment_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
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
  -- Authorize the current tenant member and the task-specific capability
  -- before reading or locking the assignment. The grant projection itself is
  -- scoped to this assignment ID, so an ungranted caller gets one denial for
  -- both real and unknown IDs.
  SELECT membership.status INTO v_member_status
    FROM eogp.organization_memberships membership
   WHERE membership.organization_id=eogp.current_organization_id()
     AND membership.id=p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_member_status<>'active' THEN
    RAISE EXCEPTION 'active assigned performer membership is required' USING ERRCODE='42501';
  END IF;

  PERFORM 1
    FROM eogp.user_role_grants user_grant
    JOIN eogp.role_permissions role_permission
      ON role_permission.organization_id=user_grant.organization_id
     AND role_permission.role_id=user_grant.role_id
   WHERE user_grant.organization_id=eogp.current_organization_id()
     AND user_grant.membership_id=p_actor_membership_id
     AND user_grant.revoked_at IS NULL
     AND (user_grant.expires_at IS NULL OR user_grant.expires_at>clock_timestamp())
     AND role_permission.permission_code='task.perform'
     AND (user_grant.scope_kind='organization'
       OR (user_grant.scope_kind='task' AND user_grant.scope_task_id=p_assignment_id))
   FOR SHARE OF user_grant,role_permission;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'task.perform permission is required for this assignment' USING ERRCODE='42501';
  END IF;

  PERFORM 1
    FROM eogp.collaboration_grants grant_row
   WHERE grant_row.grantee_organization_id=eogp.current_organization_id()
     AND grant_row.status='active'
     AND grant_row.valid_from<=statement_timestamp()
     AND (grant_row.valid_until IS NULL OR grant_row.valid_until>statement_timestamp())
     AND grant_row.allowed_actions @> ARRAY['event.task.perform']::text[]
     AND (grant_row.projection->'taskIds') @> jsonb_build_array(p_assignment_id::text)
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'active task-specific event.task.perform grant is required' USING ERRCODE='42501';
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
  -- Authorize the current tenant member and the task-specific capability
  -- before reading or locking the assignment. The grant projection itself is
  -- scoped to this assignment ID, so an ungranted caller gets one denial for
  -- both real and unknown IDs.
  SELECT membership.status INTO v_member_status
    FROM eogp.organization_memberships membership
   WHERE membership.organization_id=eogp.current_organization_id()
     AND membership.id=p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_member_status<>'active' THEN
    RAISE EXCEPTION 'active assigned performer membership is required' USING ERRCODE='42501';
  END IF;

  PERFORM 1
    FROM eogp.user_role_grants user_grant
    JOIN eogp.role_permissions role_permission
      ON role_permission.organization_id=user_grant.organization_id
     AND role_permission.role_id=user_grant.role_id
   WHERE user_grant.organization_id=eogp.current_organization_id()
     AND user_grant.membership_id=p_actor_membership_id
     AND user_grant.revoked_at IS NULL
     AND (user_grant.expires_at IS NULL OR user_grant.expires_at>clock_timestamp())
     AND role_permission.permission_code='task.perform'
     AND (user_grant.scope_kind='organization'
       OR (user_grant.scope_kind='task' AND user_grant.scope_task_id=p_assignment_id))
   FOR SHARE OF user_grant,role_permission;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'task.perform permission is required for this assignment' USING ERRCODE='42501';
  END IF;

  PERFORM 1
    FROM eogp.collaboration_grants grant_row
   WHERE grant_row.grantee_organization_id=eogp.current_organization_id()
     AND grant_row.status='active'
     AND grant_row.valid_from<=statement_timestamp()
     AND (grant_row.valid_until IS NULL OR grant_row.valid_until>statement_timestamp())
     AND grant_row.allowed_actions @> ARRAY['event.task.perform']::text[]
     AND (grant_row.projection->'taskIds') @> jsonb_build_array(p_assignment_id::text)
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'active task-specific event.task.perform grant is required' USING ERRCODE='42501';
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

