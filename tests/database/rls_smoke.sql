\set ON_ERROR_STOP on

BEGIN;
SELECT set_config('app.organization_id', :'organization_a', true);
DO $test$
DECLARE
  visible_count integer;
BEGIN
  SELECT count(*) INTO visible_count FROM eogp.venues;
  IF visible_count <> 2 THEN
    RAISE EXCEPTION 'tenant A should see exactly 2 venues, got %', visible_count;
  END IF;
END
$test$;

SELECT set_config('app.organization_id', :'organization_b', true);
DO $test$
DECLARE
  visible_count integer;
BEGIN
  SELECT count(*) INTO visible_count FROM eogp.venues;
  IF visible_count <> 1 THEN
    RAISE EXCEPTION 'tenant B should see exactly 1 venue, got %', visible_count;
  END IF;
END
$test$;

SELECT set_config('app.organization_id', '99999999-9999-4999-8999-999999999999', true);
DO $test$
DECLARE
  visible_count integer;
BEGIN
  SELECT count(*) INTO visible_count FROM eogp.venues;
  IF visible_count <> 0 THEN
    RAISE EXCEPTION 'unrelated tenant should see 0 venues, got %', visible_count;
  END IF;
END
$test$;
COMMIT;
