\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','10000000-0000-0000-0000-00000000000a',true);
UPDATE eogp.users SET locale_preference='en' WHERE id='20000000-0000-0000-0000-00000000000a';
INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind)
VALUES('79e00000-0000-4000-8000-000000000001','10000000-0000-0000-0000-00000000000a','CI-REFERENCE-MERGE-BROWSER','Synthetic reference merge manager','organization')
ON CONFLICT(id) DO NOTHING;
INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
SELECT '10000000-0000-0000-0000-00000000000a','79e00000-0000-4000-8000-000000000001',code
FROM unnest(ARRAY['guest.registry.read','guest.registry.manage','guest.registry.merge','guest.registry.contacts.manage','guest.registry.contacts.verify','guest.registry.references.manage']) code
ON CONFLICT DO NOTHING;
INSERT INTO eogp.user_role_grants(id,organization_id,membership_id,role_id,scope_kind,granted_by_membership_id)
VALUES('79e00000-0000-4000-8000-000000000002','10000000-0000-0000-0000-00000000000a','30000000-0000-0000-0000-00000000000a',
  '79e00000-0000-4000-8000-000000000001','organization','30000000-0000-0000-0000-00000000000a')
ON CONFLICT(id) DO NOTHING;
COMMIT;
