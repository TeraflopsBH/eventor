\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
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
    RAISE EXCEPTION 'committed confirmation fixtures are missing: resource holds %, space holds %',
      v_resource_holds, v_space_holds;
  END IF;
END;
$test$;
COMMIT;
