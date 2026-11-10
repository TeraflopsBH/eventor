\set ON_ERROR_STOP on

-- PostgreSQL integration smoke tests. Run as eventor_runtime after all migrations.
-- The test uses isolated synthetic tenants and deterministic IDs only.

BEGIN;
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000a', true);
INSERT INTO eogp.organizations (id, slug, name)
VALUES ('10000000-0000-0000-0000-00000000000a', 'ci-tenant-a', 'CI Tenant A');

INSERT INTO eogp.users (id, email, display_name)
VALUES ('20000000-0000-0000-0000-00000000000a', 'ci-a@example.invalid', 'CI A');

INSERT INTO eogp.organization_memberships (id, organization_id, user_id, status, joined_at)
VALUES ('30000000-0000-0000-0000-00000000000a',
        '10000000-0000-0000-0000-00000000000a',
        '20000000-0000-0000-0000-00000000000a', 'active', clock_timestamp());

INSERT INTO eogp.venues (id, organization_id, code, name)
VALUES ('40000000-0000-0000-0000-00000000000a',
        '10000000-0000-0000-0000-00000000000a', 'CI-VENUE-A', 'CI Venue A');

INSERT INTO eogp.venue_buildings (id, organization_id, venue_id, code, name)
VALUES
 ('50000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-00000000000a','40000000-0000-0000-0000-00000000000a','BLD-A1','Building A1'),
 ('50000000-0000-0000-0000-00000000000b','10000000-0000-0000-0000-00000000000a','40000000-0000-0000-0000-00000000000a','BLD-A2','Building A2');

INSERT INTO eogp.venue_levels (id, organization_id, building_id, code, name)
VALUES
 ('60000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-00000000000a','50000000-0000-0000-0000-00000000000a','L1','Level 1'),
 ('60000000-0000-0000-0000-00000000000b','10000000-0000-0000-0000-00000000000a','50000000-0000-0000-0000-00000000000b','L1','Level 1');

INSERT INTO eogp.venue_spaces (id, organization_id, venue_id, building_id, level_id, code, name, space_kind, capacity)
VALUES ('70000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-00000000000a',
        '40000000-0000-0000-0000-00000000000a','50000000-0000-0000-0000-00000000000a',
        '60000000-0000-0000-0000-00000000000a','ROOM-A','Room A','room',100);

-- A level must belong to the selected building.
DO $test$
BEGIN
  BEGIN
    INSERT INTO eogp.venue_spaces (organization_id, venue_id, building_id, level_id, code, name)
    VALUES ('10000000-0000-0000-0000-00000000000a',
            '40000000-0000-0000-0000-00000000000a',
            '50000000-0000-0000-0000-00000000000a',
            '60000000-0000-0000-0000-00000000000b',
            'BAD-LEVEL','Bad level');
    RAISE EXCEPTION 'expected cross-building level FK rejection';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;
  BEGIN
    INSERT INTO eogp.venue_spaces (organization_id, venue_id, building_id, level_id, code, name)
    VALUES ('10000000-0000-0000-0000-00000000000a',
            '40000000-0000-0000-0000-00000000000a',
            NULL, '60000000-0000-0000-0000-00000000000a',
            'BAD-NOBUILDING','Bad no building');
    RAISE EXCEPTION 'expected level-without-building check rejection';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
END;
$test$;

-- An overlapping maintenance block must fail; adjacent half-open blocks must succeed.
INSERT INTO eogp.maintenance_windows (id, organization_id, venue_space_id, starts_at, ends_at, reason_code)
VALUES
 ('80000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-00000000000a','70000000-0000-0000-0000-00000000000a','2031-01-01 10:00:00+00','2031-01-01 11:00:00+00','ci_test'),
 ('80000000-0000-0000-0000-00000000000b','10000000-0000-0000-0000-00000000000a','70000000-0000-0000-0000-00000000000a','2031-01-01 11:00:00+00','2031-01-01 12:00:00+00','ci_test'),
 ('80000000-0000-0000-0000-00000000000c','10000000-0000-0000-0000-00000000000a','70000000-0000-0000-0000-00000000000a','2031-01-01 10:30:00+00','2031-01-01 10:45:00+00','ci_test');

INSERT INTO eogp.venue_space_time_blocks
 (organization_id, venue_space_id, maintenance_window_id, reservation_kind, status, starts_at, ends_at, idempotency_key)
VALUES
 ('10000000-0000-0000-0000-00000000000a','70000000-0000-0000-0000-00000000000a','80000000-0000-0000-0000-00000000000a',
  'maintenance','blocked','2031-01-01 10:00:00+00','2031-01-01 11:00:00+00','ci-space-a');
INSERT INTO eogp.venue_space_time_blocks
 (organization_id, venue_space_id, maintenance_window_id, reservation_kind, status, starts_at, ends_at, idempotency_key)
VALUES
 ('10000000-0000-0000-0000-00000000000a','70000000-0000-0000-0000-00000000000a','80000000-0000-0000-0000-00000000000b',
  'maintenance','blocked','2031-01-01 11:00:00+00','2031-01-01 12:00:00+00','ci-space-b');

DO $test$
BEGIN
  BEGIN
    INSERT INTO eogp.venue_space_time_blocks
     (organization_id, venue_space_id, maintenance_window_id, reservation_kind, status, starts_at, ends_at, idempotency_key)
    VALUES
     ('10000000-0000-0000-0000-00000000000a','70000000-0000-0000-0000-00000000000a','80000000-0000-0000-0000-00000000000c',
      'maintenance','blocked','2031-01-01 10:30:00+00','2031-01-01 10:45:00+00','ci-space-overlap');
    RAISE EXCEPTION 'expected overlapping space reservation exclusion rejection';
  EXCEPTION WHEN exclusion_violation THEN
    NULL;
  END;
END;
$test$;

-- Create the booking draft revision and pooled resource inventory used below.
INSERT INTO eogp.resource_types (id, organization_id, code, name)
VALUES ('90000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-00000000000a','CHAIR','Chair');

INSERT INTO eogp.resource_pools (id, organization_id, venue_id, resource_type_id, code, name, capacity)
VALUES ('a0000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-00000000000a',
        '40000000-0000-0000-0000-00000000000a','90000000-0000-0000-0000-00000000000a','CHAIR-POOL','Chair pool',4);
INSERT INTO eogp.resource_pools (id, organization_id, venue_id, resource_type_id, code, name, capacity)
VALUES ('a0000000-0000-0000-0000-00000000000b','10000000-0000-0000-0000-00000000000a',
        '40000000-0000-0000-0000-00000000000a','90000000-0000-0000-0000-00000000000a','CONCURRENCY-POOL','Concurrency pool',1);

INSERT INTO eogp.booking_drafts (id, organization_id, created_by_membership_id)
VALUES ('b0000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-00000000000a','30000000-0000-0000-0000-00000000000a');

INSERT INTO eogp.booking_draft_revisions (id, organization_id, draft_id, revision_number, values_snapshot, created_by_membership_id)
VALUES ('c0000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-00000000000a',
        'b0000000-0000-0000-0000-00000000000a',1,'{}'::jsonb,'30000000-0000-0000-0000-00000000000a');

-- The first hold is idempotent; an adjacent hold is allowed; peak simultaneous
-- quantity above capacity is rejected.
DO $test$
DECLARE
  first_id uuid;
  replay_id uuid;
  adjacent_id uuid;
BEGIN
  first_id := eogp.reserve_pooled_resource(
    '10000000-0000-0000-0000-00000000000a','a0000000-0000-0000-0000-00000000000a',
    'c0000000-0000-0000-0000-00000000000a',NULL,NULL,
    '2031-02-01 10:00:00+00','2031-02-01 11:00:00+00',3,
    clock_timestamp() + interval '2 hours','ci-pool-hold-0001');
  replay_id := eogp.reserve_pooled_resource(
    '10000000-0000-0000-0000-00000000000a','a0000000-0000-0000-0000-00000000000a',
    'c0000000-0000-0000-0000-00000000000a',NULL,NULL,
    '2031-02-01 10:00:00+00','2031-02-01 11:00:00+00',3,
    (SELECT expires_at FROM eogp.resource_reservations WHERE id = first_id),
    'ci-pool-hold-0001');
  IF first_id <> replay_id THEN
    RAISE EXCEPTION 'idempotent reservation replay returned a different reservation';
  END IF;

  adjacent_id := eogp.reserve_pooled_resource(
    '10000000-0000-0000-0000-00000000000a','a0000000-0000-0000-0000-00000000000a',
    'c0000000-0000-0000-0000-00000000000a',NULL,NULL,
    '2031-02-01 11:00:00+00','2031-02-01 12:00:00+00',3,
    clock_timestamp() + interval '2 hours','ci-pool-hold-0002');

  BEGIN
    PERFORM eogp.reserve_pooled_resource(
      '10000000-0000-0000-0000-00000000000a','a0000000-0000-0000-0000-00000000000a',
      'c0000000-0000-0000-0000-00000000000a',NULL,NULL,
      '2031-02-01 10:30:00+00','2031-02-01 10:45:00+00',2,
      clock_timestamp() + interval '2 hours','ci-pool-overbook-0003');
    RAISE EXCEPTION 'expected pooled resource capacity rejection';
  EXCEPTION WHEN exclusion_violation THEN
    NULL;
  END;
END;
$test$;

COMMIT;

-- Create tenant B, then switch back to tenant A and assert the RLS projection.
BEGIN;
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000b', true);
INSERT INTO eogp.organizations (id, slug, name)
VALUES ('10000000-0000-0000-0000-00000000000b', 'ci-tenant-b', 'CI Tenant B');
INSERT INTO eogp.users (id, email, display_name)
VALUES ('20000000-0000-0000-0000-00000000000b', 'ci-b@example.invalid', 'CI B');
INSERT INTO eogp.organization_memberships (id, organization_id, user_id, status, joined_at)
VALUES ('30000000-0000-0000-0000-00000000000b',
        '10000000-0000-0000-0000-00000000000b',
        '20000000-0000-0000-0000-00000000000b', 'active', clock_timestamp());
INSERT INTO eogp.venues (id, organization_id, code, name)
VALUES ('40000000-0000-0000-0000-00000000000b',
        '10000000-0000-0000-0000-00000000000b', 'CI-VENUE-B', 'CI Venue B');
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000a', true);

DO $test$
DECLARE
  visible_orgs integer;
  visible_venues integer;
BEGIN
  SELECT count(*) INTO visible_orgs FROM eogp.organizations;
  SELECT count(*) INTO visible_venues FROM eogp.venues;
  IF visible_orgs <> 1 OR visible_venues <> 1 THEN
    RAISE EXCEPTION 'tenant RLS failed: visible orgs %, venues %', visible_orgs, visible_venues;
  END IF;
  BEGIN
    INSERT INTO eogp.venue_buildings (organization_id, venue_id, code, name)
    VALUES ('10000000-0000-0000-0000-00000000000a',
            '40000000-0000-0000-0000-00000000000b',
            'CROSS-TENANT','Should fail');
    RAISE EXCEPTION 'expected cross-tenant venue FK rejection';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;
END;
$test$;
COMMIT;

\echo 'PostgreSQL migration smoke tests passed.'
