CREATE FUNCTION eogp.lock_guest_import_batch(p_org uuid, p_event uuid, p_actor uuid, p_batch uuid)
RETURNS text LANGUAGE plpgsql SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_event_status text;
  v_state text;
BEGIN
  PERFORM eogp.assert_guest_import_permission(p_org, p_event, p_actor);
  SELECT status INTO v_event_status FROM eogp.events WHERE organization_id = p_org AND id = p_event FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002'; END IF;
  SELECT state INTO v_state FROM eogp.guest_import_batches
  WHERE organization_id = p_org AND event_id = p_event AND id = p_batch
    AND mapping_snapshot->>'format' = 'guest-names-csv-v1'
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'import batch not found' USING ERRCODE = 'P0002'; END IF;
  IF v_state = 'committed' THEN RETURN v_state; END IF;
  IF v_state <> 'ready' OR v_event_status NOT IN ('draft', 'planned', 'scheduled', 'active')
     OR NOT EXISTS (SELECT 1 FROM eogp.event_capability_overrides WHERE organization_id = p_org
       AND event_id = p_event AND capability_code = 'guest_registry' AND enabled) THEN
    RAISE EXCEPTION 'import batch or event guest list is no longer open' USING ERRCODE = '55000';
  END IF;
  RETURN v_state;
END;
$function$;

CREATE FUNCTION eogp.guest_import_commit_input(p_org uuid, p_event uuid, p_actor uuid, p_batch uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE v_state text;
        v_rows jsonb := '[]'::jsonb;
BEGIN
  v_state := eogp.lock_guest_import_batch(p_org, p_event, p_actor, p_batch);
  IF v_state = 'ready' THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object('rowNumber', row_number,
      'namesCiphertext', replace(encode(normalized_values_ciphertext, 'base64'), E'\n', ''))
      ORDER BY row_number), '[]'::jsonb)
    INTO v_rows FROM eogp.guest_import_rows
    WHERE organization_id = p_org AND event_id = p_event AND batch_id = p_batch
      AND validation_errors = '[]'::jsonb AND duplicate_candidates = '[]'::jsonb;
  END IF;
  RETURN v_rows;
END;
$function$;

CREATE FUNCTION eogp.commit_clean_guest_import(
  p_org uuid, p_event uuid, p_actor uuid, p_batch uuid, p_rows jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_state text;
  v_count integer;
  v_total integer;
  v_input record;
  v_person uuid;
  v_participation uuid;
BEGIN
  v_state := eogp.lock_guest_import_batch(p_org, p_event, p_actor, p_batch);
  SELECT count(*), count(*) FILTER (WHERE committed_participation_id IS NOT NULL)
  INTO v_total, v_count FROM eogp.guest_import_rows
  WHERE organization_id = p_org AND event_id = p_event AND batch_id = p_batch;
  IF v_state = 'committed' THEN
    RETURN jsonb_build_object('batchId', p_batch, 'importedCount', v_count, 'skippedCount', v_total - v_count);
  END IF;

  IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'invalid import rows' USING ERRCODE = '22023';
  END IF;
  SELECT count(*) INTO v_count FROM eogp.guest_import_rows
  WHERE organization_id = p_org AND event_id = p_event AND batch_id = p_batch
    AND validation_errors = '[]'::jsonb AND duplicate_candidates = '[]'::jsonb;
  IF v_count = 0 OR jsonb_array_length(p_rows) <> v_count THEN
    RAISE EXCEPTION 'import has no clean rows or its preview changed' USING ERRCODE = '55000';
  END IF;

  -- Serialize import duplicate checks across events in the same organization.
  PERFORM pg_advisory_xact_lock(hashtextextended('guest-import:' || p_org::text, 0));
  FOR v_input IN
    SELECT * FROM jsonb_to_recordset(p_rows) AS input("rowNumber" integer, "namesCiphertext" text, names jsonb)
    ORDER BY "rowNumber"
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM eogp.guest_import_rows
      WHERE organization_id = p_org AND event_id = p_event AND batch_id = p_batch
        AND row_number = v_input."rowNumber" AND committed_participation_id IS NULL
        AND validation_errors = '[]'::jsonb AND duplicate_candidates = '[]'::jsonb
        AND normalized_values_ciphertext = decode(v_input."namesCiphertext", 'base64')
    ) THEN
      RAISE EXCEPTION 'import row no longer matches its preview' USING ERRCODE = '40001';
    END IF;
    IF EXISTS (SELECT 1 FROM eogp.persons WHERE organization_id = p_org AND status = 'active'
         AND lower(first_name) = lower(v_input.names->>'firstName')
         AND lower(last_name) = lower(v_input.names->>'lastName')) THEN
      RAISE EXCEPTION 'a matching profile was added after preview' USING ERRCODE = '40001';
    END IF;

    v_person := (eogp.write_guest_registry_person(p_org, p_actor, NULL, NULL, 'create', v_input.names)->>'personId')::uuid;
    v_participation := (eogp.link_registry_person_to_event(p_org, p_event, p_actor, v_person, 'eligible')->>'participationId')::uuid;
    UPDATE eogp.guest_import_rows SET committed_participation_id = v_participation
    WHERE organization_id = p_org AND event_id = p_event AND batch_id = p_batch AND row_number = v_input."rowNumber";
  END LOOP;

  UPDATE eogp.guest_import_batches SET state = 'committed', committed_at = clock_timestamp()
  WHERE organization_id = p_org AND event_id = p_event AND id = p_batch;
  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.import.committed', 'guest_import', p_batch,
    jsonb_build_object('eventId', p_event, 'importedCount', v_count, 'skippedCount', v_total - v_count)
  );
  RETURN jsonb_build_object('batchId', p_batch, 'importedCount', v_count, 'skippedCount', v_total - v_count);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.lock_guest_import_batch(uuid,uuid,uuid,uuid),
  eogp.guest_import_commit_input(uuid,uuid,uuid,uuid),
  eogp.commit_clean_guest_import(uuid,uuid,uuid,uuid,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.guest_import_commit_input(uuid,uuid,uuid,uuid),
  eogp.commit_clean_guest_import(uuid,uuid,uuid,uuid,jsonb) TO eventor_runtime;
