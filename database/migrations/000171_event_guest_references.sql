CREATE TABLE eogp.event_guest_reference_counters (
  organization_id uuid NOT NULL,
  event_id uuid NOT NULL,
  last_number bigint NOT NULL CHECK (last_number > 0),
  PRIMARY KEY (organization_id,event_id),
  FOREIGN KEY (organization_id,event_id) REFERENCES eogp.events(organization_id,id) ON DELETE CASCADE
);
ALTER TABLE eogp.event_guest_reference_counters ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON eogp.event_guest_reference_counters FROM PUBLIC,eventor_runtime;

CREATE INDEX event_participations_reference_search_idx
  ON eogp.event_participations(organization_id,event_id,lower(btrim(participation_code)));

CREATE FUNCTION eogp.assign_event_guest_reference()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_number text;
BEGIN
  IF TG_OP='UPDATE' AND nullif(btrim(OLD.participation_code),'') IS NOT NULL THEN
    IF NEW.participation_code IS DISTINCT FROM OLD.participation_code THEN
      RAISE EXCEPTION 'event guest reference is immutable' USING ERRCODE='55000';
    END IF;
    RETURN NEW;
  END IF;

  LOOP
    -- The counter row serializes new references within this event, including explicit imports.
    INSERT INTO eogp.event_guest_reference_counters AS counter(organization_id,event_id,last_number)
    VALUES(NEW.organization_id,NEW.event_id,1)
    ON CONFLICT (organization_id,event_id) DO UPDATE SET last_number=counter.last_number+1
    RETURNING last_number::text INTO v_number;

    IF nullif(btrim(NEW.participation_code),'') IS NOT NULL THEN
      IF EXISTS (SELECT 1 FROM eogp.event_participations present WHERE present.organization_id=NEW.organization_id
        AND present.event_id=NEW.event_id AND lower(btrim(present.participation_code))=lower(btrim(NEW.participation_code))) THEN
        RAISE EXCEPTION 'event guest reference is already used' USING ERRCODE='23505';
      END IF;
      RETURN NEW;
    END IF;

    IF length(v_number)<6 THEN v_number := lpad(v_number,6,'0'); END IF;
    IF NOT EXISTS (SELECT 1 FROM eogp.event_participations present WHERE present.organization_id=NEW.organization_id
      AND present.event_id=NEW.event_id AND lower(btrim(present.participation_code))='g-'||v_number) THEN
      NEW.participation_code := 'G-'||v_number;
      RETURN NEW;
    END IF;
  END LOOP;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.assign_event_guest_reference() FROM PUBLIC;
CREATE TRIGGER event_participations_assign_reference
  BEFORE INSERT OR UPDATE OF participation_code ON eogp.event_participations
  FOR EACH ROW EXECUTE FUNCTION eogp.assign_event_guest_reference();

-- The migration fills missing references across tenants under the table owner.
ALTER TABLE eogp.event_participations NO FORCE ROW LEVEL SECURITY;
UPDATE eogp.event_participations SET participation_code=NULL
WHERE nullif(btrim(participation_code),'') IS NULL;
ALTER TABLE eogp.event_participations FORCE ROW LEVEL SECURITY;
ALTER TABLE eogp.event_participations ALTER COLUMN participation_code SET NOT NULL;

CREATE FUNCTION eogp.guest_roster_matches_search(
  p_display_name text,p_first_name text,p_last_name text,p_guest_reference text,p_query text
) RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path = pg_catalog,eogp
AS $function$
  SELECT lower(btrim(p_guest_reference))=p_query
    OR eogp.guest_roster_matches_name(p_display_name,p_first_name,p_last_name,p_query);
$function$;
REVOKE ALL ON FUNCTION eogp.guest_roster_matches_search(text,text,text,text,text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION eogp.read_event_guest_list(
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
    'recordedDisplayName', p.recorded_display_name, 'displayNameOverride', p.display_name_override,
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
      AND eogp.guest_roster_matches_search(guest.display_name, guest.snapshot_first_name, guest.snapshot_last_name,
        guest.participation_code, v_name_query)
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
    'displayName', guest.display_name, 'status', guest.status, 'categoryCode', guest.category_code
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

