\set ON_ERROR_STOP on

-- Dedicated disposable identity and membership for the real HTTP/session test.
BEGIN;
SET LOCAL ROLE eventor_owner;

SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);
INSERT INTO eogp.organizations (id, slug, name, operating_profile)
VALUES (
  '22222222-2222-4222-8222-222222222222',
  'ci-venue-b',
  'CI Venue B',
  'event_organizer'
);

INSERT INTO eogp.users (id, email, display_name, status)
VALUES (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'ci-b@example.invalid',
  'CI Authentication User',
  'active'
);

INSERT INTO eogp.organization_memberships (
  id, organization_id, user_id, status, joined_at
) VALUES (
  'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
  '22222222-2222-4222-8222-222222222222',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'active',
  clock_timestamp()
);

COMMIT;
