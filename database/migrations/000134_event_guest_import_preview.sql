REVOKE ALL ON eogp.guest_import_batches, eogp.guest_import_rows FROM eventor_runtime;

CREATE FUNCTION eogp.assert_guest_import_permission(p_org uuid, p_event uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  PERFORM eogp.assert_guest_registry_permission(p_org, p_actor, true);
  PERFORM eogp.assert_event_command_permission(p_org, p_event, p_actor, 'guest.manage');
END;
$function$;

CREATE FUNCTION eogp.prepare_guest_import_preview(p_org uuid, p_event uuid, p_actor uuid, p_source_hash text, p_rows jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_event_status text;
  v_batch uuid;
  v_input record;
  v_matches jsonb;
BEGIN
  PERFORM eogp.assert_guest_import_permission(p_org, p_event, p_actor);
  SELECT status INTO v_event_status FROM eogp.events WHERE organization_id = p_org AND id = p_event FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002'; END IF;
  IF v_event_status NOT IN ('draft', 'planned', 'scheduled', 'active')
     OR NOT EXISTS (SELECT 1 FROM eogp.event_capability_overrides WHERE organization_id = p_org
                    AND event_id = p_event AND capability_code = 'guest_registry' AND enabled) THEN
    RAISE EXCEPTION 'event guest list has not been enabled or is closed' USING ERRCODE = '55000';
  END IF;
  IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'invalid import rows' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_rows) NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION 'invalid import row count' USING ERRCODE = '22023';
  END IF;
  INSERT INTO eogp.guest_import_batches (organization_id, event_id, state, source_filename, source_sha256, mapping_snapshot, created_by_membership_id)
  VALUES (p_org, p_event, 'ready', 'guest-import.csv', p_source_hash, '{"format":"guest-names-csv-v1"}', p_actor)
  RETURNING id INTO v_batch;

  FOR v_input IN
    SELECT * FROM jsonb_to_recordset(p_rows) AS r(
      "rowNumber" integer, "sourceCiphertext" text, "namesCiphertext" text,
      "firstName" text, "lastName" text, errors jsonb
    )
  LOOP
    IF coalesce(v_input."rowNumber", 0) NOT BETWEEN 2 AND 501
       OR jsonb_typeof(v_input.errors) IS DISTINCT FROM 'array'
       OR v_input."sourceCiphertext" IS NULL OR length(v_input."sourceCiphertext") > 25000
       OR v_input."namesCiphertext" IS NULL OR length(v_input."namesCiphertext") > 25000 THEN
      RAISE EXCEPTION 'invalid import row metadata' USING ERRCODE = '22023';
    END IF;
    v_matches := '[]'::jsonb;
    IF NOT (v_input.errors ?| ARRAY['name_required', 'name_invalid', 'column_count']) THEN
      SELECT coalesce(jsonb_agg(candidate.id ORDER BY candidate.id), '[]'::jsonb) INTO v_matches
      FROM (
        SELECT id FROM eogp.persons
        WHERE organization_id = p_org AND status = 'active'
          AND lower(first_name) = lower(v_input."firstName") AND lower(last_name) = lower(v_input."lastName")
        ORDER BY id LIMIT 20
      ) candidate;
    END IF;
    INSERT INTO eogp.guest_import_rows (
      organization_id, event_id, batch_id, row_number, source_values_ciphertext,
      normalized_values_ciphertext, validation_errors, duplicate_candidates
    ) VALUES (
      p_org, p_event, v_batch, v_input."rowNumber", decode(v_input."sourceCiphertext", 'base64'),
      decode(v_input."namesCiphertext", 'base64'), v_input.errors, v_matches
    );
  END LOOP;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.import.previewed', 'guest_import', v_batch,
    jsonb_build_object('eventId', p_event, 'rowCount', jsonb_array_length(p_rows))
  );
  RETURN jsonb_build_object('batchId', v_batch, 'rowCount', jsonb_array_length(p_rows));
END;
$function$;

CREATE FUNCTION eogp.read_guest_import_preview(p_org uuid, p_event uuid, p_actor uuid, p_batch uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_rows jsonb;
BEGIN
  PERFORM eogp.assert_guest_import_permission(p_org, p_event, p_actor);
  IF NOT EXISTS (SELECT 1 FROM eogp.guest_import_batches
    WHERE organization_id = p_org AND event_id = p_event AND id = p_batch AND state = 'ready'
      AND mapping_snapshot->>'format' = 'guest-names-csv-v1') THEN
    RAISE EXCEPTION 'import preview not found' USING ERRCODE = 'P0002';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'rowNumber', row_number,
    'namesCiphertext', replace(encode(normalized_values_ciphertext, 'base64'), E'\n', ''),
    'errors', validation_errors,
    'duplicateCount', jsonb_array_length(duplicate_candidates)
  ) ORDER BY row_number), '[]'::jsonb)
  INTO v_rows FROM eogp.guest_import_rows WHERE organization_id = p_org AND event_id = p_event AND batch_id = p_batch;
  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id
  ) VALUES (p_org, p_org, p_actor, 'membership', 'guest.import.preview_viewed', 'guest_import', p_batch);
  RETURN jsonb_build_object('batchId', p_batch, 'rows', v_rows);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.assert_guest_import_permission(uuid,uuid,uuid),
  eogp.prepare_guest_import_preview(uuid,uuid,uuid,text,jsonb),
  eogp.read_guest_import_preview(uuid,uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.assert_guest_import_permission(uuid,uuid,uuid),
  eogp.prepare_guest_import_preview(uuid,uuid,uuid,text,jsonb),
  eogp.read_guest_import_preview(uuid,uuid,uuid,uuid) TO eventor_runtime;
