ALTER TABLE eogp.event_guest_saved_views
  ADD COLUMN tag_id uuid,
  ADD COLUMN group_id uuid,
  ADD FOREIGN KEY (organization_id,event_id,tag_id) REFERENCES eogp.guest_tags(organization_id,event_id,id),
  ADD FOREIGN KEY (organization_id,event_id,group_id) REFERENCES eogp.guest_groups(organization_id,event_id,id);

CREATE FUNCTION eogp.guest_roster_matches_memberships(
  p_org uuid, p_event uuid, p_guest uuid, p_tag uuid, p_group uuid
) RETURNS boolean LANGUAGE sql STABLE SET search_path = pg_catalog, eogp
AS $function$
  SELECT (p_tag IS NULL OR EXISTS (
    SELECT 1 FROM eogp.event_participation_tags assignment
    JOIN eogp.guest_tags tag ON (tag.organization_id,tag.event_id,tag.id) =
      (assignment.organization_id,assignment.event_id,assignment.tag_id)
    WHERE assignment.organization_id=p_org AND assignment.event_id=p_event AND assignment.participation_id=p_guest
      AND assignment.tag_id=p_tag AND tag.sensitivity='internal'
  )) AND (p_group IS NULL OR EXISTS (
    SELECT 1 FROM eogp.guest_group_memberships membership
    WHERE membership.organization_id=p_org AND membership.event_id=p_event AND membership.participation_id=p_guest
      AND membership.group_id=p_group
  ))
$function$;

CREATE FUNCTION eogp.read_event_guest_list(
  p_org uuid, p_event uuid, p_actor uuid, p_status text, p_offset integer, p_category uuid, p_unassigned boolean, p_name_query text,
  p_tag uuid, p_group uuid
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_event_status text;
  v_can_manage boolean;
  v_rows jsonb;
  v_name_query text := lower(btrim(coalesce(p_name_query, '')));
BEGIN
  v_can_manage := eogp.assert_event_guest_list_access(p_org, p_event, p_actor);
  SELECT status INTO v_event_status FROM eogp.events WHERE organization_id = p_org AND id = p_event;
  IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002'; END IF;
  IF length(v_name_query) > 200 OR coalesce(p_offset, -1) NOT BETWEEN 0 AND 100000 OR
     (p_status IS NOT NULL AND p_status NOT IN ('eligible', 'waitlisted', 'withdrawn', 'cancelled', 'ineligible')) THEN
    RAISE EXCEPTION 'invalid guest list filter' USING ERRCODE = '22023';
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'participationId', p.id, 'displayName', p.display_name, 'status', p.status, 'revision', p.revision,
    'categoryCode', p.category_code, 'categoryId', p.category_id, 'participationCode', p.participation_code,
    'tagIds', coalesce((
      SELECT jsonb_agg(tag.id ORDER BY tag.id) FROM eogp.event_participation_tags assignment
      JOIN eogp.guest_tags tag ON tag.organization_id = assignment.organization_id
        AND tag.event_id = assignment.event_id AND tag.id = assignment.tag_id
      WHERE assignment.organization_id = p_org AND assignment.event_id = p_event
        AND assignment.participation_id = p.id AND tag.sensitivity = 'internal'
    ), '[]'::jsonb),
    'groupIds', memberships.group_ids, 'groupRoles', memberships.group_roles
  ) ORDER BY lower(p.display_name), p.id), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT * FROM eogp.event_guest_roster_rows guest
    WHERE guest.organization_id = p_org AND guest.event_id = p_event
      AND eogp.guest_roster_matches_name(guest.display_name, guest.snapshot_first_name, guest.snapshot_last_name, v_name_query)
      AND (p_status IS NULL OR guest.status = p_status)
      AND (p_category IS NULL OR guest.category_id = p_category)
      AND (p_unassigned IS DISTINCT FROM true OR guest.category_code IS NULL)
      AND ((p_tag IS NULL AND p_group IS NULL) OR eogp.guest_roster_matches_memberships(p_org,p_event,guest.id,p_tag,p_group))
    ORDER BY lower(guest.display_name), guest.id
    LIMIT 51 OFFSET p_offset
  ) p
  CROSS JOIN LATERAL (
    SELECT coalesce(jsonb_agg(membership.group_id ORDER BY membership.group_id), '[]'::jsonb) AS group_ids,
      coalesce(jsonb_object_agg(membership.group_id, membership.membership_kind), '{}'::jsonb) AS group_roles
    FROM eogp.guest_group_memberships membership
    WHERE membership.organization_id = p_org AND membership.event_id = p_event AND membership.participation_id = p.id
  ) memberships;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id
  ) VALUES (p_org, p_org, p_actor, 'membership', 'guest.event_roster.viewed', 'event', p_event);

  RETURN jsonb_build_object(
    'people', CASE WHEN jsonb_array_length(v_rows) > 50 THEN v_rows - 50 ELSE v_rows END,
    'canViewRelationships', v_can_manage,
    'canManage', v_can_manage AND v_event_status IN ('draft', 'planned', 'scheduled', 'active'),
    'nextOffset', CASE WHEN jsonb_array_length(v_rows) > 50 AND p_offset < 100000 THEN p_offset + 50 END
  );
END;
$function$;

CREATE FUNCTION eogp.read_event_guest_roster_export(
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
    'displayName', guest.display_name, 'status', guest.status, 'categoryCode', guest.category_code
  ) ORDER BY lower(guest.display_name), guest.id), '[]'::jsonb), count(*)
  INTO v_rows, v_count
  FROM (
    SELECT * FROM eogp.event_guest_roster_rows projected
    WHERE projected.organization_id = p_org AND projected.event_id = p_event
      AND eogp.guest_roster_matches_name(projected.display_name, projected.snapshot_first_name, projected.snapshot_last_name, v_name_query)
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

CREATE OR REPLACE FUNCTION eogp.list_event_guest_saved_views(p_org uuid, p_event uuid, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE v_views jsonb;
BEGIN
  PERFORM eogp.assert_event_guest_saved_view_access(p_org, p_event, p_actor);
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'viewId', id, 'ciphertext', replace(encode(filters_ciphertext, 'base64'), E'\n', ''),
    'status', status_filter, 'category', CASE WHEN unassigned_only THEN 'unassigned' ELSE category_id::text END
  ) || jsonb_strip_nulls(jsonb_build_object('tagId',tag_id,'groupId',group_id)) ORDER BY created_at DESC, id), '[]'::jsonb) INTO v_views
  FROM eogp.event_guest_saved_views WHERE organization_id = p_org AND event_id = p_event AND owner_membership_id = p_actor;
  RETURN v_views;
END;
$function$;

CREATE FUNCTION eogp.save_event_guest_view(
  p_org uuid, p_event uuid, p_actor uuid, p_view uuid, p_label_hash text, p_ciphertext bytea,
  p_status text, p_category uuid, p_unassigned boolean, p_tag uuid, p_group uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  PERFORM eogp.assert_event_guest_saved_view_access(p_org, p_event, p_actor);
  IF p_tag IS NOT NULL AND NOT EXISTS (SELECT 1 FROM eogp.guest_tags
    WHERE organization_id=p_org AND event_id=p_event AND id=p_tag AND sensitivity='internal') THEN
    RAISE EXCEPTION 'invalid saved roster tag filter' USING ERRCODE='22023';
  END IF;
  INSERT INTO eogp.event_guest_saved_views (
    id, organization_id, event_id, owner_membership_id, label_hash, filters_ciphertext, status_filter, category_id, unassigned_only, tag_id, group_id
  ) VALUES (p_view, p_org, p_event, p_actor, p_label_hash, p_ciphertext, p_status, p_category, p_unassigned, p_tag, p_group);
  INSERT INTO eogp.audit_events (organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id)
  VALUES (p_org, p_org, p_actor, 'membership', 'guest.roster_view.created', 'event_guest_saved_view', p_view);
  RETURN jsonb_build_object('viewId', p_view);
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.read_event_guest_list(
  p_org uuid,p_event uuid,p_actor uuid,p_status text,p_offset integer,p_category uuid,p_unassigned boolean,p_name_query text
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
  SELECT eogp.read_event_guest_list(p_org,p_event,p_actor,p_status,p_offset,p_category,p_unassigned,p_name_query,NULL,NULL)
$function$;

CREATE OR REPLACE FUNCTION eogp.read_event_guest_roster_export(
  p_org uuid,p_event uuid,p_actor uuid,p_status text,p_category uuid,p_unassigned boolean,p_name_query text
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
  SELECT eogp.read_event_guest_roster_export(p_org,p_event,p_actor,p_status,p_category,p_unassigned,p_name_query,NULL,NULL)
$function$;

CREATE OR REPLACE FUNCTION eogp.save_event_guest_view(
  p_org uuid,p_event uuid,p_actor uuid,p_view uuid,p_label_hash text,p_ciphertext bytea,
  p_status text,p_category uuid,p_unassigned boolean
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
  SELECT eogp.save_event_guest_view(p_org,p_event,p_actor,p_view,p_label_hash,p_ciphertext,
    p_status,p_category,p_unassigned,NULL,NULL)
$function$;

REVOKE ALL ON FUNCTION eogp.guest_roster_matches_memberships(uuid,uuid,uuid,uuid,uuid),
  eogp.read_event_guest_list(uuid,uuid,uuid,text,integer,uuid,boolean,text,uuid,uuid),
  eogp.read_event_guest_roster_export(uuid,uuid,uuid,text,uuid,boolean,text,uuid,uuid),
  eogp.save_event_guest_view(uuid,uuid,uuid,uuid,text,bytea,text,uuid,boolean,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.read_event_guest_list(uuid,uuid,uuid,text,integer,uuid,boolean,text,uuid,uuid),
  eogp.read_event_guest_roster_export(uuid,uuid,uuid,text,uuid,boolean,text,uuid,uuid),
  eogp.save_event_guest_view(uuid,uuid,uuid,uuid,text,bytea,text,uuid,boolean,uuid,uuid) TO eventor_runtime;
