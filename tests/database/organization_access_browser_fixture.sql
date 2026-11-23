\set ON_ERROR_STOP on

-- Synthetic staff workspace data for organization-access-browser-smoke.mjs.
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);
INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
VALUES ('22222222-2222-4222-8222-222222222222','78000000-0000-4000-8000-000000000001','organization.manage')
ON CONFLICT DO NOTHING;
INSERT INTO eogp.events(id,organization_id,event_code,title,created_by_membership_id)
VALUES (
  '79000000-0000-4000-8000-000000000090','22222222-2222-4222-8222-222222222222',
  'CI-ACCESS-BROWSER','Synthetic access assignment event','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
) ON CONFLICT (id) DO NOTHING;
INSERT INTO eogp.users(id,email,display_name,status,password_hash,locale_preference)
SELECT '79000000-0000-4000-8000-000000000091','ci-access-member@example.invalid','CI Access Member','active',password_hash,'en'
FROM eogp.users WHERE id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
ON CONFLICT (id) DO UPDATE SET password_hash=EXCLUDED.password_hash,locale_preference=EXCLUDED.locale_preference;
INSERT INTO eogp.organization_memberships(id,organization_id,user_id)
VALUES('79000000-0000-4000-8000-000000000092','22222222-2222-4222-8222-222222222222','79000000-0000-4000-8000-000000000091')
ON CONFLICT (id) DO NOTHING;
INSERT INTO eogp.events(id,organization_id,event_code,title,created_by_membership_id)
VALUES('79000000-0000-4000-8000-000000000096','22222222-2222-4222-8222-222222222222',
  'CI-UNASSIGNED-EVENT','Synthetic unrelated event','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb')
ON CONFLICT(id) DO NOTHING;
INSERT INTO eogp.persons(id,organization_id,first_name,last_name,display_name,created_by_membership_id)
VALUES('79000000-0000-4000-8000-000000000094','22222222-2222-4222-8222-222222222222',
  'Synthetic','Private Guest','Synthetic private guest','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb')
ON CONFLICT(id) DO NOTHING;
INSERT INTO eogp.event_participations(id,organization_id,event_id,person_id,added_by_membership_id,person_identity_snapshot)
VALUES('79000000-0000-4000-8000-000000000095','22222222-2222-4222-8222-222222222222',
  '79000000-0000-4000-8000-000000000090','79000000-0000-4000-8000-000000000094',
  'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
  '{"firstName":"Synthetic","lastName":"Private Guest","displayName":"Synthetic private guest"}')
ON CONFLICT(id) DO NOTHING;
COMMIT;
