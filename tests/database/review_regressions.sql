\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','11111111-1111-4111-8111-111111111111',true);

-- SECURITY DEFINER expiry functions must never be executable by PUBLIC,
-- the normal runtime role or the isolated authentication role.
DO $test$
DECLARE
  v_public_execute boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1
      FROM pg_proc AS proc
      JOIN pg_namespace AS ns ON ns.oid = proc.pronamespace
      CROSS JOIN LATERAL aclexplode(
        coalesce(proc.proacl, acldefault('f', proc.proowner))
      ) AS acl
     WHERE ns.nspname = 'eogp'
       AND proc.oid = 'eogp.expire_space_holds(uuid)'::regprocedure
       AND acl.grantee = 0
       AND acl.privilege_type = 'EXECUTE'
  ) INTO v_public_execute;
  IF v_public_execute
     OR has_function_privilege('eventor_runtime','eogp.expire_space_holds(uuid)','EXECUTE')
     OR has_function_privilege('eventor_auth','eogp.expire_space_holds(uuid)','EXECUTE')
     OR NOT has_function_privilege('eventor_worker','eogp.expire_space_holds(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'space-hold expiry function privilege boundary is incorrect';
  END IF;

  SELECT EXISTS (
    SELECT 1
      FROM pg_proc AS proc
      JOIN pg_namespace AS ns ON ns.oid = proc.pronamespace
      CROSS JOIN LATERAL aclexplode(
        coalesce(proc.proacl, acldefault('f', proc.proowner))
      ) AS acl
     WHERE ns.nspname = 'eogp'
       AND proc.oid = 'eogp.expire_resource_holds(uuid)'::regprocedure
       AND acl.grantee = 0
       AND acl.privilege_type = 'EXECUTE'
  ) INTO v_public_execute;
  IF v_public_execute
     OR has_function_privilege('eventor_runtime','eogp.expire_resource_holds(uuid)','EXECUTE')
     OR has_function_privilege('eventor_auth','eogp.expire_resource_holds(uuid)','EXECUTE')
     OR NOT has_function_privilege('eventor_worker','eogp.expire_resource_holds(uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'resource-hold expiry function privilege boundary is incorrect';
  END IF;
END;
$test$;

-- A second pool of the same resource type must not let a booking line exceed
-- its aggregate requested quantity across pools.
INSERT INTO eogp.resource_pools
  (id, organization_id, venue_id, resource_type_id, code, name, capacity)
VALUES
  ('41000000-0000-4000-8000-000000000003',
   '11111111-1111-4111-8111-111111111111',
   '10000000-0000-4000-8000-000000000001',
   '40000000-0000-4000-8000-000000000001',
   'CHAIRS-SECOND','Second chair pool',10);

INSERT INTO eogp.booking_resource_lines
  (id, organization_id, draft_revision_id, resource_type_id, line_code,
   label_snapshot, requested_quantity)
VALUES
  ('52000000-0000-4000-8000-000000000003',
   '11111111-1111-4111-8111-111111111111',
   '51000000-0000-4000-8000-000000000001',
   '40000000-0000-4000-8000-000000000001',
   'CHAIR-LINE-IDEMPOTENCY','Chair line for idempotency',4);

DO $test$
BEGIN
  BEGIN
    PERFORM eogp.reserve_pooled_resource(
      '11111111-1111-4111-8111-111111111111',
      '41000000-0000-4000-8000-000000000003',
      '51000000-0000-4000-8000-000000000001',NULL,
      '52000000-0000-4000-8000-000000000001',
      '2027-01-03 10:30+00','2027-01-03 11:00+00',1,
      '2027-01-02 15:00+00','ci-line-over-0001'
    );
    RAISE EXCEPTION 'booking resource line quantity was exceeded across pools';
  EXCEPTION WHEN SQLSTATE '23514' THEN
    NULL;
  END;
END;
$test$;

-- Same idempotency key + same resource payload is idempotent. Changing only
-- the booking_resource_line_id must be rejected, not treated as a replay.
DO $test$
DECLARE
  first_id uuid;
  replay_id uuid;
BEGIN
  first_id := eogp.reserve_pooled_resource(
    '11111111-1111-4111-8111-111111111111',
    '41000000-0000-4000-8000-000000000003',
    '51000000-0000-4000-8000-000000000001',NULL,
    '52000000-0000-4000-8000-000000000003',
    '2027-01-04 10:00+00','2027-01-04 11:00+00',1,
    '2027-01-03 15:00+00','ci-line-idempotency-01'
  );
  replay_id := eogp.reserve_pooled_resource(
    '11111111-1111-4111-8111-111111111111',
    '41000000-0000-4000-8000-000000000003',
    '51000000-0000-4000-8000-000000000001',NULL,
    '52000000-0000-4000-8000-000000000003',
    '2027-01-04 10:00+00','2027-01-04 11:00+00',1,
    '2027-01-03 15:00+00','ci-line-idempotency-01'
  );
  IF first_id IS DISTINCT FROM replay_id THEN
    RAISE EXCEPTION 'identical reservation retry did not return the original id';
  END IF;

  BEGIN
    PERFORM eogp.reserve_pooled_resource(
      '11111111-1111-4111-8111-111111111111',
      '41000000-0000-4000-8000-000000000003',
      '51000000-0000-4000-8000-000000000001',NULL,
      '52000000-0000-4000-8000-000000000001',
      '2027-01-04 10:00+00','2027-01-04 11:00+00',1,
      '2027-01-03 15:00+00','ci-line-idempotency-01'
    );
    RAISE EXCEPTION 'idempotency key accepted a different booking resource line';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;
END;
$test$;

-- Space holds cannot be inserted with an already-expired deadline, and a
-- released hold cannot be revived.
INSERT INTO eogp.venue_space_time_blocks
  (id, organization_id, venue_space_id, booking_draft_revision_id,
   reservation_kind, status, starts_at, ends_at, expires_at, idempotency_key)
VALUES
  ('15000000-0000-4000-8000-000000000001',
   '11111111-1111-4111-8111-111111111111',
   '13000000-0000-4000-8000-000000000001',
   '51000000-0000-4000-8000-000000000001',
   'draft_hold','held','2027-01-05 10:00+00','2027-01-05 11:00+00',
   clock_timestamp() + interval '1 day','ci-space-hold-live-01');

UPDATE eogp.venue_space_time_blocks
   SET status='released', updated_at=clock_timestamp()
 WHERE id='15000000-0000-4000-8000-000000000001';

DO $test$
BEGIN
  BEGIN
    UPDATE eogp.venue_space_time_blocks
       SET status='held', expires_at=clock_timestamp() + interval '1 day'
     WHERE id='15000000-0000-4000-8000-000000000001';
    RAISE EXCEPTION 'released space hold was revived';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;

  BEGIN
    INSERT INTO eogp.venue_space_time_blocks
      (organization_id, venue_space_id, booking_draft_revision_id,
       reservation_kind, status, starts_at, ends_at, expires_at, idempotency_key)
    VALUES
      ('11111111-1111-4111-8111-111111111111',
       '13000000-0000-4000-8000-000000000001',
       '51000000-0000-4000-8000-000000000001',
       'draft_hold','held','2027-01-06 10:00+00','2027-01-06 11:00+00',
       clock_timestamp() - interval '1 hour','ci-space-hold-expired-01');
    RAISE EXCEPTION 'already-expired space hold was inserted as active';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;
END;
$test$;

COMMIT;
