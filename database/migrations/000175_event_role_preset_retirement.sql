ALTER TABLE eogp.roles ADD COLUMN retired_at timestamptz;

CREATE FUNCTION eogp.retire_organization_event_role(p_org uuid,p_actor uuid,p_role uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
DECLARE v_role eogp.roles%ROWTYPE;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended('eventor:organization-access:'||p_org::text,0));
  PERFORM eogp.assert_event_command_permission(p_org,NULL,p_actor,'organization.manage');
  SELECT * INTO v_role FROM eogp.roles WHERE organization_id=p_org AND id=p_role AND scope_kind='event' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'event role preset not found' USING ERRCODE='P0002'; END IF;
  IF v_role.is_system_preset THEN RAISE EXCEPTION 'system role presets cannot retire' USING ERRCODE='55000'; END IF;
  IF v_role.retired_at IS NULL THEN
    UPDATE eogp.roles SET retired_at=clock_timestamp() WHERE organization_id=p_org AND id=p_role RETURNING * INTO v_role;
    INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,
      action,aggregate_type,aggregate_id,safe_metadata)
    VALUES(p_org,p_org,p_actor,'membership','organization.role.retired','organization_role',p_role,'{"scope":"event"}');
  END IF;
  RETURN jsonb_build_object('roleId',v_role.id,'retiredAt',v_role.retired_at);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.retire_organization_event_role(uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.retire_organization_event_role(uuid,uuid,uuid) TO eventor_runtime;

CREATE OR REPLACE FUNCTION eogp.list_organization_access_roles(p_org uuid,p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_roles jsonb;
BEGIN
  PERFORM eogp.assert_event_command_permission(p_org,NULL,p_actor,'organization.manage');
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'roleId',role.id,'code',role.code,'name',role.name,'description',role.description,
    'scope',role.scope_kind,'systemPreset',role.is_system_preset,'retiredAt',role.retired_at,'permissionCodes',permissions.codes
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

CREATE OR REPLACE FUNCTION eogp.write_member_event_role(
  p_org uuid,p_actor uuid,p_member uuid,p_role uuid,p_event uuid,p_revoke uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_member_status text;
  v_grant eogp.user_role_grants%ROWTYPE;
  v_action text;
BEGIN
  -- Serialize authorization changes before taking shared authorization locks.
  PERFORM pg_advisory_xact_lock(hashtextextended('eventor:organization-access:'||p_org::text,0));
  PERFORM eogp.assert_event_command_permission(p_org,NULL,p_actor,'organization.manage');
  SELECT status INTO v_member_status FROM eogp.organization_memberships
  WHERE organization_id=p_org AND id=p_member FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'organization member not found' USING ERRCODE='P0002'; END IF;

  IF p_revoke IS NOT NULL THEN
    SELECT * INTO v_grant FROM eogp.user_role_grants
    WHERE organization_id=p_org AND membership_id=p_member AND id=p_revoke AND scope_kind='event' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'event role grant not found' USING ERRCODE='P0002'; END IF;
    IF v_grant.revoked_at IS NOT NULL THEN
      RETURN jsonb_build_object('grantId',v_grant.id,'revokedAt',v_grant.revoked_at);
    END IF;
    UPDATE eogp.user_role_grants SET revoked_at=clock_timestamp()
    WHERE organization_id=p_org AND id=v_grant.id RETURNING * INTO v_grant;
    v_action := 'organization.event_role.revoked';
  ELSE
    IF v_member_status<>'active' THEN
      RAISE EXCEPTION 'event roles require an active member' USING ERRCODE='55000';
    END IF;
    PERFORM 1 FROM eogp.roles WHERE organization_id=p_org AND id=p_role AND scope_kind='event' AND retired_at IS NULL FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'event role preset not found' USING ERRCODE='P0002'; END IF;
    PERFORM 1 FROM eogp.events WHERE organization_id=p_org AND id=p_event
      AND status NOT IN ('completed','cancelled','archived') FOR SHARE;
    IF NOT FOUND THEN RAISE EXCEPTION 'open event not found' USING ERRCODE='P0002'; END IF;
    SELECT * INTO v_grant FROM eogp.user_role_grants
    WHERE organization_id=p_org AND membership_id=p_member AND role_id=p_role
      AND scope_kind='event' AND scope_event_id=p_event AND revoked_at IS NULL
      AND (expires_at IS NULL OR expires_at>clock_timestamp()) ORDER BY created_at,id LIMIT 1;
    IF FOUND THEN RETURN jsonb_build_object('grantId',v_grant.id,'revokedAt',NULL); END IF;
    INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,scope_event_id,granted_by_membership_id)
    VALUES(p_org,p_member,p_role,'event',p_event,p_actor) RETURNING * INTO v_grant;
    v_action := 'organization.event_role.granted';
  END IF;

  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,safe_metadata)
  VALUES(p_org,p_org,p_actor,'membership',v_action,'user_role_grant',v_grant.id,
    jsonb_build_object('membershipId',p_member,'roleId',v_grant.role_id,'eventId',v_grant.scope_event_id));
  RETURN jsonb_build_object('grantId',v_grant.id,'revokedAt',v_grant.revoked_at);
END;
$function$;

