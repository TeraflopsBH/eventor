CREATE OR REPLACE FUNCTION eogp.list_organizer_events(
  p_organization_id uuid,
  p_actor_membership_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_event record;
  v_result jsonb := '[]'::jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;

  PERFORM 1
    FROM eogp.organization_memberships m
   WHERE m.organization_id = p_organization_id
     AND m.id = p_actor_membership_id
     AND m.status = 'active'
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'active organization membership required' USING ERRCODE='42501';
  END IF;

  FOR v_event IN
    SELECT e.id, e.event_code, e.title, e.description_internal, e.status,
           e.current_revision, e.details_revision, e.timezone_name,
           e.created_at, e.updated_at,
           COALESCE(capability.enabled, false) AS guest_registry_enabled,
           s.id AS schedule_revision_id, s.revision_number AS schedule_revision_number,
           s.starts_at, s.ends_at, s.timezone_name AS schedule_timezone_name,
           s.venue_summary
      FROM eogp.events e
      LEFT JOIN eogp.event_capability_overrides capability
        ON capability.organization_id = e.organization_id AND capability.event_id = e.id
        AND capability.capability_code = 'guest_registry'
      LEFT JOIN LATERAL (
        SELECT sr.id, sr.revision_number, sr.starts_at, sr.ends_at,
               sr.timezone_name, sr.venue_summary
          FROM eogp.event_schedule_revisions sr
         WHERE sr.organization_id = e.organization_id
           AND sr.event_id = e.id
         ORDER BY sr.revision_number DESC
         LIMIT 1
      ) s ON true
     WHERE e.organization_id = p_organization_id
     ORDER BY e.updated_at DESC, e.id
  LOOP
    BEGIN
      PERFORM eogp.assert_event_command_permission(
        p_organization_id, v_event.id, p_actor_membership_id, 'event.manage'
      );
      v_result := v_result || jsonb_build_array(jsonb_build_object(
        'eventId', v_event.id,
        'guestRegistryEnabled', v_event.guest_registry_enabled,
        'eventCode', v_event.event_code,
        'title', v_event.title,
        'descriptionInternal', v_event.description_internal,
        'status', v_event.status,
        'currentRevision', v_event.current_revision,
        'detailsRevision', v_event.details_revision,
        'timezoneName', v_event.timezone_name,
        'createdAt', v_event.created_at,
        'updatedAt', v_event.updated_at,
        'scheduleRevisionId', v_event.schedule_revision_id,
        'scheduleRevisionNumber', v_event.schedule_revision_number,
        'startsAt', v_event.starts_at,
        'endsAt', v_event.ends_at,
        'scheduleTimezoneName', v_event.schedule_timezone_name,
        'venueSummary', coalesce(v_event.venue_summary,'{}'::jsonb)
      ));
    EXCEPTION WHEN insufficient_privilege THEN
      NULL;
    END;
  END LOOP;

  RETURN v_result;
END;
$function$;

REVOKE INSERT, UPDATE, DELETE ON eogp.event_capability_overrides, eogp.event_participations FROM eventor_runtime;

ALTER TABLE eogp.event_participations ADD COLUMN person_identity_snapshot jsonb
  CHECK (person_identity_snapshot IS NULL OR jsonb_typeof(person_identity_snapshot) = 'object');

CREATE FUNCTION eogp.reject_participation_identity_change() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  IF OLD.person_identity_snapshot IS DISTINCT FROM NEW.person_identity_snapshot THEN
    RAISE EXCEPTION 'participation identity snapshots are immutable' USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER event_participations_immutable_identity
BEFORE UPDATE OF person_identity_snapshot ON eogp.event_participations
FOR EACH ROW EXECUTE FUNCTION eogp.reject_participation_identity_change();

CREATE FUNCTION eogp.enable_event_guest_registry(p_org uuid, p_event uuid, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE v_status text;
BEGIN
  PERFORM eogp.assert_event_command_permission(p_org, p_event, p_actor, 'event.manage');
  SELECT status INTO v_status FROM eogp.events WHERE organization_id = p_org AND id = p_event FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002'; END IF;
  IF v_status NOT IN ('draft', 'planned', 'scheduled', 'active') THEN
    RAISE EXCEPTION 'event guest list cannot be enabled in this phase' USING ERRCODE = '55000';
  END IF;
  INSERT INTO eogp.event_capability_overrides (
    organization_id, event_id, capability_code, enabled, changed_by_membership_id
  ) VALUES (p_org, p_event, 'guest_registry', true, p_actor)
  ON CONFLICT (organization_id, event_id, capability_code) DO UPDATE
    SET enabled = true, changed_by_membership_id = p_actor, changed_at = clock_timestamp()
    WHERE NOT eogp.event_capability_overrides.enabled;
  IF FOUND THEN
    INSERT INTO eogp.audit_events (
      organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id
    ) VALUES (p_org, p_org, p_actor, 'membership', 'event.guest_registry.enabled', 'event', p_event);
  END IF;
  RETURN jsonb_build_object('eventId', p_event, 'guestRegistryEnabled', true);
END;
$function$;

CREATE FUNCTION eogp.assert_event_participation_link_permission(p_org uuid, p_event uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  PERFORM eogp.assert_guest_registry_permission(p_org, p_actor, false);
  PERFORM eogp.assert_event_command_permission(p_org, p_event, p_actor, 'guest.manage');
END;
$function$;

CREATE FUNCTION eogp.list_registry_linkable_events(p_org uuid, p_actor uuid, p_person uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_event record;
  v_result jsonb := '[]'::jsonb;
BEGIN
  PERFORM eogp.assert_guest_registry_permission(p_org, p_actor, false);
  IF NOT EXISTS (SELECT 1 FROM eogp.persons WHERE organization_id = p_org AND id = p_person AND status = 'active') THEN
    RAISE EXCEPTION 'active person not found' USING ERRCODE = 'P0002';
  END IF;
  FOR v_event IN
    SELECT e.id, e.title, e.event_code FROM eogp.events e
    JOIN eogp.event_capability_overrides capability
      ON capability.organization_id = e.organization_id AND capability.event_id = e.id
      AND capability.capability_code = 'guest_registry' AND capability.enabled
    WHERE e.organization_id = p_org AND e.status IN ('draft', 'planned', 'scheduled', 'active')
      AND NOT EXISTS (SELECT 1 FROM eogp.event_participations p
        WHERE p.organization_id = p_org AND p.person_id = p_person AND p.event_id = e.id)
    ORDER BY e.updated_at DESC, e.id
  LOOP
    BEGIN
      PERFORM eogp.assert_event_command_permission(p_org, v_event.id, p_actor, 'guest.manage');
      v_result := v_result || jsonb_build_array(jsonb_build_object(
        'eventId', v_event.id, 'title', v_event.title, 'eventCode', v_event.event_code
      ));
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END LOOP;
  RETURN v_result;
END;
$function$;

CREATE FUNCTION eogp.link_registry_person_to_event(p_org uuid, p_event uuid, p_actor uuid, p_person uuid, p_status text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_event_status text;
  v_person eogp.persons%ROWTYPE;
  v_participation uuid;
BEGIN
  PERFORM eogp.assert_event_participation_link_permission(p_org, p_event, p_actor);
  SELECT status INTO v_event_status FROM eogp.events WHERE organization_id = p_org AND id = p_event FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002'; END IF;
  IF v_event_status NOT IN ('draft', 'planned', 'scheduled', 'active')
     OR NOT EXISTS (SELECT 1 FROM eogp.event_capability_overrides WHERE organization_id = p_org
                    AND event_id = p_event AND capability_code = 'guest_registry' AND enabled) THEN
    RAISE EXCEPTION 'event guest list has not been enabled or is closed' USING ERRCODE = '55000';
  END IF;
  SELECT * INTO v_person FROM eogp.persons WHERE organization_id = p_org AND id = p_person FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'person not found' USING ERRCODE = 'P0002'; END IF;
  IF v_person.status <> 'active' THEN
    RAISE EXCEPTION 'only active persons can join an event' USING ERRCODE = '55000';
  END IF;
  IF p_status IS NULL OR p_status NOT IN ('eligible', 'waitlisted', 'ineligible') THEN
    RAISE EXCEPTION 'invalid initial participation status' USING ERRCODE = '22023';
  END IF;

  INSERT INTO eogp.event_participations (
    organization_id, event_id, person_id, status, added_by_membership_id, person_identity_snapshot
  ) VALUES (
    p_org, p_event, p_person, p_status, p_actor, jsonb_build_object(
      'firstName', v_person.first_name, 'lastName', v_person.last_name,
      'displayName', coalesce(nullif(v_person.display_name, ''), nullif(v_person.preferred_name, ''),
                              concat_ws(' ', v_person.first_name, v_person.last_name)),
      'personRevision', v_person.revision
    )
  ) RETURNING id INTO v_participation;

  INSERT INTO eogp.participation_status_history (
    organization_id, event_id, participation_id, new_status, actor_membership_id, reason_code
  ) VALUES (p_org, p_event, v_participation, p_status, p_actor, 'registry_linked');

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.registry.linked', 'person', p_person,
    jsonb_build_object('eventId', p_event, 'participationId', v_participation)
  );

  RETURN jsonb_build_object('participationId', v_participation, 'eventId', p_event, 'status', p_status);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.enable_event_guest_registry(uuid,uuid,uuid),
  eogp.assert_event_participation_link_permission(uuid,uuid,uuid),
  eogp.list_registry_linkable_events(uuid,uuid,uuid),
  eogp.link_registry_person_to_event(uuid,uuid,uuid,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.enable_event_guest_registry(uuid,uuid,uuid),
  eogp.assert_event_participation_link_permission(uuid,uuid,uuid),
  eogp.list_registry_linkable_events(uuid,uuid,uuid),
  eogp.link_registry_person_to_event(uuid,uuid,uuid,uuid,text) TO eventor_runtime;

-- Use pinned names for newly linked guests and preserve the legacy projection.
CREATE OR REPLACE FUNCTION eogp.list_guest_invitation_participations(
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
  -- Hold the membership and grant/permission rows until this read transaction
  -- completes so a concurrent deactivation or permission revocation cannot
  -- commit while participant and RSVP data are being projected.
  PERFORM 1
    FROM eogp.organization_memberships membership
   WHERE membership.organization_id=p_organization_id
     AND membership.id=p_actor_membership_id
     AND membership.status='active'
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'active organization membership is required' USING ERRCODE='42501';
  END IF;

  PERFORM 1
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
   FOR SHARE OF user_grant,role_permission;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'invitation.manage permission is required for this event' USING ERRCODE='42501';
  END IF;

  SELECT COALESCE(jsonb_agg(participation_row ORDER BY participation_row->>'displayName'), '[]'::jsonb)
    INTO v_result
    FROM (
      SELECT jsonb_build_object(
        'participationId', participation.id,
        'displayName', COALESCE(participation.person_identity_snapshot->>'displayName',
          NULLIF(person.display_name,''), NULLIF(person.preferred_name,''), concat_ws(' ',person.first_name,person.last_name)),
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
        'currentResponseId', response.id,
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
        SELECT candidate.id, candidate.response, candidate.received_at
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
