\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','10000000-0000-0000-0000-00000000000b',true);
INSERT INTO eogp.users(id,email,display_name,status,password_hash)
 SELECT '79f30000-0000-4000-8000-000000000001','ci-partner-event@example.invalid','Synthetic partner event manager','active',password_hash FROM eogp.users WHERE email='ci-b@example.invalid' ON CONFLICT(id) DO NOTHING;
INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES('79f30000-0000-4000-8000-000000000002','10000000-0000-0000-0000-00000000000b','79f30000-0000-4000-8000-000000000001','active') ON CONFLICT DO NOTHING;
INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES('79f30000-0000-4000-8000-000000000003','10000000-0000-0000-0000-00000000000b','CI-PARTNER-EVENT','Synthetic partner event manager','organization') ON CONFLICT DO NOTHING;
INSERT INTO eogp.role_permissions VALUES('10000000-0000-0000-0000-00000000000b','79f30000-0000-4000-8000-000000000003','event.manage') ON CONFLICT DO NOTHING;
INSERT INTO eogp.user_role_grants(id,organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES('79f30000-0000-4000-8000-000000000004','10000000-0000-0000-0000-00000000000b','79f30000-0000-4000-8000-000000000002','79f30000-0000-4000-8000-000000000003','organization','30000000-0000-0000-0000-00000000000b') ON CONFLICT DO NOTHING;
DO $fixture$
DECLARE engine text;purpose text;grant_id uuid;
BEGIN
 FOREACH engine IN ARRAY ARRAY['chromium','firefox'] LOOP
  FOREACH purpose IN ARRAY ARRAY['CI selectable partner ','CI withdrawn partner '] LOOP
   PERFORM set_config('app.organization_id','10000000-0000-0000-0000-00000000000a',true);PERFORM set_config('app.actor_membership_id','79f20000-0000-4000-8000-000000000003',true);
   grant_id:=eogp.propose_collaboration_grant(NULL,'10000000-0000-0000-0000-00000000000b','booking',NULL,NULL,'f0000000-0000-0000-0000-00000000000a',purpose||engine,'{}',ARRAY['booking.event.link'],clock_timestamp()-interval '1 hour',clock_timestamp()+interval '1 day','79f20000-0000-4000-8000-000000000003');
   PERFORM set_config('app.organization_id','10000000-0000-0000-0000-00000000000b',true);PERFORM set_config('app.actor_membership_id','79f20000-0000-4000-8000-000000000004',true);
   PERFORM eogp.accept_collaboration_grant(grant_id,'79f20000-0000-4000-8000-000000000004');
  END LOOP;
 END LOOP;
END;
$fixture$;
COMMIT;
