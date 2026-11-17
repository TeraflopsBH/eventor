CREATE OR REPLACE FUNCTION eogp.prepare_guest_import_preview(p_org uuid, p_event uuid, p_actor uuid, p_source_hash text, p_rows jsonb)
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
    IF coalesce(v_input."rowNumber", 0) NOT BETWEEN 2 AND 1048576
       OR jsonb_typeof(v_input.errors) IS DISTINCT FROM 'array'
       OR v_input."sourceCiphertext" IS NULL OR length(v_input."sourceCiphertext") > 25000
       OR v_input."namesCiphertext" IS NULL OR length(v_input."namesCiphertext") > 25000 THEN
      RAISE EXCEPTION 'invalid import row metadata' USING ERRCODE = '22023';
    END IF;
    v_matches := '[]'::jsonb;
    IF NOT (v_input.errors ?| ARRAY['name_required', 'name_invalid', 'column_count', 'cell_not_text']) THEN
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


CREATE FUNCTION eogp.prepare_guest_import_workbook_preview(
  p_org uuid, p_event uuid, p_actor uuid, p_source_hash text, p_rows jsonb, p_sheet_index integer, p_header_row integer
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_batch jsonb;
BEGIN
  IF coalesce(p_sheet_index, 0) NOT BETWEEN 1 AND 32 OR coalesce(p_header_row, 0) NOT BETWEEN 1 AND 1048575 THEN
    RAISE EXCEPTION 'invalid worksheet selection' USING ERRCODE = '22023';
  END IF;
  v_batch := eogp.prepare_guest_import_preview(p_org, p_event, p_actor, p_source_hash, p_rows);
  UPDATE eogp.guest_import_batches
  SET source_filename = 'guest-import.xlsx',
      mapping_snapshot = mapping_snapshot || jsonb_build_object(
        'sourceFormat', 'xlsx', 'sheetIndex', p_sheet_index, 'headerRow', p_header_row
      )
  WHERE organization_id = p_org AND event_id = p_event AND id = (v_batch->>'batchId')::uuid;
  RETURN v_batch;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.prepare_guest_import_workbook_preview(uuid,uuid,uuid,text,jsonb,integer,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.prepare_guest_import_workbook_preview(uuid,uuid,uuid,text,jsonb,integer,integer) TO eventor_runtime;
