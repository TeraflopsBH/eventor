-- Staff-recorded RSVP command: append-only, permission checked and tenant scoped.
CREATE FUNCTION eogp.record_staff_rsvp_response(
  p_organization_id uuid,
  p_event_id uuid,
  p_participation_id uuid,
  p_actor_membership_id uuid,
  p_response text,
  p_source_channel text,
  p_respondent_kind text,
  p_received_at timestamptz,
  p_invitation_id uuid,
  p_notes_restricted_ciphertext bytea
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_participation eogp.event_participations%ROWTYPE;
  v_policy eogp.rsvp_policy_revisions%ROWTYPE;
  v_schedule_id uuid;
  v_sequence integer;
  v_response_id uuid;
  v_recorded_at timestamptz := clock_timestamp();
BEGIN
  PERFORM eogp.assert_event_command_permission(
    p_organization_id, p_event_id, p_actor_membership_id, 'rsvp.record'
  );

  IF p_response NOT IN ('accepted','declined','tentative')
     OR p_source_channel NOT IN ('phone','in_person','email','written','representative','staff_entry','other')
     OR p_respondent_kind NOT IN ('guest','representative','staff')
     OR p_received_at IS NULL
     OR p_received_at > v_recorded_at THEN
    RAISE EXCEPTION 'invalid staff RSVP response' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_participation
    FROM eogp.event_participations
   WHERE organization_id = p_organization_id
     AND event_id = p_event_id
     AND id = p_participation_id
   FOR UPDATE;
  IF NOT FOUND OR v_participation.status NOT IN ('eligible','waitlisted') THEN
    RAISE EXCEPTION 'event participation not found or not eligible' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_policy
    FROM eogp.rsvp_policy_revisions
   WHERE organization_id = p_organization_id
     AND event_id = p_event_id
     AND state = 'published'
   ORDER BY published_at DESC, revision_number DESC
   LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'published RSVP policy is required' USING ERRCODE = '55000';
  END IF;
  IF NOT (v_policy.allowed_responses ? p_response) THEN
    RAISE EXCEPTION 'response is not allowed by the published RSVP policy' USING ERRCODE = '22023';
  END IF;

  SELECT id INTO v_schedule_id
    FROM eogp.event_schedule_revisions
   WHERE organization_id = p_organization_id
     AND event_id = p_event_id
   ORDER BY revision_number DESC
   LIMIT 1;
  IF v_schedule_id IS NULL THEN
    RAISE EXCEPTION 'event schedule is unavailable' USING ERRCODE = '55000';
  END IF;

  IF p_invitation_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM eogp.invitations
     WHERE organization_id = p_organization_id
       AND event_id = p_event_id
       AND participation_id = p_participation_id
       AND id = p_invitation_id
  ) THEN
    RAISE EXCEPTION 'invitation does not belong to this participation' USING ERRCODE = '23503';
  END IF;

  SELECT COALESCE(max(sequence_number), 0) + 1 INTO v_sequence
    FROM eogp.rsvp_responses
   WHERE organization_id = p_organization_id
     AND event_id = p_event_id
     AND participation_id = p_participation_id;

  INSERT INTO eogp.rsvp_responses (
    organization_id, event_id, participation_id, invitation_id,
    invitation_revision_id, schedule_revision_id, sequence_number,
    response, source_channel, respondent_kind, received_at, recorded_at,
    actor_membership_id, notes_restricted_ciphertext
  ) VALUES (
    p_organization_id, p_event_id, p_participation_id, p_invitation_id,
    (SELECT id FROM eogp.invitation_revisions
      WHERE organization_id = p_organization_id
        AND event_id = p_event_id
        AND invitation_id = p_invitation_id
      ORDER BY revision_number DESC LIMIT 1),
    v_schedule_id, v_sequence, p_response, p_source_channel,
    p_respondent_kind, p_received_at, v_recorded_at,
    p_actor_membership_id, p_notes_restricted_ciphertext
  ) RETURNING id INTO v_response_id;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_organization_id, p_organization_id, p_actor_membership_id, 'membership',
    'event.rsvp.recorded', 'event_participation', p_participation_id,
    jsonb_build_object(
      'eventId', p_event_id,
      'responseId', v_response_id,
      'response', p_response,
      'sourceChannel', p_source_channel,
      'respondentKind', p_respondent_kind,
      'sequenceNumber', v_sequence
    )
  );

  RETURN jsonb_build_object(
    'id', v_response_id,
    'eventId', p_event_id,
    'participationId', p_participation_id,
    'response', p_response,
    'sourceChannel', p_source_channel,
    'respondentKind', p_respondent_kind,
    'receivedAt', p_received_at,
    'recordedAt', v_recorded_at,
    'sequenceNumber', v_sequence
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.record_staff_rsvp_response(uuid,uuid,uuid,uuid,text,text,text,timestamptz,uuid,bytea) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.record_staff_rsvp_response(uuid,uuid,uuid,uuid,text,text,text,timestamptz,uuid,bytea) TO eventor_runtime;
