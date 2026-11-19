-- Expiration and revocation are independent facts on a grant.
DO $constraint$
DECLARE v_constraint text;
BEGIN
  SELECT conname INTO STRICT v_constraint FROM pg_constraint
  WHERE conrelid='eogp.user_role_grants'::regclass AND contype='c'
    AND pg_get_constraintdef(oid) LIKE '%expires_at%revoked_at%';
  EXECUTE format('ALTER TABLE eogp.user_role_grants DROP CONSTRAINT %I',v_constraint);
END;
$constraint$;
ALTER TABLE eogp.user_role_grants ADD CONSTRAINT user_role_grants_expiry_after_creation
  CHECK (expires_at IS NULL OR expires_at>created_at);

CREATE FUNCTION eogp.list_organization_access_events(p_org uuid,p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
DECLARE v_events jsonb;
BEGIN
  PERFORM eogp.assert_event_command_permission(p_org,NULL,p_actor,'organization.manage');
  SELECT coalesce(jsonb_agg(jsonb_build_object('eventId',id,'eventCode',event_code,'title',title)
    ORDER BY lower(title),id),'[]'::jsonb) INTO v_events
  FROM eogp.events WHERE organization_id=p_org AND status NOT IN ('completed','cancelled','archived');
  RETURN v_events;
END;
$function$;

CREATE FUNCTION eogp.write_member_event_role(
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
    PERFORM 1 FROM eogp.roles WHERE organization_id=p_org AND id=p_role AND scope_kind='event' FOR SHARE;
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

REVOKE ALL ON FUNCTION eogp.list_organization_access_events(uuid,uuid),
  eogp.write_member_event_role(uuid,uuid,uuid,uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.list_organization_access_events(uuid,uuid),
  eogp.write_member_event_role(uuid,uuid,uuid,uuid,uuid,uuid) TO eventor_runtime;
