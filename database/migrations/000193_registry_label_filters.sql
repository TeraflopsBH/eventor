-- Filter before pagination/export limits using stable internal label IDs.
CREATE INDEX registry_person_labels_by_label ON eogp.registry_person_label_assignments(organization_id,label_id,person_id);
CREATE FUNCTION eogp.list_registry_labels(p_org uuid,p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_labels jsonb;
BEGIN
 PERFORM eogp.assert_registry_label_access(p_org,p_actor,false);
 SELECT coalesce(jsonb_agg(jsonb_build_object('labelId',id,'label',label,'retired',retired_at IS NOT NULL) ORDER BY retired_at IS NOT NULL,lower(label),id),'[]'::jsonb) INTO v_labels FROM eogp.registry_labels WHERE organization_id=p_org;
 RETURN v_labels;
END;
$function$;
REVOKE ALL ON FUNCTION eogp.list_registry_labels(uuid,uuid) FROM PUBLIC,eventor_auth,eventor_worker;
GRANT EXECUTE ON FUNCTION eogp.list_registry_labels(uuid,uuid) TO eventor_runtime;

CREATE FUNCTION eogp.read_guest_registry(
  p_org uuid, p_actor uuid, p_person_id uuid, p_query text, p_archived boolean, p_offset integer, p_label uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_person eogp.persons%ROWTYPE;
  v_rows jsonb;
  v_can_manage boolean := true;
  v_can_export boolean := true;
  v_can_merge boolean := true;
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
    coalesce(p_person_id, p_org), CASE WHEN p_person_id IS NULL AND p_label IS NOT NULL THEN jsonb_build_object('labelId',p_label) ELSE '{}'::jsonb END
  );

  IF p_person_id IS NOT NULL THEN RETURN eogp.guest_registry_person_projection(v_person)||jsonb_build_object('labels',eogp.registry_person_label_projection(p_org,p_person_id)); END IF;

  BEGIN
    PERFORM eogp.assert_guest_registry_permission(p_org, p_actor, true);
  EXCEPTION WHEN insufficient_privilege THEN v_can_manage := false;
  END;

  BEGIN
    PERFORM eogp.assert_event_command_permission(p_org, NULL, p_actor, 'guest.registry.export');
  EXCEPTION WHEN insufficient_privilege THEN v_can_export := false;
  END;

  BEGIN
    PERFORM eogp.assert_guest_registry_merge_permission(p_org, p_actor);
  EXCEPTION WHEN insufficient_privilege THEN v_can_merge := false;
  END;

  SELECT coalesce(jsonb_agg(eogp.guest_registry_person_projection(p)||jsonb_build_object('labels',eogp.registry_person_label_projection(p_org,p.id))
    ORDER BY lower(p.last_name), lower(p.first_name), p.id), '[]'::jsonb) INTO v_rows
  FROM (
    SELECT person.* FROM eogp.persons person
    WHERE organization_id = p_org
      AND eogp.guest_registry_matches_filter(person, v_query, p_archived)
      AND (p_label IS NULL OR EXISTS(SELECT 1 FROM eogp.registry_person_label_assignments assignment WHERE assignment.organization_id=p_org AND assignment.person_id=person.id AND assignment.label_id=p_label))
    ORDER BY lower(last_name), lower(first_name), id
    LIMIT 51 OFFSET p_offset
  ) p;
  RETURN jsonb_build_object(
    'people', CASE WHEN jsonb_array_length(v_rows) > 50 THEN v_rows - 50 ELSE v_rows END, 'canManage', v_can_manage,
    'canExport', v_can_export, 'canMerge', v_can_merge,
    'nextOffset', CASE WHEN jsonb_array_length(v_rows) > 50 AND p_offset < 100000 THEN p_offset + 50 END
  );
END;
$function$;
CREATE OR REPLACE FUNCTION eogp.read_guest_registry(p_org uuid,p_actor uuid,p_person uuid,p_query text,p_archived boolean,p_offset integer)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
 SELECT eogp.read_guest_registry(p_org,p_actor,p_person,p_query,p_archived,p_offset,NULL::uuid);
$function$;
REVOKE ALL ON FUNCTION eogp.read_guest_registry(uuid,uuid,uuid,text,boolean,integer,uuid) FROM PUBLIC,eventor_auth,eventor_worker;
GRANT EXECUTE ON FUNCTION eogp.read_guest_registry(uuid,uuid,uuid,text,boolean,integer,uuid) TO eventor_runtime;

CREATE FUNCTION eogp.read_guest_registry_export(p_org uuid, p_actor uuid, p_query text, p_archived boolean,p_label uuid)
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
      AND (p_label IS NULL OR EXISTS(SELECT 1 FROM eogp.registry_person_label_assignments assignment WHERE assignment.organization_id=p_org AND assignment.person_id=p.id AND assignment.label_id=p_label))
    ORDER BY lower(p.last_name), lower(p.first_name), p.id LIMIT 20001
  ) person;
  IF v_count > 20000 THEN
    RETURN jsonb_build_object('limitExceeded', true);
  END IF;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.registry.exported', 'organization', p_org,
    jsonb_build_object('exportedCount', v_count, 'archived', coalesce(p_archived, false))||CASE WHEN p_label IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('labelId',p_label) END
  );
  RETURN jsonb_build_object('people', v_rows);
END;
$function$;


CREATE OR REPLACE FUNCTION eogp.read_guest_registry_export(p_org uuid,p_actor uuid,p_query text,p_archived boolean)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
 SELECT eogp.read_guest_registry_export(p_org,p_actor,p_query,p_archived,NULL::uuid);
$function$;
REVOKE ALL ON FUNCTION eogp.read_guest_registry_export(uuid,uuid,text,boolean,uuid) FROM PUBLIC,eventor_auth,eventor_worker;
GRANT EXECUTE ON FUNCTION eogp.read_guest_registry_export(uuid,uuid,text,boolean,uuid) TO eventor_runtime;
