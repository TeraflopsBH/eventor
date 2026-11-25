\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
DO $test$
DECLARE
 a CONSTANT uuid:='10000000-0000-0000-0000-00000000000a';b CONSTANT uuid:='10000000-0000-0000-0000-00000000000b';
 booking CONSTANT uuid:='f0000000-0000-0000-0000-00000000000a';
 actor_a uuid:=gen_random_uuid();actor_b uuid:=gen_random_uuid();identity uuid:=gen_random_uuid();role_a uuid:=gen_random_uuid();booking_role uuid:=gen_random_uuid();role_b uuid:=gen_random_uuid();event_role uuid:=gen_random_uuid();
 event_a uuid:=gen_random_uuid();event_b uuid:=gen_random_uuid();other_b uuid:=gen_random_uuid();grant_id uuid;bad_grant uuid;expired_grant uuid:=gen_random_uuid();future_grant uuid:=gen_random_uuid();result jsonb;link_a uuid;link_b uuid;booking_before jsonb;event_before jsonb;
BEGIN
 PERFORM set_config('app.organization_id',a::text,true);PERFORM set_config('app.actor_membership_id',actor_a::text,true);
 INSERT INTO eogp.users(id,email,display_name,status) VALUES(identity,'booking-link-'||identity::text||'@example.invalid','Synthetic booking link operator','active');
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(actor_a,a,identity,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(role_a,a,'CI-LINK-OWNER','Synthetic booking association owner','organization');
 INSERT INTO eogp.role_permissions SELECT a,role_a,code FROM unnest(ARRAY['event.manage','booking.manage','collaboration.manage']) code;
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(a,actor_a,role_a,'organization',actor_a);
 INSERT INTO eogp.events(id,organization_id,event_code,title,created_by_membership_id) VALUES(event_a,a,'CI-LINK-'||event_a::text,'Synthetic same-organization association',actor_a);
 SELECT to_jsonb(record) INTO booking_before FROM eogp.booking_records record WHERE organization_id=a AND id=booking;
 SELECT to_jsonb(record) INTO event_before FROM eogp.events record WHERE organization_id=a AND id=event_a;
 result:=eogp.create_event_booking_link(a,event_a,actor_a,a,booking,NULL,'venue_for_event');link_a:=(result->>'linkId')::uuid;
 IF (SELECT to_jsonb(record) FROM eogp.booking_records record WHERE organization_id=a AND id=booking) IS DISTINCT FROM booking_before OR (SELECT to_jsonb(record) FROM eogp.events record WHERE organization_id=a AND id=event_a) IS DISTINCT FROM event_before THEN RAISE EXCEPTION 'association changed booking/event facts';END IF;
 IF result->>'status' IS DISTINCT FROM 'active' OR result->'collaborationGrantId' IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'same-organization link incorrect';END IF;
 IF eogp.create_event_booking_link(a,event_a,actor_a,a,booking,NULL,'venue_for_event')->>'linkId' IS DISTINCT FROM link_a::text OR (SELECT count(*) FROM eogp.audit_events WHERE organization_id=a AND action='booking.event.linked' AND aggregate_id=link_a)<>1 THEN RAISE EXCEPTION 'duplicate association or duplicate audit';END IF;
 BEGIN PERFORM eogp.create_event_booking_link(a,event_a,actor_a,a,booking,NULL,'other');RAISE EXCEPTION 'relationship silently repurposed';EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;END;
 BEGIN PERFORM eogp.create_event_booking_link(a,event_a,actor_a,a,booking,gen_random_uuid(),'venue_for_event');RAISE EXCEPTION 'same-organization grant accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 DELETE FROM eogp.role_permissions WHERE organization_id=a AND role_id=role_a AND permission_code='booking.manage';
 BEGIN PERFORM eogp.create_event_booking_link(a,event_a,actor_a,a,booking,NULL,'venue_for_event');RAISE EXCEPTION 'event management implied booking management';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(booking_role,a,'CI-LINK-BOOKING','Synthetic exact booking manager','booking');
 INSERT INTO eogp.role_permissions VALUES(a,booking_role,'booking.manage');
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,scope_booking_id,granted_by_membership_id) VALUES(a,actor_a,booking_role,'booking',booking,actor_a);
 IF eogp.create_event_booking_link(a,event_a,actor_a,a,booking,NULL,'venue_for_event')->>'linkId' IS DISTINCT FROM link_a::text THEN RAISE EXCEPTION 'exact booking management scope refused';END IF;
 BEGIN PERFORM eogp.create_event_booking_link(a,event_a,actor_a,a,gen_random_uuid(),NULL,'venue_for_event');RAISE EXCEPTION 'booking scope widened';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 UPDATE eogp.booking_event_links SET status='ended',status_changed_by_membership_id=actor_a,status_change_reason_code='synthetic_end' WHERE organization_id=a AND id=link_a;
 BEGIN PERFORM eogp.create_event_booking_link(a,event_a,actor_a,a,booking,NULL,'venue_for_event');RAISE EXCEPTION 'terminal association silently reactivated';EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;END;
 IF eogp.list_event_booking_links(a,event_a,actor_a,0)#>>'{links,0,status}' IS DISTINCT FROM 'ended' THEN RAISE EXCEPTION 'terminal association history hidden';END IF;
 PERFORM set_config('app.organization_id',b::text,true);PERFORM set_config('app.actor_membership_id',actor_b::text,true);
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(actor_b,b,identity,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(role_b,b,'CI-LINK-RECIPIENT','Synthetic booking association recipient','organization'),(event_role,b,'CI-LINK-EVENT','Synthetic scoped event manager','event');
 INSERT INTO eogp.role_permissions VALUES(b,role_b,'collaboration.manage'),(b,event_role,'event.manage');
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(b,actor_b,role_b,'organization',actor_b);
 INSERT INTO eogp.events(id,organization_id,event_code,title,created_by_membership_id) VALUES(event_b,b,'CI-LINK-'||event_b::text,'Synthetic cross-organization association',actor_b),(other_b,b,'CI-LINK-'||other_b::text,'Synthetic unassigned event',actor_b);
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,scope_event_id,granted_by_membership_id) VALUES(b,actor_b,event_role,'event',event_b,actor_b);
 BEGIN PERFORM eogp.create_event_booking_link(b,event_b,actor_b,a,booking,NULL,'venue_for_event');RAISE EXCEPTION 'cross-organization association without grant';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('app.organization_id',a::text,true);PERFORM set_config('app.actor_membership_id',actor_a::text,true);
 grant_id:=eogp.propose_collaboration_grant(NULL,b,'booking',NULL,NULL,booking,'Synthetic booking link acceptance','{}',ARRAY['booking.event.link'],clock_timestamp()-interval '1 hour',clock_timestamp()+interval '1 day',actor_a);
 bad_grant:=eogp.propose_collaboration_grant(NULL,b,'booking',NULL,NULL,booking,'Synthetic missing action','{}',ARRAY['booking.read'],clock_timestamp()-interval '1 hour',clock_timestamp()+interval '1 day',actor_a);
 PERFORM set_config('app.organization_id',b::text,true);PERFORM set_config('app.actor_membership_id',actor_b::text,true);
 BEGIN PERFORM eogp.create_event_booking_link(b,event_b,actor_b,a,booking,grant_id,'venue_for_event');RAISE EXCEPTION 'unaccepted collaboration accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM eogp.accept_collaboration_grant(grant_id,actor_b);PERFORM eogp.accept_collaboration_grant(bad_grant,actor_b);
 -- Active status alone does not authorize an expired or not-yet-effective historical grant.
 PERFORM set_config('app.organization_id',a::text,true);PERFORM set_config('app.actor_membership_id',actor_a::text,true);
 INSERT INTO eogp.collaboration_grants(id,organization_id,grantee_organization_id,scope_kind,scope_booking_id,purpose,allowed_actions,status,valid_from,valid_until,proposed_by_membership_id,accepted_by_membership_id,accepted_at)
 VALUES(expired_grant,a,b,'booking',booking,'Synthetic expired association authority',ARRAY['booking.event.link'],'active',clock_timestamp()-interval '2 days',clock_timestamp()-interval '1 day',actor_a,actor_b,clock_timestamp()-interval '2 days'),
 (future_grant,a,b,'booking',booking,'Synthetic future association authority',ARRAY['booking.event.link'],'active',clock_timestamp()+interval '1 day',clock_timestamp()+interval '2 days',actor_a,actor_b,clock_timestamp());
 PERFORM set_config('app.organization_id',b::text,true);PERFORM set_config('app.actor_membership_id',actor_b::text,true);
 BEGIN PERFORM eogp.create_event_booking_link(b,event_b,actor_b,a,booking,expired_grant,'venue_for_event');RAISE EXCEPTION 'expired collaboration authority accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM eogp.create_event_booking_link(b,event_b,actor_b,a,booking,future_grant,'venue_for_event');RAISE EXCEPTION 'future collaboration authority accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;

 BEGIN PERFORM eogp.create_event_booking_link(b,event_b,actor_b,a,booking,bad_grant,'venue_for_event');RAISE EXCEPTION 'missing link action accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM eogp.create_event_booking_link(b,event_b,actor_b,a,gen_random_uuid(),grant_id,'venue_for_event');RAISE EXCEPTION 'grant scope changed to another booking';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM eogp.create_event_booking_link(b,other_b,actor_b,a,booking,grant_id,'venue_for_event');RAISE EXCEPTION 'event scope bypassed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 result:=eogp.create_event_booking_link(b,event_b,actor_b,a,booking,grant_id,'venue_for_event');link_b:=(result->>'linkId')::uuid;
 IF result->>'collaborationGrantId' IS DISTINCT FROM grant_id::text OR result->>'bookingOwnerOrganizationId' IS DISTINCT FROM a::text OR (SELECT count(*) FROM jsonb_object_keys(result))<>8 THEN RAISE EXCEPTION 'association projection incorrect';END IF;
 IF eogp.list_event_booking_links(b,event_b,actor_b,0)#>>'{links,0,linkId}' IS DISTINCT FROM link_b::text THEN RAISE EXCEPTION 'event association page missing';END IF;
 BEGIN PERFORM eogp.list_event_booking_links(b,other_b,actor_b,0);RAISE EXCEPTION 'unassigned event associations exposed';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('app.organization_id',a::text,true);PERFORM set_config('app.actor_membership_id',actor_a::text,true);
 PERFORM eogp.revoke_collaboration_grant(grant_id,actor_a,'synthetic link revocation');
 BEGIN PERFORM eogp.list_event_booking_links(b,event_b,actor_a,0);RAISE EXCEPTION 'provider enumerated organizer associations';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('app.organization_id',b::text,true);PERFORM set_config('app.actor_membership_id',actor_b::text,true);
 BEGIN PERFORM eogp.assert_event_booking_link_permission(b,event_b,actor_b,a,booking,grant_id);RAISE EXCEPTION 'revoked collaboration authorized replay';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM eogp.create_event_booking_link(b,event_b,actor_b,a,booking,grant_id,'venue_for_event');RAISE EXCEPTION 'revoked collaboration authorized new command';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 IF jsonb_array_length(eogp.list_event_booking_links(b,event_b,actor_b,0)->'links') IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'grant revocation erased event-owned provenance';END IF;
 IF has_table_privilege('eventor_runtime','eogp.booking_event_links','SELECT,INSERT,UPDATE,DELETE') OR has_function_privilege('eventor_auth','eogp.create_event_booking_link(uuid,uuid,uuid,uuid,uuid,uuid,text)','EXECUTE') THEN RAISE EXCEPTION 'association command boundary bypassable';END IF;
END;
$test$;
ROLLBACK;
\echo 'Booking/event association authorization and history smoke passed.'
