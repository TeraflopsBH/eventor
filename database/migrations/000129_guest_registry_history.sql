CREATE FUNCTION eogp.read_guest_registry_history(p_org uuid, p_actor uuid, p_person uuid, p_offset integer)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_participation record;
  v_participations jsonb := '[]'::jsonb;
  v_changes jsonb;
  v_has_more boolean := false;
  v_skipped integer := 0;
BEGIN
  PERFORM eogp.assert_guest_registry_permission(p_org, p_actor, false);
  IF coalesce(p_offset, -1) NOT BETWEEN 0 AND 100000 THEN
    RAISE EXCEPTION 'invalid history offset' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM eogp.persons WHERE organization_id = p_org AND id = p_person) THEN
    RAISE EXCEPTION 'person not found' USING ERRCODE = 'P0002';
  END IF;

  FOR v_participation IN
    SELECT p.id, p.event_id, p.status, p.created_at, e.title, e.event_code, e.status AS event_status,
           schedule.starts_at
    FROM eogp.event_participations p
    JOIN eogp.events e ON e.organization_id = p.organization_id AND e.id = p.event_id
    LEFT JOIN LATERAL (
      SELECT starts_at FROM eogp.event_schedule_revisions
      WHERE organization_id = e.organization_id AND event_id = e.id
      ORDER BY revision_number DESC LIMIT 1
    ) schedule ON true
    WHERE p.organization_id = p_org AND p.person_id = p_person
    ORDER BY schedule.starts_at DESC NULLS LAST, p.created_at DESC, p.id
  LOOP
    BEGIN
      BEGIN
        PERFORM eogp.assert_event_command_permission(p_org, v_participation.event_id, p_actor, 'guest.read');
      EXCEPTION WHEN insufficient_privilege THEN
        PERFORM eogp.assert_event_command_permission(p_org, v_participation.event_id, p_actor, 'guest.manage');
      END;
      IF v_skipped < p_offset THEN
        v_skipped := v_skipped + 1;
        CONTINUE;
      END IF;
      IF jsonb_array_length(v_participations) = 50 THEN
        v_has_more := true;
        EXIT;
      END IF;
      v_participations := v_participations || jsonb_build_array(jsonb_build_object(
        'participationId', v_participation.id, 'eventId', v_participation.event_id,
        'eventTitle', v_participation.title, 'eventCode', v_participation.event_code,
        'eventStatus', v_participation.event_status, 'status', v_participation.status,
        'eventStartsAt', v_participation.starts_at, 'addedAt', v_participation.created_at
      ));
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END LOOP;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'auditId', change.id, 'action', change.action, 'at', change.occurred_at,
    'revision', change.safe_metadata->'revision'
  ) ORDER BY change.occurred_at DESC, change.id), '[]'::jsonb)
  INTO v_changes
  FROM (
    SELECT id, action, occurred_at, safe_metadata FROM eogp.audit_events
    WHERE organization_id = p_org AND aggregate_type = 'person' AND aggregate_id = p_person
      AND action IN ('guest.registry.create', 'guest.registry.update', 'guest.registry.archive')
    ORDER BY occurred_at DESC, id LIMIT 51 OFFSET p_offset
  ) change;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.registry.history_viewed', 'person', p_person, '{}'::jsonb
  );
  RETURN jsonb_build_object(
    'changes', CASE WHEN jsonb_array_length(v_changes) > 50 THEN v_changes - 50 ELSE v_changes END,
    'participations', v_participations,
    'nextOffset', CASE WHEN (v_has_more OR jsonb_array_length(v_changes) > 50) AND p_offset < 100000 THEN p_offset + 50 END
  );
END;
$function$;

CREATE INDEX event_participations_person_history_idx ON eogp.event_participations(organization_id, person_id, created_at DESC);
REVOKE ALL ON FUNCTION eogp.read_guest_registry_history(uuid,uuid,uuid,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.read_guest_registry_history(uuid,uuid,uuid,integer) TO eventor_runtime;
