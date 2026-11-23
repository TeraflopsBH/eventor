CREATE OR REPLACE FUNCTION eogp.read_event_guest_roster_export(
  p_org uuid, p_event uuid, p_actor uuid, p_status text, p_category uuid, p_unassigned boolean, p_name_query text,
  p_tag uuid, p_group uuid
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_rows jsonb;
  v_count integer;
  v_name_query text := lower(btrim(coalesce(p_name_query, '')));
BEGIN
  IF nullif(current_setting('app.actor_membership_id', true), '')::uuid IS DISTINCT FROM p_actor THEN
    RAISE EXCEPTION 'staff actor context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_event_guest_list_access(p_org, p_event, p_actor);
  IF NOT EXISTS (SELECT 1 FROM eogp.events WHERE organization_id = p_org AND id = p_event) THEN
    RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002';
  END IF;
  IF length(v_name_query) > 200 OR
     (p_status IS NOT NULL AND p_status NOT IN ('eligible', 'waitlisted', 'withdrawn', 'cancelled', 'ineligible')) THEN
    RAISE EXCEPTION 'invalid guest list filter' USING ERRCODE = '22023';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'displayName', guest.display_name, 'status', guest.status, 'categoryCode', guest.category_code,
    'participationCode',guest.participation_code
  ) ORDER BY lower(guest.display_name), guest.id), '[]'::jsonb), count(*)
  INTO v_rows, v_count
  FROM (
    SELECT * FROM eogp.event_guest_roster_rows projected
    WHERE projected.organization_id = p_org AND projected.event_id = p_event
      AND eogp.guest_roster_matches_search(projected.display_name, projected.snapshot_first_name, projected.snapshot_last_name,
        projected.participation_code, v_name_query)
      AND (p_status IS NULL OR projected.status = p_status)
      AND (p_category IS NULL OR projected.category_id = p_category)
      AND (p_unassigned IS DISTINCT FROM true OR projected.category_code IS NULL)
      AND ((p_tag IS NULL AND p_group IS NULL) OR eogp.guest_roster_matches_memberships(p_org,p_event,projected.id,p_tag,p_group))
    ORDER BY lower(projected.display_name), projected.id LIMIT 20001
  ) guest;
  IF v_count > 20000 THEN
    RETURN jsonb_build_object('limitExceeded', true);
  END IF;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.event_roster.exported', 'event', p_event,
    jsonb_build_object('exportedCount', v_count, 'statusFilter', p_status)
      || jsonb_build_object('nameFilterApplied', v_name_query <> '')
      || jsonb_strip_nulls(jsonb_build_object('categoryFilter', CASE WHEN p_unassigned THEN 'unassigned' ELSE p_category::text END,
        'tagFilterApplied', CASE WHEN p_tag IS NOT NULL THEN true END,
        'groupFilterApplied', CASE WHEN p_group IS NOT NULL THEN true END))
  );
  RETURN jsonb_build_object('people', v_rows);
END;
$function$;

