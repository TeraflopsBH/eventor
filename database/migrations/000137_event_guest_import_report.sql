CREATE FUNCTION eogp.read_guest_import_report(p_org uuid, p_event uuid, p_actor uuid, p_batch uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_report jsonb;
BEGIN
  PERFORM eogp.assert_guest_import_permission(p_org, p_event, p_actor);
  SELECT jsonb_build_object('batchId', batch.id, 'state', batch.state, 'rows', jsonb_agg(jsonb_build_object(
    'rowNumber', row.row_number,
    'outcome', CASE
      WHEN row.committed_participation_id IS NOT NULL AND reused.row_number IS NOT NULL THEN 'linked'
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
    SELECT (choice->>'rowNumber')::integer AS row_number
    FROM jsonb_array_elements(coalesce(batch.mapping_snapshot->'reuseChoices', '[]'::jsonb)) choice
    WHERE (choice->>'rowNumber')::integer = row.row_number
    LIMIT 1
  ) reused ON true
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

REVOKE ALL ON FUNCTION eogp.read_guest_import_report(uuid,uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.read_guest_import_report(uuid,uuid,uuid,uuid) TO eventor_runtime;
