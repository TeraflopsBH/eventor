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
     OR to_regprocedure('eogp.list_guest_invitation_delivery_attempts(uuid,uuid,uuid)') IS NULL
     OR to_regprocedure('eogp.current_event_schedule_revision_id(uuid,uuid)') IS NULL
     OR to_regprocedure('eogp.record_staff_guest_rsvp(uuid,uuid,uuid,uuid,text,text,text,timestamptz,uuid,bytea,uuid,text)') IS NULL THEN
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
  IF NOT has_function_privilege(current_user,
       'eogp.record_staff_guest_rsvp(uuid,uuid,uuid,uuid,text,text,text,timestamptz,uuid,bytea,uuid,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'runtime role is missing staff RSVP command execution';
  END IF;

  IF to_regprocedure('eogp.issue_guest_invitation(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,bytea,text,bytea,timestamptz,text)') IS NULL
     OR to_regprocedure('eogp.revoke_guest_invitation(uuid,uuid,uuid,text)') IS NULL
     OR to_regprocedure('eogp.discover_pending_invitation_delivery_tenants()') IS NULL
     OR to_regprocedure('eogp.claim_invitation_email_delivery(uuid)') IS NULL
     OR to_regprocedure('eogp.complete_invitation_email_delivery(uuid,uuid,text,text,text)') IS NULL
     OR to_regprocedure('eogp.authorize_invitation_email_submission(uuid,uuid)') IS NULL THEN
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
     OR NOT has_function_privilege('eventor_worker', 'eogp.authorize_invitation_email_submission(uuid,uuid)', 'EXECUTE')
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


DO $staff_rsvp_command_security$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'eogp.record_staff_guest_rsvp(uuid,uuid,uuid,uuid,text,text,text,timestamptz,uuid,bytea,uuid,text)'::regprocedure
  ) INTO v_definition;
  IF strpos(v_definition,'app.actor_membership_id')=0
     OR strpos(v_definition,'IS DISTINCT FROM p_actor_membership_id')=0
     OR strpos(v_definition,'rsvp.record')=0
     OR strpos(v_definition,'rsvp.correct')=0
     OR strpos(v_definition,'rsvp.override_deadline')=0
     OR strpos(v_definition,'current_event_schedule_revision_id')=0
     OR strpos(v_definition,'correction_of_response_id')=0
     OR strpos(v_definition,'FOR UPDATE')=0 THEN
    RAISE EXCEPTION 'staff RSVP command is missing actor, permission, effective schedule, serialization or correction guards';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger trigger_row
    WHERE trigger_row.tgrelid='eogp.rsvp_responses'::regclass
      AND trigger_row.tgname='rsvp_responses_append_only_guard'
      AND NOT trigger_row.tgisinternal
  ) THEN
    RAISE EXCEPTION 'staff RSVP history must remain append-only';
  END IF;
END;
$staff_rsvp_command_security$;

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

DO $guest_invitation_send_authorization$
DECLARE
  v_definition text;
  v_invitation_lock integer;
  v_link_lock integer;
  v_delivery_lock integer;
  v_issue_definition text;
  v_claim_definition text;
  v_revoke_definition text;
  v_issue_idempotency_lock integer;
  v_issue_idempotency_lookup integer;
  v_issue_participation_lock integer;
  v_issue_invitation_lock integer;
  v_issue_link_revoke integer;
  v_revoke_invitation_lock integer;
  v_revoke_link_update integer;
BEGIN
  SELECT pg_get_functiondef(
    'eogp.authorize_invitation_email_submission(uuid,uuid)'::regprocedure
  ) INTO v_definition;
  v_invitation_lock := strpos(v_definition, 'FOR SHARE;');
  v_link_lock := v_invitation_lock
    + strpos(substring(v_definition FROM v_invitation_lock + 1), 'FOR SHARE;');
  v_delivery_lock := strpos(v_definition, 'FOR UPDATE;');
  SELECT pg_get_functiondef('eogp.issue_guest_invitation(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,bytea,text,bytea,timestamptz,text)'::regprocedure)
    INTO v_issue_definition;
  SELECT pg_get_functiondef('eogp.claim_invitation_email_delivery(uuid)'::regprocedure)
    INTO v_claim_definition;
  SELECT pg_get_functiondef('eogp.revoke_guest_invitation(uuid,uuid,uuid,text)'::regprocedure)
    INTO v_revoke_definition;
  v_issue_idempotency_lock := strpos(v_issue_definition,'pg_advisory_xact_lock');
  v_issue_idempotency_lookup := strpos(v_issue_definition,'idempotency_key_sha256=p_idempotency_key_sha256');
  v_issue_participation_lock := strpos(v_issue_definition,'FOR UPDATE OF participation;');
  v_issue_invitation_lock := strpos(v_issue_definition,'FOR UPDATE;');
  v_issue_link_revoke := strpos(v_issue_definition,'UPDATE eogp.invitation_links');
  v_revoke_invitation_lock := strpos(v_revoke_definition,'FOR UPDATE;');
  v_revoke_link_update := strpos(v_revoke_definition,'UPDATE eogp.invitation_links');
  IF strpos(v_revoke_definition, 'app.actor_membership_id')=0
     OR strpos(v_revoke_definition, 'IS DISTINCT FROM p_actor_membership_id')=0 THEN
    RAISE EXCEPTION 'invitation revocation must bind actor identity to the authenticated membership context';
  END IF;
  IF v_invitation_lock<=0 OR v_link_lock<=v_invitation_lock
     OR v_delivery_lock<=v_link_lock
     OR strpos(v_definition, 'link.revoked_at IS NOT NULL')=0
     OR strpos(v_definition, 'link.expires_at<=clock_timestamp()')=0
     OR strpos(v_definition, 'policy.state=''published''')=0
     OR strpos(v_definition, 'current_event_schedule_revision_id')=0
     OR strpos(v_definition, 'event.status NOT IN')=0
     OR strpos(v_issue_definition, 'current_event_schedule_revision_id')=0
     OR strpos(v_claim_definition, 'current_event_schedule_revision_id')=0
     OR v_issue_idempotency_lock<=0
     OR v_issue_idempotency_lookup<=v_issue_idempotency_lock
     OR strpos(v_issue_definition, 'idempotency_key_sha256=p_idempotency_key_sha256\n   FOR UPDATE')>0
     OR v_issue_participation_lock<=0
     OR v_issue_invitation_lock<=v_issue_participation_lock
     OR v_issue_link_revoke<=v_issue_invitation_lock
     OR v_revoke_invitation_lock<=0
     OR v_revoke_link_update<=v_revoke_invitation_lock THEN
    RAISE EXCEPTION 'send authorization must lock invitation, link, delivery and revalidate capability state';
  END IF;
END;
$guest_invitation_send_authorization$;

DO $guest_invitation_delivery_revocation$
DECLARE
  v_definition text;
  v_claim_definition text;
  v_authorize_definition text;
  v_complete_definition text;
  v_revoke_definition text;
  v_trigger_enabled boolean;
BEGIN
  SELECT pg_get_functiondef(
    'eogp.suppress_revoked_guest_invitation_delivery()'::regprocedure
  ) INTO v_definition;
  SELECT pg_get_functiondef(
    'eogp.claim_invitation_email_delivery(uuid)'::regprocedure
  ) INTO v_claim_definition;
  SELECT pg_get_functiondef(
    'eogp.authorize_invitation_email_submission(uuid,uuid)'::regprocedure
  ) INTO v_authorize_definition;
  SELECT pg_get_functiondef(
    'eogp.complete_invitation_email_delivery(uuid,uuid,text,text,text)'::regprocedure
  ) INTO v_complete_definition;
  SELECT pg_get_functiondef(
    'eogp.revoke_guest_invitation(uuid,uuid,uuid,text)'::regprocedure
  ) INTO v_revoke_definition;

  IF strpos(v_definition, 'OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL') = 0
     OR strpos(v_definition, 'delivery.invitation_revision_id=NEW.invitation_revision_id') = 0
     OR strpos(v_definition, 'delivery.status=''queued''') = 0
     OR strpos(v_definition, 'INVITATION_SUPERSEDED') = 0
     OR strpos(v_definition, 'INVITATION_REVOKED') = 0
     OR strpos(v_definition, 'delivery.status=''sending''') > 0 THEN
    RAISE EXCEPTION 'link revocation must suppress queued deliveries without rewriting claimed sends';
  END IF;

  -- A claimed message is checked again after invitation and link locks. If
  -- revocation/reissue committed first, authorization must reject it; if
  -- authorization committed first, SMTP is already considered in-flight.
  IF strpos(v_authorize_definition, 'v_delivery.status<>''sending''') = 0
     OR strpos(v_authorize_definition, 'v_delivery.lease_expires_at<=clock_timestamp()') = 0
     OR strpos(v_authorize_definition, 'link.revoked_at IS NOT NULL') = 0
     OR strpos(v_authorize_definition, 'FOR UPDATE;') = 0 THEN
    RAISE EXCEPTION 'SMTP authorization must reject stale leases and revoked links after capability locking';
  END IF;

  -- Expired in-flight attempts are terminally uncertain, never silently
  -- requeued. A stale worker cannot later overwrite the expired attempt.
  IF strpos(v_claim_definition, 'status=''sending''') = 0
     OR strpos(v_claim_definition, 'status=''uncertain''') = 0
     OR strpos(v_claim_definition, 'failure_code=''SMTP_UNKNOWN''') = 0
     OR strpos(v_complete_definition, 'v_delivery.lease_expires_at<=clock_timestamp()') = 0
     OR strpos(v_revoke_definition, 'AND status=''queued''') = 0 THEN
    RAISE EXCEPTION 'expired sends must become uncertain and stale completions must be rejected';
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



DO $guest_invitation_effective_schedule$
DECLARE
  v_resolver text;
  v_history text;
  v_rsvp text;
BEGIN
  SELECT pg_get_functiondef('eogp.resolve_guest_invitation(text)'::regprocedure) INTO v_resolver;
  SELECT pg_get_functiondef('eogp.get_guest_invitation_rsvp_history(text)'::regprocedure) INTO v_history;
  SELECT pg_get_functiondef('eogp.submit_guest_invitation_rsvp(text,text,text,text,bytea)'::regprocedure) INTO v_rsvp;
  IF strpos(v_resolver,'current_event_schedule_revision_id')=0
     OR strpos(v_history,'current_event_schedule_revision_id')=0
     OR strpos(v_rsvp,'current_event_schedule_revision_id')=0
     OR strpos(v_rsvp,'event.status NOT IN')=0
     OR strpos(v_rsvp,'participation.status = ''eligible''')=0 THEN
    RAISE EXCEPTION 'guest invitation capabilities must require effective schedule, live event and eligible participation';
  END IF;
  IF strpos(v_rsvp,'INTO v_existing_request_sha256') <= strpos(v_rsvp,'current_event_schedule_revision_id') THEN
    RAISE EXCEPTION 'guest RSVP idempotency replay must follow live capability validation';
  END IF;
END;
$guest_invitation_effective_schedule$;



DO $guest_invitation_staff_schedule_projection$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef('eogp.list_guest_invitation_events(uuid,uuid)'::regprocedure) INTO v_definition;
  IF strpos(v_definition,'current_event_schedule_revision_id')=0 THEN
    RAISE EXCEPTION 'staff guest invitation event projection must display the effective schedule revision';
  END IF;
END;
$guest_invitation_staff_schedule_projection$;


DO $guest_invitation_review_guards$
DECLARE
  v_auth text;
  v_limit text;
  v_trigger_count integer;
BEGIN
  SELECT pg_get_functiondef('eogp.guard_guest_invitation_manage_permission()'::regprocedure)
    INTO v_auth;
  IF strpos(v_auth,'FOR SHARE OF user_grant,role_permission')=0
     OR strpos(v_auth,'invitation.manage')=0
     OR NOT EXISTS (
       SELECT 1 FROM pg_trigger trigger_row
        WHERE trigger_row.tgrelid='eogp.invitations'::regclass
          AND trigger_row.tgname='invitations_manage_permission_guard'
          AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled<>'D'
     ) THEN
    RAISE EXCEPTION 'invitation mutation authorization is not serialized against grant revocation';
  END IF;

  SELECT pg_get_functiondef('eogp.enforce_guest_invitation_rsvp_write_limit()'::regprocedure)
    INTO v_limit;
  IF strpos(v_limit,'v_max_guest_responses constant integer := 20')=0
     OR strpos(v_limit,'guest invitation response limit reached')=0
     OR strpos(v_limit,'54000')=0
     OR NOT EXISTS (
       SELECT 1 FROM pg_trigger trigger_row
        WHERE trigger_row.tgrelid='eogp.rsvp_responses'::regclass
          AND trigger_row.tgname='guest_invitation_rsvp_write_limit'
          AND NOT trigger_row.tgisinternal AND trigger_row.tgenabled<>'D'
     ) THEN
    RAISE EXCEPTION 'guest capability RSVP write limit is missing or disabled';
  END IF;
END;
$guest_invitation_review_guards$;


DO $guest_capability_participation_eligibility$
DECLARE
  v_resolver text;
  v_history text;
BEGIN
  SELECT pg_get_functiondef('eogp.resolve_guest_invitation(text)'::regprocedure)
    INTO v_resolver;
  SELECT pg_get_functiondef('eogp.get_guest_invitation_rsvp_history(text)'::regprocedure)
    INTO v_history;

  IF strpos(v_resolver, 'JOIN eogp.event_participations participation') = 0
     OR strpos(v_resolver, 'participation.status = ''eligible''') = 0
     OR strpos(v_history, 'JOIN eogp.event_participations participation') = 0
     OR strpos(v_history, 'participation.status = ''eligible''') = 0 THEN
    RAISE EXCEPTION 'guest invitation resolution and RSVP history must reject ineligible participants';
  END IF;
END;
$guest_capability_participation_eligibility$;


DO $guest_invitation_projection_authorization_lock$
DECLARE
  v_definition text;
  v_event_definition text;
  v_attempt_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'eogp.list_guest_invitation_participations(uuid,uuid,uuid)'::regprocedure
  ) INTO v_definition;

  IF strpos(v_definition, 'organization_memberships membership') = 0
     OR strpos(v_definition, 'membership.status=''active''') = 0
     OR strpos(v_definition, 'FOR SHARE;') = 0
     OR strpos(v_definition, 'FOR SHARE OF user_grant,role_permission') = 0
     OR strpos(v_definition, 'invitation.manage') = 0 THEN
    RAISE EXCEPTION 'guest invitation staff projection must serialize authorization with membership and permission revocation';
  END IF;

  SELECT pg_get_functiondef(
    'eogp.list_guest_invitation_events(uuid,uuid)'::regprocedure
  ) INTO v_event_definition;

  IF strpos(v_event_definition, 'organization_memberships membership') = 0
     OR strpos(v_event_definition, 'membership.status=''active''') = 0
     OR strpos(v_event_definition, 'FOR SHARE;') = 0
     OR strpos(v_event_definition, 'FOR SHARE OF user_grant,role_permission') = 0
     OR strpos(v_event_definition, 'invitation.manage') = 0 THEN
    RAISE EXCEPTION 'guest invitation event projection must serialize authorization with membership and permission revocation';
  END IF;

  SELECT pg_get_functiondef(
    'eogp.list_guest_invitation_delivery_attempts(uuid,uuid,uuid)'::regprocedure
  ) INTO v_attempt_definition;

  IF strpos(v_attempt_definition, 'organization_memberships membership') = 0
     OR strpos(v_attempt_definition, 'membership.status=''active''') = 0
     OR strpos(v_attempt_definition, 'FOR SHARE;') = 0
     OR strpos(v_attempt_definition, 'FOR SHARE OF user_grant,role_permission') = 0
     OR strpos(v_attempt_definition, 'invitation.manage permission is required') > 0
     OR (length(v_attempt_definition)-length(replace(v_attempt_definition,'guest invitation not found','')))
          / length('guest invitation not found') < 2 THEN
    RAISE EXCEPTION 'guest invitation delivery-history projection must serialize authorization and hide invitation existence from unauthorized members';
  END IF;
END;
$guest_invitation_projection_authorization_lock$;


DO $guest_invitation_command_authorization_lock$
DECLARE
  v_issue_definition text;
  v_revoke_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'eogp.issue_guest_invitation(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,bytea,text,bytea,timestamptz,text)'::regprocedure
  ) INTO v_issue_definition;
  IF strpos(v_issue_definition, 'FOR SHARE OF user_grant,role_permission') = 0
     OR strpos(v_issue_definition, 'pg_advisory_xact_lock') <= strpos(v_issue_definition, 'FOR SHARE OF user_grant,role_permission')
     OR strpos(v_issue_definition, 'idempotency_key_sha256=p_idempotency_key_sha256') <= strpos(v_issue_definition, 'pg_advisory_xact_lock') THEN
    RAISE EXCEPTION 'guest invitation issuance must lock authorization before idempotency replay lookup';
  END IF;

  SELECT pg_get_functiondef(
    'eogp.revoke_guest_invitation(uuid,uuid,uuid,text)'::regprocedure
  ) INTO v_revoke_definition;
  IF strpos(v_revoke_definition, 'FOR SHARE OF user_grant,role_permission') = 0
     OR strpos(v_revoke_definition, 'invitation.manage') = 0 THEN
    RAISE EXCEPTION 'guest invitation revocation must serialize permission revocation, including already-revoked replay results';
  END IF;
END;
$guest_invitation_command_authorization_lock$;


DO $staff_rsvp_authorization_precedes_lookup$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'eogp.record_staff_guest_rsvp(uuid,uuid,uuid,uuid,text,text,text,timestamptz,uuid,bytea,uuid,text)'::regprocedure
  ) INTO v_definition;
  IF strpos(v_definition, 'role_permission.permission_code=''rsvp.record''') = 0
     OR strpos(v_definition, 'FOR SHARE OF user_grant, role_permission') = 0
     OR strpos(v_definition, 'role_permission.permission_code=''rsvp.record''')
          > strpos(v_definition, 'FROM eogp.event_participations participation') THEN
    RAISE EXCEPTION 'staff RSVP must lock rsvp.record authorization before looking up participation state';
  END IF;
END;
$staff_rsvp_authorization_precedes_lookup$;

ROLLBACK;
