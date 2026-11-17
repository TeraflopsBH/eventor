INSERT INTO eogp.permissions (code, description, scope_kind, is_sensitive)
VALUES ('guest.registry.merge', 'Review, merge and restore duplicate guest profiles', 'organization', true);

CREATE TABLE eogp.person_merge_records (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  source_person_id uuid NOT NULL,
  destination_person_id uuid NOT NULL,
  source_revision integer NOT NULL CHECK (source_revision > 0),
  destination_revision integer NOT NULL CHECK (destination_revision > 0),
  review_audit_id uuid NOT NULL,
  resolution jsonb NOT NULL CHECK (jsonb_typeof(resolution) = 'object'),
  reason_code text NOT NULL CHECK (reason_code = 'duplicate_profile'),
  merged_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  merged_by_membership_id uuid NOT NULL,
  restored_at timestamptz,
  restored_by_membership_id uuid,
  FOREIGN KEY (organization_id, source_person_id) REFERENCES eogp.persons(organization_id, id),
  FOREIGN KEY (organization_id, destination_person_id) REFERENCES eogp.persons(organization_id, id),
  FOREIGN KEY (organization_id, merged_by_membership_id) REFERENCES eogp.organization_memberships(organization_id, id),
  FOREIGN KEY (organization_id, restored_by_membership_id) REFERENCES eogp.organization_memberships(organization_id, id),
  CHECK (source_person_id <> destination_person_id),
  CHECK ((restored_at IS NULL) = (restored_by_membership_id IS NULL))
);
CREATE UNIQUE INDEX person_merge_records_active_source ON eogp.person_merge_records (organization_id, source_person_id)
  WHERE restored_at IS NULL;
CREATE INDEX person_merge_records_history ON eogp.person_merge_records (organization_id, merged_at DESC, id);
CREATE INDEX persons_merged_into_idx ON eogp.persons (organization_id, merged_into_person_id) WHERE merged_into_person_id IS NOT NULL;
CREATE INDEX event_participations_person_idx ON eogp.event_participations (organization_id, person_id);
CREATE INDEX person_identifiers_person_idx ON eogp.person_identifiers (organization_id, person_id);

ALTER TABLE eogp.person_merge_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.person_merge_records FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON eogp.person_merge_records
  USING (organization_id = eogp.current_organization_id())
  WITH CHECK (organization_id = eogp.current_organization_id());
REVOKE ALL ON eogp.person_merge_records FROM PUBLIC, eventor_runtime;

CREATE FUNCTION eogp.assert_guest_registry_merge_permission(p_org uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  IF nullif(current_setting('app.actor_membership_id', true), '')::uuid IS DISTINCT FROM p_actor THEN
    RAISE EXCEPTION 'staff actor context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_guest_registry_permission(p_org, p_actor, true);
  PERFORM eogp.assert_event_command_permission(p_org, NULL, p_actor, 'guest.registry.merge');
END;
$function$;

CREATE FUNCTION eogp.guest_registry_merge_blocker(p_org uuid, p_source eogp.persons, p_destination eogp.persons)
RETURNS text LANGUAGE sql STABLE SET search_path = pg_catalog, eogp
AS $function$
  SELECT CASE
    WHEN p_source.status <> 'active' OR p_destination.status <> 'active' THEN 'inactive_profile'
    WHEN EXISTS (SELECT 1 FROM eogp.event_participations WHERE organization_id = p_org AND person_id = p_source.id)
      OR EXISTS (SELECT 1 FROM eogp.person_contact_points WHERE organization_id = p_org AND person_id = p_source.id)
      OR EXISTS (SELECT 1 FROM eogp.person_identifiers WHERE organization_id = p_org AND person_id = p_source.id)
      OR EXISTS (SELECT 1 FROM eogp.persons WHERE organization_id = p_org AND merged_into_person_id = p_source.id)
      THEN 'source_has_linked_records'
  END
$function$;

CREATE FUNCTION eogp.preview_guest_registry_merge(p_org uuid, p_actor uuid, p_source uuid, p_destination uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_source eogp.persons%ROWTYPE;
  v_destination eogp.persons%ROWTYPE;
  v_review uuid;
  v_blocker text;
BEGIN
  PERFORM eogp.assert_guest_registry_merge_permission(p_org, p_actor);
  IF p_source = p_destination THEN RAISE EXCEPTION 'choose two profiles' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_source FROM eogp.persons WHERE organization_id = p_org AND id = p_source;
  SELECT * INTO v_destination FROM eogp.persons WHERE organization_id = p_org AND id = p_destination;
  IF v_source.id IS NULL OR v_destination.id IS NULL THEN
    RAISE EXCEPTION 'person not found' USING ERRCODE = 'P0002';
  END IF;
  v_blocker := eogp.guest_registry_merge_blocker(p_org, v_source, v_destination);
  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.registry.merge_reviewed', 'person', p_source,
    jsonb_build_object('destinationPersonId', p_destination, 'sourceRevision', v_source.revision,
      'destinationRevision', v_destination.revision, 'eligible', v_blocker IS NULL)
  ) RETURNING id INTO v_review;
  RETURN jsonb_build_object(
    'reviewId', v_review,
    'source', eogp.guest_registry_person_projection(v_source),
    'destination', eogp.guest_registry_person_projection(v_destination),
    'blocker', v_blocker
  );
END;
$function$;

CREATE FUNCTION eogp.commit_guest_registry_merge(p_org uuid, p_actor uuid, p_source uuid, p_destination uuid,
  p_source_revision integer, p_destination_revision integer, p_reason text, p_review uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_source eogp.persons%ROWTYPE;
  v_destination eogp.persons%ROWTYPE;
  v_merge uuid;
BEGIN
  PERFORM eogp.assert_guest_registry_merge_permission(p_org, p_actor);
  IF p_source = p_destination OR p_reason IS DISTINCT FROM 'duplicate_profile' THEN
    RAISE EXCEPTION 'invalid guest merge request' USING ERRCODE = '22023';
  END IF;
  -- Both profiles are locked in a stable order, including against linking and contact edits.
  PERFORM 1 FROM eogp.persons WHERE organization_id = p_org AND id IN (p_source, p_destination)
  ORDER BY id FOR UPDATE;
  SELECT * INTO v_source FROM eogp.persons WHERE organization_id = p_org AND id = p_source;
  SELECT * INTO v_destination FROM eogp.persons WHERE organization_id = p_org AND id = p_destination;
  IF v_source.id IS NULL OR v_destination.id IS NULL THEN
    RAISE EXCEPTION 'person not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_source.revision IS DISTINCT FROM p_source_revision OR v_destination.revision IS DISTINCT FROM p_destination_revision THEN
    RAISE EXCEPTION 'person revision conflict' USING ERRCODE = '40001';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM eogp.audit_events WHERE organization_id = p_org AND id = p_review
    AND actor_membership_id = p_actor AND aggregate_id = p_source AND action = 'guest.registry.merge_reviewed'
    AND safe_metadata @> jsonb_build_object('destinationPersonId', p_destination, 'sourceRevision', p_source_revision,
      'destinationRevision', p_destination_revision, 'eligible', true))
    OR eogp.guest_registry_merge_blocker(p_org, v_source, v_destination) IS NOT NULL THEN
    RAISE EXCEPTION 'profiles cannot be merged in their current state' USING ERRCODE = '55000';
  END IF;

  INSERT INTO eogp.person_merge_records (
    organization_id, source_person_id, destination_person_id, source_revision, destination_revision,
    resolution, reason_code, merged_by_membership_id, review_audit_id
  ) VALUES (
    p_org, p_source, p_destination, p_source_revision, p_destination_revision,
    '{"firstName":"destination","lastName":"destination","displayName":"destination","preferredName":"destination"}', p_reason, p_actor, p_review
  ) RETURNING id INTO v_merge;
  UPDATE eogp.persons SET status = 'merged', merged_into_person_id = p_destination,
    revision = revision + 1, updated_at = clock_timestamp()
  WHERE organization_id = p_org AND id = p_source;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.registry.merged', 'person', p_source,
    jsonb_build_object('mergeId', v_merge, 'destinationPersonId', p_destination, 'reason', p_reason, 'revision', p_source_revision + 1)
  );
  RETURN jsonb_build_object('mergeId', v_merge, 'sourcePersonId', p_source, 'destinationPersonId', p_destination,
    'sourceRevision', p_source_revision + 1, 'status', 'merged');
END;
$function$;

CREATE FUNCTION eogp.restore_guest_registry_merge(p_org uuid, p_actor uuid, p_merge uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_merge eogp.person_merge_records%ROWTYPE;
  v_revision integer;
BEGIN
  PERFORM eogp.assert_guest_registry_merge_permission(p_org, p_actor);
  SELECT * INTO v_merge FROM eogp.person_merge_records WHERE organization_id = p_org AND id = p_merge FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'guest merge not found' USING ERRCODE = 'P0002'; END IF;
  IF v_merge.restored_at IS NOT NULL THEN
    RETURN jsonb_build_object('mergeId', p_merge, 'sourcePersonId', v_merge.source_person_id,
      'destinationPersonId', v_merge.destination_person_id, 'sourceRevision', v_merge.source_revision + 2, 'status', 'restored');
  END IF;
  UPDATE eogp.persons SET status = 'active', merged_into_person_id = NULL,
    revision = revision + 1, updated_at = clock_timestamp()
  WHERE organization_id = p_org AND id = v_merge.source_person_id
    AND status = 'merged' AND merged_into_person_id = v_merge.destination_person_id AND revision = v_merge.source_revision + 1
  RETURNING revision INTO v_revision;
  IF NOT FOUND THEN RAISE EXCEPTION 'the merged source has changed' USING ERRCODE = '40001'; END IF;

  UPDATE eogp.person_merge_records SET restored_at = clock_timestamp(), restored_by_membership_id = p_actor
  WHERE organization_id = p_org AND id = p_merge;
  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.registry.merge_restored', 'person', v_merge.source_person_id,
    jsonb_build_object('mergeId', p_merge, 'destinationPersonId', v_merge.destination_person_id, 'reason', 'incorrect_match', 'revision', v_revision)
  );
  RETURN jsonb_build_object('mergeId', p_merge, 'sourcePersonId', v_merge.source_person_id,
    'destinationPersonId', v_merge.destination_person_id, 'sourceRevision', v_revision, 'status', 'restored');
END;
$function$;

CREATE FUNCTION eogp.list_guest_registry_merges(p_org uuid, p_actor uuid, p_offset integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_rows jsonb;
BEGIN
  PERFORM eogp.assert_guest_registry_merge_permission(p_org, p_actor);
  IF coalesce(p_offset, -1) NOT BETWEEN 0 AND 100000 THEN
    RAISE EXCEPTION 'invalid merge history offset' USING ERRCODE = '22023';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'mergeId', merge.id,
    'sourceName', concat_ws(' ', source.first_name, source.last_name),
    'destinationName', concat_ws(' ', destination.first_name, destination.last_name),
    'mergedAt', merge.merged_at, 'restoredAt', merge.restored_at
  ) ORDER BY merge.merged_at DESC, merge.id), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT * FROM eogp.person_merge_records WHERE organization_id = p_org
    ORDER BY merged_at DESC, id LIMIT 51 OFFSET p_offset
  ) merge
  JOIN eogp.persons source ON source.organization_id = merge.organization_id AND source.id = merge.source_person_id
  JOIN eogp.persons destination ON destination.organization_id = merge.organization_id AND destination.id = merge.destination_person_id;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id
  ) VALUES (p_org, p_org, p_actor, 'membership', 'guest.registry.merge_history_viewed', 'organization', p_org);
  RETURN jsonb_build_object(
    'merges', CASE WHEN jsonb_array_length(v_rows) > 50 THEN v_rows - 50 ELSE v_rows END,
    'nextOffset', CASE WHEN jsonb_array_length(v_rows) > 50 AND p_offset < 100000 THEN p_offset + 50 END
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.assert_guest_registry_merge_permission(uuid,uuid),
  eogp.guest_registry_merge_blocker(uuid,eogp.persons,eogp.persons), eogp.preview_guest_registry_merge(uuid,uuid,uuid,uuid),
  eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid), eogp.restore_guest_registry_merge(uuid,uuid,uuid),
  eogp.list_guest_registry_merges(uuid,uuid,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.assert_guest_registry_merge_permission(uuid,uuid),
  eogp.preview_guest_registry_merge(uuid,uuid,uuid,uuid), eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid),
  eogp.restore_guest_registry_merge(uuid,uuid,uuid), eogp.list_guest_registry_merges(uuid,uuid,integer) TO eventor_runtime;

CREATE OR REPLACE FUNCTION eogp.read_guest_registry(
  p_org uuid, p_actor uuid, p_person_id uuid, p_query text, p_archived boolean, p_offset integer
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_person eogp.persons%ROWTYPE;
  v_rows jsonb;
  v_can_manage boolean := true;
  v_can_export boolean := true;
  v_can_merge boolean := true;
  v_query text := lower(btrim(coalesce(p_query, '')));
BEGIN
  PERFORM eogp.assert_guest_registry_permission(p_org, p_actor, false);
  IF length(v_query) > 200 OR coalesce(p_offset, -1) NOT BETWEEN 0 AND 100000 THEN
    RAISE EXCEPTION 'invalid directory filter' USING ERRCODE = '22023';
  END IF;

  IF p_person_id IS NOT NULL THEN
    SELECT * INTO v_person FROM eogp.persons WHERE organization_id = p_org AND id = p_person_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'person not found' USING ERRCODE = 'P0002'; END IF;
  END IF;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership',
    CASE WHEN p_person_id IS NULL THEN 'guest.registry.searched' ELSE 'guest.registry.profile_viewed' END,
    CASE WHEN p_person_id IS NULL THEN 'organization' ELSE 'person' END,
    coalesce(p_person_id, p_org), '{}'::jsonb
  );

  IF p_person_id IS NOT NULL THEN RETURN eogp.guest_registry_person_projection(v_person); END IF;

  BEGIN
    PERFORM eogp.assert_guest_registry_permission(p_org, p_actor, true);
  EXCEPTION WHEN insufficient_privilege THEN v_can_manage := false;
  END;

  BEGIN
    PERFORM eogp.assert_event_command_permission(p_org, NULL, p_actor, 'guest.registry.export');
  EXCEPTION WHEN insufficient_privilege THEN v_can_export := false;
  END;

  BEGIN
    PERFORM eogp.assert_guest_registry_merge_permission(p_org, p_actor);
  EXCEPTION WHEN insufficient_privilege THEN v_can_merge := false;
  END;

  SELECT coalesce(jsonb_agg(eogp.guest_registry_person_projection(p)
    ORDER BY lower(p.last_name), lower(p.first_name), p.id), '[]'::jsonb) INTO v_rows
  FROM (
    SELECT person.* FROM eogp.persons person
    WHERE organization_id = p_org
      AND eogp.guest_registry_matches_filter(person, v_query, p_archived)
    ORDER BY lower(last_name), lower(first_name), id
    LIMIT 51 OFFSET p_offset
  ) p;
  RETURN jsonb_build_object(
    'people', CASE WHEN jsonb_array_length(v_rows) > 50 THEN v_rows - 50 ELSE v_rows END, 'canManage', v_can_manage,
    'canExport', v_can_export, 'canMerge', v_can_merge,
    'nextOffset', CASE WHEN jsonb_array_length(v_rows) > 50 AND p_offset < 100000 THEN p_offset + 50 END
  );
END;
$function$;
