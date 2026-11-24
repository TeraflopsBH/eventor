\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
INSERT INTO eogp.users(id,email,display_name,status,password_hash,locale_preference)
SELECT fixture.id,fixture.email,fixture.name,'active',source.password_hash,'en'
FROM eogp.users source CROSS JOIN (VALUES
 ('88000000-0000-4000-8000-000000000001'::uuid,'organizer@demo.eventor.invalid','Demo multi-workspace organizer'),
 ('88000000-0000-4000-8000-000000000002'::uuid,'admin@demo.eventor.invalid','Demo platform administrator')
) fixture(id,email,name)
WHERE source.email='ci-b@example.invalid'
ON CONFLICT(id) DO UPDATE SET password_hash=EXCLUDED.password_hash,locale_preference='en';
SELECT set_config('app.organization_id','11111111-1111-4111-8111-111111111111',true);
INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status)
VALUES('88000000-0000-4000-8000-000000000011','11111111-1111-4111-8111-111111111111','88000000-0000-4000-8000-000000000001','active') ON CONFLICT(id) DO NOTHING;
SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);
INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status)
VALUES('88000000-0000-4000-8000-000000000012','22222222-2222-4222-8222-222222222222','88000000-0000-4000-8000-000000000001','active') ON CONFLICT(id) DO NOTHING;
SELECT set_config('app.platform_admin_reason','synthetic browser acceptance fixture',true);
UPDATE eogp.users SET is_platform_admin=true WHERE id='88000000-0000-4000-8000-000000000002';
SELECT eogp.refresh_platform_admin_access('88000000-0000-4000-8000-000000000002');
COMMIT;
