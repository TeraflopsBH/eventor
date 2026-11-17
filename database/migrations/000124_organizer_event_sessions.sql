-- Organizer session writes use the same event permission and parent lock as
-- event administration. Existing disruption commands retain owner privileges.
REVOKE INSERT, UPDATE, DELETE ON eogp.event_sessions FROM eventor_runtime;

CREATE FUNCTION eogp.list_organizer_event_sessions(
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
      'startsAt', s.starts_at, 'endsAt', s.ends_at, 'timezoneName', s.timezone_name
    ) ORDER BY s.starts_at NULLS LAST, s.code), '[]'::jsonb)
    FROM eogp.event_sessions s
    WHERE s.organization_id = p_organization_id AND s.event_id = p_event_id
  );
END;
$function$;

CREATE FUNCTION eogp.create_organizer_event_session(
  p_organization_id uuid, p_event_id uuid, p_actor_membership_id uuid,
  p_code text, p_title text, p_starts_at timestamptz, p_ends_at timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_event eogp.events%ROWTYPE;
  v_session eogp.event_sessions%ROWTYPE;
  v_code text := upper(btrim(coalesce(p_code, '')));
  v_title text := btrim(coalesce(p_title, ''));
BEGIN
  PERFORM eogp.assert_event_command_permission(
    p_organization_id, p_event_id, p_actor_membership_id, 'event.manage'
  );

  SELECT * INTO v_event FROM eogp.events
    WHERE organization_id = p_organization_id AND id = p_event_id
    FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'event not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_event.status NOT IN ('draft', 'planned') THEN
    RAISE EXCEPTION 'event must be in planning to add sessions' USING ERRCODE = '55000';
  END IF;

  IF v_code !~ '^[A-Z0-9][A-Z0-9_-]{1,79}$'
     OR length(v_title) NOT BETWEEN 2 AND 250
     OR (p_starts_at IS NULL) <> (p_ends_at IS NULL)
     OR (p_starts_at IS NOT NULL AND (
       NOT isfinite(p_starts_at) OR NOT isfinite(p_ends_at) OR p_ends_at <= p_starts_at
     )) THEN
    RAISE EXCEPTION 'invalid session details or timing' USING ERRCODE = '22023';
  END IF;

  INSERT INTO eogp.event_sessions (
    organization_id, event_id, code, title, starts_at, ends_at, timezone_name, status
  ) VALUES (
    p_organization_id, p_event_id, v_code, v_title, p_starts_at, p_ends_at, v_event.timezone_name, 'planned'
  ) RETURNING * INTO v_session;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, reason_code, safe_metadata
  ) VALUES (
    p_organization_id, p_organization_id, p_actor_membership_id, 'membership',
    'event.session.created', 'event_session', v_session.id, 'event_session_created',
    jsonb_build_object('eventId', p_event_id)
  );

  RETURN jsonb_build_object(
    'sessionId', v_session.id, 'code', v_session.code, 'title', v_session.title, 'status', v_session.status,
    'startsAt', v_session.starts_at, 'endsAt', v_session.ends_at, 'timezoneName', v_session.timezone_name
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.list_organizer_event_sessions(uuid,uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.create_organizer_event_session(uuid,uuid,uuid,text,text,timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.list_organizer_event_sessions(uuid,uuid,uuid) TO eventor_runtime;
GRANT EXECUTE ON FUNCTION eogp.create_organizer_event_session(uuid,uuid,uuid,text,text,timestamptz,timestamptz) TO eventor_runtime;
