\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SET LOCAL app.organization_id='22222222-2222-4222-8222-222222222222';

-- Reuse the committed event-notification fixture's event, schedule,
-- participations, memberships and invitations. Everything added here rolls back.
-- The notification worker fixture intentionally cancels its event. Temporarily
-- restore its lifecycle state inside this transaction so invitation revision
-- guards permit the fixture rows; the event change is rolled back at the end.
UPDATE eogp.events
   SET status='scheduled',updated_at=clock_timestamp()
 WHERE organization_id='22222222-2222-4222-8222-222222222222'
   AND id='94000000-0000-4000-8000-000000000001';

INSERT INTO eogp.rsvp_policies (
  id, organization_id, event_id, code, name
) VALUES (
  '95100000-0000-4000-8000-000000000001',
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  'CI_GUEST_ATTEMPT_HISTORY','CI guest attempt history'
);

INSERT INTO eogp.rsvp_policy_revisions (
  id, organization_id, event_id, policy_id, revision_number,
  event_timezone, state, published_at
) VALUES (
  '95200000-0000-4000-8000-000000000001',
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  '95100000-0000-4000-8000-000000000001',
  1,'Europe/Sarajevo','published',clock_timestamp()
);

INSERT INTO eogp.invitation_revisions (
  id, organization_id, event_id, invitation_id, revision_number,
  schedule_revision_id, rsvp_policy_revision_id, locale,
  presentation_snapshot_ciphertext, issued_at, created_by_membership_id
)
SELECT
  ('95300000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  ('94500000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
  1,
  '94100000-0000-4000-8000-000000000001',
  '95200000-0000-4000-8000-000000000001',
  'en',decode('455631010203','hex'),clock_timestamp(),
  'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
FROM generate_series(1,4) AS n;

INSERT INTO eogp.invitation_deliveries (
  id, organization_id, event_id, invitation_id, invitation_revision_id,
  channel, destination_ciphertext, destination_hash, status
)
SELECT
  ('95400000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  ('94500000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
  ('95300000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
  'email',decode('45435031010203','hex'),repeat(n::text,64),'queued'
FROM generate_series(1,4) AS n;

DO $attempt_history_regression$
DECLARE
  v_org uuid := '22222222-2222-4222-8222-222222222222';
  v_retry_delivery uuid := '95400000-0000-4000-8000-000000000001';
  v_uncertain_delivery uuid := '95400000-0000-4000-8000-000000000002';
  v_expired_delivery uuid := '95400000-0000-4000-8000-000000000003';
  v_suppressed_delivery uuid := '95400000-0000-4000-8000-000000000004';
  v_attempt record;
  v_count integer;
BEGIN
  -- A queued delivery has no SMTP attempt until it enters sending.
  SELECT count(*) INTO v_count
    FROM eogp.invitation_delivery_attempts
   WHERE organization_id=v_org AND delivery_id=v_retry_delivery;
  IF v_count<>0 THEN
    RAISE EXCEPTION 'queued delivery unexpectedly created an attempt';
  END IF;

  -- First SMTP claim, transient failure, and retry scheduling.
  UPDATE eogp.invitation_deliveries
     SET status='sending',attempt_count=1,
         lease_expires_at=clock_timestamp()+interval '5 minutes'
   WHERE organization_id=v_org AND id=v_retry_delivery;

  UPDATE eogp.invitation_deliveries
     SET status='queued',lease_expires_at=NULL,
         failure_code='SMTP_CONNECTION'
   WHERE organization_id=v_org AND id=v_retry_delivery;

  SELECT * INTO v_attempt
    FROM eogp.invitation_delivery_attempts
   WHERE organization_id=v_org AND delivery_id=v_retry_delivery
     AND attempt_number=1;
  IF NOT FOUND OR v_attempt.status<>'failed'
     OR v_attempt.failure_code<>'SMTP_CONNECTION'
     OR NOT v_attempt.retry_scheduled OR v_attempt.completed_at IS NULL THEN
    RAISE EXCEPTION 'transient failure did not finalize attempt 1 as retryable';
  END IF;

  -- Second claim succeeds and preserves the provider reference.
  UPDATE eogp.invitation_deliveries
     SET status='sending',attempt_count=2,
         lease_expires_at=clock_timestamp()+interval '5 minutes',
         failure_code=NULL
   WHERE organization_id=v_org AND id=v_retry_delivery;

  UPDATE eogp.invitation_deliveries
     SET status='sent',lease_expires_at=NULL,failure_code=NULL,
         provider_message_reference='<ci-guest-attempt-2@example.test>'
   WHERE organization_id=v_org AND id=v_retry_delivery;

  SELECT * INTO v_attempt
    FROM eogp.invitation_delivery_attempts
   WHERE organization_id=v_org AND delivery_id=v_retry_delivery
     AND attempt_number=2;
  IF NOT FOUND OR v_attempt.status<>'sent'
     OR v_attempt.provider_message_reference IS DISTINCT FROM '<ci-guest-attempt-2@example.test>'
     OR v_attempt.retry_scheduled OR v_attempt.completed_at IS NULL THEN
    RAISE EXCEPTION 'successful attempt 2 did not preserve sent/provider details';
  END IF;

  SELECT count(*) INTO v_count
    FROM eogp.invitation_delivery_attempts
   WHERE organization_id=v_org AND delivery_id=v_retry_delivery;
  IF v_count<>2 THEN
    RAISE EXCEPTION 'retry delivery should have exactly two attempt rows, got %',v_count;
  END IF;

  -- An ambiguous SMTP outcome is terminal and is never marked retryable.
  UPDATE eogp.invitation_deliveries
     SET status='sending',attempt_count=1,
         lease_expires_at=clock_timestamp()+interval '5 minutes'
   WHERE organization_id=v_org AND id=v_uncertain_delivery;

  UPDATE eogp.invitation_deliveries
     SET status='uncertain',lease_expires_at=NULL,
         failure_code='SMTP_UNKNOWN'
   WHERE organization_id=v_org AND id=v_uncertain_delivery;

  SELECT * INTO v_attempt
    FROM eogp.invitation_delivery_attempts
   WHERE organization_id=v_org AND delivery_id=v_uncertain_delivery
     AND attempt_number=1;
  IF NOT FOUND OR v_attempt.status<>'uncertain'
     OR v_attempt.failure_code<>'SMTP_UNKNOWN'
     OR v_attempt.retry_scheduled OR v_attempt.completed_at IS NULL THEN
    RAISE EXCEPTION 'uncertain SMTP outcome was not recorded as non-retryable';
  END IF;

  -- Expired lease recovery uses the same sending -> uncertain transition
  -- performed by claim_invitation_email_delivery().
  UPDATE eogp.invitation_deliveries
     SET status='sending',attempt_count=1,
         lease_expires_at=clock_timestamp()-interval '1 second'
   WHERE organization_id=v_org AND id=v_expired_delivery;

  UPDATE eogp.invitation_deliveries
     SET status='uncertain',lease_expires_at=NULL,
         failure_code='SMTP_UNKNOWN'
   WHERE organization_id=v_org AND id=v_expired_delivery
     AND status='sending' AND lease_expires_at<=clock_timestamp();

  SELECT * INTO v_attempt
    FROM eogp.invitation_delivery_attempts
   WHERE organization_id=v_org AND delivery_id=v_expired_delivery
     AND attempt_number=1;
  IF NOT FOUND OR v_attempt.status<>'uncertain'
     OR v_attempt.failure_code<>'SMTP_UNKNOWN'
     OR v_attempt.retry_scheduled OR v_attempt.completed_at IS NULL THEN
    RAISE EXCEPTION 'expired lease did not finalize its attempt as uncertain';
  END IF;

  -- Suppression before a worker claim must not create an SMTP attempt.
  UPDATE eogp.invitation_deliveries
     SET status='suppressed',failure_code='INVITATION_REVOKED'
   WHERE organization_id=v_org AND id=v_suppressed_delivery;

  SELECT count(*) INTO v_count
    FROM eogp.invitation_delivery_attempts
   WHERE organization_id=v_org AND delivery_id=v_suppressed_delivery;
  IF v_count<>0 THEN
    RAISE EXCEPTION 'pre-send suppression unexpectedly created an attempt';
  END IF;
END;
$attempt_history_regression$;

ROLLBACK;

\echo 'Guest invitation delivery attempt-history transition regressions passed.'
