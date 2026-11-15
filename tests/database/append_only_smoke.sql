\set ON_ERROR_STOP on

-- Run as eventor_migrator, then temporarily SET ROLE to the table owner.
-- Even privileged maintenance-level table ownership must not rewrite history.
BEGIN;
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000b', true);
SET LOCAL ROLE eventor_owner;

DO $test$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM eogp.audit_events
     WHERE organization_id = '10000000-0000-0000-0000-00000000000b'
       AND action = 'collaboration.grant.accepted'
       AND aggregate_id = '61000000-0000-4000-8000-00000000000a'
  ) THEN
    RAISE EXCEPTION 'expected collaboration acceptance audit row is missing';
  END IF;

  BEGIN
    UPDATE eogp.audit_events
       SET reason_code = 'tampered'
     WHERE organization_id = '10000000-0000-0000-0000-00000000000b'
       AND action = 'collaboration.grant.accepted'
       AND aggregate_id = '61000000-0000-4000-8000-00000000000a';
    RAISE EXCEPTION 'expected append-only UPDATE trigger rejection';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;

  BEGIN
    DELETE FROM eogp.audit_events
     WHERE organization_id = '10000000-0000-0000-0000-00000000000b'
       AND action = 'collaboration.grant.accepted'
       AND aggregate_id = '61000000-0000-4000-8000-00000000000a';
    RAISE EXCEPTION 'expected append-only DELETE trigger rejection';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
END;
$test$;
ROLLBACK;

\echo 'Append-only owner-level trigger smoke tests passed.'
