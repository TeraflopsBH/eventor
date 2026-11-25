\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
DO $test$
DECLARE
 a CONSTANT uuid:='10000000-0000-0000-0000-00000000000a';b CONSTANT uuid:='10000000-0000-0000-0000-00000000000b';booking CONSTANT uuid:='f0000000-0000-0000-0000-00000000000a';
 identity uuid:=gen_random_uuid();actor_a uuid:=gen_random_uuid();actor_b uuid:=gen_random_uuid();role_a uuid:=gen_random_uuid();role_b uuid:=gen_random_uuid();proposal uuid;accepted uuid;unaccepted uuid;before_row jsonb;after_row jsonb;first_revoked_at timestamptz;
BEGIN
 PERFORM set_config('app.organization_id',a::text,true);PERFORM set_config('app.actor_membership_id',actor_a::text,true);
 INSERT INTO eogp.users(id,email,display_name,status) VALUES(identity,'proposal-revoke-'||identity::text||'@example.invalid','Synthetic collaboration manager','active');
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(actor_a,a,identity,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(role_a,a,'CI-PROPOSAL-'||role_a,'Synthetic collaboration manager','organization');
 INSERT INTO eogp.role_permissions VALUES(a,role_a,'collaboration.manage');
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(a,actor_a,role_a,'organization',actor_a);
 proposal:=eogp.propose_collaboration_grant(NULL,b,'booking',NULL,NULL,booking,'Synthetic unaccepted proposal','{}',ARRAY['booking.event.link'],clock_timestamp()-interval '1 hour',clock_timestamp()+interval '1 day',actor_a);
 SELECT to_jsonb(grant_row) INTO before_row FROM eogp.collaboration_grants grant_row WHERE organization_id=a AND id=proposal;
 PERFORM eogp.revoke_collaboration_grant(proposal,actor_a,'Synthetic proposal withdrawn before acceptance');
 SELECT to_jsonb(grant_row),revoked_at INTO after_row,first_revoked_at FROM eogp.collaboration_grants grant_row WHERE organization_id=a AND id=proposal;
 IF after_row->>'status'<>'revoked' OR first_revoked_at IS NULL OR after_row->'accepted_at' IS DISTINCT FROM 'null'::jsonb OR after_row->'accepted_by_membership_id' IS DISTINCT FROM 'null'::jsonb
 OR (after_row-'status'-'revoked_at') IS DISTINCT FROM (before_row-'status'-'revoked_at') THEN RAISE EXCEPTION 'proposal revocation fabricated acceptance or changed grant meaning';END IF;
 PERFORM eogp.revoke_collaboration_grant(proposal,actor_a,'Synthetic repeated revocation');
 IF (SELECT revoked_at FROM eogp.collaboration_grants WHERE organization_id=a AND id=proposal) IS DISTINCT FROM first_revoked_at
 OR (SELECT count(*) FROM eogp.audit_events WHERE organization_id=a AND aggregate_id=proposal AND action='collaboration.grant.revoked' AND actor_membership_id=actor_a)<>1
 OR (SELECT count(*) FROM eogp.collaboration_grant_revisions WHERE organization_id=a AND grant_id=proposal)<>1 THEN RAISE EXCEPTION 'revocation retry changed first transition or proposal history';END IF;
 unaccepted:=eogp.propose_collaboration_grant(NULL,b,'booking',NULL,NULL,booking,'Synthetic acceptance invariant','{}',ARRAY['booking.event.link'],clock_timestamp()-interval '1 hour',clock_timestamp()+interval '1 day',actor_a);
 BEGIN
  UPDATE eogp.collaboration_grants SET status='active' WHERE organization_id=a AND id=unaccepted;RAISE EXCEPTION 'active grant without acceptance accepted';
 EXCEPTION WHEN check_violation THEN NULL;END;
 BEGIN
  UPDATE eogp.collaboration_grants SET status='expired' WHERE organization_id=a AND id=unaccepted;RAISE EXCEPTION 'expired grant without acceptance accepted';
 EXCEPTION WHEN check_violation THEN NULL;END;
 accepted:=eogp.propose_collaboration_grant(NULL,b,'booking',NULL,NULL,booking,'Synthetic accepted grant','{}',ARRAY['booking.event.link'],clock_timestamp()-interval '1 hour',clock_timestamp()+interval '1 day',actor_a);
 PERFORM set_config('app.organization_id',b::text,true);PERFORM set_config('app.actor_membership_id',actor_b::text,true);
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(actor_b,b,identity,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(role_b,b,'CI-PROPOSAL-'||role_b,'Synthetic recipient collaboration manager','organization');
 INSERT INTO eogp.role_permissions VALUES(b,role_b,'collaboration.manage');
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(b,actor_b,role_b,'organization',actor_b);
 BEGIN
  PERFORM eogp.accept_collaboration_grant(proposal,actor_b);RAISE EXCEPTION 'revoked proposal was accepted';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 BEGIN
  PERFORM eogp.revoke_collaboration_grant(proposal,actor_b,'Synthetic recipient revocation attempt');RAISE EXCEPTION 'recipient revoked provider-owned grant';
 EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL;END;
 PERFORM eogp.accept_collaboration_grant(accepted,actor_b);
 SELECT to_jsonb(grant_row) INTO before_row FROM eogp.collaboration_grants grant_row WHERE organization_id=a AND id=accepted;
 PERFORM set_config('app.organization_id',a::text,true);PERFORM set_config('app.actor_membership_id',actor_a::text,true);
 PERFORM eogp.revoke_collaboration_grant(accepted,actor_a,'Synthetic accepted grant revoked');
 SELECT to_jsonb(grant_row) INTO after_row FROM eogp.collaboration_grants grant_row WHERE organization_id=a AND id=accepted;
 IF after_row->>'status'<>'revoked' OR after_row->>'accepted_by_membership_id' IS DISTINCT FROM actor_b::text
 OR (after_row-'status'-'revoked_at') IS DISTINCT FROM (before_row-'status'-'revoked_at') THEN RAISE EXCEPTION 'accepted grant revocation changed authentic acceptance';END IF;
 DELETE FROM eogp.role_permissions WHERE organization_id=a AND role_id=role_a AND permission_code='collaboration.manage';
 BEGIN
  PERFORM eogp.revoke_collaboration_grant(proposal,actor_a,'Synthetic retry after permission revoked');RAISE EXCEPTION 'revoked authority replayed proposal revocation';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 IF has_table_privilege('eventor_runtime','eogp.collaboration_grants','UPDATE') THEN RAISE EXCEPTION 'constraint fix widened runtime writes';END IF;
END;
$test$;
ROLLBACK;
\echo 'Unaccepted proposal revocation preserves authentic history, accepted grant invariants, retry and authority smoke passed.'
