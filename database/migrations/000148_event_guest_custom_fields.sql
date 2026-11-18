REVOKE ALL ON eogp.guest_custom_field_definitions, eogp.guest_custom_field_values FROM eventor_runtime;

ALTER FUNCTION eogp.assert_event_guest_relationship_access(uuid,uuid,uuid) RENAME TO assert_event_guest_detail_access;

CREATE FUNCTION eogp.assert_event_guest_relationship_access(p_org uuid, p_event uuid, p_actor uuid)
RETURNS void LANGUAGE sql SET search_path = pg_catalog, eogp
AS $function$
  SELECT eogp.assert_event_guest_detail_access(p_org, p_event, p_actor)
$function$;
REVOKE ALL ON FUNCTION eogp.assert_event_guest_relationship_access(uuid,uuid,uuid) FROM PUBLIC;

CREATE FUNCTION eogp.list_event_guest_field_definitions(p_org uuid, p_event uuid, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE v_result jsonb;
BEGIN
  PERFORM eogp.assert_event_guest_detail_access(p_org, p_event, p_actor);
  IF NOT EXISTS (SELECT 1 FROM eogp.events WHERE organization_id = p_org AND id = p_event) THEN
    RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'fieldId', id, 'code', field_code, 'label', label, 'valueType', value_schema->>'type', 'retired', status = 'retired'
  ) ORDER BY status, lower(label), field_code), '[]'::jsonb) INTO v_result
  FROM eogp.guest_custom_field_definitions WHERE organization_id = p_org AND event_id = p_event
    AND sensitivity = 'internal' AND value_schema->>'format' = 'eventor-scalar-v1';
  RETURN v_result;
END;
$function$;

CREATE FUNCTION eogp.write_event_guest_field_definition(
  p_org uuid, p_event uuid, p_actor uuid, p_field uuid, p_code text, p_label text, p_type text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_field eogp.guest_custom_field_definitions%ROWTYPE;
  v_action text;
BEGIN
  PERFORM eogp.assert_event_guest_list_write(p_org, p_event, p_actor);
  IF p_field IS NULL THEN
    IF p_code IS NULL OR p_code !~ '^[A-Z0-9][A-Z0-9_-]{0,39}$'
       OR coalesce(length(btrim(p_label)), 0) NOT BETWEEN 1 AND 120 OR p_label ~ '[[:cntrl:]]'
       OR p_type IS NULL OR p_type NOT IN ('text', 'integer', 'boolean') THEN
      RAISE EXCEPTION 'invalid guest field definition' USING ERRCODE = '22023';
    END IF;
    INSERT INTO eogp.guest_custom_field_definitions (organization_id, event_id, field_code, label, value_schema, sensitivity)
    VALUES (p_org, p_event, p_code, btrim(p_label), jsonb_build_object('format', 'eventor-scalar-v1', 'type', p_type), 'internal')
    RETURNING * INTO v_field;
    v_action := 'guest.field.created';
  ELSE
    SELECT * INTO v_field FROM eogp.guest_custom_field_definitions WHERE organization_id = p_org AND event_id = p_event
      AND id = p_field AND sensitivity = 'internal' AND value_schema->>'format' = 'eventor-scalar-v1';
    IF NOT FOUND THEN RAISE EXCEPTION 'guest field not found' USING ERRCODE = 'P0002'; END IF;
    IF v_field.status <> 'retired' THEN
      UPDATE eogp.guest_custom_field_definitions SET status = 'retired'
      WHERE organization_id = p_org AND event_id = p_event AND id = p_field RETURNING * INTO v_field;
      v_action := 'guest.field.retired';
    END IF;
  END IF;

  IF v_action IS NOT NULL THEN
    INSERT INTO eogp.audit_events (
      organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
    ) VALUES (
      p_org, p_org, p_actor, 'membership', v_action, 'event_guest_field', v_field.id,
      jsonb_build_object('eventId', p_event)
    );
  END IF;
  RETURN jsonb_build_object('fieldId', v_field.id, 'code', v_field.field_code, 'label', v_field.label,
    'valueType', v_field.value_schema->>'type', 'retired', v_field.status = 'retired');
END;
$function$;

CREATE FUNCTION eogp.read_event_guest_field_values(p_org uuid, p_event uuid, p_actor uuid, p_guest uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE v_result jsonb;
BEGIN
  PERFORM eogp.assert_event_guest_detail_access(p_org, p_event, p_actor);
  SELECT jsonb_build_object('revision', guest.revision, 'fields', coalesce((
    SELECT jsonb_agg(jsonb_build_object(
      'fieldId', field.id, 'code', field.field_code, 'label', field.label, 'valueType', field.value_schema->>'type',
      'retired', field.status = 'retired', 'ciphertext', replace(encode(value.value_ciphertext, 'base64'), E'\n', '')
    ) ORDER BY field.status, lower(field.label), field.field_code)
    FROM eogp.guest_custom_field_definitions field
    LEFT JOIN eogp.guest_custom_field_values value ON value.organization_id = field.organization_id AND value.event_id = field.event_id
      AND value.field_definition_id = field.id AND value.participation_id = guest.id
    WHERE field.organization_id = p_org AND field.event_id = p_event AND field.sensitivity = 'internal'
      AND field.value_schema->>'format' = 'eventor-scalar-v1' AND (field.status = 'active' OR value.id IS NOT NULL)
  ), '[]'::jsonb)) INTO v_result FROM eogp.event_participations guest
  WHERE guest.organization_id = p_org AND guest.event_id = p_event AND guest.id = p_guest;
  IF NOT FOUND THEN RAISE EXCEPTION 'participation not found' USING ERRCODE = 'P0002'; END IF;
  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id
  ) VALUES (p_org, p_org, p_actor, 'membership', 'guest.fields.viewed', 'event_participation', p_guest);
  RETURN v_result;
END;
$function$;

CREATE FUNCTION eogp.read_event_guest_field_type(p_org uuid, p_event uuid, p_actor uuid, p_field uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE v_type text;
BEGIN
  PERFORM eogp.assert_event_guest_detail_access(p_org, p_event, p_actor);
  SELECT value_schema->>'type' INTO v_type FROM eogp.guest_custom_field_definitions
  WHERE organization_id = p_org AND event_id = p_event AND id = p_field AND sensitivity = 'internal'
    AND value_schema->>'format' = 'eventor-scalar-v1';
  IF NOT FOUND THEN RAISE EXCEPTION 'guest field not found' USING ERRCODE = 'P0002'; END IF;
  RETURN v_type;
END;
$function$;

CREATE FUNCTION eogp.write_event_guest_field_value(p_org uuid, p_event uuid, p_actor uuid, p_guest uuid, p_field uuid,
  p_expected_revision integer, p_type text, p_ciphertext bytea
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_guest eogp.event_participations%ROWTYPE;
  v_field eogp.guest_custom_field_definitions%ROWTYPE;
  v_changed boolean;
  v_revision integer;
BEGIN
  PERFORM eogp.assert_event_guest_list_write(p_org, p_event, p_actor);
  SELECT * INTO v_guest FROM eogp.event_participations
  WHERE organization_id = p_org AND event_id = p_event AND id = p_guest FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'participation not found' USING ERRCODE = 'P0002'; END IF;
  IF p_expected_revision IS DISTINCT FROM v_guest.revision THEN
    RAISE EXCEPTION 'participation revision conflict' USING ERRCODE = '40001';
  END IF;
  IF v_guest.status = 'cancelled' THEN RAISE EXCEPTION 'cancelled participation cannot be edited' USING ERRCODE = '55000'; END IF;
  SELECT * INTO v_field FROM eogp.guest_custom_field_definitions WHERE organization_id = p_org AND event_id = p_event
    AND id = p_field AND sensitivity = 'internal' AND value_schema->>'format' = 'eventor-scalar-v1';
  IF NOT FOUND THEN RAISE EXCEPTION 'guest field not found' USING ERRCODE = 'P0002'; END IF;
  IF p_ciphertext IS NULL THEN
    DELETE FROM eogp.guest_custom_field_values WHERE organization_id = p_org AND event_id = p_event
      AND participation_id = p_guest AND field_definition_id = p_field;
    v_changed := FOUND;
  ELSE
    IF v_field.status <> 'active' THEN RAISE EXCEPTION 'guest field has retired' USING ERRCODE = '55000'; END IF;
    IF p_type IS DISTINCT FROM v_field.value_schema->>'type' OR octet_length(p_ciphertext) NOT BETWEEN 33 AND 4096
       OR substring(p_ciphertext FROM 1 FOR 4) <> convert_to('ECP1', 'UTF8') THEN
      RAISE EXCEPTION 'invalid protected guest field value' USING ERRCODE = '22023';
    END IF;
    INSERT INTO eogp.guest_custom_field_values (
      organization_id, event_id, participation_id, field_definition_id, value_ciphertext, updated_by_membership_id
    ) VALUES (p_org, p_event, p_guest, p_field, p_ciphertext, p_actor)
    ON CONFLICT (organization_id, participation_id, field_definition_id)
    DO UPDATE SET value_ciphertext = excluded.value_ciphertext, updated_by_membership_id = excluded.updated_by_membership_id,
      updated_at = clock_timestamp();
    v_changed := true;
  END IF;

  v_revision := v_guest.revision;
  IF v_changed THEN
    UPDATE eogp.event_participations SET revision = revision + 1, updated_at = clock_timestamp()
    WHERE organization_id = p_org AND event_id = p_event AND id = p_guest RETURNING revision INTO v_revision;
    INSERT INTO eogp.audit_events (
      organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
    ) VALUES (
      p_org, p_org, p_actor, 'membership', 'guest.field.changed', 'event_participation', p_guest,
      jsonb_build_object('eventId', p_event, 'fieldId', p_field, 'cleared', p_ciphertext IS NULL, 'revision', v_revision)
    );
  END IF;
  RETURN jsonb_build_object('participationId', p_guest, 'revision', v_revision, 'fieldId', p_field);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.list_event_guest_field_definitions(uuid,uuid,uuid),
  eogp.write_event_guest_field_definition(uuid,uuid,uuid,uuid,text,text,text),
  eogp.read_event_guest_field_values(uuid,uuid,uuid,uuid), eogp.read_event_guest_field_type(uuid,uuid,uuid,uuid),
  eogp.write_event_guest_field_value(uuid,uuid,uuid,uuid,uuid,integer,text,bytea) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.list_event_guest_field_definitions(uuid,uuid,uuid),
  eogp.write_event_guest_field_definition(uuid,uuid,uuid,uuid,text,text,text),
  eogp.read_event_guest_field_values(uuid,uuid,uuid,uuid), eogp.read_event_guest_field_type(uuid,uuid,uuid,uuid),
  eogp.write_event_guest_field_value(uuid,uuid,uuid,uuid,uuid,integer,text,bytea) TO eventor_runtime;
