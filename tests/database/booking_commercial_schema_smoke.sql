
-- This smoke test runs as eventor_runtime. It verifies that the commercial
-- workflow is installed, tenant-protected, and callable only through commands.
DO $test$
DECLARE
  v_relation record;
  v_name text;
  v_required_tables text[] := ARRAY[
    'booking_approval_policies',
    'booking_approval_policy_revisions',
    'booking_offer_decision_history',
    'booking_offer_approval_decisions',
    'booking_offer_capability_idempotency',
    'booking_approval_policies',
    'booking_approval_policy_revisions'
  ];
  v_required_functions text[] := ARRAY[
    'eogp.save_booking_offer_revision(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,jsonb,jsonb,numeric,text,boolean)',
    'eogp.issue_booking_offer(uuid,uuid,uuid,text)',
    'eogp.get_booking_offer(uuid,uuid,uuid)',
    'eogp.resolve_booking_offer_capability(uuid,text)',
    'eogp.get_public_booking_offer_with_capability(uuid,text)',
    'eogp.decide_booking_offer_with_capability(uuid,text,text,text,text,bytea,bytea,text,bytea)',
    'eogp.decide_booking_offer_approval(uuid,uuid,uuid,uuid,text,text,text)',
    'eogp.get_booking_offer_approval_status(uuid,uuid,uuid)',
    'eogp.confirm_booking_from_offer(uuid,uuid,uuid,text)',
    'eogp.get_booking_approval_policies(uuid,uuid)',
    'eogp.create_booking_approval_policy(uuid,uuid,text,text)',
    'eogp.create_booking_approval_policy_revision(uuid,uuid,uuid,jsonb)',
    'eogp.update_booking_approval_policy_draft_revision(uuid,uuid,uuid,uuid,jsonb)',
    'eogp.publish_booking_approval_policy_revision(uuid,uuid,uuid,uuid)'
  ];
BEGIN
  FOREACH v_name IN ARRAY v_required_tables LOOP
    SELECT c.relrowsecurity,c.relforcerowsecurity
      INTO v_relation
      FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='eogp' AND c.relname=v_name AND c.relkind='r';
    IF NOT FOUND OR NOT v_relation.relrowsecurity OR NOT v_relation.relforcerowsecurity THEN
      RAISE EXCEPTION 'required commercial table % is missing RLS or FORCE RLS',v_name;
    END IF;
  END LOOP;

  FOREACH v_name IN ARRAY v_required_functions LOOP
    IF to_regprocedure(v_name) IS NULL THEN
      RAISE EXCEPTION 'required commercial command % is missing',v_name;
    END IF;
    IF NOT has_function_privilege(current_user,to_regprocedure(v_name),'EXECUTE') THEN
      RAISE EXCEPTION 'runtime role cannot execute required commercial command %',v_name;
    END IF;
  END LOOP;

  IF has_table_privilege(current_user,'eogp.booking_offers','SELECT')
     OR has_table_privilege(current_user,'eogp.booking_offer_revisions','SELECT')
     OR has_table_privilege(current_user,'eogp.external_action_capabilities','SELECT')
     OR has_table_privilege(current_user,'eogp.booking_offer_capability_lookup','SELECT')
     OR has_table_privilege(current_user,'eogp.booking_offer_decision_history','SELECT')
     OR has_table_privilege(current_user,'eogp.booking_offer_approval_decisions','SELECT')
     OR has_table_privilege(current_user,'eogp.booking_approval_policies','SELECT')
     OR has_table_privilege(current_user,'eogp.booking_approval_policy_revisions','SELECT')
     OR has_table_privilege(current_user,'eogp.booking_offer_expiry_tenant_queue','SELECT') THEN
    RAISE EXCEPTION 'runtime role has direct table read access to protected commercial data';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    JOIN pg_catalog.pg_class r ON r.oid=t.tgrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=r.relnamespace
    WHERE n.nspname='eogp'
      AND r.relname='external_action_capabilities'
      AND t.tgname='booking_offer_capability_lookup_insert'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'offer capability hash lookup trigger is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    JOIN pg_catalog.pg_class r ON r.oid=t.tgrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=r.relnamespace
    WHERE n.nspname='eogp'
      AND r.relname='booking_offer_revisions'
      AND t.tgname='booking_offer_approval_requirements_pin'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'pinned approval-requirement evaluation trigger is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    JOIN pg_catalog.pg_class r ON r.oid=t.tgrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=r.relnamespace
    WHERE n.nspname='eogp'
      AND r.relname='booking_offer_revisions'
      AND t.tgname='booking_offer_revision_terminal_capability_revoke'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'terminal offer transition capability-revoke trigger is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    JOIN pg_catalog.pg_class r ON r.oid=t.tgrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=r.relnamespace
    WHERE n.nspname='eogp'
      AND r.relname='booking_approval_policy_revisions'
      AND t.tgname='booking_approval_policy_revisions_immutable_guard'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'published approval policy revision immutability trigger is missing';
  END IF;

  IF has_function_privilege(current_user,'eogp.discover_due_booking_offer_expiry_tenants()','EXECUTE')
     OR has_function_privilege(current_user,'eogp.expire_due_booking_offers(uuid,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'runtime role can invoke worker-only booking offer expiry functions';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    JOIN pg_catalog.pg_class r ON r.oid=t.tgrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=r.relnamespace
    WHERE n.nspname='eogp'
      AND r.relname='booking_offers'
      AND t.tgname='booking_offer_expiry_queue_offer'
      AND NOT t.tgisinternal
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    JOIN pg_catalog.pg_class r ON r.oid=t.tgrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=r.relnamespace
    WHERE n.nspname='eogp'
      AND r.relname='booking_offer_revisions'
      AND t.tgname='booking_offer_expiry_queue_revision'
      AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'booking offer expiry queue triggers are missing';
  END IF;

  IF to_regprocedure('eogp.digest(bytea,text)') IS NULL THEN
    RAISE EXCEPTION 'pgcrypto digest function is not installed in the eogp schema';
  END IF;
END;
$test$;
