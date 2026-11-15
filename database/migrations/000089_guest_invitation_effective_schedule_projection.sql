-- Organizer event projections must show the effective schedule, not an unexecuted proposal.
CREATE OR REPLACE FUNCTION eogp.list_guest_invitation_events(
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
           AND revision.id=eogp.current_event_schedule_revision_id(event.organization_id,event.id)
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

REVOKE ALL ON FUNCTION eogp.list_guest_invitation_events(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.list_guest_invitation_events(uuid,uuid) TO eventor_runtime;
