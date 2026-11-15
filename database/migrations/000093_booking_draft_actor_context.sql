-- Bind booking-draft authorization to the authenticated staff membership.
CREATE OR REPLACE FUNCTION eogp.assert_booking_draft_permission(
  p_organization_id uuid,
  p_draft_id uuid,
  p_actor_membership_id uuid,
  p_permission_code text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_membership_status text;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id
     OR nullif(current_setting('app.actor_membership_id', true), '')::uuid
          IS DISTINCT FROM p_actor_membership_id THEN
    RAISE EXCEPTION 'organization or staff actor context mismatch' USING ERRCODE = '42501';
  END IF;

  IF p_permission_code NOT IN ('booking.draft.read','booking.draft.manage') THEN
    RAISE EXCEPTION 'unsupported booking draft permission' USING ERRCODE = '22023';
  END IF;

  SELECT membership.status
    INTO v_membership_status
    FROM eogp.organization_memberships membership
   WHERE membership.organization_id = p_organization_id
     AND membership.id = p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_membership_status <> 'active' THEN
    RAISE EXCEPTION 'active organization membership is required'
      USING ERRCODE = '42501';
  END IF;

  -- A draft is not a confirmed booking and cannot be the target of
  -- scope_booking_id. Only an organization grant can authorize a draft.
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
     AND (
       role_permission.permission_code = p_permission_code
       OR (p_permission_code = 'booking.draft.read'
           AND role_permission.permission_code = 'booking.draft.manage')
     )
   FOR SHARE OF user_grant, role_permission;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'required booking draft permission is not granted'
      USING ERRCODE = '42501';
  END IF;
END;
$function$;
