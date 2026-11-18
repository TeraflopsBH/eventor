-- Authorization metadata can be changed only by specifically authorized commands.
REVOKE INSERT, UPDATE, DELETE ON eogp.organization_memberships, eogp.roles,
  eogp.role_permissions, eogp.user_role_grants, eogp.permissions FROM PUBLIC,eventor_runtime;

CREATE FUNCTION eogp.list_organization_access_roles(p_org uuid,p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_roles jsonb;
BEGIN
  PERFORM eogp.assert_event_command_permission(p_org,NULL,p_actor,'organization.manage');
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'roleId',role.id,'code',role.code,'name',role.name,'description',role.description,
    'scope',role.scope_kind,'systemPreset',role.is_system_preset,'permissionCodes',permissions.codes
  ) ORDER BY lower(role.name),role.id),'[]'::jsonb) INTO v_roles
  FROM eogp.roles role
  CROSS JOIN LATERAL (
    SELECT coalesce(jsonb_agg(permission_code ORDER BY permission_code),'[]'::jsonb) AS codes
    FROM eogp.role_permissions
    WHERE organization_id=p_org AND role_id=role.id
  ) permissions
  WHERE role.organization_id=p_org;
  RETURN v_roles;
END;
$function$;

CREATE FUNCTION eogp.list_organization_access_members(p_org uuid,p_actor uuid,p_offset integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_members jsonb;
BEGIN
  PERFORM eogp.assert_event_command_permission(p_org,NULL,p_actor,'organization.manage');
  IF coalesce(p_offset,-1) NOT BETWEEN 0 AND 100000 THEN
    RAISE EXCEPTION 'invalid member offset' USING ERRCODE='22023';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'membershipId',profile.membership_id,'displayName',profile.display_name,'status',profile.membership_status,
    'grants',member_grants.items
  ) ORDER BY lower(profile.display_name),profile.membership_id),'[]'::jsonb) INTO v_members
  FROM (
    SELECT membership_id,display_name,membership_status FROM eogp.organization_member_profiles
    WHERE organization_id=p_org
    ORDER BY lower(display_name),membership_id LIMIT 51 OFFSET p_offset
  ) profile
  CROSS JOIN LATERAL (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'grantId',assignment.id,'roleId',role.id,'roleName',role.name,'scope',assignment.scope_kind,
      'scopeId',coalesce(assignment.scope_venue_id,assignment.scope_space_id,assignment.scope_booking_id,
        assignment.scope_event_id,assignment.scope_task_id),
      'eventId',coalesce(assignment.scope_event_id,assignment.scope_task_event_id),
      'scopeName',event.title,'expiresAt',assignment.expires_at
    ) ORDER BY lower(role.name),assignment.id),'[]'::jsonb) AS items
    FROM eogp.user_role_grants assignment
    JOIN eogp.roles role ON role.organization_id=assignment.organization_id AND role.id=assignment.role_id
    LEFT JOIN eogp.events event ON event.organization_id=assignment.organization_id AND event.id=assignment.scope_event_id
    WHERE assignment.organization_id=p_org AND assignment.membership_id=profile.membership_id
      AND assignment.revoked_at IS NULL AND (assignment.expires_at IS NULL OR assignment.expires_at>statement_timestamp())
  ) member_grants;
  RETURN jsonb_build_object(
    'members',CASE WHEN jsonb_array_length(v_members)>50 THEN v_members-50 ELSE v_members END,
    'nextOffset',CASE WHEN jsonb_array_length(v_members)>50 AND p_offset<100000 THEN p_offset+50 END
  );
END;
$function$;

CREATE FUNCTION eogp.list_organization_permission_catalogue(p_org uuid,p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_permissions jsonb;
BEGIN
  PERFORM eogp.assert_event_command_permission(p_org,NULL,p_actor,'organization.manage');
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'code',code,'description',description,'scope',scope_kind,'sensitive',is_sensitive
  ) ORDER BY code),'[]'::jsonb) INTO v_permissions
  FROM eogp.permissions WHERE scope_kind<>'platform';
  RETURN v_permissions;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.list_organization_access_roles(uuid,uuid),
  eogp.list_organization_access_members(uuid,uuid,integer),
  eogp.list_organization_permission_catalogue(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.list_organization_access_roles(uuid,uuid),
  eogp.list_organization_access_members(uuid,uuid,integer),
  eogp.list_organization_permission_catalogue(uuid,uuid) TO eventor_runtime;
