BEGIN;
SET LOCAL ROLE eventor_owner;
SET LOCAL app.organization_id='22222222-2222-4222-8222-222222222222';
DO $verify_real_expired_lease_recovery$
DECLARE
  v_delivery eogp.invitation_deliveries%ROWTYPE;
  v_attempt eogp.invitation_delivery_attempts%ROWTYPE;
BEGIN
  SELECT * INTO v_delivery
    FROM eogp.invitation_deliveries
   WHERE organization_id='22222222-2222-4222-8222-222222222222'
     AND id='96000000-0000-4000-8000-000000000001';
  SELECT * INTO v_attempt
    FROM eogp.invitation_delivery_attempts
   WHERE organization_id='22222222-2222-4222-8222-222222222222'
     AND delivery_id='96000000-0000-4000-8000-000000000001'
     AND attempt_number=1;
  IF v_delivery.status<>'uncertain'
     OR v_delivery.lease_expires_at IS NOT NULL
     OR v_delivery.failure_code<>'SMTP_UNKNOWN'
     OR NOT FOUND THEN
    RAISE EXCEPTION 'worker claim did not recover the expired delivery lease';
  END IF;
  IF v_attempt.status<>'uncertain'
     OR v_attempt.failure_code<>'SMTP_UNKNOWN'
     OR v_attempt.retry_scheduled
     OR v_attempt.completed_at IS NULL THEN
    RAISE EXCEPTION 'worker claim did not finalize the expired attempt history';
  END IF;
END;
$verify_real_expired_lease_recovery$;
ROLLBACK;
