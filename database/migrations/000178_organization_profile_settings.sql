ALTER TABLE eogp.organizations ADD COLUMN settings_revision integer NOT NULL DEFAULT 1 CHECK(settings_revision>0);

CREATE FUNCTION eogp.read_organization_profile(p_org uuid,p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_org eogp.organizations%ROWTYPE;
  v_can_manage boolean := false;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_org
    OR nullif(current_setting('app.actor_membership_id',true),'')::uuid IS DISTINCT FROM p_actor THEN
    RAISE EXCEPTION 'organization or staff actor context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM 1 FROM eogp.organization_memberships WHERE organization_id=p_org AND id=p_actor AND status='active' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'active organization membership required' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_org FROM eogp.organizations WHERE id=p_org;
  IF NOT FOUND THEN RAISE EXCEPTION 'organization not found' USING ERRCODE='P0002'; END IF;
  BEGIN
    PERFORM eogp.assert_event_command_permission(p_org,NULL,p_actor,'organization.manage');
    v_can_manage := true;
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  RETURN jsonb_build_object('name',v_org.name,'operatingProfile',v_org.operating_profile,
    'defaultTimezone',v_org.default_timezone,'revision',v_org.settings_revision,'canManage',v_can_manage);
END;
$function$;

CREATE FUNCTION eogp.update_organization_profile(
  p_org uuid,p_actor uuid,p_revision integer,p_name text,p_profile text,p_timezone text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_org eogp.organizations%ROWTYPE;
  v_name text := btrim(p_name);
BEGIN
  PERFORM eogp.assert_event_command_permission(p_org,NULL,p_actor,'organization.manage');
  IF coalesce(length(v_name),0) NOT BETWEEN 1 AND 250 OR v_name ~ '[[:cntrl:]]'
    OR p_profile IS NULL OR p_profile NOT IN ('venue_provider','event_organizer','hybrid')
    OR p_timezone IS NULL OR NOT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=p_timezone) THEN
    RAISE EXCEPTION 'invalid organization settings' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_org FROM eogp.organizations WHERE id=p_org FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'organization not found' USING ERRCODE='P0002'; END IF;
  IF v_org.settings_revision IS DISTINCT FROM p_revision THEN
    RAISE EXCEPTION 'organization settings revision conflict' USING ERRCODE='40001';
  END IF;
  IF (v_org.name,v_org.operating_profile,v_org.default_timezone) IS DISTINCT FROM (v_name,p_profile,p_timezone) THEN
    UPDATE eogp.organizations SET name=v_name,operating_profile=p_profile,default_timezone=p_timezone,
      settings_revision=settings_revision+1,updated_at=clock_timestamp() WHERE id=p_org;
    INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,
      action,aggregate_type,aggregate_id,safe_metadata)
    VALUES(p_org,p_org,p_actor,'membership','organization.profile.updated','organization',p_org,
      jsonb_build_object('revision',p_revision+1,'nameChanged',v_org.name IS DISTINCT FROM v_name,
        'profileChanged',v_org.operating_profile IS DISTINCT FROM p_profile,'timezoneChanged',v_org.default_timezone IS DISTINCT FROM p_timezone));
  END IF;
  RETURN eogp.read_organization_profile(p_org,p_actor);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.read_organization_profile(uuid,uuid),
  eogp.update_organization_profile(uuid,uuid,integer,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.read_organization_profile(uuid,uuid),
  eogp.update_organization_profile(uuid,uuid,integer,text,text,text) TO eventor_runtime;
