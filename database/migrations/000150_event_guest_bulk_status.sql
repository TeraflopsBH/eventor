CREATE FUNCTION eogp.bulk_event_guest_selection(p_selection jsonb)
RETURNS TABLE(participation_id uuid, expected_revision integer)
LANGUAGE plpgsql SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_count integer;
  v_distinct integer;
BEGIN
  IF jsonb_typeof(p_selection) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'invalid guest selection' USING ERRCODE = '22023';
  END IF;
  v_count := jsonb_array_length(p_selection);
  IF v_count NOT BETWEEN 1 AND 50 THEN
    RAISE EXCEPTION 'select between 1 and 50 guests' USING ERRCODE = '22023';
  END IF;
  SELECT count(DISTINCT selected."participationId") INTO v_distinct
  FROM jsonb_to_recordset(p_selection) AS selected("participationId" uuid, "expectedRevision" integer)
  WHERE selected."expectedRevision" >= 1;
  IF v_count <> v_distinct THEN
    RAISE EXCEPTION 'select each guest once with its current revision' USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
  SELECT selected."participationId", selected."expectedRevision"
  FROM jsonb_to_recordset(p_selection) AS selected("participationId" uuid, "expectedRevision" integer)
  ORDER BY selected."participationId";
END;
$function$;

REVOKE ALL ON FUNCTION eogp.bulk_event_guest_selection(jsonb) FROM PUBLIC;

CREATE OR REPLACE FUNCTION eogp.set_event_guest_bulk_category(p_org uuid, p_event uuid, p_actor uuid, p_category uuid, p_selection jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_count integer := 0;
  v_selection record;
  v_result jsonb;
  v_updated integer := 0;
BEGIN
  PERFORM eogp.assert_event_guest_list_write(p_org, p_event, p_actor);
  FOR v_selection IN
    SELECT * FROM eogp.bulk_event_guest_selection(p_selection) ORDER BY participation_id
  LOOP
    v_count := v_count + 1;
    v_result := eogp.set_event_guest_category(
      p_org, p_event, p_actor, v_selection.participation_id, v_selection.expected_revision, p_category
    );
    IF (v_result->>'revision')::integer <> v_selection.expected_revision THEN
      v_updated := v_updated + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('processedCount', v_count, 'updatedCount', v_updated);
END;
$function$;

CREATE FUNCTION eogp.set_event_guest_bulk_status(p_org uuid, p_event uuid, p_actor uuid, p_status text, p_selection jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_count integer := 0;
  v_selection record;
  v_result jsonb;
  v_updated integer := 0;
BEGIN
  PERFORM eogp.assert_event_guest_list_write(p_org, p_event, p_actor);
  FOR v_selection IN
    SELECT * FROM eogp.bulk_event_guest_selection(p_selection) ORDER BY participation_id
  LOOP
    v_count := v_count + 1;
    v_result := eogp.update_guest_participation_status(
      p_org, p_event, p_actor, v_selection.participation_id, v_selection.expected_revision, p_status
    );
    IF (v_result->>'revision')::integer <> v_selection.expected_revision THEN
      v_updated := v_updated + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('processedCount', v_count, 'updatedCount', v_updated);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.set_event_guest_bulk_status(uuid,uuid,uuid,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.set_event_guest_bulk_status(uuid,uuid,uuid,text,jsonb) TO eventor_runtime;
