CREATE INDEX person_merge_records_active_historical_destination
  ON eogp.person_merge_records (organization_id, destination_person_id, source_person_id)
  WHERE restored_at IS NULL AND resolution->>'eventParticipation' = 'original_reference_preserved';

CREATE FUNCTION eogp.guest_registry_merge_impact(
  p_org uuid, p_actor uuid, p_source eogp.persons, p_destination eogp.persons
) RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_link record;
  v_events jsonb := '[]'::jsonb;
  v_count integer := 0;
  v_reference text;
BEGIN
  IF p_source.status <> 'active' OR p_destination.status <> 'active' THEN
    RETURN jsonb_build_object('blocker', 'inactive_profile');
  END IF;
  IF EXISTS (SELECT 1 FROM eogp.person_contact_points WHERE organization_id = p_org AND person_id = p_source.id)
    OR EXISTS (SELECT 1 FROM eogp.person_identifiers WHERE organization_id = p_org AND person_id = p_source.id)
    OR EXISTS (SELECT 1 FROM eogp.persons WHERE organization_id = p_org AND merged_into_person_id = p_source.id) THEN
    RETURN jsonb_build_object('blocker', 'source_has_linked_records');
  END IF;

  FOR v_link IN
    SELECT participation.id, event.id AS event_id, event.event_code, event.title, event.status,
      participation.status AS participation_status
    FROM eogp.event_participations participation
    JOIN eogp.events event ON event.organization_id = participation.organization_id AND event.id = participation.event_id
    WHERE participation.organization_id = p_org AND participation.person_id = p_source.id
    ORDER BY participation.id
  LOOP
    BEGIN
      PERFORM eogp.assert_event_guest_list_access(p_org, v_link.event_id, p_actor);
    EXCEPTION WHEN insufficient_privilege THEN
      RETURN jsonb_build_object('blocker', 'event_history_access_required');
    END;
    IF v_link.status NOT IN ('completed', 'cancelled', 'archived') THEN
      RETURN jsonb_build_object('blocker', 'source_has_linked_records');
    END IF;
    IF EXISTS (
      SELECT 1 FROM eogp.event_participations other
      JOIN eogp.persons person ON person.organization_id = other.organization_id AND person.id = other.person_id
      WHERE other.organization_id = p_org AND other.event_id = v_link.event_id
        AND (other.person_id = p_destination.id OR person.merged_into_person_id = p_destination.id)
    ) THEN
      RETURN jsonb_build_object('blocker', 'event_history_overlap');
    END IF;
    v_count := v_count + 1;
    -- Bind the review to the exact preserved participation references without storing them in audit metadata.
    v_reference := encode(sha256(convert_to(coalesce(v_reference, '') || v_link.id::text, 'UTF8')), 'hex');
    IF v_count <= 50 THEN
      v_events := v_events || jsonb_build_array(jsonb_build_object(
        'eventId', v_link.event_id, 'eventCode', v_link.event_code, 'eventTitle', v_link.title,
        'eventStatus', v_link.status, 'status', v_link.participation_status
      ));
    END IF;
  END LOOP;
  RETURN jsonb_build_object('historicalEvents', v_events, 'historicalCount', v_count, 'historicalReference', v_reference);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.guest_registry_merge_impact(uuid,uuid,eogp.persons,eogp.persons) FROM PUBLIC;

CREATE OR REPLACE FUNCTION eogp.preview_guest_registry_merge(p_org uuid, p_actor uuid, p_source uuid, p_destination uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_source eogp.persons%ROWTYPE;
  v_destination eogp.persons%ROWTYPE;
  v_review uuid;
  v_impact jsonb;
BEGIN
  PERFORM eogp.assert_guest_registry_merge_permission(p_org, p_actor);
  IF p_source = p_destination THEN RAISE EXCEPTION 'choose two profiles' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_source FROM eogp.persons WHERE organization_id = p_org AND id = p_source;
  SELECT * INTO v_destination FROM eogp.persons WHERE organization_id = p_org AND id = p_destination;
  IF v_source.id IS NULL OR v_destination.id IS NULL THEN
    RAISE EXCEPTION 'person not found' USING ERRCODE = 'P0002';
  END IF;
  v_impact := eogp.guest_registry_merge_impact(p_org, p_actor, v_source, v_destination);
  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.registry.merge_reviewed', 'person', p_source,
    jsonb_build_object('destinationPersonId', p_destination, 'sourceRevision', v_source.revision,
      'destinationRevision', v_destination.revision, 'eligible', NOT (v_impact ? 'blocker'),
      'historicalReference', v_impact->>'historicalReference')
  ) RETURNING id INTO v_review;
  RETURN jsonb_build_object(
    'reviewId', v_review,
    'source', eogp.guest_registry_person_projection(v_source),
    'destination', eogp.guest_registry_person_projection(v_destination),
    'blocker', v_impact->>'blocker',
    'historicalEvents', coalesce(v_impact->'historicalEvents', '[]'::jsonb),
    'historicalCount', coalesce((v_impact->>'historicalCount')::integer, 0)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.commit_guest_registry_merge(p_org uuid, p_actor uuid, p_source uuid, p_destination uuid,
  p_source_revision integer, p_destination_revision integer, p_reason text, p_review uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_source eogp.persons%ROWTYPE;
  v_destination eogp.persons%ROWTYPE;
  v_merge uuid;
  v_impact jsonb;
  v_resolution jsonb;
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
  v_impact := eogp.guest_registry_merge_impact(p_org, p_actor, v_source, v_destination);
  IF v_impact ? 'blocker' OR NOT EXISTS (SELECT 1 FROM eogp.audit_events WHERE organization_id = p_org AND id = p_review
    AND actor_membership_id = p_actor AND aggregate_id = p_source AND action = 'guest.registry.merge_reviewed'
    AND safe_metadata @> jsonb_build_object('destinationPersonId', p_destination, 'sourceRevision', p_source_revision,
      'destinationRevision', p_destination_revision, 'eligible', true)
    AND safe_metadata->>'historicalReference' IS NOT DISTINCT FROM v_impact->>'historicalReference') THEN
    RAISE EXCEPTION 'profiles cannot be merged in their current state' USING ERRCODE = '55000';
  END IF;

  v_resolution := '{"firstName":"destination","lastName":"destination","displayName":"destination","preferredName":"destination"}';
  IF (v_impact->>'historicalCount')::integer > 0 THEN
    v_resolution := v_resolution || '{"eventParticipation":"original_reference_preserved"}'::jsonb;
  END IF;
  INSERT INTO eogp.person_merge_records (
    organization_id, source_person_id, destination_person_id, source_revision, destination_revision,
    resolution, reason_code, merged_by_membership_id, review_audit_id
  ) VALUES (
    p_org, p_source, p_destination, p_source_revision, p_destination_revision,
    v_resolution, p_reason, p_actor, p_review
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

CREATE OR REPLACE FUNCTION eogp.read_guest_registry_history(p_org uuid, p_actor uuid, p_person uuid, p_offset integer)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_participation record;
  v_participations jsonb := '[]'::jsonb;
  v_changes jsonb;
  v_has_more boolean := false;
  v_skipped integer := 0;
  v_can_manage boolean;
BEGIN
  PERFORM eogp.assert_guest_registry_permission(p_org, p_actor, false);
  IF coalesce(p_offset, -1) NOT BETWEEN 0 AND 100000 THEN
    RAISE EXCEPTION 'invalid history offset' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM eogp.persons WHERE organization_id = p_org AND id = p_person) THEN
    RAISE EXCEPTION 'person not found' USING ERRCODE = 'P0002';
  END IF;

  FOR v_participation IN
    SELECT p.id, p.event_id, p.status, p.revision, p.created_at, e.title, e.event_code, e.status AS event_status,
           p.person_id <> p_person AS from_merged_profile,
           schedule.starts_at
    FROM eogp.event_participations p
    JOIN eogp.events e ON e.organization_id = p.organization_id AND e.id = p.event_id
    LEFT JOIN LATERAL (
      SELECT starts_at FROM eogp.event_schedule_revisions
      WHERE organization_id = e.organization_id AND event_id = e.id
      ORDER BY revision_number DESC LIMIT 1
    ) schedule ON true
    WHERE p.organization_id = p_org AND (p.person_id = p_person OR p.person_id IN (
      SELECT source_person_id FROM eogp.person_merge_records
      WHERE organization_id = p_org AND destination_person_id = p_person AND restored_at IS NULL
        AND resolution->>'eventParticipation' = 'original_reference_preserved'
    ))
    ORDER BY schedule.starts_at DESC NULLS LAST, p.created_at DESC, p.id
  LOOP
    BEGIN
      BEGIN
        PERFORM eogp.assert_event_command_permission(p_org, v_participation.event_id, p_actor, 'guest.manage');
        v_can_manage := true;
      EXCEPTION WHEN insufficient_privilege THEN
        PERFORM eogp.assert_event_command_permission(p_org, v_participation.event_id, p_actor, 'guest.read');
        v_can_manage := false;
      END;
      IF v_skipped < p_offset THEN
        v_skipped := v_skipped + 1;
        CONTINUE;
      END IF;
      IF jsonb_array_length(v_participations) = 50 THEN
        v_has_more := true;
        EXIT;
      END IF;
      v_participations := v_participations || jsonb_build_array(jsonb_build_object(
        'participationId', v_participation.id, 'eventId', v_participation.event_id,
        'eventTitle', v_participation.title, 'eventCode', v_participation.event_code,
        'eventStatus', v_participation.event_status, 'status', v_participation.status,
        'revision', v_participation.revision,
        'fromMergedProfile', v_participation.from_merged_profile,
        'canManage', v_can_manage AND NOT v_participation.from_merged_profile AND v_participation.status <> 'cancelled'
          AND v_participation.event_status IN ('draft', 'planned', 'scheduled', 'active'),
        'eventStartsAt', v_participation.starts_at, 'addedAt', v_participation.created_at
      ));
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END LOOP;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'auditId', change.id, 'action', change.action, 'at', change.occurred_at,
    'revision', change.safe_metadata->'revision'
  ) ORDER BY change.occurred_at DESC, change.id), '[]'::jsonb)
  INTO v_changes
  FROM (
    SELECT id, action, occurred_at, safe_metadata FROM eogp.audit_events
    WHERE organization_id = p_org AND aggregate_type = 'person' AND aggregate_id = p_person
      AND action IN ('guest.registry.create', 'guest.registry.update', 'guest.registry.archive')
    ORDER BY occurred_at DESC, id LIMIT 51 OFFSET p_offset
  ) change;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.registry.history_viewed', 'person', p_person, '{}'::jsonb
  );
  RETURN jsonb_build_object(
    'changes', CASE WHEN jsonb_array_length(v_changes) > 50 THEN v_changes - 50 ELSE v_changes END,
    'participations', v_participations,
    'nextOffset', CASE WHEN (v_has_more OR jsonb_array_length(v_changes) > 50) AND p_offset < 100000 THEN p_offset + 50 END
  );
END;
$function$;

DROP FUNCTION eogp.guest_registry_merge_blocker(uuid,eogp.persons,eogp.persons);
