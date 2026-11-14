-- Permission-scoped staff read model for append-only RSVP response history.
-- Restricted note ciphertext is intentionally excluded.
CREATE FUNCTION eogp.list_staff_guest_rsvp_history(
  p_organization_id uuid,p_event_id uuid,p_participation_id uuid,p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE v_result jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id
     OR nullif(current_setting('app.actor_membership_id',true),'')::uuid IS DISTINCT FROM p_actor_membership_id THEN
    RAISE EXCEPTION 'organization or staff actor context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM 1 FROM eogp.organization_memberships membership
   WHERE membership.organization_id=p_organization_id AND membership.id=p_actor_membership_id AND membership.status='active'
   FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'active organization membership required' USING ERRCODE='42501'; END IF;
  PERFORM 1
    FROM eogp.user_role_grants user_grant
    JOIN eogp.role_permissions role_permission ON role_permission.organization_id=user_grant.organization_id AND role_permission.role_id=user_grant.role_id
   WHERE user_grant.organization_id=p_organization_id AND user_grant.membership_id=p_actor_membership_id
     AND user_grant.revoked_at IS NULL AND (user_grant.expires_at IS NULL OR user_grant.expires_at>clock_timestamp())
     AND role_permission.permission_code='invitation.manage'
     AND (user_grant.scope_kind='organization' OR (user_grant.scope_kind='event' AND user_grant.scope_event_id=p_event_id))
   FOR SHARE OF user_grant,role_permission;
  IF NOT FOUND THEN RAISE EXCEPTION 'invitation.manage permission is required for RSVP history' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS (SELECT 1 FROM eogp.event_participations participation
    WHERE participation.organization_id=p_organization_id AND participation.event_id=p_event_id AND participation.id=p_participation_id) THEN
    RAISE EXCEPTION 'event participation not found' USING ERRCODE='P0002';
  END IF;
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'responseId',response.id,'sequenceNumber',response.sequence_number,'response',response.response,
    'sourceChannel',response.source_channel,'respondentKind',response.respondent_kind,
    'receivedAt',response.received_at,'recordedAt',response.recorded_at,
    'actorMembershipId',response.actor_membership_id,'correctionOfResponseId',response.correction_of_response_id,
    'correctionReason',response.correction_reason,'invitationId',response.invitation_id,
    'scheduleRevisionId',response.schedule_revision_id
  ) ORDER BY response.sequence_number DESC),'[]'::jsonb)
  INTO v_result FROM eogp.rsvp_responses response
  WHERE response.organization_id=p_organization_id AND response.event_id=p_event_id AND response.participation_id=p_participation_id;
  RETURN v_result;
END;
$function$;
REVOKE ALL ON FUNCTION eogp.list_staff_guest_rsvp_history(uuid,uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.list_staff_guest_rsvp_history(uuid,uuid,uuid,uuid) TO eventor_runtime;
