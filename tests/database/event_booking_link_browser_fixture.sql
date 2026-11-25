\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','10000000-0000-0000-0000-00000000000a',true);
INSERT INTO eogp.users(id,email,display_name,password_hash,status,locale_preference)
SELECT '79b10000-0000-4000-8000-000000000001','ci-booking-link@example.invalid','Synthetic booking link manager',password_hash,'active','en' FROM eogp.users WHERE email='ci-b@example.invalid'
ON CONFLICT(id) DO UPDATE SET password_hash=EXCLUDED.password_hash,locale_preference='en';
INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES('79b10000-0000-4000-8000-000000000002','10000000-0000-0000-0000-00000000000a','79b10000-0000-4000-8000-000000000001','active') ON CONFLICT(id) DO NOTHING;
INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES('79b10000-0000-4000-8000-000000000003','10000000-0000-0000-0000-00000000000a','CI-BOOK-LINK-BROWSER','Synthetic booking association manager','organization') ON CONFLICT(id) DO NOTHING;
INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code) SELECT '10000000-0000-0000-0000-00000000000a','79b10000-0000-4000-8000-000000000003',code FROM unnest(ARRAY['event.manage','booking.manage']) code ON CONFLICT DO NOTHING;
INSERT INTO eogp.user_role_grants(id,organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES('79b10000-0000-4000-8000-000000000004','10000000-0000-0000-0000-00000000000a','79b10000-0000-4000-8000-000000000002','79b10000-0000-4000-8000-000000000003','organization','79b10000-0000-4000-8000-000000000002') ON CONFLICT(id) DO NOTHING;
COMMIT;
