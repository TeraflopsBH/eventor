-- Bind staff permission checks to the authenticated membership context.
-- This prevents a caller from supplying another membership ID to a SECURITY DEFINER
-- permission helper and using that identity for event or booking-inquiry access.

CREATE OR REPLACE FUNCTION eogp.assert_event_command_permission(
  p_organization_id uuid,
  p_event_id uuid,
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

  SELECT status INTO v_membership_status
    FROM eogp.organization_memberships
   WHERE organization_id = p_organization_id
     AND id = p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_membership_status <> 'active' THEN
    RAISE EXCEPTION 'active event-owner membership is required' USING ERRCODE = '42501';
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
     AND role_permission.permission_code = p_permission_code
     AND (
       user_grant.scope_kind = 'organization'
       OR (user_grant.scope_kind = 'event' AND user_grant.scope_event_id = p_event_id)
     )
   FOR SHARE OF user_grant, role_permission;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'required event permission is not granted for this event'
      USING ERRCODE = '42501';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.assert_booking_inquiry_permission(
  p_organization_id uuid,
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

  SELECT status INTO v_membership_status
    FROM eogp.organization_memberships
   WHERE organization_id = p_organization_id
     AND id = p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_membership_status <> 'active' THEN
    RAISE EXCEPTION 'active organization membership is required' USING ERRCODE = '42501';
  END IF;

  -- Inquiries are not bookings yet, so only organization-wide grants apply.
  -- A booking-scoped grant becomes meaningful only after draft/booking linkage.
  PERFORM 1
    FROM eogp.user_role_grants AS user_grant
    JOIN eogp.role_permissions AS role_permission
      ON role_permission.organization_id = user_grant.organization_id
     AND role_permission.role_id = user_grant.role_id
   WHERE user_grant.organization_id = p_organization_id
     AND user_grant.membership_id = p_actor_membership_id
     AND user_grant.scope_kind = 'organization'
     AND user_grant.revoked_at IS NULL
     AND (user_grant.expires_at IS NULL OR user_grant.expires_at > clock_timestamp())
     AND role_permission.permission_code = p_permission_code
   FOR SHARE OF user_grant, role_permission;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'required booking inquiry permission is not granted'
      USING ERRCODE = '42501';
  END IF;
END;
$function$;
