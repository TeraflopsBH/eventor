ALTER TABLE eogp.guest_groups
  ADD COLUMN parent_group_id uuid,
  ADD COLUMN revision integer NOT NULL DEFAULT 1 CHECK (revision > 0),
  ADD CONSTRAINT guest_group_parent_same_event FOREIGN KEY (organization_id, event_id, parent_group_id)
    REFERENCES eogp.guest_groups(organization_id, event_id, id),
  ADD CONSTRAINT guest_group_parent_not_self CHECK (parent_group_id IS DISTINCT FROM id);

CREATE INDEX guest_groups_parent_idx ON eogp.guest_groups (organization_id, event_id, parent_group_id)
  WHERE parent_group_id IS NOT NULL;

CREATE FUNCTION eogp.event_guest_group_projection(p_group eogp.guest_groups)
RETURNS jsonb LANGUAGE sql STABLE SET search_path = pg_catalog, eogp
AS $function$
  SELECT jsonb_build_object('groupId', p_group.id, 'code', p_group.group_code, 'label', p_group.name,
    'retired', p_group.retired_at IS NOT NULL, 'kind', p_group.group_kind,
    'parentGroupId', p_group.parent_group_id, 'revision', p_group.revision)
$function$;

CREATE FUNCTION eogp.assert_event_guest_group_parent(p_org uuid, p_event uuid, p_group uuid, p_parent uuid)
RETURNS void LANGUAGE plpgsql STABLE SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  IF p_parent IS NULL THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM eogp.guest_groups
    WHERE organization_id = p_org AND event_id = p_event AND id = p_parent AND retired_at IS NULL) THEN
    RAISE EXCEPTION 'parent group is unavailable in this event' USING ERRCODE = '55000';
  END IF;
  IF p_group IS NOT NULL AND EXISTS (
    WITH RECURSIVE ancestry(id, parent_group_id) AS (
      SELECT id, parent_group_id FROM eogp.guest_groups WHERE organization_id = p_org AND event_id = p_event AND id = p_parent
      UNION
      SELECT parent.id, parent.parent_group_id FROM eogp.guest_groups parent
      JOIN ancestry child ON parent.id = child.parent_group_id
      WHERE parent.organization_id = p_org AND parent.event_id = p_event
    ) SELECT 1 FROM ancestry WHERE id = p_group
  ) THEN
    RAISE EXCEPTION 'group parent would create a cycle' USING ERRCODE = '55000';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.list_event_guest_groups(p_org uuid, p_event uuid, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_groups jsonb;
BEGIN
  IF nullif(current_setting('app.actor_membership_id', true), '')::uuid IS DISTINCT FROM p_actor THEN
    RAISE EXCEPTION 'staff actor context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_event_guest_list_access(p_org, p_event, p_actor);
  IF NOT EXISTS (SELECT 1 FROM eogp.events WHERE organization_id = p_org AND id = p_event) THEN
    RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002';
  END IF;
  SELECT coalesce(jsonb_agg(eogp.event_guest_group_projection(guest_group)
    ORDER BY retired_at IS NOT NULL, lower(name), group_code), '[]'::jsonb)
  INTO v_groups FROM eogp.guest_groups guest_group WHERE organization_id = p_org AND event_id = p_event;
  RETURN v_groups;
END;
$function$;

CREATE FUNCTION eogp.write_event_guest_group(p_org uuid, p_event uuid, p_actor uuid, p_group uuid, p_code text, p_label text,
  p_kind text, p_parent uuid)
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
    INSERT INTO eogp.guest_groups (organization_id, event_id, group_code, name, group_kind, parent_group_id)
    VALUES (p_org, p_event, p_code, btrim(p_label), p_kind, p_parent) RETURNING * INTO v_group;
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

CREATE OR REPLACE FUNCTION eogp.write_event_guest_group(
  p_org uuid, p_event uuid, p_actor uuid, p_group uuid, p_code text, p_label text
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
  SELECT eogp.write_event_guest_group(p_org, p_event, p_actor, p_group, p_code, p_label, 'custom', NULL)
$function$;

CREATE FUNCTION eogp.update_event_guest_group(
  p_org uuid, p_event uuid, p_actor uuid, p_group uuid, p_expected_revision integer,
  p_label text, p_kind text, p_parent uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE v_group eogp.guest_groups%ROWTYPE;
        v_kind text;
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
  v_kind := coalesce(p_kind, v_group.group_kind);
  IF (v_group.name, v_group.group_kind, v_group.parent_group_id) IS NOT DISTINCT FROM (btrim(p_label), v_kind, p_parent) THEN
    RETURN eogp.event_guest_group_projection(v_group);
  END IF;
  UPDATE eogp.guest_groups SET name = btrim(p_label), group_kind = v_kind, parent_group_id = p_parent, revision = revision + 1
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

REVOKE ALL ON FUNCTION eogp.event_guest_group_projection(eogp.guest_groups),
  eogp.assert_event_guest_group_parent(uuid,uuid,uuid,uuid),
  eogp.write_event_guest_group(uuid,uuid,uuid,uuid,text,text,text,uuid),
  eogp.update_event_guest_group(uuid,uuid,uuid,uuid,integer,text,text,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.write_event_guest_group(uuid,uuid,uuid,uuid,text,text,text,uuid),
  eogp.update_event_guest_group(uuid,uuid,uuid,uuid,integer,text,text,uuid) TO eventor_runtime;
