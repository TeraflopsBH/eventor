\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
DO $test$
DECLARE
 a CONSTANT uuid:='10000000-0000-0000-0000-00000000000a';b CONSTANT uuid:='10000000-0000-0000-0000-00000000000b';booking CONSTANT uuid:='f0000000-0000-0000-0000-00000000000a';
 identity uuid:=gen_random_uuid();actor_a uuid:=gen_random_uuid();actor_b uuid:=gen_random_uuid();role_a uuid:=gen_random_uuid();role_b uuid:=gen_random_uuid();booking_role uuid:=gen_random_uuid();booking_assignment uuid;
 event_a uuid:=gen_random_uuid();event_b uuid:=gen_random_uuid();grant_id uuid;reference text;result jsonb;
BEGIN
 PERFORM set_config('app.organization_id',a::text,true);PERFORM set_config('app.actor_membership_id',actor_a::text,true);
 INSERT INTO eogp.users(id,email,display_name,status) VALUES(identity,'booking-reference-'||identity::text||'@example.invalid','Synthetic booking reference operator','active');
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(actor_a,a,identity,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(role_a,a,'CI-BOOK-REFERENCE','Synthetic booking reference manager','organization'),(booking_role,a,'CI-BOOK-EXACT','Synthetic exact booking reference scope','booking');
 INSERT INTO eogp.role_permissions SELECT a,role_a,code FROM unnest(ARRAY['event.manage','booking.manage','collaboration.manage']) code;
 INSERT INTO eogp.role_permissions VALUES(a,booking_role,'booking.manage');
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(a,actor_a,role_a,'organization',actor_a);
 INSERT INTO eogp.events(id,organization_id,event_code,title,created_by_membership_id) VALUES(event_a,a,'CI-REF-'||event_a::text,'Synthetic permitted booking reference',actor_a);
 SELECT booking_code INTO reference FROM eogp.booking_records WHERE organization_id=a AND id=booking;
 PERFORM eogp.create_event_booking_link(a,event_a,actor_a,a,booking,NULL,'venue_for_event');
 result:=eogp.list_event_booking_links(a,event_a,actor_a,0);
 IF result#>>'{links,0,bookingCode}' IS DISTINCT FROM reference OR NOT(eogp.list_booking_disruption_workspace(a,actor_a,0,reference)->'bookings' @> jsonb_build_array(jsonb_build_object('bookingId',booking))) THEN RAISE EXCEPTION 'permitted local reference unavailable';END IF;
 DELETE FROM eogp.role_permissions WHERE organization_id=a AND role_id=role_a AND permission_code='booking.manage';
 result:=eogp.list_event_booking_links(a,event_a,actor_a,0);
 IF result#>'{links,0,bookingCode}' IS DISTINCT FROM 'null'::jsonb OR eogp.list_booking_disruption_workspace(a,actor_a,0,reference)->'bookings' IS DISTINCT FROM '[]'::jsonb THEN RAISE EXCEPTION 'event authority exposed restricted booking references';END IF;
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,scope_booking_id,granted_by_membership_id) VALUES(a,actor_a,booking_role,'booking',booking,actor_a) RETURNING id INTO booking_assignment;
 IF eogp.list_event_booking_links(a,event_a,actor_a,0)#>>'{links,0,bookingCode}' IS DISTINCT FROM reference THEN RAISE EXCEPTION 'exact booking scope did not expose its own reference';END IF;
 UPDATE eogp.user_role_grants SET revoked_at=clock_timestamp() WHERE organization_id=a AND id=booking_assignment;
 IF eogp.list_event_booking_links(a,event_a,actor_a,0)#>'{links,0,bookingCode}' IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'revoked booking authority retained the display reference';END IF;
 -- One global identity has memberships in both organizations; selection still bounds the projection.
 PERFORM set_config('app.organization_id',b::text,true);PERFORM set_config('app.actor_membership_id',actor_b::text,true);
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(actor_b,b,identity,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(role_b,b,'CI-BOOK-RECIPIENT','Synthetic recipient event manager','organization');
 INSERT INTO eogp.role_permissions VALUES(b,role_b,'event.manage'),(b,role_b,'collaboration.manage'),(b,role_b,'booking.manage');
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(b,actor_b,role_b,'organization',actor_b);
 INSERT INTO eogp.events(id,organization_id,event_code,title,created_by_membership_id) VALUES(event_b,b,'CI-REF-'||event_b::text,'Synthetic partner booking reference',actor_b);
 PERFORM set_config('app.organization_id',a::text,true);PERFORM set_config('app.actor_membership_id',actor_a::text,true);
 grant_id:=eogp.propose_collaboration_grant(NULL,b,'booking',NULL,NULL,booking,'Synthetic event association only','{}',ARRAY['booking.event.link'],clock_timestamp()-interval '1 hour',clock_timestamp()+interval '1 day',actor_a);
 PERFORM set_config('app.organization_id',b::text,true);PERFORM set_config('app.actor_membership_id',actor_b::text,true);
 PERFORM eogp.accept_collaboration_grant(grant_id,actor_b);
 PERFORM eogp.create_event_booking_link(b,event_b,actor_b,a,booking,grant_id,'venue_for_event');
 result:=eogp.list_event_booking_links(b,event_b,actor_b,0);
 IF result#>'{links,0,bookingCode}' IS DISTINCT FROM 'null'::jsonb OR strpos(result::text,reference)>0 THEN RAISE EXCEPTION 'cross-organization association exposed a provider reference';END IF;
 IF eogp.list_booking_disruption_workspace(b,actor_b,0,reference)->'bookings' @> jsonb_build_array(jsonb_build_object('bookingId',booking)) THEN RAISE EXCEPTION 'local reference search included provider-owned booking';END IF;
 IF has_table_privilege('eventor_runtime','eogp.booking_event_links','SELECT') OR has_function_privilege('eventor_auth','eogp.list_event_booking_links(uuid,uuid,uuid,integer)','EXECUTE') THEN RAISE EXCEPTION 'reference projection widened direct access';END IF;
END;
$test$;
ROLLBACK;
\echo 'Event booking reference projection and tenant/field authority smoke passed.'
