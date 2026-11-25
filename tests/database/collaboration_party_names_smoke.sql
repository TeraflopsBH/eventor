\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
DO $test$
DECLARE
 a CONSTANT uuid:='10000000-0000-0000-0000-00000000000a';b CONSTANT uuid:='10000000-0000-0000-0000-00000000000b';booking CONSTANT uuid:='f0000000-0000-0000-0000-00000000000a';
 identity uuid:=gen_random_uuid();actor_a uuid:=gen_random_uuid();actor_b uuid:=gen_random_uuid();role_a uuid:=gen_random_uuid();role_b uuid:=gen_random_uuid();grant_id uuid;name_a text;name_b text;review jsonb;result jsonb;fingerprint text;original_fingerprint text;
BEGIN
 INSERT INTO eogp.users(id,email,display_name,status) VALUES(identity,'party-names-'||identity::text||'@example.invalid','Synthetic collaboration name manager','active');
 PERFORM set_config('app.organization_id',a::text,true);PERFORM set_config('app.actor_membership_id',actor_a::text,true);
 SELECT name INTO name_a FROM eogp.organizations WHERE id=a;
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(actor_a,a,identity,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(role_a,a,'CI-PARTY-'||role_a,'Synthetic collaboration manager','organization');
 INSERT INTO eogp.role_permissions VALUES(a,role_a,'collaboration.manage');
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(a,actor_a,role_a,'organization',actor_a);
 grant_id:=eogp.propose_collaboration_grant(NULL,b,'booking',NULL,NULL,booking,'Synthetic named booking collaboration','{"reviewLabel":"Synthetic scope"}',ARRAY['booking.event.link'],clock_timestamp()-interval '1 hour',clock_timestamp()+interval '1 day',actor_a);
 review:=eogp.read_staff_collaboration_grant(a,actor_a,grant_id);
 IF review->>'grantorDisplayName' IS DISTINCT FROM name_a OR review->'granteeDisplayName' IS DISTINCT FROM 'null'::jsonb OR review->>'canAccept'<>'false' OR review->>'canRevoke'<>'true' THEN RAISE EXCEPTION 'proposal name/hints invalid';END IF;
 UPDATE eogp.organizations SET name='Synthetic later grantor name' WHERE id=a;
 IF eogp.read_staff_collaboration_grant(a,actor_a,grant_id)->>'grantorDisplayName' IS DISTINCT FROM name_a THEN RAISE EXCEPTION 'organization rename rewrote published grantor name';END IF;
 BEGIN
  UPDATE eogp.collaboration_grants SET grantor_display_name='Forged synthetic name' WHERE organization_id=a AND id=grant_id;RAISE EXCEPTION 'published grantor name mutable';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 PERFORM set_config('app.organization_id',b::text,true);PERFORM set_config('app.actor_membership_id',actor_b::text,true);
 SELECT name INTO name_b FROM eogp.organizations WHERE id=b;
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(actor_b,b,identity,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(role_b,b,'CI-PARTY-'||role_b,'Synthetic recipient collaboration manager','organization');
 INSERT INTO eogp.role_permissions VALUES(b,role_b,'collaboration.manage');
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(b,actor_b,role_b,'organization',actor_b);
 IF EXISTS(SELECT 1 FROM eogp.organizations WHERE id=a) THEN RAISE EXCEPTION 'party snapshots widened the organization directory policy';END IF;
 review:=eogp.read_staff_collaboration_grant(b,actor_b,grant_id);original_fingerprint:=review->>'reviewFingerprint';
 IF review->>'grantorDisplayName' IS DISTINCT FROM name_a OR review->>'canAccept'<>'true' OR review->>'canRevoke'<>'false' OR original_fingerprint !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'recipient review/hints invalid';END IF;
 -- Simulate a privileged source correction: an interactive review must not approve stale meaning.
 PERFORM set_config('app.organization_id',a::text,true);PERFORM set_config('app.actor_membership_id',actor_a::text,true);
 UPDATE eogp.collaboration_grants SET projection=projection||'{"reviewLabel":"Synthetic corrected scope"}'::jsonb WHERE organization_id=a AND id=grant_id;
 PERFORM set_config('app.organization_id',b::text,true);PERFORM set_config('app.actor_membership_id',actor_b::text,true);
 BEGIN
  PERFORM eogp.accept_reviewed_collaboration_grant(b,actor_b,grant_id,original_fingerprint);RAISE EXCEPTION 'stale interactive grant review was accepted';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 IF eogp.read_staff_collaboration_grant(b,actor_b,grant_id)->>'status'<>'proposed' THEN RAISE EXCEPTION 'stale review partly accepted the grant';END IF;
 review:=eogp.read_staff_collaboration_grant(b,actor_b,grant_id);fingerprint:=review->>'reviewFingerprint';
 IF fingerprint IS NOT DISTINCT FROM original_fingerprint THEN RAISE EXCEPTION 'review fingerprint ignored changed scope';END IF;
 PERFORM set_config('TimeZone','Pacific/Auckland',true);
 result:=eogp.accept_reviewed_collaboration_grant(b,actor_b,grant_id,fingerprint);
 IF result->>'granteeDisplayName' IS DISTINCT FROM name_b OR result->>'grantorDisplayName' IS DISTINCT FROM name_a OR result->>'canAccept'<>'false' OR result->>'status'<>'active' THEN RAISE EXCEPTION 'acceptance name/hints invalid';END IF;
 PERFORM eogp.accept_reviewed_collaboration_grant(b,actor_b,grant_id,fingerprint);
 UPDATE eogp.organizations SET name='Synthetic later recipient name' WHERE id=b;
 IF eogp.read_staff_collaboration_grant(b,actor_b,grant_id)->>'granteeDisplayName' IS DISTINCT FROM name_b THEN RAISE EXCEPTION 'recipient rename rewrote published acceptance name';END IF;
 BEGIN
  UPDATE eogp.collaboration_grants SET grantee_display_name='Forged synthetic recipient' WHERE id=grant_id;RAISE EXCEPTION 'published recipient name mutable';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 PERFORM set_config('app.organization_id',a::text,true);PERFORM set_config('app.actor_membership_id',actor_a::text,true);
 result:=eogp.staff_collaboration_grant_action(a,actor_a,grant_id,'revoke','Synthetic named grant revocation');
 IF result->>'grantorDisplayName' IS DISTINCT FROM name_a OR result->>'granteeDisplayName' IS DISTINCT FROM name_b OR result->>'canRevoke'<>'false' THEN RAISE EXCEPTION 'revocation altered party name history/hints';END IF;
 IF has_function_privilege('eventor_auth','eogp.accept_reviewed_collaboration_grant(uuid,uuid,uuid,text)','EXECUTE') OR has_table_privilege('eventor_runtime','eogp.collaboration_grants','SELECT') THEN RAISE EXCEPTION 'party review widened direct/foreign-role access';END IF;
END;
$test$;
ROLLBACK;
\echo 'Published party names, tenant directory isolation, immutable history, reviewed acceptance and timezone-independent fingerprints passed.'
