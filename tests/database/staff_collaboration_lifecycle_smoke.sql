\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
DO $test$
DECLARE
 a CONSTANT uuid:='10000000-0000-0000-0000-00000000000a';b CONSTANT uuid:='10000000-0000-0000-0000-00000000000b';c CONSTANT uuid:='10000000-0000-0000-0000-00000000000c';booking CONSTANT uuid:='f0000000-0000-0000-0000-00000000000a';
 identity uuid:=gen_random_uuid();actor_a uuid:=gen_random_uuid();actor_b uuid:=gen_random_uuid();actor_c uuid:=gen_random_uuid();role_a uuid:=gen_random_uuid();role_b uuid:=gen_random_uuid();role_c uuid:=gen_random_uuid();grant_id uuid;proposal uuid;future_id uuid;expired_id uuid;result jsonb;original jsonb;configuration jsonb:='{"reviewLabel":"Synthetic explicitly shared configuration"}';item jsonb;
BEGIN
 INSERT INTO eogp.users(id,email,display_name,status) VALUES(identity,'staff-collaboration-'||identity::text||'@example.invalid','Synthetic collaboration operator','active');
 PERFORM set_config('app.organization_id',a::text,true);PERFORM set_config('app.actor_membership_id',actor_a::text,true);
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(actor_a,a,identity,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(role_a,a,'CI-STAFF-COLLAB-'||role_a,'Synthetic collaboration manager','organization');
 INSERT INTO eogp.role_permissions VALUES(a,role_a,'collaboration.manage');
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(a,actor_a,role_a,'organization',actor_a);
 grant_id:=eogp.propose_collaboration_grant(NULL,b,'booking',NULL,NULL,booking,'Synthetic shared booking scope',configuration,ARRAY['booking.event.link'],clock_timestamp()-interval '1 hour',clock_timestamp()+interval '1 day',actor_a);
 proposal:=eogp.propose_collaboration_grant(NULL,b,'booking',NULL,NULL,booking,'Synthetic unaccepted shared booking scope',configuration,ARRAY['booking.event.link'],clock_timestamp()-interval '1 hour',clock_timestamp()+interval '1 day',actor_a);
 future_id:=eogp.propose_collaboration_grant(NULL,b,'booking',NULL,NULL,booking,'Synthetic future scope','{}',ARRAY['booking.event.link'],clock_timestamp()+interval '1 hour',clock_timestamp()+interval '1 day',actor_a);
 expired_id:=eogp.propose_collaboration_grant(NULL,b,'booking',NULL,NULL,booking,'Synthetic expired proposal','{}',ARRAY['booking.event.link'],clock_timestamp()-interval '2 hours',clock_timestamp()-interval '1 hour',actor_a);
 result:=eogp.list_staff_collaboration_grants(a,actor_a,0);
 IF NOT(result->'grants' @> jsonb_build_array(jsonb_build_object('grantId',grant_id,'effective',false))) THEN RAISE EXCEPTION 'outgoing grant missing or proposal marked effective';END IF;
 FOR item IN SELECT jsonb_array_elements(result->'grants') LOOP
  IF item ? 'projection' OR item ? 'proposedByMembershipId' OR item ? 'reason' THEN RAISE EXCEPTION 'grant list exposed detail/internal fields';END IF;
 END LOOP;
 IF eogp.read_staff_collaboration_grant(a,actor_a,grant_id)->'projection' IS DISTINCT FROM configuration THEN RAISE EXCEPTION 'grantor could not review deliberately shared configuration';END IF;
 BEGIN
  PERFORM eogp.staff_collaboration_grant_action(a,actor_a,grant_id,'accept',NULL);RAISE EXCEPTION 'grantor accepted its own outgoing grant';
 EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL;END;
 BEGIN
  PERFORM eogp.staff_collaboration_grant_action(a,actor_a,proposal,'revoke',E'Bad\nreason');RAISE EXCEPTION 'control characters accepted in revocation reason';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 original:=eogp.staff_collaboration_grant_action(a,actor_a,proposal,'revoke','Synthetic unaccepted proposal revocation');
 IF original->>'status'<>'revoked' OR original->'acceptedAt' IS DISTINCT FROM 'null'::jsonb OR original->>'effective'<>'false' THEN RAISE EXCEPTION 'proposal revocation fabricated active history';END IF;
 IF eogp.staff_collaboration_grant_action(a,actor_a,proposal,'revoke','Synthetic repeated revocation') IS DISTINCT FROM original THEN RAISE EXCEPTION 'revocation retry changed original outcome';END IF;
 PERFORM set_config('app.organization_id',b::text,true);PERFORM set_config('app.actor_membership_id',actor_b::text,true);
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(actor_b,b,identity,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(role_b,b,'CI-STAFF-COLLAB-'||role_b,'Synthetic recipient collaboration manager','organization');
 INSERT INTO eogp.role_permissions VALUES(b,role_b,'collaboration.manage');
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(b,actor_b,role_b,'organization',actor_b);
 IF eogp.read_staff_collaboration_grant(b,actor_b,grant_id)->'projection' IS DISTINCT FROM configuration THEN RAISE EXCEPTION 'recipient could not review shared configuration';END IF;
 result:=eogp.staff_collaboration_grant_action(b,actor_b,grant_id,'accept',NULL);
 IF result->>'status'<>'active' OR result->>'effective'<>'true' OR result->>'acceptedAt' IS NULL THEN RAISE EXCEPTION 'recipient acceptance missing';END IF;
 IF eogp.staff_collaboration_grant_action(b,actor_b,grant_id,'accept',NULL) IS DISTINCT FROM result THEN RAISE EXCEPTION 'acceptance retry changed original outcome';END IF;
 IF (SELECT count(*) FROM eogp.audit_events WHERE organization_id=b AND aggregate_id=grant_id AND action='collaboration.grant.accepted')<>1 THEN RAISE EXCEPTION 'duplicate acceptance audit';END IF;
 FOREACH proposal IN ARRAY ARRAY[proposal,future_id,expired_id] LOOP
  BEGIN
   PERFORM eogp.staff_collaboration_grant_action(b,actor_b,proposal,'accept',NULL);RAISE EXCEPTION 'inactive or unavailable proposal accepted';
  EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 END LOOP;
 BEGIN
  PERFORM eogp.staff_collaboration_grant_action(b,actor_b,grant_id,'revoke','Synthetic recipient attempt');RAISE EXCEPTION 'recipient revoked provider grant';
 EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL;END;
 PERFORM set_config('app.organization_id',a::text,true);PERFORM set_config('app.actor_membership_id',actor_a::text,true);
 result:=eogp.staff_collaboration_grant_action(a,actor_a,grant_id,'revoke','Synthetic accepted-grant revocation');
 IF result->>'acceptedAt' IS NULL OR result->>'status'<>'revoked' OR result->>'effective'<>'false' THEN RAISE EXCEPTION 'accepted grant revocation projection invalid';END IF;
 PERFORM set_config('app.organization_id',b::text,true);PERFORM set_config('app.actor_membership_id',actor_b::text,true);
 BEGIN
  PERFORM eogp.assert_staff_collaboration_action(b,actor_b,grant_id,'accept');RAISE EXCEPTION 'cached acceptance permission survived grant revocation';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 IF eogp.read_staff_collaboration_grant(b,actor_b,grant_id)->>'status'<>'revoked' THEN RAISE EXCEPTION 'recipient lost historical grant metadata';END IF;
 PERFORM set_config('app.organization_id',c::text,true);PERFORM set_config('app.actor_membership_id',actor_c::text,true);
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(actor_c,c,identity,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(role_c,c,'CI-STAFF-COLLAB-'||role_c,'Synthetic unrelated collaboration manager','organization');
 INSERT INTO eogp.role_permissions VALUES(c,role_c,'collaboration.manage');
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(c,actor_c,role_c,'organization',actor_c);
 IF eogp.list_staff_collaboration_grants(c,actor_c,0)->'grants' @> jsonb_build_array(jsonb_build_object('grantId',grant_id)) THEN RAISE EXCEPTION 'unrelated tenant listed private grant';END IF;
 BEGIN
  PERFORM eogp.read_staff_collaboration_grant(c,actor_c,grant_id);RAISE EXCEPTION 'unrelated tenant reviewed private grant';
 EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL;END;
 DELETE FROM eogp.role_permissions WHERE organization_id=c AND role_id=role_c AND permission_code='collaboration.manage';
 BEGIN
  PERFORM eogp.read_staff_collaboration_grant(c,actor_c,grant_id);RAISE EXCEPTION 'unauthorized member reached grant lookup';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN
  PERFORM eogp.list_staff_collaboration_grants(a,actor_a,0);RAISE EXCEPTION 'forged tenant context listed grants';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 IF has_table_privilege('eventor_runtime','eogp.collaboration_grants','SELECT') OR has_table_privilege('eventor_runtime','eogp.collaboration_grants','UPDATE') OR has_function_privilege('eventor_auth','eogp.read_staff_collaboration_grant(uuid,uuid,uuid)','EXECUTE') OR has_function_privilege('eventor_worker','eogp.staff_collaboration_grant_action(uuid,uuid,uuid,text,text)','EXECUTE') THEN RAISE EXCEPTION 'grant commands widened direct/foreign-role access';END IF;
END;
$test$;
ROLLBACK;
\echo 'Staff collaboration party projection, detail review, lifecycle, revocation, validity and authority smoke passed.'
