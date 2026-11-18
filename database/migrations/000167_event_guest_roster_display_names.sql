ALTER TABLE eogp.event_participations ADD COLUMN roster_display_name_override text
  CHECK (roster_display_name_override IS NULL OR (
    length(btrim(roster_display_name_override)) BETWEEN 1 AND 250
    AND roster_display_name_override !~ '[[:cntrl:]]'
  ));

CREATE OR REPLACE VIEW eogp.event_guest_roster_rows WITH (security_invoker = true) AS
SELECT participation.organization_id,participation.event_id,participation.id,
  coalesce(participation.roster_display_name_override, recorded.display_name) AS display_name,
  participation.status,participation.revision,participation.category_code,participation.participation_code,participation.category_id,
  participation.person_identity_snapshot->>'firstName' AS snapshot_first_name,
  participation.person_identity_snapshot->>'lastName' AS snapshot_last_name,
  recorded.display_name AS recorded_display_name,
  participation.roster_display_name_override AS display_name_override
FROM eogp.event_participations participation
JOIN eogp.persons person ON person.organization_id=participation.organization_id AND person.id=participation.person_id
CROSS JOIN LATERAL (
  SELECT coalesce(participation.person_identity_snapshot->>'displayName',nullif(person.display_name,''),
    nullif(person.preferred_name,''),concat_ws(' ',person.first_name,person.last_name)) AS display_name
) recorded;

CREATE FUNCTION eogp.set_event_guest_roster_name(
  p_org uuid,p_event uuid,p_actor uuid,p_participation uuid,p_expected_revision integer,p_name text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_guest eogp.event_participations%ROWTYPE;
  v_name text := btrim(p_name);
BEGIN
  PERFORM eogp.assert_event_guest_list_write(p_org,p_event,p_actor);
  IF p_name IS NOT NULL AND (length(v_name) NOT BETWEEN 1 AND 250 OR v_name ~ '[[:cntrl:]]') THEN
    RAISE EXCEPTION 'invalid event guest roster name' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_guest FROM eogp.event_participations
  WHERE organization_id=p_org AND event_id=p_event AND id=p_participation FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'participation not found' USING ERRCODE='P0002'; END IF;
  IF v_guest.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'participation revision conflict' USING ERRCODE='40001';
  END IF;
  IF v_guest.status='cancelled' THEN
    RAISE EXCEPTION 'cancelled participation cannot be edited' USING ERRCODE='55000';
  END IF;
  IF v_guest.roster_display_name_override IS DISTINCT FROM v_name THEN
    UPDATE eogp.event_participations
    SET roster_display_name_override=v_name,revision=revision+1,updated_at=clock_timestamp()
    WHERE organization_id=p_org AND event_id=p_event AND id=p_participation RETURNING * INTO v_guest;
    INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,
      action,aggregate_type,aggregate_id,safe_metadata)
    VALUES(p_org,p_org,p_actor,'membership','guest.participation.roster_name_changed','event_participation',p_participation,
      jsonb_build_object('eventId',p_event,'overrideApplied',v_name IS NOT NULL,'revision',v_guest.revision));
  END IF;
  RETURN jsonb_build_object('participationId',p_participation,'revision',v_guest.revision);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.set_event_guest_roster_name(uuid,uuid,uuid,uuid,integer,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.set_event_guest_roster_name(uuid,uuid,uuid,uuid,integer,text) TO eventor_runtime;

CREATE OR REPLACE FUNCTION eogp.read_event_guest_list(
  p_org uuid, p_event uuid, p_actor uuid, p_status text, p_offset integer, p_category uuid, p_unassigned boolean, p_name_query text,
  p_tag uuid, p_group uuid
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_event_status text;
  v_can_manage boolean;
  v_rows jsonb;
  v_name_query text := lower(btrim(coalesce(p_name_query, '')));
BEGIN
  v_can_manage := eogp.assert_event_guest_list_access(p_org, p_event, p_actor);
  SELECT status INTO v_event_status FROM eogp.events WHERE organization_id = p_org AND id = p_event;
  IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002'; END IF;
  IF length(v_name_query) > 200 OR coalesce(p_offset, -1) NOT BETWEEN 0 AND 100000 OR
     (p_status IS NOT NULL AND p_status NOT IN ('eligible', 'waitlisted', 'withdrawn', 'cancelled', 'ineligible')) THEN
    RAISE EXCEPTION 'invalid guest list filter' USING ERRCODE = '22023';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'participationId', p.id, 'displayName', p.display_name, 'status', p.status, 'revision', p.revision,
    'recordedDisplayName', p.recorded_display_name, 'displayNameOverride', p.display_name_override,
    'categoryCode', p.category_code, 'categoryId', p.category_id, 'participationCode', p.participation_code,
    'tagIds', coalesce((
      SELECT jsonb_agg(tag.id ORDER BY tag.id) FROM eogp.event_participation_tags assignment
      JOIN eogp.guest_tags tag ON tag.organization_id = assignment.organization_id
        AND tag.event_id = assignment.event_id AND tag.id = assignment.tag_id
      WHERE assignment.organization_id = p_org AND assignment.event_id = p_event
        AND assignment.participation_id = p.id AND tag.sensitivity = 'internal'
    ), '[]'::jsonb),
    'groupIds', memberships.group_ids, 'groupRoles', memberships.group_roles
  ) ORDER BY lower(p.display_name), p.id), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT * FROM eogp.event_guest_roster_rows guest
    WHERE guest.organization_id = p_org AND guest.event_id = p_event
      AND eogp.guest_roster_matches_name(guest.display_name, guest.snapshot_first_name, guest.snapshot_last_name, v_name_query)
      AND (p_status IS NULL OR guest.status = p_status)
      AND (p_category IS NULL OR guest.category_id = p_category)
      AND (p_unassigned IS DISTINCT FROM true OR guest.category_code IS NULL)
      AND ((p_tag IS NULL AND p_group IS NULL) OR eogp.guest_roster_matches_memberships(p_org,p_event,guest.id,p_tag,p_group))
    ORDER BY lower(guest.display_name), guest.id
    LIMIT 51 OFFSET p_offset
  ) p
  CROSS JOIN LATERAL (
    SELECT coalesce(jsonb_agg(membership.group_id ORDER BY membership.group_id), '[]'::jsonb) AS group_ids,
      coalesce(jsonb_object_agg(membership.group_id, membership.membership_kind), '{}'::jsonb) AS group_roles
    FROM eogp.guest_group_memberships membership
    WHERE membership.organization_id = p_org AND membership.event_id = p_event AND membership.participation_id = p.id
  ) memberships;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id
  ) VALUES (p_org, p_org, p_actor, 'membership', 'guest.event_roster.viewed', 'event', p_event);

  RETURN jsonb_build_object(
    'people', CASE WHEN jsonb_array_length(v_rows) > 50 THEN v_rows - 50 ELSE v_rows END,
    'canViewRelationships', v_can_manage,
    'canManage', v_can_manage AND v_event_status IN ('draft', 'planned', 'scheduled', 'active'),
    'nextOffset', CASE WHEN jsonb_array_length(v_rows) > 50 AND p_offset < 100000 THEN p_offset + 50 END
  );
END;
$function$;
