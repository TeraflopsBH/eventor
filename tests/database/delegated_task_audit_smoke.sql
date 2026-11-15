\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','11111111-1111-4111-8111-111111111111',true);

DO $test$
DECLARE
  v_count integer;
BEGIN
  SELECT count(*) INTO v_count
    FROM eogp.audit_events
   WHERE organization_id = '11111111-1111-4111-8111-111111111111'
     AND action = 'event.task.status.changed'
     AND aggregate_type = 'event_responsibility_assignment'
     AND aggregate_id = '67000000-0000-4000-8000-000000000001'
     AND actor_organization_id = '22222222-2222-4222-8222-222222222222'
     AND actor_membership_id = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
     AND authorization_grant_owner_organization_id = '11111111-1111-4111-8111-111111111111'
     AND authorization_grant_id = '61000000-0000-4000-8000-000000000099'
     AND reason_code = 'ci_started';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'expected one owner-tenant audit row with delegated actor provenance; got %', v_count;
  END IF;
END;
$test$;
COMMIT;
