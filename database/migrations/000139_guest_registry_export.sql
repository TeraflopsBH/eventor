INSERT INTO eogp.permissions (code, description, scope_kind, is_sensitive)
VALUES ('guest.registry.export', 'Export the organizer-owned guest name directory', 'organization', true);

CREATE FUNCTION eogp.guest_registry_matches_filter(p_person eogp.persons, p_query text, p_archived boolean)
RETURNS boolean LANGUAGE sql STABLE
AS $function$
  SELECT p_person.status = CASE WHEN p_archived THEN 'archived' ELSE 'active' END
    AND (p_query = '' OR pg_catalog.strpos(pg_catalog.lower(pg_catalog.concat_ws(' ', p_person.first_name, p_person.last_name)), p_query) > 0
      OR pg_catalog.strpos(pg_catalog.lower(pg_catalog.concat_ws(' ', p_person.last_name, p_person.first_name)), p_query) > 0
      OR pg_catalog.strpos(pg_catalog.lower(coalesce(p_person.display_name, '')), p_query) > 0
      OR pg_catalog.strpos(pg_catalog.lower(coalesce(p_person.preferred_name, '')), p_query) > 0);
$function$;

CREATE OR REPLACE FUNCTION eogp.read_guest_registry(
  p_org uuid, p_actor uuid, p_person_id uuid, p_query text, p_archived boolean, p_offset integer
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_person eogp.persons%ROWTYPE;
  v_rows jsonb;
  v_can_manage boolean := true;
  v_can_export boolean := true;
  v_query text := lower(btrim(coalesce(p_query, '')));
BEGIN
  PERFORM eogp.assert_guest_registry_permission(p_org, p_actor, false);
  IF length(v_query) > 200 OR coalesce(p_offset, -1) NOT BETWEEN 0 AND 100000 THEN
    RAISE EXCEPTION 'invalid directory filter' USING ERRCODE = '22023';
  END IF;

  IF p_person_id IS NOT NULL THEN
    SELECT * INTO v_person FROM eogp.persons WHERE organization_id = p_org AND id = p_person_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'person not found' USING ERRCODE = 'P0002'; END IF;
  END IF;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership',
    CASE WHEN p_person_id IS NULL THEN 'guest.registry.searched' ELSE 'guest.registry.profile_viewed' END,
    CASE WHEN p_person_id IS NULL THEN 'organization' ELSE 'person' END,
    coalesce(p_person_id, p_org), '{}'::jsonb
  );

  IF p_person_id IS NOT NULL THEN RETURN eogp.guest_registry_person_projection(v_person); END IF;

  BEGIN
    PERFORM eogp.assert_guest_registry_permission(p_org, p_actor, true);
  EXCEPTION WHEN insufficient_privilege THEN v_can_manage := false;
  END;

  BEGIN
    PERFORM eogp.assert_event_command_permission(p_org, NULL, p_actor, 'guest.registry.export');
  EXCEPTION WHEN insufficient_privilege THEN v_can_export := false;
  END;

  SELECT coalesce(jsonb_agg(eogp.guest_registry_person_projection(p)
    ORDER BY lower(p.last_name), lower(p.first_name), p.id), '[]'::jsonb) INTO v_rows
  FROM (
    SELECT person.* FROM eogp.persons person
    WHERE organization_id = p_org
      AND eogp.guest_registry_matches_filter(person, v_query, p_archived)
    ORDER BY lower(last_name), lower(first_name), id
    LIMIT 51 OFFSET p_offset
  ) p;
  RETURN jsonb_build_object(
    'people', CASE WHEN jsonb_array_length(v_rows) > 50 THEN v_rows - 50 ELSE v_rows END, 'canManage', v_can_manage,
    'canExport', v_can_export,
    'nextOffset', CASE WHEN jsonb_array_length(v_rows) > 50 AND p_offset < 100000 THEN p_offset + 50 END
  );
END;
$function$;

CREATE FUNCTION eogp.read_guest_registry_export(p_org uuid, p_actor uuid, p_query text, p_archived boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_query text := lower(btrim(coalesce(p_query, '')));
  v_rows jsonb;
  v_count integer;
BEGIN
  IF nullif(current_setting('app.actor_membership_id', true), '')::uuid IS DISTINCT FROM p_actor THEN
    RAISE EXCEPTION 'staff actor context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_guest_registry_permission(p_org, p_actor, false);
  PERFORM eogp.assert_event_command_permission(p_org, NULL, p_actor, 'guest.registry.export');
  IF length(v_query) > 200 THEN
    RAISE EXCEPTION 'invalid directory filter' USING ERRCODE = '22023';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'firstName', person.first_name, 'lastName', person.last_name, 'displayName', person.display_name,
    'preferredName', person.preferred_name, 'status', person.status
  ) ORDER BY lower(person.last_name), lower(person.first_name), person.id), '[]'::jsonb), count(*)
  INTO v_rows, v_count
  FROM (
    SELECT p.* FROM eogp.persons p
    WHERE p.organization_id = p_org AND eogp.guest_registry_matches_filter(p, v_query, p_archived)
    ORDER BY lower(p.last_name), lower(p.first_name), p.id LIMIT 20001
  ) person;
  IF v_count > 20000 THEN
    RETURN jsonb_build_object('limitExceeded', true);
  END IF;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.registry.exported', 'organization', p_org,
    jsonb_build_object('exportedCount', v_count, 'archived', coalesce(p_archived, false))
  );
  RETURN jsonb_build_object('people', v_rows);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.guest_registry_matches_filter(eogp.persons,text,boolean),
  eogp.read_guest_registry_export(uuid,uuid,text,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.read_guest_registry_export(uuid,uuid,text,boolean) TO eventor_runtime;
