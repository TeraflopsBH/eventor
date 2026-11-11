-- Provide the permitted staff workspace with a minimal same-organization
-- assignee roster. No email or identity/contact fields are projected.

CREATE FUNCTION eogp.list_booking_inquiry_assignees(
  p_organization_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_items jsonb;
BEGIN
  PERFORM eogp.assert_booking_inquiry_permission(
    p_organization_id, p_actor_membership_id, 'booking.inquiry.assign'
  );

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'membershipId', membership.id,
        'displayName', app_user.display_name
      )
      ORDER BY lower(app_user.display_name), membership.id
    ),
    '[]'::jsonb
  )
    INTO v_items
    FROM eogp.organization_memberships membership
    JOIN eogp.users app_user
      ON app_user.id = membership.user_id
   WHERE membership.organization_id = p_organization_id
     AND membership.status = 'active'
     AND app_user.status = 'active';

  RETURN jsonb_build_object('items', v_items);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.list_booking_inquiry_assignees(uuid,uuid)
  FROM PUBLIC, eventor_worker, eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.list_booking_inquiry_assignees(uuid,uuid)
  TO eventor_runtime;

COMMENT ON FUNCTION eogp.list_booking_inquiry_assignees(uuid,uuid) IS
  'Returns only active same-organization membership IDs and display names for inquiry assignment, gated by booking.inquiry.assign. No email/contact data is projected.';
