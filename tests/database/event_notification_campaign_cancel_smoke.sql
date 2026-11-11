\set ON_ERROR_STOP on
BEGIN;
SET LOCAL app.organization_id='22222222-2222-4222-8222-222222222222';

DO $cancel$
DECLARE
  v_rejected boolean := false;
  v_status text;
BEGIN
  BEGIN
    PERFORM eogp.cancel_queued_event_notification_campaign(
      '22222222-2222-4222-8222-222222222222',
      (SELECT id FROM eogp.event_notification_campaigns
        WHERE organization_id='22222222-2222-4222-8222-222222222222'
          AND event_decision_id='94900000-0000-4000-8000-000000000001'),
      'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
    );
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_rejected := true;
  END;

  SELECT status INTO v_status
    FROM eogp.event_notification_campaigns
   WHERE organization_id='22222222-2222-4222-8222-222222222222'
     AND event_decision_id='94900000-0000-4000-8000-000000000001';
  IF NOT v_rejected OR v_status<>'sending' THEN
    RAISE EXCEPTION 'a campaign already being sent must not be cancelled: rejected %, status %',
      v_rejected,v_status;
  END IF;
END;
$cancel$;
COMMIT;

\echo 'Notification campaign cancellation guard smoke test passed.'
