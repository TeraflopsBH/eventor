-- Complete locale preference administration for staff users and organizations.
-- Organization locale remains a fallback; a user preference is global across tenants.

ALTER TABLE eogp.users
  ADD COLUMN locale_preference text
  CHECK (locale_preference IS NULL OR locale_preference IN ('bs-BA','en'));

-- The authentication role owns global user preferences. It receives access only
-- to this non-sensitive preference column, never broader account data.
GRANT SELECT (locale_preference) ON eogp.users TO eventor_auth;
GRANT UPDATE (locale_preference,updated_at) ON eogp.users TO eventor_auth;
GRANT SELECT (default_locale) ON eogp.organizations TO eventor_auth;

CREATE FUNCTION eogp.get_organization_locale_settings(
  p_organization_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_locale text;
  v_can_manage boolean := false;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;

  SELECT default_locale INTO v_locale
    FROM eogp.organizations
   WHERE id=p_organization_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'organization not found' USING ERRCODE='P0002';
  END IF;

  BEGIN
    PERFORM eogp.assert_event_command_permission(
      p_organization_id,NULL,p_actor_membership_id,'organization.manage'
    );
    v_can_manage := true;
  EXCEPTION WHEN insufficient_privilege THEN
    v_can_manage := false;
  END;

  RETURN jsonb_build_object(
    'defaultLocale',v_locale,
    'canManage',v_can_manage
  );
END;
$function$;

CREATE FUNCTION eogp.set_organization_default_locale(
  p_organization_id uuid,
  p_actor_membership_id uuid,
  p_locale text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_previous_locale text;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;

  PERFORM eogp.assert_event_command_permission(
    p_organization_id,NULL,p_actor_membership_id,'organization.manage'
  );

  IF p_locale NOT IN ('bs-BA','en') THEN
    RAISE EXCEPTION 'unsupported organization locale' USING ERRCODE='22023';
  END IF;

  SELECT default_locale INTO v_previous_locale
    FROM eogp.organizations
   WHERE id=p_organization_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'organization not found' USING ERRCODE='P0002';
  END IF;

  UPDATE eogp.organizations
     SET default_locale=p_locale,updated_at=clock_timestamp()
   WHERE id=p_organization_id;

  IF v_previous_locale IS DISTINCT FROM p_locale THEN
    INSERT INTO eogp.audit_events (
      organization_id,actor_organization_id,actor_membership_id,actor_kind,
      action,aggregate_type,aggregate_id,safe_metadata
    ) VALUES (
      p_organization_id,p_organization_id,p_actor_membership_id,'membership',
      'organization.locale_default_changed','organization',p_organization_id,
      jsonb_build_object('previousLocale',v_previous_locale,'defaultLocale',p_locale)
    );
  END IF;

  RETURN jsonb_build_object('defaultLocale',p_locale);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.get_organization_locale_settings(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.set_organization_default_locale(uuid,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
  eogp.get_organization_locale_settings(uuid,uuid),
  eogp.set_organization_default_locale(uuid,uuid,text)
TO eventor_runtime;
