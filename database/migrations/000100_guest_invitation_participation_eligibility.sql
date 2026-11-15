-- Withdrawn or otherwise ineligible participants must not retain access
-- to guest invitation presentation data or RSVP history through a live link.

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
    JOIN eogp.event_participations participation
      ON participation.organization_id = invitation.organization_id
     AND participation.event_id = invitation.event_id
     AND participation.id = invitation.participation_id
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
     AND participation.status = 'eligible'
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
    JOIN eogp.event_participations participation
      ON participation.organization_id = invitation.organization_id
     AND participation.event_id = invitation.event_id
     AND participation.id = invitation.participation_id
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
     AND participation.status = 'eligible'
     AND invitation.current_revision_number = revision.revision_number
     AND revision.issued_at IS NOT NULL
     AND policy.state = 'published'
     AND revision.schedule_revision_id = eogp.current_event_schedule_revision_id(v_organization_id,event.id)
     AND event.status NOT IN ('completed', 'cancelled', 'archived');

  RETURN v_result;
END;
$function$;
