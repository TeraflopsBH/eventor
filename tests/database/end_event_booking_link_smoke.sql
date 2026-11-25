\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
DO $test$
DECLARE
 a CONSTANT uuid:='10000000-0000-0000-0000-00000000000a';b CONSTANT uuid:='10000000-0000-0000-0000-00000000000b';booking CONSTANT uuid:='f0000000-0000-0000-0000-00000000000a';
 identity uuid:=gen_random_uuid();actor_a uuid:=gen_random_uuid();actor_b uuid:=gen_random_uuid();role_a uuid:=gen_random_uuid();role_b uuid:=gen_random_uuid();event_a uuid:=gen_random_uuid();event_b uuid:=gen_random_uuid();grant_id uuid;revoked_event uuid:=gen_random_uuid();revoked_link uuid;exact_role uuid:=gen_random_uuid();link_a uuid;link_b uuid;notice_id uuid:=gen_random_uuid();receipt jsonb;result jsonb;before_booking jsonb;before_event jsonb;before_grant jsonb;
BEGIN
 PERFORM set_config('app.organization_id',a::text,true);PERFORM set_config('app.actor_membership_id',actor_a::text,true);
 INSERT INTO eogp.users(id,email,display_name,status) VALUES(identity,'end-link-'||identity::text||'@example.invalid','Synthetic association manager','active');
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(actor_a,a,identity,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(role_a,a,'CI-END-'||role_a,'Synthetic association manager','organization');
 INSERT INTO eogp.role_permissions SELECT a,role_a,code FROM unnest(ARRAY['event.manage','booking.manage','collaboration.manage']) code;
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(a,actor_a,role_a,'organization',actor_a);
 INSERT INTO eogp.events(id,organization_id,event_code,title,created_by_membership_id) VALUES(event_a,a,'CI-END-'||event_a,'Synthetic local association ending',actor_a);
 SELECT to_jsonb(record) INTO before_booking FROM eogp.booking_records record WHERE organization_id=a AND id=booking;
 SELECT to_jsonb(event) INTO before_event FROM eogp.events event WHERE organization_id=a AND id=event_a;
 link_a:=(eogp.create_event_booking_link(a,event_a,actor_a,a,booking,NULL,'venue_for_event')->>'linkId')::uuid;
 PERFORM eogp.record_booking_disruption_notice(a,booking,actor_a,notice_id,'synthetic_disruption','Synthetic source public notice',NULL,NULL);
 receipt:=eogp.publish_local_event_disruption(a,event_a,actor_a,booking,notice_id);
 BEGIN
  PERFORM eogp.end_event_booking_link(a,gen_random_uuid(),actor_a,link_a);RAISE EXCEPTION 'wrong event association ended';
 EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL;END;
 DELETE FROM eogp.role_permissions WHERE organization_id=a AND role_id=role_a AND permission_code='booking.manage';
 result:=eogp.end_event_booking_link(a,event_a,actor_a,link_a);
 IF result->>'status'<>'ended' OR eogp.end_event_booking_link(a,event_a,actor_a,link_a) IS DISTINCT FROM result THEN RAISE EXCEPTION 'ending/retry mismatch';END IF;
 IF (SELECT status_changed_by_membership_id FROM eogp.booking_event_links WHERE organization_id=a AND id=link_a) IS DISTINCT FROM actor_a
 OR (SELECT count(*) FROM eogp.audit_events WHERE organization_id=a AND aggregate_id=link_a AND action='booking.event.link.ended' AND reason_code='event_manager_ended')<>1 THEN RAISE EXCEPTION 'ending lost authentic attribution or duplicated audit';END IF;
 IF eogp.list_event_disruption_notices(a,event_a,actor_a,0)#>'{notices,0}' IS DISTINCT FROM receipt THEN RAISE EXCEPTION 'ending altered published receipt';END IF;
 INSERT INTO eogp.role_permissions VALUES(a,role_a,'booking.manage');
 BEGIN
  PERFORM eogp.publish_local_event_disruption(a,event_a,actor_a,booking,notice_id);RAISE EXCEPTION 'publication reused ended link';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 BEGIN
  PERFORM eogp.create_event_booking_link(a,event_a,actor_a,a,booking,NULL,'venue_for_event');RAISE EXCEPTION 'create reactivated ended link';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 IF (SELECT to_jsonb(record) FROM eogp.booking_records record WHERE organization_id=a AND id=booking) IS DISTINCT FROM before_booking
 OR (SELECT to_jsonb(event) FROM eogp.events event WHERE organization_id=a AND id=event_a) IS DISTINCT FROM before_event THEN RAISE EXCEPTION 'ending mutated booking/event facts';END IF;
 INSERT INTO eogp.events(id,organization_id,event_code,title,created_by_membership_id) VALUES(revoked_event,a,'CI-END-'||revoked_event,'Synthetic revoked association',actor_a);
 revoked_link:=(eogp.create_event_booking_link(a,revoked_event,actor_a,a,booking,NULL,'venue_for_event')->>'linkId')::uuid;
 UPDATE eogp.booking_event_links SET status='revoked',status_changed_by_membership_id=actor_a,status_change_reason_code='synthetic_revocation' WHERE organization_id=a AND id=revoked_link;
 BEGIN
  PERFORM eogp.end_event_booking_link(a,revoked_event,actor_a,revoked_link);RAISE EXCEPTION 'revoked association was relabelled';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 DELETE FROM eogp.role_permissions WHERE organization_id=a AND role_id=role_a AND permission_code='event.manage';
 BEGIN
  PERFORM eogp.end_event_booking_link(a,event_a,actor_a,link_a);RAISE EXCEPTION 'revoked event scope replayed ending';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(exact_role,a,'CI-END-EXACT-'||exact_role,'Synthetic exact event manager','event');
 INSERT INTO eogp.role_permissions VALUES(a,exact_role,'event.manage');
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,scope_event_id,granted_by_membership_id) VALUES(a,actor_a,exact_role,'event',event_a,actor_a);
 IF eogp.end_event_booking_link(a,event_a,actor_a,link_a) IS DISTINCT FROM result THEN RAISE EXCEPTION 'exact event scope lost original terminal identity';END IF;
 BEGIN
  PERFORM eogp.end_event_booking_link(a,revoked_event,actor_a,revoked_link);RAISE EXCEPTION 'exact event scope reached another event';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 UPDATE eogp.organization_memberships SET status='suspended' WHERE organization_id=a AND id=actor_a;
 BEGIN
  PERFORM eogp.end_event_booking_link(a,event_a,actor_a,link_a);RAISE EXCEPTION 'suspended member ended a link';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 UPDATE eogp.organization_memberships SET status='active' WHERE organization_id=a AND id=actor_a;
 -- The recipient can end its own link even after source collaboration authority is revoked.
 PERFORM set_config('app.organization_id',b::text,true);PERFORM set_config('app.actor_membership_id',actor_b::text,true);
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(actor_b,b,identity,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(role_b,b,'CI-END-'||role_b,'Synthetic partner event manager','organization');
 INSERT INTO eogp.role_permissions VALUES(b,role_b,'event.manage'),(b,role_b,'collaboration.manage');
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(b,actor_b,role_b,'organization',actor_b);
 INSERT INTO eogp.events(id,organization_id,event_code,title,created_by_membership_id) VALUES(event_b,b,'CI-END-'||event_b,'Synthetic partner association ending',actor_b);
 PERFORM set_config('app.organization_id',a::text,true);PERFORM set_config('app.actor_membership_id',actor_a::text,true);
 grant_id:=eogp.propose_collaboration_grant(NULL,b,'booking',NULL,NULL,booking,'Synthetic association only','{}',ARRAY['booking.event.link'],clock_timestamp()-interval '1 hour',clock_timestamp()+interval '1 day',actor_a);
 PERFORM set_config('app.organization_id',b::text,true);PERFORM set_config('app.actor_membership_id',actor_b::text,true);
 PERFORM eogp.accept_collaboration_grant(grant_id,actor_b);
 link_b:=(eogp.create_event_booking_link(b,event_b,actor_b,a,booking,grant_id,'venue_for_event')->>'linkId')::uuid;
 PERFORM set_config('app.organization_id',a::text,true);PERFORM set_config('app.actor_membership_id',actor_a::text,true);
 PERFORM eogp.revoke_collaboration_grant(grant_id,actor_a,'Synthetic source revocation');
 SELECT to_jsonb(grant_row) INTO before_grant FROM eogp.collaboration_grants grant_row WHERE organization_id=a AND id=grant_id;
 PERFORM set_config('app.organization_id',b::text,true);PERFORM set_config('app.actor_membership_id',actor_b::text,true);
 IF eogp.end_event_booking_link(b,event_b,actor_b,link_b)->>'status'<>'ended' THEN RAISE EXCEPTION 'source revocation blocked recipient-owned ending';END IF;
 BEGIN
  PERFORM eogp.end_event_booking_link(b,event_b,actor_b,link_a);RAISE EXCEPTION 'foreign link was discoverable';
 EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL;END;
 PERFORM set_config('app.organization_id',a::text,true);PERFORM set_config('app.actor_membership_id',actor_a::text,true);
 IF (SELECT to_jsonb(grant_row) FROM eogp.collaboration_grants grant_row WHERE organization_id=a AND id=grant_id) IS DISTINCT FROM before_grant THEN RAISE EXCEPTION 'ending modified provider grant';END IF;
 IF has_table_privilege('eventor_runtime','eogp.booking_event_links','UPDATE') OR has_function_privilege('eventor_auth','eogp.end_event_booking_link(uuid,uuid,uuid,uuid)','EXECUTE') OR has_function_privilege('eventor_worker','eogp.end_event_booking_link(uuid,uuid,uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'ending widened direct access';END IF;
END;
$test$;
ROLLBACK;
\echo 'Event-owned booking link ending, retained receipts, source revocation, retry and authority smoke passed.'
