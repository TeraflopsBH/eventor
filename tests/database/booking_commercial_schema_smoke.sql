
-- This smoke test runs as eventor_runtime. It verifies that the commercial
-- workflow is installed, tenant-protected, and callable only through commands.
DO $test$
DECLARE
  v_relation record;
  v_name text;
  v_definition text;
  v_required_tables text[] := ARRAY[
    'booking_approval_policies',
    'booking_approval_policy_revisions',
    'booking_offer_decision_history',
    'booking_offer_approval_decisions',
    'booking_offer_capability_idempotency',
    'booking_offer_email_deliveries',
    'booking_price_lists','booking_price_list_revisions','booking_price_items',
    'cancellation_policies','cancellation_policy_revisions',
    'booking_tax_profiles','booking_tax_profile_revisions'
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
    'eogp.publish_booking_approval_policy_revision(uuid,uuid,uuid,uuid)',
    'eogp.queue_booking_offer_email_delivery(uuid,uuid,uuid,text,text,bytea)',
    'eogp.list_booking_offer_email_deliveries(uuid,uuid,uuid,text,integer,integer)',
    'eogp.reconcile_booking_offer_email_delivery(uuid,uuid,uuid,text,text,text)',
    'eogp.retry_booking_offer_email_delivery(uuid,uuid,uuid,text)',
    'eogp.get_booking_price_lists(uuid,uuid)',
    'eogp.create_booking_price_list(uuid,uuid,text,text,text,uuid,uuid,text,text)',
    'eogp.create_booking_price_list_revision(uuid,uuid,uuid,text,text,timestamptz,timestamptz)',
    'eogp.replace_booking_price_list_draft_items(uuid,uuid,uuid,uuid,text,text,timestamptz,timestamptz,jsonb)',
    'eogp.publish_booking_price_list_revision(uuid,uuid,uuid,uuid)',
    'eogp.get_booking_cancellation_policies(uuid,uuid)',
    'eogp.create_booking_cancellation_policy(uuid,uuid,text,text)',
    'eogp.create_booking_cancellation_policy_revision(uuid,uuid,uuid,text,text,jsonb,jsonb,jsonb)',
    'eogp.update_booking_cancellation_policy_draft_revision(uuid,uuid,uuid,uuid,text,text,jsonb,jsonb,jsonb)',
    'eogp.publish_booking_cancellation_policy_revision(uuid,uuid,uuid,uuid)',
    'eogp.get_booking_tax_profiles(uuid,uuid)',
    'eogp.create_booking_tax_profile(uuid,uuid,text,text,text,text,text,text)',
    'eogp.create_booking_tax_profile_revision(uuid,uuid,uuid,text,text,text,text,text,integer,timestamptz,timestamptz)',
    'eogp.update_booking_tax_profile_draft_revision(uuid,uuid,uuid,uuid,text,text,text,text,text,integer,timestamptz,timestamptz,jsonb)',
    'eogp.publish_booking_tax_profile_revision(uuid,uuid,uuid,uuid)',
    'eogp.set_booking_price_list_tax_profile_revision(uuid,uuid,uuid,uuid,uuid)'
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
     OR has_table_privilege(current_user,'eogp.booking_offer_expiry_tenant_queue','SELECT')
     OR has_table_privilege(current_user,'eogp.booking_offer_email_deliveries','SELECT')
     OR has_table_privilege(current_user,'eogp.booking_offer_email_delivery_tenant_queue','SELECT')
     OR has_table_privilege(current_user,'eogp.booking_price_lists','SELECT')
     OR has_table_privilege(current_user,'eogp.booking_price_list_revisions','SELECT')
     OR has_table_privilege(current_user,'eogp.booking_price_items','SELECT')
     OR has_table_privilege(current_user,'eogp.cancellation_policies','SELECT')
     OR has_table_privilege(current_user,'eogp.cancellation_policy_revisions','SELECT')
     OR has_table_privilege(current_user,'eogp.booking_tax_profiles','SELECT')
     OR has_table_privilege(current_user,'eogp.booking_tax_profile_revisions','SELECT') THEN
    RAISE EXCEPTION 'runtime role has direct table read access to protected commercial data';
  END IF;

  IF to_regprocedure('eogp.allocate_booking_offer_adjustment_tax(uuid,uuid,jsonb,jsonb,text)') IS NULL THEN
    RAISE EXCEPTION 'offer adjustment tax allocation helper is missing';
  END IF;
  IF has_function_privilege(current_user,
       'eogp.allocate_booking_offer_adjustment_tax(uuid,uuid,jsonb,jsonb,text)','EXECUTE') THEN
    RAISE EXCEPTION 'runtime role must not execute the internal adjustment tax allocation helper directly';
  END IF;
  SELECT pg_get_functiondef(
    'eogp.save_booking_offer_revision(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,jsonb,jsonb,numeric,text,boolean)'::regprocedure
  ) INTO v_definition;
  IF position('allocate_booking_offer_adjustment_tax' in v_definition)=0
     OR position('v_tax_lines' in v_definition)=0 THEN
    RAISE EXCEPTION 'offer-save command does not use the adjustment tax allocation helper';
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

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    JOIN pg_catalog.pg_class r ON r.oid=t.tgrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=r.relnamespace
    WHERE n.nspname='eogp' AND r.relname='cancellation_policy_revisions'
      AND t.tgname='cancellation_policy_revisions_published_immutable_guard' AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'published cancellation policy revision immutability trigger is missing';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    JOIN pg_catalog.pg_class r ON r.oid=t.tgrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=r.relnamespace
    WHERE n.nspname='eogp' AND r.relname='booking_tax_profile_revisions'
      AND t.tgname='booking_tax_profile_revisions_published_immutable_guard' AND NOT t.tgisinternal
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    JOIN pg_catalog.pg_class r ON r.oid=t.tgrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=r.relnamespace
    WHERE n.nspname='eogp' AND r.relname='booking_price_list_revisions'
      AND t.tgname='booking_price_list_tax_profile_publish_guard' AND NOT t.tgisinternal
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    JOIN pg_catalog.pg_class r ON r.oid=t.tgrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=r.relnamespace
    WHERE n.nspname='eogp' AND r.relname='booking_offer_revisions'
      AND t.tgname='booking_offer_revision_tax_configuration_snapshot' AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'tax-profile immutability, price-list validation or offer snapshot trigger is missing';
  END IF;

  IF NOT has_table_privilege('eventor_worker','eogp.booking_offer_expiry_tenant_queue','SELECT')
     OR NOT has_function_privilege('eventor_worker','eogp.discover_due_booking_offer_expiry_tenants()','EXECUTE')
     OR NOT has_function_privilege('eventor_worker','eogp.expire_due_booking_offers(uuid,integer)','EXECUTE') THEN
    RAISE EXCEPTION 'worker role is missing booking offer expiry queue permissions';
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

  IF has_table_privilege('eventor_worker','eogp.booking_offer_email_deliveries','SELECT') THEN
    RAISE EXCEPTION 'worker role has direct access to booking offer email payloads';
  END IF;

  IF EXISTS (
    SELECT required.column_name
      FROM (VALUES ('manual_retry_count'),('last_operator_resolution'),
                   ('last_operator_reason'),('last_operator_membership_id'),('last_operator_at'))
           AS required(column_name)
     WHERE NOT EXISTS (
       SELECT 1 FROM pg_catalog.pg_attribute attribute
       JOIN pg_catalog.pg_class relation ON relation.oid=attribute.attrelid
       JOIN pg_catalog.pg_namespace namespace ON namespace.oid=relation.relnamespace
       WHERE namespace.nspname='eogp'
         AND relation.relname='booking_offer_email_deliveries'
         AND attribute.attname=required.column_name
         AND attribute.attnum>0 AND NOT attribute.attisdropped
     )
  ) THEN
    RAISE EXCEPTION 'booking offer email reconciliation metadata columns are missing';
  END IF;

  IF has_function_privilege('eventor_worker','eogp.list_booking_offer_email_deliveries(uuid,uuid,uuid,text,integer,integer)','EXECUTE')
     OR has_function_privilege('eventor_worker','eogp.reconcile_booking_offer_email_delivery(uuid,uuid,uuid,text,text,text)','EXECUTE')
     OR has_function_privilege('eventor_worker','eogp.retry_booking_offer_email_delivery(uuid,uuid,uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'worker role can invoke staff-only offer email operations';
  END IF;

  IF has_table_privilege('eventor_runtime','eogp.booking_offer_email_deliveries','SELECT')
     OR NOT has_function_privilege('eventor_runtime','eogp.list_booking_offer_email_deliveries(uuid,uuid,uuid,text,integer,integer)','EXECUTE')
     OR NOT has_function_privilege('eventor_runtime','eogp.reconcile_booking_offer_email_delivery(uuid,uuid,uuid,text,text,text)','EXECUTE')
     OR NOT has_function_privilege('eventor_runtime','eogp.retry_booking_offer_email_delivery(uuid,uuid,uuid,text)','EXECUTE') THEN
    RAISE EXCEPTION 'runtime role is missing permission-gated offer email operations';
  END IF;

  IF NOT has_table_privilege('eventor_worker','eogp.booking_offer_email_delivery_tenant_queue','SELECT')
     OR NOT has_function_privilege('eventor_worker','eogp.discover_pending_booking_offer_email_tenants()','EXECUTE')
     OR NOT has_function_privilege('eventor_worker','eogp.claim_booking_offer_email_delivery(uuid)','EXECUTE')
     OR NOT has_function_privilege('eventor_worker','eogp.complete_booking_offer_email_delivery(uuid,uuid,text,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'worker role is missing booking offer email queue permissions';
  END IF;

  IF has_function_privilege(current_user,'eogp.discover_pending_booking_offer_email_tenants()','EXECUTE')
     OR has_function_privilege(current_user,'eogp.claim_booking_offer_email_delivery(uuid)','EXECUTE')
     OR has_function_privilege(current_user,'eogp.complete_booking_offer_email_delivery(uuid,uuid,text,text,text)','EXECUTE') THEN
    RAISE EXCEPTION 'runtime role can invoke worker-only booking offer email functions';
  END IF;

  IF to_regprocedure('eogp.calculate_booking_offer_tax(uuid,uuid,text,text,timestamptz,jsonb,numeric)') IS NULL
     OR has_function_privilege(current_user,
       'eogp.calculate_booking_offer_tax(uuid,uuid,text,text,timestamptz,jsonb,numeric)','EXECUTE') THEN
    RAISE EXCEPTION 'tax calculation helper must exist and remain internal to the authorized offer command';
  END IF;
  IF position('calculate_booking_offer_tax' IN pg_get_functiondef(
       'eogp.save_booking_offer_revision(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,jsonb,jsonb,numeric,text,boolean)'::regprocedure
     ))=0 THEN
    RAISE EXCEPTION 'offer preparation does not invoke the tax calculation helper';
  END IF;

  IF (SELECT numeric_scale FROM information_schema.columns
       WHERE table_schema='eogp' AND table_name='booking_offer_revisions' AND column_name='tax_amount')<4
     OR (SELECT numeric_scale FROM information_schema.columns
       WHERE table_schema='eogp' AND table_name='booking_offer_revisions' AND column_name='total_amount')<4 THEN
    RAISE EXCEPTION 'offer amounts do not preserve configured tax precision';
  END IF;

  IF to_regprocedure('eogp.digest(bytea,text)') IS NULL THEN
    RAISE EXCEPTION 'pgcrypto digest function is not installed in the eogp schema';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    JOIN pg_catalog.pg_class r ON r.oid=t.tgrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=r.relnamespace
    WHERE n.nspname='eogp' AND r.relname='booking_price_list_revisions'
      AND t.tgname='booking_price_list_revisions_published_immutable_guard' AND NOT t.tgisinternal
  ) OR NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_trigger t
    JOIN pg_catalog.pg_class r ON r.oid=t.tgrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=r.relnamespace
    WHERE n.nspname='eogp' AND r.relname='booking_price_items'
      AND t.tgname='booking_price_items_published_parent_guard' AND NOT t.tgisinternal
  ) THEN
    RAISE EXCEPTION 'price-list revision and item immutability guards are missing';
  END IF;

END;
$test$;
