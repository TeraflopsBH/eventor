-- Staff-authorized RSVP history projection. Restricted notes are intentionally omitted.
CREATE FUNCTION eogp.get_participation_rsvp_history(
  p_organization_id uuid,
  p_participation_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_event_id uuid;
  v_responses jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;

  SELECT event_id INTO v_event_id
    FROM eogp.event_participations
   WHERE organization_id = p_organization_id
     AND id = p_participation_id
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'event participation not found' USING ERRCODE = 'P0002';
  END IF;

  PERFORM eogp.assert_event_command_permission(
    p_organization_id, v_event_id, p_actor_membership_id, 'guest.read'
  );

  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'id', response.id,
        'sequenceNumber', response.sequence_number,
        'response', response.response,
        'sourceChannel', response.source_channel,
        'respondentKind', response.respondent_kind,
        'receivedAt', response.received_at,
        'recordedAt', response.recorded_at,
        'actorMembershipId', response.actor_membership_id,
        'invitationId', response.invitation_id,
        'correctionOfResponseId', response.correction_of_response_id,
        'correctionReason', response.correction_reason
      ) ORDER BY response.sequence_number
    ),
    '[]'::jsonb
  ) INTO v_responses
    FROM eogp.rsvp_responses AS response
   WHERE response.organization_id = p_organization_id
     AND response.event_id = v_event_id
     AND response.participation_id = p_participation_id;

  RETURN jsonb_build_object(
    'eventId', v_event_id,
    'participationId', p_participation_id,
    'responses', v_responses
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.get_participation_rsvp_history(uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.get_participation_rsvp_history(uuid,uuid,uuid) TO eventor_runtime;
