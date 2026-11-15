-- Keep guest bearer capabilities bound to the effective event schedule and live event state.
-- Prevent idempotency replay from bypassing capability revocation or supersession.

CREATE OR REPLACE FUNCTION eogp.resolve_guest_invitation(
  p_token_sha256 text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_organization_id uuid;
  v_link_id uuid;
  v_result jsonb;
BEGIN
  IF p_token_sha256 IS NULL OR p_token_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid guest invitation capability' USING ERRCODE = '22023';
  END IF;

  SELECT lookup.organization_id, lookup.invitation_link_id
    INTO v_organization_id, v_link_id
    FROM eogp.guest_invitation_capability_lookup lookup
   WHERE lookup.token_sha256 = p_token_sha256;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'guest invitation not found' USING ERRCODE = 'P0002';
  END IF;

  PERFORM set_config('app.organization_id', v_organization_id::text, true);

  SELECT jsonb_build_object(
    'organizationId', invitation.organization_id,
    'invitationId', invitation.id,
    'invitationRevisionId', revision.id,
    'eventId', event.id,
    'eventTitle', event.title,
    'eventStatus', event.status,
    'startsAt', schedule.starts_at,
    'endsAt', schedule.ends_at,
    'timezone', schedule.timezone_name,
    'locale', revision.locale,
    'presentationSnapshotCiphertext', replace(encode(revision.presentation_snapshot_ciphertext, 'base64'), E'\\n', ''),
    'allowedResponses', policy.allowed_responses,
    'responseDeadline', policy.response_deadline,
    'responseChangeAllowed', policy.response_change_allowed,
    'currentResponse', (
      SELECT response.response
        FROM eogp.rsvp_responses response
       WHERE response.organization_id = invitation.organization_id
         AND response.event_id = invitation.event_id
         AND response.participation_id = invitation.participation_id
       ORDER BY response.sequence_number DESC
       LIMIT 1
    )
  )
    INTO v_result
    FROM eogp.invitation_links link
    JOIN eogp.invitations invitation
      ON invitation.organization_id = link.organization_id
     AND invitation.event_id = link.event_id
     AND invitation.id = link.invitation_id
    JOIN eogp.invitation_revisions revision
      ON revision.organization_id = link.organization_id
     AND revision.event_id = link.event_id
     AND revision.invitation_id = link.invitation_id
     AND revision.id = link.invitation_revision_id
    JOIN eogp.events event
      ON event.organization_id = invitation.organization_id
     AND event.id = invitation.event_id
    JOIN eogp.event_schedule_revisions schedule
      ON schedule.organization_id = revision.organization_id
     AND schedule.event_id = revision.event_id
     AND schedule.id = revision.schedule_revision_id
    JOIN eogp.rsvp_policy_revisions policy
      ON policy.organization_id = revision.organization_id
     AND policy.event_id = revision.event_id
     AND policy.id = revision.rsvp_policy_revision_id
   WHERE link.organization_id = v_organization_id
     AND link.id = v_link_id
     AND link.token_sha256 = p_token_sha256
     AND link.revoked_at IS NULL
     AND link.expires_at > clock_timestamp()
     AND invitation.status = 'active'
     AND invitation.current_revision_number = revision.revision_number
     AND revision.issued_at IS NOT NULL
     AND policy.state = 'published'
     AND revision.schedule_revision_id = eogp.current_event_schedule_revision_id(v_organization_id,event.id)
     AND event.status NOT IN ('completed', 'cancelled', 'archived');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'guest invitation is expired, revoked or unavailable'
      USING ERRCODE = '55000';
  END IF;

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.get_guest_invitation_rsvp_history(
  p_token_sha256 text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_organization_id uuid;
  v_link_id uuid;
  v_result jsonb;
BEGIN
  IF p_token_sha256 IS NULL OR p_token_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid guest invitation capability' USING ERRCODE = '22023';
  END IF;

  SELECT lookup.organization_id, lookup.invitation_link_id
    INTO v_organization_id, v_link_id
    FROM eogp.guest_invitation_capability_lookup lookup
   WHERE lookup.token_sha256 = p_token_sha256;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'guest invitation not found' USING ERRCODE = 'P0002';
  END IF;

  PERFORM set_config('app.organization_id', v_organization_id::text, true);

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'responseId', response.id,
    'response', response.response,
    'receivedAt', response.received_at,
    'sequenceNumber', response.sequence_number
  ) ORDER BY response.sequence_number DESC), '[]'::jsonb)
    INTO v_result
    FROM eogp.invitation_links link
    JOIN eogp.invitations invitation
      ON invitation.organization_id = link.organization_id
     AND invitation.event_id = link.event_id
     AND invitation.id = link.invitation_id
    JOIN eogp.invitation_revisions revision
      ON revision.organization_id = link.organization_id
     AND revision.event_id = link.event_id
     AND revision.invitation_id = link.invitation_id
     AND revision.id = link.invitation_revision_id
    JOIN eogp.events event
      ON event.organization_id = invitation.organization_id
     AND event.id = invitation.event_id
    JOIN eogp.rsvp_policy_revisions policy
      ON policy.organization_id = revision.organization_id
     AND policy.event_id = revision.event_id
     AND policy.id = revision.rsvp_policy_revision_id
    JOIN eogp.rsvp_responses response
      ON response.organization_id = invitation.organization_id
     AND response.event_id = invitation.event_id
     AND response.participation_id = invitation.participation_id
   WHERE link.organization_id = v_organization_id
     AND link.id = v_link_id
     AND link.token_sha256 = p_token_sha256
     AND link.revoked_at IS NULL
     AND link.expires_at > clock_timestamp()
     AND invitation.status = 'active'
     AND invitation.current_revision_number = revision.revision_number
     AND revision.issued_at IS NOT NULL
     AND policy.state = 'published'
     AND revision.schedule_revision_id = eogp.current_event_schedule_revision_id(v_organization_id,event.id)
     AND event.status NOT IN ('completed', 'cancelled', 'archived');

  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.submit_guest_invitation_rsvp(
  p_token_sha256 text,
  p_idempotency_key_sha256 text,
  p_request_sha256 text,
  p_response text,
  p_notes_restricted_ciphertext bytea DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_organization_id uuid;
  v_link_id uuid;
  v_participation_id uuid;
  v_link eogp.invitation_links%ROWTYPE;
  v_invitation eogp.invitations%ROWTYPE;
  v_revision eogp.invitation_revisions%ROWTYPE;
  v_policy eogp.rsvp_policy_revisions%ROWTYPE;
  v_schedule_id uuid;
  v_existing_request_sha256 text;
  v_existing_response jsonb;
  v_previous_response text;
  v_sequence_number integer;
  v_response_id uuid;
  v_now timestamptz := clock_timestamp();
  v_result jsonb;
BEGIN
  IF p_token_sha256 IS NULL OR p_token_sha256 !~ '^[0-9a-f]{64}$'
     OR p_idempotency_key_sha256 IS NULL OR p_idempotency_key_sha256 !~ '^[0-9a-f]{64}$'
     OR p_request_sha256 IS NULL OR p_request_sha256 !~ '^[0-9a-f]{64}$'
     OR p_response IS NULL OR p_response NOT IN ('accepted', 'declined', 'tentative') THEN
    RAISE EXCEPTION 'invalid guest RSVP request' USING ERRCODE = '22023';
  END IF;
  IF p_notes_restricted_ciphertext IS NOT NULL
     AND (octet_length(p_notes_restricted_ciphertext) <= 32
          OR substring(p_notes_restricted_ciphertext FROM 1 FOR 4) <> convert_to('ECP1', 'UTF8')) THEN
    RAISE EXCEPTION 'guest RSVP note must use the ECP1 encrypted envelope'
      USING ERRCODE = '22023';
  END IF;

  SELECT lookup.organization_id, lookup.invitation_link_id
    INTO v_organization_id, v_link_id
    FROM eogp.guest_invitation_capability_lookup lookup
   WHERE lookup.token_sha256 = p_token_sha256;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'guest invitation not found' USING ERRCODE = 'P0002';
  END IF;

  PERFORM set_config('app.organization_id', v_organization_id::text, true);

  -- Match issuance/reissue lock order: participation, invitation, then link.
  -- This read discovers the immutable participation identifier only; mutable state
  -- is reloaded under row locks before the capability is accepted.
  SELECT invitation.participation_id
    INTO v_participation_id
    FROM eogp.invitation_links link
    JOIN eogp.invitations invitation
      ON invitation.organization_id = link.organization_id
     AND invitation.event_id = link.event_id
     AND invitation.id = link.invitation_id
   WHERE link.organization_id = v_organization_id
     AND link.id = v_link_id
     AND link.token_sha256 = p_token_sha256;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'guest invitation not found' USING ERRCODE = 'P0002';
  END IF;

  PERFORM 1
    FROM eogp.event_participations participation
   WHERE participation.organization_id = v_organization_id
     AND participation.id = v_participation_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'guest participation not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT invitation.*
    INTO v_invitation
    FROM eogp.invitations invitation
   WHERE invitation.organization_id = v_organization_id
     AND invitation.participation_id = v_participation_id
     AND invitation.id = (
       SELECT link.invitation_id
         FROM eogp.invitation_links link
        WHERE link.organization_id = v_organization_id
          AND link.id = v_link_id
          AND link.token_sha256 = p_token_sha256
     )
   FOR UPDATE;
  IF NOT FOUND OR v_invitation.status <> 'active' THEN
    RAISE EXCEPTION 'guest invitation is not active' USING ERRCODE = '55000';
  END IF;

  SELECT link.*
    INTO v_link
    FROM eogp.invitation_links link
   WHERE link.organization_id = v_organization_id
     AND link.id = v_link_id
     AND link.invitation_id = v_invitation.id
     AND link.token_sha256 = p_token_sha256
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'guest invitation not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_link.revoked_at IS NOT NULL OR v_link.expires_at <= v_now THEN
    RAISE EXCEPTION 'guest invitation is expired or revoked' USING ERRCODE = '55000';
  END IF;

  SELECT revision.*
    INTO v_revision
    FROM eogp.invitation_revisions revision
   WHERE revision.organization_id = v_organization_id
     AND revision.event_id = v_link.event_id
     AND revision.invitation_id = v_link.invitation_id
     AND revision.id = v_link.invitation_revision_id;
  IF NOT FOUND OR v_revision.issued_at IS NULL
     OR v_revision.revision_number <> v_invitation.current_revision_number THEN
    RAISE EXCEPTION 'guest invitation revision is no longer current' USING ERRCODE = '55000';
  END IF;

  SELECT policy.*
    INTO v_policy
    FROM eogp.rsvp_policy_revisions policy
   WHERE policy.organization_id = v_organization_id
     AND policy.event_id = v_revision.event_id
     AND policy.id = v_revision.rsvp_policy_revision_id;
  IF NOT FOUND OR v_policy.state <> 'published'
     OR NOT (v_policy.allowed_responses ? p_response) THEN
    RAISE EXCEPTION 'RSVP response is not allowed by the published policy'
      USING ERRCODE = '55000';
  END IF;

  -- A capability issued for an obsolete schedule or inactive event must not
  -- remain usable after an executed event decision.
  IF NOT EXISTS (
    SELECT 1
      FROM eogp.events event
      JOIN eogp.event_schedule_revisions schedule
        ON schedule.organization_id = event.organization_id
       AND schedule.event_id = event.id
     WHERE event.organization_id = v_organization_id
       AND event.id = v_invitation.event_id
       AND event.status NOT IN ('completed','cancelled','archived')
       AND schedule.id = v_revision.schedule_revision_id
       AND schedule.id = eogp.current_event_schedule_revision_id(v_organization_id,event.id)
  ) OR NOT EXISTS (
    SELECT 1
      FROM eogp.event_participations participation
     WHERE participation.organization_id = v_organization_id
       AND participation.event_id = v_invitation.event_id
       AND participation.id = v_invitation.participation_id
       AND participation.status = 'eligible'
  ) THEN
    RAISE EXCEPTION 'guest invitation capability is no longer valid for the current event state'
      USING ERRCODE = '55000';
  END IF;

  -- Cached responses are replayable only while the bearer capability remains live.
  SELECT record.request_sha256, record.response_body
    INTO v_existing_request_sha256, v_existing_response
    FROM eogp.guest_invitation_rsvp_idempotency record
   WHERE record.organization_id = v_organization_id
     AND record.invitation_link_id = v_link_id
     AND record.idempotency_key_sha256 = p_idempotency_key_sha256
   FOR UPDATE;
  IF FOUND THEN
    IF v_existing_request_sha256 <> p_request_sha256 THEN
      RAISE EXCEPTION 'guest RSVP idempotency key was reused with a different request'
        USING ERRCODE = '55000';
    END IF;
    RETURN jsonb_set(v_existing_response, '{replayed}', 'true'::jsonb, true);
  END IF;

  SELECT response.response
    INTO v_previous_response
    FROM eogp.rsvp_responses response
   WHERE response.organization_id = v_organization_id
     AND response.event_id = v_invitation.event_id
     AND response.participation_id = v_invitation.participation_id
   ORDER BY response.sequence_number DESC
   LIMIT 1;
  IF FOUND AND NOT v_policy.response_change_allowed THEN
    RAISE EXCEPTION 'RSVP changes are not allowed by the published policy'
      USING ERRCODE = '55000';
  END IF;
  IF v_policy.response_deadline IS NOT NULL
     AND v_policy.response_deadline <= v_now
     AND v_previous_response IS NOT NULL
     AND v_policy.late_change_requires_staff THEN
    RAISE EXCEPTION 'late RSVP changes require staff assistance' USING ERRCODE = '55000';
  END IF;

  SELECT COALESCE(max(response.sequence_number), 0) + 1
    INTO v_sequence_number
    FROM eogp.rsvp_responses response
   WHERE response.organization_id = v_organization_id
     AND response.participation_id = v_invitation.participation_id;

  INSERT INTO eogp.rsvp_responses (
    organization_id, event_id, participation_id, invitation_id,
    invitation_revision_id, schedule_revision_id, sequence_number,
    response, source_channel, respondent_kind, received_at, invitation_link_id,
    notes_restricted_ciphertext
  ) VALUES (
    v_organization_id, v_invitation.event_id, v_invitation.participation_id,
    v_invitation.id, v_revision.id, v_revision.schedule_revision_id,
    v_sequence_number, p_response, 'invitation_link', 'guest', v_now, v_link.id,
    p_notes_restricted_ciphertext
  ) RETURNING id INTO v_response_id;

  v_result := jsonb_build_object(
    'invitationId', v_invitation.id,
    'responseId', v_response_id,
    'response', p_response,
    'receivedAt', v_now,
    'replayed', false
  );

  INSERT INTO eogp.guest_invitation_rsvp_idempotency (
    organization_id, invitation_link_id, idempotency_key_sha256,
    request_sha256, response_body
  ) VALUES (
    v_organization_id, v_link.id, p_idempotency_key_sha256,
    p_request_sha256, v_result
  );

  INSERT INTO eogp.audit_events (
    organization_id, actor_external_capability_id, actor_kind, action, aggregate_type, aggregate_id,
    reason_code, safe_metadata, occurred_at
  ) VALUES (
    v_organization_id, v_link.id, 'external_capability', 'guest.rsvp.submitted',
    'invitation', v_invitation.id, 'guest_submitted_rsvp',
    jsonb_build_object('response', p_response, 'responseId', v_response_id),
    v_now
  );

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.resolve_guest_invitation(text),
  eogp.get_guest_invitation_rsvp_history(text),
  eogp.submit_guest_invitation_rsvp(text,text,text,text,bytea)
  FROM PUBLIC,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.resolve_guest_invitation(text),
  eogp.get_guest_invitation_rsvp_history(text),
  eogp.submit_guest_invitation_rsvp(text,text,text,text,bytea)
  TO eventor_runtime;
