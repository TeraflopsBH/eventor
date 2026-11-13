\set ON_ERROR_STOP on
BEGIN;
SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);

DO $test$
DECLARE
  v_projection jsonb;
  v_unexpected_id uuid;
BEGIN
  -- Runtime cannot inspect any assignment column directly. Access goes through
  -- the function, which validates the actual membership argument.
  BEGIN
    SELECT id INTO v_unexpected_id
      FROM eogp.event_responsibility_assignments
     WHERE id = '67000000-0000-4000-8000-000000000001';
    RAISE EXCEPTION 'runtime directly read the delegated task table';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;

  v_projection := eogp.get_assigned_task_projection(
    '67000000-0000-4000-8000-000000000001',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
  );
  IF v_projection ->> 'taskCode' <> 'CI-SETUP'
     OR v_projection ->> 'status' <> 'not_started'
     OR v_projection ? 'evidenceReference' THEN
    RAISE EXCEPTION 'delegated task projection is not the expected allowlisted shape: %', v_projection;
  END IF;

  BEGIN
    PERFORM eogp.get_assigned_task_projection(
      '67000000-0000-4000-8000-000000000001',
      'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa'
    );
    RAISE EXCEPTION 'task projection accepted a membership from the wrong organization';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;

  v_projection := eogp.update_assigned_task_status(
    '67000000-0000-4000-8000-000000000001',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    'in_progress',
    'ci_started',
    '{"workOrder":"CI-001"}'::jsonb
  );
  IF v_projection ->> 'status' <> 'in_progress' THEN
    RAISE EXCEPTION 'delegated task status command did not return the updated status';
  END IF;

  v_projection := eogp.get_assigned_task_projection(
    '67000000-0000-4000-8000-000000000001',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
  );
  IF v_projection ->> 'status' <> 'in_progress' THEN
    RAISE EXCEPTION 'delegated task status command did not persist the status';
  END IF;

  BEGIN
    PERFORM eogp.update_assigned_task_status(
      '67000000-0000-4000-8000-000000000001',
      'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
      'not_started',
      'ci_invalid_reverse',
      '{}'::jsonb
    );
    RAISE EXCEPTION 'invalid delegated task status transition unexpectedly succeeded';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
END;
$test$;

COMMIT;
