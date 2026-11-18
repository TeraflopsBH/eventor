ALTER TABLE eogp.guest_relationships ADD COLUMN retired_at timestamptz;
REVOKE ALL ON eogp.guest_relationships FROM eventor_runtime;
CREATE INDEX guest_relationships_from_guest_idx
  ON eogp.guest_relationships (organization_id, event_id, from_participation_id);
CREATE INDEX guest_relationships_to_guest_idx
  ON eogp.guest_relationships (organization_id, event_id, to_participation_id);

CREATE FUNCTION eogp.assert_event_guest_relationship_access(p_org uuid, p_event uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  IF nullif(current_setting('app.actor_membership_id', true), '')::uuid IS DISTINCT FROM p_actor THEN
    RAISE EXCEPTION 'staff actor context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_event_command_permission(p_org, p_event, p_actor, 'guest.manage');
END;
$function$;

CREATE FUNCTION eogp.read_event_guest_relationships(p_org uuid, p_event uuid, p_actor uuid, p_guest uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_relationships jsonb;
BEGIN
  PERFORM eogp.assert_event_guest_relationship_access(p_org, p_event, p_actor);
  IF NOT EXISTS (SELECT 1 FROM eogp.event_participations WHERE organization_id = p_org AND event_id = p_event AND id = p_guest) THEN
    RAISE EXCEPTION 'participation not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'relationshipId', link.id, 'kind', link.relationship_kind, 'relatedParticipationId', guest.id,
    'relatedDisplayName', guest.display_name, 'retiredAt', link.retired_at,
    'direction', CASE WHEN link.directionality = 'mutual' THEN 'mutual'
      WHEN link.from_participation_id = p_guest THEN 'outgoing' ELSE 'incoming' END
  ) ORDER BY link.retired_at IS NOT NULL, lower(guest.display_name), link.id), '[]'::jsonb) INTO v_relationships
  FROM eogp.guest_relationships link
  JOIN eogp.event_guest_roster_rows guest ON guest.organization_id = link.organization_id AND guest.event_id = link.event_id
    AND guest.id = CASE WHEN link.from_participation_id = p_guest THEN link.to_participation_id ELSE link.from_participation_id END
  WHERE link.organization_id = p_org AND link.event_id = p_event
    AND (link.from_participation_id = p_guest OR link.to_participation_id = p_guest);

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id
  ) VALUES (p_org, p_org, p_actor, 'membership', 'guest.relationships.viewed', 'event_participation', p_guest);
  RETURN v_relationships;
END;
$function$;

CREATE FUNCTION eogp.write_event_guest_relationship(
  p_org uuid, p_event uuid, p_actor uuid, p_guest uuid, p_relationship uuid, p_related uuid, p_kind text, p_directionality text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_link eogp.guest_relationships%ROWTYPE;
  v_kind text := btrim(p_kind);
  v_from uuid;
  v_to uuid;
  v_action text;
  v_guests integer;
BEGIN
  PERFORM eogp.assert_event_guest_list_write(p_org, p_event, p_actor);
  IF p_relationship IS NULL THEN
    IF p_guest IS NULL OR p_related IS NULL OR p_guest = p_related
       OR coalesce(length(v_kind), 0) NOT BETWEEN 1 AND 80 OR v_kind ~ '[[:cntrl:]]'
       OR p_directionality IS NULL OR p_directionality NOT IN ('mutual', 'directed') THEN
      RAISE EXCEPTION 'invalid guest relationship' USING ERRCODE = '22023';
    END IF;
    SELECT count(*) INTO v_guests FROM eogp.event_participations
    WHERE organization_id = p_org AND event_id = p_event AND id IN (p_guest, p_related) AND status <> 'cancelled';
    IF v_guests <> 2 THEN
      RAISE EXCEPTION 'one or both guests are unavailable in this event' USING ERRCODE = 'P0002';
    END IF;

    v_from := CASE WHEN p_directionality = 'mutual' THEN least(p_guest, p_related) ELSE p_guest END;
    v_to := CASE WHEN p_directionality = 'mutual' THEN greatest(p_guest, p_related) ELSE p_related END;
    IF EXISTS (SELECT 1 FROM eogp.guest_relationships
      WHERE organization_id = p_org AND event_id = p_event AND retired_at IS NULL
        AND lower(relationship_kind) = lower(v_kind) AND directionality = p_directionality
        AND ((from_participation_id = v_from AND to_participation_id = v_to)
          OR (p_directionality = 'mutual' AND from_participation_id = v_to AND to_participation_id = v_from))) THEN
      RAISE EXCEPTION 'guest relationship already exists' USING ERRCODE = '55000';
    END IF;

    INSERT INTO eogp.guest_relationships (
      organization_id, event_id, from_participation_id, to_participation_id, relationship_kind, directionality
    ) VALUES (p_org, p_event, v_from, v_to, v_kind, p_directionality) RETURNING * INTO v_link;
    v_action := 'guest.relationship.created';
  ELSE
    SELECT * INTO v_link FROM eogp.guest_relationships
    WHERE organization_id = p_org AND event_id = p_event AND id = p_relationship
      AND (from_participation_id = p_guest OR to_participation_id = p_guest) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'guest relationship not found' USING ERRCODE = 'P0002'; END IF;
    IF v_link.retired_at IS NOT NULL THEN
      RETURN jsonb_build_object('relationshipId', v_link.id, 'retiredAt', v_link.retired_at);
    END IF;
    UPDATE eogp.guest_relationships SET retired_at = clock_timestamp()
    WHERE organization_id = p_org AND event_id = p_event AND id = p_relationship RETURNING * INTO v_link;
    v_action := 'guest.relationship.retired';
  END IF;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', v_action, 'event_guest_relationship', v_link.id,
    jsonb_build_object('eventId', p_event, 'fromParticipationId', v_link.from_participation_id, 'toParticipationId', v_link.to_participation_id)
  );
  RETURN jsonb_build_object('relationshipId', v_link.id, 'retiredAt', v_link.retired_at);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.assert_event_guest_relationship_access(uuid,uuid,uuid),
  eogp.read_event_guest_relationships(uuid,uuid,uuid,uuid),
  eogp.write_event_guest_relationship(uuid,uuid,uuid,uuid,uuid,uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.read_event_guest_relationships(uuid,uuid,uuid,uuid),
  eogp.write_event_guest_relationship(uuid,uuid,uuid,uuid,uuid,uuid,text,text) TO eventor_runtime;

CREATE OR REPLACE FUNCTION eogp.read_event_guest_list(
  p_org uuid, p_event uuid, p_actor uuid, p_status text, p_offset integer, p_category uuid, p_unassigned boolean, p_name_query text
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
    'categoryCode', p.category_code, 'categoryId', p.category_id, 'participationCode', p.participation_code,
    'tagIds', coalesce((
      SELECT jsonb_agg(tag.id ORDER BY tag.id) FROM eogp.event_participation_tags assignment
      JOIN eogp.guest_tags tag ON tag.organization_id = assignment.organization_id
        AND tag.event_id = assignment.event_id AND tag.id = assignment.tag_id
      WHERE assignment.organization_id = p_org AND assignment.event_id = p_event
        AND assignment.participation_id = p.id AND tag.sensitivity = 'internal'
    ), '[]'::jsonb),
    'groupIds', coalesce((
      SELECT jsonb_agg(membership.group_id ORDER BY membership.group_id) FROM eogp.guest_group_memberships membership
      WHERE membership.organization_id = p_org AND membership.event_id = p_event AND membership.participation_id = p.id
    ), '[]'::jsonb)
  ) ORDER BY lower(p.display_name), p.id), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT * FROM eogp.event_guest_roster_rows guest
    WHERE guest.organization_id = p_org AND guest.event_id = p_event
      AND eogp.guest_roster_matches_name(guest.display_name, guest.snapshot_first_name, guest.snapshot_last_name, v_name_query)
      AND (p_status IS NULL OR guest.status = p_status)
      AND (p_category IS NULL OR guest.category_id = p_category)
      AND (p_unassigned IS DISTINCT FROM true OR guest.category_code IS NULL)
    ORDER BY lower(guest.display_name), guest.id
    LIMIT 51 OFFSET p_offset
  ) p;

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
