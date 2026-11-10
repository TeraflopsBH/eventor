\set ON_ERROR_STOP on

-- PostgreSQL integration smoke tests. Run as eventor_runtime after all migrations.
-- The test uses isolated synthetic tenants and deterministic IDs only.

BEGIN;
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000a', true);
INSERT INTO eogp.organizations (id, slug, name)
VALUES ('10000000-0000-0000-0000-00000000000a', 'ci-tenant-a', 'CI Tenant A');

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

-- Version-pinned catalogue membership must pair each option with its own revision.
INSERT INTO eogp.config_catalogues (id, organization_id, scope_kind, code, name)
VALUES
 ('31000000-0000-4000-8000-00000000000a','10000000-0000-0000-0000-00000000000a','organization','CI-CATALOGUE-A','CI Catalogue A'),
 ('31000000-0000-4000-8000-00000000000b','10000000-0000-0000-0000-00000000000a','organization','CI-CATALOGUE-B','CI Catalogue B');
INSERT INTO eogp.config_catalogue_revisions (id, organization_id, catalogue_id, revision_number)
VALUES
 ('32000000-0000-4000-8000-00000000000a','10000000-0000-0000-0000-00000000000a','31000000-0000-4000-8000-00000000000a',1);
INSERT INTO eogp.config_catalogue_options (id, organization_id, catalogue_id, stable_code)
VALUES
 ('33000000-0000-4000-8000-00000000000a','10000000-0000-0000-0000-00000000000a','31000000-0000-4000-8000-00000000000a','OPTION-A1'),
 ('33000000-0000-4000-8000-00000000000b','10000000-0000-0000-0000-00000000000a','31000000-0000-4000-8000-00000000000a','OPTION-A2'),
 ('33000000-0000-4000-8000-00000000000c','10000000-0000-0000-0000-00000000000a','31000000-0000-4000-8000-00000000000b','OPTION-B1');
INSERT INTO eogp.config_catalogue_option_revisions
 (id, organization_id, catalogue_id, option_id, revision_number, label, value, state)
VALUES
 ('34000000-0000-4000-8000-00000000000a','10000000-0000-0000-0000-00000000000a','31000000-0000-4000-8000-00000000000a','33000000-0000-4000-8000-00000000000a',1,'Option A1','"a1"'::jsonb,'published'),
 ('34000000-0000-4000-8000-00000000000b','10000000-0000-0000-0000-00000000000a','31000000-0000-4000-8000-00000000000a','33000000-0000-4000-8000-00000000000b',1,'Option A2','"a2"'::jsonb,'published'),
 ('34000000-0000-4000-8000-00000000000c','10000000-0000-0000-0000-00000000000a','31000000-0000-4000-8000-00000000000b','33000000-0000-4000-8000-00000000000c',1,'Option B1','"b1"'::jsonb,'published');
INSERT INTO eogp.config_catalogue_revision_options
 (organization_id, catalogue_id, catalogue_revision_id, option_id, option_revision_id)
VALUES
 ('10000000-0000-0000-0000-00000000000a','31000000-0000-4000-8000-00000000000a','32000000-0000-4000-8000-00000000000a','33000000-0000-4000-8000-00000000000a','34000000-0000-4000-8000-00000000000a');

DO $test$
BEGIN
  BEGIN
    INSERT INTO eogp.config_catalogue_revision_options
     (organization_id, catalogue_id, catalogue_revision_id, option_id, option_revision_id)
    VALUES
     ('10000000-0000-0000-0000-00000000000a','31000000-0000-4000-8000-00000000000a','32000000-0000-4000-8000-00000000000a','33000000-0000-4000-8000-00000000000b','34000000-0000-4000-8000-00000000000a');
    RAISE EXCEPTION 'expected option/revision identity mismatch rejection';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;
  BEGIN
    INSERT INTO eogp.config_catalogue_revision_options
     (organization_id, catalogue_id, catalogue_revision_id, option_id, option_revision_id)
    VALUES
     ('10000000-0000-0000-0000-00000000000a','31000000-0000-4000-8000-00000000000a','32000000-0000-4000-8000-00000000000a','33000000-0000-4000-8000-00000000000c','34000000-0000-4000-8000-00000000000c');
    RAISE EXCEPTION 'expected cross-catalogue option rejection';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;
END;
$test$;

-- Person merge targets are valid within the same tenant.
INSERT INTO eogp.persons (id, organization_id, first_name, last_name, created_by_membership_id)
VALUES
 ('51000000-0000-4000-8000-00000000000a','10000000-0000-0000-0000-00000000000a','Merge','Target','30000000-0000-0000-0000-00000000000a'),
 ('51000000-0000-4000-8000-00000000000b','10000000-0000-0000-0000-00000000000a','Merge','Source','30000000-0000-0000-0000-00000000000a');
UPDATE eogp.persons
   SET status = 'merged', merged_into_person_id = '51000000-0000-4000-8000-00000000000a'
 WHERE organization_id = '10000000-0000-0000-0000-00000000000a'
   AND id = '51000000-0000-4000-8000-00000000000b';

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

-- External self-service cancellation must preserve the external capability actor,
-- rather than attributing the business transition to an invented staff user.
INSERT INTO eogp.booking_offers (id, organization_id, draft_id, status)
VALUES ('d0000000-0000-0000-0000-00000000000a',
        '10000000-0000-0000-0000-00000000000a',
        'b0000000-0000-0000-0000-00000000000a','accepted');

INSERT INTO eogp.booking_offer_revisions
 (id, organization_id, offer_id, revision_number, draft_revision_id, terms_snapshot, currency, subtotal, tax_amount, total_amount, state, issued_at, accepted_at)
VALUES
 ('e0000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-00000000000a',
  'd0000000-0000-0000-0000-00000000000a',1,'c0000000-0000-0000-0000-00000000000a',
  '{}'::jsonb,'BAM',0,0,0,'accepted',clock_timestamp(),clock_timestamp());

INSERT INTO eogp.booking_records (id, organization_id, booking_code, source_offer_revision_id)
VALUES ('f0000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-00000000000a',
        'CI-EXTERNAL-CANCEL','e0000000-0000-0000-0000-00000000000a');

INSERT INTO eogp.booking_party_contacts
 (id, organization_id, booking_id, party_role, display_name_ciphertext, email_hash, email_ciphertext, authorized_actions)
VALUES
 ('a1000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-00000000000a',
  'f0000000-0000-0000-0000-00000000000a','authorized_booking_contact',
  decode('010203','hex'),repeat('b',64),decode('aabbcc','hex'),
  ARRAY['booking.cancellation.request']);

INSERT INTO eogp.external_action_capabilities
 (id, organization_id, booking_id, booking_contact_id, action_code, token_sha256, expires_at, created_by_membership_id)
VALUES
 ('a2000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-00000000000a',
  'f0000000-0000-0000-0000-00000000000a','a1000000-0000-0000-0000-00000000000a',
  'booking_cancellation_request',repeat('c',64),clock_timestamp()+interval '1 day',
  '30000000-0000-0000-0000-00000000000a');

INSERT INTO eogp.booking_cancellation_requests
 (id, organization_id, booking_id, requester_kind, requester_contact_id, external_capability_id,
  reason_code, status, resolved_at)
VALUES
 ('a3000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-00000000000a',
  'f0000000-0000-0000-0000-00000000000a','external_contact',
  'a1000000-0000-0000-0000-00000000000a','a2000000-0000-0000-0000-00000000000a',
  'customer_withdrawal','effective',clock_timestamp());

UPDATE eogp.booking_records
   SET status = 'cancelled', cancelled_at = clock_timestamp(), revision_number = revision_number + 1
 WHERE organization_id = '10000000-0000-0000-0000-00000000000a'
   AND id = 'f0000000-0000-0000-0000-00000000000a';

INSERT INTO eogp.booking_cancellation_effects
 (organization_id, booking_id, cancellation_request_id, commercial_consequence_snapshot,
  executed_by_membership_id, executed_by_external_capability_id, executed_by_kind)
VALUES
 ('10000000-0000-0000-0000-00000000000a','f0000000-0000-0000-0000-00000000000a',
  'a3000000-0000-0000-0000-00000000000a','{}'::jsonb,
  NULL,'a2000000-0000-0000-0000-00000000000a','external_capability');

INSERT INTO eogp.booking_status_history
 (organization_id, booking_id, previous_status, new_status, actor_membership_id,
  actor_external_capability_id, actor_kind, reason_code)
VALUES
 ('10000000-0000-0000-0000-00000000000a','f0000000-0000-0000-0000-00000000000a',
  'confirmed','cancelled',NULL,'a2000000-0000-0000-0000-00000000000a',
  'external_capability','customer_withdrawal');

DO $test$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM eogp.booking_cancellation_effects
     WHERE organization_id = '10000000-0000-0000-0000-00000000000a'
       AND booking_id = 'f0000000-0000-0000-0000-00000000000a'
       AND executed_by_kind = 'external_capability'
       AND executed_by_external_capability_id = 'a2000000-0000-0000-0000-00000000000a'
       AND executed_by_membership_id IS NULL
  ) THEN
    RAISE EXCEPTION 'external cancellation actor attribution was not persisted';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM eogp.booking_status_history
     WHERE organization_id = '10000000-0000-0000-0000-00000000000a'
       AND booking_id = 'f0000000-0000-0000-0000-00000000000a'
       AND actor_kind = 'external_capability'
       AND actor_external_capability_id = 'a2000000-0000-0000-0000-00000000000a'
       AND actor_membership_id IS NULL
  ) THEN
    RAISE EXCEPTION 'external status-change actor attribution was not persisted';
  END IF;
END;
$test$;


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
INSERT INTO eogp.organization_memberships (id, organization_id, user_id, status, joined_at)
VALUES ('30000000-0000-0000-0000-00000000000b',
        '10000000-0000-0000-0000-00000000000b',
        '20000000-0000-0000-0000-00000000000b', 'active', clock_timestamp());
INSERT INTO eogp.venues (id, organization_id, code, name)
VALUES ('40000000-0000-0000-0000-00000000000b',
        '10000000-0000-0000-0000-00000000000b', 'CI-VENUE-B', 'CI Venue B');
INSERT INTO eogp.persons (id, organization_id, first_name, last_name, created_by_membership_id)
VALUES ('52000000-0000-4000-8000-00000000000b','10000000-0000-0000-0000-00000000000b',
        'Tenant B','Person','30000000-0000-0000-0000-00000000000b');
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000a', true);

DO $test$
DECLARE
  visible_orgs integer;
  visible_venues integer;
  visible_profiles integer;
BEGIN
  SELECT count(*) INTO visible_orgs FROM eogp.organizations;
  SELECT count(*) INTO visible_venues FROM eogp.venues;
  SELECT count(*) INTO visible_profiles FROM eogp.organization_member_profiles;
  IF visible_orgs <> 1 OR visible_venues <> 1 OR visible_profiles <> 1 THEN
    RAISE EXCEPTION 'tenant RLS/profile view failed: orgs %, venues %, profiles %', visible_orgs, visible_venues, visible_profiles;
  END IF;
  IF has_table_privilege(current_user, 'eogp.users', 'SELECT')
     OR has_column_privilege(current_user, 'eogp.users', 'password_hash', 'SELECT')
     OR has_table_privilege(current_user, 'eogp.users', 'INSERT') THEN
    RAISE EXCEPTION 'general runtime role has direct access to global user identities';
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
  BEGIN
    INSERT INTO eogp.persons
      (id, organization_id, first_name, last_name, merged_into_person_id, status, created_by_membership_id)
    VALUES
      ('52000000-0000-4000-8000-00000000000a','10000000-0000-0000-0000-00000000000a',
       'Cross','Tenant target','52000000-0000-4000-8000-00000000000b','merged',
       '30000000-0000-0000-0000-00000000000a');
    RAISE EXCEPTION 'expected cross-tenant person merge target rejection';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;
  BEGIN
    INSERT INTO eogp.persons
      (id, organization_id, first_name, last_name, created_by_membership_id)
    VALUES
      ('53000000-0000-4000-8000-00000000000a','10000000-0000-0000-0000-00000000000a',
       'Wrong','Membership','30000000-0000-0000-0000-00000000000b');
    RAISE EXCEPTION 'expected cross-tenant creator membership rejection';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;
END;
$test$;
COMMIT;

-- Create an unrelated tenant that must not see the A-to-B collaboration grant.
BEGIN;
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000c', true);
INSERT INTO eogp.organizations (id, slug, name)
VALUES ('10000000-0000-0000-0000-00000000000c', 'ci-tenant-c', 'CI Tenant C');
INSERT INTO eogp.organization_memberships (id, organization_id, user_id, status, joined_at)
VALUES ('30000000-0000-0000-0000-00000000000c',
        '10000000-0000-0000-0000-00000000000c',
        '20000000-0000-0000-0000-00000000000c', 'active', clock_timestamp());
COMMIT;

-- Provider A proposes a venue-scoped grant to organizer B.
BEGIN;
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000a', true);
SELECT eogp.propose_collaboration_grant(
  '61000000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000b',
  'venue',
  '40000000-0000-0000-0000-00000000000a',
  NULL,
  NULL,
  'CI venue snapshot collaboration',
  '{"venueSummary":true}'::jsonb,
  ARRAY['venue.snapshot.use','venue.snapshot.read']::text[],
  clock_timestamp() - interval '1 minute',
  clock_timestamp() + interval '1 day',
  '30000000-0000-0000-0000-00000000000a'
);
DO $test$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM eogp.collaboration_grants
     WHERE organization_id = '10000000-0000-0000-0000-00000000000a'
       AND id = '61000000-0000-4000-8000-00000000000a'
       AND status = 'proposed'
  ) OR NOT EXISTS (
    SELECT 1 FROM eogp.collaboration_grant_revisions
     WHERE organization_id = '10000000-0000-0000-0000-00000000000a'
       AND grant_id = '61000000-0000-4000-8000-00000000000a'
       AND revision_number = 1
  ) OR NOT EXISTS (
    SELECT 1 FROM eogp.audit_events
     WHERE organization_id = '10000000-0000-0000-0000-00000000000a'
       AND action = 'collaboration.grant.proposed'
       AND aggregate_id = '61000000-0000-4000-8000-00000000000a'
  ) THEN
    RAISE EXCEPTION 'grant proposal must atomically write grant, revision and audit';
  END IF;
END;
$test$;
COMMIT;

-- Only the named grantee tenant can see and accept the proposal, and the actor
-- must be an active membership of that grantee organization.
BEGIN;
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000b', true);
DO $test$
DECLARE
  visible_grants integer;
BEGIN
  SELECT count(*) INTO visible_grants
    FROM eogp.collaboration_grants
   WHERE id = '61000000-0000-4000-8000-00000000000a';
  IF visible_grants <> 1 THEN
    RAISE EXCEPTION 'grantee cannot see the proposed collaboration grant';
  END IF;
  BEGIN
    PERFORM eogp.accept_collaboration_grant(
      '61000000-0000-4000-8000-00000000000a',
      '30000000-0000-0000-0000-00000000000a');
    RAISE EXCEPTION 'expected non-grantee membership rejection';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;
END;
$test$;
SELECT eogp.accept_collaboration_grant(
  '61000000-0000-4000-8000-00000000000a',
  '30000000-0000-0000-0000-00000000000b');
-- Idempotent acceptance by the same actor must not write a second audit event.
SELECT eogp.accept_collaboration_grant(
  '61000000-0000-4000-8000-00000000000a',
  '30000000-0000-0000-0000-00000000000b');
DO $test$
DECLARE
  accepted_audits integer;
BEGIN
  SELECT count(*) INTO accepted_audits
    FROM eogp.audit_events
   WHERE organization_id = '10000000-0000-0000-0000-00000000000b'
     AND action = 'collaboration.grant.accepted'
     AND aggregate_id = '61000000-0000-4000-8000-00000000000a';
  IF accepted_audits <> 1 THEN
    RAISE EXCEPTION 'grant acceptance audit should be emitted exactly once; got %', accepted_audits;
  END IF;
  BEGIN
    PERFORM eogp.revoke_collaboration_grant(
      '61000000-0000-4000-8000-00000000000a',
      '30000000-0000-0000-0000-00000000000b',
      'not authorized by grantor');
    RAISE EXCEPTION 'expected grantee-side grantor revocation rejection';
  EXCEPTION WHEN SQLSTATE 'P0002' THEN
    NULL;
  END;
END;
$test$;
COMMIT;

-- A separate booking-scoped grant may link only the exact booking in its scope.
BEGIN;
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000a', true);
SELECT eogp.propose_collaboration_grant(
  '61000000-0000-4000-8000-00000000000b',
  '10000000-0000-0000-0000-00000000000b',
  'booking',
  NULL,
  NULL,
  'f0000000-0000-0000-0000-00000000000a',
  'CI booking-event link',
  '{"bookingSummary":true}'::jsonb,
  ARRAY['booking.event.link']::text[],
  clock_timestamp() - interval '1 minute',
  clock_timestamp() + interval '1 day',
  '30000000-0000-0000-0000-00000000000a'
);
COMMIT;

BEGIN;
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000b', true);
SELECT eogp.accept_collaboration_grant(
  '61000000-0000-4000-8000-00000000000b',
  '30000000-0000-0000-0000-00000000000b'
);
INSERT INTO eogp.events (id, organization_id, event_code, title, created_by_membership_id)
VALUES
 ('62000000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000b',
  'CI-SHARED-EVENT','CI Shared Event','30000000-0000-0000-0000-00000000000b');
COMMIT;

BEGIN;
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000a', true);
INSERT INTO eogp.venue_space_revisions
 (id, organization_id, venue_space_id, revision_number, geometry, semantic_snapshot, content_sha256, published_at, created_by_membership_id)
VALUES
 ('64000000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000a',
  '70000000-0000-0000-0000-00000000000a',
  1, '{}'::jsonb, '{"label":"CI published revision"}'::jsonb,
  repeat('d',64), clock_timestamp(),
  '30000000-0000-0000-0000-00000000000a');

-- The booking-scoped grant must not authorize a venue plan share.
DO $test$
BEGIN
  BEGIN
    INSERT INTO eogp.venue_snapshot_shares
     (id, organization_id, venue_space_revision_id, event_owner_organization_id,
      event_id, collaboration_grant_id, approved_layers, approved_resources,
      source_content_sha256, expires_at, approved_by_membership_id)
    VALUES
     ('63000000-0000-4000-8000-00000000000b',
      '10000000-0000-0000-0000-00000000000a',
      '64000000-0000-4000-8000-00000000000a',
      '10000000-0000-0000-0000-00000000000b',
      '62000000-0000-4000-8000-00000000000a',
      '61000000-0000-4000-8000-00000000000b',
      '[]'::jsonb, '[]'::jsonb, repeat('d',64),
      clock_timestamp() + interval '23 hours',
      '30000000-0000-0000-0000-00000000000a');
    RAISE EXCEPTION 'booking-scoped grant unexpectedly authorized a venue snapshot share';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;
END;
$test$;

-- The venue-scoped grant authorizes this exact published revision for this event.
INSERT INTO eogp.venue_snapshot_shares
 (id, organization_id, venue_space_revision_id, event_owner_organization_id,
  event_id, collaboration_grant_id, approved_layers, approved_resources,
  source_content_sha256, expires_at, approved_by_membership_id)
VALUES
 ('63000000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000a',
  '64000000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000b',
  '62000000-0000-4000-8000-00000000000a',
  '61000000-0000-4000-8000-00000000000a',
  '[]'::jsonb, '[]'::jsonb, repeat('d',64),
  clock_timestamp() + interval '23 hours',
  '30000000-0000-0000-0000-00000000000a');
COMMIT;

-- Event owner B can copy the approved, still-live share into its own immutable
-- snapshot, but a venue-scope grant cannot be substituted for a booking link.
BEGIN;
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000b', true);
INSERT INTO eogp.event_venue_snapshots
 (id, organization_id, event_id, share_owner_organization_id, snapshot_share_id,
  source_organization_id, source_space_revision_id, source_content_sha256,
  snapshot_content, created_by_membership_id)
VALUES
 ('65000000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000b',
  '62000000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000a',
  '63000000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000a',
  '64000000-0000-4000-8000-00000000000a',
  repeat('d',64), '{"layers":[],"resources":[]}'::jsonb,
  '30000000-0000-0000-0000-00000000000b');

DO $test$
BEGIN
  BEGIN
    INSERT INTO eogp.booking_event_links
     (id, organization_id, booking_owner_organization_id, booking_id,
      event_id, grant_owner_organization_id, collaboration_grant_id,
      created_by_membership_id)
    VALUES
     ('66000000-0000-4000-8000-00000000000b',
      '10000000-0000-0000-0000-00000000000b',
      '10000000-0000-0000-0000-00000000000a',
      'f0000000-0000-0000-0000-00000000000a',
      '62000000-0000-4000-8000-00000000000a',
      '10000000-0000-0000-0000-00000000000a',
      '61000000-0000-4000-8000-00000000000a',
      '30000000-0000-0000-0000-00000000000b');
    RAISE EXCEPTION 'venue-scoped grant unexpectedly authorized a booking-event link';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;
END;
$test$;

INSERT INTO eogp.booking_event_links
 (id, organization_id, booking_owner_organization_id, booking_id,
  event_id, grant_owner_organization_id, collaboration_grant_id,
  created_by_membership_id)
VALUES
 ('66000000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000b',
  '10000000-0000-0000-0000-00000000000a',
  'f0000000-0000-0000-0000-00000000000a',
  '62000000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000a',
  '61000000-0000-4000-8000-00000000000b',
  '30000000-0000-0000-0000-00000000000b');

DO $test$
DECLARE
  link_audits integer;
BEGIN
  SELECT count(*) INTO link_audits
    FROM eogp.audit_events
   WHERE organization_id = '10000000-0000-0000-0000-00000000000b'
     AND action = 'booking.event.linked'
     AND aggregate_id = '66000000-0000-4000-8000-00000000000a'
     AND actor_organization_id = '10000000-0000-0000-0000-00000000000b'
     AND authorization_grant_owner_organization_id = '10000000-0000-0000-0000-00000000000a'
     AND authorization_grant_id = '61000000-0000-4000-8000-00000000000b';
  IF link_audits <> 1 THEN
    RAISE EXCEPTION 'booking-event link creation must be audited with delegated grant provenance; got %', link_audits;
  END IF;

  BEGIN
    UPDATE eogp.booking_event_links
       SET relationship_kind = 'other'
     WHERE organization_id = '10000000-0000-0000-0000-00000000000b'
       AND id = '66000000-0000-4000-8000-00000000000a';
    RAISE EXCEPTION 'expected booking-event link immutable-field update rejection';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
END;
$test$;

INSERT INTO eogp.event_sessions
 (id, organization_id, event_id, code, title, starts_at, ends_at, status)
VALUES
 ('62100000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000b',
  '62000000-0000-4000-8000-00000000000a',
  'CI-SESSION','CI Session','2031-06-01 10:00:00+00',
  '2031-06-01 12:00:00+00','planned');

INSERT INTO eogp.event_session_spaces
 (id, organization_id, event_id, session_id, event_venue_snapshot_id,
  allocation_mode, created_by_membership_id)
VALUES
 ('62200000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000b',
  '62000000-0000-4000-8000-00000000000a',
  '62100000-0000-4000-8000-00000000000a',
  '65000000-0000-4000-8000-00000000000a',
  'zone','30000000-0000-0000-0000-00000000000b');

INSERT INTO eogp.event_venue_snapshot_layers
 (id, organization_id, event_id, snapshot_id, layer_code, layer_snapshot)
VALUES
 ('65100000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000b',
  '62000000-0000-4000-8000-00000000000a',
  '65000000-0000-4000-8000-00000000000a',
  'CI-LAYER','{"kind":"zones"}'::jsonb);

INSERT INTO eogp.event_venue_snapshot_objects
 (id, organization_id, snapshot_id, snapshot_layer_id, object_kind, object_snapshot)
VALUES
 ('65200000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000b',
  '65000000-0000-4000-8000-00000000000a',
  '65100000-0000-4000-8000-00000000000a',
  'zone','{"code":"CI-ZONE"}'::jsonb);

INSERT INTO eogp.event_venue_snapshot_resources
 (id, organization_id, event_id, snapshot_id, source_resource_pool_id, resource_snapshot)
VALUES
 ('65300000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000b',
  '62000000-0000-4000-8000-00000000000a',
  '65000000-0000-4000-8000-00000000000a',
  'a0000000-0000-0000-0000-00000000000a',
  '{"kind":"pool","label":"CI Resource"}'::jsonb);
COMMIT;

-- A third tenant must not see the grant. Grantor A can revoke it; grantee B
-- retains access to the historical grant row but it is no longer active.
BEGIN;
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000c', true);
DO $test$
DECLARE
  visible_grants integer;
BEGIN
  SELECT count(*) INTO visible_grants
    FROM eogp.collaboration_grants
   WHERE id = '61000000-0000-4000-8000-00000000000a';
  IF visible_grants <> 0 THEN
    RAISE EXCEPTION 'unrelated tenant can observe a collaboration grant';
  END IF;
END;
$test$;
COMMIT;

BEGIN;
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000a', true);
SELECT eogp.revoke_collaboration_grant(
  '61000000-0000-4000-8000-00000000000a',
  '30000000-0000-0000-0000-00000000000a',
  'CI grant lifecycle revocation');
SELECT eogp.revoke_collaboration_grant(
  '61000000-0000-4000-8000-00000000000b',
  '30000000-0000-0000-0000-00000000000a',
  'CI booking link grant revocation');
COMMIT;

BEGIN;
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000b', true);
DO $test$
DECLARE
  grant_status text;
BEGIN
  SELECT status INTO grant_status
    FROM eogp.collaboration_grants
   WHERE id = '61000000-0000-4000-8000-00000000000a';
  IF grant_status <> 'revoked' THEN
    RAISE EXCEPTION 'grantee should retain the revoked historical grant, got %', grant_status;
  END IF;
  SELECT status INTO grant_status
    FROM eogp.collaboration_grants
   WHERE id = '61000000-0000-4000-8000-00000000000b';
  IF grant_status <> 'revoked' THEN
    RAISE EXCEPTION 'booking link grant should be revoked, got %', grant_status;
  END IF;

  BEGIN
    INSERT INTO eogp.event_venue_snapshots
     (id, organization_id, event_id, share_owner_organization_id, snapshot_share_id,
      source_organization_id, source_space_revision_id, source_content_sha256,
      snapshot_content, created_by_membership_id)
    VALUES
     ('65000000-0000-4000-8000-00000000000b',
      '10000000-0000-0000-0000-00000000000b',
      '62000000-0000-4000-8000-00000000000a',
      '10000000-0000-0000-0000-00000000000a',
      '63000000-0000-4000-8000-00000000000a',
      '10000000-0000-0000-0000-00000000000a',
      '64000000-0000-4000-8000-00000000000a',
      repeat('d',64), '{"layers":[],"resources":[]}'::jsonb,
      '30000000-0000-0000-0000-00000000000b');
    RAISE EXCEPTION 'revoked collaboration grant unexpectedly permitted a new snapshot';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;

  BEGIN
    INSERT INTO eogp.booking_event_links
     (id, organization_id, booking_owner_organization_id, booking_id,
      event_id, grant_owner_organization_id, collaboration_grant_id,
      created_by_membership_id)
    VALUES
     ('66000000-0000-4000-8000-00000000000c',
      '10000000-0000-0000-0000-00000000000b',
      '10000000-0000-0000-0000-00000000000a',
      'f0000000-0000-0000-0000-00000000000a',
      '62000000-0000-4000-8000-00000000000a',
      '10000000-0000-0000-0000-00000000000a',
      '61000000-0000-4000-8000-00000000000b',
      '30000000-0000-0000-0000-00000000000b');
    RAISE EXCEPTION 'revoked collaboration grant unexpectedly permitted a new booking link';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;

  BEGIN
    INSERT INTO eogp.event_session_spaces
     (id, organization_id, event_id, session_id, event_venue_snapshot_id,
      allocation_mode, created_by_membership_id)
    VALUES
     ('62200000-0000-4000-8000-00000000000b',
      '10000000-0000-0000-0000-00000000000b',
      '62000000-0000-4000-8000-00000000000a',
      '62100000-0000-4000-8000-00000000000a',
      '65000000-0000-4000-8000-00000000000a',
      'zone','30000000-0000-0000-0000-00000000000b');
    RAISE EXCEPTION 'revoked collaboration grant unexpectedly permitted a new session-space binding';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;

  BEGIN
    INSERT INTO eogp.event_venue_snapshot_layers
     (id, organization_id, event_id, snapshot_id, layer_code, layer_snapshot)
    VALUES
     ('65100000-0000-4000-8000-00000000000b',
      '10000000-0000-0000-0000-00000000000b',
      '62000000-0000-4000-8000-00000000000a',
      '65000000-0000-4000-8000-00000000000a',
      'LATE-LAYER','{"kind":"late"}'::jsonb);
    RAISE EXCEPTION 'revoked collaboration grant unexpectedly permitted a new snapshot layer';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;
END;
$test$;
COMMIT;

\echo 'PostgreSQL migration smoke tests passed.'
