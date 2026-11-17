CREATE INDEX event_participations_category_idx
  ON eogp.event_participations (organization_id, event_id, category_id, status)
  WHERE category_id IS NOT NULL;

CREATE FUNCTION eogp.read_event_guest_list(
  p_org uuid, p_event uuid, p_actor uuid, p_status text, p_offset integer, p_category uuid, p_unassigned boolean
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_event_status text;
  v_can_manage boolean;
  v_rows jsonb;
BEGIN
  v_can_manage := eogp.assert_event_guest_list_access(p_org, p_event, p_actor);
  SELECT status INTO v_event_status FROM eogp.events WHERE organization_id = p_org AND id = p_event;
  IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002'; END IF;
  IF coalesce(p_offset, -1) NOT BETWEEN 0 AND 100000 OR
     (p_status IS NOT NULL AND p_status NOT IN ('eligible', 'waitlisted', 'withdrawn', 'cancelled', 'ineligible')) THEN
    RAISE EXCEPTION 'invalid guest list filter' USING ERRCODE = '22023';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'participationId', p.id, 'displayName', p.display_name, 'status', p.status, 'revision', p.revision,
    'categoryCode', p.category_code, 'categoryId', p.category_id, 'participationCode', p.participation_code
  ) ORDER BY lower(p.display_name), p.id), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT * FROM eogp.event_guest_roster_rows guest
    WHERE guest.organization_id = p_org AND guest.event_id = p_event
      AND (p_status IS NULL OR guest.status = p_status)
      AND (p_category IS NULL OR guest.category_id = p_category)
      AND (p_unassigned IS DISTINCT FROM true OR guest.category_code IS NULL)
    ORDER BY lower(guest.display_name), guest.id
    LIMIT 51 OFFSET p_offset
  ) p;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id
  ) VALUES (p_org, p_org, p_actor, 'membership', 'guest.event_roster.viewed', 'event', p_event);

  RETURN jsonb_build_object(
    'people', CASE WHEN jsonb_array_length(v_rows) > 50 THEN v_rows - 50 ELSE v_rows END,
    'canManage', v_can_manage AND v_event_status IN ('draft', 'planned', 'scheduled', 'active'),
    'nextOffset', CASE WHEN jsonb_array_length(v_rows) > 50 AND p_offset < 100000 THEN p_offset + 50 END
  );
END;
$function$;

CREATE FUNCTION eogp.read_event_guest_roster_export(
  p_org uuid, p_event uuid, p_actor uuid, p_status text, p_category uuid, p_unassigned boolean
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_rows jsonb;
  v_count integer;
BEGIN
  IF nullif(current_setting('app.actor_membership_id', true), '')::uuid IS DISTINCT FROM p_actor THEN
    RAISE EXCEPTION 'staff actor context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_event_guest_list_access(p_org, p_event, p_actor);
  IF NOT EXISTS (SELECT 1 FROM eogp.events WHERE organization_id = p_org AND id = p_event) THEN
    RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002';
  END IF;
  IF p_status IS NOT NULL AND p_status NOT IN ('eligible', 'waitlisted', 'withdrawn', 'cancelled', 'ineligible') THEN
    RAISE EXCEPTION 'invalid guest list filter' USING ERRCODE = '22023';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'displayName', guest.display_name, 'status', guest.status, 'categoryCode', guest.category_code
  ) ORDER BY lower(guest.display_name), guest.id), '[]'::jsonb), count(*)
  INTO v_rows, v_count
  FROM (
    SELECT * FROM eogp.event_guest_roster_rows projected
    WHERE projected.organization_id = p_org AND projected.event_id = p_event
      AND (p_status IS NULL OR projected.status = p_status)
      AND (p_category IS NULL OR projected.category_id = p_category)
      AND (p_unassigned IS DISTINCT FROM true OR projected.category_code IS NULL)
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
      || jsonb_strip_nulls(jsonb_build_object('categoryFilter', CASE WHEN p_unassigned THEN 'unassigned' ELSE p_category::text END))
  );
  RETURN jsonb_build_object('people', v_rows);
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.read_event_guest_list(p_org uuid, p_event uuid, p_actor uuid, p_status text, p_offset integer)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
  SELECT eogp.read_event_guest_list(p_org, p_event, p_actor, p_status, p_offset, NULL, false)
$function$;

CREATE OR REPLACE FUNCTION eogp.read_event_guest_roster_export(p_org uuid, p_event uuid, p_actor uuid, p_status text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
  SELECT eogp.read_event_guest_roster_export(p_org, p_event, p_actor, p_status, NULL, false)
$function$;

REVOKE ALL ON FUNCTION eogp.read_event_guest_list(uuid,uuid,uuid,text,integer,uuid,boolean),
  eogp.read_event_guest_roster_export(uuid,uuid,uuid,text,uuid,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.read_event_guest_list(uuid,uuid,uuid,text,integer,uuid,boolean),
  eogp.read_event_guest_roster_export(uuid,uuid,uuid,text,uuid,boolean) TO eventor_runtime;
