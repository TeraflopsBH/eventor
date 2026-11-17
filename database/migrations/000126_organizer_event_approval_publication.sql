ALTER TABLE eogp.events
  DROP CONSTRAINT events_status_check,
  ADD CONSTRAINT events_status_check CHECK (status IN (
    'draft', 'planned', 'ready_for_approval', 'approved', 'scheduled',
    'active', 'completed', 'cancelled', 'postponed', 'archived'
  ));

CREATE FUNCTION eogp.guard_event_details_under_review() RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  IF OLD.status IN ('ready_for_approval', 'approved')
     AND (OLD.title, OLD.description_internal, OLD.timezone_name)
         IS DISTINCT FROM (NEW.title, NEW.description_internal, NEW.timezone_name) THEN
    RAISE EXCEPTION 'return event to planning before editing details' USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER events_guard_details_under_review
BEFORE UPDATE OF title, description_internal, timezone_name ON eogp.events
FOR EACH ROW EXECUTE FUNCTION eogp.guard_event_details_under_review();

CREATE FUNCTION eogp.transition_organizer_event(
  p_organization_id uuid, p_event_id uuid, p_actor_membership_id uuid,
  p_expected_details_revision integer, p_expected_schedule_revision integer,
  p_action text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_event eogp.events%ROWTYPE;
  v_status text;
  v_schedule_revision_id uuid;
BEGIN
  PERFORM eogp.assert_event_command_permission(
    p_organization_id, p_event_id, p_actor_membership_id, 'event.manage'
  );

  SELECT * INTO v_event FROM eogp.events
  WHERE organization_id = p_organization_id AND id = p_event_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002';
  END IF;
  IF p_expected_details_revision IS DISTINCT FROM v_event.details_revision
     OR p_expected_schedule_revision IS DISTINCT FROM v_event.current_revision THEN
    RAISE EXCEPTION 'event revision conflict' USING ERRCODE = '40001';
  END IF;

  v_status := CASE
    WHEN p_action = 'plan' AND v_event.status = 'draft' THEN 'planned'
    WHEN p_action = 'submit' AND v_event.status = 'planned' THEN 'ready_for_approval'
    WHEN p_action = 'approve' AND v_event.status = 'ready_for_approval' THEN 'approved'
    WHEN p_action = 'return_to_planning' AND v_event.status IN ('ready_for_approval', 'approved') THEN 'planned'
    WHEN p_action = 'publish' AND v_event.status = 'approved' THEN 'scheduled'
  END;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'event transition is not available in its current state' USING ERRCODE = '55000';
  END IF;

  IF p_action IN ('submit', 'approve', 'publish') THEN
    IF EXISTS (
      SELECT 1 FROM eogp.event_change_requests
      WHERE organization_id = p_organization_id AND event_id = p_event_id
        AND status IN ('submitted', 'under_review', 'approved')
    ) THEN
      RAISE EXCEPTION 'resolve the pending event change before advancing the event' USING ERRCODE = '55000';
    END IF;
    SELECT id INTO v_schedule_revision_id FROM eogp.event_schedule_revisions
    WHERE organization_id = p_organization_id AND event_id = p_event_id
      AND revision_number = v_event.current_revision
      AND isfinite(starts_at) AND isfinite(ends_at);
    IF NOT FOUND THEN
      RAISE EXCEPTION 'event needs a valid current schedule' USING ERRCODE = '55000';
    END IF;
  END IF;

  UPDATE eogp.events
  SET status = v_status, details_revision = details_revision + 1, updated_at = clock_timestamp()
  WHERE organization_id = p_organization_id AND id = p_event_id;

  INSERT INTO eogp.event_status_history (
    organization_id, event_id, previous_status, new_status, actor_membership_id, reason_code
  ) VALUES (
    p_organization_id, p_event_id, v_event.status, v_status, p_actor_membership_id, p_action
  );

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, reason_code, safe_metadata
  ) VALUES (
    p_organization_id, p_organization_id, p_actor_membership_id, 'membership',
    'event.lifecycle.transitioned', 'event', p_event_id, p_action,
    jsonb_build_object(
      'previousStatus', v_event.status, 'status', v_status,
      'detailsRevision', v_event.details_revision + 1,
      'scheduleRevisionId', v_schedule_revision_id
    )
  );

  RETURN jsonb_build_object(
    'eventId', p_event_id, 'status', v_status, 'detailsRevision', v_event.details_revision + 1,
    'currentRevision', v_event.current_revision
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.transition_organizer_event(uuid,uuid,uuid,integer,integer,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.transition_organizer_event(uuid,uuid,uuid,integer,integer,text) TO eventor_runtime;
