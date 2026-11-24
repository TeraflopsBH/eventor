-- Expose only selected-tenant membership management status, never the global account directory.
CREATE OR REPLACE FUNCTION eogp.search_organization_access_members(p_org uuid,p_actor uuid,p_offset integer,p_query text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_members jsonb;
  v_query text := lower(btrim(coalesce(p_query,'')));
BEGIN
  PERFORM eogp.assert_event_command_permission(p_org,NULL,p_actor,'organization.manage');
  IF length(v_query)>200 OR coalesce(p_offset,-1) NOT BETWEEN 0 AND 100000 THEN
    RAISE EXCEPTION 'invalid member offset' USING ERRCODE='22023';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'membershipId',profile.membership_id,'displayName',profile.display_name,'status',profile.membership_status,
    'revision',membership.access_revision,
    'hostManaged',EXISTS(SELECT 1 FROM eogp.users account WHERE account.id=membership.user_id AND account.is_platform_admin),
    'grants',member_grants.items
  ) ORDER BY lower(profile.display_name),profile.membership_id),'[]'::jsonb) INTO v_members
  FROM (
    SELECT membership_id,display_name,membership_status FROM eogp.organization_member_profiles
    WHERE organization_id=p_org AND (v_query='' OR position(v_query in lower(display_name))>0)
    ORDER BY lower(display_name),membership_id LIMIT 51 OFFSET p_offset
  ) profile
  JOIN eogp.organization_memberships membership ON membership.organization_id=p_org AND membership.id=profile.membership_id
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


REVOKE ALL ON FUNCTION eogp.search_organization_access_members(uuid,uuid,integer,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.search_organization_access_members(uuid,uuid,integer,text) TO eventor_runtime;

-- Keep the legacy unfiltered directory consistent with the searched directory.
CREATE OR REPLACE FUNCTION eogp.list_organization_access_members(p_org uuid,p_actor uuid,p_offset integer)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,eogp
AS $function$
 SELECT eogp.search_organization_access_members(p_org,p_actor,p_offset,'');
$function$;
REVOKE ALL ON FUNCTION eogp.list_organization_access_members(uuid,uuid,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.list_organization_access_members(uuid,uuid,integer) TO eventor_runtime;
