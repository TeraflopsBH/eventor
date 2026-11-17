CREATE TABLE eogp.event_guest_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid NOT NULL,
  code text NOT NULL CHECK (code ~ '^[A-Z0-9][A-Z0-9_-]{0,39}$'),
  label text NOT NULL CHECK (length(btrim(label)) BETWEEN 1 AND 120),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  retired_at timestamptz,
  UNIQUE (organization_id, event_id, code),
  UNIQUE (organization_id, event_id, id, code),
  FOREIGN KEY (organization_id, event_id) REFERENCES eogp.events(organization_id, id)
);

ALTER TABLE eogp.event_guest_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.event_guest_categories FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON eogp.event_guest_categories
  USING (organization_id = eogp.current_organization_id())
  WITH CHECK (organization_id = eogp.current_organization_id());
REVOKE ALL ON eogp.event_guest_categories FROM PUBLIC, eventor_runtime;

-- Existing event participations may carry legacy codes. Keep those readable.
ALTER TABLE eogp.event_participations
  ADD COLUMN category_id uuid,
  ADD CHECK (category_id IS NULL OR category_code IS NOT NULL),
  ADD FOREIGN KEY (organization_id, event_id, category_id, category_code)
    REFERENCES eogp.event_guest_categories(organization_id, event_id, id, code);

CREATE FUNCTION eogp.assert_event_guest_category_write(p_org uuid, p_event uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_status text;
BEGIN
  IF nullif(current_setting('app.actor_membership_id', true), '')::uuid IS DISTINCT FROM p_actor THEN
    RAISE EXCEPTION 'staff actor context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_event_command_permission(p_org, p_event, p_actor, 'guest.manage');
  SELECT status INTO v_status FROM eogp.events WHERE organization_id = p_org AND id = p_event FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002'; END IF;
  IF v_status NOT IN ('draft', 'planned', 'scheduled', 'active') THEN
    RAISE EXCEPTION 'event guest categories cannot be changed in this phase' USING ERRCODE = '55000';
  END IF;
END;
$function$;

CREATE FUNCTION eogp.list_event_guest_categories(p_org uuid, p_event uuid, p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_categories jsonb;
BEGIN
  IF nullif(current_setting('app.actor_membership_id', true), '')::uuid IS DISTINCT FROM p_actor THEN
    RAISE EXCEPTION 'staff actor context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_event_guest_list_access(p_org, p_event, p_actor);
  IF NOT EXISTS (SELECT 1 FROM eogp.events WHERE organization_id = p_org AND id = p_event) THEN
    RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'categoryId', id, 'code', code, 'label', label, 'retired', retired_at IS NOT NULL
  ) ORDER BY retired_at IS NOT NULL, lower(label), code), '[]'::jsonb)
  INTO v_categories FROM eogp.event_guest_categories WHERE organization_id = p_org AND event_id = p_event;
  RETURN v_categories;
END;
$function$;

CREATE FUNCTION eogp.write_event_guest_category(
  p_org uuid, p_event uuid, p_actor uuid, p_category uuid, p_code text, p_label text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_category eogp.event_guest_categories%ROWTYPE;
  v_action text;
BEGIN
  PERFORM eogp.assert_event_guest_category_write(p_org, p_event, p_actor);
  IF p_category IS NULL THEN
    IF p_code IS NULL OR p_code !~ '^[A-Z0-9][A-Z0-9_-]{0,39}$'
       OR coalesce(length(btrim(p_label)), 0) NOT BETWEEN 1 AND 120
       OR p_label ~ '[[:cntrl:]]' THEN
      RAISE EXCEPTION 'invalid guest category code or label' USING ERRCODE = '22023';
    END IF;
    INSERT INTO eogp.event_guest_categories (organization_id, event_id, code, label)
    VALUES (p_org, p_event, p_code, btrim(p_label)) RETURNING * INTO v_category;
    v_action := 'guest.category.created';
  ELSE
    UPDATE eogp.event_guest_categories SET retired_at = clock_timestamp()
    WHERE organization_id = p_org AND event_id = p_event AND id = p_category AND retired_at IS NULL
    RETURNING * INTO v_category;
    IF NOT FOUND THEN
      SELECT * INTO v_category FROM eogp.event_guest_categories
      WHERE organization_id = p_org AND event_id = p_event AND id = p_category;
      IF NOT FOUND THEN RAISE EXCEPTION 'guest category not found' USING ERRCODE = 'P0002'; END IF;
      RETURN jsonb_build_object('categoryId', v_category.id, 'code', v_category.code, 'label', v_category.label, 'retired', true);
    END IF;
    v_action := 'guest.category.retired';
  END IF;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', v_action, 'event_guest_category', v_category.id,
    jsonb_build_object('eventId', p_event)
  );
  RETURN jsonb_build_object('categoryId', v_category.id, 'code', v_category.code,
    'label', v_category.label, 'retired', v_category.retired_at IS NOT NULL);
END;
$function$;

CREATE FUNCTION eogp.set_event_guest_category(
  p_org uuid, p_event uuid, p_actor uuid, p_participation uuid, p_expected_revision integer, p_category uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_previous eogp.event_participations%ROWTYPE;
  v_category eogp.event_guest_categories%ROWTYPE;
  v_revision integer;
BEGIN
  PERFORM eogp.assert_event_guest_category_write(p_org, p_event, p_actor);
  SELECT * INTO v_previous FROM eogp.event_participations
  WHERE organization_id = p_org AND event_id = p_event AND id = p_participation FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'participation not found' USING ERRCODE = 'P0002'; END IF;
  IF p_expected_revision IS DISTINCT FROM v_previous.revision THEN
    RAISE EXCEPTION 'participation revision conflict' USING ERRCODE = '40001';
  END IF;
  IF v_previous.status = 'cancelled' THEN
    RAISE EXCEPTION 'cancelled participation cannot be edited' USING ERRCODE = '55000';
  END IF;
  IF p_category IS NOT NULL THEN
    SELECT * INTO v_category FROM eogp.event_guest_categories
    WHERE organization_id = p_org AND event_id = p_event AND id = p_category;
    IF NOT FOUND THEN RAISE EXCEPTION 'guest category not found' USING ERRCODE = 'P0002'; END IF;
    IF v_category.retired_at IS NOT NULL THEN
      RAISE EXCEPTION 'retired categories cannot be assigned' USING ERRCODE = '55000';
    END IF;
  END IF;
  v_revision := v_previous.revision;
  IF v_previous.category_id IS DISTINCT FROM p_category OR v_previous.category_code IS DISTINCT FROM v_category.code THEN
    UPDATE eogp.event_participations
    SET category_id = p_category, category_code = v_category.code, revision = revision + 1, updated_at = clock_timestamp()
    WHERE organization_id = p_org AND event_id = p_event AND id = p_participation RETURNING revision INTO v_revision;
    INSERT INTO eogp.audit_events (
      organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
    ) VALUES (
      p_org, p_org, p_actor, 'membership', 'guest.participation.category_changed', 'event_participation', p_participation,
      jsonb_build_object('eventId', p_event, 'previousCategoryId', v_previous.category_id, 'categoryId', p_category, 'revision', v_revision)
    );
  END IF;
  RETURN jsonb_build_object('participationId', p_participation, 'revision', v_revision, 'categoryId', p_category);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.assert_event_guest_category_write(uuid,uuid,uuid),
  eogp.list_event_guest_categories(uuid,uuid,uuid), eogp.write_event_guest_category(uuid,uuid,uuid,uuid,text,text),
  eogp.set_event_guest_category(uuid,uuid,uuid,uuid,integer,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.list_event_guest_categories(uuid,uuid,uuid),
  eogp.write_event_guest_category(uuid,uuid,uuid,uuid,text,text),
  eogp.set_event_guest_category(uuid,uuid,uuid,uuid,integer,uuid) TO eventor_runtime;

CREATE OR REPLACE VIEW eogp.event_guest_roster_rows WITH (security_invoker = true) AS
SELECT participation.organization_id, participation.event_id, participation.id,
  coalesce(participation.person_identity_snapshot->>'displayName', nullif(person.display_name, ''),
           nullif(person.preferred_name, ''), concat_ws(' ', person.first_name, person.last_name)) AS display_name,
  participation.status, participation.revision, participation.category_code, participation.participation_code, participation.category_id
FROM eogp.event_participations participation
JOIN eogp.persons person ON person.organization_id = participation.organization_id AND person.id = participation.person_id;

CREATE OR REPLACE FUNCTION eogp.read_event_guest_list(p_org uuid, p_event uuid, p_actor uuid, p_status text, p_offset integer)
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
