\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','10000000-0000-0000-0000-00000000000a',true);
UPDATE eogp.users SET locale_preference='en' WHERE id='20000000-0000-0000-0000-00000000000a';
INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind)
VALUES('79000000-0000-4000-8000-000000000098','10000000-0000-0000-0000-00000000000a',
  'CI-PROVIDER-NOTICES','Synthetic provider notice manager','organization')
ON CONFLICT(id) DO NOTHING;
INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
VALUES('10000000-0000-0000-0000-00000000000a','79000000-0000-4000-8000-000000000098','booking.manage')
ON CONFLICT DO NOTHING;
INSERT INTO eogp.user_role_grants(id,organization_id,membership_id,role_id,scope_kind,granted_by_membership_id)
VALUES('79000000-0000-4000-8000-000000000099','10000000-0000-0000-0000-00000000000a',
  '30000000-0000-0000-0000-00000000000a','79000000-0000-4000-8000-000000000098','organization','30000000-0000-0000-0000-00000000000a')
ON CONFLICT(id) DO NOTHING;
COMMIT;
