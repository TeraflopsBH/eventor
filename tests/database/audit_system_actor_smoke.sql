\set ON_ERROR_STOP on

BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);

DO $system_actor_regression$
DECLARE
  v_valid_insert_rolled_back boolean := false;
  v_invalid_identity_rejected boolean := false;
BEGIN
  BEGIN
    INSERT INTO eogp.audit_events (
      organization_id,actor_kind,action,aggregate_type,reason_code,safe_metadata,occurred_at
    ) VALUES (
      '22222222-2222-4222-8222-222222222222','system',
      'ci.system_actor.accepted','ci_fixture','regression',
      '{}'::jsonb,clock_timestamp()
    );
    RAISE EXCEPTION 'rollback valid system actor fixture' USING ERRCODE='P0001';
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    v_valid_insert_rolled_back := true;
  END;

  IF NOT v_valid_insert_rolled_back THEN
    RAISE EXCEPTION 'valid system actor insert was not exercised';
  END IF;

  BEGIN
    INSERT INTO eogp.audit_events (
      organization_id,actor_membership_id,actor_kind,action,aggregate_type,reason_code,safe_metadata,occurred_at
    ) VALUES (
      '22222222-2222-4222-8222-222222222222',
      'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb','system',
      'ci.system_actor.invalid','ci_fixture','regression',
      '{}'::jsonb,clock_timestamp()
    );
    RAISE EXCEPTION 'invalid system actor identity unexpectedly succeeded';
  EXCEPTION WHEN check_violation THEN
    v_invalid_identity_rejected := true;
  END;

  IF NOT v_invalid_identity_rejected THEN
    RAISE EXCEPTION 'invalid system actor identity was not rejected';
  END IF;
END;
$system_actor_regression$;

ROLLBACK;
