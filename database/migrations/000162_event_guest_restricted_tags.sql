INSERT INTO eogp.permissions (code, description, scope_kind, is_sensitive) VALUES
  ('guest.tags.restricted.read', 'Read restricted event guest tags', 'event', true),
  ('guest.tags.restricted.manage', 'Create, retire and assign restricted event guest tags', 'event', true);

ALTER TABLE eogp.guest_tags ADD COLUMN restricted_label_ciphertext bytea
  CHECK (restricted_label_ciphertext IS NULL OR (sensitivity = 'restricted'
    AND octet_length(restricted_label_ciphertext) BETWEEN 33 AND 512
    AND substring(restricted_label_ciphertext from 1 for 4) = convert_to('ECP1', 'UTF8')));

-- Restricted codes occupy a separate namespace so internal tag creation cannot probe them.
ALTER TABLE eogp.guest_tags DROP CONSTRAINT guest_tags_organization_id_event_id_tag_code_key;
CREATE UNIQUE INDEX guest_tags_code_by_visibility
  ON eogp.guest_tags (organization_id, event_id, tag_code, (sensitivity = 'restricted'));

CREATE FUNCTION eogp.assert_restricted_guest_tag_permission(p_org uuid, p_event uuid, p_actor uuid, p_write boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  IF NOT p_write THEN
    BEGIN
      PERFORM eogp.assert_event_command_permission(p_org, p_event, p_actor, 'guest.tags.restricted.read');
      RETURN;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END IF;
  PERFORM eogp.assert_event_command_permission(p_org, p_event, p_actor, 'guest.tags.restricted.manage');
END;
$function$;

CREATE FUNCTION eogp.can_view_restricted_guest_tags(p_org uuid, p_event uuid, p_actor uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  PERFORM eogp.assert_restricted_guest_tag_permission(p_org, p_event, p_actor, false);
  RETURN true;
EXCEPTION WHEN insufficient_privilege THEN RETURN false;
END;
$function$;

CREATE FUNCTION eogp.read_restricted_event_guest_tags(p_org uuid, p_event uuid, p_actor uuid, p_participation uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_event_status text;
  v_can_manage boolean;
  v_participation eogp.event_participations%ROWTYPE;
  v_tags jsonb;
  v_assigned jsonb;
BEGIN
  v_can_manage := eogp.assert_event_guest_list_access(p_org, p_event, p_actor);
  PERFORM eogp.assert_restricted_guest_tag_permission(p_org, p_event, p_actor, false);
  SELECT status INTO v_event_status FROM eogp.events WHERE organization_id = p_org AND id = p_event;
  IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002'; END IF;

  IF v_can_manage THEN
    BEGIN
      PERFORM eogp.assert_restricted_guest_tag_permission(p_org, p_event, p_actor, true);
    EXCEPTION WHEN insufficient_privilege THEN v_can_manage := false;
    END;
  END IF;
  v_can_manage := v_can_manage AND v_event_status IN ('draft', 'planned', 'scheduled', 'active');

  IF p_participation IS NOT NULL THEN
    SELECT * INTO v_participation FROM eogp.event_participations
    WHERE organization_id = p_org AND event_id = p_event AND id = p_participation;
    IF NOT FOUND THEN RAISE EXCEPTION 'participation not found' USING ERRCODE = 'P0002'; END IF;
    v_can_manage := v_can_manage AND v_participation.status <> 'cancelled';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'tagId', tag.id, 'code', tag.tag_code, 'retired', tag.retired_at IS NOT NULL,
    'ciphertext', replace(encode(tag.restricted_label_ciphertext, 'base64'), E'\n', ''),
    'legacyLabel', CASE WHEN tag.restricted_label_ciphertext IS NULL THEN tag.label END
  ) ORDER BY tag.retired_at IS NOT NULL, tag.tag_code), '[]'::jsonb),
  coalesce(jsonb_agg(tag.id ORDER BY tag.id) FILTER (WHERE assigned.tag_id IS NOT NULL), '[]'::jsonb)
  INTO v_tags, v_assigned
  FROM eogp.guest_tags tag
  LEFT JOIN eogp.event_participation_tags assigned
    ON assigned.organization_id = tag.organization_id AND assigned.event_id = tag.event_id
    AND assigned.tag_id = tag.id AND assigned.participation_id = p_participation
  WHERE tag.organization_id = p_org AND tag.event_id = p_event AND tag.sensitivity = 'restricted';

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org,p_org,p_actor,'membership','guest.restricted_tags.viewed',
    CASE WHEN p_participation IS NULL THEN 'event' ELSE 'event_participation' END,
    coalesce(p_participation,p_event),jsonb_build_object('eventId',p_event)
  );
  RETURN jsonb_build_object('tags',v_tags,'assignedTagIds',v_assigned,'revision',v_participation.revision,'canManage',v_can_manage);
END;
$function$;

CREATE FUNCTION eogp.write_restricted_event_guest_tag(
  p_org uuid, p_event uuid, p_actor uuid, p_tag uuid, p_code text, p_ciphertext bytea
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_tag eogp.guest_tags%ROWTYPE;
  v_action text;
BEGIN
  PERFORM eogp.assert_event_guest_list_write(p_org, p_event, p_actor);
  PERFORM eogp.assert_restricted_guest_tag_permission(p_org, p_event, p_actor, true);
  IF p_code IS NOT NULL THEN
    IF p_code !~ '^[A-Z0-9][A-Z0-9_-]{0,39}$' OR p_ciphertext IS NULL THEN
      RAISE EXCEPTION 'invalid restricted guest tag' USING ERRCODE = '22023';
    END IF;
    INSERT INTO eogp.guest_tags(id,organization_id,event_id,tag_code,label,sensitivity,restricted_label_ciphertext)
    VALUES(p_tag,p_org,p_event,p_code,p_code,'restricted',p_ciphertext) RETURNING * INTO v_tag;
    v_action := 'guest.restricted_tag.created';
  ELSE
    UPDATE eogp.guest_tags SET retired_at=clock_timestamp()
    WHERE organization_id=p_org AND event_id=p_event AND id=p_tag AND sensitivity='restricted' AND retired_at IS NULL
    RETURNING * INTO v_tag;
    IF NOT FOUND THEN
      SELECT * INTO v_tag FROM eogp.guest_tags
      WHERE organization_id=p_org AND event_id=p_event AND id=p_tag AND sensitivity='restricted';
      IF NOT FOUND THEN RAISE EXCEPTION 'guest tag not found' USING ERRCODE = 'P0002'; END IF;
      RETURN jsonb_build_object('tagId',v_tag.id,'retired',true);
    END IF;
    v_action := 'guest.restricted_tag.retired';
  END IF;
  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org,p_org,p_actor,'membership',v_action,'event_guest_tag',v_tag.id,jsonb_build_object('eventId',p_event)
  );
  RETURN jsonb_build_object('tagId',v_tag.id,'retired',v_tag.retired_at IS NOT NULL);
END;
$function$;

CREATE FUNCTION eogp.set_event_guest_tags(p_org uuid, p_event uuid, p_actor uuid, p_participation uuid,
  p_expected_revision integer, p_tag_ids uuid[], p_sensitivity text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_participation eogp.event_participations%ROWTYPE;
  v_before uuid[];
  v_after uuid[];
  v_revision integer;
BEGIN
  PERFORM eogp.assert_event_guest_list_write(p_org, p_event, p_actor);
  IF p_sensitivity IS NULL OR p_sensitivity NOT IN ('internal', 'restricted') THEN
    RAISE EXCEPTION 'invalid guest tag classification' USING ERRCODE = '22023';
  END IF;
  IF p_sensitivity = 'restricted' THEN
    PERFORM eogp.assert_restricted_guest_tag_permission(p_org, p_event, p_actor, true);
  END IF;
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
    AND assignment.participation_id = p_participation AND tag.sensitivity = p_sensitivity;

  IF EXISTS (
    SELECT 1 FROM unnest(v_after) selected(id) WHERE NOT EXISTS (
      SELECT 1 FROM eogp.guest_tags tag WHERE tag.organization_id = p_org AND tag.event_id = p_event
        AND tag.id = selected.id AND tag.sensitivity = p_sensitivity
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
      p_org, p_org, p_actor, 'membership', CASE WHEN p_sensitivity = 'restricted' THEN 'guest.participation.restricted_tags_changed'
        ELSE 'guest.participation.tags_changed' END, 'event_participation', p_participation,
      jsonb_build_object('eventId', p_event, 'previousTagIds', v_before, 'tagIds', v_after, 'revision', v_revision)
    );
  END IF;
  RETURN jsonb_build_object('participationId', p_participation, 'revision', v_revision, 'tagIds', v_after);
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.set_event_guest_tags(p_org uuid, p_event uuid, p_actor uuid, p_participation uuid,
  p_expected_revision integer, p_tag_ids uuid[]
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
  SELECT eogp.set_event_guest_tags(p_org, p_event, p_actor, p_participation, p_expected_revision, p_tag_ids, 'internal')
$function$;

REVOKE ALL ON FUNCTION eogp.assert_restricted_guest_tag_permission(uuid,uuid,uuid,boolean),
  eogp.can_view_restricted_guest_tags(uuid,uuid,uuid),
  eogp.read_restricted_event_guest_tags(uuid,uuid,uuid,uuid),
  eogp.write_restricted_event_guest_tag(uuid,uuid,uuid,uuid,text,bytea),
  eogp.set_event_guest_tags(uuid,uuid,uuid,uuid,integer,uuid[],text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.assert_restricted_guest_tag_permission(uuid,uuid,uuid,boolean),
  eogp.can_view_restricted_guest_tags(uuid,uuid,uuid),
  eogp.read_restricted_event_guest_tags(uuid,uuid,uuid,uuid),
  eogp.write_restricted_event_guest_tag(uuid,uuid,uuid,uuid,text,bytea),
  eogp.set_event_guest_tags(uuid,uuid,uuid,uuid,integer,uuid[],text) TO eventor_runtime;
