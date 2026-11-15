-- Authorize staff RSVP writes before resource lookup to prevent participation enumeration.

CREATE OR REPLACE FUNCTION eogp.record_staff_guest_rsvp(
  p_organization_id uuid,
  p_event_id uuid,
  p_participation_id uuid,
  p_actor_membership_id uuid,
  p_response text,
  p_source_channel text,
  p_respondent_kind text,
  p_received_at timestamptz,
  p_invitation_id uuid,
  p_notes_restricted_ciphertext bytea,
  p_correction_of_response_id uuid,
  p_correction_reason text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_event_status text;
  v_policy eogp.rsvp_policy_revisions%ROWTYPE;
  v_invitation eogp.invitations%ROWTYPE;
  v_invitation_revision_id uuid;
  v_policy_revision_id uuid;
  v_schedule_revision_id uuid;
  v_latest_response_id uuid;
  v_sequence_number integer;
  v_response_id uuid;
  v_recorded_at timestamptz;
  v_now timestamptz := clock_timestamp();
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id
     OR nullif(current_setting('app.actor_membership_id', true), '')::uuid
          IS DISTINCT FROM p_actor_membership_id THEN
    RAISE EXCEPTION 'organization or staff actor context mismatch' USING ERRCODE='42501';
  END IF;

  IF p_response IS NULL OR p_source_channel IS NULL OR p_respondent_kind IS NULL
     OR p_response NOT IN ('accepted','declined','tentative')
     OR p_source_channel NOT IN ('phone','in_person','email','written','representative','staff_entry','other')
     OR p_respondent_kind NOT IN ('guest','representative','staff')
     OR p_received_at IS NULL OR p_received_at > v_now
     OR ((p_correction_of_response_id IS NULL) <> (p_correction_reason IS NULL))
     OR (p_correction_reason IS NOT NULL AND length(btrim(p_correction_reason)) < 3)
     OR (p_source_channel='representative' AND p_respondent_kind<>'representative')
     OR (p_source_channel='staff_entry' AND p_respondent_kind<>'staff')
     OR (p_notes_restricted_ciphertext IS NOT NULL
       AND (octet_length(p_notes_restricted_ciphertext)<=32
         OR substring(p_notes_restricted_ciphertext FROM 1 FOR 4)<>convert_to('ECP1','UTF8'))) THEN
    RAISE EXCEPTION 'invalid staff RSVP values' USING ERRCODE='22023';
  END IF;

  PERFORM 1
    FROM eogp.organization_memberships membership
   WHERE membership.organization_id=p_organization_id
     AND membership.id=p_actor_membership_id
     AND membership.status='active'
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'active organization membership required' USING ERRCODE='42501';
  END IF;

  -- Authorize before looking up participation state so members without
  -- rsvp.record cannot distinguish existing/eligible IDs from missing ones.
  PERFORM 1
    FROM eogp.user_role_grants user_grant
    JOIN eogp.role_permissions role_permission
      ON role_permission.organization_id=user_grant.organization_id
     AND role_permission.role_id=user_grant.role_id
   WHERE user_grant.organization_id=p_organization_id
     AND user_grant.membership_id=p_actor_membership_id
     AND user_grant.revoked_at IS NULL
     AND (user_grant.expires_at IS NULL OR user_grant.expires_at>v_now)
     AND role_permission.permission_code='rsvp.record'
     AND (user_grant.scope_kind='organization'
       OR (user_grant.scope_kind='event' AND user_grant.scope_event_id=p_event_id))
   FOR SHARE OF user_grant, role_permission;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'rsvp.record permission is required' USING ERRCODE='42501';
  END IF;

  -- Participation is the serialization anchor shared with guest RSVP and
  -- invitation issue/reissue. Lock it before invitation and response rows.
  PERFORM 1
    FROM eogp.event_participations participation
   WHERE participation.organization_id=p_organization_id
     AND participation.event_id=p_event_id
     AND participation.id=p_participation_id
     AND participation.status='eligible'
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'eligible event participation not found' USING ERRCODE='P0002';
  END IF;

  SELECT event.status
    INTO v_event_status
    FROM eogp.events event
   WHERE event.organization_id=p_organization_id
     AND event.id=p_event_id
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'event not found' USING ERRCODE='P0002';
  END IF;
  IF v_event_status IN ('completed','cancelled','archived') THEN
    RAISE EXCEPTION 'RSVP cannot be recorded for a closed event' USING ERRCODE='55000';
  END IF;

  v_schedule_revision_id := eogp.current_event_schedule_revision_id(p_organization_id,p_event_id);
  IF v_schedule_revision_id IS NULL THEN
    RAISE EXCEPTION 'event has no effective schedule' USING ERRCODE='55000';
  END IF;

  IF p_invitation_id IS NOT NULL THEN
    SELECT invitation.*
      INTO v_invitation
      FROM eogp.invitations invitation
     WHERE invitation.organization_id=p_organization_id
       AND invitation.event_id=p_event_id
       AND invitation.id=p_invitation_id
       AND invitation.participation_id=p_participation_id
     FOR SHARE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'invitation does not belong to this participation' USING ERRCODE='P0002';
    END IF;
    SELECT revision.id, revision.rsvp_policy_revision_id
      INTO v_invitation_revision_id, v_policy_revision_id
      FROM eogp.invitation_revisions revision
     WHERE revision.organization_id=p_organization_id
       AND revision.event_id=p_event_id
       AND revision.invitation_id=p_invitation_id
       AND revision.revision_number=v_invitation.current_revision_number
     ORDER BY revision.revision_number DESC
     LIMIT 1;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'current invitation revision not found' USING ERRCODE='55000';
    END IF;
    SELECT policy.*
      INTO v_policy
      FROM eogp.rsvp_policy_revisions policy
     WHERE policy.organization_id=p_organization_id
       AND policy.event_id=p_event_id
       AND policy.id=v_policy_revision_id;
  ELSE
    SELECT policy.*
      INTO v_policy
      FROM eogp.rsvp_policy_revisions policy
     WHERE policy.organization_id=p_organization_id
       AND policy.event_id=p_event_id
       AND policy.state='published'
     ORDER BY policy.revision_number DESC
     LIMIT 1;
  END IF;
  IF NOT FOUND OR v_policy.state<>'published'
     OR NOT (v_policy.allowed_responses ? p_response) THEN
    RAISE EXCEPTION 'no applicable published RSVP policy allows this response' USING ERRCODE='55000';
  END IF;



  SELECT response.id
    INTO v_latest_response_id
    FROM eogp.rsvp_responses response
   WHERE response.organization_id=p_organization_id
     AND response.event_id=p_event_id
     AND response.participation_id=p_participation_id
   ORDER BY response.sequence_number DESC
   LIMIT 1;

  IF p_correction_of_response_id IS NOT NULL THEN
    PERFORM 1
      FROM eogp.user_role_grants user_grant
      JOIN eogp.role_permissions role_permission
        ON role_permission.organization_id=user_grant.organization_id
       AND role_permission.role_id=user_grant.role_id
     WHERE user_grant.organization_id=p_organization_id
       AND user_grant.membership_id=p_actor_membership_id
       AND user_grant.revoked_at IS NULL
       AND (user_grant.expires_at IS NULL OR user_grant.expires_at>v_now)
       AND role_permission.permission_code='rsvp.correct'
       AND (user_grant.scope_kind='organization'
         OR (user_grant.scope_kind='event' AND user_grant.scope_event_id=p_event_id))
     FOR SHARE OF user_grant, role_permission;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'rsvp.correct permission is required to correct RSVP history' USING ERRCODE='42501';
    END IF;
    IF v_latest_response_id IS DISTINCT FROM p_correction_of_response_id THEN
      RAISE EXCEPTION 'only the current RSVP response can be corrected' USING ERRCODE='55000';
    END IF;
  ELSIF v_latest_response_id IS NOT NULL AND NOT v_policy.response_change_allowed THEN
    RAISE EXCEPTION 'RSVP changes are not allowed by the published policy' USING ERRCODE='55000';
  END IF;

  IF v_policy.late_change_requires_staff
     AND v_policy.response_deadline IS NOT NULL AND v_policy.response_deadline <= v_now THEN
    PERFORM 1
      FROM eogp.user_role_grants user_grant
      JOIN eogp.role_permissions role_permission
        ON role_permission.organization_id=user_grant.organization_id
       AND role_permission.role_id=user_grant.role_id
     WHERE user_grant.organization_id=p_organization_id
       AND user_grant.membership_id=p_actor_membership_id
       AND user_grant.revoked_at IS NULL
       AND (user_grant.expires_at IS NULL OR user_grant.expires_at>v_now)
       AND role_permission.permission_code='rsvp.override_deadline'
       AND (user_grant.scope_kind='organization'
         OR (user_grant.scope_kind='event' AND user_grant.scope_event_id=p_event_id))
     FOR SHARE OF user_grant, role_permission;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'rsvp.override_deadline permission is required after the RSVP deadline' USING ERRCODE='42501';
    END IF;
  END IF;

  SELECT COALESCE(max(response.sequence_number),0)+1
    INTO v_sequence_number
    FROM eogp.rsvp_responses response
   WHERE response.organization_id=p_organization_id
     AND response.event_id=p_event_id
     AND response.participation_id=p_participation_id;

  INSERT INTO eogp.rsvp_responses (
    organization_id,event_id,participation_id,invitation_id,invitation_revision_id,
    schedule_revision_id,sequence_number,response,source_channel,respondent_kind,
    received_at,actor_membership_id,correction_of_response_id,correction_reason,
    notes_restricted_ciphertext
  ) VALUES (
    p_organization_id,p_event_id,p_participation_id,p_invitation_id,
    v_invitation_revision_id,v_schedule_revision_id,v_sequence_number,p_response,
    p_source_channel,p_respondent_kind,p_received_at,p_actor_membership_id,
    p_correction_of_response_id,p_correction_reason,p_notes_restricted_ciphertext
  ) RETURNING id, recorded_at INTO v_response_id, v_recorded_at;

  INSERT INTO eogp.audit_events (
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata,occurred_at
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    CASE WHEN p_correction_of_response_id IS NULL
      THEN 'guest.rsvp.recorded' ELSE 'guest.rsvp.corrected' END,
    'event_participation',p_participation_id,
    CASE WHEN p_correction_of_response_id IS NULL
      THEN 'staff_recorded' ELSE 'staff_correction' END,
    jsonb_build_object(
      'responseId',v_response_id,'response',p_response,
      'sourceChannel',p_source_channel,'respondentKind',p_respondent_kind,
      'sequenceNumber',v_sequence_number,
      'correctionOfResponseId',p_correction_of_response_id
    ),
    v_recorded_at
  );

  RETURN jsonb_build_object(
    'responseId',v_response_id,
    'participationId',p_participation_id,
    'response',p_response,
    'sourceChannel',p_source_channel,
    'respondentKind',p_respondent_kind,
    'receivedAt',p_received_at,
    'recordedAt',v_recorded_at,
    'sequenceNumber',v_sequence_number,
    'correctionOfResponseId',p_correction_of_response_id
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.record_staff_guest_rsvp(uuid,uuid,uuid,uuid,text,text,text,timestamptz,uuid,bytea,uuid,text)
  FROM PUBLIC,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.record_staff_guest_rsvp(uuid,uuid,uuid,uuid,text,text,text,timestamptz,uuid,bytea,uuid,text)
  TO eventor_runtime;
