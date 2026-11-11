\set ON_ERROR_STOP on

BEGIN;
SET LOCAL ROLE eventor_owner;

-- Deterministic tenant, identity and venue fixtures.
SELECT set_config('app.organization_id','11111111-1111-4111-8111-111111111111',true);
INSERT INTO eogp.organizations (id, slug, name, operating_profile)
VALUES ('11111111-1111-4111-8111-111111111111','ci-venue-a','CI Venue A','venue_provider');
SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);
INSERT INTO eogp.organizations (id, slug, name, operating_profile)
VALUES ('22222222-2222-4222-8222-222222222222','ci-venue-b','CI Venue B','event_organizer');
SELECT set_config('app.organization_id','11111111-1111-4111-8111-111111111111',true);

INSERT INTO eogp.users (id, email, display_name, status)
VALUES
  ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','ci-a@example.invalid','CI User A','active'),
  ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','ci-b@example.invalid','CI User B','active');

INSERT INTO eogp.organization_memberships (id, organization_id, user_id, status, joined_at)
VALUES ('aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','active',clock_timestamp());
SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);
INSERT INTO eogp.organization_memberships (id, organization_id, user_id, status, joined_at)
VALUES ('bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb','22222222-2222-4222-8222-222222222222','bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','active',clock_timestamp());
SELECT set_config('app.organization_id','11111111-1111-4111-8111-111111111111',true);

INSERT INTO eogp.venues (id, organization_id, code, name, timezone_name)
VALUES
  ('10000000-0000-4000-8000-000000000001','11111111-1111-4111-8111-111111111111','VENUE-A','Venue A','Europe/Sarajevo'),
  ('10000000-0000-4000-8000-000000000002','11111111-1111-4111-8111-111111111111','VENUE-B','Venue B','Europe/Sarajevo');
SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);
INSERT INTO eogp.venues (id, organization_id, code, name, timezone_name)
VALUES ('20000000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','VENUE-C','Venue C','Europe/Sarajevo');
SELECT set_config('app.organization_id','11111111-1111-4111-8111-111111111111',true);

-- A grantee can accept the provider's proposed grant through the audited
-- command without receiving direct UPDATE privileges on provider-owned grants.
INSERT INTO eogp.collaboration_grants (
  id, organization_id, grantee_organization_id, scope_kind, scope_venue_id,
  purpose, projection, allowed_actions, proposed_by_membership_id
) VALUES (
  '60000000-0000-4000-8000-000000000001',
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  'venue','10000000-0000-4000-8000-000000000001',
  'CI shared venue plan', '{"venueSummary":true}'::jsonb,
  ARRAY['venue.snapshot.read'], 'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa'
);
SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);
SELECT eogp.accept_collaboration_grant(
  '60000000-0000-4000-8000-000000000001',
  'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
);
DO $test$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM eogp.collaboration_grants
     WHERE id = '60000000-0000-4000-8000-000000000001'
       AND status = 'active'
       AND accepted_by_membership_id = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
  ) THEN
    RAISE EXCEPTION 'collaboration grant acceptance was not committed';
  END IF;
END
$test$;
SELECT set_config('app.organization_id','11111111-1111-4111-8111-111111111111',true);

INSERT INTO eogp.venue_buildings (id, organization_id, venue_id, code, name)
VALUES
  ('11000000-0000-4000-8000-000000000001','11111111-1111-4111-8111-111111111111','10000000-0000-4000-8000-000000000001','BLD-A','Building A'),
  ('11000000-0000-4000-8000-000000000002','11111111-1111-4111-8111-111111111111','10000000-0000-4000-8000-000000000002','BLD-B','Building B');

INSERT INTO eogp.venue_levels (id, organization_id, building_id, code, name)
VALUES
  ('12000000-0000-4000-8000-000000000001','11111111-1111-4111-8111-111111111111','11000000-0000-4000-8000-000000000001','L0','Ground floor');

INSERT INTO eogp.venue_spaces (id, organization_id, venue_id, building_id, level_id, code, name, space_kind, capacity)
VALUES
  ('13000000-0000-4000-8000-000000000001','11111111-1111-4111-8111-111111111111','10000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000001','12000000-0000-4000-8000-000000000001','MAIN','Main Hall','room',300);

DO $test$
BEGIN
  BEGIN
    INSERT INTO eogp.venue_spaces (
      organization_id, venue_id, building_id, code, name, space_kind
    ) VALUES (
      '11111111-1111-4111-8111-111111111111',
      '10000000-0000-4000-8000-000000000001',
      '11000000-0000-4000-8000-000000000002',
      'WRONG-BUILDING','Invalid hierarchy','room'
    );
    RAISE EXCEPTION 'cross-venue building reference unexpectedly succeeded';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;
END
$test$;

-- Same-tenant person merge is permitted; cross-tenant merge is rejected.
INSERT INTO eogp.persons (id, organization_id, first_name, last_name, status, created_by_membership_id)
VALUES
  ('30000000-0000-4000-8000-000000000001','11111111-1111-4111-8111-111111111111','Person','One','active','aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa'),
  ('30000000-0000-4000-8000-000000000002','11111111-1111-4111-8111-111111111111','Person','Two','active','aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa');
SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);
INSERT INTO eogp.persons (id, organization_id, first_name, last_name, status, created_by_membership_id)
VALUES ('30000000-0000-4000-8000-000000000003','22222222-2222-4222-8222-222222222222','Person','Three','active','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');
SELECT set_config('app.organization_id','11111111-1111-4111-8111-111111111111',true);
INSERT INTO eogp.persons (id, organization_id, first_name, last_name, status, created_by_membership_id)
VALUES ('30000000-0000-4000-8000-000000000004','11111111-1111-4111-8111-111111111111','Person','Four','active','aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa');

UPDATE eogp.persons
   SET status = 'merged',
       merged_into_person_id = '30000000-0000-4000-8000-000000000002'
 WHERE organization_id = '11111111-1111-4111-8111-111111111111'
   AND id = '30000000-0000-4000-8000-000000000001';

DO $test$
BEGIN
  BEGIN
    UPDATE eogp.persons
       SET status = 'merged',
           merged_into_person_id = '30000000-0000-4000-8000-000000000003'
     WHERE organization_id = '11111111-1111-4111-8111-111111111111'
       AND id = '30000000-0000-4000-8000-000000000004';
    RAISE EXCEPTION 'cross-tenant person merge unexpectedly succeeded';
  EXCEPTION WHEN foreign_key_violation THEN
    NULL;
  END;
END
$test$;

-- Space reservations use half-open intervals: adjacent blocks are valid.
INSERT INTO eogp.maintenance_windows (
  id, organization_id, venue_space_id, starts_at, ends_at, reason_code
) VALUES
  ('14000000-0000-4000-8000-000000000001','11111111-1111-4111-8111-111111111111','13000000-0000-4000-8000-000000000001','2027-01-03 10:00+00','2027-01-03 11:00+00','CI-A'),
  ('14000000-0000-4000-8000-000000000002','11111111-1111-4111-8111-111111111111','13000000-0000-4000-8000-000000000001','2027-01-03 11:00+00','2027-01-03 12:00+00','CI-B');

INSERT INTO eogp.venue_space_time_blocks (
  organization_id, venue_space_id, maintenance_window_id, reservation_kind,
  status, starts_at, ends_at, idempotency_key
) VALUES
  ('11111111-1111-4111-8111-111111111111','13000000-0000-4000-8000-000000000001','14000000-0000-4000-8000-000000000001','maintenance','blocked','2027-01-03 10:00+00','2027-01-03 11:00+00','ci-space-adjacent-1'),
  ('11111111-1111-4111-8111-111111111111','13000000-0000-4000-8000-000000000001','14000000-0000-4000-8000-000000000002','maintenance','blocked','2027-01-03 11:00+00','2027-01-03 12:00+00','ci-space-adjacent-2');

DO $test$
DECLARE
  v_window uuid := '14000000-0000-4000-8000-000000000003';
BEGIN
  BEGIN
    INSERT INTO eogp.maintenance_windows (
      id, organization_id, venue_space_id, starts_at, ends_at, reason_code
    ) VALUES (
      v_window,'11111111-1111-4111-8111-111111111111',
      '13000000-0000-4000-8000-000000000001',
      '2027-01-03 10:30+00','2027-01-03 11:30+00','CI-OVERLAP'
    );
    INSERT INTO eogp.venue_space_time_blocks (
      organization_id, venue_space_id, maintenance_window_id, reservation_kind,
      status, starts_at, ends_at, idempotency_key
    ) VALUES (
      '11111111-1111-4111-8111-111111111111','13000000-0000-4000-8000-000000000001',
      v_window,'maintenance','blocked','2027-01-03 10:30+00','2027-01-03 11:30+00','ci-space-overlap'
    );
    RAISE EXCEPTION 'overlapping space reservation unexpectedly succeeded';
  EXCEPTION WHEN exclusion_violation THEN
    NULL;
  END;
END
$test$;

-- Pooled capacity evaluates peak simultaneous usage by interval segment.
INSERT INTO eogp.resource_types (id, organization_id, code, name, unit_label)
VALUES
  ('40000000-0000-4000-8000-000000000001','11111111-1111-4111-8111-111111111111','CHAIR','Chair','chair'),
  ('40000000-0000-4000-8000-000000000002','11111111-1111-4111-8111-111111111111','CONCURRENCY','Concurrent unit','unit');

INSERT INTO eogp.resource_pools (id, organization_id, venue_id, resource_type_id, code, name, capacity)
VALUES
  ('41000000-0000-4000-8000-000000000001','11111111-1111-4111-8111-111111111111','10000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001','CHAIRS','Chair pool',4),
  ('41000000-0000-4000-8000-000000000002','11111111-1111-4111-8111-111111111111','10000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000002','CONCURRENCY','Concurrency pool',3);

INSERT INTO eogp.booking_drafts (id, organization_id, created_by_membership_id, current_revision_number)
VALUES ('50000000-0000-4000-8000-000000000001','11111111-1111-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',1);

INSERT INTO eogp.booking_draft_revisions (
  id, organization_id, draft_id, revision_number, values_snapshot,
  created_by_membership_id
) VALUES (
  '51000000-0000-4000-8000-000000000001','11111111-1111-4111-8111-111111111111',
  '50000000-0000-4000-8000-000000000001',1,'{}',
  'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa'
);

INSERT INTO eogp.booking_resource_lines (
  id, organization_id, draft_revision_id, resource_type_id, line_code,
  label_snapshot, requested_quantity
) VALUES
  ('52000000-0000-4000-8000-000000000001','11111111-1111-4111-8111-111111111111','51000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000001','CHAIR-LINE','Chairs',4),
  ('52000000-0000-4000-8000-000000000002','11111111-1111-4111-8111-111111111111','51000000-0000-4000-8000-000000000001','40000000-0000-4000-8000-000000000002','CONCURRENCY-LINE','Concurrent units',3);

SELECT set_config('app.organization_id','11111111-1111-4111-8111-111111111111',true);

SELECT eogp.reserve_pooled_resource(
  '11111111-1111-4111-8111-111111111111','41000000-0000-4000-8000-000000000001',
  '51000000-0000-4000-8000-000000000001',NULL,'52000000-0000-4000-8000-000000000001',
  '2027-01-03 10:00+00','2027-01-03 11:00+00',2,'2027-01-02 15:00+00','ci-pool-a-0001'
);
SELECT eogp.reserve_pooled_resource(
  '11111111-1111-4111-8111-111111111111','41000000-0000-4000-8000-000000000001',
  '51000000-0000-4000-8000-000000000001',NULL,'52000000-0000-4000-8000-000000000001',
  '2027-01-03 12:00+00','2027-01-03 13:00+00',2,'2027-01-02 15:00+00','ci-pool-a-0002'
);
-- Both existing holds intersect this long request, but never overlap each other.
-- Peak simultaneous usage is 4, so this request must succeed for capacity 4.
SELECT eogp.reserve_pooled_resource(
  '11111111-1111-4111-8111-111111111111','41000000-0000-4000-8000-000000000001',
  '51000000-0000-4000-8000-000000000001',NULL,'52000000-0000-4000-8000-000000000001',
  '2027-01-03 10:00+00','2027-01-03 13:00+00',2,'2027-01-02 15:00+00','ci-pool-a-0003'
);

DO $test$
BEGIN
  BEGIN
    PERFORM eogp.reserve_pooled_resource(
      '11111111-1111-4111-8111-111111111111','41000000-0000-4000-8000-000000000001',
      '51000000-0000-4000-8000-000000000001',NULL,'52000000-0000-4000-8000-000000000001',
      '2027-01-03 10:30+00','2027-01-03 11:00+00',3,'2027-01-02 15:00+00','ci-pool-over-0001'
    );
    RAISE EXCEPTION 'pooled capacity overbooking unexpectedly succeeded';
  EXCEPTION WHEN exclusion_violation THEN
    NULL;
  END;
END
$test$;

COMMIT;
