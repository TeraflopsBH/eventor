CREATE FUNCTION eogp.prepare_mapped_guest_import_preview(
  p_org uuid, p_event uuid, p_actor uuid, p_source_hash text, p_rows jsonb,
  p_mapping jsonb, p_sheet integer, p_header integer
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_selection record;
  v_column integer;
  v_selected integer[] := ARRAY[]::integer[];
  v_batch jsonb;
BEGIN
  PERFORM eogp.assert_guest_import_permission(p_org, p_event, p_actor);
  IF jsonb_typeof(p_mapping) IS DISTINCT FROM 'object' OR NOT (p_mapping ?& ARRAY['firstName','lastName'])
    OR (p_sheet IS NULL) <> (p_header IS NULL) THEN
    RAISE EXCEPTION 'invalid guest import mapping' USING ERRCODE = '22023';
  END IF;
  FOR v_selection IN SELECT * FROM jsonb_each(p_mapping)
  LOOP
    IF v_selection.key NOT IN ('firstName','lastName','displayName','preferredName')
      OR jsonb_typeof(v_selection.value) <> 'number' OR v_selection.value::text !~ '^[0-9]{1,2}$' THEN
      RAISE EXCEPTION 'invalid guest import column' USING ERRCODE = '22023';
    END IF;
    v_column := v_selection.value::text::integer;
    IF v_column NOT BETWEEN 1 AND 64 OR v_column = ANY(v_selected) THEN
      RAISE EXCEPTION 'select distinct guest import columns' USING ERRCODE = '22023';
    END IF;
    v_selected := array_append(v_selected, v_column);
  END LOOP;

  IF p_sheet IS NULL THEN
    v_batch := eogp.prepare_guest_import_preview(p_org, p_event, p_actor, p_source_hash, p_rows);
  ELSE
    v_batch := eogp.prepare_guest_import_workbook_preview(p_org, p_event, p_actor, p_source_hash, p_rows, p_sheet, p_header);
  END IF;

  UPDATE eogp.guest_import_batches
  SET mapping_snapshot = mapping_snapshot || jsonb_build_object('columnsByField', p_mapping)
  WHERE organization_id = p_org AND event_id = p_event AND id = (v_batch->>'batchId')::uuid;
  RETURN v_batch;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.prepare_mapped_guest_import_preview(uuid,uuid,uuid,text,jsonb,jsonb,integer,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.prepare_mapped_guest_import_preview(uuid,uuid,uuid,text,jsonb,jsonb,integer,integer) TO eventor_runtime;
