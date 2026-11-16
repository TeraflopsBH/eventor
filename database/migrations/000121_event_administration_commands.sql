-- Event administration command/query boundary.
-- Event metadata has its own optimistic revision; current_revision remains the
-- immutable schedule revision number used by event change requests.

ALTER TABLE eogp.events
  ADD COLUMN details_revision integer NOT NULL DEFAULT 1
    CHECK (details_revision > 0);

CREATE INDEX events_organization_status_updated_idx
  ON eogp.events (organization_id, status, updated_at DESC);

CREATE FUNCTION eogp.create_organizer_event(
  p_organization_id uuid,
  p_actor_membership_id uuid,
  p_event_code text,
  p_title text,
  p_description_internal text,
  p_starts_at timestamptz,
  p_ends_at timestamptz,
  p_timezone_name text,
  p_venue_summary jsonb,
  p_schedule_snapshot jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp, public
AS $function$
DECLARE
  v_event_id uuid := gen_random_uuid();
  v_code text := upper(btrim(coalesce(p_event_code,'')));
  v_title text := btrim(coalesce(p_title,''));
  v_schedule_revision_id uuid := gen_random_uuid();
  v_capability_set_id uuid := gen_random_uuid();
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;

  PERFORM 1
    FROM eogp.organization_memberships m
   WHERE m.organization_id = p_organization_id
     AND m.id = p_actor_membership_id
     AND m.status = 'active'
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'active organization membership required' USING ERRCODE='42501';
  END IF;

  IF v_code !~ '^[A-Z0-9][A-Z0-9_-]{1,79}$'
     OR length(v_title) NOT BETWEEN 2 AND 250
     OR (p_description_internal IS NOT NULL AND length(p_description_internal) > 10000)
     OR p_starts_at IS NULL OR p_ends_at IS NULL OR p_ends_at <= p_starts_at
     OR p_timezone_name IS NULL
     OR NOT EXISTS (SELECT 1 FROM pg_catalog.pg_timezone_names WHERE name = p_timezone_name)
     OR jsonb_typeof(coalesce(p_venue_summary,'{}'::jsonb)) <> 'object'
     OR jsonb_typeof(coalesce(p_schedule_snapshot,'{}'::jsonb)) <> 'object' THEN
    RAISE EXCEPTION 'event details or schedule are invalid' USING ERRCODE='22023';
  END IF;

  -- The new event has no event-scoped grants yet. The helper accepts an
  -- organization-scoped event.manage grant and serializes permission revocation.
  PERFORM eogp.assert_event_command_permission(
    p_organization_id, v_event_id, p_actor_membership_id, 'event.manage'
  );

  INSERT INTO eogp.events (
    id, organization_id, event_code, title, description_internal,
    status, timezone_name, current_revision, details_revision,
    created_by_membership_id
  ) VALUES (
    v_event_id, p_organization_id, v_code, v_title, nullif(btrim(p_description_internal),''),
    'draft', p_timezone_name, 1, 1, p_actor_membership_id
  );

  INSERT INTO eogp.event_schedule_revisions (
    id, organization_id, event_id, revision_number, schedule_kind,
    starts_at, ends_at, timezone_name, venue_summary, schedule_snapshot,
    created_by_membership_id
  ) VALUES (
    v_schedule_revision_id, p_organization_id, v_event_id, 1, 'original',
    p_starts_at, p_ends_at, p_timezone_name,
    coalesce(p_venue_summary,'{}'::jsonb),
    coalesce(p_schedule_snapshot,'{}'::jsonb) ||
      jsonb_build_object(
        'startsAt', p_starts_at,
        'endsAt', p_ends_at,
        'timezoneName', p_timezone_name
      ),
    p_actor_membership_id
  );

  INSERT INTO eogp.event_capability_sets (
    id, organization_id, event_id, current_revision_number
  ) VALUES (v_capability_set_id, p_organization_id, v_event_id, 1);

  INSERT INTO eogp.event_capability_revisions (
    organization_id, capability_set_id, revision_number, capabilities, state
  ) VALUES (
    p_organization_id, v_capability_set_id, 1, '{}'::jsonb, 'draft'
  );

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, reason_code, safe_metadata
  ) VALUES (
    p_organization_id, p_organization_id, p_actor_membership_id, 'membership',
    'event.created', 'event', v_event_id, 'event_created',
    jsonb_build_object(
      'eventCode', v_code,
      'detailsRevision', 1,
      'scheduleRevision', 1
    )
  );

  RETURN jsonb_build_object(
    'eventId', v_event_id,
    'eventCode', v_code,
    'title', v_title,
    'descriptionInternal', nullif(btrim(p_description_internal),''),
    'status', 'draft',
    'detailsRevision', 1,
    'currentRevision', 1,
    'scheduleRevisionId', v_schedule_revision_id,
    'startsAt', p_starts_at,
    'endsAt', p_ends_at,
    'timezoneName', p_timezone_name
  );
END;
$function$;

CREATE FUNCTION eogp.list_organizer_events(
  p_organization_id uuid,
  p_actor_membership_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp, public
AS $function$
DECLARE
  v_event record;
  v_result jsonb := '[]'::jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;

  PERFORM 1
    FROM eogp.organization_memberships m
   WHERE m.organization_id = p_organization_id
     AND m.id = p_actor_membership_id
     AND m.status = 'active'
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'active organization membership required' USING ERRCODE='42501';
  END IF;

  FOR v_event IN
    SELECT e.id, e.event_code, e.title, e.description_internal, e.status,
           e.current_revision, e.details_revision, e.timezone_name,
           e.created_at, e.updated_at,
           s.id AS schedule_revision_id, s.revision_number AS schedule_revision_number,
           s.starts_at, s.ends_at, s.timezone_name AS schedule_timezone_name,
           s.venue_summary
      FROM eogp.events e
      LEFT JOIN LATERAL (
        SELECT sr.id, sr.revision_number, sr.starts_at, sr.ends_at,
               sr.timezone_name, sr.venue_summary
          FROM eogp.event_schedule_revisions sr
         WHERE sr.organization_id = e.organization_id
           AND sr.event_id = e.id
         ORDER BY sr.revision_number DESC
         LIMIT 1
      ) s ON true
     WHERE e.organization_id = p_organization_id
     ORDER BY e.updated_at DESC, e.id
  LOOP
    BEGIN
      PERFORM eogp.assert_event_command_permission(
        p_organization_id, v_event.id, p_actor_membership_id, 'event.manage'
      );
      v_result := v_result || jsonb_build_array(jsonb_build_object(
        'eventId', v_event.id,
        'eventCode', v_event.event_code,
        'title', v_event.title,
        'descriptionInternal', v_event.description_internal,
        'status', v_event.status,
        'currentRevision', v_event.current_revision,
        'detailsRevision', v_event.details_revision,
        'timezoneName', v_event.timezone_name,
        'createdAt', v_event.created_at,
        'updatedAt', v_event.updated_at,
        'scheduleRevisionId', v_event.schedule_revision_id,
        'scheduleRevisionNumber', v_event.schedule_revision_number,
        'startsAt', v_event.starts_at,
        'endsAt', v_event.ends_at,
        'scheduleTimezoneName', v_event.schedule_timezone_name,
        'venueSummary', coalesce(v_event.venue_summary,'{}'::jsonb)
      ));
    EXCEPTION WHEN insufficient_privilege THEN
      NULL;
    END;
  END LOOP;

  RETURN v_result;
END;
$function$;

CREATE FUNCTION eogp.update_organizer_event_details(
  p_organization_id uuid,
  p_event_id uuid,
  p_actor_membership_id uuid,
  p_expected_details_revision integer,
  p_title text,
  p_description_internal text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp, public
AS $function$
DECLARE
  v_event eogp.events%ROWTYPE;
  v_title text := btrim(coalesce(p_title,''));
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;

  PERFORM eogp.assert_event_command_permission(
    p_organization_id, p_event_id, p_actor_membership_id, 'event.manage'
  );

  SELECT * INTO v_event
    FROM eogp.events
   WHERE organization_id = p_organization_id
     AND id = p_event_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'event not found' USING ERRCODE='P0002';
  END IF;

  IF v_event.status = 'archived' THEN
    RAISE EXCEPTION 'archived events cannot be edited' USING ERRCODE='55000';
  END IF;
  IF p_expected_details_revision IS NULL
     OR p_expected_details_revision <> v_event.details_revision THEN
    RAISE EXCEPTION 'event details revision conflict' USING ERRCODE='40001';
  END IF;
  IF length(v_title) NOT BETWEEN 2 AND 250
     OR (p_description_internal IS NOT NULL AND length(p_description_internal) > 10000) THEN
    RAISE EXCEPTION 'event details are invalid' USING ERRCODE='22023';
  END IF;

  UPDATE eogp.events
     SET title = v_title,
         description_internal = nullif(btrim(p_description_internal),''),
         details_revision = details_revision + 1,
         updated_at = clock_timestamp()
   WHERE organization_id = p_organization_id
     AND id = p_event_id
  RETURNING * INTO v_event;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, reason_code, safe_metadata
  ) VALUES (
    p_organization_id, p_organization_id, p_actor_membership_id, 'membership',
    'event.details.updated', 'event', p_event_id, 'event_details_updated',
    jsonb_build_object('detailsRevision', v_event.details_revision)
  );

  RETURN jsonb_build_object(
    'eventId', v_event.id,
    'eventCode', v_event.event_code,
    'title', v_event.title,
    'descriptionInternal', v_event.description_internal,
    'status', v_event.status,
    'detailsRevision', v_event.details_revision,
    'currentRevision', v_event.current_revision,
    'updatedAt', v_event.updated_at
  );
END;
$function$;

CREATE FUNCTION eogp.archive_organizer_event(
  p_organization_id uuid,
  p_event_id uuid,
  p_actor_membership_id uuid,
  p_expected_details_revision integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp, public
AS $function$
DECLARE
  v_event eogp.events%ROWTYPE;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;

  PERFORM eogp.assert_event_command_permission(
    p_organization_id, p_event_id, p_actor_membership_id, 'event.manage'
  );

  SELECT * INTO v_event
    FROM eogp.events
   WHERE organization_id = p_organization_id
     AND id = p_event_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'event not found' USING ERRCODE='P0002';
  END IF;

  IF v_event.status = 'archived' THEN
    RETURN jsonb_build_object(
      'eventId', v_event.id, 'status', 'archived',
      'detailsRevision', v_event.details_revision, 'alreadyArchived', true
    );
  END IF;
  IF p_expected_details_revision IS NULL
     OR p_expected_details_revision <> v_event.details_revision THEN
    RAISE EXCEPTION 'event details revision conflict' USING ERRCODE='40001';
  END IF;
  IF v_event.status IN ('active','scheduled')
     OR EXISTS (
       SELECT 1 FROM eogp.event_sessions s
        WHERE s.organization_id = p_organization_id
          AND s.event_id = p_event_id
          AND s.status IN ('scheduled','active')
     ) THEN
    RAISE EXCEPTION 'active or scheduled event sessions must be completed or cancelled before archiving'
      USING ERRCODE='55000';
  END IF;

  UPDATE eogp.events
     SET status = 'archived',
         details_revision = details_revision + 1,
         updated_at = clock_timestamp()
   WHERE organization_id = p_organization_id
     AND id = p_event_id
  RETURNING * INTO v_event;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, reason_code, safe_metadata
  ) VALUES (
    p_organization_id, p_organization_id, p_actor_membership_id, 'membership',
    'event.archived', 'event', p_event_id, 'event_archived',
    jsonb_build_object('detailsRevision', v_event.details_revision)
  );

  RETURN jsonb_build_object(
    'eventId', v_event.id, 'status', v_event.status,
    'detailsRevision', v_event.details_revision, 'alreadyArchived', false
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.create_organizer_event(uuid,uuid,text,text,text,timestamptz,timestamptz,text,jsonb,jsonb)
  FROM PUBLIC, eventor_worker, eventor_auth;
REVOKE ALL ON FUNCTION eogp.list_organizer_events(uuid,uuid)
  FROM PUBLIC, eventor_worker, eventor_auth;
REVOKE ALL ON FUNCTION eogp.update_organizer_event_details(uuid,uuid,uuid,integer,text,text)
  FROM PUBLIC, eventor_worker, eventor_auth;
REVOKE ALL ON FUNCTION eogp.archive_organizer_event(uuid,uuid,uuid,integer)
  FROM PUBLIC, eventor_worker, eventor_auth;

GRANT EXECUTE ON FUNCTION eogp.create_organizer_event(uuid,uuid,text,text,text,timestamptz,timestamptz,text,jsonb,jsonb)
  TO eventor_runtime;
GRANT EXECUTE ON FUNCTION eogp.list_organizer_events(uuid,uuid)
  TO eventor_runtime;
GRANT EXECUTE ON FUNCTION eogp.update_organizer_event_details(uuid,uuid,uuid,integer,text,text)
  TO eventor_runtime;
GRANT EXECUTE ON FUNCTION eogp.archive_organizer_event(uuid,uuid,uuid,integer)
  TO eventor_runtime;
