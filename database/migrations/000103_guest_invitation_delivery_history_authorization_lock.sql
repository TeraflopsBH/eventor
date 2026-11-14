-- Serialize staff delivery-attempt history reads with membership and permission revocation.

CREATE OR REPLACE FUNCTION eogp.list_guest_invitation_delivery_attempts(
  p_organization_id uuid,
  p_invitation_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_event_id uuid;
  v_result jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id
     OR nullif(current_setting('app.actor_membership_id',true),'')::uuid IS DISTINCT FROM p_actor_membership_id THEN
    RAISE EXCEPTION 'organization or staff actor context mismatch' USING ERRCODE='42501';
  END IF;
  -- Keep membership active for the complete delivery-history projection.
  PERFORM 1
    FROM eogp.organization_memberships membership
   WHERE membership.organization_id=p_organization_id
     AND membership.id=p_actor_membership_id
     AND membership.status='active'
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'active staff membership is required' USING ERRCODE='42501';
  END IF;

  SELECT invitation.event_id INTO v_event_id
    FROM eogp.invitations invitation
   WHERE invitation.organization_id=p_organization_id AND invitation.id=p_invitation_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'guest invitation not found' USING ERRCODE='P0002';
  END IF;
  PERFORM 1
    FROM eogp.user_role_grants user_grant
    JOIN eogp.role_permissions role_permission
      ON role_permission.organization_id=user_grant.organization_id
     AND role_permission.role_id=user_grant.role_id
   WHERE user_grant.organization_id=p_organization_id
     AND user_grant.membership_id=p_actor_membership_id
     AND user_grant.revoked_at IS NULL
     AND (user_grant.expires_at IS NULL OR user_grant.expires_at>clock_timestamp())
     AND role_permission.permission_code='invitation.manage'
     AND (user_grant.scope_kind='organization'
       OR (user_grant.scope_kind='event' AND user_grant.scope_event_id=v_event_id))
   FOR SHARE OF user_grant,role_permission;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'invitation.manage permission is required for this event' USING ERRCODE='42501';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'attemptId',attempt.id,
    'deliveryId',attempt.delivery_id,
    'attemptNumber',attempt.attempt_number,
    'status',attempt.status,
    'failureCode',attempt.failure_code,
    'providerMessageReference',attempt.provider_message_reference,
    'startedAt',attempt.started_at,
    'completedAt',attempt.completed_at,
    'retryScheduled',attempt.retry_scheduled
  ) ORDER BY attempt.started_at DESC,attempt.id DESC),'[]'::jsonb)
    INTO v_result
    FROM eogp.invitation_delivery_attempts attempt
   WHERE attempt.organization_id=p_organization_id
     AND attempt.invitation_id=p_invitation_id;
  RETURN v_result;
END;
$function$;
