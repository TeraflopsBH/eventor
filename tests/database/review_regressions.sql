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

  IF has_table_privilege('eventor_runtime','eogp.venue_space_time_blocks','UPDATE')
     OR has_table_privilege('eventor_runtime','eogp.venue_space_time_blocks','DELETE')
     OR has_table_privilege('eventor_worker','eogp.venue_space_time_blocks','UPDATE')
     OR has_table_privilege('eventor_worker','eogp.venue_space_time_blocks','DELETE') THEN
    RAISE EXCEPTION 'runtime/worker may still mutate or delete space reservation rows directly';
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

-- Individually tracked units and pooled reservations share one capacity
-- invariant. A pool of ten cannot have ten pooled units plus a discrete unit
-- at the same time.
INSERT INTO eogp.resource_units
  (id, organization_id, resource_pool_id, unit_code, status)
VALUES
  ('42000000-0000-4000-8000-000000000003',
   '11111111-1111-4111-8111-111111111111',
   '41000000-0000-4000-8000-000000000003',
   'CI-MIXED-UNIT-01','available');

SELECT eogp.reserve_pooled_resource(
  '11111111-1111-4111-8111-111111111111',
  '41000000-0000-4000-8000-000000000003',
  '51000000-0000-4000-8000-000000000001',NULL,NULL,
  '2027-01-07 10:00+00','2027-01-07 11:00+00',10,
  '2027-01-06 15:00+00','ci-mixed-mode-pool-001'
);

DO $test$
BEGIN
  BEGIN
    PERFORM eogp.reserve_resource_unit(
      '11111111-1111-4111-8111-111111111111',
      '42000000-0000-4000-8000-000000000003',
      '51000000-0000-4000-8000-000000000001',
      NULL,NULL,NULL,
      '2027-01-07 10:00+00','2027-01-07 11:00+00',
      '2027-01-06 15:00+00','ci-mixed-mode-unit-001'
    );
    RAISE EXCEPTION 'mixed pooled/discrete reservations exceeded pool capacity';
  EXCEPTION WHEN exclusion_violation THEN
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


-- Task delegation is explicit at both layers: the event owner grant names
-- the exact task ID, and the performing organization assigns task.perform.
INSERT INTO eogp.events
  (id, organization_id, event_code, title, created_by_membership_id)
VALUES
  ('68000000-0000-4000-8000-000000000001',
   '11111111-1111-4111-8111-111111111111',
   'CI-DELEGATED-TASK','CI Delegated Task Event',
   'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa');

SELECT eogp.propose_collaboration_grant(
  '61000000-0000-4000-8000-000000000099',
  '22222222-2222-4222-8222-222222222222',
  'space',
  NULL,
  '13000000-0000-4000-8000-000000000001',
  NULL,
  'CI delegated task performance',
  '{"taskIds":["67000000-0000-4000-8000-000000000001"]}'::jsonb,
  ARRAY['event.task.perform']::text[],
  clock_timestamp() - interval '1 minute',
  clock_timestamp() + interval '1 day',
  'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa'
);

SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);
SELECT eogp.accept_collaboration_grant(
  '61000000-0000-4000-8000-000000000099',
  'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
);

INSERT INTO eogp.roles
  (id, organization_id, code, name, scope_kind)
VALUES
  ('69000000-0000-4000-8000-000000000001',
   '22222222-2222-4222-8222-222222222222',
   'CI-TASK-PERFORMER','CI Task Performer','organization');

INSERT INTO eogp.role_permissions
  (organization_id, role_id, permission_code)
VALUES
  ('22222222-2222-4222-8222-222222222222',
   '69000000-0000-4000-8000-000000000001',
   'task.perform');

INSERT INTO eogp.user_role_grants
  (id, organization_id, membership_id, role_id, scope_kind,
   granted_by_membership_id)
VALUES
  ('6a000000-0000-4000-8000-000000000001',
   '22222222-2222-4222-8222-222222222222',
   'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
   '69000000-0000-4000-8000-000000000001',
   'organization',
   'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');

SELECT set_config('app.organization_id','11111111-1111-4111-8111-111111111111',true);
INSERT INTO eogp.event_responsibility_assignments (
  id, organization_id, event_id, task_code, task_label,
  accountable_party_kind, performing_party_kind,
  performing_organization_id, performing_membership_id,
  grant_owner_organization_id, collaboration_grant_id,
  permitted_projection, created_by_membership_id
) VALUES (
  '67000000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111',
  '68000000-0000-4000-8000-000000000001',
  'CI-SETUP','Prepare the venue',
  'event_owner','organization',
  '22222222-2222-4222-8222-222222222222',
  'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
  '11111111-1111-4111-8111-111111111111',
  '61000000-0000-4000-8000-000000000099',
  '{"taskStatus":true}'::jsonb,
  'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa'
);


-- A booking-confirmation fixture exercises the secured draft-hold conversion:
-- one pooled reservation, one individually tracked unit and one space hold.
INSERT INTO eogp.booking_offers (id, organization_id, draft_id, status)
VALUES
 ('71000000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111',
  '50000000-0000-4000-8000-000000000001','accepted');

INSERT INTO eogp.booking_offer_revisions
 (id, organization_id, offer_id, revision_number, draft_revision_id,
  terms_snapshot, currency, subtotal, tax_amount, total_amount,
  state, issued_at, accepted_at)
VALUES
 ('72000000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111',
  '71000000-0000-4000-8000-000000000001',1,
  '51000000-0000-4000-8000-000000000001',
  '{}'::jsonb,'BAM',0,0,0,'accepted',
  clock_timestamp() - interval '1 hour',clock_timestamp());

INSERT INTO eogp.booking_records
 (id, organization_id, booking_code, source_offer_revision_id)
VALUES
 ('73000000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111',
  'CI-CONFIRM-RESERVATIONS',
  '72000000-0000-4000-8000-000000000001');

INSERT INTO eogp.booking_confirmed_snapshots
 (organization_id, booking_id, offer_revision_id,
  cancellation_policy_revision_id, customer_terms_snapshot,
  price_snapshot, confirmed_by_membership_id, snapshot_sha256)
VALUES
 ('11111111-1111-4111-8111-111111111111',
  '73000000-0000-4000-8000-000000000001',
  '72000000-0000-4000-8000-000000000001',
  NULL,'{}'::jsonb,'{}'::jsonb,
  'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',repeat('f',64));

INSERT INTO eogp.booking_resource_lines
 (id, organization_id, booking_id, resource_type_id, line_code,
  label_snapshot, requested_quantity, approved_quantity)
VALUES
 ('74000000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111',
  '73000000-0000-4000-8000-000000000001',
  '40000000-0000-4000-8000-000000000001',
  'CHAIR-LINE-IDEMPOTENCY','Confirmed chair line',4,4);

INSERT INTO eogp.resource_units
 (id, organization_id, resource_pool_id, unit_code, status)
VALUES
 ('42000000-0000-4000-8000-000000000004',
  '11111111-1111-4111-8111-111111111111',
  '41000000-0000-4000-8000-000000000003',
  'CI-CONFIRM-UNIT-01','available');

INSERT INTO eogp.resource_reservations
 (id, organization_id, resource_pool_id, booking_draft_revision_id,
  booking_resource_line_id, quantity, starts_at, ends_at, status,
  expires_at, idempotency_key)
VALUES
 ('43000000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111',
  '41000000-0000-4000-8000-000000000003',
  '51000000-0000-4000-8000-000000000001',
  '52000000-0000-4000-8000-000000000003',
  2,'2027-02-02 10:00+00','2027-02-02 11:00+00','held',
  clock_timestamp() + interval '1 day','ci-confirm-pooled-hold-01');

SELECT eogp.reserve_resource_unit(
  '11111111-1111-4111-8111-111111111111',
  '42000000-0000-4000-8000-000000000004',
  '51000000-0000-4000-8000-000000000001',
  NULL,NULL,
  '52000000-0000-4000-8000-000000000003',
  '2027-02-03 10:00+00','2027-02-03 11:00+00',
  clock_timestamp() + interval '1 day','ci-confirm-unit-hold-01');

INSERT INTO eogp.venue_space_time_blocks
 (id, organization_id, venue_space_id, booking_draft_revision_id,
  reservation_kind, status, starts_at, ends_at, expires_at,
  idempotency_key, actor_membership_id)
VALUES
 ('15000000-0000-4000-8000-000000000002',
  '11111111-1111-4111-8111-111111111111',
  '13000000-0000-4000-8000-000000000001',
  '51000000-0000-4000-8000-000000000001',
  'draft_hold','held','2027-02-04 10:00+00','2027-02-04 11:00+00',
  clock_timestamp() + interval '1 day',
  'ci-confirm-space-hold-01',
  'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa');

INSERT INTO eogp.roles
 (id, organization_id, code, name, scope_kind)
VALUES
 ('76000000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111',
  'CI-BOOKING-CONFIRMER','CI Booking Confirmer','organization');

INSERT INTO eogp.role_permissions (organization_id, role_id, permission_code)
VALUES
 ('11111111-1111-4111-8111-111111111111',
  '76000000-0000-4000-8000-000000000001','booking.confirm');

INSERT INTO eogp.user_role_grants
 (id, organization_id, membership_id, role_id, scope_kind,
  granted_by_membership_id)
VALUES
 ('77000000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111',
  'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',
  '76000000-0000-4000-8000-000000000001',
  'organization',
  'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa');

COMMIT;
