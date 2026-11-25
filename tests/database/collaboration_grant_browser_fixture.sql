\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','10000000-0000-0000-0000-00000000000a',true);
INSERT INTO eogp.users(id,email,display_name,status,password_hash)
 SELECT fixture.id,fixture.email,'Synthetic collaboration browser manager','active',source.password_hash FROM eogp.users source
 CROSS JOIN(VALUES('79f20000-0000-4000-8000-000000000001'::uuid,'ci-collaboration-a@example.invalid'),('79f20000-0000-4000-8000-000000000002'::uuid,'ci-collaboration-b@example.invalid')) fixture(id,email)
 WHERE source.email='ci-b@example.invalid' ON CONFLICT(id) DO NOTHING;
INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status)
 VALUES('79f20000-0000-4000-8000-000000000003','10000000-0000-0000-0000-00000000000a','79f20000-0000-4000-8000-000000000001','active') ON CONFLICT DO NOTHING;
INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind)
 VALUES('79f20000-0000-4000-8000-000000000005','10000000-0000-0000-0000-00000000000a','CI-COLLAB-BROWSER','Synthetic collaboration browser role','organization') ON CONFLICT DO NOTHING;
INSERT INTO eogp.role_permissions VALUES('10000000-0000-0000-0000-00000000000a','79f20000-0000-4000-8000-000000000005','collaboration.manage') ON CONFLICT DO NOTHING;
INSERT INTO eogp.user_role_grants(id,organization_id,membership_id,role_id,scope_kind,granted_by_membership_id)
 VALUES('79f20000-0000-4000-8000-000000000007','10000000-0000-0000-0000-00000000000a','79f20000-0000-4000-8000-000000000003','79f20000-0000-4000-8000-000000000005','organization','30000000-0000-0000-0000-00000000000a') ON CONFLICT DO NOTHING;
SELECT set_config('app.organization_id','10000000-0000-0000-0000-00000000000b',true);
INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status)
 VALUES('79f20000-0000-4000-8000-000000000004','10000000-0000-0000-0000-00000000000b','79f20000-0000-4000-8000-000000000002','active') ON CONFLICT DO NOTHING;
INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind)
 VALUES('79f20000-0000-4000-8000-000000000006','10000000-0000-0000-0000-00000000000b','CI-COLLAB-BROWSER','Synthetic collaboration browser role','organization') ON CONFLICT DO NOTHING;
INSERT INTO eogp.role_permissions VALUES('10000000-0000-0000-0000-00000000000b','79f20000-0000-4000-8000-000000000006','collaboration.manage') ON CONFLICT DO NOTHING;
INSERT INTO eogp.user_role_grants(id,organization_id,membership_id,role_id,scope_kind,granted_by_membership_id)
 VALUES('79f20000-0000-4000-8000-000000000008','10000000-0000-0000-0000-00000000000b','79f20000-0000-4000-8000-000000000004','79f20000-0000-4000-8000-000000000006','organization','30000000-0000-0000-0000-00000000000b') ON CONFLICT DO NOTHING;
SELECT set_config('app.organization_id','10000000-0000-0000-0000-00000000000a',true);
SELECT set_config('app.actor_membership_id','79f20000-0000-4000-8000-000000000003',true);
DO $fixture$
DECLARE engine text;
BEGIN
 FOREACH engine IN ARRAY ARRAY['chromium','firefox'] LOOP
  PERFORM eogp.propose_collaboration_grant(NULL,'10000000-0000-0000-0000-00000000000b','booking',NULL,NULL,'f0000000-0000-0000-0000-00000000000a',
   'CI partner access '||engine,'{"reviewLabel":"<b>Synthetic shared scope</b>"}',ARRAY['booking.event.link'],clock_timestamp()-interval '1 hour',clock_timestamp()+interval '1 day','79f20000-0000-4000-8000-000000000003');
  PERFORM eogp.propose_collaboration_grant(NULL,'10000000-0000-0000-0000-00000000000b','booking',NULL,NULL,'f0000000-0000-0000-0000-00000000000a',
   'CI unaccepted partner '||engine,'{}',ARRAY['booking.event.link'],clock_timestamp()-interval '1 hour',clock_timestamp()+interval '1 day','79f20000-0000-4000-8000-000000000003');
 END LOOP;
END;
$fixture$;
COMMIT;
