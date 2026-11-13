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

  IF NOT has_column_privilege(current_user,'eogp.outbox_events','id','SELECT')
     OR NOT has_column_privilege(current_user,'eogp.outbox_events','organization_id','SELECT')
     OR NOT has_column_privilege(current_user,'eogp.outbox_events','topic','SELECT')
     OR NOT has_column_privilege(current_user,'eogp.outbox_events','available_at','SELECT')
     OR NOT has_column_privilege(current_user,'eogp.outbox_events','published_at','SELECT')
     OR NOT has_column_privilege(current_user,'eogp.outbox_events','dead_lettered_at','SELECT') THEN
    RAISE EXCEPTION 'worker lacks the minimal outbox discovery metadata privileges';
  END IF;

  IF has_table_privilege(current_user,'eogp.events','SELECT')
     OR has_table_privilege(current_user,'eogp.person_contact_points','SELECT')
     OR has_table_privilege(current_user,'eogp.event_notification_campaigns','SELECT')
     OR has_table_privilege(current_user,'eogp.event_notification_campaigns','UPDATE')
     OR has_table_privilege(current_user,'eogp.event_notification_recipients','SELECT')
     OR has_table_privilege(current_user,'eogp.event_notification_recipients','INSERT')
     OR has_table_privilege(current_user,'eogp.event_notification_exclusions','SELECT')
     OR has_table_privilege(current_user,'eogp.event_notification_delivery_attempts','SELECT')
     OR has_table_privilege(current_user,'eogp.event_notification_delivery_attempts','INSERT') THEN
    RAISE EXCEPTION 'worker must not directly read source contacts or campaign/recipient snapshots';
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

-- With no tenant context, the worker may discover only pending notification
-- tenant IDs and only through the metadata columns granted above.
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

DO $process$
DECLARE
  v_result jsonb;
BEGIN
  v_result := eogp.process_event_notification_outbox(10);
  IF (v_result ->> 'processed')::integer <> 1
     OR (v_result ->> 'campaignPreviewsPrepared')::integer <> 1
     OR (v_result ->> 'deferred')::integer <> 0
     OR (v_result ->> 'deadLettered')::integer <> 0 THEN
    RAISE EXCEPTION 'worker did not successfully prepare exactly one campaign: %',v_result;
  END IF;

  IF (SELECT published_at IS NULL OR dead_lettered_at IS NOT NULL
        FROM eogp.outbox_events
       WHERE organization_id = '22222222-2222-4222-8222-222222222222'
         AND id = '95000000-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'successfully prepared outbox event was not acknowledged';
  END IF;
END;
$process$;
COMMIT;

-- A second pass must not recreate a campaign or duplicate recipients.
BEGIN;
SET LOCAL app.organization_id = '22222222-2222-4222-8222-222222222222';
DO $second_pass$
DECLARE
  v_result jsonb;
BEGIN
  v_result := eogp.process_event_notification_outbox(10);
  IF (v_result ->> 'processed')::integer <> 0
     OR (v_result ->> 'campaignPreviewsPrepared')::integer <> 0
     OR (v_result ->> 'deferred')::integer <> 0
     OR (v_result ->> 'deadLettered')::integer <> 0 THEN
    RAISE EXCEPTION 'worker retried an already acknowledged outbox item: %',v_result;
  END IF;
END;
$second_pass$;
COMMIT;

\echo 'Tenant-safe notification worker boundary smoke tests passed.'
