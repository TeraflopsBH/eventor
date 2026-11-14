-- Guest bearer capability commands must be callable without exposing lookup tables.
BEGIN;

DO $guest_capability_acl$
DECLARE
  v_rls_enabled boolean;
  v_rls_forced boolean;
BEGIN
  IF to_regprocedure('eogp.resolve_guest_invitation(text)') IS NULL
     OR to_regprocedure('eogp.submit_guest_invitation_rsvp(text,text,text,text,bytea)') IS NULL
     OR to_regprocedure('eogp.get_guest_invitation_rsvp_history(text)') IS NULL
     OR to_regprocedure('eogp.list_guest_invitation_events(uuid,uuid)') IS NULL
     OR to_regprocedure('eogp.list_guest_invitation_participations(uuid,uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'guest invitation runtime or staff projection functions are missing';
  END IF;

  IF has_table_privilege(current_user, 'eogp.guest_invitation_capability_lookup', 'SELECT')
     OR has_table_privilege(current_user, 'eogp.guest_invitation_rsvp_idempotency', 'SELECT') THEN
    RAISE EXCEPTION 'runtime role has direct access to guest capability internals';
  END IF;

  SELECT relation.relrowsecurity, relation.relforcerowsecurity
    INTO v_rls_enabled, v_rls_forced
    FROM pg_class relation
    JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
   WHERE namespace.nspname = 'eogp'
     AND relation.relname = 'guest_invitation_rsvp_idempotency';
  IF NOT COALESCE(v_rls_enabled, false) OR NOT COALESCE(v_rls_forced, false) THEN
    RAISE EXCEPTION 'guest RSVP idempotency records must enforce tenant RLS';
  END IF;

  IF NOT has_function_privilege(current_user, 'eogp.resolve_guest_invitation(text)', 'EXECUTE')
     OR NOT has_function_privilege(current_user, 'eogp.submit_guest_invitation_rsvp(text,text,text,text,bytea)', 'EXECUTE')
     OR NOT has_function_privilege(current_user, 'eogp.get_guest_invitation_rsvp_history(text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'runtime role is missing guest invitation command execution';
  END IF;

  IF to_regprocedure('eogp.issue_guest_invitation(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,bytea,text,bytea,timestamptz,text)') IS NULL
     OR to_regprocedure('eogp.revoke_guest_invitation(uuid,uuid,uuid,text)') IS NULL
     OR to_regprocedure('eogp.discover_pending_invitation_delivery_tenants()') IS NULL
     OR to_regprocedure('eogp.claim_invitation_email_delivery(uuid)') IS NULL
     OR to_regprocedure('eogp.complete_invitation_email_delivery(uuid,uuid,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'staff invitation or email worker functions are missing';
  END IF;

  IF has_table_privilege(current_user, 'eogp.invitation_deliveries', 'SELECT')
     OR has_table_privilege(current_user, 'eogp.invitation_delivery_tenant_queue', 'SELECT') THEN
    RAISE EXCEPTION 'runtime role has direct access to invitation delivery internals';
  END IF;
  IF NOT has_function_privilege(current_user, 'eogp.list_guest_invitation_events(uuid,uuid)', 'EXECUTE')
     OR NOT has_function_privilege(current_user, 'eogp.list_guest_invitation_participations(uuid,uuid,uuid)', 'EXECUTE')
     OR NOT has_function_privilege(current_user,
       'eogp.issue_guest_invitation(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,bytea,text,bytea,timestamptz,text)', 'EXECUTE')
     OR NOT has_function_privilege(current_user, 'eogp.revoke_guest_invitation(uuid,uuid,uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'runtime role is missing staff invitation commands';
  END IF;
  IF NOT has_function_privilege('eventor_worker',
       'eogp.discover_pending_invitation_delivery_tenants()', 'EXECUTE')
     OR NOT has_function_privilege('eventor_worker', 'eogp.claim_invitation_email_delivery(uuid)', 'EXECUTE')
     OR NOT has_function_privilege('eventor_worker', 'eogp.complete_invitation_email_delivery(uuid,uuid,text,text,text)', 'EXECUTE')
     OR has_table_privilege('eventor_worker', 'eogp.invitation_deliveries', 'SELECT') THEN
    RAISE EXCEPTION 'worker invitation delivery privileges are not narrowly scoped';
  END IF;
END;
$guest_capability_acl$;

DO $guest_capability_validation$
BEGIN
  BEGIN
    PERFORM eogp.resolve_guest_invitation('invalid');
    RAISE EXCEPTION 'resolver accepted a malformed token digest';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM eogp.submit_guest_invitation_rsvp('invalid', 'invalid', 'invalid', 'accepted', NULL);
    RAISE EXCEPTION 'RSVP command accepted malformed capability and idempotency digests';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM eogp.get_guest_invitation_rsvp_history('invalid');
    RAISE EXCEPTION 'RSVP history accepted a malformed token digest';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;
END;
$guest_capability_validation$;

ROLLBACK;
