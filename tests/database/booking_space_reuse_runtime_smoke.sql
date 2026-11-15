\set ON_ERROR_STOP on
BEGIN;
SELECT set_config('app.organization_id','11111111-1111-4111-8111-111111111111',true);

DO $test$
DECLARE
  v_venue_space_id uuid;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
  v_new_hold_id uuid;
BEGIN
  SELECT venue_space_id,starts_at,ends_at
    INTO v_venue_space_id,v_starts_at,v_ends_at
    FROM eogp.venue_space_time_blocks
   WHERE organization_id='11111111-1111-4111-8111-111111111111'
     AND id='15000000-0000-4000-8000-000000000002'
     AND booking_id='73000000-0000-4000-8000-000000000001'
     AND status='released';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'released booking-space reservation fixture is required';
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM eogp.venue_space_time_blocks
     WHERE organization_id='11111111-1111-4111-8111-111111111111'
       AND venue_space_id=v_venue_space_id
       AND starts_at=v_starts_at AND ends_at=v_ends_at
       AND idempotency_key='ci-space-reuse-cancelled-hold'
       AND status='cancelled'
  ) OR NOT EXISTS(
    SELECT 1 FROM eogp.venue_space_time_blocks
     WHERE organization_id='11111111-1111-4111-8111-111111111111'
       AND venue_space_id=v_venue_space_id
       AND starts_at=v_starts_at AND ends_at=v_ends_at
       AND idempotency_key='ci-space-reuse-expired-hold'
       AND status='expired'
  ) THEN
    RAISE EXCEPTION 'cancelled and worker-expired overlapping terminal claims are required';
  END IF;

  -- This is the runtime role's real write path: a new claim over the same
  -- half-open interval must be accepted after all previous claims are terminal.
  INSERT INTO eogp.venue_space_time_blocks(
    organization_id,venue_space_id,booking_draft_revision_id,reservation_kind,status,
    starts_at,ends_at,expires_at,idempotency_key,actor_membership_id
  ) VALUES(
    '11111111-1111-4111-8111-111111111111',v_venue_space_id,
    '89000000-0000-4000-8000-000000000002','draft_hold','held',
    v_starts_at,v_ends_at,clock_timestamp()+interval '1 day',
    'ci-space-reuse-new-active-hold','aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa'
  ) RETURNING id INTO v_new_hold_id;

  IF NOT EXISTS(
    SELECT 1 FROM eogp.venue_space_time_blocks
     WHERE organization_id='11111111-1111-4111-8111-111111111111'
       AND id=v_new_hold_id AND status='held'
       AND venue_space_id=v_venue_space_id
       AND starts_at=v_starts_at AND ends_at=v_ends_at
  ) THEN
    RAISE EXCEPTION 'runtime could not persist the replacement hold over the released interval';
  END IF;
END;
$test$;
ROLLBACK;
