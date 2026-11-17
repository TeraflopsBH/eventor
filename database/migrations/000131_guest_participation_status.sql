ALTER TABLE eogp.event_participations ADD COLUMN revision integer NOT NULL DEFAULT 1 CHECK (revision > 0);

CREATE OR REPLACE FUNCTION eogp.read_guest_registry_history(p_org uuid, p_actor uuid, p_person uuid, p_offset integer)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_participation record;
  v_participations jsonb := '[]'::jsonb;
  v_changes jsonb;
  v_has_more boolean := false;
  v_skipped integer := 0;
  v_can_manage boolean;
BEGIN
  PERFORM eogp.assert_guest_registry_permission(p_org, p_actor, false);
  IF coalesce(p_offset, -1) NOT BETWEEN 0 AND 100000 THEN
    RAISE EXCEPTION 'invalid history offset' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM eogp.persons WHERE organization_id = p_org AND id = p_person) THEN
    RAISE EXCEPTION 'person not found' USING ERRCODE = 'P0002';
  END IF;

  FOR v_participation IN
    SELECT p.id, p.event_id, p.status, p.revision, p.created_at, e.title, e.event_code, e.status AS event_status,
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
        PERFORM eogp.assert_event_command_permission(p_org, v_participation.event_id, p_actor, 'guest.manage');
        v_can_manage := true;
      EXCEPTION WHEN insufficient_privilege THEN
        PERFORM eogp.assert_event_command_permission(p_org, v_participation.event_id, p_actor, 'guest.read');
        v_can_manage := false;
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
        'revision', v_participation.revision,
        'canManage', v_can_manage AND v_participation.status <> 'cancelled'
          AND v_participation.event_status IN ('draft', 'planned', 'scheduled', 'active'),
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

CREATE FUNCTION eogp.update_guest_participation_status(
  p_org uuid, p_event uuid, p_actor uuid, p_participation uuid, p_expected_revision integer, p_status text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_event_status text;
  v_participation eogp.event_participations%ROWTYPE;
  v_person_status text;
BEGIN
  PERFORM eogp.assert_event_command_permission(p_org, p_event, p_actor, 'guest.manage');
  SELECT status INTO v_event_status FROM eogp.events WHERE organization_id = p_org AND id = p_event FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002'; END IF;
  IF v_event_status NOT IN ('draft', 'planned', 'scheduled', 'active') THEN
    RAISE EXCEPTION 'event guest list cannot be changed in this phase' USING ERRCODE = '55000';
  END IF;
  SELECT * INTO v_participation FROM eogp.event_participations
  WHERE organization_id = p_org AND event_id = p_event AND id = p_participation FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'participation not found' USING ERRCODE = 'P0002'; END IF;
  IF p_expected_revision IS DISTINCT FROM v_participation.revision THEN
    RAISE EXCEPTION 'participation revision conflict' USING ERRCODE = '40001';
  END IF;
  IF p_status IS NULL OR p_status NOT IN ('eligible', 'waitlisted', 'ineligible', 'withdrawn') THEN
    RAISE EXCEPTION 'invalid participation status' USING ERRCODE = '22023';
  END IF;
  IF v_participation.status = 'cancelled' THEN
    RAISE EXCEPTION 'cancelled participation cannot be reopened by this command' USING ERRCODE = '55000';
  END IF;
  IF v_participation.status = p_status THEN
    RETURN jsonb_build_object('participationId', p_participation, 'status', p_status, 'revision', v_participation.revision);
  END IF;

  IF p_status IN ('eligible', 'waitlisted') THEN
    SELECT status INTO v_person_status FROM eogp.persons
    WHERE organization_id = p_org AND id = v_participation.person_id FOR SHARE;
    IF v_person_status <> 'active' THEN
      RAISE EXCEPTION 'person is no longer active' USING ERRCODE = '55000';
    END IF;
  END IF;

  IF p_status <> 'eligible' AND EXISTS (
    SELECT 1 FROM eogp.invitations
    WHERE organization_id = p_org AND event_id = p_event AND participation_id = p_participation
      AND status IN ('active', 'draft')
  ) THEN
    RAISE EXCEPTION 'revoke the outstanding invitation before changing eligibility' USING ERRCODE = '55000';
  END IF;

  UPDATE eogp.event_participations SET status = p_status, revision = revision + 1, updated_at = clock_timestamp()
  WHERE organization_id = p_org AND event_id = p_event AND id = p_participation;

  INSERT INTO eogp.participation_status_history (
    organization_id, event_id, participation_id, previous_status, new_status, actor_membership_id, reason_code
  ) VALUES (p_org, p_event, p_participation, v_participation.status, p_status, p_actor, 'staff_status_change');

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.participation.status_updated', 'event_participation', p_participation,
    jsonb_build_object('eventId', p_event, 'previousStatus', v_participation.status, 'status', p_status)
  );
  RETURN jsonb_build_object('participationId', p_participation, 'status', p_status, 'revision', v_participation.revision + 1);
END;
$function$;

CREATE FUNCTION eogp.assert_guest_participation_management(p_org uuid, p_event uuid, p_actor uuid)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
  SELECT eogp.assert_event_command_permission(p_org, p_event, p_actor, 'guest.manage')
$function$;

REVOKE ALL ON FUNCTION eogp.update_guest_participation_status(uuid,uuid,uuid,uuid,integer,text),
  eogp.assert_guest_participation_management(uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.update_guest_participation_status(uuid,uuid,uuid,uuid,integer,text),
  eogp.assert_guest_participation_management(uuid,uuid,uuid) TO eventor_runtime;
