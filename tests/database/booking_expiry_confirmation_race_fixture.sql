\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','11111111-1111-4111-8111-111111111111',true);

DO $test$
DECLARE
  v_space_id uuid;
BEGIN
  -- Use a free active space and a distant interval so this fixture is isolated
  -- from the booking confirmation/release fixtures already in the CI database.
  SELECT space.id INTO v_space_id
    FROM eogp.venue_spaces space
   WHERE space.organization_id='11111111-1111-4111-8111-111111111111'
     AND space.status='active'
     AND NOT EXISTS (
       SELECT 1
         FROM eogp.venue_space_time_blocks block
        WHERE block.organization_id=space.organization_id
          AND block.venue_space_id=space.id
          AND block.status IN ('held','confirmed','blocked')
          AND tstzrange(block.starts_at,block.ends_at,'[)')
              && tstzrange('2037-01-01 10:00:00+00'::timestamptz,
                           '2037-01-01 11:00:00+00'::timestamptz,'[)')
     )
   ORDER BY space.id
   LIMIT 1;

  IF v_space_id IS NULL THEN
    RAISE EXCEPTION 'an active venue space without a 2037 fixture conflict is required';
  END IF;

  INSERT INTO eogp.venue_space_time_blocks(
    id,organization_id,venue_space_id,booking_draft_revision_id,
    reservation_kind,status,starts_at,ends_at,expires_at,
    idempotency_key,actor_membership_id
  ) VALUES(
    '8a000000-0000-4000-8000-000000000001',
    '11111111-1111-4111-8111-111111111111',
    v_space_id,
    '51000000-0000-4000-8000-000000000002',
    'draft_hold','held',
    '2037-01-01 10:00:00+00','2037-01-01 11:00:00+00',
    clock_timestamp()+interval '3 seconds',
    'ci-expiry-confirm-race-worker-wins',
    'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa'
  );
END;
$test$;
COMMIT;
