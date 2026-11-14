\set ON_ERROR_STOP on

-- Owner-level fixture and constraint smoke tests. RLS assertions run separately as eventor_runtime.
-- The test uses isolated synthetic tenants and deterministic IDs only.

BEGIN;
SET LOCAL ROLE eventor_owner;
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

-- Once published, a catalogue revision and its option associations are frozen.
UPDATE eogp.config_catalogue_revisions
   SET state = 'published', published_at = clock_timestamp()
 WHERE organization_id = '10000000-0000-0000-0000-00000000000a'
   AND id = '32000000-0000-4000-8000-00000000000a';

DO $test$
BEGIN
  BEGIN
    UPDATE eogp.config_catalogue_revisions
       SET state = 'retired'
     WHERE organization_id = '10000000-0000-0000-0000-00000000000a'
       AND id = '32000000-0000-4000-8000-00000000000a';
    RAISE EXCEPTION 'expected published catalogue revision immutability rejection';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
  BEGIN
    INSERT INTO eogp.config_catalogue_revision_options
     (organization_id, catalogue_id, catalogue_revision_id, option_id, option_revision_id)
    VALUES
     ('10000000-0000-0000-0000-00000000000a',
      '31000000-0000-4000-8000-00000000000a',
      '32000000-0000-4000-8000-00000000000a',
      '33000000-0000-4000-8000-00000000000b',
      '34000000-0000-4000-8000-00000000000b');
    RAISE EXCEPTION 'expected published catalogue membership immutability rejection';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
  BEGIN
    UPDATE eogp.config_catalogue_option_revisions
       SET label = 'Tampered published label'
     WHERE organization_id = '10000000-0000-0000-0000-00000000000a'
       AND id = '34000000-0000-4000-8000-00000000000a';
    RAISE EXCEPTION 'expected published catalogue option revision immutability rejection';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
END;
$test$;

DO $test$
DECLARE
  v_denied boolean := false;
BEGIN
  BEGIN
    PERFORM eogp.create_booking_form(
      '10000000-0000-0000-0000-00000000000a',
      '30000000-0000-0000-0000-00000000000a',
      'CI-BOOKING-FORM',
      'CI Booking Form',
      'bs-BA',
      '{"fields":[{"code":"category","type":"text","label":"Category","required":false}]}'::jsonb
    );
  EXCEPTION WHEN insufficient_privilege THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'booking form creation without booking.manage permission unexpectedly succeeded';
  END IF;
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

DO $test$
BEGIN
  BEGIN
    UPDATE eogp.booking_offer_revisions
       SET terms_snapshot = '{"tampered":true}'::jsonb
     WHERE organization_id = '10000000-0000-0000-0000-00000000000a'
       AND id = 'e0000000-0000-0000-0000-00000000000a';
    RAISE EXCEPTION 'expected issued offer terms immutability rejection';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
  BEGIN
    UPDATE eogp.booking_draft_revisions
       SET values_snapshot = '{"tampered":true}'::jsonb
     WHERE organization_id = '10000000-0000-0000-0000-00000000000a'
       AND id = 'c0000000-0000-0000-0000-00000000000a';
    RAISE EXCEPTION 'expected append-only booking draft revision rejection';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
END;
$test$;

INSERT INTO eogp.booking_records (id, organization_id, booking_code, source_offer_revision_id)
VALUES ('f0000000-0000-0000-0000-00000000000a','10000000-0000-0000-0000-00000000000a',
        'CI-EXTERNAL-CANCEL','e0000000-0000-0000-0000-00000000000a');

-- The confirmed booking snapshot is the immutable source of the cancellation
-- policy that governs later cancellation effects (NULL means no policy applied).
INSERT INTO eogp.booking_confirmed_snapshots
 (organization_id, booking_id, offer_revision_id, cancellation_policy_revision_id,
  customer_terms_snapshot, price_snapshot, confirmed_by_membership_id, snapshot_sha256)
VALUES
 ('10000000-0000-0000-0000-00000000000a',
  'f0000000-0000-0000-0000-00000000000a',
  'e0000000-0000-0000-0000-00000000000a',
  NULL,
  '{}'::jsonb, '{}'::jsonb,
  '30000000-0000-0000-0000-00000000000a',
  repeat('f',64));

-- A different policy revision exists in the same tenant but is not pinned to
-- this booking. Cancellation effects must not silently substitute it.
INSERT INTO eogp.cancellation_policies (id, organization_id, code, name)
VALUES
 ('a4000000-0000-0000-0000-00000000000a',
  '10000000-0000-0000-0000-00000000000a','CI-OTHER-POLICY','CI Other Policy');

INSERT INTO eogp.cancellation_policy_revisions
 (id, organization_id, cancellation_policy_id, revision_number, customer_mode,
  approval_rules, commercial_rules, notice_rules, public_terms, state, published_at)
VALUES
 ('a5000000-0000-0000-0000-00000000000a',
  '10000000-0000-0000-0000-00000000000a',
  'a4000000-0000-0000-0000-00000000000a',
  1,'approval_required','{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
  'CI policy terms','published',clock_timestamp());

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

DO $test$
BEGIN
  BEGIN
    INSERT INTO eogp.booking_cancellation_effects
      (organization_id, booking_id, cancellation_request_id, policy_revision_id,
       commercial_consequence_snapshot, executed_by_membership_id,
       executed_by_external_capability_id, executed_by_kind)
    VALUES
      ('10000000-0000-0000-0000-00000000000a',
       'f0000000-0000-0000-0000-00000000000a',
       'a3000000-0000-0000-0000-00000000000a',
       'a5000000-0000-0000-0000-00000000000a',
       '{}'::jsonb, NULL,
       'a2000000-0000-0000-0000-00000000000a','external_capability');
    RAISE EXCEPTION 'cancellation effect accepted an unpinned policy revision';
  EXCEPTION WHEN SQLSTATE '23514' THEN
    NULL;
  END;
END;
$test$;

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