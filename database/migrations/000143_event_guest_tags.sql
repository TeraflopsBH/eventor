ALTER TABLE eogp.guest_tags ADD COLUMN retired_at timestamptz;
REVOKE ALL ON eogp.guest_tags, eogp.event_participation_tags FROM eventor_runtime;

CREATE FUNCTION eogp.assert_event_guest_list_write(p_org uuid, p_event uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_status text;
BEGIN
  IF nullif(current_setting('app.actor_membership_id', true), '')::uuid IS DISTINCT FROM p_actor THEN
    RAISE EXCEPTION 'staff actor context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_event_command_permission(p_org, p_event, p_actor, 'guest.manage');
  SELECT status INTO v_status FROM eogp.events WHERE organization_id = p_org AND id = p_event FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002'; END IF;
  IF v_status NOT IN ('draft', 'planned', 'scheduled', 'active') THEN
    RAISE EXCEPTION 'event guest list cannot be changed in this phase' USING ERRCODE = '55000';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.assert_event_guest_category_write(p_org uuid, p_event uuid, p_actor uuid)
RETURNS void LANGUAGE sql SET search_path = pg_catalog, eogp
AS $function$
  SELECT eogp.assert_event_guest_list_write(p_org, p_event, p_actor)
$function$;

CREATE FUNCTION eogp.list_event_guest_tags(p_org uuid, p_event uuid, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_tags jsonb;
BEGIN
  IF nullif(current_setting('app.actor_membership_id', true), '')::uuid IS DISTINCT FROM p_actor THEN
    RAISE EXCEPTION 'staff actor context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_event_guest_list_access(p_org, p_event, p_actor);
  IF NOT EXISTS (SELECT 1 FROM eogp.events WHERE organization_id = p_org AND id = p_event) THEN
    RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'tagId', id, 'code', tag_code, 'label', label, 'retired', retired_at IS NOT NULL
  ) ORDER BY retired_at IS NOT NULL, lower(label), tag_code), '[]'::jsonb)
  INTO v_tags FROM eogp.guest_tags WHERE organization_id = p_org AND event_id = p_event AND sensitivity = 'internal';
  RETURN v_tags;
END;
$function$;

CREATE FUNCTION eogp.write_event_guest_tag(p_org uuid, p_event uuid, p_actor uuid, p_tag uuid, p_code text, p_label text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_tag eogp.guest_tags%ROWTYPE;
  v_action text;
BEGIN
  PERFORM eogp.assert_event_guest_list_write(p_org, p_event, p_actor);
  IF p_tag IS NULL THEN
    IF p_code IS NULL OR p_code !~ '^[A-Z0-9][A-Z0-9_-]{0,39}$'
       OR coalesce(length(btrim(p_label)), 0) NOT BETWEEN 1 AND 120 OR p_label ~ '[[:cntrl:]]' THEN
      RAISE EXCEPTION 'invalid guest tag code or label' USING ERRCODE = '22023';
    END IF;
    INSERT INTO eogp.guest_tags (organization_id, event_id, tag_code, label, sensitivity)
    VALUES (p_org, p_event, p_code, btrim(p_label), 'internal') RETURNING * INTO v_tag;
    v_action := 'guest.tag.created';
  ELSE
    UPDATE eogp.guest_tags SET retired_at = clock_timestamp()
    WHERE organization_id = p_org AND event_id = p_event AND id = p_tag AND sensitivity = 'internal' AND retired_at IS NULL
    RETURNING * INTO v_tag;
    IF NOT FOUND THEN
      SELECT * INTO v_tag FROM eogp.guest_tags
      WHERE organization_id = p_org AND event_id = p_event AND id = p_tag AND sensitivity = 'internal';
      IF NOT FOUND THEN RAISE EXCEPTION 'guest tag not found' USING ERRCODE = 'P0002'; END IF;
      RETURN jsonb_build_object('tagId', v_tag.id, 'code', v_tag.tag_code, 'label', v_tag.label, 'retired', true);
    END IF;
    v_action := 'guest.tag.retired';
  END IF;
  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', v_action, 'event_guest_tag', v_tag.id, jsonb_build_object('eventId', p_event)
  );
  RETURN jsonb_build_object('tagId', v_tag.id, 'code', v_tag.tag_code, 'label', v_tag.label, 'retired', v_tag.retired_at IS NOT NULL);
END;
$function$;

CREATE FUNCTION eogp.set_event_guest_tags(p_org uuid, p_event uuid, p_actor uuid, p_participation uuid,
  p_expected_revision integer, p_tag_ids uuid[]
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_participation eogp.event_participations%ROWTYPE;
  v_before uuid[];
  v_after uuid[];
  v_revision integer;
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
  FROM unnest(p_tag_ids) item(id) WHERE id IS NOT NULL;
  IF cardinality(p_tag_ids) IS DISTINCT FROM cardinality(v_after) OR cardinality(v_after) > 1000 THEN
    RAISE EXCEPTION 'invalid event guest tags' USING ERRCODE = '22023';
  END IF;
  SELECT coalesce(array_agg(assignment.tag_id ORDER BY assignment.tag_id), ARRAY[]::uuid[]) INTO v_before
  FROM eogp.event_participation_tags assignment
  JOIN eogp.guest_tags tag ON tag.organization_id = assignment.organization_id
    AND tag.event_id = assignment.event_id AND tag.id = assignment.tag_id
  WHERE assignment.organization_id = p_org AND assignment.event_id = p_event
    AND assignment.participation_id = p_participation AND tag.sensitivity = 'internal';

  IF EXISTS (
    SELECT 1 FROM unnest(v_after) selected(id) WHERE NOT EXISTS (
      SELECT 1 FROM eogp.guest_tags tag WHERE tag.organization_id = p_org AND tag.event_id = p_event
        AND tag.id = selected.id AND tag.sensitivity = 'internal'
        AND (tag.retired_at IS NULL OR tag.id = ANY(v_before))
    )
  ) THEN
    RAISE EXCEPTION 'one or more tags cannot be assigned' USING ERRCODE = '55000';
  END IF;

  v_revision := v_participation.revision;
  IF v_after <> v_before THEN
    DELETE FROM eogp.event_participation_tags
    WHERE organization_id = p_org AND event_id = p_event AND participation_id = p_participation
      AND tag_id = ANY(v_before) AND NOT tag_id = ANY(v_after);
    INSERT INTO eogp.event_participation_tags (organization_id, event_id, participation_id, tag_id, added_by_membership_id)
    SELECT p_org, p_event, p_participation, selected.id, p_actor
    FROM unnest(v_after) selected(id) WHERE NOT selected.id = ANY(v_before);
    UPDATE eogp.event_participations SET revision = revision + 1, updated_at = clock_timestamp()
    WHERE organization_id = p_org AND event_id = p_event AND id = p_participation RETURNING revision INTO v_revision;
    INSERT INTO eogp.audit_events (
      organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
    ) VALUES (
      p_org, p_org, p_actor, 'membership', 'guest.participation.tags_changed', 'event_participation', p_participation,
      jsonb_build_object('eventId', p_event, 'previousTagIds', v_before, 'tagIds', v_after, 'revision', v_revision)
    );
  END IF;
  RETURN jsonb_build_object('participationId', p_participation, 'revision', v_revision, 'tagIds', v_after);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.assert_event_guest_list_write(uuid,uuid,uuid),
  eogp.list_event_guest_tags(uuid,uuid,uuid), eogp.write_event_guest_tag(uuid,uuid,uuid,uuid,text,text),
  eogp.set_event_guest_tags(uuid,uuid,uuid,uuid,integer,uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.list_event_guest_tags(uuid,uuid,uuid), eogp.write_event_guest_tag(uuid,uuid,uuid,uuid,text,text),
  eogp.set_event_guest_tags(uuid,uuid,uuid,uuid,integer,uuid[]) TO eventor_runtime;

CREATE OR REPLACE FUNCTION eogp.read_event_guest_list(
  p_org uuid, p_event uuid, p_actor uuid, p_status text, p_offset integer, p_category uuid, p_unassigned boolean
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_event_status text;
  v_can_manage boolean;
  v_rows jsonb;
BEGIN
  v_can_manage := eogp.assert_event_guest_list_access(p_org, p_event, p_actor);
  SELECT status INTO v_event_status FROM eogp.events WHERE organization_id = p_org AND id = p_event;
  IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002'; END IF;
  IF coalesce(p_offset, -1) NOT BETWEEN 0 AND 100000 OR
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
    ), '[]'::jsonb)
  ) ORDER BY lower(p.display_name), p.id), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT * FROM eogp.event_guest_roster_rows guest
    WHERE guest.organization_id = p_org AND guest.event_id = p_event
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
    'canManage', v_can_manage AND v_event_status IN ('draft', 'planned', 'scheduled', 'active'),
    'nextOffset', CASE WHEN jsonb_array_length(v_rows) > 50 AND p_offset < 100000 THEN p_offset + 50 END
  );
END;
$function$;
