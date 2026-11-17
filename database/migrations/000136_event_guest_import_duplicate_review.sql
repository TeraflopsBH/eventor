CREATE OR REPLACE FUNCTION eogp.read_guest_import_preview(p_org uuid, p_event uuid, p_actor uuid, p_batch uuid)
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
    'duplicateCount', jsonb_array_length(duplicate_candidates),
    'matches', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
        'personId', person.id, 'revision', person.revision,
        'name', concat_ws(' ', person.first_name, person.last_name),
        'displayName', person.display_name, 'preferredName', person.preferred_name
      ) ORDER BY person.updated_at DESC, person.id)
      FROM jsonb_array_elements_text(import_row.duplicate_candidates) AS candidate(person_id)
      JOIN eogp.persons person ON person.id = candidate.person_id::uuid
      WHERE person.organization_id = p_org AND person.status = 'active'
        AND import_row.validation_errors = '[]'::jsonb
        AND NOT EXISTS (SELECT 1 FROM eogp.event_participations p
          WHERE p.organization_id = p_org AND p.event_id = p_event AND p.person_id = person.id)
    ), '[]'::jsonb)
  ) ORDER BY row_number), '[]'::jsonb)
  INTO v_rows FROM eogp.guest_import_rows import_row WHERE organization_id = p_org AND event_id = p_event AND batch_id = p_batch;
  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id
  ) VALUES (p_org, p_org, p_actor, 'membership', 'guest.import.preview_viewed', 'guest_import', p_batch);
  RETURN jsonb_build_object('batchId', p_batch, 'rows', v_rows);
END;
$function$;

CREATE FUNCTION eogp.commit_reviewed_guest_import(
  p_org uuid, p_event uuid, p_actor uuid, p_batch uuid, p_rows jsonb, p_reuses jsonb
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
  SELECT count(*), count(*) FILTER (WHERE committed_participation_id IS NOT NULL)
  INTO v_total, v_count FROM eogp.guest_import_rows
  WHERE organization_id = p_org AND event_id = p_event AND batch_id = p_batch;
  IF v_state = 'committed' THEN
    SELECT coalesce(mapping_snapshot->'reuseChoices', '[]'::jsonb) INTO v_saved_choices
    FROM eogp.guest_import_batches WHERE organization_id = p_org AND event_id = p_event AND id = p_batch;
    IF v_saved_choices <> v_choices THEN
      RAISE EXCEPTION 'import was already committed with different choices' USING ERRCODE = '55000';
    END IF;
    RETURN jsonb_build_object('batchId', p_batch, 'importedCount', v_count, 'skippedCount', v_total - v_count);
  END IF;

  IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'invalid import rows' USING ERRCODE = '22023';
  END IF;
  SELECT count(*) INTO v_count FROM eogp.guest_import_rows
  WHERE organization_id = p_org AND event_id = p_event AND batch_id = p_batch
    AND validation_errors = '[]'::jsonb AND duplicate_candidates = '[]'::jsonb;
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
      mapping_snapshot = mapping_snapshot || jsonb_build_object('reuseChoices', v_choices)
  WHERE organization_id = p_org AND event_id = p_event AND id = p_batch;
  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.import.committed', 'guest_import', p_batch,
    jsonb_build_object('eventId', p_event, 'importedCount', v_count, 'reusedCount', v_reused, 'skippedCount', v_total - v_count)
  );
  RETURN jsonb_build_object('batchId', p_batch, 'importedCount', v_count, 'skippedCount', v_total - v_count);
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.commit_clean_guest_import(
  p_org uuid, p_event uuid, p_actor uuid, p_batch uuid, p_rows jsonb
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
  SELECT eogp.commit_reviewed_guest_import(p_org, p_event, p_actor, p_batch, p_rows, '[]'::jsonb)
$function$;

REVOKE ALL ON FUNCTION eogp.commit_reviewed_guest_import(uuid,uuid,uuid,uuid,jsonb,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.commit_reviewed_guest_import(uuid,uuid,uuid,uuid,jsonb,jsonb) TO eventor_runtime;
