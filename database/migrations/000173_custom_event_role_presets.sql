CREATE FUNCTION eogp.create_organization_event_role(
  p_org uuid,p_actor uuid,p_code text,p_name text,p_description text,p_permissions text[]
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_role eogp.roles%ROWTYPE;
  v_description text := nullif(btrim(p_description),'');
  v_permission_count integer;
BEGIN
  PERFORM eogp.assert_event_command_permission(p_org,NULL,p_actor,'organization.manage');
  IF p_code IS NULL OR p_code !~ '^[A-Z0-9][A-Z0-9_-]{0,39}$'
    OR coalesce(length(btrim(p_name)),0) NOT BETWEEN 1 AND 120 OR p_name ~ '[[:cntrl:]]'
    OR length(v_description)>500 OR v_description ~ '[[:cntrl:]]'
    OR coalesce(cardinality(p_permissions),0) NOT BETWEEN 1 AND 100 THEN
    RAISE EXCEPTION 'invalid event role preset' USING ERRCODE='22023';
  END IF;
  SELECT count(*) INTO v_permission_count
  FROM eogp.permissions WHERE code=ANY(p_permissions) AND scope_kind='event';
  IF v_permission_count<>cardinality(p_permissions) THEN
    RAISE EXCEPTION 'select distinct event-level permission codes' USING ERRCODE='22023';
  END IF;
  INSERT INTO eogp.roles(organization_id,code,name,description,scope_kind)
  VALUES(p_org,p_code,btrim(p_name),v_description,'event') RETURNING * INTO v_role;
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
  SELECT p_org,v_role.id,code FROM unnest(p_permissions) code;
  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,safe_metadata)
  VALUES(p_org,p_org,p_actor,'membership','organization.role.created','organization_role',v_role.id,
    jsonb_build_object('scope','event','permissionCount',v_permission_count));
  RETURN jsonb_build_object('roleId',v_role.id);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.create_organization_event_role(uuid,uuid,text,text,text,text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.create_organization_event_role(uuid,uuid,text,text,text,text[]) TO eventor_runtime;
