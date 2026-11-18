CREATE FUNCTION eogp.archive_guest_registry_profiles(p_org uuid, p_actor uuid, p_selection jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_count integer;
  v_distinct integer;
  v_profile record;
BEGIN
  PERFORM eogp.assert_guest_registry_permission(p_org, p_actor, true);
  IF jsonb_typeof(p_selection) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'invalid Registry profile selection' USING ERRCODE = '22023';
  END IF;
  v_count := jsonb_array_length(p_selection);
  IF v_count NOT BETWEEN 1 AND 50 THEN
    RAISE EXCEPTION 'select between 1 and 50 Registry profiles' USING ERRCODE = '22023';
  END IF;
  SELECT count(DISTINCT selected."personId") INTO v_distinct
  FROM jsonb_to_recordset(p_selection) AS selected("personId" uuid, "expectedRevision" integer)
  WHERE selected."expectedRevision" >= 1;
  IF v_count <> v_distinct THEN
    RAISE EXCEPTION 'select each Registry profile once with its current revision' USING ERRCODE = '22023';
  END IF;

  FOR v_profile IN
    SELECT * FROM jsonb_to_recordset(p_selection) AS selected("personId" uuid, "expectedRevision" integer)
    ORDER BY selected."personId"
  LOOP
    PERFORM eogp.write_guest_registry_person(p_org, p_actor, v_profile."personId", v_profile."expectedRevision", 'archive', '{}'::jsonb);
  END LOOP;
  RETURN jsonb_build_object('archivedCount', v_count);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.archive_guest_registry_profiles(uuid,uuid,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.archive_guest_registry_profiles(uuid,uuid,jsonb) TO eventor_runtime;
