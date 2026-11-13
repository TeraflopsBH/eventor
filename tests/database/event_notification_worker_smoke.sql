\set ON_ERROR_STOP on
BEGIN;

DO $outbox_boundary$
DECLARE
  v_security_definer boolean;
  v_search_path text[];
BEGIN
  IF session_user <> 'eventor_worker' THEN
    RAISE EXCEPTION 'outbox preparation smoke test must connect as eventor_worker';
  END IF;

  IF has_table_privilege(current_user,'eogp.outbox_events','SELECT')
     OR has_table_privilege(current_user,'eogp.outbox_events','UPDATE')
     OR has_column_privilege(current_user,'eogp.outbox_events','payload','SELECT')
     OR has_column_privilege(current_user,'eogp.outbox_events','aggregate_id','SELECT')
     OR has_column_privilege(current_user,'eogp.outbox_events','idempotency_key','SELECT') THEN
    RAISE EXCEPTION 'worker must not directly read full outbox rows or update them';
  END IF;

  IF NOT has_column_privilege(current_user,'eogp.outbox_events','organization_id','SELECT')
     OR NOT has_column_privilege(current_user,'eogp.outbox_events','topic','SELECT')
     OR NOT has_column_privilege(current_user,'eogp.outbox_events','available_at','SELECT')
     OR NOT has_column_privilege(current_user,'eogp.outbox_events','published_at','SELECT')
     OR NOT has_column_privilege(current_user,'eogp.outbox_events','dead_lettered_at','SELECT') THEN
    RAISE EXCEPTION 'worker lacks the minimal outbox discovery metadata privileges';
  END IF;

  SELECT procedure.prosecdef, procedure.proconfig
    INTO v_security_definer, v_search_path
    FROM pg_proc AS procedure
    JOIN pg_namespace AS namespace ON namespace.oid = procedure.pronamespace
   WHERE namespace.nspname = 'eogp'
     AND procedure.proname = 'process_event_notification_outbox'
     AND procedure.pronargs = 1;

  IF v_security_definer IS DISTINCT FROM true
     OR NOT EXISTS (
       SELECT 1
         FROM unnest(coalesce(v_search_path, ARRAY[]::text[])) AS setting
        WHERE replace(setting,' ','') = 'search_path=pg_catalog,eogp'
     ) THEN
    RAISE EXCEPTION 'outbox processor must be SECURITY DEFINER with a fixed search_path';
  END IF;

  IF has_function_privilege('eventor_runtime',
       'eogp.process_event_notification_outbox(integer)','EXECUTE')
     OR NOT has_function_privilege('eventor_worker',
       'eogp.process_event_notification_outbox(integer)','EXECUTE') THEN
    RAISE EXCEPTION 'outbox processor execution must be restricted to eventor_worker';
  END IF;
END;
$outbox_boundary$;

-- With no tenant context, the worker may discover only the pending notification
-- topic and only through the metadata columns granted above.
DO $outbox_discovery$
DECLARE
  pending_tenants integer;
  unrelated_topics integer;
BEGIN
  SELECT count(DISTINCT organization_id)
    INTO pending_tenants
    FROM eogp.outbox_events
   WHERE topic = 'event.change.notification_requested'
     AND published_at IS NULL
     AND dead_lettered_at IS NULL
     AND available_at <= clock_timestamp();

  SELECT count(topic)
    INTO unrelated_topics
    FROM eogp.outbox_events
   WHERE topic <> 'event.change.notification_requested';

  IF pending_tenants < 1 OR unrelated_topics <> 0 THEN
    RAISE EXCEPTION 'worker outbox discovery leaked unrelated topics or found no pending tenant: pending %, unrelated %',
      pending_tenants, unrelated_topics;
  END IF;
END;
$outbox_discovery$;

SET LOCAL app.organization_id = '22222222-2222-4222-8222-222222222222';

SELECT eogp.process_event_notification_outbox(10);

DO $test$
DECLARE
  v_campaign_id uuid;
  v_count integer;
  v_recipient_ciphertext bytea;
  v_expected_ciphertext bytea;
BEGIN
  SELECT id, recipient_count
    INTO v_campaign_id, v_count
    FROM eogp.event_notification_campaigns
   WHERE organization_id = '22222222-2222-4222-8222-222222222222'
     AND event_decision_id = '94900000-0000-4000-8000-000000000001'
     AND purpose = 'event_cancellation';

  IF v_campaign_id IS NULL OR v_count <> 3 THEN
    RAISE EXCEPTION 'worker did not create the two historically invited eligible recipients in a preview campaign; campaign %, count %',
      v_campaign_id, v_count;
  END IF;

  IF (SELECT status FROM eogp.event_notification_campaigns WHERE id = v_campaign_id) <> 'previewed' THEN
    RAISE EXCEPTION 'worker must leave the campaign in previewed state for organizer review';
  END IF;

  SELECT destination_ciphertext INTO v_recipient_ciphertext
    FROM eogp.event_notification_recipients
   WHERE organization_id = '22222222-2222-4222-8222-222222222222'
     AND campaign_id = v_campaign_id
     AND participation_id = '94300000-0000-4000-8000-000000000001';
  SELECT encrypted_value INTO v_expected_ciphertext
    FROM eogp.person_contact_points
   WHERE id = '94400000-0000-4000-8000-000000000001';

  IF v_recipient_ciphertext IS DISTINCT FROM v_expected_ciphertext THEN
    RAISE EXCEPTION 'worker did not preserve the encrypted destination snapshot';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM eogp.event_notification_recipients
     WHERE organization_id = '22222222-2222-4222-8222-222222222222'
       AND campaign_id = v_campaign_id
       AND participation_id = '94300000-0000-4000-8000-000000000003'
       AND invitation_id = '94500000-0000-4000-8000-000000000003'
  ) THEN
    RAISE EXCEPTION 'previously invited participant was omitted because the latest invitation revision was still a draft';
  END IF;

  SELECT count(*) INTO v_count
    FROM eogp.event_notification_exclusions
   WHERE organization_id = '22222222-2222-4222-8222-222222222222'
     AND campaign_id = v_campaign_id
     AND participation_id = '94300000-0000-4000-8000-000000000002'
     AND exclusion_reason = 'no_verified_permitted_contact';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'worker did not record excluded participant without permitted contact';
  END IF;

  SELECT count(*) INTO v_count
    FROM eogp.event_notification_delivery_attempts
   WHERE organization_id = '22222222-2222-4222-8222-222222222222'
     AND campaign_id = v_campaign_id;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'campaign preparation must not create delivery attempts or pretend to send';
  END IF;

  IF (SELECT published_at IS NULL OR dead_lettered_at IS NOT NULL
        FROM eogp.outbox_events
       WHERE organization_id = '22222222-2222-4222-8222-222222222222'
         AND id = '95000000-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'successfully prepared outbox event was not acknowledged';
  END IF;
END;
$test$;
COMMIT;

-- A second pass must not recreate a campaign or duplicate recipients.
BEGIN;
SET LOCAL app.organization_id = '22222222-2222-4222-8222-222222222222';
DO $second_pass$
DECLARE
  v_result jsonb;
  v_count integer;
BEGIN
  v_result := eogp.process_event_notification_outbox(10);
  IF (v_result ->> 'processed')::integer <> 0 THEN
    RAISE EXCEPTION 'worker retried an already acknowledged outbox item: %',v_result;
  END IF;
  SELECT count(*) INTO v_count
    FROM eogp.event_notification_campaigns
   WHERE organization_id = '22222222-2222-4222-8222-222222222222'
     AND event_decision_id = '94900000-0000-4000-8000-000000000001';
  IF v_count <> 1 THEN RAISE EXCEPTION 'duplicate campaign created on worker replay'; END IF;
END;
$second_pass$;
COMMIT;
