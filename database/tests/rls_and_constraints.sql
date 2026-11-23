\set ON_ERROR_STOP on

-- PostgreSQL integration smoke tests. Run as eventor_owner via eventor_migrator SET ROLE.
-- FORCE ROW LEVEL SECURITY remains active; runtime privilege checks target eventor_runtime.
-- The test uses isolated synthetic tenants and deterministic IDs only.

BEGIN;
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000a', true);
INSERT INTO eogp.organizations (id, slug, name)
VALUES ('10000000-0000-0000-0000-00000000000a', 'ci-tenant-a', 'CI Tenant A');

INSERT INTO eogp.organization_memberships (id, organization_id, user_id, status, joined_at)
VALUES ('30000000-0000-0000-0000-00000000000a',
        '10000000-0000-0000-0000-00000000000a',
        '20000000-0000-0000-0000-00000000000a', 'active', clock_timestamp());
INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind)
VALUES ('e8200000-0000-4000-8000-00000000000a','10000000-0000-0000-0000-00000000000a','CI-COLLAB-MANAGER-A','CI Collaboration Manager A','organization');
INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
VALUES
 ('10000000-0000-0000-0000-00000000000a','e8200000-0000-4000-8000-00000000000a','collaboration.manage'),
 ('10000000-0000-0000-0000-00000000000a','e8200000-0000-4000-8000-00000000000a','event.manage');
INSERT INTO eogp.user_role_grants(id,organization_id,membership_id,role_id,scope_kind,granted_by_membership_id)
VALUES ('e8300000-0000-4000-8000-00000000000a','10000000-0000-0000-0000-00000000000a','30000000-0000-0000-0000-00000000000a','e8200000-0000-4000-8000-00000000000a','organization','30000000-0000-0000-0000-00000000000a');

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

INSERT INTO eogp.booking_form_definitions
 (id, organization_id, scope_kind, form_code, name)
VALUES
 ('41000000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000a',
  'organization','CI-BOOKING-FORM','CI Booking Form');

INSERT INTO eogp.booking_form_revisions
 (id, organization_id, form_definition_id, revision_number, locale,
  field_schema, state, published_at)
VALUES
 ('42000000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000a',
  '41000000-0000-4000-8000-00000000000a',
  1,'bs-BA','{"fields":[]}'::jsonb,'published',clock_timestamp());

DO $test$
BEGIN
  BEGIN
    UPDATE eogp.booking_form_revisions
       SET field_schema = '{"fields":[{"code":"tampered"}]}'::jsonb
     WHERE organization_id = '10000000-0000-0000-0000-00000000000a'
       AND id = '42000000-0000-4000-8000-00000000000a';
    RAISE EXCEPTION 'expected published booking form revision immutability rejection';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
  BEGIN
    INSERT INTO eogp.booking_form_catalogue_bindings
     (organization_id, form_revision_id, catalogue_id, catalogue_revision_id, field_code)
    VALUES
     ('10000000-0000-0000-0000-00000000000a',
      '42000000-0000-4000-8000-00000000000a',
      '31000000-0000-4000-8000-00000000000a',
      '32000000-0000-4000-8000-00000000000a',
      'category');
    RAISE EXCEPTION 'expected published booking form binding immutability rejection';
  EXCEPTION WHEN SQLSTATE '55000' THEN
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

-- A second published revision is deliberately not pinned to this booking.
INSERT INTO eogp.cancellation_policy_revisions
 (id, organization_id, cancellation_policy_id, revision_number, customer_mode,
  approval_rules, commercial_rules, notice_rules, public_terms, state, published_at)
VALUES
 ('a6000000-0000-0000-0000-00000000000a',
  '10000000-0000-0000-0000-00000000000a',
  'a4000000-0000-0000-0000-00000000000a',
  2,'approval_required','{}'::jsonb,'{}'::jsonb,'{}'::jsonb,
  'CI later policy terms','published',clock_timestamp());


-- The confirmed booking snapshot is the immutable source of the cancellation
-- policy that governs later cancellation effects (NULL means no policy applied).
INSERT INTO eogp.booking_confirmed_snapshots
 (organization_id, booking_id, offer_revision_id, cancellation_policy_revision_id,
  customer_terms_snapshot, price_snapshot, confirmed_by_membership_id, snapshot_sha256)
VALUES
 ('10000000-0000-0000-0000-00000000000a',
  'f0000000-0000-0000-0000-00000000000a',
  'e0000000-0000-0000-0000-00000000000a',
  'a5000000-0000-0000-0000-00000000000a',
  '{}'::jsonb, '{}'::jsonb,
  '30000000-0000-0000-0000-00000000000a',
  repeat('f',64));

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
 (organization_id, booking_id, cancellation_request_id, policy_revision_id,
  commercial_consequence_snapshot, executed_by_membership_id,
  executed_by_external_capability_id, executed_by_kind)
VALUES
 ('10000000-0000-0000-0000-00000000000a','f0000000-0000-0000-0000-00000000000a',
  'a3000000-0000-0000-0000-00000000000a','a5000000-0000-0000-0000-00000000000a',
  '{}'::jsonb,NULL,'a2000000-0000-0000-0000-00000000000a','external_capability');

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
       'a6000000-0000-0000-0000-00000000000a',
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

-- Create tenant B, then switch back to tenant A and assert the RLS projection.
BEGIN;
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000b', true);
INSERT INTO eogp.organizations (id, slug, name)
VALUES ('10000000-0000-0000-0000-00000000000b', 'ci-tenant-b', 'CI Tenant B');
INSERT INTO eogp.organization_memberships (id, organization_id, user_id, status, joined_at)
VALUES ('30000000-0000-0000-0000-00000000000b',
        '10000000-0000-0000-0000-00000000000b',
        '20000000-0000-0000-0000-00000000000b', 'active', clock_timestamp());
INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind)
VALUES ('e8200000-0000-4000-8000-00000000000b','10000000-0000-0000-0000-00000000000b','CI-COLLAB-MANAGER-B','CI Collaboration Manager B','organization');
INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
VALUES ('10000000-0000-0000-0000-00000000000b','e8200000-0000-4000-8000-00000000000b','collaboration.manage');
INSERT INTO eogp.user_role_grants(id,organization_id,membership_id,role_id,scope_kind,granted_by_membership_id)
VALUES ('e8300000-0000-4000-8000-00000000000b','10000000-0000-0000-0000-00000000000b','30000000-0000-0000-0000-00000000000b','e8200000-0000-4000-8000-00000000000b','organization','30000000-0000-0000-0000-00000000000b');
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
  IF has_table_privilege('eventor_runtime', 'eogp.users', 'SELECT')
     OR has_column_privilege('eventor_runtime', 'eogp.users', 'password_hash', 'SELECT')
     OR has_table_privilege('eventor_runtime', 'eogp.users', 'INSERT') THEN
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
SELECT set_config('app.actor_membership_id', '30000000-0000-0000-0000-00000000000a', true);
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
SELECT set_config('app.actor_membership_id', '30000000-0000-0000-0000-00000000000b', true);
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

-- A distinct read-only venue grant must allow source SELECT without permitting
-- the event owner to bind/copy the provider's plan into an event snapshot.
BEGIN;
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000a', true);
SELECT set_config('app.actor_membership_id', '30000000-0000-0000-0000-00000000000a', true);
SELECT eogp.propose_collaboration_grant(
  '61000000-0000-4000-8000-00000000000c',
  '10000000-0000-0000-0000-00000000000b',
  'venue',
  '40000000-0000-0000-0000-00000000000a',
  NULL,
  NULL,
  'CI read-only venue snapshot grant',
  '{"venueSummary":true}'::jsonb,
  ARRAY['venue.snapshot.read']::text[],
  clock_timestamp() - interval '1 minute',
  clock_timestamp() + interval '1 day',
  '30000000-0000-0000-0000-00000000000a'
);
COMMIT;

BEGIN;
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000b', true);
SELECT set_config('app.actor_membership_id', '30000000-0000-0000-0000-00000000000b', true);
SELECT eogp.accept_collaboration_grant(
  '61000000-0000-4000-8000-00000000000c',
  '30000000-0000-0000-0000-00000000000b'
);
COMMIT;

-- A separate booking-scoped grant may link only the exact booking in its scope.
BEGIN;
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000a', true);
SELECT set_config('app.actor_membership_id', '30000000-0000-0000-0000-00000000000a', true);
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
SELECT set_config('app.actor_membership_id', '30000000-0000-0000-0000-00000000000b', true);
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
  repeat('d',64), NULL,
  '30000000-0000-0000-0000-00000000000a');

-- Draft spatial children can be edited before publication.
INSERT INTO eogp.spatial_layers
 (id, organization_id, venue_space_revision_id, code, label, layer_kind)
VALUES
 ('64100000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000a',
  '64000000-0000-4000-8000-00000000000a',
  'CI-ZONES','CI Zones','zones');

INSERT INTO eogp.spatial_objects
 (id, organization_id, layer_id, object_kind, stable_code, geometry)
VALUES
 ('64200000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000a',
  '64100000-0000-4000-8000-00000000000a',
  'zone','CI-ZONE','{"x":0,"y":0,"width":10,"height":10}'::jsonb);

INSERT INTO eogp.spatial_layers
 (id, organization_id, venue_space_revision_id, code, label, layer_kind)
VALUES
 ('64100000-0000-4000-8000-00000000000b',
  '10000000-0000-0000-0000-00000000000a',
  '64000000-0000-4000-8000-00000000000a',
  'CI-PRIVATE','CI Private Layer','security');

INSERT INTO eogp.spatial_objects
 (id, organization_id, layer_id, object_kind, stable_code, geometry)
VALUES
 ('64200000-0000-4000-8000-00000000000b',
  '10000000-0000-0000-0000-00000000000a',
  '64100000-0000-4000-8000-00000000000b',
  'zone','CI-PRIVATE-ZONE','{"x":50,"y":0,"width":10,"height":10}'::jsonb);

INSERT INTO eogp.spatial_layers
 (id, organization_id, venue_space_revision_id, code, label, layer_kind)
VALUES
 ('64100000-0000-0000-0000-00000000000c',
  '10000000-0000-0000-0000-00000000000a',
  '64000000-0000-4000-8000-00000000000a',
  'CI-ZONES-SECOND','CI Second Zones','zones');

INSERT INTO eogp.spatial_objects
 (id, organization_id, layer_id, object_kind, stable_code, geometry)
VALUES
 ('64200000-0000-4000-8000-00000000000c',
  '10000000-0000-0000-0000-00000000000a',
  '64100000-0000-0000-0000-00000000000c',
  'zone','CI-ZONE-SECOND','{"x":20,"y":0,"width":10,"height":10}'::jsonb);

INSERT INTO eogp.floor_plan_assets
 (id, organization_id, venue_space_revision_id, storage_key, media_type, content_sha256, byte_length)
VALUES
 ('64300000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000a',
  '64000000-0000-4000-8000-00000000000a',
  'ci/test/floorplan.svg','image/svg+xml',repeat('e',64),0);

UPDATE eogp.venue_space_revisions
   SET published_at = clock_timestamp()
 WHERE organization_id = '10000000-0000-0000-0000-00000000000a'
   AND id = '64000000-0000-4000-8000-00000000000a';

DO $test$
BEGIN
  BEGIN
    UPDATE eogp.venue_space_revisions
       SET geometry = '{"tampered":true}'::jsonb
     WHERE organization_id = '10000000-0000-0000-0000-00000000000a'
       AND id = '64000000-0000-4000-8000-00000000000a';
    RAISE EXCEPTION 'expected published venue revision immutability rejection';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
  BEGIN
    INSERT INTO eogp.spatial_layers
     (organization_id, venue_space_revision_id, code, label, layer_kind)
    VALUES
     ('10000000-0000-0000-0000-00000000000a',
      '64000000-0000-4000-8000-00000000000a',
      'LATE','Late Layer','zones');
    RAISE EXCEPTION 'expected published venue revision child insertion rejection';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
  BEGIN
    UPDATE eogp.spatial_objects
       SET geometry = '{"tampered":true}'::jsonb
     WHERE organization_id = '10000000-0000-0000-0000-00000000000a'
       AND id = '64200000-0000-4000-8000-00000000000a';
    RAISE EXCEPTION 'expected published venue spatial object immutability rejection';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
END;
$test$;

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

-- A provider approval cannot name a layer outside the source revision.
DO $test$
BEGIN
  BEGIN
    INSERT INTO eogp.venue_snapshot_shares
     (id, organization_id, venue_space_revision_id, event_owner_organization_id,
      event_id, collaboration_grant_id, approved_layers, approved_resources,
      source_content_sha256, expires_at, approved_by_membership_id)
    VALUES
     ('63000000-0000-4000-8000-00000000000c',
      '10000000-0000-0000-0000-00000000000a',
      '64000000-0000-4000-8000-00000000000a',
      '10000000-0000-0000-0000-00000000000b',
      '62000000-0000-4000-8000-00000000000a',
      '61000000-0000-4000-8000-00000000000a',
      '["64100000-0000-4000-8000-00000000000c"]'::jsonb,
      '[]'::jsonb, repeat('d',64), clock_timestamp() + interval '23 hours',
      '30000000-0000-0000-0000-00000000000a');
    RAISE EXCEPTION 'provider share unexpectedly accepted a layer outside the source revision';
  EXCEPTION WHEN SQLSTATE '22023' THEN
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
  '["64100000-0000-4000-8000-00000000000a","64100000-0000-0000-0000-00000000000c"]'::jsonb,
  '["a0000000-0000-0000-0000-00000000000a"]'::jsonb,
  repeat('d',64),
  clock_timestamp() + interval '23 hours',
  '30000000-0000-0000-0000-00000000000a');
INSERT INTO eogp.venue_space_revisions
 (id, organization_id, venue_space_id, revision_number, geometry, semantic_snapshot,
  content_sha256, published_at, created_by_membership_id)
VALUES
 ('64000000-0000-4000-8000-00000000000b',
  '10000000-0000-0000-0000-00000000000a',
  '70000000-0000-0000-0000-00000000000a',
  2, '{}'::jsonb, '{"label":"CI read-only revision"}'::jsonb,
  repeat('e',64), clock_timestamp(),
  '30000000-0000-0000-0000-00000000000a');

INSERT INTO eogp.venue_snapshot_shares
 (id, organization_id, venue_space_revision_id, event_owner_organization_id,
  event_id, collaboration_grant_id, approved_layers, approved_resources,
  source_content_sha256, expires_at, approved_by_membership_id)
VALUES
 ('63000000-0000-4000-8000-00000000000d',
  '10000000-0000-0000-0000-00000000000a',
  '64000000-0000-4000-8000-00000000000b',
  '10000000-0000-0000-0000-00000000000b',
  '62000000-0000-4000-8000-00000000000a',
  '61000000-0000-4000-8000-00000000000c',
  '[]'::jsonb, '[]'::jsonb, repeat('e',64),
  clock_timestamp() + interval '23 hours',
  '30000000-0000-0000-0000-00000000000a');
COMMIT;

-- Event owner B can copy the approved, still-live share into its own immutable
-- snapshot, but a venue-scope grant cannot be substituted for a booking link.
BEGIN;
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000b', true);

-- The organizer can read only the exact approved source layer/object/resource
-- rows while the share and grant are live, not the provider's full inventory.
DO $test$
DECLARE
  source_revisions integer;
  source_spaces integer;
  source_layers integer;
  source_objects integer;
  source_pools integer;
BEGIN
  SELECT count(*) INTO source_revisions
    FROM eogp.venue_space_revisions
   WHERE organization_id = '10000000-0000-0000-0000-00000000000a';
  SELECT count(*) INTO source_spaces
    FROM eogp.venue_spaces
   WHERE organization_id = '10000000-0000-0000-0000-00000000000a';
  SELECT count(*) INTO source_layers
    FROM eogp.spatial_layers
   WHERE organization_id = '10000000-0000-0000-0000-00000000000a';
  SELECT count(*) INTO source_objects
    FROM eogp.spatial_objects
   WHERE organization_id = '10000000-0000-0000-0000-00000000000a';
  SELECT count(*) INTO source_pools
    FROM eogp.resource_pools
   WHERE organization_id = '10000000-0000-0000-0000-00000000000a';

  IF source_revisions <> 2 OR source_spaces <> 1
     OR source_layers <> 2 OR source_objects <> 2 OR source_pools <> 1 THEN
    RAISE EXCEPTION
      'recipient source projection is too broad or incomplete: revisions %, spaces %, layers %, objects %, pools %',
      source_revisions, source_spaces, source_layers, source_objects, source_pools;
  END IF;
END;
$test$;

DO $test$
DECLARE
  visible_read_only_revision integer;
BEGIN
  SELECT count(*) INTO visible_read_only_revision
    FROM eogp.venue_space_revisions
   WHERE organization_id = '10000000-0000-0000-0000-00000000000a'
     AND id = '64000000-0000-4000-8000-00000000000b';
  IF visible_read_only_revision <> 1 THEN
    RAISE EXCEPTION 'venue.snapshot.read did not expose its approved source revision';
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
      '63000000-0000-4000-8000-00000000000d',
      '10000000-0000-0000-0000-00000000000a',
      '64000000-0000-4000-8000-00000000000b',
      repeat('e',64), '{"layers":[],"resources":[]}'::jsonb,
      '30000000-0000-0000-0000-00000000000b');
    RAISE EXCEPTION 'read-only snapshot grant unexpectedly permitted event snapshot use';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;
END;
$test$;

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
 (id, organization_id, event_id, snapshot_id, source_layer_id, layer_code, layer_snapshot)
VALUES
 ('65100000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000b',
  '62000000-0000-4000-8000-00000000000a',
  '65000000-0000-4000-8000-00000000000a',
  '64100000-0000-4000-8000-00000000000a',
  'CI-LAYER','{"kind":"zones"}'::jsonb);

INSERT INTO eogp.event_venue_snapshot_layers
 (id, organization_id, event_id, snapshot_id, source_layer_id, layer_code, layer_snapshot)
VALUES
 ('65100000-0000-4000-8000-00000000000b',
  '10000000-0000-0000-0000-00000000000b',
  '62000000-0000-4000-8000-00000000000a',
  '65000000-0000-4000-8000-00000000000a',
  '64100000-0000-0000-0000-00000000000c',
  'CI-LAYER-SECOND','{"kind":"zones"}'::jsonb);

INSERT INTO eogp.event_venue_snapshot_objects
 (id, organization_id, snapshot_id, snapshot_layer_id, source_object_id, object_kind, object_snapshot)
VALUES
 ('65200000-0000-4000-8000-00000000000a',
  '10000000-0000-0000-0000-00000000000b',
  '65000000-0000-4000-8000-00000000000a',
  '65100000-0000-4000-8000-00000000000a',
  '64200000-0000-4000-8000-00000000000a',
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

DO $test$
BEGIN
  BEGIN
    INSERT INTO eogp.event_venue_snapshot_objects
     (id, organization_id, snapshot_id, snapshot_layer_id, source_object_id, object_kind, object_snapshot)
    VALUES
     ('65200000-0000-4000-8000-00000000000c',
      '10000000-0000-0000-0000-00000000000b',
      '65000000-0000-4000-8000-00000000000a',
      '65100000-0000-4000-8000-00000000000b',
      '64200000-0000-0000-0000-00000000000a',
      'zone','{"code":"WRONG-LAYER-MAPPING"}'::jsonb);
    RAISE EXCEPTION 'source object was attached to a different copied snapshot layer';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;
END;
$test$;

DO $test$
BEGIN
  BEGIN
    INSERT INTO eogp.event_venue_snapshot_layers
     (id, organization_id, event_id, snapshot_id, source_layer_id, layer_code, layer_snapshot)
    VALUES
     ('65100000-0000-4000-8000-00000000000b',
      '10000000-0000-0000-0000-00000000000b',
      '62000000-0000-4000-8000-00000000000a',
      '65000000-0000-4000-8000-00000000000a',
      '64100000-0000-4000-8000-00000000000b',
      'PRIVATE','{"kind":"security"}'::jsonb);
    RAISE EXCEPTION 'unapproved private layer unexpectedly entered event snapshot';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;

  BEGIN
    INSERT INTO eogp.event_venue_snapshot_objects
     (id, organization_id, snapshot_id, snapshot_layer_id, source_object_id, object_kind, object_snapshot)
    VALUES
     ('65200000-0000-4000-8000-00000000000b',
      '10000000-0000-0000-0000-00000000000b',
      '65000000-0000-4000-8000-00000000000a',
      '65100000-0000-4000-8000-00000000000a',
      '64200000-0000-4000-8000-00000000000b',
      'zone','{"code":"CI-PRIVATE-ZONE"}'::jsonb);
    RAISE EXCEPTION 'object from an unapproved layer unexpectedly entered event snapshot';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;

  BEGIN
    INSERT INTO eogp.event_venue_snapshot_resources
     (id, organization_id, event_id, snapshot_id, source_resource_pool_id, resource_snapshot)
    VALUES
     ('65300000-0000-4000-8000-00000000000b',
      '10000000-0000-0000-0000-00000000000b',
      '62000000-0000-4000-8000-00000000000a',
      '65000000-0000-4000-8000-00000000000a',
      'a0000000-0000-0000-0000-00000000000b',
      '{"kind":"pool","label":"Unapproved"}'::jsonb);
    RAISE EXCEPTION 'unapproved resource pool unexpectedly entered event snapshot';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;
END;
$test$;
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
SELECT set_config('app.actor_membership_id', '30000000-0000-0000-0000-00000000000a', true);
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
  visible_source_layers integer;
  visible_source_pools integer;
  retained_snapshot_layers integer;
  retained_snapshot_objects integer;
  retained_snapshot_resources integer;
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

  SELECT count(*) INTO visible_source_layers
    FROM eogp.spatial_layers
   WHERE organization_id = '10000000-0000-0000-0000-00000000000a';
  SELECT count(*) INTO visible_source_pools
    FROM eogp.resource_pools
   WHERE organization_id = '10000000-0000-0000-0000-00000000000a';
  SELECT count(*) INTO retained_snapshot_layers
    FROM eogp.event_venue_snapshot_layers
   WHERE organization_id = '10000000-0000-0000-0000-00000000000b'
     AND snapshot_id = '65000000-0000-4000-8000-00000000000a';
  SELECT count(*) INTO retained_snapshot_objects
    FROM eogp.event_venue_snapshot_objects
   WHERE organization_id = '10000000-0000-0000-0000-00000000000b'
     AND snapshot_id = '65000000-0000-4000-8000-00000000000a';
  SELECT count(*) INTO retained_snapshot_resources
    FROM eogp.event_venue_snapshot_resources
   WHERE organization_id = '10000000-0000-0000-0000-00000000000b'
     AND snapshot_id = '65000000-0000-4000-8000-00000000000a';

  IF visible_source_layers <> 0 OR visible_source_pools <> 0 THEN
    RAISE EXCEPTION 'revoked grant must hide provider source data from the recipient';
  END IF;
  IF retained_snapshot_layers <> 2 OR retained_snapshot_objects <> 1
     OR retained_snapshot_resources <> 1 THEN
    RAISE EXCEPTION 'revocation must retain the already-copied event-owned historical snapshot';
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

SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000a', true);
SELECT set_config('app.actor_membership_id', '30000000-0000-0000-0000-00000000000a', true);

-- Event administration commands use the existing event.manage authorization
-- boundary, immutable schedule revision and separate metadata revision.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_session_id uuid;
  v_session jsonb;
  v_created jsonb;
  v_updated jsonb;
  v_archived jsonb;
  v_event_id uuid;
  v_list jsonb;
  v_count integer;
BEGIN
  v_created := eogp.create_organizer_event(
    '10000000-0000-0000-0000-00000000000a',
    '30000000-0000-0000-0000-00000000000a',
    'CI-EVENT-ADMIN',
    'CI Event Administration',
    'Initial event details',
    clock_timestamp() + interval '1 day',
    clock_timestamp() + interval '1 day 3 hours',
    'Europe/Sarajevo',
    '{"venue":"not assigned"}'::jsonb,
    '{"source":"rls_and_constraints"}'::jsonb
  );
  v_event_id := (v_created->>'eventId')::uuid;

  IF v_created->>'status' <> 'draft'
     OR (v_created->>'detailsRevision')::integer <> 1
     OR (v_created->>'currentRevision')::integer <> 1 THEN
    RAISE EXCEPTION 'event creation did not initialize draft and revision state';
  END IF;

  SELECT count(*) INTO v_count
    FROM eogp.event_schedule_revisions
   WHERE organization_id = '10000000-0000-0000-0000-00000000000a'
     AND event_id = v_event_id
     AND revision_number = 1
     AND schedule_kind = 'original';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'event creation must create exactly one original schedule revision';
  END IF;

  SELECT count(*) INTO v_count
    FROM eogp.event_capability_revisions r
    JOIN eogp.event_capability_sets s
      ON s.organization_id = r.organization_id
     AND s.id = r.capability_set_id
   WHERE s.organization_id = '10000000-0000-0000-0000-00000000000a'
     AND s.event_id = v_event_id
     AND r.revision_number = 1
     AND r.state = 'draft';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'event creation must initialize an empty capability revision';
  END IF;

  v_list := eogp.list_organizer_events(
    '10000000-0000-0000-0000-00000000000a',
    '30000000-0000-0000-0000-00000000000a'
  );
  IF NOT v_list @> jsonb_build_array(jsonb_build_object('eventId',v_event_id)) THEN
    RAISE EXCEPTION 'event manager must see the event in the organizer list';
  END IF;

  v_session := eogp.create_organizer_event_session(
    v_org, v_event_id, v_actor, 'opening', 'Opening session', NULL, NULL
  );
  IF v_session->>'status' <> 'planned' OR v_session->>'code' <> 'OPENING'
     OR v_session->>'timezoneName' <> 'Europe/Sarajevo'
     OR NOT EXISTS (
       SELECT 1 FROM eogp.audit_events
       WHERE organization_id = v_org AND actor_membership_id = v_actor
         AND aggregate_id = (v_session->>'sessionId')::uuid AND action = 'event.session.created'
     ) THEN
    RAISE EXCEPTION 'session creation must set its planning state, inherit timezone and audit the actor';
  END IF;
  IF eogp.list_organizer_event_sessions(v_org, v_event_id, v_actor)
       IS DISTINCT FROM jsonb_build_array(v_session || jsonb_build_object('detailsRevision', 1)) THEN
    RAISE EXCEPTION 'session list must return the persisted session';
  END IF;
  BEGIN
    PERFORM eogp.create_organizer_event_session(
      v_org, v_event_id, v_actor, 'OPENING', 'Duplicate session', NULL, NULL
    );
    RAISE EXCEPTION 'duplicate session code unexpectedly succeeded';
  EXCEPTION WHEN unique_violation THEN
    NULL;
  END;
  BEGIN
    PERFORM eogp.create_organizer_event_session(
      v_org, v_event_id, v_actor, 'TIMED', 'Incomplete timing', clock_timestamp(), NULL
    );
    RAISE EXCEPTION 'partial timing unexpectedly succeeded';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;
  BEGIN
    PERFORM eogp.list_organizer_event_sessions(
      '10000000-0000-0000-0000-00000000000b', v_event_id, v_actor
    );
    RAISE EXCEPTION 'cross-tenant session listing unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  BEGIN
    PERFORM eogp.create_organizer_event_session(
      v_org, v_event_id, '30000000-0000-0000-0000-00000000000b',
      'SPOOF', 'Wrong actor', NULL, NULL
    );
    RAISE EXCEPTION 'session creation accepted a different actor';
  EXCEPTION WHEN insufficient_privilege THEN
    NULL;
  END;
  IF has_table_privilege('eventor_runtime', 'eogp.event_sessions', 'INSERT,UPDATE,DELETE')
     OR has_function_privilege('eventor_worker',
       'eogp.create_organizer_event_session(uuid,uuid,uuid,text,text,timestamptz,timestamptz)', 'EXECUTE')
     OR NOT has_function_privilege('eventor_runtime',
       'eogp.create_organizer_event_session(uuid,uuid,uuid,text,text,timestamptz,timestamptz)', 'EXECUTE') THEN
    RAISE EXCEPTION 'session write privileges must be limited to the scoped runtime command';
  END IF;

  v_session_id := (v_session->>'sessionId')::uuid;
  v_session := eogp.update_organizer_event_session(
    v_org, v_event_id, v_session_id, v_actor, 1, 'Revised opening',
    '2031-01-18 10:00:00+00', '2031-01-18 11:00:00+00'
  );
  IF v_session->>'title' <> 'Revised opening' OR v_session->>'detailsRevision' <> '2'
     OR v_session->>'code' <> 'OPENING' OR v_session->>'status' <> 'planned'
     OR NOT EXISTS (
       SELECT 1 FROM eogp.audit_events WHERE organization_id = v_org
         AND aggregate_id = v_session_id AND action = 'event.session.updated'
         AND actor_membership_id = v_actor AND safe_metadata->>'detailsRevision' = '2'
     ) THEN
    RAISE EXCEPTION 'session edit must advance its revision and audit the actor';
  END IF;

  BEGIN
    PERFORM eogp.update_organizer_event_session(
      v_org, v_event_id, v_session_id, v_actor, 1, 'Stale edit', NULL, NULL
    );
    RAISE EXCEPTION 'stale session edit unexpectedly succeeded';
  EXCEPTION WHEN serialization_failure THEN
    NULL;
  END;
  BEGIN
    PERFORM eogp.update_organizer_event_session(
      v_org, gen_random_uuid(), v_session_id, v_actor, 2, 'Wrong parent event', NULL, NULL
    );
    RAISE EXCEPTION 'editing a session through a different event unexpectedly succeeded';
  EXCEPTION WHEN no_data_found THEN
    NULL;
  END;
  BEGIN
    PERFORM eogp.update_organizer_event_session(
      v_org, v_event_id, v_session_id, v_actor, 2, 'Partial timing', clock_timestamp(), NULL
    );
    RAISE EXCEPTION 'editing a session to partial timing unexpectedly succeeded';
  EXCEPTION WHEN invalid_parameter_value THEN
    NULL;
  END;

  v_updated := eogp.update_organizer_event_details(
    '10000000-0000-0000-0000-00000000000a',
    v_event_id,
    '30000000-0000-0000-0000-00000000000a',
    1,
    'CI Event Administration Updated',
    'Updated details'
  );
  IF v_updated->>'title' <> 'CI Event Administration Updated'
     OR (v_updated->>'detailsRevision')::integer <> 2 THEN
    RAISE EXCEPTION 'event metadata update must increment its own revision';
  END IF;

  BEGIN
    PERFORM eogp.update_organizer_event_details(
      '10000000-0000-0000-0000-00000000000a',
      v_event_id,
      '30000000-0000-0000-0000-00000000000a',
      1,
      'Stale update',
      NULL
    );
    RAISE EXCEPTION 'stale event details revision unexpectedly succeeded';
  EXCEPTION WHEN SQLSTATE '40001' THEN
    NULL;
  END;

  v_archived := eogp.archive_organizer_event(
    '10000000-0000-0000-0000-00000000000a',
    v_event_id,
    '30000000-0000-0000-0000-00000000000a',
    2
  );
  IF v_archived->>'status' <> 'archived'
     OR (v_archived->>'detailsRevision')::integer <> 3 THEN
    RAISE EXCEPTION 'draft event archive must advance the metadata revision';
  END IF;

  v_archived := eogp.archive_organizer_event(
    '10000000-0000-0000-0000-00000000000a',
    v_event_id,
    '30000000-0000-0000-0000-00000000000a',
    2
  );
  IF v_archived->>'alreadyArchived' <> 'true'
     OR (v_archived->>'detailsRevision')::integer <> 3 THEN
    RAISE EXCEPTION 'repeated archive command should return the already-archived result';
  END IF;

  BEGIN
    PERFORM eogp.update_organizer_event_details(
      '10000000-0000-0000-0000-00000000000a',
      v_event_id,
      '30000000-0000-0000-0000-00000000000a',
      3,
      'Edit archived event',
      NULL
    );
    RAISE EXCEPTION 'archived event unexpectedly accepted metadata edits';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;

  BEGIN
    PERFORM eogp.create_organizer_event_session(
      v_org, v_event_id, v_actor, 'TOO-LATE', 'Archived event session', NULL, NULL
    );
    RAISE EXCEPTION 'archived event unexpectedly accepted a new session';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;

  BEGIN
    PERFORM eogp.update_organizer_event_session(
      v_org, v_event_id, v_session_id, v_actor, 2, 'Archived event session edit', NULL, NULL
    );
    RAISE EXCEPTION 'archived event unexpectedly accepted a session edit';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN
    NULL;
  END;

  IF NOT has_function_privilege(
       'eventor_runtime',
       'eogp.create_organizer_event(uuid,uuid,text,text,text,timestamp with time zone,timestamp with time zone,text,jsonb,jsonb)',
       'EXECUTE'
     )
     OR has_function_privilege(
       'eventor_worker',
       'eogp.create_organizer_event(uuid,uuid,text,text,text,timestamp with time zone,timestamp with time zone,text,jsonb,jsonb)',
       'EXECUTE'
     )
     OR has_table_privilege('eventor_runtime','eogp.events','INSERT') THEN
    RAISE EXCEPTION 'event administration must expose only the scoped runtime command';
  END IF;
END;
$test$;


-- Organizer lifecycle approval must follow the planned schedule and record each actor.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_event_id uuid;
  v_session_id uuid;
  v_result jsonb;
BEGIN
  v_result := eogp.create_organizer_event(
    v_org, v_actor, 'CI-EVENT-APPROVAL', 'Approval test event', NULL,
    '2031-01-18 09:00:00+00', '2031-01-18 12:00:00+00', 'Europe/Sarajevo', '{}', '{}'
  );
  v_event_id := (v_result->>'eventId')::uuid;
  v_result := eogp.create_organizer_event_session(v_org, v_event_id, v_actor, 'INTRO', 'Opening session', NULL, NULL);
  v_session_id := (v_result->>'sessionId')::uuid;

  BEGIN
    PERFORM eogp.transition_organizer_event(v_org, v_event_id, v_actor, 1, 1, 'publish');
    RAISE EXCEPTION 'publishing an unapproved event unexpectedly succeeded';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;

  PERFORM eogp.transition_organizer_event(v_org, v_event_id, v_actor, 1, 1, 'plan');
  BEGIN
    PERFORM eogp.transition_organizer_event(v_org, v_event_id, v_actor, 2, 2, 'submit');
    RAISE EXCEPTION 'submission with a stale schedule revision unexpectedly succeeded';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  PERFORM eogp.transition_organizer_event(v_org, v_event_id, v_actor, 2, 1, 'submit');
  BEGIN
    PERFORM eogp.update_organizer_event_details(v_org, v_event_id, v_actor, 3, 'Changed title', NULL);
    RAISE EXCEPTION 'editing an event under review unexpectedly succeeded';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  BEGIN
    PERFORM eogp.create_organizer_event_session(v_org, v_event_id, v_actor, 'EXTRA', 'Additional session', NULL, NULL);
    RAISE EXCEPTION 'adding a session during review unexpectedly succeeded';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;

  PERFORM eogp.transition_organizer_event(v_org, v_event_id, v_actor, 3, 1, 'return_to_planning');
  PERFORM eogp.transition_organizer_event(v_org, v_event_id, v_actor, 4, 1, 'submit');
  PERFORM eogp.transition_organizer_event(v_org, v_event_id, v_actor, 5, 1, 'approve');
  BEGIN
    PERFORM eogp.transition_organizer_event(v_org, v_event_id, v_actor, 5, 1, 'publish');
    RAISE EXCEPTION 'publishing with stale approval details unexpectedly succeeded';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  v_result := eogp.transition_organizer_event(v_org, v_event_id, v_actor, 6, 1, 'publish');
  IF v_result->>'status' <> 'scheduled' OR v_result->>'currentRevision' <> '1'
     OR v_result->>'detailsRevision' <> '7'
     OR (SELECT count(*) FROM eogp.event_status_history WHERE organization_id = v_org
         AND event_id = v_event_id AND actor_membership_id = v_actor) <> 6
     OR NOT EXISTS (SELECT 1 FROM eogp.audit_events WHERE organization_id = v_org
         AND aggregate_id = v_event_id AND action = 'event.lifecycle.transitioned' AND reason_code = 'publish'
         AND actor_membership_id = v_actor AND safe_metadata->>'scheduleRevisionId' IS NOT NULL) THEN
    RAISE EXCEPTION 'publication must record actor and schedule without modifying the schedule revision';
  END IF;
  PERFORM eogp.transition_organizer_event_session(v_org, v_event_id, v_session_id, v_actor, 1, 1, 'schedule');
  BEGIN
    PERFORM eogp.transition_organizer_event_session(v_org, v_event_id, v_session_id, v_actor, 2, 1, 'start');
    RAISE EXCEPTION 'starting a session before its event unexpectedly succeeded';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  PERFORM eogp.transition_organizer_event(v_org, v_event_id, v_actor, 7, 1, 'start');
  PERFORM eogp.transition_organizer_event_session(v_org, v_event_id, v_session_id, v_actor, 2, 1, 'start');
  BEGIN
    PERFORM eogp.transition_organizer_event(v_org, v_event_id, v_actor, 8, 1, 'complete');
    RAISE EXCEPTION 'closing an event with an active session unexpectedly succeeded';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  BEGIN
    PERFORM eogp.transition_organizer_event_session(v_org, v_event_id, v_session_id, v_actor, 2, 1, 'complete');
    RAISE EXCEPTION 'completing a session with a stale revision unexpectedly succeeded';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  BEGIN
    PERFORM eogp.transition_organizer_event_session(v_org, v_event_id, v_session_id, v_actor, 3, 2, 'complete');
    RAISE EXCEPTION 'completing a session with a stale parent schedule unexpectedly succeeded';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  v_result := eogp.transition_organizer_event_session(v_org, v_event_id, v_session_id, v_actor, 3, 1, 'complete');
  IF v_result->>'status' <> 'completed' OR v_result->>'detailsRevision' <> '4'
     OR (SELECT count(*) FROM eogp.audit_events WHERE organization_id = v_org AND aggregate_id = v_session_id
         AND actor_membership_id = v_actor AND action = 'event.session.lifecycle.transitioned') <> 3 THEN
    RAISE EXCEPTION 'session progress must advance the revision and record each actor';
  END IF;
  v_result := eogp.transition_organizer_event(v_org, v_event_id, v_actor, 8, 1, 'complete');
  IF v_result->>'status' <> 'completed' OR v_result->>'detailsRevision' <> '9' THEN
    RAISE EXCEPTION 'closing a live event with finished sessions must succeed';
  END IF;
  IF has_function_privilege('eventor_worker',
       'eogp.transition_organizer_event(uuid,uuid,uuid,integer,integer,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'worker must not have direct event transition permission';
  END IF;
END;
$test$;

-- Persistent registry permissions are organization-wide grants separate from event operations.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_role uuid := gen_random_uuid();
  v_person uuid;
  v_event uuid;
  v_event_role uuid := gen_random_uuid();
  v_result jsonb;
BEGIN
  BEGIN
    PERFORM eogp.read_guest_registry(v_org, v_actor, NULL, '', false, 0);
    RAISE EXCEPTION 'event manager unexpectedly accessed the organization registry';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  INSERT INTO eogp.roles (id, organization_id, code, name, scope_kind)
    VALUES (v_role, v_org, 'CI-REGISTRY', 'CI Registry', 'organization');
  INSERT INTO eogp.role_permissions (organization_id, role_id, permission_code)
    VALUES (v_org, v_role, 'guest.registry.read');
  INSERT INTO eogp.user_role_grants (organization_id, membership_id, role_id, scope_kind, granted_by_membership_id)
    VALUES (v_org, v_actor, v_role, 'organization', v_actor);
  IF (eogp.read_guest_registry(v_org, v_actor, NULL, '', false, 0)->>'canManage')::boolean THEN
    RAISE EXCEPTION 'read-only registry grant reported write access';
  END IF;
  BEGIN
    PERFORM eogp.write_guest_registry_person(v_org, v_actor, NULL, NULL, 'create', '{"firstName":"Read","lastName":"Only"}');
    RAISE EXCEPTION 'read-only registry grant unexpectedly allowed person creation';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  INSERT INTO eogp.role_permissions (organization_id, role_id, permission_code)
    VALUES (v_org, v_role, 'guest.registry.manage');

  v_result := eogp.write_guest_registry_person(
    v_org, v_actor, NULL, NULL, 'create', '{"firstName":"Synthetic","lastName":"Directory Case","preferredName":"Preferred"}'
  );
  v_person := (v_result->>'personId')::uuid;
  IF v_result ? 'firstName' OR v_result->>'revision' <> '1' THEN
    RAISE EXCEPTION 'registry write result contains private names or an incorrect revision';
  END IF;
  IF jsonb_array_length(eogp.read_guest_registry(v_org, v_actor, NULL, 'directory case synthetic', false, 0)->'people') <> 1 THEN
    RAISE EXCEPTION 'directory must support name lookup in either order';
  END IF;
  BEGIN
    PERFORM eogp.read_guest_registry_export(v_org,v_actor,'',false);
    RAISE EXCEPTION 'Registry manager without an export grant unexpectedly exported profiles';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  INSERT INTO eogp.role_permissions (organization_id, role_id, permission_code)
    VALUES (v_org, v_role, 'guest.registry.export');
  v_result := eogp.read_guest_registry_export(v_org,v_actor,'Directory Case Synthetic',false);
  IF v_result->'people' IS DISTINCT FROM
       '[{"firstName":"Synthetic","lastName":"Directory Case","displayName":null,"preferredName":"Preferred","status":"active"}]'::jsonb
     OR eogp.read_guest_registry(v_org,v_actor,NULL,'',false,0)->>'canExport' IS DISTINCT FROM 'true'
     OR NOT EXISTS (SELECT 1 FROM eogp.audit_events WHERE organization_id = v_org AND aggregate_id = v_org
        AND action = 'guest.registry.exported' AND safe_metadata = '{"exportedCount":1,"archived":false}'::jsonb) THEN
    RAISE EXCEPTION 'Registry export did not use the correct filter, projection, capability or audit event';
  END IF;
  BEGIN
    PERFORM eogp.read_guest_registry_export(gen_random_uuid(),v_actor,'',false);
    RAISE EXCEPTION 'cross-tenant Registry export unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  v_result := eogp.write_guest_registry_person(v_org, v_actor, v_person, 1, 'update', '{"preferredName":null}');
  IF v_result->>'revision' <> '2' OR
     eogp.read_guest_registry(v_org, v_actor, v_person, '', false, 0)->'preferredName' <> 'null'::jsonb THEN
    RAISE EXCEPTION 'partial name update failed to clear the optional name and increment the revision';
  END IF;
  BEGIN
    PERFORM eogp.write_guest_registry_person(v_org, v_actor, v_person, 1, 'archive', '{}');
    RAISE EXCEPTION 'archiving with stale revision unexpectedly succeeded';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  v_result := eogp.create_organizer_event(
    v_org, v_actor, 'CI-REGISTRY-PARTICIPATION', 'Registry participation', NULL,
    '2031-01-18 09:00:00+00', '2031-01-18 12:00:00+00', 'Europe/Sarajevo', '{}', '{}'
  );
  v_event := (v_result->>'eventId')::uuid;
  INSERT INTO eogp.event_participations (organization_id, event_id, person_id, status, added_by_membership_id)
    VALUES (v_org, v_event, v_person, 'eligible', v_actor);
  BEGIN
    PERFORM eogp.write_guest_registry_person(v_org, v_actor, v_person, 2, 'archive', '{}');
    RAISE EXCEPTION 'archive unexpectedly hid a person with outstanding event participation';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  UPDATE eogp.event_participations SET status = 'withdrawn'
    WHERE organization_id = v_org AND event_id = v_event AND person_id = v_person;
  PERFORM eogp.write_guest_registry_person(v_org, v_actor, v_person, 2, 'archive', '{}');
  IF eogp.read_guest_registry_export(v_org,v_actor,'Directory Case',false)->'people' IS DISTINCT FROM '[]'::jsonb
     OR (eogp.read_guest_registry_export(v_org,v_actor,'Directory Case',true)#>>'{people,0,status}') IS DISTINCT FROM 'archived' THEN
    RAISE EXCEPTION 'Registry export did not respect archive filtering';
  END IF;
  IF jsonb_array_length(eogp.read_guest_registry(v_org, v_actor, NULL, 'Directory Case', false, 0)->'people') <> 0
     OR jsonb_array_length(eogp.read_guest_registry(v_org, v_actor, NULL, 'Directory Case', true, 0)->'people') <> 1
     OR NOT EXISTS (SELECT 1 FROM eogp.event_participations
       WHERE organization_id = v_org AND event_id = v_event AND person_id = v_person AND status = 'withdrawn')
     OR has_table_privilege('eventor_runtime', 'eogp.persons', 'SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'profile archival or the runtime registry boundary is incorrect';
  END IF;
  v_result := eogp.read_guest_registry_history(v_org, v_actor, v_person, 0);
  IF v_result->'participations' <> '[]'::jsonb OR jsonb_array_length(v_result->'changes') <> 3
     OR v_result::text LIKE '%Directory Case%' THEN
    RAISE EXCEPTION 'registry history must hide events without guest permission and omit private names';
  END IF;
  INSERT INTO eogp.roles (id, organization_id, code, name, scope_kind)
    VALUES (v_event_role, v_org, 'CI-REGISTRY-EVENT', 'CI Registry Event Reader', 'event');
  INSERT INTO eogp.role_permissions (organization_id, role_id, permission_code)
    VALUES (v_org, v_event_role, 'guest.read');
  INSERT INTO eogp.user_role_grants (organization_id, membership_id, role_id, scope_kind, scope_event_id, granted_by_membership_id)
    VALUES (v_org, v_actor, v_event_role, 'event', v_event, v_actor);
  v_result := eogp.read_guest_registry_history(v_org, v_actor, v_person, 0);
  IF jsonb_array_length(v_result->'participations') <> 1
     OR v_result#>>'{participations,0,eventId}' <> v_event::text
     OR v_result#>>'{participations,0,status}' <> 'withdrawn'
     OR NOT EXISTS (SELECT 1 FROM eogp.audit_events WHERE organization_id = v_org
         AND aggregate_id = v_person AND actor_membership_id = v_actor AND action = 'guest.registry.history_viewed') THEN
    RAISE EXCEPTION 'authorized archived participation history or access audit is missing';
  END IF;
  v_result := eogp.read_event_guest_list(v_org, v_event, v_actor, 'withdrawn', 0);
  IF (v_result->>'canManage')::boolean OR jsonb_array_length(v_result->'people') <> 1 THEN
    RAISE EXCEPTION 'read-only event grant must allow a filtered roster without management controls';
  END IF;
  IF eogp.read_guest_registry_history(v_org, v_actor, v_person, 50)->'participations' <> '[]'::jsonb THEN
    RAISE EXCEPTION 'history pagination repeated an earlier page';
  END IF;
  BEGIN
    PERFORM eogp.read_guest_registry('10000000-0000-0000-0000-00000000000b', v_actor, v_person, '', false, 0);
    RAISE EXCEPTION 'cross-tenant registry access unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$test$;

-- Reuse one organizer profile across events without changing prior identity snapshots.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_person uuid;
  v_first_event uuid;
  v_second_event uuid;
  v_result jsonb;
  v_participation uuid;
  v_invitation uuid;
BEGIN
  v_result := eogp.write_guest_registry_person(v_org, v_actor, NULL, NULL, 'create',
    '{"firstName":"Original","lastName":"Synthetic","displayName":"Pinned Name"}');
  v_person := (v_result->>'personId')::uuid;
  v_result := eogp.create_organizer_event(v_org, v_actor, 'CI-LINK-A', 'First link target', NULL,
    '2031-01-18 09:00:00+00', '2031-01-18 12:00:00+00', 'Europe/Sarajevo', '{}', '{}');
  v_first_event := (v_result->>'eventId')::uuid;
  v_result := eogp.create_organizer_event(v_org, v_actor, 'CI-LINK-B', 'Second link target', NULL,
    '2031-01-18 09:00:00+00', '2031-01-18 12:00:00+00', 'Europe/Sarajevo', '{}', '{}');
  v_second_event := (v_result->>'eventId')::uuid;

  PERFORM eogp.enable_event_guest_registry(v_org, v_first_event, v_actor);
  IF eogp.list_registry_linkable_events(v_org, v_actor, v_person) <> '[]'::jsonb THEN
    RAISE EXCEPTION 'registry permission unexpectedly allowed browsing event guest lists';
  END IF;
  BEGIN
    PERFORM eogp.link_registry_person_to_event(v_org, v_first_event, v_actor, v_person, 'eligible');
    RAISE EXCEPTION 'registry permission unexpectedly allowed adding to an event';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM eogp.read_event_guest_list(v_org, v_first_event, v_actor, NULL, 0);
    RAISE EXCEPTION 'event administration without guest permission exposed a guest list';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM eogp.read_event_guest_roster_export(v_org, v_first_event, v_actor, NULL);
    RAISE EXCEPTION 'event administration without guest permission exposed a roster export';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  INSERT INTO eogp.role_permissions (organization_id, role_id, permission_code)
  SELECT v_org, role.id, permission.code
  FROM eogp.roles role CROSS JOIN (VALUES ('guest.manage'),('invitation.manage')) permission(code)
  WHERE role.organization_id = v_org AND role.code = 'CI-REGISTRY';

  IF jsonb_array_length(eogp.list_registry_linkable_events(v_org, v_actor, v_person)) <> 1 THEN
    RAISE EXCEPTION 'event selection must include only enabled, authorized guest lists';
  END IF;
  BEGIN
    PERFORM eogp.link_registry_person_to_event(v_org, v_second_event, v_actor, v_person, 'eligible');
    RAISE EXCEPTION 'linking to a disabled event guest list unexpectedly succeeded';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;

  v_result := eogp.link_registry_person_to_event(v_org, v_first_event, v_actor, v_person, 'eligible');
  v_participation := (v_result->>'participationId')::uuid;
  PERFORM eogp.write_guest_registry_person(v_org, v_actor, v_person, 1, 'update', '{"displayName":"Current Name"}');
  v_result := eogp.read_event_guest_list(v_org, v_first_event, v_actor, 'eligible', 0);
  IF NOT (v_result->>'canManage')::boolean
     OR v_result#>>'{people,0,displayName}' <> 'Pinned Name'
     OR v_result#>'{people,0}' ? 'personId'
     OR eogp.read_event_guest_list(v_org, v_first_event, v_actor, 'waitlisted', 0)->'people' <> '[]'::jsonb
     OR NOT eogp.list_event_guest_workspaces(v_org, v_actor) @> jsonb_build_array(jsonb_build_object('eventId', v_first_event)) THEN
    RAISE EXCEPTION 'roster must show the scoped pinned name, filter statuses, and omit Registry identifiers';
  END IF;
  v_result := eogp.read_event_guest_roster_export(v_org, v_first_event, v_actor, 'eligible');
  IF v_result->'people' IS DISTINCT FROM '[{"displayName":"Pinned Name","status":"eligible","categoryCode":null}]'::jsonb
     OR eogp.read_event_guest_roster_export(v_org, v_first_event, v_actor, 'waitlisted')->'people' IS DISTINCT FROM '[]'::jsonb
     OR has_table_privilege('eventor_runtime', 'eogp.event_guest_roster_rows', 'SELECT')
     OR NOT EXISTS (SELECT 1 FROM eogp.audit_events WHERE organization_id = v_org AND aggregate_id = v_first_event
        AND action = 'guest.event_roster.exported' AND safe_metadata @> '{"exportedCount":1,"statusFilter":"eligible"}') THEN
    RAISE EXCEPTION 'roster export exposed a wrong projection, missed the filter or did not audit';
  END IF;
  IF NOT eogp.list_guest_invitation_participations(v_org, v_first_event, v_actor)
      @> '[{"displayName":"Pinned Name"}]'::jsonb THEN
    RAISE EXCEPTION 'profile edit changed a linked event name';
  END IF;
  BEGIN
    PERFORM eogp.link_registry_person_to_event(v_org, v_first_event, v_actor, v_person, 'eligible');
    RAISE EXCEPTION 'duplicate event participation unexpectedly succeeded';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;

  PERFORM eogp.enable_event_guest_registry(v_org, v_second_event, v_actor);
  PERFORM eogp.link_registry_person_to_event(v_org, v_second_event, v_actor, v_person, 'waitlisted');
  IF NOT eogp.list_guest_invitation_participations(v_org, v_second_event, v_actor)
      @> '[{"displayName":"Current Name","status":"waitlisted"}]'::jsonb
     OR jsonb_array_length(eogp.read_guest_registry_history(v_org, v_actor, v_person, 0)->'participations') <> 2
     OR has_table_privilege('eventor_runtime', 'eogp.event_participations', 'INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'historic participation, permissioned writes or cross-event profile reuse failed';
  END IF;
  INSERT INTO eogp.invitations (organization_id, event_id, participation_id, created_by_membership_id, issued_at)
    VALUES (v_org, v_first_event, v_participation, v_actor, clock_timestamp()) RETURNING id INTO v_invitation;
  BEGIN
    PERFORM eogp.update_guest_participation_status(v_org, v_first_event, v_actor, v_participation, 1, 'withdrawn');
    RAISE EXCEPTION 'withdrawal unexpectedly left an outstanding invitation';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  PERFORM eogp.revoke_guest_invitation(v_org, v_invitation, v_actor, 'withdraw_guest');
  v_result := eogp.update_guest_participation_status(v_org, v_first_event, v_actor, v_participation, 1, 'withdrawn');
  IF v_result->>'status' <> 'withdrawn' OR v_result->>'revision' <> '2'
     OR NOT EXISTS (SELECT 1 FROM eogp.participation_status_history WHERE organization_id = v_org
        AND participation_id = v_participation AND previous_status = 'eligible' AND new_status = 'withdrawn'
        AND actor_membership_id = v_actor)
     OR NOT EXISTS (SELECT 1 FROM eogp.persons WHERE organization_id = v_org AND id = v_person AND status = 'active')
     OR NOT EXISTS (SELECT 1 FROM eogp.event_participations WHERE organization_id = v_org
        AND event_id = v_second_event AND person_id = v_person AND status = 'waitlisted') THEN
    RAISE EXCEPTION 'withdrawal must record event history without altering the person or other events';
  END IF;
  BEGIN
    PERFORM eogp.update_guest_participation_status(v_org, v_first_event, v_actor, v_participation, 1, 'eligible');
    RAISE EXCEPTION 'stale participation edit unexpectedly succeeded';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
END;
$test$;

-- Contact values have a separate permission and encrypted write boundary.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_cipher CONSTANT bytea := convert_to('ECP1' || repeat('x', 32), 'UTF8');
  v_person uuid;
  v_contact uuid;
  v_result jsonb;
BEGIN
  v_result := eogp.write_guest_registry_person(v_org, v_actor, NULL, NULL, 'create',
    '{"firstName":"Contact","lastName":"Synthetic"}');
  v_person := (v_result->>'personId')::uuid;
  BEGIN
    PERFORM eogp.read_guest_registry_contacts(v_org, v_actor, v_person);
    RAISE EXCEPTION 'ordinary Registry permission exposed contact values';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  INSERT INTO eogp.role_permissions (organization_id, role_id, permission_code)
  SELECT v_org, id, 'guest.registry.contacts.manage' FROM eogp.roles WHERE organization_id = v_org AND code = 'CI-REGISTRY';

  v_result := eogp.write_guest_registry_contact(v_org, v_actor, v_person, NULL, NULL, 'email',
    repeat('a',64), v_cipher, 'permitted', true);
  v_contact := (v_result->>'contactId')::uuid;
  IF v_result ? 'ciphertext' OR v_result->>'revision' <> '1'
     OR eogp.read_guest_registry_contacts(v_org,v_actor,v_person)#>>'{contacts,0,ciphertext}' <> encode(v_cipher,'base64')
     OR eogp.read_guest_registry_contacts(v_org,v_actor,v_person)#>>'{contacts,0,verified}' <> 'false' THEN
    RAISE EXCEPTION 'contact storage or write projection is incorrect';
  END IF;
  BEGIN
    PERFORM eogp.write_guest_registry_contact(v_org, v_actor, v_person, NULL, NULL, 'email',
      repeat('b',64), v_cipher, 'permitted', true);
    RAISE EXCEPTION 'second primary email unexpectedly succeeded';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  BEGIN
    PERFORM eogp.write_guest_registry_contact(v_org, v_actor, v_person, v_contact, 2, NULL, NULL, NULL, 'withdrawn', false);
    RAISE EXCEPTION 'stale contact preference edit unexpectedly succeeded';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  PERFORM eogp.write_guest_registry_contact(v_org, v_actor, v_person, v_contact, 1, NULL, NULL, NULL, 'withdrawn', false);
  IF eogp.read_guest_registry_contacts(v_org,v_actor,v_person)#>>'{contacts,0,consent}' <> 'withdrawn'
     OR has_table_privilege('eventor_runtime', 'eogp.person_contact_points', 'SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'contact consent or runtime access boundary is incorrect';
  END IF;
END;
$test$;

-- Import preview persists encrypted staging rows and leaves Registry and event guests intact.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-4000-8000-00000000000a';
  v_fixture_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_event uuid;
  v_batch uuid;
  v_result jsonb;
  v_before integer;
  v_cipher text := encode(convert_to('ECP1' || repeat('x', 32), 'UTF8'), 'base64');
BEGIN
  SELECT id INTO v_event FROM eogp.events WHERE organization_id = v_fixture_org AND event_code = 'CI-LINK-A';
  SELECT count(*) INTO v_before FROM eogp.event_participations WHERE organization_id = v_fixture_org AND event_id = v_event;
  v_result := eogp.prepare_guest_import_preview(v_fixture_org, v_event, v_actor, repeat('a',64), jsonb_build_array(
    jsonb_build_object('rowNumber',2,'firstName','contact','lastName','synthetic',
      'sourceCiphertext',v_cipher,'namesCiphertext',v_cipher,'errors','[]'::jsonb),
    jsonb_build_object('rowNumber',3,'firstName','','lastName','Synthetic',
      'sourceCiphertext',v_cipher,'namesCiphertext',v_cipher,'errors','["name_required"]'::jsonb)
  ));
  v_batch := (v_result->>'batchId')::uuid;
  IF v_result ? 'rows' OR v_result->>'rowCount' <> '2' THEN
    RAISE EXCEPTION 'preview creation result exposed values or wrong row count';
  END IF;
  v_result := eogp.read_guest_import_preview(v_fixture_org, v_event, v_actor, v_batch);
  IF v_result#>>'{rows,0,duplicateCount}' <> '1' OR v_result#>>'{rows,0,namesCiphertext}' <> v_cipher
     OR v_result#>>'{rows,1,errors,0}' <> 'name_required'
     OR (SELECT count(*) FROM eogp.event_participations WHERE organization_id = v_fixture_org AND event_id = v_event) <> v_before
     OR has_table_privilege('eventor_runtime', 'eogp.guest_import_rows', 'SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'import preview validation, confidentiality or write isolation failed';
  END IF;
  v_result := eogp.read_guest_import_report(v_fixture_org, v_event, v_actor, v_batch);
  IF v_result->>'state' IS DISTINCT FROM 'ready' OR v_result#>'{rows,0}' IS DISTINCT FROM
       '{"rowNumber":2,"outcome":"needs_review","errors":[],"duplicateCount":1}'::jsonb
     OR v_result#>'{rows,1}' IS DISTINCT FROM
       '{"rowNumber":3,"outcome":"invalid","errors":["name_required"],"duplicateCount":0}'::jsonb THEN
    RAISE EXCEPTION 'preview report contains incorrect diagnostics or leaked data';
  END IF;
  BEGIN
    PERFORM eogp.read_guest_import_preview(v_org, v_event, v_actor, v_batch);
    RAISE EXCEPTION 'cross-tenant preview unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM eogp.read_guest_import_report(v_org, v_event, v_actor, v_batch);
    RAISE EXCEPTION 'cross-tenant report unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$test$;

-- Committing a preview imports only clean rows and rolls back on late duplicates.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_cipher text := encode(convert_to('ECP1' || repeat('x', 32), 'UTF8'), 'base64');
  v_event uuid;
  v_batch uuid;
  v_result jsonb;
  v_clean jsonb := '{"firstName":"Import","lastName":"Clean"}';
  v_late jsonb := '{"firstName":"Import","lastName":"Late Match"}';
  v_rows jsonb;
BEGIN
  SELECT id INTO v_event FROM eogp.events WHERE organization_id = v_org AND event_code = 'CI-LINK-A';
  v_result := eogp.prepare_guest_import_preview(v_org, v_event, v_actor, repeat('b',64), jsonb_build_array(
    jsonb_build_object('rowNumber',2,'firstName','Import','lastName','Clean',
      'sourceCiphertext',v_cipher,'namesCiphertext',v_cipher,'errors','[]'::jsonb),
    jsonb_build_object('rowNumber',3,'firstName','Import','lastName','Late Match',
      'sourceCiphertext',v_cipher,'namesCiphertext',v_cipher,'errors','[]'::jsonb)
  ));
  v_batch := (v_result->>'batchId')::uuid;
  v_rows := jsonb_build_array(
    jsonb_build_object('rowNumber',2,'namesCiphertext',v_cipher,'names',v_clean),
    jsonb_build_object('rowNumber',3,'namesCiphertext',v_cipher,'names',v_late));
  PERFORM eogp.write_guest_registry_person(v_org, v_actor, NULL, NULL, 'create', v_late);
  BEGIN
    PERFORM eogp.commit_clean_guest_import(v_org, v_event, v_actor, v_batch, v_rows);
    RAISE EXCEPTION 'commit did not detect a late duplicate';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  IF EXISTS (SELECT 1 FROM eogp.persons WHERE organization_id = v_org AND first_name = 'Import' AND last_name = 'Clean')
     OR EXISTS (SELECT 1 FROM eogp.guest_import_rows WHERE organization_id = v_org AND batch_id = v_batch
                AND committed_participation_id IS NOT NULL) THEN
    RAISE EXCEPTION 'failed import did not roll back the first row';
  END IF;

  v_result := eogp.prepare_guest_import_preview(v_org, v_event, v_actor, repeat('c',64), jsonb_build_array(
    jsonb_build_object('rowNumber',2,'firstName','Import','lastName','Clean',
      'sourceCiphertext',v_cipher,'namesCiphertext',v_cipher,'errors','[]'::jsonb),
    jsonb_build_object('rowNumber',3,'firstName','Import','lastName','Late Match',
      'sourceCiphertext',v_cipher,'namesCiphertext',v_cipher,'errors','[]'::jsonb)
  ));
  v_batch := (v_result->>'batchId')::uuid;
  IF jsonb_array_length(eogp.guest_import_commit_input(v_org,v_event,v_actor,v_batch)) <> 1 THEN
    RAISE EXCEPTION 'duplicate row was included in the clean import input';
  END IF;
  v_result := eogp.commit_clean_guest_import(v_org, v_event, v_actor, v_batch, jsonb_build_array(v_rows->0));
  IF v_result->>'importedCount' <> '1' OR v_result->>'skippedCount' <> '1'
     OR eogp.commit_clean_guest_import(v_org,v_event,v_actor,v_batch,'[]') <> v_result
     OR NOT EXISTS (SELECT 1 FROM eogp.guest_import_rows WHERE organization_id = v_org AND batch_id = v_batch
                    AND row_number = 2 AND committed_participation_id IS NOT NULL) THEN
    RAISE EXCEPTION 'clean import or batch replay failed';
  END IF;
  v_result := eogp.read_guest_import_report(v_org, v_event, v_actor, v_batch);
  IF v_result->>'state' IS DISTINCT FROM 'committed'
     OR v_result#>>'{rows,0,outcome}' IS DISTINCT FROM 'created'
     OR v_result#>>'{rows,1,outcome}' IS DISTINCT FROM 'skipped' THEN
    RAISE EXCEPTION 'clean import report did not reconcile committed and unresolved rows';
  END IF;
END;
$test$;

-- A reviewed match reuses an active Registry profile and pins the reviewed revision.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_cipher text := encode(convert_to('ECP1' || repeat('x', 32), 'UTF8'), 'base64');
  v_event uuid;
  v_batch uuid;
  v_person uuid;
  v_choices jsonb;
  v_result jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id = v_org AND event_code = 'CI-LINK-A';
  SELECT id INTO STRICT v_person FROM eogp.persons WHERE organization_id = v_org
    AND first_name = 'Import' AND last_name = 'Late Match';
  v_batch := (eogp.prepare_guest_import_preview(v_org, v_event, v_actor, repeat('d',64), jsonb_build_array(
    jsonb_build_object('rowNumber',2,'firstName','Import','lastName','Late Match',
      'sourceCiphertext',v_cipher,'namesCiphertext',v_cipher,'errors','[]'::jsonb),
    jsonb_build_object('rowNumber',3,'firstName','Import','lastName','Late Match',
      'sourceCiphertext',v_cipher,'namesCiphertext',v_cipher,'errors','["duplicate_in_file"]'::jsonb)
  ))->>'batchId')::uuid;
  v_result := eogp.read_guest_import_preview(v_org, v_event, v_actor, v_batch);
  IF v_result#>>'{rows,0,matches,0,personId}' IS DISTINCT FROM v_person::text
     OR v_result#>>'{rows,0,matches,0,revision}' IS DISTINCT FROM '1'
     OR v_result#>'{rows,1,matches}' IS DISTINCT FROM '[]'::jsonb THEN
    RAISE EXCEPTION 'review exposed a wrong, stale or invalid candidate';
  END IF;
  v_choices := jsonb_build_array(jsonb_build_object('rowNumber',2,'personId',v_person,'expectedRevision',1));
  PERFORM eogp.write_guest_registry_person(v_org,v_actor,v_person,1,'update','{"displayName":"Reviewed Fixture"}');
  BEGIN
    PERFORM eogp.commit_reviewed_guest_import(v_org,v_event,v_actor,v_batch,'[]',v_choices);
    RAISE EXCEPTION 'stale match unexpectedly committed';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  v_choices := jsonb_set(v_choices, '{0,expectedRevision}', '2');
  v_result := eogp.commit_reviewed_guest_import(v_org,v_event,v_actor,v_batch,'[]',v_choices);
  IF v_result->>'importedCount' IS DISTINCT FROM '1' OR v_result->>'skippedCount' IS DISTINCT FROM '1'
     OR eogp.commit_reviewed_guest_import(v_org,v_event,v_actor,v_batch,'[]',v_choices) IS DISTINCT FROM v_result
     OR NOT EXISTS (SELECT 1 FROM eogp.event_participations WHERE organization_id = v_org AND event_id = v_event
                   AND person_id = v_person AND person_identity_snapshot->>'displayName' = 'Reviewed Fixture'
                   AND person_identity_snapshot->>'personRevision' = '2')
     OR (SELECT count(*) FROM eogp.persons WHERE organization_id = v_org AND first_name = 'Import'
         AND last_name = 'Late Match') <> 1 THEN
    RAISE EXCEPTION 'review did not link and pin the existing profile';
  END IF;
  v_result := eogp.read_guest_import_report(v_org, v_event, v_actor, v_batch);
  IF v_result#>'{rows,0}' IS DISTINCT FROM '{"rowNumber":2,"outcome":"linked","errors":[],"duplicateCount":1}'::jsonb
     OR v_result#>>'{rows,1,outcome}' IS DISTINCT FROM 'invalid' THEN
    RAISE EXCEPTION 'reviewed report did not reconcile linked and invalid rows';
  END IF;
  BEGIN
    PERFORM eogp.commit_clean_guest_import(v_org,v_event,v_actor,v_batch,'[]');
    RAISE EXCEPTION 'different duplicate choices replayed a committed batch';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
END;
$test$;

-- Workbook imports record selection metadata and reconcile errors at original worksheet rows.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_cipher text := encode(convert_to('ECP1' || repeat('x', 32), 'UTF8'), 'base64');
  v_event uuid;
  v_batch uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id = v_org AND event_code = 'CI-LINK-A';
  v_result := eogp.prepare_guest_import_workbook_preview(v_org, v_event, v_actor, repeat('e',64), jsonb_build_array(
    jsonb_build_object('rowNumber',503,'firstName','Import','lastName','Workbook Fixture',
      'sourceCiphertext',v_cipher,'namesCiphertext',v_cipher,'errors','[]'::jsonb),
    jsonb_build_object('rowNumber',508,'firstName','Import','lastName','Late Match',
      'sourceCiphertext',v_cipher,'namesCiphertext',v_cipher,'errors','["cell_not_text"]'::jsonb)
  ), 2, 3);
  v_batch := (v_result->>'batchId')::uuid;
  IF NOT EXISTS (SELECT 1 FROM eogp.guest_import_batches WHERE organization_id=v_org AND event_id=v_event AND id=v_batch
       AND source_filename='guest-import.xlsx'
       AND mapping_snapshot @> '{"sourceFormat":"xlsx","sheetIndex":2,"headerRow":3}'::jsonb) THEN
    RAISE EXCEPTION 'workbook preview lost source format or worksheet selection';
  END IF;
  PERFORM eogp.commit_clean_guest_import(v_org,v_event,v_actor,v_batch,jsonb_build_array(
    jsonb_build_object('rowNumber',503,'namesCiphertext',v_cipher,'names','{"firstName":"Import","lastName":"Workbook Fixture"}'::jsonb)
  ));
  v_result := eogp.read_guest_import_report(v_org,v_event,v_actor,v_batch);
  IF v_result->'rows' IS DISTINCT FROM '[
    {"rowNumber":503,"outcome":"created","errors":[],"duplicateCount":0},
    {"rowNumber":508,"outcome":"invalid","errors":["cell_not_text"],"duplicateCount":0}
  ]'::jsonb THEN
    RAISE EXCEPTION 'workbook report lost the original sheet rows or errors';
  END IF;
END;
$test$;

-- Guest categories are event-specific. Retirement keeps old assignments and the code reserved.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_event uuid;
  v_other_event uuid;
  v_participation uuid;
  v_revision integer;
  v_category uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id = v_org AND event_code = 'CI-LINK-A';
  SELECT id INTO STRICT v_other_event FROM eogp.events WHERE organization_id = v_org AND event_code = 'CI-LINK-B';
  SELECT p.id, p.revision INTO STRICT v_participation, v_revision
  FROM eogp.event_participations p JOIN eogp.persons person
    ON person.organization_id = p.organization_id AND person.id = p.person_id
  WHERE p.organization_id = v_org AND p.event_id = v_event AND person.last_name = 'Workbook Fixture';

  v_result := eogp.write_event_guest_category(v_org,v_other_event,v_actor,NULL,'STEWARDS','Stewards');
  v_category := (v_result->>'categoryId')::uuid;
  BEGIN
    PERFORM eogp.set_event_guest_category(v_org,v_event,v_actor,v_participation,v_revision,v_category);
    RAISE EXCEPTION 'a category from a different event was assigned';
  EXCEPTION WHEN no_data_found THEN NULL;
  END;

  v_result := eogp.write_event_guest_category(v_org,v_event,v_actor,NULL,'STEWARDS','Fixture stewards');
  v_category := (v_result->>'categoryId')::uuid;
  PERFORM eogp.set_event_guest_category(v_org,v_event,v_actor,v_participation,v_revision,v_category);
  BEGIN
    PERFORM eogp.set_event_guest_category(v_org,v_event,v_actor,v_participation,v_revision,NULL);
    RAISE EXCEPTION 'a stale participation write removed the category';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  PERFORM eogp.write_event_guest_category(v_org,v_event,v_actor,v_category,NULL,NULL);
  IF jsonb_array_length(eogp.read_event_guest_list(v_org,v_event,v_actor,'eligible',0,v_category,false)->'people') <> 1
     OR eogp.read_event_guest_list(v_org,v_event,v_actor,'withdrawn',0,v_category,false)->'people' IS DISTINCT FROM '[]'::jsonb
     OR eogp.read_event_guest_roster_export(v_org,v_event,v_actor,'eligible',v_category,false)->'people'
       IS DISTINCT FROM '[{"displayName":"Import Workbook Fixture","status":"eligible","categoryCode":"STEWARDS"}]'::jsonb
     OR (eogp.read_event_guest_roster_export(v_org,v_event,v_actor,NULL,NULL,true)->'people')
       @> '[{"categoryCode":"STEWARDS"}]'::jsonb THEN
    RAISE EXCEPTION 'category filters diverged between the roster and export';
  END IF;
  IF NOT eogp.list_event_guest_categories(v_org,v_event,v_actor)
       @> jsonb_build_array(jsonb_build_object('categoryId',v_category,'label','Fixture stewards','retired',true))
     OR NOT (eogp.read_event_guest_list(v_org,v_event,v_actor,NULL,0)->'people')
       @> jsonb_build_array(jsonb_build_object('participationId',v_participation,'categoryId',v_category,'categoryCode','STEWARDS'))
     OR has_table_privilege('eventor_runtime','eogp.event_guest_categories','SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'retired category history or runtime access boundary is incorrect';
  END IF;
  BEGIN
    PERFORM eogp.write_event_guest_category(v_org,v_event,v_actor,NULL,'STEWARDS','Repurposed');
    RAISE EXCEPTION 'a retired category code was reused';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  PERFORM eogp.set_event_guest_category(v_org,v_event,v_actor,v_participation,v_revision+1,NULL);
  BEGIN
    PERFORM eogp.set_event_guest_category(v_org,v_event,v_actor,v_participation,v_revision+2,v_category);
    RAISE EXCEPTION 'a retired category was assigned again';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
END;
$test$;

-- Editing internal tags preserves hidden assignments and protects retired tags.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_event uuid;
  v_participation uuid;
  v_revision integer;
  v_internal uuid;
  v_restricted uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id = v_org AND event_code = 'CI-LINK-A';
  SELECT p.id, p.revision INTO STRICT v_participation, v_revision
  FROM eogp.event_participations p JOIN eogp.persons person
    ON person.organization_id = p.organization_id AND person.id = p.person_id
  WHERE p.organization_id = v_org AND p.event_id = v_event AND person.last_name = 'Workbook Fixture';

  INSERT INTO eogp.guest_tags (organization_id,event_id,tag_code,label,sensitivity)
  VALUES (v_org,v_event,'RESTRICTED-FIXTURE','Restricted fixture','restricted') RETURNING id INTO v_restricted;
  INSERT INTO eogp.event_participation_tags (organization_id,event_id,participation_id,tag_id,added_by_membership_id)
  VALUES (v_org,v_event,v_participation,v_restricted,v_actor);

  v_result := eogp.write_event_guest_tag(v_org,v_event,v_actor,NULL,'TEAM-A','Team A');
  v_internal := (v_result->>'tagId')::uuid;
  IF eogp.list_event_guest_tags(v_org,v_event,v_actor) IS DISTINCT FROM jsonb_build_array(v_result)
     OR has_table_privilege('eventor_runtime','eogp.guest_tags','SELECT,INSERT,UPDATE,DELETE')
     OR has_table_privilege('eventor_runtime','eogp.event_participation_tags','SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'tag catalogue or runtime grants exposed restricted data';
  END IF;
  BEGIN
    PERFORM eogp.set_event_guest_tags(v_org,v_event,v_actor,v_participation,v_revision,ARRAY[v_restricted]);
    RAISE EXCEPTION 'restricted tag was accepted in the internal command';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;

  PERFORM eogp.set_event_guest_tags(v_org,v_event,v_actor,v_participation,v_revision,ARRAY[v_internal]);
  IF NOT (eogp.read_event_guest_list(v_org,v_event,v_actor,NULL,0)->'people')
       @> jsonb_build_array(jsonb_build_object('participationId',v_participation,'tagIds',ARRAY[v_internal]))
     OR (eogp.read_event_guest_list(v_org,v_event,v_actor,NULL,0)->'people')::text LIKE '%' || v_restricted || '%' THEN
    RAISE EXCEPTION 'roster tag projection is missing or leaked restricted assignments';
  END IF;
  PERFORM eogp.write_event_guest_tag(v_org,v_event,v_actor,v_internal,NULL,NULL);
  v_result := eogp.set_event_guest_tags(v_org,v_event,v_actor,v_participation,v_revision+1,ARRAY[v_internal]);
  IF v_result->>'revision' IS DISTINCT FROM (v_revision+1)::text THEN
    RAISE EXCEPTION 'preserving an already assigned retired tag changed its revision';
  END IF;
  BEGIN
    PERFORM eogp.set_event_guest_tags(v_org,v_event,v_actor,v_participation,v_revision,ARRAY[]::uuid[]);
    RAISE EXCEPTION 'stale update was allowed to remove an internal tag';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  PERFORM eogp.set_event_guest_tags(v_org,v_event,v_actor,v_participation,v_revision+1,ARRAY[]::uuid[]);
  BEGIN
    PERFORM eogp.set_event_guest_tags(v_org,v_event,v_actor,v_participation,v_revision+2,ARRAY[v_internal]);
    RAISE EXCEPTION 'retired tag could be newly assigned';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  IF NOT EXISTS (SELECT 1 FROM eogp.event_participation_tags
    WHERE organization_id = v_org AND participation_id = v_participation AND tag_id = v_restricted) THEN
    RAISE EXCEPTION 'updating internal tags removed an unrelated restricted assignment';
  END IF;
END;
$test$;

-- Profile merge needs a separate grant, checks both reviewed revisions, and can restore the source.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_event uuid;
  v_source uuid;
  v_destination uuid;
  v_participation uuid;
  v_merge uuid;
  v_review uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id = v_org AND event_code = 'CI-LINK-A';
  v_source := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Duplicate","lastName":"Merge Fixture","displayName":"Source Fixture"}')->>'personId')::uuid;
  v_destination := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Duplicate","lastName":"Merge Fixture","displayName":"Destination Fixture"}')->>'personId')::uuid;
  v_participation := (eogp.link_registry_person_to_event(v_org,v_event,v_actor,v_destination,'eligible')->>'participationId')::uuid;

  BEGIN
    PERFORM eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
    RAISE EXCEPTION 'ordinary Registry management unexpectedly permitted merge review';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  INSERT INTO eogp.role_permissions (organization_id, role_id, permission_code)
  SELECT v_org, id, 'guest.registry.merge' FROM eogp.roles WHERE organization_id = v_org AND code = 'CI-REGISTRY';
  IF eogp.preview_guest_registry_merge(v_org,v_actor,v_destination,v_source)->>'blocker' IS DISTINCT FROM 'source_has_linked_records'
     OR eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination)->'blocker' IS DISTINCT FROM 'null'::jsonb
     OR eogp.read_guest_registry(v_org,v_actor,NULL,'',false,0)->>'canMerge' IS DISTINCT FROM 'true' THEN
    RAISE EXCEPTION 'merge review did not account for source dependencies or capability';
  END IF;
  v_review := (eogp.preview_guest_registry_merge(v_org,v_actor,v_destination,v_source)->>'reviewId')::uuid;
  BEGIN
    PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_destination,v_source,1,1,'duplicate_profile',v_review);
    RAISE EXCEPTION 'linked source unexpectedly merged';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;

  BEGIN
    PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,1,1,'duplicate_profile',gen_random_uuid());
    RAISE EXCEPTION 'merge unexpectedly committed without a valid recorded review';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  v_review := (eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination)->>'reviewId')::uuid;
  PERFORM eogp.write_guest_registry_person(v_org,v_actor,v_destination,1,'update','{"preferredName":"Reviewed"}');
  BEGIN
    PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,1,1,'duplicate_profile',v_review);
    RAISE EXCEPTION 'stale destination review unexpectedly merged';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  v_review := (eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination)->>'reviewId')::uuid;
  v_merge := (eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,1,2,'duplicate_profile',v_review)->>'mergeId')::uuid;
  IF eogp.read_guest_registry(v_org,v_actor,v_source,'',false,0)->>'status' IS DISTINCT FROM 'merged'
     OR eogp.read_guest_registry(v_org,v_actor,NULL,'Source Fixture',false,0)->'people' IS DISTINCT FROM '[]'::jsonb
     OR (SELECT person_identity_snapshot->>'displayName' FROM eogp.event_participations
          WHERE organization_id=v_org AND id=v_participation) IS DISTINCT FROM 'Destination Fixture'
     OR (eogp.list_guest_registry_merges(v_org,v_actor,0)#>>'{merges,0,mergeId}') IS DISTINCT FROM v_merge::text
     OR has_table_privilege('eventor_runtime','eogp.person_merge_records','SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'merge lost its audit, directory or historical event boundary';
  END IF;
  v_result := eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);
  IF v_result->>'status' IS DISTINCT FROM 'restored'
     OR eogp.restore_guest_registry_merge(v_org,v_actor,v_merge) IS DISTINCT FROM v_result
     OR NOT EXISTS (SELECT 1 FROM eogp.persons WHERE organization_id=v_org AND id=v_source
        AND status='active' AND display_name='Source Fixture' AND merged_into_person_id IS NULL AND revision=3)
     OR NOT EXISTS (SELECT 1 FROM eogp.audit_events WHERE organization_id=v_org AND aggregate_id=v_source
        AND action='guest.registry.merge_restored' AND safe_metadata @> jsonb_build_object('mergeId',v_merge)) THEN
    RAISE EXCEPTION 'restoring the profile lost the original record or audit';
  END IF;
END;
$test$;

-- Group membership changes are event-scoped and retain existing membership roles.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_event uuid;
  v_other_event uuid;
  v_participation uuid;
  v_revision integer;
  v_first uuid;
  v_second uuid;
  v_foreign uuid;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id = v_org AND event_code = 'CI-LINK-A';
  SELECT id INTO STRICT v_other_event FROM eogp.events WHERE organization_id = v_org AND event_code = 'CI-LINK-B';
  SELECT p.id, p.revision INTO STRICT v_participation, v_revision
  FROM eogp.event_participations p JOIN eogp.persons person
    ON person.organization_id = p.organization_id AND person.id = p.person_id
  WHERE p.organization_id = v_org AND p.event_id = v_event AND person.last_name = 'Workbook Fixture';
  v_first := (eogp.write_event_guest_group(v_org,v_event,v_actor,NULL,'DELEGATION','Delegation A')->>'groupId')::uuid;
  v_second := (eogp.write_event_guest_group(v_org,v_event,v_actor,NULL,'TEAM','Team B')->>'groupId')::uuid;
  v_foreign := (eogp.write_event_guest_group(v_org,v_other_event,v_actor,NULL,'DELEGATION','Other event group')->>'groupId')::uuid;
  INSERT INTO eogp.guest_group_memberships(organization_id,event_id,group_id,participation_id,membership_kind)
  VALUES (v_org,v_event,v_first,v_participation,'lead');
  BEGIN
    PERFORM eogp.set_event_guest_groups(v_org,v_event,v_actor,v_participation,v_revision,ARRAY[v_first,v_foreign]);
    RAISE EXCEPTION 'group from a different event was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  PERFORM eogp.set_event_guest_groups(v_org,v_event,v_actor,v_participation,v_revision,ARRAY[v_first,v_second]);
  IF NOT (eogp.read_event_guest_list(v_org,v_event,v_actor,NULL,0)->'people')
       @> jsonb_build_array(jsonb_build_object('participationId',v_participation,'groupIds',ARRAY[v_first,v_second]))
     OR NOT EXISTS (SELECT 1 FROM eogp.guest_group_memberships WHERE organization_id=v_org AND event_id=v_event
         AND group_id=v_first AND participation_id=v_participation AND membership_kind='lead')
     OR has_table_privilege('eventor_runtime','eogp.guest_group_memberships','SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'group assignment did not retain membership or grants correctly';
  END IF;

  BEGIN
    PERFORM eogp.set_event_guest_groups(v_org,v_event,v_actor,v_participation,v_revision+1,ARRAY[v_first,v_second],
      jsonb_build_object(v_foreign,'lead'));
    RAISE EXCEPTION 'role was accepted for a group outside the selection';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  PERFORM eogp.set_event_guest_groups(v_org,v_event,v_actor,v_participation,v_revision+1,ARRAY[v_first,v_second],
    jsonb_build_object(v_first,'security_liaison'));
  IF NOT (eogp.read_event_guest_list(v_org,v_event,v_actor,NULL,0)->'people') @> jsonb_build_array(jsonb_build_object(
       'participationId',v_participation,'groupRoles',jsonb_build_object(v_first,'security_liaison',v_second,'member'),
       'revision',v_revision+2)) THEN
    RAISE EXCEPTION 'role-only change did not persist or advance the revision';
  END IF;
  PERFORM eogp.write_event_guest_group(v_org,v_event,v_actor,v_first,NULL,NULL);
  BEGIN
    PERFORM eogp.set_event_guest_groups(v_org,v_event,v_actor,v_participation,v_revision+2,ARRAY[v_first,v_second],
      jsonb_build_object(v_first,'assistant'));
    RAISE EXCEPTION 'retired group role was edited';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  IF NOT eogp.list_event_guest_groups(v_org,v_event,v_actor)
      @> jsonb_build_array(jsonb_build_object('groupId',v_first,'retired',true)) THEN
    RAISE EXCEPTION 'group retirement was not recorded';
  END IF;
  BEGIN
    PERFORM eogp.set_event_guest_groups(v_org,v_event,v_actor,v_participation,v_revision,ARRAY[v_second]);
    RAISE EXCEPTION 'stale group selection unexpectedly committed';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  PERFORM eogp.set_event_guest_groups(v_org,v_event,v_actor,v_participation,v_revision+2,ARRAY[v_second]);
  BEGIN
    PERFORM eogp.set_event_guest_groups(v_org,v_event,v_actor,v_participation,v_revision+3,ARRAY[v_first,v_second]);
    RAISE EXCEPTION 'retired group was newly selected';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
END;
$test$;

-- Name search uses event identity snapshots and keeps raw names out of export audit data.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_first uuid;
  v_second uuid;
  v_export jsonb;
BEGIN
  SELECT id INTO STRICT v_first FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  SELECT id INTO STRICT v_second FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-B';
  v_export := eogp.read_event_guest_roster_export(v_org,v_second,v_actor,'waitlisted',NULL,false,' current name ');
  IF NOT (eogp.read_event_guest_list(v_org,v_first,v_actor,'withdrawn',0,NULL,false,'synthetic original')->'people')
     @> '[{"displayName":"Pinned Name"}]'::jsonb
     OR eogp.read_event_guest_list(v_org,v_first,v_actor,NULL,0,NULL,false,'current name')->'people' IS DISTINCT FROM '[]'::jsonb
     OR v_export->'people' IS DISTINCT FROM '[{"displayName":"Current Name","status":"waitlisted","categoryCode":null}]'::jsonb THEN
    RAISE EXCEPTION 'name search or export did not preserve event identity';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM eogp.audit_events WHERE organization_id=v_org AND aggregate_id=v_second
        AND action='guest.event_roster.exported'
        AND safe_metadata = '{"exportedCount":1,"statusFilter":"waitlisted","nameFilterApplied":true}'::jsonb) THEN
    RAISE EXCEPTION 'export audit is missing safe name search metadata';
  END IF;
END;
$test$;

-- Relationship links stay in one event and preserve direction, retirement and restricted notes.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_event uuid;
  v_other_event uuid;
  v_guest uuid;
  v_related uuid;
  v_foreign uuid;
  v_link uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  SELECT id INTO STRICT v_other_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-B';
  SELECT id INTO STRICT v_guest FROM eogp.event_participations WHERE organization_id=v_org AND event_id=v_event
    AND person_identity_snapshot->>'lastName'='Workbook Fixture';
  SELECT id INTO STRICT v_related FROM eogp.event_participations WHERE organization_id=v_org AND event_id=v_event
    AND person_identity_snapshot->>'displayName'='Destination Fixture';
  SELECT id INTO STRICT v_foreign FROM eogp.event_participations WHERE organization_id=v_org AND event_id=v_other_event;
  BEGIN
    PERFORM eogp.write_event_guest_relationship(v_org,v_event,v_actor,v_guest,NULL,v_foreign,'Interpreter','directed');
    RAISE EXCEPTION 'a cross-event relationship was accepted';
  EXCEPTION WHEN no_data_found THEN NULL;
  END;

  v_link := (eogp.write_event_guest_relationship(v_org,v_event,v_actor,v_guest,NULL,v_related,'Interpreter','directed')->>'relationshipId')::uuid;
  UPDATE eogp.guest_relationships SET notes_restricted_ciphertext=convert_to('synthetic note','UTF8')
  WHERE organization_id=v_org AND id=v_link;
  v_result := eogp.read_event_guest_relationships(v_org,v_event,v_actor,v_guest)->0;
  IF v_result->>'direction' IS DISTINCT FROM 'outgoing' OR v_result->>'relatedDisplayName' IS DISTINCT FROM 'Destination Fixture'
     OR v_result ? 'notes' OR v_result ? 'notesCiphertext'
     OR (eogp.read_event_guest_relationships(v_org,v_event,v_actor,v_related)#>>'{0,direction}') IS DISTINCT FROM 'incoming'
     OR has_table_privilege('eventor_runtime','eogp.guest_relationships','SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'relationship direction or restricted data projection is incorrect';
  END IF;

  PERFORM eogp.write_event_guest_relationship(v_org,v_event,v_actor,v_related,v_link,NULL,NULL,NULL);
  IF (eogp.read_event_guest_relationships(v_org,v_event,v_actor,v_guest)#>>'{0,retiredAt}') IS NULL THEN
    RAISE EXCEPTION 'ended relationship lost its history';
  END IF;
  PERFORM eogp.write_event_guest_relationship(v_org,v_event,v_actor,v_guest,NULL,v_related,'Family','mutual');
  BEGIN
    PERFORM eogp.write_event_guest_relationship(v_org,v_event,v_actor,v_related,NULL,v_guest,' family ','mutual');
    RAISE EXCEPTION 'a reversed duplicate mutual relationship was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
END;
$test$;

-- Custom-field commands keep encrypted values event-scoped and retain retired fields for existing values.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_cipher bytea := convert_to('ECP1' || repeat('x', 32), 'UTF8');
  v_event uuid;
  v_guest uuid;
  v_revision integer;
  v_field uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  SELECT id,revision INTO STRICT v_guest,v_revision FROM eogp.event_participations WHERE organization_id=v_org AND event_id=v_event
    AND person_identity_snapshot->>'lastName'='Workbook Fixture';
  INSERT INTO eogp.guest_custom_field_definitions(organization_id,event_id,field_code,label,value_schema,sensitivity)
  VALUES (v_org,v_event,'RESTRICTED-TEST','Restricted fixture','{"format":"eventor-scalar-v1","type":"text"}','restricted');
  v_result := eogp.write_event_guest_field_definition(v_org,v_event,v_actor,NULL,'FIXTURE-NUMBER','Fixture number','integer');
  v_field := (v_result->>'fieldId')::uuid;
  IF eogp.list_event_guest_field_definitions(v_org,v_event,v_actor) IS DISTINCT FROM jsonb_build_array(v_result)
    OR has_table_privilege('eventor_runtime','eogp.guest_custom_field_values','SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'custom field definitions or grants exposed protected data';
  END IF;
  BEGIN
    PERFORM eogp.write_event_guest_field_value(v_org,v_event,v_actor,v_guest,v_field,v_revision,'text',v_cipher);
    RAISE EXCEPTION 'custom field accepted a mismatched type';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  PERFORM eogp.write_event_guest_field_value(v_org,v_event,v_actor,v_guest,v_field,v_revision,'integer',v_cipher);
  BEGIN
    PERFORM eogp.write_event_guest_field_value(v_org,v_event,v_actor,v_guest,v_field,v_revision,'integer',NULL);
    RAISE EXCEPTION 'a stale custom field write succeeded';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  PERFORM eogp.write_event_guest_field_definition(v_org,v_event,v_actor,v_field,NULL,NULL,NULL);
  v_result := eogp.read_event_guest_field_values(v_org,v_event,v_actor,v_guest);
  IF v_result#>>'{fields,0,ciphertext}' IS DISTINCT FROM encode(v_cipher,'base64')
    OR v_result#>>'{fields,0,retired}' IS DISTINCT FROM 'true'
    OR jsonb_array_length(v_result->'fields') <> 1 THEN
    RAISE EXCEPTION 'retired field value or encrypted projection missing';
  END IF;
  BEGIN
    PERFORM eogp.write_event_guest_field_value(v_org,v_event,v_actor,v_guest,v_field,v_revision+1,'integer',v_cipher);
    RAISE EXCEPTION 'a retired custom field accepted a replacement value';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  PERFORM eogp.write_event_guest_field_value(v_org,v_event,v_actor,v_guest,v_field,v_revision+1,'integer',NULL);
  IF eogp.read_event_guest_field_values(v_org,v_event,v_actor,v_guest)->'fields' IS DISTINCT FROM '[]'::jsonb THEN
    RAISE EXCEPTION 'clearing a retired field left a value';
  END IF;
END;
$test$;

-- Bulk categorization uses one transaction and checks every selected participation revision.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_event uuid;
  v_category uuid;
  v_guests jsonb;
  v_result jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  v_category := (eogp.write_event_guest_category(v_org,v_event,v_actor,NULL,'BULK-FIXTURE','Bulk fixture')->>'categoryId')::uuid;
  SELECT jsonb_agg(jsonb_build_object('participationId',chosen.id,'expectedRevision',chosen.revision) ORDER BY chosen.id)
  INTO v_guests FROM (SELECT id,revision FROM eogp.event_participations
    WHERE organization_id=v_org AND event_id=v_event AND status<>'cancelled' ORDER BY id LIMIT 2) chosen;
  BEGIN
    PERFORM eogp.set_event_guest_bulk_category(v_org,v_event,v_actor,v_category,
      jsonb_set(v_guests,'{1,expectedRevision}',to_jsonb((v_guests#>>'{1,expectedRevision}')::integer+1)));
    RAISE EXCEPTION 'a stale bulk category update committed';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  IF EXISTS (SELECT 1 FROM eogp.event_participations WHERE organization_id=v_org AND event_id=v_event AND category_id=v_category) THEN
    RAISE EXCEPTION 'failed bulk category update did not roll back';
  END IF;
  BEGIN
    PERFORM eogp.set_event_guest_bulk_category(v_org,v_event,v_actor,v_category,jsonb_build_array(v_guests->0,v_guests->0));
    RAISE EXCEPTION 'a duplicate guest was accepted in a bulk update';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  v_result := eogp.set_event_guest_bulk_category(v_org,v_event,v_actor,v_category,v_guests);
  IF v_result <> '{"processedCount":2,"updatedCount":2}'::jsonb
    OR (SELECT count(*) FROM eogp.event_participations WHERE organization_id=v_org AND event_id=v_event AND category_id=v_category) <> 2 THEN
    RAISE EXCEPTION 'bulk category update did not update both selected guests';
  END IF;
END;
$test$;

-- An active invitation prevents the whole bulk status change until expressly revoked.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_event uuid;
  v_guests jsonb;
  v_invitation uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  SELECT jsonb_agg(jsonb_build_object('participationId',chosen.id,'expectedRevision',chosen.revision) ORDER BY chosen.id)
  INTO v_guests FROM (SELECT id,revision FROM eogp.event_participations
    WHERE organization_id=v_org AND event_id=v_event AND status='eligible' ORDER BY id LIMIT 2) chosen;
  INSERT INTO eogp.invitations (organization_id,event_id,participation_id,created_by_membership_id,issued_at)
    VALUES (v_org,v_event,(v_guests#>>'{1,participationId}')::uuid,v_actor,clock_timestamp()) RETURNING id INTO v_invitation;
  BEGIN
    PERFORM eogp.set_event_guest_bulk_status(v_org,v_event,v_actor,'waitlisted',v_guests);
    RAISE EXCEPTION 'bulk status changed an invited guest';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  IF EXISTS (SELECT 1 FROM eogp.event_participations
    WHERE organization_id=v_org AND event_id=v_event AND id IN ((v_guests#>>'{0,participationId}')::uuid,(v_guests#>>'{1,participationId}')::uuid)
      AND status <> 'eligible') THEN
    RAISE EXCEPTION 'failed bulk status update did not roll back';
  END IF;
  PERFORM eogp.revoke_guest_invitation(v_org,v_invitation,v_actor,'fixture_bulk');
  v_result := eogp.set_event_guest_bulk_status(v_org,v_event,v_actor,'waitlisted',v_guests);
  IF v_result <> '{"processedCount":2,"updatedCount":2}'::jsonb
    OR (SELECT count(*) FROM eogp.event_participations WHERE organization_id=v_org AND event_id=v_event
      AND id IN ((v_guests#>>'{0,participationId}')::uuid,(v_guests#>>'{1,participationId}')::uuid) AND status='waitlisted') <> 2 THEN
    RAISE EXCEPTION 'bulk status did not waitlist both selected guests';
  END IF;
END;
$test$;

-- Staff who share an event can save views without seeing or deleting each other's preferences.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_cipher bytea := convert_to('ECP1' || repeat('x', 32), 'UTF8');
  v_event uuid;
  v_other_event uuid;
  v_foreign_category uuid;
  v_user uuid;
  v_member uuid;
  v_role uuid;
  v_view uuid := gen_random_uuid();
  v_second_view uuid := gen_random_uuid();
  v_result jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  SELECT id INTO STRICT v_other_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-B';
  SELECT id INTO STRICT v_foreign_category FROM eogp.event_guest_categories
    WHERE organization_id=v_org AND event_id=v_other_event AND code='STEWARDS';
  PERFORM eogp.save_event_guest_view(v_org,v_event,v_actor,v_view,repeat('1',64),v_cipher,'waitlisted',NULL,true);
  BEGIN
    PERFORM eogp.save_event_guest_view(v_org,v_event,v_actor,gen_random_uuid(),repeat('2',64),v_cipher,NULL,v_foreign_category,false);
    RAISE EXCEPTION 'a saved view accepted a category from another event';
  EXCEPTION WHEN foreign_key_violation THEN NULL;
  END;
  v_result := eogp.list_event_guest_saved_views(v_org,v_event,v_actor)->0;
  IF v_result IS DISTINCT FROM jsonb_build_object('viewId',v_view,'ciphertext',encode(v_cipher,'base64'),'status','waitlisted','category','unassigned')
    OR has_table_privilege('eventor_runtime','eogp.event_guest_saved_views','SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'saved view projection or direct access boundary is incorrect';
  END IF;

  INSERT INTO eogp.users (email,display_name) VALUES ('view-reader@example.invalid','Saved View Fixture') RETURNING id INTO v_user;
  INSERT INTO eogp.organization_memberships (organization_id,user_id) VALUES (v_org,v_user) RETURNING id INTO v_member;
  INSERT INTO eogp.roles(organization_id,code,name,scope_kind) VALUES (v_org,'VIEW-READER','View Reader','event') RETURNING id INTO v_role;
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code) VALUES (v_org,v_role,'guest.read');
  INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,scope_event_id,granted_by_membership_id)
    VALUES (v_org,v_member,v_role,'event',v_event,v_actor);
  PERFORM set_config('app.actor_membership_id',v_member::text,true);
  IF eogp.list_event_guest_saved_views(v_org,v_event,v_member) <> '[]'::jsonb THEN
    RAISE EXCEPTION 'one staff member saw another member''s saved view';
  END IF;
  BEGIN
    PERFORM eogp.delete_event_guest_saved_view(v_org,v_event,v_member,v_view);
    RAISE EXCEPTION 'one staff member deleted another member''s saved view';
  EXCEPTION WHEN no_data_found THEN NULL;
  END;
  PERFORM eogp.save_event_guest_view(v_org,v_event,v_member,v_second_view,repeat('1',64),v_cipher,'eligible',NULL,false);
  IF (eogp.list_event_guest_saved_views(v_org,v_event,v_member)#>>'{0,viewId}') IS DISTINCT FROM v_second_view::text THEN
    RAISE EXCEPTION 'guest read grant could not save a personal view';
  END IF;
  PERFORM set_config('app.actor_membership_id',v_actor::text,true);
  PERFORM eogp.delete_event_guest_saved_view(v_org,v_event,v_actor,v_view);
  IF eogp.list_event_guest_saved_views(v_org,v_event,v_actor) <> '[]'::jsonb THEN
    RAISE EXCEPTION 'deleted personal view was still listed';
  END IF;
END;
$test$;

-- Mapped previews retain field positions and continue through the encrypted import pipeline.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_cipher text := encode(convert_to('ECP1' || repeat('x', 32), 'UTF8'), 'base64');
  v_event uuid;
  v_batch uuid;
  v_rows jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  v_rows := jsonb_build_array(jsonb_build_object('rowNumber',503,'firstName','Mapped','lastName','Columns',
    'sourceCiphertext',v_cipher,'namesCiphertext',v_cipher,'errors','[]'::jsonb));
  BEGIN
    PERFORM eogp.prepare_mapped_guest_import_preview(v_org,v_event,v_actor,repeat('f',64),v_rows,
      '{"firstName":3,"lastName":3}',2,3);
    RAISE EXCEPTION 'duplicate source column was accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  v_batch := (eogp.prepare_mapped_guest_import_preview(v_org,v_event,v_actor,repeat('f',64),v_rows,
    '{"firstName":3,"lastName":1}',2,3)->>'batchId')::uuid;
  IF NOT EXISTS (SELECT 1 FROM eogp.guest_import_batches WHERE organization_id=v_org AND event_id=v_event AND id=v_batch
    AND mapping_snapshot @> '{"sourceFormat":"xlsx","sheetIndex":2,"headerRow":3,"columnsByField":{"firstName":3,"lastName":1}}')
    OR eogp.read_guest_import_preview(v_org,v_event,v_actor,v_batch)#>>'{rows,0,rowNumber}' IS DISTINCT FROM '503' THEN
    RAISE EXCEPTION 'mapped preview lost source positions or worksheet metadata';
  END IF;
END;
$test$;

-- Staff can explicitly create a distinct profile for a valid flagged row.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_cipher text := encode(convert_to('ECP1' || repeat('x', 32), 'UTF8'), 'base64');
  v_event uuid;
  v_batch uuid;
  v_input jsonb;
  v_result jsonb;
  v_before bigint;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  SELECT count(*) INTO v_before FROM eogp.persons WHERE organization_id=v_org AND first_name='Contact' AND last_name='Synthetic';
  IF v_before <> 1 THEN RAISE EXCEPTION 'distinct profile fixture is missing'; END IF;
  v_batch := (eogp.prepare_guest_import_preview(v_org,v_event,v_actor,repeat('0',64),jsonb_build_array(
    jsonb_build_object('rowNumber',2,'firstName','Contact','lastName','Synthetic','sourceCiphertext',v_cipher,
      'namesCiphertext',v_cipher,'errors','[]'::jsonb),
    jsonb_build_object('rowNumber',3,'firstName','Contact','lastName','Synthetic','sourceCiphertext',v_cipher,
      'namesCiphertext',v_cipher,'errors','["name_invalid"]'::jsonb)
  ))->>'batchId')::uuid;
  IF eogp.guest_import_commit_input(v_org,v_event,v_actor,v_batch) <> '[]'::jsonb
     OR jsonb_array_length(eogp.guest_import_commit_input(v_org,v_event,v_actor,v_batch,ARRAY[2])) <> 1 THEN
    RAISE EXCEPTION 'explicit distinct choice did not control staged value access';
  END IF;

  BEGIN
    PERFORM eogp.commit_reviewed_guest_import(v_org,v_event,v_actor,v_batch,'[]','[]',ARRAY[3]);
    RAISE EXCEPTION 'invalid row was accepted as a distinct profile';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  v_input := jsonb_build_array(jsonb_build_object('rowNumber',2,'namesCiphertext',v_cipher,
    'names','{"firstName":"Contact","lastName":"Synthetic","displayName":"Distinct Fixture"}'::jsonb));
  v_result := eogp.commit_reviewed_guest_import(v_org,v_event,v_actor,v_batch,v_input,'[]',ARRAY[2]);
  IF (v_result->>'importedCount') IS DISTINCT FROM '1'
    OR (SELECT count(*) FROM eogp.persons WHERE organization_id=v_org AND first_name='Contact' AND last_name='Synthetic') <> v_before + 1
    OR eogp.commit_reviewed_guest_import(v_org,v_event,v_actor,v_batch,'[]','[]',ARRAY[2]) <> v_result THEN
    RAISE EXCEPTION 'distinct profile did not create exactly one additional guest with a stable replay';
  END IF;
  BEGIN
    PERFORM eogp.commit_reviewed_guest_import(v_org,v_event,v_actor,v_batch,'[]','[]');
    RAISE EXCEPTION 'replay without the distinct choice was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
END;
$test$;

-- Profile updates use staged values, require review revisions and preserve an existing event snapshot.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_cipher text := encode(convert_to('ECP1' || repeat('x', 32), 'UTF8'), 'base64');
  v_event uuid;
  v_linked uuid;
  v_unlinked uuid;
  v_batch uuid;
  v_input jsonb;
  v_choices jsonb;
  v_preview jsonb;
  v_result jsonb;
  v_snapshot jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  v_linked := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Review","lastName":"Linked","displayName":"Pinned Name","preferredName":"Keep This"}')->>'personId')::uuid;
  v_unlinked := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Review","lastName":"Unlinked","displayName":"Old Name"}')->>'personId')::uuid;
  PERFORM eogp.link_registry_person_to_event(v_org,v_event,v_actor,v_linked,'eligible');
  SELECT person_identity_snapshot INTO STRICT v_snapshot FROM eogp.event_participations
    WHERE organization_id=v_org AND event_id=v_event AND person_id=v_linked;
  v_batch := (eogp.prepare_guest_import_preview(v_org,v_event,v_actor,repeat('1',64),jsonb_build_array(
    jsonb_build_object('rowNumber',2,'firstName','Review','lastName','Linked',
      'sourceCiphertext',v_cipher,'namesCiphertext',v_cipher,'errors','[]'::jsonb),
    jsonb_build_object('rowNumber',3,'firstName','Review','lastName','Unlinked',
      'sourceCiphertext',v_cipher,'namesCiphertext',v_cipher,'errors','[]'::jsonb)
  ))->>'batchId')::uuid;
  v_preview := eogp.read_guest_import_preview(v_org,v_event,v_actor,v_batch);
  IF v_preview#>'{rows,0,matches}' <> '[]'::jsonb
    OR NOT (v_preview#>'{rows,0,updateMatches,0}' @> jsonb_build_object('personId',v_linked,'onEvent',true))
    OR NOT (v_preview#>'{rows,1,updateMatches,0}' @> jsonb_build_object('personId',v_unlinked,'onEvent',false)) THEN
    RAISE EXCEPTION 'update preview did not distinguish existing participation from a new link';
  END IF;
  v_input := jsonb_build_array(
    jsonb_build_object('rowNumber',2,'namesCiphertext',v_cipher,
      'names','{"firstName":"Review","lastName":"Linked","displayName":"Current Name","preferredName":null}'::jsonb),
    jsonb_build_object('rowNumber',3,'namesCiphertext',v_cipher,
      'names','{"firstName":"Review","lastName":"Unlinked","displayName":"New Name"}'::jsonb)
  );
  v_choices := jsonb_build_array(
    jsonb_build_object('rowNumber',2,'personId',v_linked,'expectedRevision',1),
    jsonb_build_object('rowNumber',3,'personId',v_unlinked,'expectedRevision',2)
  );
  BEGIN
    PERFORM eogp.commit_reviewed_guest_import(v_org,v_event,v_actor,v_batch,v_input,'[]',ARRAY[]::integer[],v_choices);
    RAISE EXCEPTION 'stale update revision was accepted';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  IF NOT EXISTS (SELECT 1 FROM eogp.persons WHERE id=v_linked AND revision=1 AND display_name='Pinned Name') THEN
    RAISE EXCEPTION 'an earlier profile change survived a stale update';
  END IF;
  v_choices := jsonb_set(v_choices,'{1,expectedRevision}','1');
  v_result := eogp.commit_reviewed_guest_import(v_org,v_event,v_actor,v_batch,v_input,'[]',ARRAY[]::integer[],v_choices);
  IF v_result->>'importedCount' IS DISTINCT FROM '2'
    OR NOT EXISTS (SELECT 1 FROM eogp.persons WHERE id=v_linked AND revision=2 AND display_name='Current Name' AND preferred_name='Keep This')
    OR NOT EXISTS (SELECT 1 FROM eogp.event_participations WHERE organization_id=v_org AND event_id=v_event
      AND person_id=v_linked AND person_identity_snapshot=v_snapshot)
    OR NOT EXISTS (SELECT 1 FROM eogp.event_participations WHERE organization_id=v_org AND event_id=v_event
      AND person_id=v_unlinked AND person_identity_snapshot->>'displayName'='New Name')
    OR (SELECT count(*) FROM jsonb_array_elements(eogp.read_guest_import_report(v_org,v_event,v_actor,v_batch)->'rows') row
      WHERE row->>'outcome'='updated') <> 2
    OR eogp.commit_reviewed_guest_import(v_org,v_event,v_actor,v_batch,'[]','[]',ARRAY[]::integer[],v_choices) <> v_result THEN
    RAISE EXCEPTION 'reviewed profile updates or their outcome report were incorrect';
  END IF;
END;
$test$;

-- Group metadata changes are revision-checked, event-scoped and acyclic.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_event uuid;
  v_other_event uuid;
  v_root uuid;
  v_section uuid;
  v_leaf uuid;
  v_foreign uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  SELECT id INTO STRICT v_other_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-B';
  v_root := (eogp.write_event_guest_group(v_org,v_event,v_actor,NULL,'GROUP-ROOT','Root','organization',NULL)->>'groupId')::uuid;
  v_section := (eogp.write_event_guest_group(v_org,v_event,v_actor,NULL,'GROUP-SECTION','Section','delegation',v_root)->>'groupId')::uuid;
  v_leaf := (eogp.write_event_guest_group(v_org,v_event,v_actor,NULL,'GROUP-LEAF','Leaf','team',v_section)->>'groupId')::uuid;
  v_foreign := (eogp.write_event_guest_group(v_org,v_other_event,v_actor,NULL,'GROUP-OTHER','Other')->>'groupId')::uuid;
  BEGIN
    PERFORM eogp.update_event_guest_group(v_org,v_event,v_actor,v_root,1,'Root',NULL,v_leaf);
    RAISE EXCEPTION 'group parent cycle was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  BEGIN
    PERFORM eogp.update_event_guest_group(v_org,v_event,v_actor,v_section,1,'Section',NULL,v_foreign);
    RAISE EXCEPTION 'foreign event parent was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  PERFORM eogp.write_event_guest_group(v_org,v_event,v_actor,v_root,NULL,NULL);
  BEGIN
    PERFORM eogp.update_event_guest_group(v_org,v_event,v_actor,v_leaf,1,'Leaf',NULL,v_root);
    RAISE EXCEPTION 'a retired group was accepted as a new parent';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  v_result := eogp.update_event_guest_group(v_org,v_event,v_actor,v_section,1,'Section renamed',NULL,v_root);
  IF NOT v_result @> jsonb_build_object('parentGroupId',v_root,'kind','delegation','revision',2,'code','GROUP-SECTION') THEN
    RAISE EXCEPTION 'group metadata was not preserved through the retained parent';
  END IF;
  BEGIN
    PERFORM eogp.update_event_guest_group(v_org,v_event,v_actor,v_section,1,'Stale',NULL,NULL);
    RAISE EXCEPTION 'stale group revision was accepted';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  PERFORM eogp.update_event_guest_group(v_org,v_event,v_actor,v_section,2,'Section renamed','official_party',NULL);
  IF NOT eogp.list_event_guest_groups(v_org,v_event,v_actor) @> jsonb_build_array(
    jsonb_build_object('groupId',v_section,'parentGroupId',NULL,'kind','official_party','revision',3),
    jsonb_build_object('groupId',v_leaf,'parentGroupId',v_section)) THEN
    RAISE EXCEPTION 'reparenting did not preserve the child group';
  END IF;
END;
$test$;

-- Closed event records stay attached to their original participation and remain permission-filtered after a merge.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_event uuid;
  v_source uuid;
  v_destination uuid;
  v_overlap uuid;
  v_participation uuid;
  v_unlinked_review uuid;
  v_review jsonb;
  v_merge uuid;
  v_user uuid;
  v_member uuid;
  v_role uuid;
BEGIN
  v_event := (eogp.create_organizer_event(v_org,v_actor,'CI-HIST-MERGE','Historical merge fixture',NULL,
    '2031-01-18 09:00:00+00','2031-01-18 12:00:00+00','Europe/Sarajevo','{}','{}')->>'eventId')::uuid;
  PERFORM eogp.enable_event_guest_registry(v_org,v_event,v_actor);
  v_source := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Historical","lastName":"Source","displayName":"Original badge"}')->>'personId')::uuid;
  v_destination := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Historical","lastName":"Kept"}')->>'personId')::uuid;
  v_overlap := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Historical","lastName":"Overlap"}')->>'personId')::uuid;
  v_unlinked_review := (eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination)->>'reviewId')::uuid;
  v_participation := (eogp.link_registry_person_to_event(v_org,v_event,v_actor,v_source,'eligible')->>'participationId')::uuid;
  PERFORM eogp.link_registry_person_to_event(v_org,v_event,v_actor,v_overlap,'eligible');
  UPDATE eogp.events SET status='completed' WHERE organization_id=v_org AND id=v_event;
  IF eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_overlap)->>'blocker' IS DISTINCT FROM 'event_history_overlap' THEN
    RAISE EXCEPTION 'merge preview accepted overlapping event history';
  END IF;
  BEGIN
    PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,1,1,'duplicate_profile',v_unlinked_review);
    RAISE EXCEPTION 'review still permitted a merge after the participation set changed';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;

  INSERT INTO eogp.users (email,display_name) VALUES ('merge-reviewer@example.invalid','Merge Reviewer') RETURNING id INTO v_user;
  INSERT INTO eogp.organization_memberships (organization_id,user_id) VALUES (v_org,v_user) RETURNING id INTO v_member;
  INSERT INTO eogp.roles(organization_id,code,name,scope_kind) VALUES (v_org,'MERGE-REVIEWER','Merge Reviewer','organization') RETURNING id INTO v_role;
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
    VALUES (v_org,v_role,'guest.registry.read'),(v_org,v_role,'guest.registry.manage'),(v_org,v_role,'guest.registry.merge');
  INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id)
    VALUES (v_org,v_member,v_role,'organization',v_actor);
  PERFORM set_config('app.actor_membership_id',v_member::text,true);
  v_review := eogp.preview_guest_registry_merge(v_org,v_member,v_source,v_destination);
  IF v_review->>'blocker' IS DISTINCT FROM 'event_history_access_required'
    OR v_review->'historicalEvents' IS DISTINCT FROM '[]'::jsonb THEN
    RAISE EXCEPTION 'a Registry-only reviewer accessed linked event details';
  END IF;
  PERFORM set_config('app.actor_membership_id',v_actor::text,true);

  v_review := eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
  IF v_review->'blocker' IS DISTINCT FROM 'null'::jsonb
    OR v_review->>'historicalCount' IS DISTINCT FROM '1'
    OR v_review#>>'{historicalEvents,0,eventId}' IS DISTINCT FROM v_event::text THEN
    RAISE EXCEPTION 'closed event was missing from the merge review';
  END IF;
  v_merge := (eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,1,1,'duplicate_profile',
    (v_review->>'reviewId')::uuid)->>'mergeId')::uuid;
  IF NOT (eogp.read_guest_registry_history(v_org,v_actor,v_destination,0)->'participations') @> jsonb_build_array(
      jsonb_build_object('participationId',v_participation,'fromMergedProfile',true,'canManage',false))
    OR NOT EXISTS (SELECT 1 FROM eogp.event_participations WHERE organization_id=v_org AND id=v_participation
      AND person_id=v_source AND person_identity_snapshot->>'displayName'='Original badge')
    OR eogp.preview_guest_registry_merge(v_org,v_actor,v_overlap,v_destination)->>'blocker' IS DISTINCT FROM 'event_history_overlap' THEN
    RAISE EXCEPTION 'merged history changed the original event record or allowed an overlap';
  END IF;

  PERFORM set_config('app.actor_membership_id',v_member::text,true);
  IF eogp.read_guest_registry_history(v_org,v_member,v_destination,0)->'participations' <> '[]'::jsonb THEN
    RAISE EXCEPTION 'merged history bypassed event permissions';
  END IF;
  PERFORM set_config('app.actor_membership_id',v_actor::text,true);
  PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);
  IF eogp.read_guest_registry_history(v_org,v_actor,v_destination,0)->'participations' <> '[]'::jsonb
    OR NOT (eogp.read_guest_registry_history(v_org,v_actor,v_source,0)->'participations') @> jsonb_build_array(
      jsonb_build_object('participationId',v_participation,'fromMergedProfile',false)) THEN
    RAISE EXCEPTION 'restored source history was not independent of the destination';
  END IF;
END;
$test$;

-- Source references use a protected namespace and a profile revision, with uniqueness by organization and source.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_cipher bytea := convert_to('ECP1' || repeat('x',32),'UTF8');
  v_person uuid;
  v_other uuid;
  v_reference uuid;
  v_result jsonb;
BEGIN
  v_person := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Synthetic","lastName":"Reference"}')->>'personId')::uuid;
  v_other := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Other","lastName":"Reference"}')->>'personId')::uuid;
  BEGIN
    PERFORM eogp.read_guest_registry_references(v_org,v_actor,v_person);
    RAISE EXCEPTION 'registry permission exposed source references';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
    SELECT v_org,id,'guest.registry.references.read' FROM eogp.roles WHERE organization_id=v_org AND code='CI-REGISTRY';
  IF eogp.read_guest_registry_references(v_org,v_actor,v_person)->>'canManage' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'a reference read grant implied write access';
  END IF;
  BEGIN
    PERFORM eogp.write_guest_registry_reference(v_org,v_actor,v_person,NULL,1,'add','CRM',repeat('a',64),v_cipher);
    RAISE EXCEPTION 'a read-only actor saved a reference';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
    SELECT v_org,id,'guest.registry.references.manage' FROM eogp.roles WHERE organization_id=v_org AND code='CI-REGISTRY';

  v_result := eogp.write_guest_registry_reference(v_org,v_actor,v_person,NULL,1,'add','CRM',repeat('a',64),v_cipher);
  v_reference := (v_result->>'referenceId')::uuid;
  IF v_result->>'profileRevision' IS DISTINCT FROM '2' OR v_result ? 'ciphertext'
    OR eogp.read_guest_registry_references(v_org,v_actor,v_person)#>>'{references,0,source}' IS DISTINCT FROM 'CRM'
    OR has_table_privilege('eventor_runtime','eogp.person_identifiers','SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'reference mutation exposed protected data or failed to update the profile revision';
  END IF;
  BEGIN
    PERFORM eogp.write_guest_registry_reference(v_org,v_actor,v_other,NULL,1,'add','CRM',repeat('a',64),v_cipher);
    RAISE EXCEPTION 'a reference could identify two people in the same source';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  PERFORM eogp.write_guest_registry_reference(v_org,v_actor,v_other,NULL,1,'add','ERP',repeat('a',64),v_cipher);
  BEGIN
    PERFORM eogp.write_guest_registry_reference(v_org,v_actor,v_person,v_reference,1,'replace','CRM',repeat('b',64),v_cipher);
    RAISE EXCEPTION 'a stale reference edit committed';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  PERFORM eogp.write_guest_registry_reference(v_org,v_actor,v_person,v_reference,2,'replace','CRM',repeat('b',64),v_cipher);
  PERFORM eogp.write_guest_registry_reference(v_org,v_actor,v_person,v_reference,3,'remove',NULL,NULL,NULL);
  IF eogp.read_guest_registry_references(v_org,v_actor,v_person)->'references' <> '[]'::jsonb
    OR EXISTS (SELECT 1 FROM eogp.person_identifiers WHERE organization_id=v_org AND id=v_reference)
    OR NOT EXISTS (SELECT 1 FROM eogp.audit_events WHERE organization_id=v_org AND aggregate_id=v_person
        AND action='guest.registry.reference.remove'
        AND safe_metadata=jsonb_build_object('referenceId',v_reference,'revision',4)) THEN
    RAISE EXCEPTION 'removing a reference retained its value or missed the audit event';
  END IF;
END;
$test$;

-- Reference matching uses the selected namespace, rechecks reference ownership and never creates an unmatched profile.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_cipher bytea := convert_to('ECP1' || repeat('x',32),'UTF8');
  v_event uuid;
  v_person uuid;
  v_reference uuid;
  v_batch uuid;
  v_rows jsonb;
  v_preview jsonb;
  v_choices jsonb;
  v_result jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  v_person := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Registry","lastName":"Reference Match"}')->>'personId')::uuid;
  v_reference := (eogp.write_guest_registry_reference(v_org,v_actor,v_person,NULL,1,'add','CRM',repeat('0',64),v_cipher)
    ->>'referenceId')::uuid;
  v_rows := jsonb_build_array(
    jsonb_build_object('rowNumber',2,'firstName','Different','lastName','Source Name','referenceFingerprint',repeat('0',64),
      'sourceCiphertext',encode(v_cipher,'base64'),'namesCiphertext',encode(v_cipher,'base64'),'errors','[]'::jsonb),
    jsonb_build_object('rowNumber',3,'firstName','Unmatched','lastName','Source Name','referenceFingerprint',repeat('1',64),
      'sourceCiphertext',encode(v_cipher,'base64'),'namesCiphertext',encode(v_cipher,'base64'),'errors','[]'::jsonb)
  );
  v_batch := (eogp.prepare_reference_guest_import_preview(v_org,v_event,v_actor,repeat('c',64),v_rows,
    '{"firstName":1,"lastName":2}',NULL,NULL,'CRM',3)->>'batchId')::uuid;
  v_preview := eogp.read_guest_import_preview(v_org,v_event,v_actor,v_batch);
  IF v_preview->>'matchingSource' IS DISTINCT FROM 'CRM'
    OR v_preview#>>'{rows,0,matches,0,personId}' IS DISTINCT FROM v_person::text
    OR v_preview#>'{rows,1,errors}' IS DISTINCT FROM '["reference_unmatched"]'::jsonb
    OR eogp.guest_import_commit_input(v_org,v_event,v_actor,v_batch) <> '[]'::jsonb THEN
    RAISE EXCEPTION 'reference strategy did not select an exact match or mark an unmatched row';
  END IF;
  BEGIN
    PERFORM eogp.commit_reviewed_guest_import(v_org,v_event,v_actor,v_batch,'[]','[]',ARRAY[2]);
    RAISE EXCEPTION 'creating a separate profile from a reference match unexpectedly succeeded';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;

  DELETE FROM eogp.role_permissions
  WHERE organization_id=v_org AND role_id=(SELECT id FROM eogp.roles WHERE organization_id=v_org AND code='CI-REGISTRY')
    AND permission_code IN ('guest.registry.references.read','guest.registry.references.manage');
  BEGIN
    PERFORM eogp.read_guest_import_report(v_org,v_event,v_actor,v_batch);
    RAISE EXCEPTION 'report remained available after reference grant was revoked';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
    SELECT v_org,id,permission FROM eogp.roles CROSS JOIN
      (VALUES ('guest.registry.references.read'),('guest.registry.references.manage')) AS grant_codes(permission)
    WHERE organization_id=v_org AND code='CI-REGISTRY';

  v_choices := jsonb_build_array(jsonb_build_object('rowNumber',2,'personId',v_person,'expectedRevision',2));
  v_result := eogp.commit_reviewed_guest_import(v_org,v_event,v_actor,v_batch,'[]',v_choices);
  IF v_result->>'importedCount' IS DISTINCT FROM '1' OR v_result->>'skippedCount' IS DISTINCT FROM '1'
    OR NOT EXISTS (SELECT 1 FROM eogp.event_participations
      WHERE organization_id=v_org AND event_id=v_event AND person_id=v_person
        AND person_identity_snapshot->>'firstName'='Registry') THEN
    RAISE EXCEPTION 'reference reuse did not preserve the existing person and names';
  END IF;

  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-B';
  v_batch := (eogp.prepare_reference_guest_import_preview(v_org,v_event,v_actor,repeat('d',64),v_rows,
    '{"firstName":1,"lastName":2}',1,1,'CRM',3)->>'batchId')::uuid;
  PERFORM eogp.write_guest_registry_reference(v_org,v_actor,v_person,v_reference,2,'replace','CRM',repeat('2',64),v_cipher);
  IF eogp.read_guest_import_preview(v_org,v_event,v_actor,v_batch)#>'{rows,0,matches}' IS DISTINCT FROM '[]'::jsonb THEN
    RAISE EXCEPTION 'preview still offers a destination after its matching reference changed';
  END IF;
  BEGIN
    PERFORM eogp.commit_reviewed_guest_import(v_org,v_event,v_actor,v_batch,'[]',v_choices);
    RAISE EXCEPTION 'commit accepted a reference no longer assigned to the reviewed person';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
END;
$test$;

-- Verification requires a distinct grant and records evidence without changing consent or storing the contact in audit metadata.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_cipher bytea := convert_to('ECP1' || repeat('v',32),'UTF8');
  v_person uuid;
  v_phone uuid;
  v_email uuid;
  v_result jsonb;
BEGIN
  v_person := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Verification","lastName":"Fixture"}')->>'personId')::uuid;
  v_phone := (eogp.write_guest_registry_contact(v_org,v_actor,v_person,NULL,NULL,'phone',repeat('9',64),v_cipher,
    'permitted',true)->>'contactId')::uuid;
  v_email := (eogp.write_guest_registry_contact(v_org,v_actor,v_person,NULL,NULL,'email',repeat('8',64),v_cipher,
    'unknown',false)->>'contactId')::uuid;
  IF eogp.read_guest_registry_contacts(v_org,v_actor,v_person)->>'canVerify' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'managing contact values implied verification access';
  END IF;
  BEGIN
    PERFORM eogp.set_guest_registry_contact_verification(v_org,v_actor,v_person,v_phone,1,'callback');
    RAISE EXCEPTION 'contact verification succeeded with ordinary contact management';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
    SELECT v_org,id,'guest.registry.contacts.verify' FROM eogp.roles WHERE organization_id=v_org AND code='CI-REGISTRY';

  BEGIN
    PERFORM eogp.set_guest_registry_contact_verification(v_org,v_actor,v_person,v_email,1,'callback');
    RAISE EXCEPTION 'an email contact was verified by callback';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  v_result := eogp.set_guest_registry_contact_verification(v_org,v_actor,v_person,v_phone,1,'callback');
  IF v_result IS DISTINCT FROM jsonb_build_object('contactId',v_phone,'revision',2,'verified',true)
    OR NOT EXISTS (SELECT 1 FROM eogp.person_contact_points WHERE organization_id=v_org AND id=v_phone
      AND verification_method='callback' AND verified_at IS NOT NULL AND verified_by_membership_id=v_actor
      AND encrypted_value=v_cipher AND contact_consent='permitted' AND is_primary)
    OR NOT EXISTS (SELECT 1 FROM eogp.audit_events WHERE organization_id=v_org AND aggregate_id=v_person
      AND action='guest.registry.contact_verified' AND safe_metadata=jsonb_build_object('contactId',v_phone,
        'kind','phone','method','callback','revision',2)) THEN
    RAISE EXCEPTION 'verification failed to record evidence or changed contact preferences';
  END IF;
  BEGIN
    PERFORM eogp.set_guest_registry_contact_verification(v_org,v_actor,v_person,v_phone,1,NULL);
    RAISE EXCEPTION 'stale verification revision was accepted';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  PERFORM eogp.write_guest_registry_contact(v_org,v_actor,v_person,v_phone,2,NULL,NULL,NULL,'withdrawn',false);
  PERFORM eogp.set_guest_registry_contact_verification(v_org,v_actor,v_person,v_phone,3,NULL);
  IF NOT EXISTS (SELECT 1 FROM eogp.person_contact_points WHERE organization_id=v_org AND id=v_phone
    AND NOT is_verified AND verified_at IS NULL AND contact_consent='withdrawn' AND revision=4) THEN
    RAISE EXCEPTION 'verification revocation did not preserve the withdrawal';
  END IF;
  BEGIN
    PERFORM eogp.set_guest_registry_contact_verification(v_org,v_actor,v_person,v_phone,4,'in_person');
    RAISE EXCEPTION 'a withdrawn contact was newly verified';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
END;
$test$;

-- Bulk tag edits share individual roster guards and roll back as one transaction.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_event uuid;
  v_person uuid;
  v_first uuid;
  v_second uuid;
  v_tag uuid;
  v_keep uuid;
  v_hidden uuid;
  v_selection jsonb;
  v_result jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  v_person := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Bulk Tag","lastName":"First Fixture"}')->>'personId')::uuid;
  v_first := (eogp.link_registry_person_to_event(v_org,v_event,v_actor,v_person,'eligible')->>'participationId')::uuid;
  v_person := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Bulk Tag","lastName":"Second Fixture"}')->>'personId')::uuid;
  v_second := (eogp.link_registry_person_to_event(v_org,v_event,v_actor,v_person,'waitlisted')->>'participationId')::uuid;
  v_tag := (eogp.write_event_guest_tag(v_org,v_event,v_actor,NULL,'BULK-TAG','Bulk tag fixture')->>'tagId')::uuid;
  v_keep := (eogp.write_event_guest_tag(v_org,v_event,v_actor,NULL,'BULK-KEEP','Keep this tag')->>'tagId')::uuid;
  INSERT INTO eogp.guest_tags(organization_id,event_id,tag_code,label,sensitivity)
    VALUES (v_org,v_event,'BULK-HIDDEN','Restricted fixture','restricted') RETURNING id INTO v_hidden;
  INSERT INTO eogp.event_participation_tags(organization_id,event_id,participation_id,tag_id,added_by_membership_id)
    VALUES (v_org,v_event,v_first,v_hidden,v_actor);
  PERFORM eogp.set_event_guest_tags(v_org,v_event,v_actor,v_first,1,ARRAY[v_keep]);

  -- The later sorted participant is stale so the earlier write must roll back.
  SELECT jsonb_agg(jsonb_build_object('participationId',guest.id,
    'expectedRevision', CASE WHEN guest.id=greatest(v_first,v_second) THEN guest.revision+1 ELSE guest.revision END))
  INTO v_selection FROM eogp.event_participations guest WHERE guest.id IN (v_first,v_second);
  BEGIN
    PERFORM eogp.set_event_guest_bulk_tag(v_org,v_event,v_actor,v_tag,'add',v_selection);
    RAISE EXCEPTION 'stale bulk tag selection was accepted';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  IF EXISTS (SELECT 1 FROM eogp.event_participation_tags WHERE organization_id=v_org AND event_id=v_event AND tag_id=v_tag) THEN
    RAISE EXCEPTION 'earlier bulk tag edit survived the failed batch';
  END IF;

  v_selection := jsonb_build_array(jsonb_build_object('participationId',v_first,'expectedRevision',2),
    jsonb_build_object('participationId',v_second,'expectedRevision',1));
  v_result := eogp.set_event_guest_bulk_tag(v_org,v_event,v_actor,v_tag,'add',v_selection);
  IF v_result <> '{"processedCount":2,"updatedCount":2}'::jsonb
    OR (SELECT count(*) FROM eogp.event_participation_tags WHERE organization_id=v_org AND event_id=v_event AND tag_id=v_tag) <> 2 THEN
    RAISE EXCEPTION 'bulk tag did not update both guests';
  END IF;
  PERFORM eogp.write_event_guest_tag(v_org,v_event,v_actor,v_tag,NULL,NULL);
  v_selection := jsonb_build_array(jsonb_build_object('participationId',v_first,'expectedRevision',3),
    jsonb_build_object('participationId',v_second,'expectedRevision',2));
  BEGIN
    PERFORM eogp.set_event_guest_bulk_tag(v_org,v_event,v_actor,v_tag,'add',v_selection);
    RAISE EXCEPTION 'bulk add accepted a retired tag';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  v_result := eogp.set_event_guest_bulk_tag(v_org,v_event,v_actor,v_tag,'remove',v_selection);
  IF v_result <> '{"processedCount":2,"updatedCount":2}'::jsonb
    OR EXISTS (SELECT 1 FROM eogp.event_participation_tags WHERE organization_id=v_org AND event_id=v_event AND tag_id=v_tag)
    OR (SELECT count(*) FROM eogp.event_participation_tags WHERE organization_id=v_org AND event_id=v_event
      AND participation_id=v_first AND tag_id IN (v_keep,v_hidden)) <> 2 THEN
    RAISE EXCEPTION 'bulk removal changed an unrelated tag or retained the requested tag';
  END IF;
END;
$test$;

-- A restricted tag requires its own event grant and remains absent from ordinary rosters and tag commands.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_cipher bytea := convert_to('ECP1' || repeat('r',32),'UTF8');
  v_event uuid;
  v_other_event uuid;
  v_person uuid;
  v_guest uuid;
  v_restricted uuid := gen_random_uuid();
  v_internal uuid;
  v_role uuid := gen_random_uuid();
  v_view jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  SELECT id INTO STRICT v_other_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-B';
  v_person := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Restricted","lastName":"Tag Fixture"}')->>'personId')::uuid;
  v_guest := (eogp.link_registry_person_to_event(v_org,v_event,v_actor,v_person,'eligible')->>'participationId')::uuid;
  BEGIN
    PERFORM eogp.write_restricted_event_guest_tag(v_org,v_event,v_actor,v_restricted,'SHARED-CODE',v_cipher);
    RAISE EXCEPTION 'ordinary roster management created a restricted tag';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;

  INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(v_role,v_org,'CI-RESTRICTED-TAGS','Restricted Tags','event');
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code) VALUES(v_org,v_role,'guest.tags.restricted.read');
  INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,scope_event_id,granted_by_membership_id)
    VALUES(v_org,v_actor,v_role,'event',v_event,v_actor);
  IF eogp.read_restricted_event_guest_tags(v_org,v_event,v_actor,NULL)->>'canManage' IS DISTINCT FROM 'false'
    OR eogp.can_view_restricted_guest_tags(v_org,v_other_event,v_actor) THEN
    RAISE EXCEPTION 'restricted tag access crossed a role or event boundary';
  END IF;
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code) VALUES(v_org,v_role,'guest.tags.restricted.manage');

  PERFORM eogp.write_restricted_event_guest_tag(v_org,v_event,v_actor,v_restricted,'SHARED-CODE',v_cipher);
  v_internal := (eogp.write_event_guest_tag(v_org,v_event,v_actor,NULL,'SHARED-CODE','Visible label')->>'tagId')::uuid;
  PERFORM eogp.set_event_guest_tags(v_org,v_event,v_actor,v_guest,1,ARRAY[v_restricted],'restricted');
  PERFORM eogp.set_event_guest_tags(v_org,v_event,v_actor,v_guest,2,ARRAY[v_internal]);
  v_view := eogp.read_restricted_event_guest_tags(v_org,v_event,v_actor,v_guest);
  IF v_view->'assignedTagIds' IS DISTINCT FROM jsonb_build_array(v_restricted)
    OR NOT (v_view->'tags') @> jsonb_build_array(jsonb_build_object('tagId',v_restricted,'ciphertext',encode(v_cipher,'base64'),'legacyLabel',NULL))
    OR (eogp.list_event_guest_tags(v_org,v_event,v_actor) @> jsonb_build_array(jsonb_build_object('tagId',v_restricted)))
    OR NOT (eogp.read_event_guest_list(v_org,v_event,v_actor,NULL,0,NULL,false,'Restricted Tag Fixture')->'people')
      @> jsonb_build_array(jsonb_build_object('participationId',v_guest,'tagIds',ARRAY[v_internal]))
    OR NOT EXISTS (SELECT 1 FROM eogp.event_participation_tags WHERE organization_id=v_org AND participation_id=v_guest AND tag_id=v_restricted) THEN
    RAISE EXCEPTION 'restricted tags leaked into ordinary projections or lost their protected value';
  END IF;
  PERFORM eogp.write_restricted_event_guest_tag(v_org,v_event,v_actor,v_restricted,NULL,NULL);
  PERFORM eogp.set_event_guest_tags(v_org,v_event,v_actor,v_guest,3,ARRAY[]::uuid[],'restricted');
  IF NOT EXISTS (SELECT 1 FROM eogp.event_participation_tags WHERE organization_id=v_org AND participation_id=v_guest AND tag_id=v_internal)
    OR eogp.read_restricted_event_guest_tags(v_org,v_event,v_actor,v_guest)->'assignedTagIds' <> '[]'::jsonb THEN
    RAISE EXCEPTION 'restricted removal changed an ordinary tag';
  END IF;
  DELETE FROM eogp.role_permissions WHERE organization_id=v_org AND role_id=v_role;
  BEGIN
    PERFORM eogp.read_restricted_event_guest_tags(v_org,v_event,v_actor,v_guest);
    RAISE EXCEPTION 'ordinary roster management read a restricted tag';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$test$;

-- Registry relationships use their own grants and cannot cross organizations.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_source uuid;
  v_related uuid;
  v_foreign CONSTANT uuid := '52000000-0000-4000-8000-00000000000b';
  v_directed uuid;
  v_mutual uuid;
  v_view jsonb;
BEGIN
  v_source := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Relationship","lastName":"Source Fixture"}')->>'personId')::uuid;
  v_related := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Relationship","lastName":"Related Fixture"}')->>'personId')::uuid;
  BEGIN
    PERFORM eogp.read_guest_registry_relationships(v_org,v_actor,v_source);
    RAISE EXCEPTION 'ordinary Registry read exposed relationship history';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
    SELECT v_org,id,'guest.registry.relationships.read' FROM eogp.roles WHERE organization_id=v_org AND code='CI-REGISTRY';
  IF eogp.read_guest_registry_relationships(v_org,v_actor,v_source)->>'canManage' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'Registry relationship read grant implied write access';
  END IF;
  BEGIN
    PERFORM eogp.write_guest_registry_relationship(v_org,v_actor,v_source,NULL,v_related,'assistant','directed');
    RAISE EXCEPTION 'relationship creation accepted read-only permissions';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
    SELECT v_org,id,'guest.registry.relationships.manage' FROM eogp.roles WHERE organization_id=v_org AND code='CI-REGISTRY';
  BEGIN
    PERFORM eogp.write_guest_registry_relationship(v_org,v_actor,v_source,NULL,v_foreign,'assistant','directed');
    RAISE EXCEPTION 'relationship crossed the organization boundary';
  EXCEPTION WHEN no_data_found THEN NULL;
  END;
  v_directed := (eogp.write_guest_registry_relationship(v_org,v_actor,v_source,NULL,v_related,'assistant','directed')->>'relationshipId')::uuid;
  v_mutual := (eogp.write_guest_registry_relationship(v_org,v_actor,v_related,NULL,v_source,'family','mutual')->>'relationshipId')::uuid;
  BEGIN
    PERFORM eogp.write_guest_registry_relationship(v_org,v_actor,v_source,NULL,v_related,'family','mutual');
    RAISE EXCEPTION 'reversed duplicate mutual relationship was accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  v_view := eogp.read_guest_registry_relationships(v_org,v_actor,v_source);
  IF NOT (v_view->'relationships') @> jsonb_build_array(
      jsonb_build_object('relationshipId',v_directed,'direction','outgoing','relatedPersonId',v_related),
      jsonb_build_object('relationshipId',v_mutual,'direction','mutual','relatedPersonId',v_related))
    OR NOT (eogp.read_guest_registry_relationships(v_org,v_actor,v_related)->'relationships')
      @> jsonb_build_array(jsonb_build_object('relationshipId',v_directed,'direction','incoming','relatedPersonId',v_source))
    OR eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_related)->>'blocker' IS DISTINCT FROM 'source_has_linked_records'
    OR has_table_privilege('eventor_runtime','eogp.person_relationships','SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'relationship direction, permissions or merge guard was incorrect';
  END IF;
  PERFORM eogp.write_guest_registry_relationship(v_org,v_actor,v_related,v_directed,NULL,NULL,NULL);
  PERFORM eogp.write_guest_registry_relationship(v_org,v_actor,v_source,v_mutual,NULL,NULL,NULL);
  IF (SELECT count(*) FROM eogp.person_relationships WHERE organization_id=v_org
      AND id IN (v_directed,v_mutual) AND ended_at IS NOT NULL AND ended_by_membership_id=v_actor) <> 2
    OR eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_related)->'blocker' IS DISTINCT FROM 'null'::jsonb THEN
    RAISE EXCEPTION 'ending relationships lost history or left a stale merge blocker';
  END IF;
END;
$test$;

-- A blocked or stale profile rolls back a bulk archive; successful changes retain the existing profile audit.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_event uuid;
  v_first uuid;
  v_second uuid;
  v_third uuid;
  v_blocked uuid;
  v_independent uuid;
  v_selection jsonb;
  v_result jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  v_first := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Bulk Archive","lastName":"First Fixture"}')->>'personId')::uuid;
  v_second := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Bulk Archive","lastName":"Second Fixture"}')->>'personId')::uuid;
  v_third := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Bulk Archive","lastName":"Third Fixture"}')->>'personId')::uuid;

  -- Place the blocked record last in lock order to exercise rollback of an earlier change.
  v_blocked := greatest(v_first,v_second);
  v_independent := least(v_first,v_second);
  PERFORM eogp.link_registry_person_to_event(v_org,v_event,v_actor,v_blocked,'eligible');
  v_selection := jsonb_build_array(jsonb_build_object('personId',v_independent,'expectedRevision',1),
    jsonb_build_object('personId',v_blocked,'expectedRevision',1));
  BEGIN
    PERFORM eogp.archive_guest_registry_profiles(v_org,v_actor,v_selection);
    RAISE EXCEPTION 'bulk archive accepted a profile with outstanding event participation';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  IF NOT EXISTS (SELECT 1 FROM eogp.persons WHERE organization_id=v_org AND id=v_independent AND status='active' AND revision=1)
    OR EXISTS (SELECT 1 FROM eogp.audit_events WHERE organization_id=v_org AND aggregate_id=v_independent AND action='guest.registry.archive') THEN
    RAISE EXCEPTION 'an earlier archive survived the blocked batch';
  END IF;
  BEGIN
    PERFORM eogp.archive_guest_registry_profiles(v_org,v_actor,jsonb_set(v_selection,'{1,expectedRevision}','2'));
    RAISE EXCEPTION 'bulk archive accepted a stale revision';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;

  v_selection := jsonb_build_array(jsonb_build_object('personId',v_independent,'expectedRevision',1),
    jsonb_build_object('personId',v_third,'expectedRevision',1));
  v_result := eogp.archive_guest_registry_profiles(v_org,v_actor,v_selection);
  IF v_result IS DISTINCT FROM '{"archivedCount":2}'::jsonb
    OR (SELECT count(*) FROM eogp.persons WHERE organization_id=v_org AND id IN (v_independent,v_third)
        AND status='archived' AND revision=2) <> 2
    OR (SELECT count(*) FROM eogp.audit_events WHERE organization_id=v_org AND aggregate_id IN (v_independent,v_third)
        AND action='guest.registry.archive') <> 2 THEN
    RAISE EXCEPTION 'bulk archive missed a profile or audit record';
  END IF;
END;
$test$;

-- Roster membership filters apply to pagination, exports and personal views without using restricted tags.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_cipher bytea := convert_to('ECP1' || repeat('v',32),'UTF8');
  v_event uuid;
  v_person uuid;
  v_first uuid;
  v_second uuid;
  v_tag uuid;
  v_group uuid;
  v_restricted uuid;
  v_view uuid := gen_random_uuid();
  v_rows jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  v_person := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Filter","lastName":"One","displayName":"Filter One"}')->>'personId')::uuid;
  v_first := (eogp.link_registry_person_to_event(v_org,v_event,v_actor,v_person,'eligible')->>'participationId')::uuid;
  v_person := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Filter","lastName":"Two","displayName":"Filter Two"}')->>'personId')::uuid;
  v_second := (eogp.link_registry_person_to_event(v_org,v_event,v_actor,v_person,'eligible')->>'participationId')::uuid;
  v_tag := (eogp.write_event_guest_tag(v_org,v_event,v_actor,NULL,'FILTER-TAG','Tag filter fixture')->>'tagId')::uuid;
  v_group := (eogp.write_event_guest_group(v_org,v_event,v_actor,NULL,'FILTER-GROUP','Group filter fixture')->>'groupId')::uuid;
  PERFORM eogp.set_event_guest_tags(v_org,v_event,v_actor,v_first,1,ARRAY[v_tag]);
  PERFORM eogp.set_event_guest_groups(v_org,v_event,v_actor,v_first,2,ARRAY[v_group]);
  PERFORM eogp.set_event_guest_groups(v_org,v_event,v_actor,v_second,1,ARRAY[v_group]);
  INSERT INTO eogp.guest_tags(organization_id,event_id,tag_code,label,sensitivity)
    VALUES (v_org,v_event,'FILTER-RESTRICTED','Restricted filter fixture','restricted') RETURNING id INTO v_restricted;
  INSERT INTO eogp.event_participation_tags(organization_id,event_id,participation_id,tag_id,added_by_membership_id)
    VALUES (v_org,v_event,v_first,v_restricted,v_actor);

  v_rows := eogp.read_event_guest_list(v_org,v_event,v_actor,NULL,0,NULL,false,'Filter',v_tag,v_group)->'people';
  IF jsonb_array_length(v_rows) <> 1 OR v_rows#>>'{0,participationId}' IS DISTINCT FROM v_first::text
    OR (eogp.read_event_guest_roster_export(v_org,v_event,v_actor,NULL,NULL,false,'Filter',v_tag,v_group)->'people')
      IS DISTINCT FROM '[{"displayName":"Filter One","status":"eligible","categoryCode":null}]'::jsonb
    OR eogp.read_event_guest_list(v_org,v_event,v_actor,NULL,0,NULL,false,NULL,v_restricted,NULL)->'people' <> '[]'::jsonb THEN
    RAISE EXCEPTION 'tag and group filters did not preserve roster scope or export parity';
  END IF;
  PERFORM eogp.save_event_guest_view(v_org,v_event,v_actor,v_view,repeat('9',64),v_cipher,NULL,NULL,false,v_tag,v_group);
  IF NOT eogp.list_event_guest_saved_views(v_org,v_event,v_actor) @> jsonb_build_array(
    jsonb_build_object('viewId',v_view,'tagId',v_tag,'groupId',v_group)) THEN
    RAISE EXCEPTION 'saved view lost its membership filters';
  END IF;
  BEGIN
    PERFORM eogp.save_event_guest_view(v_org,v_event,v_actor,gen_random_uuid(),repeat('8',64),v_cipher,NULL,NULL,false,v_restricted,v_group);
    RAISE EXCEPTION 'saved view exposed a restricted tag as an ordinary filter';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
END;
$test$;

-- An unmatched source reference is created only by explicit review and in the same transaction as its profile and event link.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_cipher bytea := convert_to('ECP1' || repeat('x',32),'UTF8');
  v_encoded text := encode(v_cipher,'base64');
  v_event uuid;
  v_occupied uuid;
  v_late uuid;
  v_fresh uuid := gen_random_uuid();
  v_batch uuid;
  v_preview jsonb;
  v_rows jsonb;
  v_input jsonb;
  v_creates jsonb;
  v_result jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  v_occupied := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Archived","lastName":"Reference Owner"}')->>'personId')::uuid;
  PERFORM eogp.write_guest_registry_reference(v_org,v_actor,v_occupied,NULL,1,'add','NEWREF',repeat('1',64),v_cipher);
  PERFORM eogp.write_guest_registry_person(v_org,v_actor,v_occupied,2,'archive','{}');
  v_rows := jsonb_build_array(
    jsonb_build_object('rowNumber',2,'firstName','New','lastName','Reference Guest','referenceFingerprint',repeat('0',64),
      'sourceCiphertext',v_encoded,'namesCiphertext',v_encoded,'errors','[]'::jsonb),
    jsonb_build_object('rowNumber',3,'firstName','Archived','lastName','Reference Owner','referenceFingerprint',repeat('1',64),
      'sourceCiphertext',v_encoded,'namesCiphertext',v_encoded,'errors','[]'::jsonb),
    jsonb_build_object('rowNumber',4,'firstName','Late','lastName','Reference Owner','referenceFingerprint',repeat('2',64),
      'sourceCiphertext',v_encoded,'namesCiphertext',v_encoded,'errors','[]'::jsonb)
  );
  v_batch := (eogp.prepare_reference_guest_import_preview(v_org,v_event,v_actor,repeat('e',64),v_rows,
    '{"firstName":1,"lastName":2}',NULL,NULL,'NEWREF',3)->>'batchId')::uuid;
  v_preview := eogp.read_guest_import_preview(v_org,v_event,v_actor,v_batch);
  IF v_preview->>'canCreateReferences' IS DISTINCT FROM 'true'
    OR v_preview#>'{rows,0,errors}' IS DISTINCT FROM '["reference_unmatched"]'::jsonb
    OR v_preview#>'{rows,1,errors}' IS DISTINCT FROM '["reference_unavailable"]'::jsonb
    OR eogp.guest_import_commit_input(v_org,v_event,v_actor,v_batch) <> '[]'::jsonb
    OR jsonb_array_length(eogp.guest_import_commit_input(v_org,v_event,v_actor,v_batch,ARRAY[]::integer[],ARRAY[2])) <> 1 THEN
    RAISE EXCEPTION 'reference creation candidates did not match the preview and explicit choices';
  END IF;

  DELETE FROM eogp.role_permissions WHERE organization_id=v_org AND permission_code='guest.registry.references.manage'
    AND role_id=(SELECT id FROM eogp.roles WHERE organization_id=v_org AND code='CI-REGISTRY');
  IF eogp.read_guest_import_preview(v_org,v_event,v_actor,v_batch)->>'canCreateReferences' IS DISTINCT FROM 'false' THEN
    RAISE EXCEPTION 'read-only reference access enabled profile creation';
  END IF;
  BEGIN
    PERFORM eogp.guest_import_commit_input(v_org,v_event,v_actor,v_batch,ARRAY[]::integer[],ARRAY[2]);
    RAISE EXCEPTION 'reference management was not required for creation input';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
    SELECT v_org,id,'guest.registry.references.manage' FROM eogp.roles WHERE organization_id=v_org AND code='CI-REGISTRY';

  v_late := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Another","lastName":"Contact"}')->>'personId')::uuid;
  PERFORM eogp.write_guest_registry_reference(v_org,v_actor,v_late,NULL,1,'add','NEWREF',repeat('2',64),v_cipher);
  v_input := jsonb_build_array(jsonb_build_object('rowNumber',2,'namesCiphertext',v_encoded,
    'names','{"firstName":"New","lastName":"Reference Guest"}'::jsonb));
  v_creates := jsonb_build_array(jsonb_build_object('rowNumber',2,'personId',v_fresh,'fingerprint',repeat('0',64),'ciphertext',v_encoded));
  BEGIN
    PERFORM eogp.commit_reviewed_guest_import(v_org,v_event,v_actor,v_batch,
      v_input || jsonb_build_array(jsonb_build_object('rowNumber',4,'namesCiphertext',v_encoded,
        'names','{"firstName":"Late","lastName":"Reference Owner"}'::jsonb)), '[]',ARRAY[]::integer[],'[]',
      v_creates || jsonb_build_array(jsonb_build_object('rowNumber',4,'personId',gen_random_uuid(),
        'fingerprint',repeat('2',64),'ciphertext',v_encoded)));
    RAISE EXCEPTION 'commit accepted a reference assigned after preview';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  IF EXISTS (SELECT 1 FROM eogp.persons WHERE organization_id=v_org AND id=v_fresh) THEN
    RAISE EXCEPTION 'earlier reference creation persisted after the failed batch';
  END IF;
  v_result := eogp.commit_reviewed_guest_import(v_org,v_event,v_actor,v_batch,v_input,'[]',ARRAY[]::integer[],'[]',v_creates);
  IF v_result->>'importedCount' IS DISTINCT FROM '1'
    OR NOT EXISTS (SELECT 1 FROM eogp.person_identifiers WHERE organization_id=v_org AND person_id=v_fresh
      AND identifier_kind='external-ref-v1:NEWREF' AND encrypted_value=v_cipher)
    OR NOT EXISTS (SELECT 1 FROM eogp.event_participations WHERE organization_id=v_org AND event_id=v_event AND person_id=v_fresh)
    OR NOT (eogp.read_guest_import_report(v_org,v_event,v_actor,v_batch)->'rows')
      @> '[{"rowNumber":2,"outcome":"created","errors":[]}]'::jsonb
    OR eogp.commit_reviewed_guest_import(v_org,v_event,v_actor,v_batch,'[]','[]',ARRAY[]::integer[],'[]',
      '[{"rowNumber":2}]') <> v_result THEN
    RAISE EXCEPTION 'reference creation did not persist atomically or allow a stable replay';
  END IF;
END;
$test$;

-- A staff roster name is revision-checked and preserves the Registry and invitation identities.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_event uuid;
  v_other_event uuid;
  v_person uuid;
  v_guest uuid;
  v_other_guest uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  SELECT id INTO STRICT v_other_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-B';
  v_person := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Roster","lastName":"Fixture","displayName":"Pinned Staff Fixture"}')->>'personId')::uuid;
  v_guest := (eogp.link_registry_person_to_event(v_org,v_event,v_actor,v_person,'eligible')->>'participationId')::uuid;
  v_other_guest := (eogp.link_registry_person_to_event(v_org,v_other_event,v_actor,v_person,'eligible')->>'participationId')::uuid;
  PERFORM eogp.write_guest_registry_person(v_org,v_actor,v_person,1,'update','{"displayName":"Registry Current Fixture"}');

  v_result := eogp.set_event_guest_roster_name(v_org,v_event,v_actor,v_guest,1,'Staff Display Override');
  IF v_result->>'revision' IS DISTINCT FROM '2'
    OR NOT (eogp.read_event_guest_list(v_org,v_event,v_actor,NULL,0,NULL,false,'Staff Display Override')->'people')
      @> jsonb_build_array(jsonb_build_object('participationId',v_guest,'displayName','Staff Display Override',
        'recordedDisplayName','Pinned Staff Fixture','displayNameOverride','Staff Display Override'))
    OR (eogp.read_event_guest_roster_export(v_org,v_event,v_actor,NULL,NULL,false,'Staff Display Override')->'people')
      IS DISTINCT FROM '[{"displayName":"Staff Display Override","status":"eligible","categoryCode":null}]'::jsonb
    OR NOT eogp.list_guest_invitation_participations(v_org,v_event,v_actor) @> jsonb_build_array(
        jsonb_build_object('participationId',v_guest,'displayName','Pinned Staff Fixture'))
    OR NOT (eogp.read_event_guest_list(v_org,v_other_event,v_actor,NULL,0,NULL,false,'Pinned Staff Fixture')->'people')
      @> jsonb_build_array(jsonb_build_object('participationId',v_other_guest,'displayName','Pinned Staff Fixture','displayNameOverride',NULL))
    OR NOT EXISTS (SELECT 1 FROM eogp.persons WHERE organization_id=v_org AND id=v_person AND display_name='Registry Current Fixture') THEN
    RAISE EXCEPTION 'staff roster override changed a recorded profile or event identity';
  END IF;
  BEGIN
    PERFORM eogp.set_event_guest_roster_name(v_org,v_event,v_actor,v_guest,1,NULL);
    RAISE EXCEPTION 'stale roster name change was accepted';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  PERFORM eogp.set_event_guest_roster_name(v_org,v_event,v_actor,v_guest,2,NULL);
  IF NOT (eogp.read_event_guest_list(v_org,v_event,v_actor,NULL,0,NULL,false,'Pinned Staff Fixture')->'people')
    @> jsonb_build_array(jsonb_build_object('participationId',v_guest,'displayName','Pinned Staff Fixture','displayNameOverride',NULL))
    OR EXISTS (SELECT 1 FROM eogp.audit_events WHERE organization_id=v_org AND aggregate_id=v_guest
      AND action='guest.participation.roster_name_changed' AND safe_metadata::text LIKE '%Staff Display Override%') THEN
    RAISE EXCEPTION 'clearing roster names missed the original name or leaked it into audit';
  END IF;
END;
$test$;

-- Placement preferences are optional, revision-checked and retained by older group updates.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_event uuid;
  v_group uuid;
  v_result jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  v_result := eogp.write_event_guest_group(v_org,v_event,v_actor,NULL,'PLACEMENT','Placement group','team',NULL,'same_table',12);
  v_group := (v_result->>'groupId')::uuid;
  IF v_result->>'placementPreference' IS DISTINCT FROM 'same_table' OR v_result->>'expectedSize' IS DISTINCT FROM '12' THEN
    RAISE EXCEPTION 'group creation omitted placement preferences';
  END IF;
  v_result := eogp.update_event_guest_group(v_org,v_event,v_actor,v_group,1,'Renamed group',NULL,NULL);
  IF v_result->>'placementPreference' IS DISTINCT FROM 'same_table' OR v_result->>'expectedSize' IS DISTINCT FROM '12' THEN
    RAISE EXCEPTION 'legacy group update cleared placement preferences';
  END IF;
  BEGIN
    PERFORM eogp.update_event_guest_group(v_org,v_event,v_actor,v_group,1,'Stale group',NULL,NULL,'{"expectedSize":14}');
    RAISE EXCEPTION 'stale group placement update was accepted';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  PERFORM eogp.update_event_guest_group(v_org,v_event,v_actor,v_group,2,'Renamed group',NULL,NULL,
    '{"placementPreference":"nearby","expectedSize":null}');
  IF NOT eogp.list_event_guest_groups(v_org,v_event,v_actor) @> jsonb_build_array(
    jsonb_build_object('groupId',v_group,'placementPreference','nearby','expectedSize',NULL,'revision',3)) THEN
    RAISE EXCEPTION 'group placement edit or expected size clear did not persist';
  END IF;
END;
$test$;

-- Placement rules preserve pair symmetry, explicit scope/priority and retirement history.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_event uuid;
  v_other uuid;
  v_first uuid;
  v_second uuid;
  v_foreign uuid;
  v_rule uuid;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  SELECT id INTO STRICT v_other FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-B';
  v_first := (eogp.write_event_guest_group(v_org,v_event,v_actor,NULL,'GROUP-RULE-1','Rule group A')->>'groupId')::uuid;
  v_second := (eogp.write_event_guest_group(v_org,v_event,v_actor,NULL,'GROUP-RULE-2','Rule group B')->>'groupId')::uuid;
  v_foreign := (eogp.write_event_guest_group(v_org,v_other,v_actor,NULL,'GROUP-RULE-3','Rule group C')->>'groupId')::uuid;
  BEGIN
    PERFORM eogp.write_guest_group_placement_rule(v_org,v_event,v_actor,NULL,v_first,v_foreign,'zone','apart','required');
    RAISE EXCEPTION 'placement accepted a group from another event';
  EXCEPTION WHEN no_data_found THEN NULL;
  END;
  v_rule := (eogp.write_guest_group_placement_rule(v_org,v_event,v_actor,NULL,v_second,v_first,'zone','apart','required')->>'ruleId')::uuid;
  BEGIN
    PERFORM eogp.write_guest_group_placement_rule(v_org,v_event,v_actor,NULL,v_first,v_second,'zone','together','preferred');
    RAISE EXCEPTION 'conflicting rule for the same group pair and scope was accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
  IF NOT (eogp.read_guest_group_placement_rules(v_org,v_event,v_actor)->'rules') @> jsonb_build_array(
      jsonb_build_object('ruleId',v_rule,'firstGroupId',least(v_first,v_second),'secondGroupId',greatest(v_first,v_second),
        'scope','zone','condition','apart','priority','required','applicable',true))
    OR eogp.read_guest_group_placement_rules(v_org,v_other,v_actor)->'rules' <> '[]'::jsonb
    OR has_table_privilege('eventor_runtime','eogp.guest_group_placement_rules','SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'placement projection lost its scope, priority or authorization boundary';
  END IF;
  PERFORM eogp.write_event_guest_group(v_org,v_event,v_actor,v_second,NULL,NULL);
  IF NOT (eogp.read_guest_group_placement_rules(v_org,v_event,v_actor)->'rules') @> jsonb_build_array(
    jsonb_build_object('ruleId',v_rule,'applicable',false,'retiredAt',NULL)) THEN
    RAISE EXCEPTION 'a rule for a retired group remained applicable';
  END IF;
  PERFORM eogp.write_guest_group_placement_rule(v_org,v_event,v_actor,v_rule,NULL,NULL,NULL,NULL,NULL);
  IF NOT EXISTS (SELECT 1 FROM eogp.guest_group_placement_rules WHERE organization_id=v_org AND id=v_rule
    AND retired_at IS NOT NULL AND retired_by_membership_id=v_actor) THEN
    RAISE EXCEPTION 'placement rule retirement lost history';
  END IF;
END;
$test$;

-- Event notes use distinct grants and preserve withdrawal history without projecting content.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_cipher CONSTANT bytea := convert_to('ECP1' || repeat('n',32),'UTF8');
  v_event uuid;
  v_other uuid;
  v_person uuid;
  v_guest uuid;
  v_note uuid := gen_random_uuid();
  v_role uuid := gen_random_uuid();
  v_result jsonb;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  SELECT id INTO STRICT v_other FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-B';
  v_person := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Staff","lastName":"Note Fixture"}')->>'personId')::uuid;
  v_guest := (eogp.link_registry_person_to_event(v_org,v_event,v_actor,v_person,'eligible')->>'participationId')::uuid;
  BEGIN
    PERFORM eogp.read_event_guest_notes(v_org,v_event,v_actor,v_guest,0);
    RAISE EXCEPTION 'ordinary roster management read staff notes';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(v_role,v_org,'CI-GUEST-NOTES','Staff Notes','event');
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code) VALUES(v_org,v_role,'guest.notes.read');
  INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,scope_event_id,granted_by_membership_id)
    VALUES(v_org,v_actor,v_role,'event',v_event,v_actor);
  BEGIN
    PERFORM eogp.write_event_guest_note(v_org,v_event,v_actor,v_guest,v_note,v_cipher);
    RAISE EXCEPTION 'read-only staff notes grant allowed creation';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  IF eogp.read_event_guest_notes(v_org,v_event,v_actor,v_guest,0)->>'canManage' IS DISTINCT FROM 'false'
    OR eogp.can_view_event_guest_notes(v_org,v_other,v_actor)
    OR has_table_privilege('eventor_runtime','eogp.guest_notes','SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'staff note access crossed permission or event boundaries';
  END IF;

  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code) VALUES(v_org,v_role,'guest.notes.manage');
  INSERT INTO eogp.guest_notes(organization_id,event_id,participation_id,note_ciphertext,created_by_membership_id)
    VALUES(v_org,v_event,v_guest,v_cipher,v_actor);
  v_result := eogp.write_event_guest_note(v_org,v_event,v_actor,v_guest,v_note,v_cipher);
  IF v_result->>'noteId' IS DISTINCT FROM v_note::text OR v_result ?| array['ciphertext','text'] THEN
    RAISE EXCEPTION 'staff note mutation omitted the ID or included note content';
  END IF;
  v_result := eogp.read_event_guest_notes(v_org,v_event,v_actor,v_guest,0);
  IF jsonb_array_length(v_result->'notes') IS DISTINCT FROM 1
    OR v_result#>>'{notes,0,ciphertext}' IS DISTINCT FROM encode(v_cipher,'base64') THEN
    RAISE EXCEPTION 'staff note projection missed the encrypted envelope or included a legacy row';
  END IF;
  PERFORM eogp.write_event_guest_note(v_org,v_event,v_actor,v_guest,v_note,NULL);
  v_result := eogp.read_event_guest_notes(v_org,v_event,v_actor,v_guest,0);
  IF v_result#>'{notes,0,ciphertext}' IS DISTINCT FROM 'null'::jsonb OR v_result#>>'{notes,0,withdrawnAt}' IS NULL
    OR NOT EXISTS (SELECT 1 FROM eogp.guest_notes WHERE id=v_note AND withdrawn_by_membership_id=v_actor AND note_ciphertext=v_cipher)
    OR (SELECT count(*) FROM eogp.audit_events WHERE organization_id=v_org AND aggregate_id=v_note
      AND action IN ('guest.note.recorded','guest.note.withdrawn')
      AND safe_metadata=jsonb_build_object('eventId',v_event,'participationId',v_guest)) <> 2 THEN
    RAISE EXCEPTION 'staff note withdrawal lost history or projected withdrawn content';
  END IF;
END;
$test$;

-- Guest references are immutable, event-scoped and available in roster and export searches.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_event uuid;
  v_other uuid;
  v_person uuid;
  v_guest uuid;
  v_reference text;
  v_other_reference text;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  SELECT id INTO STRICT v_other FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-B';
  v_person := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',
    '{"firstName":"Reference","lastName":"Fixture"}')->>'personId')::uuid;
  v_guest := (eogp.link_registry_person_to_event(v_org,v_event,v_actor,v_person,'eligible')->>'participationId')::uuid;
  PERFORM eogp.link_registry_person_to_event(v_org,v_other,v_actor,v_person,'waitlisted');
  SELECT participation_code INTO STRICT v_reference FROM eogp.event_participations WHERE organization_id=v_org AND id=v_guest;
  SELECT participation_code INTO STRICT v_other_reference FROM eogp.event_participations
    WHERE organization_id=v_org AND event_id=v_other AND person_id=v_person;
  BEGIN
    UPDATE eogp.event_participations SET participation_code='REPLACED' WHERE organization_id=v_org AND id=v_guest;
    RAISE EXCEPTION 'changing the guest reference was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
  IF v_reference !~ '^G-[0-9]{6,}$' OR v_other_reference !~ '^G-[0-9]{6,}$'
    OR jsonb_array_length(eogp.read_event_guest_list(v_org,v_event,v_actor,NULL,0,NULL,false,lower(v_reference))->'people') <> 1
    OR NOT (eogp.read_event_guest_list(v_org,v_event,v_actor,NULL,0,NULL,false,lower(v_reference))->'people')
       @> jsonb_build_array(jsonb_build_object('participationId',v_guest,'participationCode',v_reference))
    OR eogp.read_event_guest_roster_export(v_org,v_event,v_actor,NULL,NULL,false,lower(v_reference))->'people'
       IS DISTINCT FROM '[{"displayName":"Reference Fixture","status":"eligible","categoryCode":null}]'::jsonb
    OR EXISTS (SELECT 1 FROM eogp.event_participations WHERE organization_id=v_org AND event_id=v_event
      AND id<>v_guest AND lower(btrim(participation_code))=lower(v_reference))
    OR has_table_privilege('eventor_runtime','eogp.event_guest_reference_counters','SELECT,INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'guest reference generation, filtering or authorization failed';
  END IF;
END;
$test$;

-- Organization access is available only to an organization-wide manager.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_other_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000b';
  v_role uuid := gen_random_uuid();
  v_event uuid;
  v_grant uuid := gen_random_uuid();
  v_result jsonb;
BEGIN
  PERFORM set_config('app.organization_id',v_org::text,true);
  PERFORM set_config('app.actor_membership_id',v_actor::text,true);
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(v_role,v_org,'CI-ACCESS-ADMIN','CI Access Admin','organization');
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code) VALUES(v_org,v_role,'organization.manage');
  INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,scope_event_id,granted_by_membership_id)
    VALUES(v_org,v_actor,v_role,'event',v_event,v_actor);
  BEGIN
    PERFORM eogp.list_organization_access_roles(v_org,v_actor);
    RAISE EXCEPTION 'an event-level grant read the organization catalogue';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  INSERT INTO eogp.user_role_grants(id,organization_id,membership_id,role_id,scope_kind,granted_by_membership_id)
    VALUES(v_grant,v_org,v_actor,v_role,'organization',v_actor);
  PERFORM eogp.assert_staff_event_replay_permission(v_org,NULL,v_actor,'organization.manage');
  BEGIN
    PERFORM eogp.assert_staff_event_replay_permission(v_org,v_event,v_actor,'organization.manage');
    RAISE EXCEPTION 'organization manage replay accepted an event scope';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  v_result := eogp.list_organization_access_members(v_org,v_actor,0);
  IF NOT v_result->'members' @> jsonb_build_array(jsonb_build_object('membershipId',v_actor,'status','active',
      'grants',jsonb_build_array(jsonb_build_object('grantId',v_grant,'scope','organization'),
        jsonb_build_object('roleId',v_role,'scope','event','scopeId',v_event))))
    OR v_result::text LIKE '%password%'
    OR NOT eogp.list_organization_access_roles(v_org,v_actor) @> jsonb_build_array(
      jsonb_build_object('roleId',v_role,'permissionCodes',jsonb_build_array('organization.manage')))
    OR NOT eogp.list_organization_permission_catalogue(v_org,v_actor) @> '[{"code":"guest.notes.manage","sensitive":true}]'::jsonb
    OR has_table_privilege('eventor_runtime','eogp.role_permissions','INSERT,UPDATE,DELETE')
    OR has_table_privilege('eventor_runtime','eogp.user_role_grants','INSERT,UPDATE,DELETE')
    OR has_table_privilege('eventor_runtime','eogp.roles','INSERT,UPDATE,DELETE')
    OR has_table_privilege('eventor_runtime','eogp.organization_memberships','INSERT,UPDATE,DELETE') THEN
    RAISE EXCEPTION 'access projection missed a scoped grant or allowed direct authorization writes';
  END IF;
  BEGIN
    PERFORM eogp.list_organization_access_members(v_other_org,v_actor,0);
    RAISE EXCEPTION 'organization manager saw a different tenant';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  UPDATE eogp.user_role_grants SET revoked_at=clock_timestamp() WHERE organization_id=v_org AND id=v_grant;
  BEGIN
    PERFORM eogp.list_organization_permission_catalogue(v_org,v_actor);
    RAISE EXCEPTION 'permission catalogue stayed available after revocation';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$test$;

-- Custom role presets describe event permissions independently of assignments.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_admin uuid;
  v_role uuid;
BEGIN
  PERFORM set_config('app.organization_id',v_org::text,true);
  PERFORM set_config('app.actor_membership_id',v_actor::text,true);
  BEGIN
    PERFORM eogp.create_organization_event_role(v_org,v_actor,'ROSTER-CREW','Roster crew',NULL,ARRAY['guest.read']);
    RAISE EXCEPTION 'ordinary event staff created a role preset';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  SELECT id INTO STRICT v_admin FROM eogp.roles WHERE organization_id=v_org AND code='CI-ACCESS-ADMIN';
  INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id)
    VALUES(v_org,v_actor,v_admin,'organization',v_actor);
  BEGIN
    PERFORM eogp.create_organization_event_role(v_org,v_actor,'ROSTER-CREW','Roster crew',NULL,ARRAY['organization.manage']);
    RAISE EXCEPTION 'custom event role included an organization-wide permission';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  BEGIN
    PERFORM eogp.create_organization_event_role(v_org,v_actor,'ROSTER-CREW','Roster crew',NULL,ARRAY['guest.read','guest.read']);
    RAISE EXCEPTION 'custom event role accepted duplicate permissions';
  EXCEPTION WHEN invalid_parameter_value THEN NULL;
  END;
  v_role := (eogp.create_organization_event_role(v_org,v_actor,'ROSTER-CREW','Roster crew','Event staff',
    ARRAY['guest.read','guest.notes.read'])->>'roleId')::uuid;
  IF NOT eogp.list_organization_access_roles(v_org,v_actor) @> jsonb_build_array(jsonb_build_object('roleId',v_role,
      'code','ROSTER-CREW','scope','event','systemPreset',false,'permissionCodes',jsonb_build_array('guest.notes.read','guest.read')))
    OR EXISTS (SELECT 1 FROM eogp.user_role_grants WHERE organization_id=v_org AND role_id=v_role)
    OR NOT EXISTS (SELECT 1 FROM eogp.audit_events WHERE organization_id=v_org AND actor_membership_id=v_actor
      AND action='organization.role.created' AND aggregate_id=v_role AND safe_metadata='{"scope":"event","permissionCount":2}'::jsonb) THEN
    RAISE EXCEPTION 'custom event role was implicitly assigned or omitted role and audit data';
  END IF;
  BEGIN
    PERFORM eogp.create_organization_event_role(v_org,v_actor,'ROSTER-CREW','Other crew',NULL,ARRAY['guest.read']);
    RAISE EXCEPTION 'duplicate event role code was accepted';
  EXCEPTION WHEN unique_violation THEN NULL;
  END;
END;
$test$;

-- Event role assignments are scoped, idempotent and reversible through retained revocation.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_event uuid;
  v_other uuid;
  v_role uuid;
  v_member uuid;
  v_user uuid;
  v_grant uuid;
  v_new uuid;
  v_admin uuid;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  SELECT id INTO STRICT v_other FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-B';
  SELECT id INTO STRICT v_role FROM eogp.roles WHERE organization_id=v_org AND code='ROSTER-CREW';
  SELECT id INTO STRICT v_admin FROM eogp.roles WHERE organization_id=v_org AND code='CI-ACCESS-ADMIN';
  INSERT INTO eogp.users(display_name) VALUES ('Scoped role fixture') RETURNING id INTO v_user;
  INSERT INTO eogp.organization_memberships(organization_id,user_id) VALUES(v_org,v_user) RETURNING id INTO v_member;
  BEGIN
    PERFORM eogp.write_member_event_role(v_org,v_actor,v_member,v_admin,v_event,NULL);
    RAISE EXCEPTION 'organization role was assigned as an event role';
  EXCEPTION WHEN no_data_found THEN NULL;
  END;
  v_grant := (eogp.write_member_event_role(v_org,v_actor,v_member,v_role,v_event,NULL)->>'grantId')::uuid;
  IF eogp.write_member_event_role(v_org,v_actor,v_member,v_role,v_event,NULL)->>'grantId' IS DISTINCT FROM v_grant::text THEN
    RAISE EXCEPTION 'repeated event role assignment created a duplicate grant';
  END IF;
  PERFORM set_config('app.actor_membership_id',v_member::text,true);
  PERFORM eogp.assert_event_command_permission(v_org,v_event,v_member,'guest.read');
  BEGIN
    PERFORM eogp.assert_event_command_permission(v_org,v_other,v_member,'guest.read');
    RAISE EXCEPTION 'event role assignment leaked to another event';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  BEGIN
    PERFORM eogp.write_member_event_role(v_org,v_member,v_member,v_role,v_other,NULL);
    RAISE EXCEPTION 'event member granted a role without organization management';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM set_config('app.actor_membership_id',v_actor::text,true);
  UPDATE eogp.user_role_grants SET expires_at=clock_timestamp()+interval '1 day'
    WHERE organization_id=v_org AND id=v_grant;
  PERFORM eogp.write_member_event_role(v_org,v_actor,v_member,NULL,NULL,v_grant);
  PERFORM eogp.write_member_event_role(v_org,v_actor,v_member,NULL,NULL,v_grant);
  IF NOT EXISTS (SELECT 1 FROM eogp.user_role_grants WHERE organization_id=v_org AND id=v_grant
    AND expires_at IS NOT NULL AND revoked_at IS NOT NULL)
    OR (SELECT count(*) FROM eogp.audit_events WHERE organization_id=v_org AND aggregate_id=v_grant
      AND action='organization.event_role.revoked')<>1 THEN
    RAISE EXCEPTION 'grant revocation lost expiry or duplicated its audit';
  END IF;
  v_new := (eogp.write_member_event_role(v_org,v_actor,v_member,v_role,v_event,NULL)->>'grantId')::uuid;
  IF v_new=v_grant THEN RAISE EXCEPTION 'regrant overwrote revoked history'; END IF;
  UPDATE eogp.organization_memberships SET status='suspended' WHERE organization_id=v_org AND id=v_member;
  BEGIN
    PERFORM eogp.write_member_event_role(v_org,v_actor,v_member,v_role,v_other,NULL);
    RAISE EXCEPTION 'inactive member received an event role';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
END;
$test$;

-- Retirement preserves current permission history and blocks future assignments.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_event uuid;
  v_other uuid;
  v_role uuid;
  v_grant uuid;
BEGIN
  SELECT id INTO STRICT v_event FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  SELECT id INTO STRICT v_other FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-B';
  v_role := (eogp.create_organization_event_role(v_org,v_actor,'RETIRE-ROLE','Retirement fixture',NULL,ARRAY['guest.read'])->>'roleId')::uuid;
  v_grant := (eogp.write_member_event_role(v_org,v_actor,v_actor,v_role,v_event,NULL)->>'grantId')::uuid;
  PERFORM eogp.retire_organization_event_role(v_org,v_actor,v_role);
  PERFORM eogp.retire_organization_event_role(v_org,v_actor,v_role);
  IF NOT eogp.list_organization_access_roles(v_org,v_actor) @> jsonb_build_array(jsonb_build_object('roleId',v_role))
    OR NOT EXISTS (SELECT 1 FROM eogp.roles WHERE organization_id=v_org AND id=v_role AND retired_at IS NOT NULL)
    OR NOT EXISTS (SELECT 1 FROM eogp.user_role_grants WHERE organization_id=v_org AND id=v_grant AND revoked_at IS NULL)
    OR (SELECT count(*) FROM eogp.audit_events WHERE organization_id=v_org AND aggregate_id=v_role
      AND action='organization.role.retired')<>1 THEN
    RAISE EXCEPTION 'role retirement changed assignments, lost history or duplicated audit';
  END IF;
  BEGIN
    PERFORM eogp.write_member_event_role(v_org,v_actor,v_actor,v_role,v_other,NULL);
    RAISE EXCEPTION 'retired role accepted a new assignment';
  EXCEPTION WHEN no_data_found THEN NULL;
  END;
  PERFORM eogp.write_member_event_role(v_org,v_actor,v_actor,NULL,NULL,v_grant);
END;
$test$;

-- Session cancellation preserves identity and rejects stale or final-state changes.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_event uuid;
  v_other uuid;
  v_session uuid;
  v_schedule integer;
  v_result jsonb;
BEGIN
  SELECT id,current_revision INTO STRICT v_event,v_schedule FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-A';
  SELECT id INTO STRICT v_other FROM eogp.events WHERE organization_id=v_org AND event_code='CI-LINK-B';
  v_session := (eogp.create_organizer_event_session(v_org,v_event,v_actor,'CANCEL-FIXTURE','Cancelled fixture',NULL,NULL)->>'sessionId')::uuid;
  BEGIN
    PERFORM eogp.transition_organizer_event_session(v_org,v_other,v_session,v_actor,1,v_schedule,'cancel');
    RAISE EXCEPTION 'session cancellation crossed events';
  EXCEPTION WHEN no_data_found THEN NULL;
  END;
  BEGIN
    PERFORM eogp.transition_organizer_event_session(v_org,v_event,v_session,v_actor,1,v_schedule+1,'cancel');
    RAISE EXCEPTION 'session cancellation accepted an obsolete parent schedule';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  v_result := eogp.transition_organizer_event_session(v_org,v_event,v_session,v_actor,1,v_schedule,'cancel');
  IF v_result IS DISTINCT FROM jsonb_build_object('sessionId',v_session,'status','cancelled','detailsRevision',2)
    OR NOT EXISTS (SELECT 1 FROM eogp.audit_events WHERE organization_id=v_org AND aggregate_id=v_session
      AND action='event.session.lifecycle.transitioned' AND reason_code='cancel'
      AND safe_metadata->>'previousStatus'='planned') THEN
    RAISE EXCEPTION 'session cancellation lost revision or audit history';
  END IF;
  BEGIN
    PERFORM eogp.transition_organizer_event_session(v_org,v_event,v_session,v_actor,1,v_schedule,'cancel');
    RAISE EXCEPTION 'session cancellation accepted stale details';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  BEGIN
    PERFORM eogp.transition_organizer_event_session(v_org,v_event,v_session,v_actor,2,v_schedule,'start');
    RAISE EXCEPTION 'cancelled session was restarted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;
  END;
END;
$test$;

-- Membership access preserves administrator recovery and invalidates only scoped sessions.
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_other CONSTANT uuid := '10000000-0000-0000-0000-00000000000b';
  v_actor CONSTANT uuid := '30000000-0000-0000-0000-00000000000a';
  v_user uuid;
  v_member uuid;
  v_other_member uuid;
  v_session uuid := gen_random_uuid();
  v_other_session uuid := gen_random_uuid();
  v_actor_revision integer;
BEGIN
  SELECT access_revision INTO STRICT v_actor_revision FROM eogp.organization_memberships WHERE organization_id=v_org AND id=v_actor;
  BEGIN
    PERFORM eogp.set_organization_membership_access(v_org,v_actor,v_actor,v_actor_revision,'suspended');
    RAISE EXCEPTION 'last organization administrator was suspended';
  EXCEPTION WHEN SQLSTATE 'P1771' THEN NULL;
  END;
  INSERT INTO eogp.users(display_name) VALUES('Membership access fixture') RETURNING id INTO v_user;
  INSERT INTO eogp.organization_memberships(organization_id,user_id) VALUES(v_org,v_user) RETURNING id INTO v_member;
  INSERT INTO eogp.user_sessions(id,user_id,organization_id,membership_id,session_token_sha256,csrf_token_sha256,expires_at)
  VALUES(v_session,v_user,v_org,v_member,md5(v_session::text)||md5(v_session::text),repeat('0',64),clock_timestamp()+interval '1 day');

  PERFORM set_config('app.organization_id',v_other::text,true);
  INSERT INTO eogp.organization_memberships(organization_id,user_id) VALUES(v_other,v_user) RETURNING id INTO v_other_member;
  INSERT INTO eogp.user_sessions(id,user_id,organization_id,membership_id,session_token_sha256,csrf_token_sha256,expires_at)
  VALUES(v_other_session,v_user,v_other,v_other_member,md5(v_other_session::text)||md5(v_other_session::text),repeat('0',64),clock_timestamp()+interval '1 day');
  PERFORM set_config('app.organization_id',v_org::text,true);

  BEGIN
    PERFORM eogp.set_organization_membership_access(v_org,v_actor,v_other_member,1,'suspended');
    RAISE EXCEPTION 'membership access crossed organizations';
  EXCEPTION WHEN no_data_found THEN NULL;
  END;
  INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,scope_event_id,granted_by_membership_id)
  SELECT v_org,v_member,role.id,'event',event.id,v_actor
  FROM eogp.roles role CROSS JOIN eogp.events event
  WHERE role.organization_id=v_org AND role.code='ROSTER-CREW' AND event.organization_id=v_org AND event.event_code='CI-LINK-A';
  PERFORM eogp.set_organization_membership_access(v_org,v_actor,v_member,1,'suspended');
  IF NOT EXISTS(SELECT 1 FROM eogp.user_sessions WHERE organization_id=v_org AND id=v_session AND revoked_at IS NOT NULL) THEN
    RAISE EXCEPTION 'suspension retained an active membership session';
  END IF;
  BEGIN
    PERFORM eogp.set_organization_membership_access(v_org,v_actor,v_member,1,'active');
    RAISE EXCEPTION 'membership access accepted a stale revision';
  EXCEPTION WHEN serialization_failure THEN NULL;
  END;
  PERFORM eogp.set_organization_membership_access(v_org,v_actor,v_member,2,'active');
  IF NOT EXISTS(SELECT 1 FROM eogp.user_role_grants WHERE organization_id=v_org AND membership_id=v_member AND revoked_at IS NULL) THEN
    RAISE EXCEPTION 'membership state changes removed the role grants';
  END IF;
  IF NOT (eogp.list_organization_access_members(v_org,v_actor,0)->'members') @>
       jsonb_build_array(jsonb_build_object('membershipId',v_member,'status','active','revision',3))
    OR NOT EXISTS(SELECT 1 FROM eogp.user_sessions WHERE organization_id=v_org AND id=v_session AND revoked_at IS NOT NULL)
    OR (SELECT count(*) FROM eogp.audit_events WHERE organization_id=v_org AND aggregate_id=v_member
      AND action='organization.membership.access_changed')<>2 THEN
    RAISE EXCEPTION 'restoration missed revisions, revived old sessions or lost audit history';
  END IF;
  PERFORM set_config('app.actor_membership_id',v_member::text,true);
  BEGIN
    PERFORM eogp.set_organization_membership_access(v_org,v_member,v_actor,v_actor_revision,'suspended');
    RAISE EXCEPTION 'ordinary member changed organization access';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
  PERFORM set_config('app.actor_membership_id',v_actor::text,true);
  PERFORM set_config('app.organization_id',v_other::text,true);
  IF NOT EXISTS(SELECT 1 FROM eogp.user_sessions WHERE organization_id=v_other AND id=v_other_session AND revoked_at IS NULL) THEN
    RAISE EXCEPTION 'suspension revoked the user session in another organization';
  END IF;
  PERFORM set_config('app.organization_id',v_org::text,true);
END;
$test$;

COMMIT;

\echo 'PostgreSQL migration smoke tests passed.'
