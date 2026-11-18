CREATE FUNCTION eogp.set_event_guest_groups(p_org uuid, p_event uuid, p_actor uuid, p_participation uuid,
  p_expected_revision integer, p_group_ids uuid[], p_roles jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_participation eogp.event_participations%ROWTYPE;
  v_before uuid[];
  v_after uuid[];
  v_revision integer;
  v_role_changes integer;
BEGIN
  PERFORM eogp.assert_event_guest_list_write(p_org, p_event, p_actor);
  SELECT * INTO v_participation FROM eogp.event_participations
  WHERE organization_id = p_org AND event_id = p_event AND id = p_participation FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'participation not found' USING ERRCODE = 'P0002'; END IF;
  IF p_expected_revision IS DISTINCT FROM v_participation.revision THEN
    RAISE EXCEPTION 'participation revision conflict' USING ERRCODE = '40001';
  END IF;
  IF v_participation.status = 'cancelled' THEN
    RAISE EXCEPTION 'cancelled participation cannot be edited' USING ERRCODE = '55000';
  END IF;
  SELECT coalesce(array_agg(DISTINCT id ORDER BY id), ARRAY[]::uuid[]) INTO v_after
  FROM unnest(p_group_ids) item(id) WHERE id IS NOT NULL;
  IF cardinality(p_group_ids) IS DISTINCT FROM cardinality(v_after) OR cardinality(v_after) > 1000 THEN
    RAISE EXCEPTION 'invalid event guest groups' USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_roles) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'invalid group roles' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM jsonb_each_text(p_roles) role(group_id, kind)
    WHERE role.group_id <> (role.group_id::uuid)::text OR NOT role.group_id::uuid = ANY(v_after)
      OR role.kind IS NULL OR role.kind NOT IN ('member', 'lead', 'assistant', 'partner', 'security_liaison')
  ) THEN
    RAISE EXCEPTION 'invalid group roles' USING ERRCODE = '22023';
  END IF;
  SELECT coalesce(array_agg(assignment.group_id ORDER BY assignment.group_id), ARRAY[]::uuid[]) INTO v_before
  FROM eogp.guest_group_memberships assignment
  WHERE assignment.organization_id = p_org AND assignment.event_id = p_event
    AND assignment.participation_id = p_participation;

  IF EXISTS (
    SELECT 1 FROM unnest(v_after) selected(id) WHERE NOT EXISTS (
      SELECT 1 FROM eogp.guest_groups guest_group WHERE guest_group.organization_id = p_org AND guest_group.event_id = p_event
        AND guest_group.id = selected.id
        AND (guest_group.retired_at IS NULL OR guest_group.id = ANY(v_before))
    )
  ) THEN
    RAISE EXCEPTION 'one or more groups cannot be assigned' USING ERRCODE = '55000';
  END IF;

  IF EXISTS (
    SELECT 1 FROM eogp.guest_groups guest_group
    WHERE guest_group.organization_id = p_org AND guest_group.event_id = p_event
      AND guest_group.retired_at IS NOT NULL AND p_roles ? guest_group.id::text
  ) THEN
    RAISE EXCEPTION 'retired group roles cannot be changed' USING ERRCODE = '55000';
  END IF;

  v_revision := v_participation.revision;
  IF v_after <> v_before THEN
    DELETE FROM eogp.guest_group_memberships
    WHERE organization_id = p_org AND event_id = p_event AND participation_id = p_participation
      AND group_id = ANY(v_before) AND NOT group_id = ANY(v_after);
    INSERT INTO eogp.guest_group_memberships (organization_id, event_id, participation_id, group_id)
    SELECT p_org, p_event, p_participation, selected.id
    FROM unnest(v_after) selected(id) WHERE NOT selected.id = ANY(v_before);
  END IF;

  UPDATE eogp.guest_group_memberships membership SET membership_kind = role.kind
  FROM jsonb_each_text(p_roles) role(group_id, kind)
  WHERE membership.organization_id = p_org AND membership.event_id = p_event
    AND membership.participation_id = p_participation AND membership.group_id = role.group_id::uuid
    AND membership.membership_kind IS DISTINCT FROM role.kind;
  GET DIAGNOSTICS v_role_changes = ROW_COUNT;
  IF v_after <> v_before OR v_role_changes > 0 THEN
    UPDATE eogp.event_participations SET revision = revision + 1, updated_at = clock_timestamp()
    WHERE organization_id = p_org AND event_id = p_event AND id = p_participation RETURNING revision INTO v_revision;
    INSERT INTO eogp.audit_events (
      organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
    ) VALUES (
      p_org, p_org, p_actor, 'membership', 'guest.participation.groups_changed', 'event_participation', p_participation,
      jsonb_build_object('eventId', p_event, 'previousGroupIds', v_before, 'groupIds', v_after, 'roleChangeCount', v_role_changes, 'revision', v_revision)
    );
  END IF;
  RETURN jsonb_build_object('participationId', p_participation, 'revision', v_revision, 'groupIds', v_after);
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.set_event_guest_groups(
  p_org uuid, p_event uuid, p_actor uuid, p_participation uuid, p_expected_revision integer, p_group_ids uuid[]
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
  SELECT eogp.set_event_guest_groups(p_org, p_event, p_actor, p_participation, p_expected_revision, p_group_ids, '{}'::jsonb)
$function$;

REVOKE ALL ON FUNCTION eogp.set_event_guest_groups(uuid,uuid,uuid,uuid,integer,uuid[],jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.set_event_guest_groups(uuid,uuid,uuid,uuid,integer,uuid[],jsonb) TO eventor_runtime;

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
