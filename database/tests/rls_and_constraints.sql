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
  v_result jsonb;
BEGIN
  v_result := eogp.create_organizer_event(
    v_org, v_actor, 'CI-EVENT-APPROVAL', 'Approval test event', NULL,
    '2031-01-18 09:00:00+00', '2031-01-18 12:00:00+00', 'Europe/Sarajevo', '{}', '{}'
  );
  v_event_id := (v_result->>'eventId')::uuid;

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
  IF has_function_privilege('eventor_worker',
       'eogp.transition_organizer_event(uuid,uuid,uuid,integer,integer,text)', 'EXECUTE') THEN
    RAISE EXCEPTION 'worker must not have direct event transition permission';
  END IF;
END;
$test$;

COMMIT;

\echo 'PostgreSQL migration smoke tests passed.'
