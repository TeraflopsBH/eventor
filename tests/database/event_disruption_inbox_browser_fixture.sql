\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','10000000-0000-0000-0000-00000000000a',true);
INSERT INTO eogp.users(id,email,display_name,status,password_hash)
 SELECT '79c10000-0000-4000-8000-000000000001','ci-event-inbox@example.invalid','Synthetic event-only inbox manager','active',password_hash
 FROM eogp.users WHERE email='ci-b@example.invalid' ON CONFLICT(id) DO NOTHING;
INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status)
 VALUES('79c10000-0000-4000-8000-000000000002','10000000-0000-0000-0000-00000000000a','79c10000-0000-4000-8000-000000000001','active') ON CONFLICT DO NOTHING;
INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind)
 VALUES('79c10000-0000-4000-8000-000000000003','10000000-0000-0000-0000-00000000000a','CI-EVENT-INBOX','Synthetic event-only inbox manager','organization') ON CONFLICT DO NOTHING;
INSERT INTO eogp.role_permissions VALUES('10000000-0000-0000-0000-00000000000a','79c10000-0000-4000-8000-000000000003','event.manage') ON CONFLICT DO NOTHING;
INSERT INTO eogp.user_role_grants(id,organization_id,membership_id,role_id,scope_kind,granted_by_membership_id)
 VALUES('79c10000-0000-4000-8000-000000000004','10000000-0000-0000-0000-00000000000a','79c10000-0000-4000-8000-000000000002','79c10000-0000-4000-8000-000000000003','organization','30000000-0000-0000-0000-00000000000a') ON CONFLICT DO NOTHING;
COMMIT;
