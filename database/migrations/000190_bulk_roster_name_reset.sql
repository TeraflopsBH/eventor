-- Explicitly reset only the selected event-local display-name overrides.
CREATE FUNCTION eogp.reset_event_guest_bulk_roster_names(p_org uuid,p_event uuid,p_actor uuid,p_selection jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_selection record;v_result jsonb;v_count integer:=0;v_updated integer:=0;
BEGIN
 PERFORM eogp.assert_event_guest_list_write(p_org,p_event,p_actor);
 FOR v_selection IN SELECT * FROM eogp.bulk_event_guest_selection(p_selection) ORDER BY participation_id LOOP
  v_count:=v_count+1;
  v_result:=eogp.set_event_guest_roster_name(p_org,p_event,p_actor,v_selection.participation_id,v_selection.expected_revision,NULL);
  IF (v_result->>'revision')::integer<>v_selection.expected_revision THEN v_updated:=v_updated+1;END IF;
 END LOOP;
 RETURN jsonb_build_object('processedCount',v_count,'updatedCount',v_updated);
END;
$function$;
REVOKE ALL ON FUNCTION eogp.reset_event_guest_bulk_roster_names(uuid,uuid,uuid,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.reset_event_guest_bulk_roster_names(uuid,uuid,uuid,jsonb) TO eventor_runtime;
