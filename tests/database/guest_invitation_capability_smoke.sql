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
     OR to_regprocedure('eogp.list_guest_invitation_participations(uuid,uuid,uuid)') IS NULL
     OR to_regprocedure('eogp.list_guest_invitation_delivery_attempts(uuid,uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'guest invitation runtime or staff projection functions are missing';
  END IF;

  IF has_table_privilege(current_user, 'eogp.guest_invitation_capability_lookup', 'SELECT')
     OR has_table_privilege(current_user, 'eogp.guest_invitation_rsvp_idempotency', 'SELECT')
     OR has_table_privilege(current_user, 'eogp.invitation_delivery_attempts', 'SELECT') THEN
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
     OR NOT has_function_privilege(current_user, 'eogp.list_guest_invitation_delivery_attempts(uuid,uuid,uuid)', 'EXECUTE')
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


DO $guest_rsvp_lock_order$
DECLARE
  v_definition text;
  v_participation_lock integer;
  v_invitation_select integer;
  v_invitation_lock integer;
  v_link_select integer;
  v_link_lock integer;
BEGIN
  SELECT pg_get_functiondef(
    'eogp.submit_guest_invitation_rsvp(text,text,text,text,bytea)'::regprocedure
  ) INTO v_definition;

  v_participation_lock := strpos(v_definition, 'FOR UPDATE;');
  v_invitation_select := strpos(v_definition, 'INTO v_invitation');
  v_invitation_lock := v_invitation_select
    + strpos(substring(v_definition FROM v_invitation_select), 'FOR UPDATE;') - 1;
  v_link_select := strpos(v_definition, 'INTO v_link');
  v_link_lock := v_link_select
    + strpos(substring(v_definition FROM v_link_select), 'FOR UPDATE;') - 1;

  IF v_participation_lock <= 0
     OR v_invitation_select <= v_participation_lock
     OR v_invitation_lock <= v_invitation_select
     OR v_link_select <= v_invitation_lock
     OR v_link_lock <= v_link_select
     OR NOT (
       v_participation_lock < v_invitation_lock
       AND v_invitation_lock < v_link_lock
     ) THEN
    RAISE EXCEPTION 'guest RSVP must lock participation, invitation, then link';
  END IF;
END;
$guest_rsvp_lock_order$;

DO $guest_rsvp_history_capability$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'eogp.get_guest_invitation_rsvp_history(text)'::regprocedure
  ) INTO v_definition;

  IF strpos(v_definition, 'link.revoked_at IS NULL') = 0
     OR strpos(v_definition, 'link.expires_at > clock_timestamp()') = 0
     OR strpos(v_definition, 'invitation.status = ''active''') = 0
     OR strpos(v_definition, 'invitation.current_revision_number = revision.revision_number') = 0
     OR strpos(v_definition, 'revision.issued_at IS NOT NULL') = 0
     OR strpos(v_definition, 'policy.state = ''published''') = 0
     OR strpos(v_definition, 'event.status NOT IN (''completed'', ''cancelled'', ''archived'')') = 0 THEN
    RAISE EXCEPTION 'guest RSVP history must enforce the same live capability state as invitation resolution';
  END IF;
END;
$guest_rsvp_history_capability$;

DO $guest_invitation_delivery_revocation$
DECLARE
  v_definition text;
  v_trigger_enabled boolean;
BEGIN
  SELECT pg_get_functiondef(
    'eogp.suppress_revoked_guest_invitation_delivery()'::regprocedure
  ) INTO v_definition;

  IF strpos(v_definition, 'OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL') = 0
     OR strpos(v_definition, 'delivery.invitation_revision_id=NEW.invitation_revision_id') = 0
     OR strpos(v_definition, 'delivery.status=''queued''') = 0
     OR strpos(v_definition, 'INVITATION_SUPERSEDED') = 0
     OR strpos(v_definition, 'INVITATION_REVOKED') = 0 THEN
    RAISE EXCEPTION 'revoked or superseded invitation links must suppress their queued delivery';
  END IF;

  SELECT trigger_row.tgenabled <> 'D'
    INTO v_trigger_enabled
    FROM pg_trigger trigger_row
   WHERE trigger_row.tgrelid='eogp.invitation_links'::regclass
     AND trigger_row.tgname='invitation_link_suppress_queued_delivery'
     AND NOT trigger_row.tgisinternal;

  IF NOT COALESCE(v_trigger_enabled,false) THEN
    RAISE EXCEPTION 'invitation-link revocation delivery guard trigger is missing or disabled';
  END IF;
END;
$guest_invitation_delivery_revocation$;

ROLLBACK;
