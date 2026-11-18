CREATE FUNCTION eogp.write_guest_registry_person(
  p_org uuid, p_actor uuid, p_person_id uuid, p_expected_revision integer, p_action text, p_names jsonb, p_create_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_person eogp.persons%ROWTYPE;
  v_first text;
  v_last text;
  v_display text;
  v_preferred text;
BEGIN
  PERFORM eogp.assert_guest_registry_permission(p_org, p_actor, true);
  IF p_action IS NULL OR p_action NOT IN ('create', 'update', 'archive') THEN
    RAISE EXCEPTION 'invalid person operation' USING ERRCODE = '22023';
  END IF;

  IF p_action <> 'create' THEN
    SELECT * INTO v_person FROM eogp.persons WHERE organization_id = p_org AND id = p_person_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'person not found' USING ERRCODE = 'P0002'; END IF;
    IF p_expected_revision IS DISTINCT FROM v_person.revision THEN
      RAISE EXCEPTION 'person revision conflict' USING ERRCODE = '40001';
    END IF;
    IF v_person.status <> 'active' THEN
      RAISE EXCEPTION 'only active persons can be changed' USING ERRCODE = '55000';
    END IF;
  END IF;

  IF p_action = 'archive' THEN
    IF EXISTS (
      SELECT 1 FROM eogp.event_participations participation
      JOIN eogp.events event ON event.organization_id = participation.organization_id
                           AND event.id = participation.event_id
      WHERE participation.organization_id = p_org AND participation.person_id = p_person_id
        AND participation.status IN ('eligible', 'waitlisted')
        AND event.status NOT IN ('completed', 'cancelled', 'archived')
    ) THEN
      RAISE EXCEPTION 'person has outstanding event participation' USING ERRCODE = '55000';
    END IF;
    UPDATE eogp.persons SET status = 'archived', revision = revision + 1, updated_at = clock_timestamp()
    WHERE organization_id = p_org AND id = p_person_id RETURNING * INTO v_person;
  ELSE
    IF jsonb_typeof(p_names) IS DISTINCT FROM 'object' OR p_names = '{}'::jsonb THEN
      RAISE EXCEPTION 'invalid profile fields' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (
         SELECT 1 FROM jsonb_each(p_names) f
         WHERE f.key NOT IN ('firstName', 'lastName', 'displayName', 'preferredName')
           OR jsonb_typeof(f.value) NOT IN ('string', 'null')
       ) THEN
      RAISE EXCEPTION 'invalid profile fields' USING ERRCODE = '22023';
    END IF;
    v_first := CASE WHEN p_names ? 'firstName' THEN btrim(p_names->>'firstName') ELSE v_person.first_name END;
    v_last := CASE WHEN p_names ? 'lastName' THEN btrim(p_names->>'lastName') ELSE v_person.last_name END;
    v_display := CASE WHEN p_names ? 'displayName' THEN nullif(btrim(p_names->>'displayName'), '') ELSE v_person.display_name END;
    v_preferred := CASE WHEN p_names ? 'preferredName' THEN nullif(btrim(p_names->>'preferredName'), '') ELSE v_person.preferred_name END;
    IF coalesce(length(v_first), 0) NOT BETWEEN 1 AND 200 OR coalesce(length(v_last), 0) NOT BETWEEN 1 AND 200
       OR length(v_display) > 250 OR length(v_preferred) > 200 THEN
      RAISE EXCEPTION 'invalid profile names' USING ERRCODE = '22023';
    END IF;
    IF p_action = 'create' THEN
      INSERT INTO eogp.persons (id, organization_id, first_name, last_name, display_name, preferred_name, created_by_membership_id)
      VALUES (coalesce(p_create_id, gen_random_uuid()), p_org, v_first, v_last, v_display, v_preferred, p_actor) RETURNING * INTO v_person;
    ELSE
      UPDATE eogp.persons SET first_name = v_first, last_name = v_last,
        display_name = v_display, preferred_name = v_preferred, revision = revision + 1, updated_at = clock_timestamp()
      WHERE organization_id = p_org AND id = p_person_id RETURNING * INTO v_person;
    END IF;
  END IF;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.registry.' || p_action,
    'person', v_person.id, jsonb_build_object('revision', v_person.revision)
  );
  RETURN jsonb_build_object('personId', v_person.id, 'revision', v_person.revision, 'status', v_person.status);
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.write_guest_registry_person(
  p_org uuid, p_actor uuid, p_person_id uuid, p_expected_revision integer, p_action text, p_names jsonb
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
  SELECT eogp.write_guest_registry_person(p_org,p_actor,p_person_id,p_expected_revision,p_action,p_names,NULL)
$function$;

REVOKE ALL ON FUNCTION eogp.write_guest_registry_person(uuid,uuid,uuid,integer,text,jsonb,uuid) FROM PUBLIC;

CREATE OR REPLACE FUNCTION eogp.prepare_reference_guest_import_preview(
  p_org uuid, p_event uuid, p_actor uuid, p_source_hash text, p_rows jsonb, p_mapping jsonb,
  p_sheet integer, p_header integer, p_source text, p_reference_column integer
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE v_batch jsonb;
BEGIN
  PERFORM eogp.assert_guest_reference_permission(p_org, p_actor, false);
  IF coalesce(p_source, '') !~ '^[A-Z0-9][A-Z0-9_-]{0,39}$'
    OR coalesce(p_reference_column, 0) NOT BETWEEN 1 AND 64
    OR EXISTS (SELECT 1 FROM jsonb_each(p_mapping) selected WHERE selected.value = to_jsonb(p_reference_column)) THEN
    RAISE EXCEPTION 'invalid guest import reference selection' USING ERRCODE = '22023';
  END IF;
  v_batch := eogp.prepare_mapped_guest_import_preview(p_org, p_event, p_actor, p_source_hash, p_rows, p_mapping, p_sheet, p_header);
  UPDATE eogp.guest_import_batches
  SET mapping_snapshot = mapping_snapshot || jsonb_build_object('matchingSource', p_source, 'referenceColumn', p_reference_column)
  WHERE organization_id = p_org AND event_id = p_event AND id = (v_batch->>'batchId')::uuid;

  UPDATE eogp.guest_import_rows staged
  SET reference_match_fingerprint = input."referenceFingerprint",
      duplicate_candidates = CASE WHEN candidate.status IS DISTINCT FROM 'active' OR staged.validation_errors <> '[]'::jsonb THEN '[]'::jsonb
        ELSE jsonb_build_array(candidate.person_id) END,
      validation_errors = CASE
        WHEN staged.validation_errors <> '[]'::jsonb THEN staged.validation_errors
        WHEN candidate.person_id IS NULL THEN '["reference_unmatched"]'::jsonb
        WHEN candidate.status <> 'active' THEN '["reference_unavailable"]'::jsonb
        ELSE '[]'::jsonb END
  FROM jsonb_to_recordset(p_rows) AS input("rowNumber" integer, "referenceFingerprint" text)
  LEFT JOIN LATERAL (
    SELECT reference.person_id, person.status FROM eogp.person_identifiers reference
    JOIN eogp.persons person ON person.organization_id = reference.organization_id AND person.id = reference.person_id
    WHERE reference.organization_id = p_org AND reference.identifier_kind = 'external-ref-v1:' || p_source
      AND reference.identifier_hash = input."referenceFingerprint"
  ) candidate ON true
  WHERE staged.organization_id = p_org AND staged.event_id = p_event AND staged.batch_id = (v_batch->>'batchId')::uuid
    AND staged.row_number = input."rowNumber";
  RETURN v_batch;
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.read_guest_import_preview(p_org uuid, p_event uuid, p_actor uuid, p_batch uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_rows jsonb;
  v_source text;
  v_can_create boolean := false;
BEGIN
  v_source := eogp.assert_guest_import_batch_permission(p_org, p_event, p_actor, p_batch);
  IF NOT EXISTS (SELECT 1 FROM eogp.guest_import_batches
    WHERE organization_id = p_org AND event_id = p_event AND id = p_batch AND state = 'ready'
      AND mapping_snapshot->>'format' = 'guest-names-csv-v1') THEN
    RAISE EXCEPTION 'import preview not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_source IS NOT NULL THEN
    BEGIN
      PERFORM eogp.assert_guest_reference_permission(p_org,p_actor,true);
      v_can_create := true;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
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
        AND eogp.guest_import_reference_matches(p_org, person.id, v_source, import_row.reference_match_fingerprint)
    ) match
  ) candidates
  WHERE import_row.organization_id = p_org AND import_row.event_id = p_event AND import_row.batch_id = p_batch;
  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id
  ) VALUES (p_org, p_org, p_actor, 'membership', 'guest.import.preview_viewed', 'guest_import', p_batch);
  RETURN jsonb_build_object('batchId', p_batch, 'rows', v_rows, 'matchingSource', v_source, 'canCreateReferences', v_can_create);
END;
$function$;

CREATE FUNCTION eogp.guest_import_commit_input(
  p_org uuid,p_event uuid,p_actor uuid,p_batch uuid,p_explicit_rows integer[],p_create_rows integer[]
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_state text;
  v_rows jsonb := '[]'::jsonb;
BEGIN
  v_state := eogp.lock_guest_import_batch(p_org,p_event,p_actor,p_batch);
  IF cardinality(p_create_rows) > 0 THEN
    PERFORM eogp.assert_guest_reference_permission(p_org,p_actor,true);
  END IF;
  IF v_state = 'ready' THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object('rowNumber',row_number,
      'namesCiphertext',replace(encode(normalized_values_ciphertext,'base64'),E'\n',''))
      ORDER BY row_number),'[]'::jsonb)
    INTO v_rows FROM eogp.guest_import_rows
    WHERE organization_id=p_org AND event_id=p_event AND batch_id=p_batch
      AND ((validation_errors = '[]'::jsonb AND (duplicate_candidates = '[]'::jsonb OR row_number=ANY(p_explicit_rows)))
        OR (validation_errors = '["reference_unmatched"]'::jsonb AND row_number=ANY(p_create_rows)));
  END IF;
  RETURN v_rows;
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.guest_import_commit_input(p_org uuid,p_event uuid,p_actor uuid,p_batch uuid,p_distinct_rows integer[])
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
  SELECT eogp.guest_import_commit_input(p_org,p_event,p_actor,p_batch,p_distinct_rows,ARRAY[]::integer[])
$function$;

CREATE FUNCTION eogp.commit_reviewed_guest_import(
  p_org uuid, p_event uuid, p_actor uuid, p_batch uuid, p_rows jsonb, p_reuses jsonb, p_distinct_rows integer[],
  p_updates jsonb, p_reference_creations jsonb
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
  v_source text;
  v_create_rows integer[];
  v_saved_creates jsonb;
  v_created_count integer;
  v_creation record;
BEGIN
  v_state := eogp.lock_guest_import_batch(p_org, p_event, p_actor, p_batch);
  SELECT mapping_snapshot->>'matchingSource' INTO v_source FROM eogp.guest_import_batches
  WHERE organization_id = p_org AND event_id = p_event AND id = p_batch;
  IF v_source IS NOT NULL AND cardinality(p_distinct_rows) > 0 THEN
    RAISE EXCEPTION 'reference matches do not allow separate profile creation' USING ERRCODE = '55000';
  END IF;
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
  IF jsonb_typeof(p_reference_creations) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'invalid new reference choices' USING ERRCODE='22023';
  END IF;
  SELECT coalesce(array_agg(DISTINCT selected."rowNumber" ORDER BY selected."rowNumber"),ARRAY[]::integer[])
  INTO v_create_rows
  FROM jsonb_to_recordset(p_reference_creations) selected("rowNumber" integer)
  WHERE selected."rowNumber" BETWEEN 2 AND 1048576;
  IF jsonb_array_length(p_reference_creations) <> cardinality(v_create_rows) OR cardinality(v_create_rows) > 500
    OR v_create_rows && (v_distinct_rows || v_update_rows)
    OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_choices) choice WHERE (choice->>'rowNumber')::integer=ANY(v_create_rows))
    OR (cardinality(v_create_rows)>0 AND v_source IS NULL) THEN
    RAISE EXCEPTION 'invalid new reference choices' USING ERRCODE='22023';
  END IF;
  IF cardinality(v_create_rows)>0 THEN
    PERFORM eogp.assert_guest_reference_permission(p_org,p_actor,true);
  END IF;
  SELECT count(*), count(*) FILTER (WHERE committed_participation_id IS NOT NULL)
  INTO v_total, v_count FROM eogp.guest_import_rows
  WHERE organization_id = p_org AND event_id = p_event AND batch_id = p_batch;
  IF v_state = 'committed' THEN
    SELECT coalesce(mapping_snapshot->'reuseChoices', '[]'::jsonb),
      coalesce(mapping_snapshot->'distinctProfileRows', '[]'::jsonb),
      coalesce(mapping_snapshot->'updateChoices', '[]'::jsonb),
      coalesce(mapping_snapshot->'newReferenceRows','[]'::jsonb)
    INTO v_saved_choices, v_saved_distinct, v_saved_updates, v_saved_creates
    FROM eogp.guest_import_batches WHERE organization_id = p_org AND event_id = p_event AND id = p_batch;
    IF v_saved_choices <> v_choices OR v_saved_distinct <> to_jsonb(v_distinct_rows)
      OR v_saved_updates <> v_updates OR v_saved_creates <> to_jsonb(v_create_rows) THEN
      RAISE EXCEPTION 'import was already committed with different choices' USING ERRCODE = '55000';
    END IF;
    RETURN jsonb_build_object('batchId', p_batch, 'importedCount', v_count, 'skippedCount', v_total - v_count);
  END IF;

  IF jsonb_typeof(p_rows) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'invalid import rows' USING ERRCODE = '22023';
  END IF;
  SELECT count(*) FILTER (WHERE duplicate_candidates = '[]'::jsonb OR row_number = ANY(v_distinct_rows || v_update_rows || v_create_rows)),
    count(*) FILTER (WHERE duplicate_candidates <> '[]'::jsonb AND row_number = ANY(v_distinct_rows)),
    count(*) FILTER (WHERE duplicate_candidates <> '[]'::jsonb AND row_number = ANY(v_update_rows)),
    count(*) FILTER (WHERE validation_errors = '["reference_unmatched"]'::jsonb AND row_number = ANY(v_create_rows))
  INTO v_count, v_distinct_count, v_updated_count, v_created_count FROM eogp.guest_import_rows
  WHERE organization_id = p_org AND event_id = p_event AND batch_id = p_batch
    AND (validation_errors = '[]'::jsonb OR (validation_errors = '["reference_unmatched"]'::jsonb AND row_number=ANY(v_create_rows)));
  IF v_distinct_count <> cardinality(v_distinct_rows) THEN
    RAISE EXCEPTION 'separate profiles require valid rows flagged for duplicate review' USING ERRCODE = '55000';
  END IF;
  IF v_updated_count <> cardinality(v_update_rows) THEN
    RAISE EXCEPTION 'profile updates require valid rows flagged for duplicate review' USING ERRCODE = '55000';
  END IF;
  IF v_created_count <> cardinality(v_create_rows) THEN
    RAISE EXCEPTION 'new references require an unmatched staged reference' USING ERRCODE='55000';
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
        AND ((validation_errors = '[]'::jsonb
          AND (duplicate_candidates = '[]'::jsonb OR row_number = ANY(v_distinct_rows || v_update_rows)))
          OR (validation_errors = '["reference_unmatched"]'::jsonb AND row_number=ANY(v_create_rows)))
        AND normalized_values_ciphertext = decode(v_input."namesCiphertext", 'base64')
    ) THEN
      RAISE EXCEPTION 'import row no longer matches its preview' USING ERRCODE = '40001';
    END IF;
    IF v_input."rowNumber" = ANY(v_create_rows) THEN
      SELECT * INTO v_creation FROM jsonb_to_recordset(p_reference_creations)
        AS item("rowNumber" integer,"personId" uuid,fingerprint text,ciphertext text)
      WHERE item."rowNumber"=v_input."rowNumber";
      IF v_creation."personId" IS NULL OR NOT EXISTS (
        SELECT 1 FROM eogp.guest_import_rows WHERE organization_id=p_org AND event_id=p_event AND batch_id=p_batch
          AND row_number=v_input."rowNumber" AND reference_match_fingerprint=v_creation.fingerprint
      ) THEN
        RAISE EXCEPTION 'new reference does not match its staged row' USING ERRCODE='40001';
      END IF;
      IF EXISTS (SELECT 1 FROM eogp.person_identifiers WHERE organization_id=p_org
        AND identifier_kind='external-ref-v1:'||v_source AND identifier_hash=v_creation.fingerprint) THEN
        RAISE EXCEPTION 'reference was assigned after import preview' USING ERRCODE='40001';
      END IF;
      v_person := (eogp.write_guest_registry_person(
        p_org,p_actor,NULL,NULL,'create',v_input.names,v_creation."personId")->>'personId')::uuid;
      PERFORM eogp.write_guest_registry_reference(
        p_org,p_actor,v_person,NULL,1,'add',v_source,v_creation.fingerprint,decode(v_creation.ciphertext,'base64'));
      v_participation := NULL;
    ELSIF v_input."rowNumber" = ANY(v_update_rows) THEN
      SELECT choice INTO v_update FROM jsonb_array_elements(v_updates) choice
      WHERE (choice->>'rowNumber')::integer = v_input."rowNumber";
      v_person := (v_update->>'personId')::uuid;
      IF NOT EXISTS (SELECT 1 FROM eogp.guest_import_rows
        WHERE organization_id = p_org AND event_id = p_event AND batch_id = p_batch
          AND row_number = v_input."rowNumber" AND duplicate_candidates ? v_person::text
          AND eogp.guest_import_reference_matches(p_org, v_person, v_source, reference_match_fingerprint)) THEN
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
    UPDATE eogp.guest_import_rows SET committed_participation_id = v_participation,
      validation_errors = CASE WHEN v_input."rowNumber"=ANY(v_create_rows) THEN '[]'::jsonb ELSE validation_errors END
    WHERE organization_id = p_org AND event_id = p_event AND batch_id = p_batch AND row_number = v_input."rowNumber";
  END LOOP;

  FOR v_input IN
    SELECT * FROM jsonb_to_recordset(v_choices) AS input("rowNumber" integer, "personId" uuid, "expectedRevision" integer)
    ORDER BY "rowNumber"
  LOOP
    IF NOT EXISTS (SELECT 1 FROM eogp.guest_import_rows WHERE organization_id = p_org AND event_id = p_event
        AND batch_id = p_batch AND row_number = v_input."rowNumber" AND committed_participation_id IS NULL
        AND validation_errors = '[]'::jsonb AND duplicate_candidates ? v_input."personId"::text
        AND eogp.guest_import_reference_matches(p_org, v_input."personId", v_source, reference_match_fingerprint)) THEN
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
      mapping_snapshot = mapping_snapshot || jsonb_build_object('reuseChoices', v_choices, 'distinctProfileRows', v_distinct_rows, 'updateChoices', v_updates, 'newReferenceRows', v_create_rows)
  WHERE organization_id = p_org AND event_id = p_event AND id = p_batch;
  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.import.committed', 'guest_import', p_batch,
    jsonb_build_object('eventId', p_event, 'importedCount', v_count, 'reusedCount', v_reused, 'distinctProfileCount', v_distinct_count,
      'updatedCount', v_updated_count, 'referenceCreatedCount', v_created_count, 'skippedCount', v_total - v_count)
  );
  RETURN jsonb_build_object('batchId', p_batch, 'importedCount', v_count, 'skippedCount', v_total - v_count);
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.commit_reviewed_guest_import(
  p_org uuid,p_event uuid,p_actor uuid,p_batch uuid,p_rows jsonb,p_reuses jsonb,p_distinct_rows integer[],p_updates jsonb
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
  SELECT eogp.commit_reviewed_guest_import(p_org,p_event,p_actor,p_batch,p_rows,p_reuses,p_distinct_rows,p_updates,'[]'::jsonb)
$function$;

REVOKE ALL ON FUNCTION eogp.guest_import_commit_input(uuid,uuid,uuid,uuid,integer[],integer[]),
  eogp.commit_reviewed_guest_import(uuid,uuid,uuid,uuid,jsonb,jsonb,integer[],jsonb,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.guest_import_commit_input(uuid,uuid,uuid,uuid,integer[],integer[]),
  eogp.commit_reviewed_guest_import(uuid,uuid,uuid,uuid,jsonb,jsonb,integer[],jsonb,jsonb) TO eventor_runtime;

CREATE OR REPLACE FUNCTION eogp.read_guest_import_report(p_org uuid, p_event uuid, p_actor uuid, p_batch uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_report jsonb;
BEGIN
  PERFORM eogp.assert_guest_import_batch_permission(p_org, p_event, p_actor, p_batch);
  SELECT jsonb_build_object('batchId', batch.id, 'state', batch.state, 'rows', jsonb_agg(jsonb_build_object(
    'rowNumber', row.row_number,
    'outcome', CASE
      WHEN row.committed_participation_id IS NOT NULL AND reviewed.outcome IS NOT NULL THEN reviewed.outcome
      WHEN row.committed_participation_id IS NOT NULL THEN 'created'
      WHEN row.validation_errors = '["reference_unmatched"]'::jsonb THEN
        CASE WHEN batch.state = 'committed' THEN 'skipped' ELSE 'needs_review' END
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
