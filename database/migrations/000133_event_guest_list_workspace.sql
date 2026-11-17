CREATE FUNCTION eogp.assert_event_guest_list_access(p_org uuid, p_event uuid, p_actor uuid)
RETURNS boolean LANGUAGE plpgsql SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  BEGIN
    PERFORM eogp.assert_event_command_permission(p_org, p_event, p_actor, 'guest.manage');
    RETURN true;
  EXCEPTION WHEN insufficient_privilege THEN
    PERFORM eogp.assert_event_command_permission(p_org, p_event, p_actor, 'guest.read');
    RETURN false;
  END;
END;
$function$;

CREATE FUNCTION eogp.list_event_guest_workspaces(p_org uuid, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_event record;
  v_result jsonb := '[]'::jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_org
     OR nullif(current_setting('app.actor_membership_id', true), '')::uuid IS DISTINCT FROM p_actor THEN
    RAISE EXCEPTION 'organization or staff actor context mismatch' USING ERRCODE = '42501';
  END IF;

  FOR v_event IN
    SELECT event.id, event.title, event.event_code, event.status
    FROM eogp.events event WHERE event.organization_id = p_org AND (
      EXISTS (SELECT 1 FROM eogp.event_capability_overrides capability
        WHERE capability.organization_id = p_org AND capability.event_id = event.id
          AND capability.capability_code = 'guest_registry' AND capability.enabled)
      OR EXISTS (SELECT 1 FROM eogp.event_participations p WHERE p.organization_id = p_org AND p.event_id = event.id)
    )
    ORDER BY event.updated_at DESC, event.id
  LOOP
    BEGIN
      PERFORM eogp.assert_event_guest_list_access(p_org, v_event.id, p_actor);
      v_result := v_result || jsonb_build_array(jsonb_build_object(
        'eventId', v_event.id, 'title', v_event.title, 'eventCode', v_event.event_code, 'status', v_event.status
      ));
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END LOOP;
  RETURN v_result;
END;
$function$;

CREATE FUNCTION eogp.read_event_guest_list(p_org uuid, p_event uuid, p_actor uuid, p_status text, p_offset integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_event_status text;
  v_can_manage boolean;
  v_rows jsonb;
BEGIN
  v_can_manage := eogp.assert_event_guest_list_access(p_org, p_event, p_actor);
  SELECT status INTO v_event_status FROM eogp.events WHERE organization_id = p_org AND id = p_event;
  IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002'; END IF;
  IF coalesce(p_offset, -1) NOT BETWEEN 0 AND 100000 OR
     (p_status IS NOT NULL AND p_status NOT IN ('eligible', 'waitlisted', 'withdrawn', 'cancelled', 'ineligible')) THEN
    RAISE EXCEPTION 'invalid guest list filter' USING ERRCODE = '22023';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'participationId', p.id, 'displayName', p.display_name, 'status', p.status, 'revision', p.revision,
    'categoryCode', p.category_code, 'participationCode', p.participation_code
  ) ORDER BY lower(p.display_name), p.id), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT participation.id, participation.status, participation.revision,
           participation.category_code, participation.participation_code,
           coalesce(participation.person_identity_snapshot->>'displayName', nullif(person.display_name, ''),
                    nullif(person.preferred_name, ''), concat_ws(' ', person.first_name, person.last_name)) AS display_name
    FROM eogp.event_participations participation
    JOIN eogp.persons person ON person.organization_id = participation.organization_id AND person.id = participation.person_id
    WHERE participation.organization_id = p_org AND participation.event_id = p_event
      AND (p_status IS NULL OR participation.status = p_status)
    ORDER BY lower(coalesce(participation.person_identity_snapshot->>'displayName', nullif(person.display_name, ''),
                    nullif(person.preferred_name, ''), concat_ws(' ', person.first_name, person.last_name))), participation.id
    LIMIT 51 OFFSET p_offset
  ) p;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id
  ) VALUES (p_org, p_org, p_actor, 'membership', 'guest.event_roster.viewed', 'event', p_event);

  RETURN jsonb_build_object(
    'people', CASE WHEN jsonb_array_length(v_rows) > 50 THEN v_rows - 50 ELSE v_rows END,
    'canManage', v_can_manage AND v_event_status IN ('draft', 'planned', 'scheduled', 'active'),
    'nextOffset', CASE WHEN jsonb_array_length(v_rows) > 50 AND p_offset < 100000 THEN p_offset + 50 END
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.assert_event_guest_list_access(uuid,uuid,uuid),
  eogp.list_event_guest_workspaces(uuid,uuid), eogp.read_event_guest_list(uuid,uuid,uuid,text,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.list_event_guest_workspaces(uuid,uuid),
  eogp.read_event_guest_list(uuid,uuid,uuid,text,integer) TO eventor_runtime;
