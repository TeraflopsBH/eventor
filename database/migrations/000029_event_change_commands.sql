-- Authoritative organizer-side event change commands.
-- These functions are the only supported write boundary for the corresponding
-- API operations. They verify tenant context, active membership, scoped
-- permission, aggregate revision and lifecycle transitions inside the
-- transaction that records the audit/outbox effects.

CREATE FUNCTION eogp.assert_event_command_permission(
  p_organization_id uuid,
  p_event_id uuid,
  p_actor_membership_id uuid,
  p_permission_code text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_membership_status text;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;

  SELECT status INTO v_membership_status
    FROM eogp.organization_memberships
   WHERE organization_id = p_organization_id
     AND id = p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_membership_status <> 'active' THEN
    RAISE EXCEPTION 'active event-owner membership is required' USING ERRCODE = '42501';
  END IF;

  PERFORM 1
    FROM eogp.user_role_grants AS user_grant
    JOIN eogp.role_permissions AS role_permission
      ON role_permission.organization_id = user_grant.organization_id
     AND role_permission.role_id = user_grant.role_id
   WHERE user_grant.organization_id = p_organization_id
     AND user_grant.membership_id = p_actor_membership_id
     AND user_grant.revoked_at IS NULL
     AND (user_grant.expires_at IS NULL OR user_grant.expires_at > clock_timestamp())
     AND role_permission.permission_code = p_permission_code
     AND (
       user_grant.scope_kind = 'organization'
       OR (user_grant.scope_kind = 'event' AND user_grant.scope_event_id = p_event_id)
     )
   FOR SHARE OF user_grant, role_permission;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'required event permission is not granted for this event'
      USING ERRCODE = '42501';
  END IF;
END;
$function$;


CREATE FUNCTION eogp.submit_event_change_request(
  p_organization_id uuid,
  p_event_id uuid,
  p_actor_membership_id uuid,
  p_change_kind text,
  p_expected_event_revision integer,
  p_reason_code text,
  p_reason_internal_ciphertext bytea,
  p_public_message text,
  p_replacement_schedule jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_event_status text;
  v_current_revision integer;
  v_permission_code text;
  v_replacement_schedule_id uuid;
  v_revision_number integer;
  v_start timestamptz;
  v_end timestamptz;
  v_timezone text;
  v_venue_summary jsonb;
  v_snapshot jsonb;
  v_material_change boolean;
  v_reconfirmation_policy text;
  v_request_id uuid := gen_random_uuid();
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;

  IF p_change_kind IS NULL OR p_change_kind NOT IN ('cancel','postpone','reschedule')
     OR p_expected_event_revision IS NULL OR p_expected_event_revision < 1
     OR p_reason_code IS NULL OR length(btrim(p_reason_code)) < 2
     OR length(p_reason_code) > 100 THEN
    RAISE EXCEPTION 'invalid event change request' USING ERRCODE = '22023';
  END IF;

  IF p_change_kind = 'cancel' THEN
    v_permission_code := 'event.cancellation.initiate';
  ELSE
    v_permission_code := 'event.postponement.manage';
  END IF;
  PERFORM eogp.assert_event_command_permission(
    p_organization_id, p_event_id, p_actor_membership_id, v_permission_code
  );

  SELECT status, current_revision
    INTO v_event_status, v_current_revision
    FROM eogp.events
   WHERE organization_id = p_organization_id
     AND id = p_event_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_current_revision <> p_expected_event_revision THEN
    RAISE EXCEPTION 'event revision is stale'
      USING ERRCODE = '40001',
            DETAIL = format('expected revision %s, current revision is %s',
                            p_expected_event_revision, v_current_revision);
  END IF;
  IF v_event_status IN ('completed','cancelled','archived') THEN
    RAISE EXCEPTION 'event cannot accept a change request in its current state'
      USING ERRCODE = '55000';
  END IF;

  IF EXISTS (
    SELECT 1 FROM eogp.event_change_requests
     WHERE organization_id = p_organization_id
       AND event_id = p_event_id
       AND status IN ('submitted','under_review','approved')
  ) THEN
    RAISE EXCEPTION 'another event change request is already awaiting resolution'
      USING ERRCODE = '55000';
  END IF;

  IF p_change_kind = 'reschedule' THEN
    IF jsonb_typeof(p_replacement_schedule) IS DISTINCT FROM 'object'
       OR nullif(p_replacement_schedule ->> 'startsAt','') IS NULL
       OR nullif(p_replacement_schedule ->> 'endsAt','') IS NULL
       OR nullif(btrim(p_replacement_schedule ->> 'timezone'),'') IS NULL THEN
      RAISE EXCEPTION 'reschedule requires startsAt, endsAt and timezone'
        USING ERRCODE = '22023';
    END IF;

    BEGIN
      v_start := (p_replacement_schedule ->> 'startsAt')::timestamptz;
      v_end := (p_replacement_schedule ->> 'endsAt')::timestamptz;
      v_timezone := p_replacement_schedule ->> 'timezone';
      v_material_change := coalesce((p_replacement_schedule ->> 'materialChange')::boolean,true);
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'replacement schedule contains an invalid date, time or boolean'
        USING ERRCODE = '22023';
    END;
    IF v_end <= v_start THEN
      RAISE EXCEPTION 'replacement schedule end must be after its start'
        USING ERRCODE = '22023';
    END IF;

    v_venue_summary := coalesce(p_replacement_schedule -> 'venueSummary','{}'::jsonb);
    IF jsonb_typeof(v_venue_summary) IS DISTINCT FROM 'object' THEN
      RAISE EXCEPTION 'replacement venueSummary must be a JSON object'
        USING ERRCODE = '22023';
    END IF;
    v_snapshot := p_replacement_schedule;
    v_reconfirmation_policy := coalesce(
      p_replacement_schedule ->> 'reconfirmationPolicy','accepted_tentative'
    );
    IF v_reconfirmation_policy NOT IN ('none','accepted_tentative','all_active_invitees','all_invited') THEN
      RAISE EXCEPTION 'replacement schedule reconfirmationPolicy is invalid'
        USING ERRCODE = '22023';
    END IF;

    SELECT coalesce(max(revision_number),0) + 1
      INTO v_revision_number
      FROM eogp.event_schedule_revisions
     WHERE organization_id = p_organization_id
       AND event_id = p_event_id;

    INSERT INTO eogp.event_schedule_revisions (
      organization_id, event_id, revision_number, schedule_kind,
      starts_at, ends_at, timezone_name, venue_summary, schedule_snapshot,
      material_change, reconfirmation_policy, created_by_membership_id
    ) VALUES (
      p_organization_id, p_event_id, v_revision_number, 'reschedule',
      v_start, v_end, v_timezone, v_venue_summary, v_snapshot,
      v_material_change, v_reconfirmation_policy, p_actor_membership_id
    )
    RETURNING id INTO v_replacement_schedule_id;
  ELSIF p_replacement_schedule IS NOT NULL THEN
    RAISE EXCEPTION 'replacementSchedule is allowed only for a reschedule request'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO eogp.event_change_requests (
    id, organization_id, event_id, change_kind, expected_event_revision,
    reason_code, reason_internal_ciphertext, public_message,
    replacement_schedule_revision_id, status,
    initiated_by_organization_id, initiated_by_membership_id
  ) VALUES (
    v_request_id, p_organization_id, p_event_id, p_change_kind,
    p_expected_event_revision, p_reason_code, p_reason_internal_ciphertext,
    p_public_message, v_replacement_schedule_id, 'submitted',
    p_organization_id, p_actor_membership_id
  );

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, reason_code, safe_metadata
  ) VALUES (
    p_organization_id, p_organization_id, p_actor_membership_id, 'membership',
    'event.change_request.submitted', 'event', p_event_id, p_reason_code,
    jsonb_build_object('changeRequestId',v_request_id,'changeKind',p_change_kind,
                       'expectedEventRevision',p_expected_event_revision)
  );

  RETURN jsonb_build_object(
    'changeRequestId',v_request_id,
    'eventId',p_event_id,
    'changeKind',p_change_kind,
    'status','submitted',
    'expectedEventRevision',p_expected_event_revision,
    'replacementScheduleRevisionId',v_replacement_schedule_id
  );
END;
$function$;


CREATE FUNCTION eogp.decide_event_change_request(
  p_organization_id uuid,
  p_change_request_id uuid,
  p_actor_membership_id uuid,
  p_decision text,
  p_reason text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_request eogp.event_change_requests%ROWTYPE;
  v_event_revision integer;
  v_permission_code text;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;
  IF p_decision IS NULL OR p_decision NOT IN ('approved','rejected')
     OR p_reason IS NULL OR length(btrim(p_reason)) < 3
     OR length(p_reason) > 2000 THEN
    RAISE EXCEPTION 'invalid event change decision' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_request
    FROM eogp.event_change_requests
   WHERE organization_id = p_organization_id
     AND id = p_change_request_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'event change request not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_request.change_kind = 'cancel' THEN
    v_permission_code := 'event.cancellation.approve';
  ELSE
    v_permission_code := 'event.postponement.manage';
  END IF;
  PERFORM eogp.assert_event_command_permission(
    p_organization_id, v_request.event_id, p_actor_membership_id, v_permission_code
  );

  SELECT current_revision INTO v_event_revision
    FROM eogp.events
   WHERE organization_id = p_organization_id
     AND id = v_request.event_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_event_revision <> v_request.expected_event_revision THEN
    RAISE EXCEPTION 'event changed after the request was submitted'
      USING ERRCODE = '40001';
  END IF;
  IF v_request.status NOT IN ('submitted','under_review') THEN
    RAISE EXCEPTION 'event change request is not awaiting a decision'
      USING ERRCODE = '55000';
  END IF;

  INSERT INTO eogp.event_change_approval_decisions (
    organization_id, event_id, change_request_id, decision,
    actor_organization_id, actor_membership_id, reason
  ) VALUES (
    p_organization_id, v_request.event_id, v_request.id, p_decision,
    p_organization_id, p_actor_membership_id, p_reason
  );

  UPDATE eogp.event_change_requests
     SET status = p_decision,
         resolved_at = clock_timestamp()
   WHERE organization_id = p_organization_id
     AND id = p_change_request_id;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, reason_code, safe_metadata
  ) VALUES (
    p_organization_id, p_organization_id, p_actor_membership_id, 'membership',
    'event.change_request.' || p_decision, 'event', v_request.event_id,
    'change_request_' || p_decision,
    jsonb_build_object('changeRequestId',v_request.id,'decision',p_decision)
  );

  RETURN jsonb_build_object(
    'changeRequestId',v_request.id,
    'eventId',v_request.event_id,
    'changeKind',v_request.change_kind,
    'status',p_decision,
    'decidedAt',clock_timestamp()
  );
END;
$function$;


CREATE FUNCTION eogp.execute_event_change_request(
  p_organization_id uuid,
  p_change_request_id uuid,
  p_actor_membership_id uuid,
  p_expected_event_revision integer,
  p_campaign_audience text DEFAULT NULL,
  p_send_notifications boolean DEFAULT true,
  p_custom_participation_ids uuid[] DEFAULT ARRAY[]::uuid[]
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_request eogp.event_change_requests%ROWTYPE;
  v_event_status text;
  v_previous_status text;
  v_event_revision integer;
  v_permission_code text;
  v_decision_kind text;
  v_original_schedule_id uuid;
  v_decision_id uuid := gen_random_uuid();
  v_audience text;
  v_future_session_count integer := 0;
  v_custom_count integer := 0;
  v_custom_ids_json jsonb := '[]'::jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;
  IF p_expected_event_revision IS NULL OR p_expected_event_revision < 1
     OR (p_custom_participation_ids IS NOT NULL
         AND (array_position(p_custom_participation_ids,NULL::uuid) IS NOT NULL
              OR (cardinality(p_custom_participation_ids) > 0
                  AND cardinality(p_custom_participation_ids) <>
                      (SELECT count(DISTINCT requested.participation_id) FROM unnest(p_custom_participation_ids) AS requested(participation_id))))) THEN
    RAISE EXCEPTION 'invalid event execution parameters' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_request
    FROM eogp.event_change_requests
   WHERE organization_id = p_organization_id
     AND id = p_change_request_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'event change request not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_request.change_kind = 'cancel' THEN
    v_permission_code := 'event.cancellation.execute';
  ELSE
    v_permission_code := 'event.postponement.manage';
  END IF;
  PERFORM eogp.assert_event_command_permission(
    p_organization_id, v_request.event_id, p_actor_membership_id, v_permission_code
  );

  SELECT status, current_revision
    INTO v_event_status, v_event_revision
    FROM eogp.events
   WHERE organization_id = p_organization_id
     AND id = v_request.event_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_request.status <> 'approved' THEN
    RAISE EXCEPTION 'event change request must be approved before execution'
      USING ERRCODE = '55000';
  END IF;
  IF v_event_revision <> p_expected_event_revision
     OR v_request.expected_event_revision <> p_expected_event_revision THEN
    RAISE EXCEPTION 'event revision is stale; refresh the change preview'
      USING ERRCODE = '40001';
  END IF;
  IF v_event_status IN ('completed','cancelled','archived') THEN
    RAISE EXCEPTION 'event cannot be changed in its current state'
      USING ERRCODE = '55000';
  END IF;

  v_audience := coalesce(
    p_campaign_audience,
    CASE WHEN v_request.change_kind = 'cancel'
         THEN 'all_active_invitees'
         ELSE 'accepted_tentative' END
  );
  IF v_audience NOT IN ('accepted_tentative','all_active_invitees',
                        'all_previously_invited','custom') THEN
    RAISE EXCEPTION 'invalid notification campaign audience'
      USING ERRCODE = '22023';
  END IF;

  IF v_audience = 'custom' THEN
    IF coalesce(cardinality(p_custom_participation_ids),0) = 0 THEN
      RAISE EXCEPTION 'custom audience requires one or more participation IDs'
        USING ERRCODE = '22023';
    END IF;
    SELECT count(DISTINCT participation_id)
      INTO v_custom_count
      FROM eogp.event_participations
     WHERE organization_id = p_organization_id
       AND event_id = v_request.event_id
       AND id = ANY(p_custom_participation_ids);
    IF v_custom_count <> cardinality(p_custom_participation_ids) THEN
      RAISE EXCEPTION 'every custom audience participant must belong to this event'
        USING ERRCODE = '22023';
    END IF;
    v_custom_ids_json := to_jsonb(p_custom_participation_ids);
  ELSIF coalesce(cardinality(p_custom_participation_ids),0) > 0 THEN
    RAISE EXCEPTION 'custom participation IDs require the custom audience kind'
      USING ERRCODE = '22023';
  END IF;

  v_decision_kind := CASE v_request.change_kind
    WHEN 'cancel' THEN 'cancelled'
    WHEN 'postpone' THEN 'postponed'
    WHEN 'reschedule' THEN 'rescheduled'
  END;

  SELECT id INTO v_original_schedule_id
    FROM eogp.event_schedule_revisions
   WHERE organization_id = p_organization_id
     AND event_id = v_request.event_id
     AND (v_request.replacement_schedule_revision_id IS NULL
          OR id <> v_request.replacement_schedule_revision_id)
   ORDER BY revision_number DESC
   LIMIT 1;

  UPDATE eogp.event_change_requests
     SET status = 'executed',
         resolved_at = coalesce(resolved_at,clock_timestamp())
   WHERE organization_id = p_organization_id
     AND id = v_request.id;

  v_previous_status := v_event_status;
  UPDATE eogp.events
     SET status = CASE v_request.change_kind
           WHEN 'cancel' THEN 'cancelled'
           WHEN 'postpone' THEN 'postponed'
           WHEN 'reschedule' THEN CASE WHEN v_event_status = 'active' THEN 'active' ELSE 'scheduled' END
         END,
         current_revision = current_revision + 1,
         updated_at = clock_timestamp()
   WHERE organization_id = p_organization_id
     AND id = v_request.event_id;

  IF v_request.change_kind = 'cancel' THEN
    UPDATE eogp.event_sessions
       SET status = 'cancelled'
     WHERE organization_id = p_organization_id
       AND event_id = v_request.event_id
       AND status IN ('planned','scheduled','active')
       AND (starts_at IS NULL OR starts_at > clock_timestamp());
    GET DIAGNOSTICS v_future_session_count = ROW_COUNT;
  END IF;

  INSERT INTO eogp.event_decisions (
    id, organization_id, event_id, source_change_request_id, decision_kind,
    original_schedule_revision_id, replacement_schedule_revision_id, reason_code,
    reason_internal_ciphertext, public_message,
    executed_by_organization_id, executed_by_membership_id
  ) VALUES (
    v_decision_id, p_organization_id, v_request.event_id, v_request.id, v_decision_kind,
    v_original_schedule_id, v_request.replacement_schedule_revision_id, v_request.reason_code,
    v_request.reason_internal_ciphertext, v_request.public_message,
    p_organization_id, p_actor_membership_id
  );

  INSERT INTO eogp.event_decision_sessions (
    organization_id, event_id, decision_id, session_id, outcome
  )
  SELECT p_organization_id, v_request.event_id, v_decision_id, session.id,
         CASE
           WHEN v_request.change_kind = 'cancel'
                AND (session.status = 'completed'
                     OR (session.starts_at IS NOT NULL AND session.starts_at <= clock_timestamp()))
             THEN 'unaffected'
           WHEN v_request.change_kind = 'cancel' THEN 'cancelled'
           WHEN v_request.change_kind = 'postpone' THEN 'postponed'
           ELSE 'rescheduled'
         END
    FROM eogp.event_sessions AS session
   WHERE session.organization_id = p_organization_id
     AND session.event_id = v_request.event_id;

  INSERT INTO eogp.event_status_history (
    organization_id, event_id, previous_status, new_status, decision_id,
    actor_membership_id, reason_code
  )
  SELECT p_organization_id, v_request.event_id, v_previous_status, event.status,
         v_decision_id, p_actor_membership_id, v_request.reason_code
    FROM eogp.events AS event
   WHERE event.organization_id = p_organization_id
     AND event.id = v_request.event_id;

  IF p_send_notifications THEN
    INSERT INTO eogp.outbox_events (
      organization_id, topic, aggregate_type, aggregate_id, payload, idempotency_key
    ) VALUES (
      p_organization_id, 'event.change.notification_requested', 'event', v_request.event_id,
      jsonb_build_object(
        'eventDecisionId',v_decision_id,
        'changeRequestId',v_request.id,
        'decisionKind',v_decision_kind,
        'audienceKind',v_audience,
        'customParticipationIds',v_custom_ids_json
      ),
      'event-change:' || v_request.id::text || ':notification'
    )
    ON CONFLICT (organization_id,idempotency_key) DO NOTHING;
  END IF;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, reason_code, safe_metadata
  ) VALUES (
    p_organization_id, p_organization_id, p_actor_membership_id, 'membership',
    'event.change_request.executed', 'event', v_request.event_id, v_request.reason_code,
    jsonb_build_object(
      'changeRequestId',v_request.id,
      'eventDecisionId',v_decision_id,
      'decisionKind',v_decision_kind,
      'notificationRequested',p_send_notifications,
      'audienceKind',CASE WHEN p_send_notifications THEN v_audience ELSE NULL END,
      'futureSessionsCancelled',v_future_session_count
    )
  );

  RETURN jsonb_build_object(
    'eventId',v_request.event_id,
    'changeRequestId',v_request.id,
    'eventDecisionId',v_decision_id,
    'decisionKind',v_decision_kind,
    'status',CASE v_request.change_kind
      WHEN 'cancel' THEN 'cancelled'
      WHEN 'postpone' THEN 'postponed'
      WHEN 'reschedule' THEN CASE WHEN v_previous_status = 'active' THEN 'active' ELSE 'scheduled' END
    END,
    'currentRevision',p_expected_event_revision + 1,
    'notificationRequested',p_send_notifications,
    'notificationAudience',CASE WHEN p_send_notifications THEN v_audience ELSE NULL END,
    'notificationState',CASE WHEN p_send_notifications THEN 'queued_for_dispatch' ELSE 'not_requested' END
  );
END;
$function$;


REVOKE ALL ON FUNCTION eogp.assert_event_command_permission(uuid,uuid,uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.submit_event_change_request(uuid,uuid,uuid,text,integer,text,bytea,text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.decide_event_change_request(uuid,uuid,uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.execute_event_change_request(uuid,uuid,uuid,integer,text,boolean,uuid[]) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION eogp.submit_event_change_request(uuid,uuid,uuid,text,integer,text,bytea,text,jsonb),
  eogp.decide_event_change_request(uuid,uuid,uuid,text,text),
  eogp.execute_event_change_request(uuid,uuid,uuid,integer,text,boolean,uuid[])
  TO eventor_runtime;
