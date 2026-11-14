-- Organizer-facing guest invitation workspace projections.
-- These projections expose only invitation-management data and never contact values.

CREATE FUNCTION eogp.list_guest_invitation_events(
  p_organization_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id
     OR nullif(current_setting('app.actor_membership_id', true), '')::uuid
          IS DISTINCT FROM p_actor_membership_id THEN
    RAISE EXCEPTION 'organization or staff actor context mismatch' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM eogp.organization_memberships membership
     WHERE membership.organization_id=p_organization_id
       AND membership.id=p_actor_membership_id
       AND membership.status='active'
  ) THEN
    RAISE EXCEPTION 'active staff membership is required' USING ERRCODE='42501';
  END IF;

  SELECT COALESCE(jsonb_agg(event_row ORDER BY event_row->>'startsAt' NULLS LAST, event_row->>'title'), '[]'::jsonb)
    INTO v_result
    FROM (
      SELECT jsonb_build_object(
        'eventId', event.id,
        'eventCode', event.event_code,
        'title', event.title,
        'status', event.status,
        'startsAt', schedule.starts_at,
        'endsAt', schedule.ends_at,
        'timezone', COALESCE(schedule.timezone_name, event.timezone_name),
        'scheduleRevisionId', schedule.id,
        'rsvpPolicyRevisionId', (SELECT policy.id FROM eogp.rsvp_policy_revisions policy
          WHERE policy.organization_id=event.organization_id AND policy.event_id=event.id AND policy.state='published'
          ORDER BY policy.revision_number DESC LIMIT 1),
        'eligibleParticipationCount', (
          SELECT count(*) FROM eogp.event_participations participation
           WHERE participation.organization_id=event.organization_id
             AND participation.event_id=event.id
             AND participation.status='eligible'
        ),
        'invitationCount', (
          SELECT count(*) FROM eogp.invitations invitation
           WHERE invitation.organization_id=event.organization_id
             AND invitation.event_id=event.id
             AND invitation.status IN ('active','draft')
        )
      ) AS event_row
      FROM eogp.events event
      LEFT JOIN LATERAL (
        SELECT revision.id, revision.starts_at, revision.ends_at, revision.timezone_name
          FROM eogp.event_schedule_revisions revision
         WHERE revision.organization_id=event.organization_id
           AND revision.event_id=event.id
         ORDER BY revision.revision_number DESC
         LIMIT 1
      ) schedule ON true
      WHERE event.organization_id=p_organization_id
        AND EXISTS (
          SELECT 1
            FROM eogp.user_role_grants user_grant
            JOIN eogp.role_permissions role_permission
              ON role_permission.organization_id=user_grant.organization_id
             AND role_permission.role_id=user_grant.role_id
           WHERE user_grant.organization_id=p_organization_id
             AND user_grant.membership_id=p_actor_membership_id
             AND user_grant.revoked_at IS NULL
             AND (user_grant.expires_at IS NULL OR user_grant.expires_at>clock_timestamp())
             AND role_permission.permission_code='invitation.manage'
             AND (user_grant.scope_kind='organization'
               OR (user_grant.scope_kind='event' AND user_grant.scope_event_id=event.id))
        )
    ) events;
  RETURN v_result;
END;
$function$;

CREATE FUNCTION eogp.list_guest_invitation_participations(
  p_organization_id uuid,
  p_event_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id
     OR nullif(current_setting('app.actor_membership_id', true), '')::uuid
          IS DISTINCT FROM p_actor_membership_id THEN
    RAISE EXCEPTION 'organization or staff actor context mismatch' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM eogp.organization_memberships membership
     WHERE membership.organization_id=p_organization_id
       AND membership.id=p_actor_membership_id
       AND membership.status='active'
  ) OR NOT EXISTS (
    SELECT 1
      FROM eogp.user_role_grants user_grant
      JOIN eogp.role_permissions role_permission
        ON role_permission.organization_id=user_grant.organization_id
       AND role_permission.role_id=user_grant.role_id
     WHERE user_grant.organization_id=p_organization_id
       AND user_grant.membership_id=p_actor_membership_id
       AND user_grant.revoked_at IS NULL
       AND (user_grant.expires_at IS NULL OR user_grant.expires_at>clock_timestamp())
       AND role_permission.permission_code='invitation.manage'
       AND (user_grant.scope_kind='organization'
         OR (user_grant.scope_kind='event' AND user_grant.scope_event_id=p_event_id))
  ) THEN
    RAISE EXCEPTION 'invitation.manage permission is required for this event' USING ERRCODE='42501';
  END IF;

  SELECT COALESCE(jsonb_agg(participation_row ORDER BY participation_row->>'displayName'), '[]'::jsonb)
    INTO v_result
    FROM (
      SELECT jsonb_build_object(
        'participationId', participation.id,
        'displayName', COALESCE(NULLIF(person.display_name,''), NULLIF(person.preferred_name,''), concat_ws(' ',person.first_name,person.last_name)),
        'participationCode', participation.participation_code,
        'categoryCode', participation.category_code,
        'status', participation.status,
        'emailReady', EXISTS (
          SELECT 1 FROM eogp.person_contact_points contact
           WHERE contact.organization_id=participation.organization_id
             AND contact.person_id=participation.person_id
             AND contact.contact_kind='email'
             AND contact.is_primary=true
             AND contact.is_verified=true
             AND contact.contact_consent='permitted'
        ),
        'invitationId', invitation.id,
        'invitationStatus', invitation.status,
        'invitationRevisionNumber', invitation.current_revision_number,
        'deliveryStatus', delivery.status,
        'currentResponse', response.response,
        'responseReceivedAt', response.received_at
      ) AS participation_row
      FROM eogp.event_participations participation
      JOIN eogp.persons person
        ON person.organization_id=participation.organization_id
       AND person.id=participation.person_id
      LEFT JOIN LATERAL (
        SELECT candidate.id, candidate.status, candidate.current_revision_number
          FROM eogp.invitations candidate
         WHERE candidate.organization_id=participation.organization_id
           AND candidate.event_id=participation.event_id
           AND candidate.participation_id=participation.id
         ORDER BY candidate.created_at DESC
         LIMIT 1
      ) invitation ON true
      LEFT JOIN LATERAL (
        SELECT candidate.status
          FROM eogp.invitation_deliveries candidate
         WHERE candidate.organization_id=participation.organization_id
           AND candidate.event_id=participation.event_id
           AND candidate.invitation_id=invitation.id
         ORDER BY candidate.queued_at DESC
         LIMIT 1
      ) delivery ON true
      LEFT JOIN LATERAL (
        SELECT candidate.response, candidate.received_at
          FROM eogp.rsvp_responses candidate
         WHERE candidate.organization_id=participation.organization_id
           AND candidate.event_id=participation.event_id
           AND candidate.participation_id=participation.id
         ORDER BY candidate.sequence_number DESC
         LIMIT 1
      ) response ON true
      WHERE participation.organization_id=p_organization_id
        AND participation.event_id=p_event_id
        AND person.status='active'
    ) participations;
  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.list_guest_invitation_events(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.list_guest_invitation_participations(uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.list_guest_invitation_events(uuid,uuid) TO eventor_runtime;
GRANT EXECUTE ON FUNCTION eogp.list_guest_invitation_participations(uuid,uuid,uuid) TO eventor_runtime;
