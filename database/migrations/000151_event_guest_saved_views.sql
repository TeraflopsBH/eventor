ALTER TABLE eogp.event_guest_categories
  ADD CONSTRAINT event_guest_categories_event_id_key UNIQUE (organization_id, event_id, id);

CREATE TABLE eogp.event_guest_saved_views (
  id uuid PRIMARY KEY,
  organization_id uuid NOT NULL,
  event_id uuid NOT NULL,
  owner_membership_id uuid NOT NULL,
  label_hash text NOT NULL CHECK (label_hash ~ '^[0-9a-f]{64}$'),
  filters_ciphertext bytea NOT NULL CHECK (
    octet_length(filters_ciphertext) BETWEEN 33 AND 4096 AND substring(filters_ciphertext FROM 1 FOR 4) = convert_to('ECP1', 'UTF8')
  ),
  status_filter text CHECK (status_filter IN ('eligible','waitlisted','withdrawn','cancelled','ineligible')),
  category_id uuid,
  unassigned_only boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, event_id, owner_membership_id, label_hash),
  FOREIGN KEY (organization_id, event_id) REFERENCES eogp.events(organization_id, id),
  FOREIGN KEY (organization_id, owner_membership_id) REFERENCES eogp.organization_memberships(organization_id, id),
  FOREIGN KEY (organization_id, event_id, category_id) REFERENCES eogp.event_guest_categories(organization_id, event_id, id),
  CHECK (NOT unassigned_only OR category_id IS NULL)
);
ALTER TABLE eogp.event_guest_saved_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.event_guest_saved_views FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON eogp.event_guest_saved_views
  USING (organization_id = eogp.current_organization_id())
  WITH CHECK (organization_id = eogp.current_organization_id());
REVOKE ALL ON eogp.event_guest_saved_views FROM PUBLIC, eventor_runtime;

CREATE FUNCTION eogp.assert_event_guest_saved_view_access(p_org uuid, p_event uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  IF nullif(current_setting('app.actor_membership_id', true), '')::uuid IS DISTINCT FROM p_actor THEN
    RAISE EXCEPTION 'staff actor context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_event_guest_list_access(p_org, p_event, p_actor);
  IF NOT EXISTS (SELECT 1 FROM eogp.events WHERE organization_id = p_org AND id = p_event) THEN
    RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002';
  END IF;
END;
$function$;

CREATE FUNCTION eogp.list_event_guest_saved_views(p_org uuid, p_event uuid, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE v_views jsonb;
BEGIN
  PERFORM eogp.assert_event_guest_saved_view_access(p_org, p_event, p_actor);
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'viewId', id, 'ciphertext', replace(encode(filters_ciphertext, 'base64'), E'\n', ''),
    'status', status_filter, 'category', CASE WHEN unassigned_only THEN 'unassigned' ELSE category_id::text END
  ) ORDER BY created_at DESC, id), '[]'::jsonb) INTO v_views
  FROM eogp.event_guest_saved_views WHERE organization_id = p_org AND event_id = p_event AND owner_membership_id = p_actor;
  RETURN v_views;
END;
$function$;

CREATE FUNCTION eogp.save_event_guest_view(
  p_org uuid, p_event uuid, p_actor uuid, p_view uuid, p_label_hash text, p_ciphertext bytea,
  p_status text, p_category uuid, p_unassigned boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  PERFORM eogp.assert_event_guest_saved_view_access(p_org, p_event, p_actor);
  INSERT INTO eogp.event_guest_saved_views (
    id, organization_id, event_id, owner_membership_id, label_hash, filters_ciphertext, status_filter, category_id, unassigned_only
  ) VALUES (p_view, p_org, p_event, p_actor, p_label_hash, p_ciphertext, p_status, p_category, p_unassigned);
  INSERT INTO eogp.audit_events (organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id)
  VALUES (p_org, p_org, p_actor, 'membership', 'guest.roster_view.created', 'event_guest_saved_view', p_view);
  RETURN jsonb_build_object('viewId', p_view);
END;
$function$;

CREATE FUNCTION eogp.delete_event_guest_saved_view(p_org uuid, p_event uuid, p_actor uuid, p_view uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  PERFORM eogp.assert_event_guest_saved_view_access(p_org, p_event, p_actor);
  DELETE FROM eogp.event_guest_saved_views
    WHERE organization_id = p_org AND event_id = p_event AND owner_membership_id = p_actor AND id = p_view;
  IF NOT FOUND THEN RAISE EXCEPTION 'saved view not found' USING ERRCODE = 'P0002'; END IF;
  INSERT INTO eogp.audit_events (organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id)
  VALUES (p_org, p_org, p_actor, 'membership', 'guest.roster_view.deleted', 'event_guest_saved_view', p_view);
  RETURN jsonb_build_object('viewId', p_view);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.assert_event_guest_saved_view_access(uuid,uuid,uuid),
  eogp.list_event_guest_saved_views(uuid,uuid,uuid), eogp.save_event_guest_view(uuid,uuid,uuid,uuid,text,bytea,text,uuid,boolean),
  eogp.delete_event_guest_saved_view(uuid,uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.assert_event_guest_saved_view_access(uuid,uuid,uuid),
  eogp.list_event_guest_saved_views(uuid,uuid,uuid), eogp.save_event_guest_view(uuid,uuid,uuid,uuid,text,bytea,text,uuid,boolean),
  eogp.delete_event_guest_saved_view(uuid,uuid,uuid,uuid) TO eventor_runtime;
