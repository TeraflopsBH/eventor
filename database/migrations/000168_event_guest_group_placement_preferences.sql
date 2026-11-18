ALTER TABLE eogp.guest_groups
  ADD COLUMN placement_preference text CHECK (placement_preference IN ('same_table','same_zone','nearby','separate')),
  ADD COLUMN expected_size integer CHECK (expected_size > 0);

CREATE OR REPLACE FUNCTION eogp.event_guest_group_projection(p_group eogp.guest_groups)
RETURNS jsonb LANGUAGE sql STABLE SET search_path = pg_catalog, eogp
AS $function$
  SELECT jsonb_build_object('groupId', p_group.id, 'code', p_group.group_code, 'label', p_group.name,
    'retired', p_group.retired_at IS NOT NULL, 'kind', p_group.group_kind,
    'parentGroupId', p_group.parent_group_id, 'revision', p_group.revision,
    'placementPreference', p_group.placement_preference, 'expectedSize', p_group.expected_size)
$function$;

CREATE FUNCTION eogp.write_event_guest_group(p_org uuid, p_event uuid, p_actor uuid, p_group uuid, p_code text, p_label text,
  p_kind text, p_parent uuid, p_placement text, p_size integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_group eogp.guest_groups%ROWTYPE;
  v_action text;
BEGIN
  PERFORM eogp.assert_event_guest_list_write(p_org, p_event, p_actor);
  IF p_group IS NULL THEN
    IF p_code IS NULL OR p_code !~ '^[A-Z0-9][A-Z0-9_-]{0,39}$'
       OR coalesce(length(btrim(p_label)), 0) NOT BETWEEN 1 AND 120 OR p_label ~ '[[:cntrl:]]' THEN
      RAISE EXCEPTION 'invalid guest group code or label' USING ERRCODE = '22023';
    END IF;
    IF p_kind IS NULL OR p_kind NOT IN ('custom', 'family', 'couple', 'delegation', 'official_party', 'team', 'organization') THEN
      RAISE EXCEPTION 'invalid guest group type' USING ERRCODE = '22023';
    END IF;
    PERFORM eogp.assert_event_guest_group_parent(p_org, p_event, NULL, p_parent);
    INSERT INTO eogp.guest_groups (organization_id, event_id, group_code, name, group_kind, parent_group_id, placement_preference, expected_size)
    VALUES (p_org, p_event, p_code, btrim(p_label), p_kind, p_parent, p_placement, p_size) RETURNING * INTO v_group;
    v_action := 'guest.group.created';
  ELSE
    UPDATE eogp.guest_groups SET retired_at = clock_timestamp(), revision = revision + 1
    WHERE organization_id = p_org AND event_id = p_event AND id = p_group AND retired_at IS NULL
    RETURNING * INTO v_group;
    IF NOT FOUND THEN
      SELECT * INTO v_group FROM eogp.guest_groups
      WHERE organization_id = p_org AND event_id = p_event AND id = p_group;
      IF NOT FOUND THEN RAISE EXCEPTION 'guest group not found' USING ERRCODE = 'P0002'; END IF;
      RETURN eogp.event_guest_group_projection(v_group);
    END IF;
    v_action := 'guest.group.retired';
  END IF;
  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', v_action, 'event_guest_group', v_group.id, jsonb_build_object('eventId', p_event)
  );
  RETURN eogp.event_guest_group_projection(v_group);
END;
$function$;

CREATE FUNCTION eogp.update_event_guest_group(
  p_org uuid, p_event uuid, p_actor uuid, p_group uuid, p_expected_revision integer,
  p_label text, p_kind text, p_parent uuid, p_preferences jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE v_group eogp.guest_groups%ROWTYPE;
        v_kind text;
        v_placement text;
        v_size integer;
BEGIN
  -- The event write lock serializes reparenting and retirement in this event.
  PERFORM eogp.assert_event_guest_list_write(p_org, p_event, p_actor);
  SELECT * INTO v_group FROM eogp.guest_groups
  WHERE organization_id = p_org AND event_id = p_event AND id = p_group FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'guest group not found' USING ERRCODE = 'P0002'; END IF;
  IF v_group.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'guest group revision conflict' USING ERRCODE = '40001';
  END IF;
  IF v_group.retired_at IS NOT NULL THEN
    RAISE EXCEPTION 'retired guest group cannot be edited' USING ERRCODE = '55000';
  END IF;
  IF coalesce(length(btrim(p_label)), 0) NOT BETWEEN 1 AND 120 OR p_label ~ '[[:cntrl:]]'
    OR (p_kind IS NOT NULL AND p_kind NOT IN ('custom', 'family', 'couple', 'delegation', 'official_party', 'team', 'organization')) THEN
    RAISE EXCEPTION 'invalid guest group label or type' USING ERRCODE = '22023';
  END IF;
  IF p_parent IS DISTINCT FROM v_group.parent_group_id THEN
    PERFORM eogp.assert_event_guest_group_parent(p_org, p_event, p_group, p_parent);
  END IF;
  IF jsonb_typeof(p_preferences) IS DISTINCT FROM 'object'
    OR EXISTS (SELECT 1 FROM jsonb_each(p_preferences) setting
      WHERE setting.key NOT IN ('placementPreference','expectedSize')
        OR (setting.key = 'placementPreference' AND jsonb_typeof(setting.value) NOT IN ('string','null'))
        OR (setting.key = 'expectedSize' AND jsonb_typeof(setting.value) <> 'null' AND setting.value::text !~ '^[0-9]+$')) THEN
    RAISE EXCEPTION 'invalid guest group placement preferences' USING ERRCODE='22023';
  END IF;
  v_kind := coalesce(p_kind, v_group.group_kind);
  v_placement := CASE WHEN p_preferences ? 'placementPreference' THEN p_preferences->>'placementPreference'
    ELSE v_group.placement_preference END;
  v_size := CASE WHEN p_preferences ? 'expectedSize' THEN (p_preferences->>'expectedSize')::integer
    ELSE v_group.expected_size END;
  IF (v_group.name, v_group.group_kind, v_group.parent_group_id, v_group.placement_preference, v_group.expected_size)
    IS NOT DISTINCT FROM (btrim(p_label), v_kind, p_parent, v_placement, v_size) THEN
    RETURN eogp.event_guest_group_projection(v_group);
  END IF;
  UPDATE eogp.guest_groups SET name = btrim(p_label), group_kind = v_kind, parent_group_id = p_parent,
    placement_preference = v_placement, expected_size = v_size, revision = revision + 1
  WHERE organization_id = p_org AND event_id = p_event AND id = p_group RETURNING * INTO v_group;
  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.group.updated', 'event_guest_group', p_group,
    jsonb_build_object('eventId', p_event, 'revision', v_group.revision)
  );
  RETURN eogp.event_guest_group_projection(v_group);
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.write_event_guest_group(
  p_org uuid,p_event uuid,p_actor uuid,p_group uuid,p_code text,p_label text,p_kind text,p_parent uuid
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
  SELECT eogp.write_event_guest_group(p_org,p_event,p_actor,p_group,p_code,p_label,p_kind,p_parent,NULL,NULL)
$function$;

CREATE OR REPLACE FUNCTION eogp.update_event_guest_group(
  p_org uuid,p_event uuid,p_actor uuid,p_group uuid,p_expected_revision integer,p_label text,p_kind text,p_parent uuid
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
  SELECT eogp.update_event_guest_group(p_org,p_event,p_actor,p_group,p_expected_revision,p_label,p_kind,p_parent,'{}'::jsonb)
$function$;

REVOKE ALL ON FUNCTION eogp.write_event_guest_group(uuid,uuid,uuid,uuid,text,text,text,uuid,text,integer),
  eogp.update_event_guest_group(uuid,uuid,uuid,uuid,integer,text,text,uuid,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.write_event_guest_group(uuid,uuid,uuid,uuid,text,text,text,uuid,text,integer),
  eogp.update_event_guest_group(uuid,uuid,uuid,uuid,integer,text,text,uuid,jsonb) TO eventor_runtime;
