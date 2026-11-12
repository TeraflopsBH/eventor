\set ON_ERROR_STOP on

-- Tenant RLS and cross-organization collaboration assertions.
-- Prerequisite fixtures are committed by constraints_and_booking_fixtures.sql.
-- Run this file as eventor_runtime after all migrations.

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

-- A distinct read-only venue grant must allow source SELECT without permitting
-- the event owner to bind/copy the provider's plan into an event snapshot.
BEGIN;
SELECT set_config('app.organization_id', '10000000-0000-0000-0000-00000000000a', true);
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
SELECT eogp.accept_collaboration_grant(
  '61000000-0000-4000-8000-00000000000c',
  '30000000-0000-0000-0000-00000000000b'
);
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
COMMIT;

\echo 'PostgreSQL migration smoke tests passed.'
