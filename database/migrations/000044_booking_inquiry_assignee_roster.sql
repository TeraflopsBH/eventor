-- Provide the permitted staff workspace with a minimal same-organization
-- assignee roster. No email or identity/contact fields are projected.

CREATE FUNCTION eogp.get_booking_inquiry_capabilities(
  p_organization_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_can_assign boolean := false;
  v_can_manage boolean := false;
  v_can_annotate boolean := false;
BEGIN
  PERFORM eogp.assert_booking_inquiry_permission(
    p_organization_id, p_actor_membership_id, 'booking.inquiry.read'
  );

  BEGIN
    PERFORM eogp.assert_booking_inquiry_permission(
      p_organization_id, p_actor_membership_id, 'booking.inquiry.assign'
    );
    v_can_assign := true;
  EXCEPTION WHEN insufficient_privilege THEN
    v_can_assign := false;
  END;

  BEGIN
    PERFORM eogp.assert_booking_inquiry_permission(
      p_organization_id, p_actor_membership_id, 'booking.inquiry.manage'
    );
    v_can_manage := true;
  EXCEPTION WHEN insufficient_privilege THEN
    v_can_manage := false;
  END;

  BEGIN
    PERFORM eogp.assert_booking_inquiry_permission(
      p_organization_id, p_actor_membership_id, 'booking.inquiry.annotate'
    );
    v_can_annotate := true;
  EXCEPTION WHEN insufficient_privilege THEN
    v_can_annotate := false;
  END;

  RETURN jsonb_build_object(
    'canAssign', v_can_assign,
    'canManage', v_can_manage,
    'canAnnotate', v_can_annotate
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.get_booking_inquiry_capabilities(uuid,uuid)
  FROM PUBLIC, eventor_worker, eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.get_booking_inquiry_capabilities(uuid,uuid)
  TO eventor_runtime;

COMMENT ON FUNCTION eogp.get_booking_inquiry_capabilities(uuid,uuid) IS
  'Returns non-sensitive inquiry permission flags for an active read-authorized organization membership.';

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
