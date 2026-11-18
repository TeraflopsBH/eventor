CREATE FUNCTION eogp.guest_import_commit_input(p_org uuid, p_event uuid, p_actor uuid, p_batch uuid, p_distinct_rows integer[])
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
      AND validation_errors = '[]'::jsonb
      AND (duplicate_candidates = '[]'::jsonb OR row_number = ANY(p_distinct_rows));
  END IF;
  RETURN v_rows;
END;
$function$;

CREATE FUNCTION eogp.commit_reviewed_guest_import(
  p_org uuid, p_event uuid, p_actor uuid, p_batch uuid, p_rows jsonb, p_reuses jsonb, p_distinct_rows integer[]
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_state text;
  v_count integer;
  v_total integer;
  v_input record;
  v_person uuid;
  v_participation uuid;
  v_saved_choices jsonb;
  v_choices jsonb;
  v_person_revision integer;
  v_reused integer := 0;
  v_distinct_rows integer[];
  v_saved_distinct jsonb;
  v_distinct_count integer;
BEGIN
  v_state := eogp.lock_guest_import_batch(p_org, p_event, p_actor, p_batch);
  IF jsonb_typeof(p_reuses) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'invalid import duplicate choices' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_reuses) > 500 THEN
    RAISE EXCEPTION 'too many import duplicate choices' USING ERRCODE = '22023';
  END IF;
  SELECT coalesce(jsonb_agg(choice ORDER BY (choice->>'rowNumber')::integer), '[]'::jsonb)
  INTO v_choices FROM jsonb_array_elements(p_reuses) choice;
  SELECT coalesce(array_agg(DISTINCT selected.row_number ORDER BY selected.row_number), ARRAY[]::integer[])
  INTO v_distinct_rows FROM unnest(p_distinct_rows) AS selected(row_number)
  WHERE selected.row_number BETWEEN 2 AND 1048576;
  IF cardinality(p_distinct_rows) IS DISTINCT FROM cardinality(v_distinct_rows)
    OR cardinality(v_distinct_rows) > 500
    OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_choices) AS choice
      WHERE (choice->>'rowNumber')::integer = ANY(v_distinct_rows)) THEN
    RAISE EXCEPTION 'invalid separate profile choices' USING ERRCODE = '22023';
  END IF;
  SELECT count(*), count(*) FILTER (WHERE committed_participation_id IS NOT NULL)
  INTO v_total, v_count FROM eogp.guest_import_rows
  WHERE organization_id = p_org AND event_id = p_event AND batch_id = p_batch;
  IF v_state = 'committed' THEN
    SELECT coalesce(mapping_snapshot->'reuseChoices', '[]'::jsonb),
      coalesce(mapping_snapshot->'distinctProfileRows', '[]'::jsonb)
    INTO v_saved_choices, v_saved_distinct
    FROM eogp.guest_import_batches WHERE organization_id = p_org AND event_id = p_event AND id = p_batch;
    IF v_saved_choices <> v_choices OR v_saved_distinct <> to_jsonb(v_distinct_rows) THEN
      RAISE EXCEPTION 'import was already committed with different choices' USING ERRCODE = '55000';
    END IF;
    RETURN jsonb_build_object('batchId', p_batch, 'importedCount', v_count, 'skippedCount', v_total - v_count);
  END IF;

  IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'invalid import rows' USING ERRCODE = '22023';
  END IF;
  SELECT count(*) FILTER (WHERE duplicate_candidates = '[]'::jsonb OR row_number = ANY(v_distinct_rows)),
    count(*) FILTER (WHERE duplicate_candidates <> '[]'::jsonb AND row_number = ANY(v_distinct_rows))
  INTO v_count, v_distinct_count FROM eogp.guest_import_rows
  WHERE organization_id = p_org AND event_id = p_event AND batch_id = p_batch AND validation_errors = '[]'::jsonb;
  IF v_distinct_count <> cardinality(v_distinct_rows) THEN
    RAISE EXCEPTION 'separate profiles require valid rows flagged for duplicate review' USING ERRCODE = '55000';
  END IF;
  IF (v_count = 0 AND v_choices = '[]'::jsonb) OR jsonb_array_length(p_rows) <> v_count THEN
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
        AND validation_errors = '[]'::jsonb
        AND (duplicate_candidates = '[]'::jsonb OR row_number = ANY(v_distinct_rows))
        AND normalized_values_ciphertext = decode(v_input."namesCiphertext", 'base64')
    ) THEN
      RAISE EXCEPTION 'import row no longer matches its preview' USING ERRCODE = '40001';
    END IF;
    IF NOT v_input."rowNumber" = ANY(v_distinct_rows)
      AND EXISTS (SELECT 1 FROM eogp.persons WHERE organization_id = p_org AND status = 'active'
         AND lower(first_name) = lower(v_input.names->>'firstName')
         AND lower(last_name) = lower(v_input.names->>'lastName')) THEN
      RAISE EXCEPTION 'a matching profile was added after preview' USING ERRCODE = '40001';
    END IF;

    v_person := (eogp.write_guest_registry_person(p_org, p_actor, NULL, NULL, 'create', v_input.names)->>'personId')::uuid;
    v_participation := (eogp.link_registry_person_to_event(p_org, p_event, p_actor, v_person, 'eligible')->>'participationId')::uuid;
    UPDATE eogp.guest_import_rows SET committed_participation_id = v_participation
    WHERE organization_id = p_org AND event_id = p_event AND batch_id = p_batch AND row_number = v_input."rowNumber";
  END LOOP;

  FOR v_input IN
    SELECT * FROM jsonb_to_recordset(v_choices) AS input("rowNumber" integer, "personId" uuid, "expectedRevision" integer)
    ORDER BY "rowNumber"
  LOOP
    IF NOT EXISTS (SELECT 1 FROM eogp.guest_import_rows WHERE organization_id = p_org AND event_id = p_event
        AND batch_id = p_batch AND row_number = v_input."rowNumber" AND committed_participation_id IS NULL
        AND validation_errors = '[]'::jsonb AND duplicate_candidates ? v_input."personId"::text) THEN
      RAISE EXCEPTION 'profile is not available for this import row' USING ERRCODE = '55000';
    END IF;
    SELECT revision INTO v_person_revision FROM eogp.persons
    WHERE organization_id = p_org AND id = v_input."personId" AND status = 'active' FOR UPDATE;
    IF NOT FOUND OR v_person_revision IS DISTINCT FROM v_input."expectedRevision" THEN
      RAISE EXCEPTION 'matching profile changed since review' USING ERRCODE = '40001';
    END IF;
    IF EXISTS (SELECT 1 FROM eogp.event_participations WHERE organization_id = p_org AND event_id = p_event
        AND person_id = v_input."personId") THEN
      RAISE EXCEPTION 'matching profile already participates in the event' USING ERRCODE = '40001';
    END IF;

    v_participation := (eogp.link_registry_person_to_event(p_org, p_event, p_actor,
      v_input."personId", 'eligible')->>'participationId')::uuid;
    UPDATE eogp.guest_import_rows SET committed_participation_id = v_participation
    WHERE organization_id = p_org AND event_id = p_event AND batch_id = p_batch AND row_number = v_input."rowNumber";
    v_reused := v_reused + 1;
  END LOOP;
  v_count := v_count + v_reused;

  UPDATE eogp.guest_import_batches SET state = 'committed', committed_at = clock_timestamp(),
      mapping_snapshot = mapping_snapshot || jsonb_build_object('reuseChoices', v_choices, 'distinctProfileRows', v_distinct_rows)
  WHERE organization_id = p_org AND event_id = p_event AND id = p_batch;
  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.import.committed', 'guest_import', p_batch,
    jsonb_build_object('eventId', p_event, 'importedCount', v_count, 'reusedCount', v_reused, 'distinctProfileCount', v_distinct_count, 'skippedCount', v_total - v_count)
  );
  RETURN jsonb_build_object('batchId', p_batch, 'importedCount', v_count, 'skippedCount', v_total - v_count);
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.guest_import_commit_input(p_org uuid, p_event uuid, p_actor uuid, p_batch uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
  SELECT eogp.guest_import_commit_input(p_org, p_event, p_actor, p_batch, ARRAY[]::integer[])
$function$;

CREATE OR REPLACE FUNCTION eogp.commit_reviewed_guest_import(
  p_org uuid, p_event uuid, p_actor uuid, p_batch uuid, p_rows jsonb, p_reuses jsonb
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
  SELECT eogp.commit_reviewed_guest_import(p_org, p_event, p_actor, p_batch, p_rows, p_reuses, ARRAY[]::integer[])
$function$;

REVOKE ALL ON FUNCTION eogp.guest_import_commit_input(uuid,uuid,uuid,uuid,integer[]),
  eogp.commit_reviewed_guest_import(uuid,uuid,uuid,uuid,jsonb,jsonb,integer[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.guest_import_commit_input(uuid,uuid,uuid,uuid,integer[]),
  eogp.commit_reviewed_guest_import(uuid,uuid,uuid,uuid,jsonb,jsonb,integer[]) TO eventor_runtime;
