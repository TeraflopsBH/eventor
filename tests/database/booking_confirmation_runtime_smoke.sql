\set ON_ERROR_STOP on
BEGIN;
SELECT set_config('app.organization_id','11111111-1111-4111-8111-111111111111',true);
DO $test$
DECLARE
  v_resource_holds integer;
  v_space_holds integer;
BEGIN
  SELECT count(*) INTO v_resource_holds
    FROM eogp.resource_reservations
   WHERE organization_id = '11111111-1111-4111-8111-111111111111'
     AND booking_draft_revision_id = '51000000-0000-4000-8000-000000000002'
     AND status = 'held'
     AND idempotency_key IN ('ci-confirm-pooled-hold-01','ci-confirm-unit-hold-01');
  SELECT count(*) INTO v_space_holds
    FROM eogp.venue_space_time_blocks
   WHERE organization_id = '11111111-1111-4111-8111-111111111111'
     AND booking_draft_revision_id = '51000000-0000-4000-8000-000000000002'
     AND status = 'held'
     AND idempotency_key = 'ci-confirm-space-hold-01';
  IF v_resource_holds <> 2 OR v_space_holds <> 1 THEN
    RAISE EXCEPTION 'runtime cannot see confirmation fixtures: tenant context %, resource holds %, space holds %',
      eogp.current_organization_id(), v_resource_holds, v_space_holds;
  END IF;
END;
$test$;

DO $test$
DECLARE
  v_result jsonb;
  v_resource_count integer;
  v_old_hold_count integer;
  v_space_count integer;
  v_audit_count integer;
BEGIN
  v_result := eogp.confirm_booking_reservations(
    '11111111-1111-4111-8111-111111111111',
    '51000000-0000-4000-8000-000000000002',
    '73000000-0000-4000-8000-000000000001',
    'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',
    'ci_booking_confirmed'
  );

  IF (v_result ->> 'resourceReservationsConfirmed')::integer <> 2
     OR (v_result ->> 'spaceReservationsConfirmed')::integer <> 1
     OR (v_result ->> 'changed')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'reservation confirmation returned unexpected result: %', v_result;
  END IF;

  SELECT count(*) INTO v_old_hold_count
    FROM eogp.resource_reservations
   WHERE organization_id = '11111111-1111-4111-8111-111111111111'
     AND booking_draft_revision_id = '51000000-0000-4000-8000-000000000002'
     AND id IN (
       '43000000-0000-4000-8000-000000000001',
       (SELECT id FROM eogp.resource_reservations
         WHERE organization_id = '11111111-1111-4111-8111-111111111111'
           AND idempotency_key = 'ci-confirm-unit-hold-01')
     )
     AND status = 'released';
  IF v_old_hold_count <> 2 THEN
    RAISE EXCEPTION 'expected both draft resource holds to be released, got %', v_old_hold_count;
  END IF;

  SELECT count(*) INTO v_resource_count
    FROM eogp.resource_reservations
   WHERE organization_id = '11111111-1111-4111-8111-111111111111'
     AND booking_id = '73000000-0000-4000-8000-000000000001'
     AND booking_resource_line_id = '74000000-0000-4000-8000-000000000001'
     AND booking_draft_revision_id IS NULL
     AND status = 'confirmed'
     AND expires_at IS NULL;
  IF v_resource_count <> 2 THEN
    RAISE EXCEPTION 'expected pooled and discrete booking reservations with mapped booking line, got %', v_resource_count;
  END IF;

  SELECT count(*) INTO v_space_count
    FROM eogp.venue_space_time_blocks
   WHERE organization_id = '11111111-1111-4111-8111-111111111111'
     AND id = '15000000-0000-4000-8000-000000000002'
     AND reservation_kind = 'booking'
     AND booking_draft_revision_id IS NULL
     AND booking_id = '73000000-0000-4000-8000-000000000001'
     AND status = 'confirmed'
     AND expires_at IS NULL;
  IF v_space_count <> 1 THEN
    RAISE EXCEPTION 'draft space hold was not atomically converted to booking occupancy';
  END IF;

  -- A retry must be harmless and must not emit a second audit event.
  v_result := eogp.confirm_booking_reservations(
    '11111111-1111-4111-8111-111111111111',
    '51000000-0000-4000-8000-000000000002',
    '73000000-0000-4000-8000-000000000001',
    'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',
    'ci_booking_confirmed'
  );
  IF (v_result ->> 'changed')::boolean IS DISTINCT FROM false
     OR (v_result ->> 'resourceReservationsConfirmed')::integer <> 0
     OR (v_result ->> 'spaceReservationsConfirmed')::integer <> 0 THEN
    RAISE EXCEPTION 'booking confirmation retry was not idempotent: %', v_result;
  END IF;

  SELECT count(*) INTO v_audit_count
    FROM eogp.audit_events
   WHERE organization_id = '11111111-1111-4111-8111-111111111111'
     AND action = 'booking.reservations.confirmed'
     AND aggregate_type = 'booking'
     AND aggregate_id = '73000000-0000-4000-8000-000000000001'
     AND actor_membership_id = 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa'
     AND reason_code = 'ci_booking_confirmed';
  IF v_audit_count <> 1 THEN
    RAISE EXCEPTION 'expected exactly one booking reservation confirmation audit, got %', v_audit_count;
  END IF;

  BEGIN
    PERFORM eogp.confirm_booking_reservations(
      '11111111-1111-4111-8111-111111111111',
      '51000000-0000-4000-8000-000000000002',
      '73000000-0000-4000-8000-000000000001',
      'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
      'ci_wrong_actor'
    );
    RAISE EXCEPTION 'booking confirmation accepted a membership from another organization';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;
END;
$test$;
COMMIT;
