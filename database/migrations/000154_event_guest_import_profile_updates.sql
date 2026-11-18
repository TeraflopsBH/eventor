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
    'matches', candidates.linkable,
    'updateMatches', candidates.updatable
  ) ORDER BY row_number), '[]'::jsonb)
  INTO v_rows FROM eogp.guest_import_rows import_row
  CROSS JOIN LATERAL (
    SELECT coalesce(jsonb_agg(match.profile ORDER BY match.updated_at DESC, match.id)
             FILTER (WHERE NOT match.on_event), '[]'::jsonb) AS linkable,
           coalesce(jsonb_agg(match.profile || jsonb_build_object(
             'firstName', match.first_name, 'lastName', match.last_name, 'onEvent', match.on_event
           ) ORDER BY match.updated_at DESC, match.id), '[]'::jsonb) AS updatable
    FROM (
      SELECT person.id, person.first_name, person.last_name, person.updated_at,
        jsonb_build_object(
          'personId', person.id, 'revision', person.revision,
          'name', concat_ws(' ', person.first_name, person.last_name),
          'displayName', person.display_name, 'preferredName', person.preferred_name
        ) AS profile,
        EXISTS (SELECT 1 FROM eogp.event_participations p
          WHERE p.organization_id = p_org AND p.event_id = p_event AND p.person_id = person.id) AS on_event
      FROM jsonb_array_elements_text(import_row.duplicate_candidates) AS candidate(person_id)
      JOIN eogp.persons person ON person.id = candidate.person_id::uuid
      WHERE person.organization_id = p_org AND person.status = 'active'
        AND import_row.validation_errors = '[]'::jsonb
    ) match
  ) candidates
  WHERE import_row.organization_id = p_org AND import_row.event_id = p_event AND import_row.batch_id = p_batch;
  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id
  ) VALUES (p_org, p_org, p_actor, 'membership', 'guest.import.preview_viewed', 'guest_import', p_batch);
  RETURN jsonb_build_object('batchId', p_batch, 'rows', v_rows);
END;
$function$;

CREATE FUNCTION eogp.commit_reviewed_guest_import(
  p_org uuid, p_event uuid, p_actor uuid, p_batch uuid, p_rows jsonb, p_reuses jsonb, p_distinct_rows integer[],
  p_updates jsonb
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
  v_updated_count integer;
  v_updates jsonb;
  v_saved_updates jsonb;
  v_update_rows integer[];
  v_update jsonb;
  v_profile eogp.persons%ROWTYPE;
  v_names jsonb;
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
  IF jsonb_typeof(p_updates) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'invalid import update choices' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_updates) > 500 THEN
    RAISE EXCEPTION 'too many import update choices' USING ERRCODE = '22023';
  END IF;
  SELECT coalesce(jsonb_agg(choice ORDER BY (choice->>'rowNumber')::integer), '[]'::jsonb),
    coalesce(array_agg((choice->>'rowNumber')::integer), ARRAY[]::integer[])
  INTO v_updates, v_update_rows
  FROM jsonb_array_elements(p_updates) choice;
  IF v_update_rows && v_distinct_rows OR EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_updates || v_choices) choice
    GROUP BY (choice->>'rowNumber')::integer HAVING count(*) > 1 OR (choice->>'rowNumber')::integer IS NULL
  ) OR EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_updates || v_choices) choice
    GROUP BY (choice->>'personId')::uuid HAVING count(*) > 1 OR (choice->>'personId')::uuid IS NULL
  ) THEN
    RAISE EXCEPTION 'choose a single action per import row and profile' USING ERRCODE = '22023';
  END IF;
  SELECT count(*), count(*) FILTER (WHERE committed_participation_id IS NOT NULL)
  INTO v_total, v_count FROM eogp.guest_import_rows
  WHERE organization_id = p_org AND event_id = p_event AND batch_id = p_batch;
  IF v_state = 'committed' THEN
    SELECT coalesce(mapping_snapshot->'reuseChoices', '[]'::jsonb),
      coalesce(mapping_snapshot->'distinctProfileRows', '[]'::jsonb),
      coalesce(mapping_snapshot->'updateChoices', '[]'::jsonb)
    INTO v_saved_choices, v_saved_distinct, v_saved_updates
    FROM eogp.guest_import_batches WHERE organization_id = p_org AND event_id = p_event AND id = p_batch;
    IF v_saved_choices <> v_choices OR v_saved_distinct <> to_jsonb(v_distinct_rows)
      OR v_saved_updates <> v_updates THEN
      RAISE EXCEPTION 'import was already committed with different choices' USING ERRCODE = '55000';
    END IF;
    RETURN jsonb_build_object('batchId', p_batch, 'importedCount', v_count, 'skippedCount', v_total - v_count);
  END IF;

  IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'invalid import rows' USING ERRCODE = '22023';
  END IF;
  SELECT count(*) FILTER (WHERE duplicate_candidates = '[]'::jsonb OR row_number = ANY(v_distinct_rows || v_update_rows)),
    count(*) FILTER (WHERE duplicate_candidates <> '[]'::jsonb AND row_number = ANY(v_distinct_rows)),
    count(*) FILTER (WHERE duplicate_candidates <> '[]'::jsonb AND row_number = ANY(v_update_rows))
  INTO v_count, v_distinct_count, v_updated_count FROM eogp.guest_import_rows
  WHERE organization_id = p_org AND event_id = p_event AND batch_id = p_batch AND validation_errors = '[]'::jsonb;
  IF v_distinct_count <> cardinality(v_distinct_rows) THEN
    RAISE EXCEPTION 'separate profiles require valid rows flagged for duplicate review' USING ERRCODE = '55000';
  END IF;
  IF v_updated_count <> cardinality(v_update_rows) THEN
    RAISE EXCEPTION 'profile updates require valid rows flagged for duplicate review' USING ERRCODE = '55000';
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
        AND (duplicate_candidates = '[]'::jsonb OR row_number = ANY(v_distinct_rows || v_update_rows))
        AND normalized_values_ciphertext = decode(v_input."namesCiphertext", 'base64')
    ) THEN
      RAISE EXCEPTION 'import row no longer matches its preview' USING ERRCODE = '40001';
    END IF;
    IF v_input."rowNumber" = ANY(v_update_rows) THEN
      SELECT choice INTO v_update FROM jsonb_array_elements(v_updates) choice
      WHERE (choice->>'rowNumber')::integer = v_input."rowNumber";
      v_person := (v_update->>'personId')::uuid;
      IF NOT EXISTS (SELECT 1 FROM eogp.guest_import_rows
        WHERE organization_id = p_org AND event_id = p_event AND batch_id = p_batch
          AND row_number = v_input."rowNumber" AND duplicate_candidates ? v_person::text) THEN
        RAISE EXCEPTION 'profile is not available for this import row' USING ERRCODE = '55000';
      END IF;
      SELECT * INTO v_profile FROM eogp.persons
      WHERE organization_id = p_org AND id = v_person AND status = 'active' FOR UPDATE;
      IF NOT FOUND OR v_profile.revision IS DISTINCT FROM (v_update->>'expectedRevision')::integer THEN
        RAISE EXCEPTION 'matching profile changed since review' USING ERRCODE = '40001';
      END IF;
      -- A missing or blank optional cell preserves the existing Registry value.
      v_names := jsonb_strip_nulls(jsonb_build_object(
        'firstName', v_input.names->>'firstName',
        'lastName', v_input.names->>'lastName',
        'displayName', nullif(btrim(v_input.names->>'displayName'), ''),
        'preferredName', nullif(btrim(v_input.names->>'preferredName'), '')
      ));
      IF v_profile.first_name IS NOT DISTINCT FROM v_names->>'firstName'
        AND v_profile.last_name IS NOT DISTINCT FROM v_names->>'lastName'
        AND v_profile.display_name IS NOT DISTINCT FROM coalesce(v_names->>'displayName', v_profile.display_name)
        AND v_profile.preferred_name IS NOT DISTINCT FROM coalesce(v_names->>'preferredName', v_profile.preferred_name) THEN
        RAISE EXCEPTION 'staged row has no profile changes' USING ERRCODE = '55000';
      END IF;
      PERFORM eogp.write_guest_registry_person(p_org, p_actor, v_person, v_profile.revision, 'update', v_names);
      SELECT id INTO v_participation FROM eogp.event_participations
      WHERE organization_id = p_org AND event_id = p_event AND person_id = v_person;
    ELSE
      IF NOT v_input."rowNumber" = ANY(v_distinct_rows)
        AND EXISTS (SELECT 1 FROM eogp.persons WHERE organization_id = p_org AND status = 'active'
          AND lower(first_name) = lower(v_input.names->>'firstName')
          AND lower(last_name) = lower(v_input.names->>'lastName')) THEN
        RAISE EXCEPTION 'a matching profile was added after preview' USING ERRCODE = '40001';
      END IF;
      v_person := (eogp.write_guest_registry_person(p_org, p_actor, NULL, NULL, 'create', v_input.names)->>'personId')::uuid;
      v_participation := NULL;
    END IF;
    IF v_participation IS NULL THEN
      v_participation := (eogp.link_registry_person_to_event(p_org, p_event, p_actor, v_person, 'eligible')->>'participationId')::uuid;
    END IF;
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
      mapping_snapshot = mapping_snapshot || jsonb_build_object('reuseChoices', v_choices, 'distinctProfileRows', v_distinct_rows, 'updateChoices', v_updates)
  WHERE organization_id = p_org AND event_id = p_event AND id = p_batch;
  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.import.committed', 'guest_import', p_batch,
    jsonb_build_object('eventId', p_event, 'importedCount', v_count, 'reusedCount', v_reused, 'distinctProfileCount', v_distinct_count,
      'updatedCount', v_updated_count, 'skippedCount', v_total - v_count)
  );
  RETURN jsonb_build_object('batchId', p_batch, 'importedCount', v_count, 'skippedCount', v_total - v_count);
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.commit_reviewed_guest_import(
  p_org uuid, p_event uuid, p_actor uuid, p_batch uuid, p_rows jsonb, p_reuses jsonb, p_distinct_rows integer[]
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
  SELECT eogp.commit_reviewed_guest_import(p_org, p_event, p_actor, p_batch, p_rows, p_reuses, p_distinct_rows, '[]'::jsonb)
$function$;

REVOKE ALL ON FUNCTION eogp.commit_reviewed_guest_import(uuid,uuid,uuid,uuid,jsonb,jsonb,integer[],jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.commit_reviewed_guest_import(uuid,uuid,uuid,uuid,jsonb,jsonb,integer[],jsonb) TO eventor_runtime;

CREATE OR REPLACE FUNCTION eogp.read_guest_import_report(p_org uuid, p_event uuid, p_actor uuid, p_batch uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_report jsonb;
BEGIN
  PERFORM eogp.assert_guest_import_permission(p_org, p_event, p_actor);
  SELECT jsonb_build_object('batchId', batch.id, 'state', batch.state, 'rows', jsonb_agg(jsonb_build_object(
    'rowNumber', row.row_number,
    'outcome', CASE
      WHEN row.committed_participation_id IS NOT NULL AND reviewed.outcome IS NOT NULL THEN reviewed.outcome
      WHEN row.committed_participation_id IS NOT NULL THEN 'created'
      WHEN row.validation_errors <> '[]'::jsonb THEN 'invalid'
      WHEN batch.state = 'committed' THEN 'skipped'
      WHEN row.duplicate_candidates <> '[]'::jsonb THEN 'needs_review'
      ELSE 'ready'
    END,
    'errors', row.validation_errors,
    'duplicateCount', jsonb_array_length(row.duplicate_candidates)
  ) ORDER BY row.row_number)) INTO v_report
  FROM eogp.guest_import_batches batch
  JOIN eogp.guest_import_rows row ON row.organization_id = batch.organization_id
    AND row.event_id = batch.event_id AND row.batch_id = batch.id
  LEFT JOIN LATERAL (
    SELECT outcome FROM (VALUES ('reuseChoices', 'linked'), ('updateChoices', 'updated')) AS action(key, outcome)
    CROSS JOIN LATERAL jsonb_array_elements(coalesce(batch.mapping_snapshot->action.key, '[]'::jsonb)) choice
    WHERE (choice->>'rowNumber')::integer = row.row_number
    LIMIT 1
  ) reviewed ON true
  WHERE batch.organization_id = p_org AND batch.event_id = p_event AND batch.id = p_batch
    AND batch.state IN ('ready', 'committed') AND batch.mapping_snapshot->>'format' = 'guest-names-csv-v1'
  GROUP BY batch.id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'import report not found' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id
  ) VALUES (p_org, p_org, p_actor, 'membership', 'guest.import.report_viewed', 'guest_import', p_batch);
  RETURN v_report;
END;
$function$;
