INSERT INTO eogp.permissions (code, description, scope_kind, is_sensitive) VALUES
  ('guest.registry.read', 'Browse organizer-owned person profiles', 'organization', true),
  ('guest.registry.manage', 'Create, edit and archive organizer-owned person profiles', 'organization', true);

ALTER TABLE eogp.persons ADD COLUMN revision integer NOT NULL DEFAULT 1 CHECK (revision > 0);
REVOKE ALL ON eogp.persons FROM eventor_runtime;

CREATE FUNCTION eogp.assert_guest_registry_permission(p_org uuid, p_actor uuid, p_write boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  IF NOT p_write THEN
    BEGIN
      PERFORM eogp.assert_event_command_permission(p_org, NULL, p_actor, 'guest.registry.read');
      RETURN;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END IF;
  PERFORM eogp.assert_event_command_permission(p_org, NULL, p_actor, 'guest.registry.manage');
END;
$function$;

CREATE FUNCTION eogp.guest_registry_person_projection(p_person eogp.persons)
RETURNS jsonb LANGUAGE sql STABLE SET search_path = pg_catalog, eogp
AS $function$
  SELECT jsonb_build_object(
    'personId', p_person.id, 'firstName', p_person.first_name, 'lastName', p_person.last_name,
    'displayName', p_person.display_name, 'preferredName', p_person.preferred_name,
    'status', p_person.status, 'revision', p_person.revision
  )
$function$;

CREATE FUNCTION eogp.read_guest_registry(
  p_org uuid, p_actor uuid, p_person_id uuid, p_query text, p_archived boolean, p_offset integer
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_person eogp.persons%ROWTYPE;
  v_rows jsonb;
  v_can_manage boolean := true;
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

  SELECT coalesce(jsonb_agg(eogp.guest_registry_person_projection(p)
    ORDER BY lower(p.last_name), lower(p.first_name), p.id), '[]'::jsonb) INTO v_rows
  FROM (
    SELECT person.* FROM eogp.persons person
    WHERE organization_id = p_org
      AND status = CASE WHEN p_archived THEN 'archived' ELSE 'active' END
      AND (v_query = '' OR strpos(lower(concat_ws(' ', first_name, last_name)), v_query) > 0
        OR strpos(lower(concat_ws(' ', last_name, first_name)), v_query) > 0
        OR strpos(lower(coalesce(display_name, '')), v_query) > 0
        OR strpos(lower(coalesce(preferred_name, '')), v_query) > 0)
    ORDER BY lower(last_name), lower(first_name), id
    LIMIT 51 OFFSET p_offset
  ) p;
  RETURN jsonb_build_object(
    'people', CASE WHEN jsonb_array_length(v_rows) > 50 THEN v_rows - 50 ELSE v_rows END, 'canManage', v_can_manage,
    'nextOffset', CASE WHEN jsonb_array_length(v_rows) > 50 AND p_offset < 100000 THEN p_offset + 50 END
  );
END;
$function$;

CREATE FUNCTION eogp.write_guest_registry_person(
  p_org uuid, p_actor uuid, p_person_id uuid, p_expected_revision integer, p_action text, p_names jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_person eogp.persons%ROWTYPE;
  v_first text;
  v_last text;
  v_display text;
  v_preferred text;
BEGIN
  PERFORM eogp.assert_guest_registry_permission(p_org, p_actor, true);
  IF p_action IS NULL OR p_action NOT IN ('create', 'update', 'archive') THEN
    RAISE EXCEPTION 'invalid person operation' USING ERRCODE = '22023';
  END IF;

  IF p_action <> 'create' THEN
    SELECT * INTO v_person FROM eogp.persons WHERE organization_id = p_org AND id = p_person_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'person not found' USING ERRCODE = 'P0002'; END IF;
    IF p_expected_revision IS DISTINCT FROM v_person.revision THEN
      RAISE EXCEPTION 'person revision conflict' USING ERRCODE = '40001';
    END IF;
    IF v_person.status <> 'active' THEN
      RAISE EXCEPTION 'only active persons can be changed' USING ERRCODE = '55000';
    END IF;
  END IF;

  IF p_action = 'archive' THEN
    IF EXISTS (
      SELECT 1 FROM eogp.event_participations participation
      JOIN eogp.events event ON event.organization_id = participation.organization_id
                           AND event.id = participation.event_id
      WHERE participation.organization_id = p_org AND participation.person_id = p_person_id
        AND participation.status IN ('eligible', 'waitlisted')
        AND event.status NOT IN ('completed', 'cancelled', 'archived')
    ) THEN
      RAISE EXCEPTION 'person has outstanding event participation' USING ERRCODE = '55000';
    END IF;
    UPDATE eogp.persons SET status = 'archived', revision = revision + 1, updated_at = clock_timestamp()
    WHERE organization_id = p_org AND id = p_person_id RETURNING * INTO v_person;
  ELSE
    IF jsonb_typeof(p_names) IS DISTINCT FROM 'object' OR p_names = '{}'::jsonb THEN
      RAISE EXCEPTION 'invalid profile fields' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (
         SELECT 1 FROM jsonb_each(p_names) f
         WHERE f.key NOT IN ('firstName', 'lastName', 'displayName', 'preferredName')
           OR jsonb_typeof(f.value) NOT IN ('string', 'null')
       ) THEN
      RAISE EXCEPTION 'invalid profile fields' USING ERRCODE = '22023';
    END IF;
    v_first := CASE WHEN p_names ? 'firstName' THEN btrim(p_names->>'firstName') ELSE v_person.first_name END;
    v_last := CASE WHEN p_names ? 'lastName' THEN btrim(p_names->>'lastName') ELSE v_person.last_name END;
    v_display := CASE WHEN p_names ? 'displayName' THEN nullif(btrim(p_names->>'displayName'), '') ELSE v_person.display_name END;
    v_preferred := CASE WHEN p_names ? 'preferredName' THEN nullif(btrim(p_names->>'preferredName'), '') ELSE v_person.preferred_name END;
    IF coalesce(length(v_first), 0) NOT BETWEEN 1 AND 200 OR coalesce(length(v_last), 0) NOT BETWEEN 1 AND 200
       OR length(v_display) > 250 OR length(v_preferred) > 200 THEN
      RAISE EXCEPTION 'invalid profile names' USING ERRCODE = '22023';
    END IF;
    IF p_action = 'create' THEN
      INSERT INTO eogp.persons (organization_id, first_name, last_name, display_name, preferred_name, created_by_membership_id)
      VALUES (p_org, v_first, v_last, v_display, v_preferred, p_actor) RETURNING * INTO v_person;
    ELSE
      UPDATE eogp.persons SET first_name = v_first, last_name = v_last,
        display_name = v_display, preferred_name = v_preferred, revision = revision + 1, updated_at = clock_timestamp()
      WHERE organization_id = p_org AND id = p_person_id RETURNING * INTO v_person;
    END IF;
  END IF;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.registry.' || p_action,
    'person', v_person.id, jsonb_build_object('revision', v_person.revision)
  );
  RETURN jsonb_build_object('personId', v_person.id, 'revision', v_person.revision, 'status', v_person.status);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.guest_registry_person_projection(eogp.persons) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.assert_guest_registry_permission(uuid,uuid,boolean),
  eogp.read_guest_registry(uuid,uuid,uuid,text,boolean,integer),
  eogp.write_guest_registry_person(uuid,uuid,uuid,integer,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.assert_guest_registry_permission(uuid,uuid,boolean),
  eogp.read_guest_registry(uuid,uuid,uuid,text,boolean,integer),
  eogp.write_guest_registry_person(uuid,uuid,uuid,integer,text,jsonb) TO eventor_runtime;
