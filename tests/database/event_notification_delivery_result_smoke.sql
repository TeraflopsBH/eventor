\set ON_ERROR_STOP on
BEGIN;
SET LOCAL app.organization_id='22222222-2222-4222-8222-222222222222';

DO $delivery_result$
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
$delivery_result$;
COMMIT;

\echo 'SMTP delivery result smoke tests passed.'
