-- Contract/privilege smoke for staff-recorded RSVP command.
DO $block$
DECLARE
  v_function regprocedure :=
    'eogp.record_staff_rsvp_response(uuid,uuid,uuid,uuid,text,text,text,timestamptz,uuid,bytea)'::regprocedure;
  v_security_definer boolean;
  v_source text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM eogp.permissions WHERE code = 'rsvp.record') THEN
    RAISE EXCEPTION 'rsvp.record permission is missing';
  END IF;

  SELECT prosecdef, prosrc INTO v_security_definer, v_source
    FROM pg_proc WHERE oid = v_function;
  IF NOT v_security_definer OR position('assert_event_command_permission' IN v_source) = 0 THEN
    RAISE EXCEPTION 'staff RSVP command must be SECURITY DEFINER and enforce event permission';
  END IF;

  IF NOT has_function_privilege(current_user, v_function, 'EXECUTE') THEN
    RAISE EXCEPTION 'runtime role cannot execute staff RSVP command';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM pg_proc p
      CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
     WHERE p.oid = v_function
       AND a.grantee = 0
       AND a.privilege_type = 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'staff RSVP command must not be executable by PUBLIC';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger
     WHERE tgrelid = 'eogp.rsvp_responses'::regclass
       AND tgname = 'rsvp_responses_append_only_guard'
       AND NOT tgisinternal
  ) THEN
    RAISE EXCEPTION 'RSVP response history append-only trigger is missing';
  END IF;
END;
$block$;
