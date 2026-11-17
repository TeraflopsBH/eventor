ALTER TABLE eogp.event_sessions
  ADD COLUMN details_revision integer NOT NULL DEFAULT 1 CHECK (details_revision > 0);

CREATE OR REPLACE FUNCTION eogp.list_organizer_event_sessions(
  p_organization_id uuid, p_event_id uuid, p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  PERFORM eogp.assert_event_command_permission(
    p_organization_id, p_event_id, p_actor_membership_id, 'event.manage'
  );

  IF NOT EXISTS (
    SELECT 1 FROM eogp.events WHERE organization_id = p_organization_id AND id = p_event_id
  ) THEN
    RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002';
  END IF;

  RETURN (
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'sessionId', s.id, 'code', s.code, 'title', s.title, 'status', s.status,
      'startsAt', s.starts_at, 'endsAt', s.ends_at, 'timezoneName', s.timezone_name,
      'detailsRevision', s.details_revision
    ) ORDER BY s.starts_at NULLS LAST, s.code), '[]'::jsonb)
    FROM eogp.event_sessions s
    WHERE s.organization_id = p_organization_id AND s.event_id = p_event_id
  );
END;
$function$;

CREATE FUNCTION eogp.update_organizer_event_session(
  p_organization_id uuid, p_event_id uuid, p_session_id uuid, p_actor_membership_id uuid,
  p_expected_details_revision integer, p_title text, p_starts_at timestamptz, p_ends_at timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_event_status text;
  v_session eogp.event_sessions%ROWTYPE;
  v_title text := btrim(coalesce(p_title, ''));
BEGIN
  PERFORM eogp.assert_event_command_permission(
    p_organization_id, p_event_id, p_actor_membership_id, 'event.manage'
  );

  -- Serialize against event archive and disruption before locking the session.
  SELECT status INTO v_event_status FROM eogp.events
    WHERE organization_id = p_organization_id AND id = p_event_id
    FOR UPDATE;

  SELECT * INTO v_session FROM eogp.event_sessions
    WHERE organization_id = p_organization_id AND event_id = p_event_id AND id = p_session_id
    FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'event session not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_event_status NOT IN ('draft', 'planned') OR v_session.status <> 'planned' THEN
    RAISE EXCEPTION 'only planned sessions on a draft or planned event can be edited' USING ERRCODE = '55000';
  END IF;

  IF p_expected_details_revision IS DISTINCT FROM v_session.details_revision THEN
    RAISE EXCEPTION 'session details revision conflict' USING ERRCODE = '40001';
  END IF;

  -- Older rows may have a single timestamp. Preserve that timing on title-only
  -- edits and require a valid pair or two NULLs when timing changes.
  IF length(v_title) NOT BETWEEN 2 AND 250 OR (
    (p_starts_at, p_ends_at) IS DISTINCT FROM (v_session.starts_at, v_session.ends_at)
    AND (
      (p_starts_at IS NULL) <> (p_ends_at IS NULL)
      OR (p_starts_at IS NOT NULL AND (
        NOT isfinite(p_starts_at) OR NOT isfinite(p_ends_at) OR p_ends_at <= p_starts_at
      ))
    )
  ) THEN
    RAISE EXCEPTION 'invalid session details or timing' USING ERRCODE = '22023';
  END IF;

  UPDATE eogp.event_sessions
  SET title = v_title, starts_at = p_starts_at, ends_at = p_ends_at,
      details_revision = details_revision + 1
  WHERE organization_id = p_organization_id AND event_id = p_event_id AND id = p_session_id
  RETURNING * INTO v_session;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, reason_code, safe_metadata
  ) VALUES (
    p_organization_id, p_organization_id, p_actor_membership_id, 'membership',
    'event.session.updated', 'event_session', p_session_id, 'event_session_updated',
    jsonb_build_object('eventId', p_event_id, 'detailsRevision', v_session.details_revision)
  );

  RETURN jsonb_build_object(
    'sessionId', v_session.id, 'code', v_session.code, 'title', v_session.title, 'status', v_session.status,
    'startsAt', v_session.starts_at, 'endsAt', v_session.ends_at, 'timezoneName', v_session.timezone_name,
    'detailsRevision', v_session.details_revision
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.update_organizer_event_session(uuid,uuid,uuid,uuid,integer,text,timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.update_organizer_event_session(uuid,uuid,uuid,uuid,integer,text,timestamptz,timestamptz) TO eventor_runtime;
