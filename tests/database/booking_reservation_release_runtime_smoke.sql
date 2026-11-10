\set ON_ERROR_STOP on
BEGIN;
SELECT set_config('app.organization_id','11111111-1111-4111-8111-111111111111',true);

DO $test$
DECLARE
  v_resource_id uuid;
  v_unselected_resource_id uuid;
  v_space_id uuid := '15000000-0000-4000-8000-000000000002';
  v_released bigint;
  v_retry bigint;
  v_audit_count integer;
  v_metadata jsonb;
BEGIN
  SELECT id INTO v_resource_id
    FROM eogp.resource_reservations
   WHERE organization_id = '11111111-1111-4111-8111-111111111111'
     AND booking_id = '73000000-0000-4000-8000-000000000001'
     AND resource_pool_id IS NOT NULL
     AND status = 'confirmed'
   ORDER BY id
   LIMIT 1;

  SELECT id INTO v_unselected_resource_id
    FROM eogp.resource_reservations
   WHERE organization_id = '11111111-1111-4111-8111-111111111111'
     AND booking_id = '73000000-0000-4000-8000-000000000001'
     AND resource_unit_id IS NOT NULL
     AND status = 'confirmed'
   ORDER BY id
   LIMIT 1;

  IF v_resource_id IS NULL OR v_unselected_resource_id IS NULL THEN
    RAISE EXCEPTION 'confirmed pooled and unit reservation fixtures are required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM eogp.venue_space_time_blocks
     WHERE organization_id = '11111111-1111-4111-8111-111111111111'
       AND id = v_space_id
       AND booking_id = '73000000-0000-4000-8000-000000000001'
       AND status = 'confirmed'
  ) THEN
    RAISE EXCEPTION 'confirmed venue-space reservation fixture is required';
  END IF;

  -- A partial request may mix resource and space reservation IDs.
  v_released := eogp.release_booking_reservations(
    '11111111-1111-4111-8111-111111111111',
    '73000000-0000-4000-8000-000000000001',
    ARRAY[v_resource_id, v_space_id],
    'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',
    'ci_partial_release'
  );
  IF v_released <> 2 THEN
    RAISE EXCEPTION 'expected exactly two selected reservation rows to be released, got %', v_released;
  END IF;

  IF (SELECT status FROM eogp.resource_reservations
       WHERE organization_id = '11111111-1111-4111-8111-111111111111'
         AND id = v_resource_id) <> 'released'
     OR (SELECT status FROM eogp.venue_space_time_blocks
          WHERE organization_id = '11111111-1111-4111-8111-111111111111'
            AND id = v_space_id) <> 'released' THEN
    RAISE EXCEPTION 'selected resource/space reservation was not released';
  END IF;

  IF (SELECT status FROM eogp.resource_reservations
       WHERE organization_id = '11111111-1111-4111-8111-111111111111'
         AND id = v_unselected_resource_id) <> 'confirmed' THEN
    RAISE EXCEPTION 'release command changed a reservation that was not selected';
  END IF;

  -- Retry only sees already-terminal selected rows: no new change or audit.
  v_retry := eogp.release_booking_reservations(
    '11111111-1111-4111-8111-111111111111',
    '73000000-0000-4000-8000-000000000001',
    ARRAY[v_resource_id, v_space_id],
    'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',
    'ci_partial_release'
  );
  IF v_retry <> 0 THEN
    RAISE EXCEPTION 'release retry should return zero, got %', v_retry;
  END IF;

  SELECT count(*), max(safe_metadata)
    INTO v_audit_count, v_metadata
    FROM eogp.audit_events
   WHERE organization_id = '11111111-1111-4111-8111-111111111111'
     AND action = 'booking.reservations.released'
     AND aggregate_type = 'booking'
     AND aggregate_id = '73000000-0000-4000-8000-000000000001'
     AND actor_membership_id = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa'
     AND reason_code = 'ci_partial_release';
  IF v_audit_count <> 1 THEN
    RAISE EXCEPTION 'expected exactly one release audit for the partial operation, got %', v_audit_count;
  END IF;
  IF v_metadata -> 'resourceReservationIdsReleased' <> jsonb_build_array(v_resource_id::text)
     OR v_metadata -> 'spaceReservationIdsReleased' <> jsonb_build_array(v_space_id::text) THEN
    RAISE EXCEPTION 'release audit does not identify the exact changed reservation rows: %', v_metadata;
  END IF;

  -- A mixed valid/unknown request must be rejected atomically.
  BEGIN
    PERFORM eogp.release_booking_reservations(
      '11111111-1111-4111-8111-111111111111',
      '73000000-0000-4000-8000-000000000001',
      ARRAY[v_unselected_resource_id, '99999999-9999-4999-8999-999999999999'::uuid],
      'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',
      'ci_invalid_release'
    );
    RAISE EXCEPTION 'release accepted an ID that does not belong to this booking';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;
  IF (SELECT status FROM eogp.resource_reservations
       WHERE organization_id = '11111111-1111-4111-8111-111111111111'
         AND id = v_unselected_resource_id) <> 'confirmed' THEN
    RAISE EXCEPTION 'invalid mixed request partially released a valid reservation';
  END IF;

  -- The caller must not be able to target duplicate or empty ID arrays.
  BEGIN
    PERFORM eogp.release_booking_reservations(
      '11111111-1111-4111-8111-111111111111',
      '73000000-0000-4000-8000-000000000001',
      ARRAY[v_unselected_resource_id, v_unselected_resource_id],
      'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',
      'ci_duplicate_release'
    );
    RAISE EXCEPTION 'release accepted duplicate reservation IDs';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  BEGIN
    PERFORM eogp.release_booking_reservations(
      '11111111-1111-4111-8111-111111111111',
      '73000000-0000-4000-8000-000000000001',
      ARRAY[]::uuid[],
      'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',
      'ci_empty_release'
    );
    RAISE EXCEPTION 'release accepted an empty reservation ID array';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  -- Membership in a different tenant cannot authorize this booking action.
  BEGIN
    PERFORM eogp.release_booking_reservations(
      '11111111-1111-4111-8111-111111111111',
      '73000000-0000-4000-8000-000000000001',
      ARRAY[v_unselected_resource_id],
      'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
      'ci_wrong_actor'
    );
    RAISE EXCEPTION 'release accepted a membership from another organization';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;
END;
$test$;

COMMIT;
