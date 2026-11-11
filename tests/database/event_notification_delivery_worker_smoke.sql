\set ON_ERROR_STOP on
BEGIN;
SET LOCAL app.organization_id='22222222-2222-4222-8222-222222222222';

DO $delivery_first$
DECLARE
  v_campaign_id uuid;
  v_job record;
  v_result jsonb;
  v_retry_scheduled boolean := false;
  v_message_reference text;
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
     OR v_job.smtp_settings->>'host'<>'smtp.resend.com'
     OR v_job.sender_email<>'events@example.test'
     OR v_job.subject_template IS NULL THEN
    RAISE EXCEPTION 'worker claim did not return the required encrypted SMTP job';
  END IF;
  v_message_reference:=eogp.prepare_resend_delivery_submission(
    '22222222-2222-4222-8222-222222222222',v_job.attempt_id
  );
  IF v_message_reference IS DISTINCT FROM
     '<eventor-' || replace(v_job.attempt_id::text,'-','') || '@delivery.eventor.invalid>' THEN
    RAISE EXCEPTION 'Resend Message-ID was not stable and attempt-specific: %',v_message_reference;
  END IF;
  v_result:=eogp.complete_email_delivery_attempt(
    '22222222-2222-4222-8222-222222222222',
    v_job.attempt_id,'sent',NULL,v_message_reference
  );
  IF v_result->>'outcome'<>'sent' THEN
    RAISE EXCEPTION 'successful SMTP acceptance was not recorded';
  END IF;

  v_result:=eogp.record_verified_notification_provider_event(
    '22222222-2222-4222-8222-222222222222','smtp','ci-provider-event-1',
    v_job.attempt_id,v_message_reference,'delivered',repeat('a',64)
  );
  IF v_result->>'status'<>'delivered' OR (v_result->>'duplicate')::boolean THEN
    RAISE EXCEPTION 'verified provider delivery event was not recorded';
  END IF;
  v_result:=eogp.record_verified_notification_provider_event(
    '22222222-2222-4222-8222-222222222222','smtp','ci-provider-event-1',
    v_job.attempt_id,v_message_reference,'delivered',repeat('a',64)
  );
  IF NOT (v_result->>'duplicate')::boolean THEN
    RAISE EXCEPTION 'duplicate provider callback was not idempotent';
  END IF;

  SELECT * INTO v_job
    FROM eogp.claim_next_email_delivery('22222222-2222-4222-8222-222222222222');
  IF v_job.attempt_id IS NULL THEN
    RAISE EXCEPTION 'second queued recipient was not claimable';
  END IF;
  v_message_reference:=eogp.prepare_resend_delivery_submission(
    '22222222-2222-4222-8222-222222222222',v_job.attempt_id
  );
  v_result:=eogp.complete_email_delivery_attempt(
    '22222222-2222-4222-8222-222222222222',
    v_job.attempt_id,'uncertain','SMTP_UNKNOWN',NULL
  );
  v_retry_scheduled:=(v_result->>'retryScheduled')::boolean;
  IF v_retry_scheduled THEN
    RAISE EXCEPTION 'uncertain SMTP outcome must never schedule an automatic retry';
  END IF;

  -- Keep a second independent uncertain attempt so the Resend smoke can
  -- resolve one via provider callback while the reporting smoke exercises
  -- explicit operator reconciliation on the other.
  SELECT * INTO v_job
    FROM eogp.claim_next_email_delivery('22222222-2222-4222-8222-222222222222');
  IF v_job.attempt_id IS NULL THEN
    RAISE EXCEPTION 'third recipient delivery attempt was not claimable';
  END IF;
  v_message_reference:=eogp.prepare_resend_delivery_submission(
    '22222222-2222-4222-8222-222222222222',v_job.attempt_id
  );
  v_result:=eogp.complete_email_delivery_attempt(
    '22222222-2222-4222-8222-222222222222',
    v_job.attempt_id,'uncertain','SMTP_UNKNOWN',NULL
  );
  IF (v_result->>'retryScheduled')::boolean THEN
    RAISE EXCEPTION 'third uncertain SMTP outcome must never schedule an automatic retry';
  END IF;

END;
$delivery_first$;

DO $delivery_retry$
DECLARE
  v_campaign_id uuid;
  v_status text;
  v_attempt_count integer;
BEGIN
  SELECT id,status INTO v_campaign_id,v_status
    FROM eogp.event_notification_campaigns
   WHERE organization_id='22222222-2222-4222-8222-222222222222'
     AND event_decision_id='94900000-0000-4000-8000-000000000001';
  SELECT count(*) INTO v_attempt_count
    FROM eogp.event_notification_delivery_attempts
   WHERE organization_id='22222222-2222-4222-8222-222222222222'
     AND campaign_id=v_campaign_id;
  IF v_status<>'partial' OR v_attempt_count<>3 THEN
    RAISE EXCEPTION 'delivery state machine ended unexpectedly: status %, attempts %',
      v_status,v_attempt_count;
  END IF;
END;
$delivery_retry$;
COMMIT;

\echo 'SMTP delivery worker state-machine smoke tests passed.'
