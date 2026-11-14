\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','11111111-1111-4111-8111-111111111111',true);

-- The preceding runtime release test has released this exact booking-space
-- interval. Prepare two other terminal claims over the same interval and let
-- the real expiry command transition an overdue hold to expired.
DO $test$
DECLARE
  v_venue_space_id uuid;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
  v_expired_hold_id uuid := '89000000-0000-4000-8000-000000000003';
  v_expired_count bigint;
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

  INSERT INTO eogp.booking_drafts(
    id,organization_id,created_by_membership_id,status,current_revision_number
  ) VALUES(
    '89000000-0000-4000-8000-000000000001',
    '11111111-1111-4111-8111-111111111111',
    'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa','draft',1
  );

  INSERT INTO eogp.booking_draft_revisions(
    id,organization_id,draft_id,revision_number,values_snapshot,timezone_name,
    change_reason,created_by_membership_id
  ) VALUES(
    '89000000-0000-4000-8000-000000000002',
    '11111111-1111-4111-8111-111111111111',
    '89000000-0000-4000-8000-000000000001',1,'{"fixture":"space-reuse-lifecycle"}',
    'Europe/Sarajevo','Space reservation reuse lifecycle regression',
    'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa'
  );

  INSERT INTO eogp.venue_space_time_blocks(
    organization_id,venue_space_id,booking_draft_revision_id,reservation_kind,status,
    starts_at,ends_at,expires_at,idempotency_key,actor_membership_id
  ) VALUES(
    '11111111-1111-4111-8111-111111111111',v_venue_space_id,
    '89000000-0000-4000-8000-000000000002','draft_hold','cancelled',
    v_starts_at,v_ends_at,NULL,'ci-space-reuse-cancelled-hold',
    'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa'
  );

  INSERT INTO eogp.venue_space_time_blocks(
    id,organization_id,venue_space_id,booking_draft_revision_id,reservation_kind,status,
    starts_at,ends_at,expires_at,idempotency_key,actor_membership_id
  ) VALUES(
    v_expired_hold_id,'11111111-1111-4111-8111-111111111111',v_venue_space_id,
    '89000000-0000-4000-8000-000000000002','draft_hold','held',
    v_starts_at,v_ends_at,clock_timestamp()+interval '1 second',
    'ci-space-reuse-expired-hold','aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa'
  );

  -- Preserve the future-expiry invariant and let wall-clock time elapse;
  -- direct deadline backdating is intentionally rejected by the guard trigger.
  PERFORM pg_sleep(1.1);
  v_expired_count:=eogp.expire_space_holds('11111111-1111-4111-8111-111111111111');
  IF v_expired_count<1 OR NOT EXISTS(
    SELECT 1 FROM eogp.venue_space_time_blocks
     WHERE organization_id='11111111-1111-4111-8111-111111111111'
       AND id=v_expired_hold_id AND status='expired'
  ) THEN
    RAISE EXCEPTION 'space expiry command did not expire the overdue hold (changed rows: %)',v_expired_count;
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM eogp.venue_space_time_blocks
     WHERE organization_id='11111111-1111-4111-8111-111111111111'
       AND id='15000000-0000-4000-8000-000000000002' AND status='released'
  ) OR NOT EXISTS(
    SELECT 1 FROM eogp.venue_space_time_blocks
     WHERE organization_id='11111111-1111-4111-8111-111111111111'
       AND idempotency_key='ci-space-reuse-cancelled-hold' AND status='cancelled'
  ) THEN
    RAISE EXCEPTION 'terminal release/cancellation fixture states were not preserved';
  END IF;
END;
$test$;
COMMIT;
