\set ON_ERROR_STOP on
BEGIN;
SET LOCAL app.organization_id='22222222-2222-4222-8222-222222222222';

DO $delivery_first$
DECLARE
  v_campaign_id uuid;
  v_job record;
  v_result jsonb;
  v_retry_scheduled boolean := false;
  v_queued integer;
BEGIN
  IF session_user<>'eventor_worker' THEN
    RAISE EXCEPTION 'delivery worker smoke test must run as eventor_worker';
  END IF;
  IF has_table_privilege(current_user,'eogp.organization_delivery_config_revisions','SELECT')
     OR has_table_privilege(current_user,'eogp.organization_delivery_config_heads','SELECT') THEN
    RAISE EXCEPTION 'worker must not directly read SMTP configuration or credentials';
  END IF;

  SELECT id INTO v_campaign_id
    FROM eogp.event_notification_campaigns
   WHERE organization_id='22222222-2222-4222-8222-222222222222'
     AND event_decision_id='94900000-0000-4000-8000-000000000001';
  IF NOT EXISTS (
    SELECT 1 FROM eogp.discover_pending_email_delivery_tenants()
     WHERE organization_id='22222222-2222-4222-8222-222222222222'
  ) THEN
    RAISE EXCEPTION 'queued delivery tenant was not discoverable';
  END IF;

  SELECT * INTO v_job
    FROM eogp.claim_next_email_delivery('22222222-2222-4222-8222-222222222222');
  IF v_job.attempt_id IS NULL OR v_job.destination_ciphertext IS NULL
     OR v_job.smtp_settings->>'host'<>'smtp.example.test'
     OR v_job.sender_email<>'events@example.test'
     OR v_job.subject_template IS NULL THEN
    RAISE EXCEPTION 'worker claim did not return the required encrypted SMTP job';
  END IF;
  v_result:=eogp.complete_email_delivery_attempt(
    '22222222-2222-4222-8222-222222222222',
    v_job.attempt_id,'sent',NULL,'ci-smtp-accepted-1'
  );
  IF v_result->>'outcome'<>'sent' THEN
    RAISE EXCEPTION 'successful SMTP acceptance was not recorded';
  END IF;

  SELECT * INTO v_job
    FROM eogp.claim_next_email_delivery('22222222-2222-4222-8222-222222222222');
  IF v_job.attempt_id IS NULL THEN
    RAISE EXCEPTION 'second queued recipient was not claimable';
  END IF;
  v_result:=eogp.complete_email_delivery_attempt(
    '22222222-2222-4222-8222-222222222222',
    v_job.attempt_id,'failed','SMTP_4XX',NULL
  );
  v_retry_scheduled:=(v_result->>'retryScheduled')::boolean;
  IF NOT v_retry_scheduled THEN
    RAISE EXCEPTION 'temporary SMTP 4xx failure did not schedule a retry';
  END IF;

  SELECT count(*) INTO v_queued
    FROM eogp.event_notification_delivery_attempts attempt
   WHERE attempt.organization_id='22222222-2222-4222-8222-222222222222'
     AND attempt.campaign_id=v_campaign_id
     AND attempt.status='queued' AND attempt.attempt_number=2
     AND NOT EXISTS (
       SELECT 1 FROM eogp.event_notification_delivery_attempt_events event
        WHERE event.organization_id=attempt.organization_id AND event.attempt_id=attempt.id
     );
  IF v_queued<>1 THEN
    RAISE EXCEPTION 'expected one retry queued after temporary failure, got %',v_queued;
  END IF;
END;
$delivery_first$;

DO $delivery_retry$
DECLARE
  v_campaign_id uuid;
  v_status text;
  v_attempt_count integer;
  v_retry_count integer;
BEGIN
  SELECT id,status INTO v_campaign_id,v_status
    FROM eogp.event_notification_campaigns
   WHERE organization_id='22222222-2222-4222-8222-222222222222'
     AND event_decision_id='94900000-0000-4000-8000-000000000001';
  SELECT count(*) INTO v_attempt_count
    FROM eogp.event_notification_delivery_attempts
   WHERE organization_id='22222222-2222-4222-8222-222222222222'
     AND campaign_id=v_campaign_id;
  SELECT count(*) INTO v_retry_count
    FROM eogp.event_notification_delivery_attempts attempt
   WHERE attempt.organization_id='22222222-2222-4222-8222-222222222222'
     AND attempt.campaign_id=v_campaign_id
     AND attempt.status='queued' AND attempt.attempt_number=2
     AND NOT EXISTS (
       SELECT 1 FROM eogp.event_notification_delivery_attempt_events event
        WHERE event.organization_id=attempt.organization_id AND event.attempt_id=attempt.id
     );
  IF v_status<>'sending' OR v_attempt_count<>3 OR v_retry_count<>1 THEN
    RAISE EXCEPTION 'retry state machine ended unexpectedly: status %, attempts %, queued retries %',
      v_status,v_attempt_count,v_retry_count;
  END IF;
END;
$delivery_retry$;
COMMIT;

\echo 'SMTP delivery worker state-machine smoke tests passed.'
