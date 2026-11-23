ALTER TABLE eogp.organization_memberships ADD COLUMN access_revision integer NOT NULL DEFAULT 1 CHECK (access_revision>0);

CREATE FUNCTION eogp.set_organization_membership_access(
  p_org uuid,p_actor uuid,p_member uuid,p_expected_revision integer,p_status text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_member eogp.organization_memberships%ROWTYPE;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('eventor:organization-access:'||p_org::text,0));
  PERFORM eogp.assert_event_command_permission(p_org,NULL,p_actor,'organization.manage');
  SELECT * INTO v_member FROM eogp.organization_memberships
  WHERE organization_id=p_org AND id=p_member FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'organization member not found' USING ERRCODE='P0002'; END IF;
  IF v_member.access_revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'membership revision conflict' USING ERRCODE='40001';
  END IF;
  IF p_status IS NULL OR p_status NOT IN ('active','suspended') THEN
    RAISE EXCEPTION 'invalid membership access state' USING ERRCODE='22023';
  END IF;
  IF v_member.status NOT IN ('active','suspended') THEN
    RAISE EXCEPTION 'only active or suspended memberships can change access' USING ERRCODE='55000';
  END IF;
  IF p_status=v_member.status THEN
    RETURN jsonb_build_object('membershipId',v_member.id,'status',v_member.status,'revision',v_member.access_revision);
  END IF;
  IF p_status='active' AND NOT EXISTS (SELECT 1 FROM eogp.users WHERE id=v_member.user_id AND status='active') THEN
    RAISE EXCEPTION 'an active user is required to restore membership access' USING ERRCODE='55000';
  END IF;
  IF p_status='suspended' THEN
    PERFORM 1 FROM eogp.organization_memberships member
    JOIN eogp.users identity ON identity.id=member.user_id AND identity.status='active'
    JOIN eogp.user_role_grants assignment ON assignment.organization_id=member.organization_id AND assignment.membership_id=member.id
    JOIN eogp.role_permissions permission ON permission.organization_id=assignment.organization_id AND permission.role_id=assignment.role_id
    WHERE member.organization_id=p_org AND member.id<>p_member AND member.status='active'
      AND assignment.scope_kind='organization' AND assignment.revoked_at IS NULL
      AND (assignment.expires_at IS NULL OR assignment.expires_at>clock_timestamp())
      AND permission.permission_code='organization.manage'
    FOR SHARE OF member,identity,assignment,permission;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'retain an active organization administrator before suspending access' USING ERRCODE='P1771';
    END IF;
  END IF;

  UPDATE eogp.organization_memberships SET status=p_status,access_revision=access_revision+1
  WHERE organization_id=p_org AND id=p_member RETURNING * INTO v_member;
  IF p_status='suspended' THEN
    UPDATE eogp.user_sessions SET revoked_at=clock_timestamp()
    WHERE organization_id=p_org AND membership_id=p_member AND revoked_at IS NULL;
  END IF;
  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,safe_metadata)
  VALUES(p_org,p_org,p_actor,'membership','organization.membership.access_changed','organization_membership',p_member,
    jsonb_build_object('status',p_status,'revision',v_member.access_revision));
  RETURN jsonb_build_object('membershipId',v_member.id,'status',v_member.status,'revision',v_member.access_revision);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.set_organization_membership_access(uuid,uuid,uuid,integer,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.set_organization_membership_access(uuid,uuid,uuid,integer,text) TO eventor_runtime;

CREATE OR REPLACE FUNCTION eogp.list_organization_access_members(p_org uuid,p_actor uuid,p_offset integer)
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
    'revision',membership.access_revision,
    'grants',member_grants.items
  ) ORDER BY lower(profile.display_name),profile.membership_id),'[]'::jsonb) INTO v_members
  FROM (
    SELECT membership_id,display_name,membership_status FROM eogp.organization_member_profiles
    WHERE organization_id=p_org
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

