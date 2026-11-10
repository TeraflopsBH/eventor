\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','11111111-1111-4111-8111-111111111111',true);

-- The confirmation smoke test has already converted this fixture's holds.
-- Move the confirmed booking into the cancellation state and grant the same
-- test actor the existing booking-scoped release permission.
DO $test$
DECLARE
  v_rows integer;
BEGIN
  UPDATE eogp.booking_records
     SET status = 'cancelled'
   WHERE organization_id = '11111111-1111-4111-8111-111111111111'
     AND id = '73000000-0000-4000-8000-000000000001'
     AND status = 'confirmed';
  GET DIAGNOSTICS v_rows = ROW_COUNT;

  IF v_rows <> 1 THEN
    RAISE EXCEPTION 'expected to cancel exactly one confirmed release-test booking, got %', v_rows;
  END IF;
END;
$test$;

INSERT INTO eogp.role_permissions (organization_id, role_id, permission_code)
VALUES (
  '11111111-1111-4111-8111-111111111111',
  '76000000-0000-4000-8000-000000000001',
  'booking.cancellation.execute'
)
ON CONFLICT DO NOTHING;

COMMIT;
