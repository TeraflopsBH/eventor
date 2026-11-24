-- Atomic roster group membership changes; preserve existing roles and unrelated groups.
CREATE FUNCTION eogp.set_event_guest_bulk_group(p_org uuid, p_event uuid, p_actor uuid, p_group uuid, p_action text, p_selection jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_count integer;
  v_distinct integer;
  v_selection record;
  v_result jsonb;
  v_groups uuid[];
  v_updated integer := 0;
BEGIN
  PERFORM eogp.assert_event_guest_list_write(p_org, p_event, p_actor);
  IF p_action IS NULL OR p_action NOT IN ('add', 'remove') THEN
    RAISE EXCEPTION 'invalid bulk group action' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM eogp.guest_groups WHERE organization_id = p_org AND event_id = p_event AND id = p_group
      AND (p_action = 'remove' OR retired_at IS NULL)
  ) THEN
    RAISE EXCEPTION 'group is unavailable for this action' USING ERRCODE = '55000';
  END IF;
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

  -- Lock in the same stable order as the single-row commands before reading memberships.
  -- Any missing, cancelled or stale selection raises below and rolls back the whole batch.
  PERFORM 1 FROM eogp.event_participations participation
  JOIN jsonb_to_recordset(p_selection) AS selected("participationId" uuid, "expectedRevision" integer)
    ON selected."participationId" = participation.id
  WHERE participation.organization_id = p_org AND participation.event_id = p_event
  ORDER BY participation.id FOR UPDATE OF participation;

  FOR v_selection IN
    SELECT * FROM jsonb_to_recordset(p_selection) AS selected("participationId" uuid, "expectedRevision" integer)
    ORDER BY selected."participationId"
  LOOP
    SELECT coalesce(array_agg(assignment.group_id ORDER BY assignment.group_id), ARRAY[]::uuid[]) INTO v_groups
    FROM eogp.guest_group_memberships assignment
    WHERE assignment.organization_id = p_org AND assignment.event_id = p_event
      AND assignment.participation_id = v_selection."participationId";
    IF p_action = 'remove' THEN
      v_groups := array_remove(v_groups, p_group);
    ELSIF NOT p_group = ANY(v_groups) THEN
      v_groups := array_append(v_groups, p_group);
    END IF;
    v_result := eogp.set_event_guest_groups(
      p_org, p_event, p_actor, v_selection."participationId", v_selection."expectedRevision", v_groups
    );
    IF (v_result->>'revision')::integer <> v_selection."expectedRevision" THEN
      v_updated := v_updated + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('processedCount', v_count, 'updatedCount', v_updated);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.set_event_guest_bulk_group(uuid,uuid,uuid,uuid,text,jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.set_event_guest_bulk_group(uuid,uuid,uuid,uuid,text,jsonb) TO eventor_runtime;
