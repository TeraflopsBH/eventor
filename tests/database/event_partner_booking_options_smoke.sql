\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
DO $test$
DECLARE
 a CONSTANT uuid:='10000000-0000-0000-0000-00000000000a';b CONSTANT uuid:='10000000-0000-0000-0000-00000000000b';booking CONSTANT uuid:='f0000000-0000-0000-0000-00000000000a';
 identity uuid:=gen_random_uuid();actor_a uuid:=gen_random_uuid();actor_b uuid:=gen_random_uuid();role_a uuid:=gen_random_uuid();role_b uuid:=gen_random_uuid();event_a uuid:=gen_random_uuid();event_b uuid:=gen_random_uuid();other_event uuid:=gen_random_uuid();exact_role uuid:=gen_random_uuid();grants uuid[]:='{}';item uuid;idx integer;result jsonb;link_id uuid;before_booking jsonb;before_event jsonb;
BEGIN
 INSERT INTO eogp.users(id,email,display_name,status) VALUES(identity,'partner-options-'||identity::text||'@example.invalid','Synthetic partner options operator','active');
 PERFORM set_config('app.organization_id',a::text,true);PERFORM set_config('app.actor_membership_id',actor_a::text,true);
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(actor_a,a,identity,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(role_a,a,'CI-OPTIONS-'||role_a,'Synthetic partner grant manager','organization');
 INSERT INTO eogp.role_permissions VALUES(a,role_a,'collaboration.manage'),(a,role_a,'event.manage');
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(a,actor_a,role_a,'organization',actor_a);
 INSERT INTO eogp.events(id,organization_id,event_code,title,created_by_membership_id) VALUES(event_a,a,'CI-OPTIONS-'||event_a,'Synthetic outgoing grant event',actor_a);
 SELECT to_jsonb(record) INTO before_booking FROM eogp.booking_records record WHERE organization_id=a AND id=booking;
 FOR idx IN 1..6 LOOP
  grants:=array_append(grants,eogp.propose_collaboration_grant(NULL,b,'booking',NULL,NULL,booking,'Synthetic shared booking '||idx,'{"privateConfiguration":"PRIVATE-CHOICE-MARKER"}',CASE WHEN idx=5 THEN ARRAY['venue.snapshot.read'] ELSE ARRAY['booking.event.link'] END,clock_timestamp()-interval '1 hour',clock_timestamp()+interval '1 day',actor_a));
 END LOOP;
 IF eogp.list_event_partner_booking_options(a,event_a,actor_a,0)->'options' @> jsonb_build_array(jsonb_build_object('grantId',grants[1])) THEN RAISE EXCEPTION 'outgoing or proposed grants became booking choices';END IF;
 PERFORM set_config('app.organization_id',b::text,true);PERFORM set_config('app.actor_membership_id',actor_b::text,true);
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(actor_b,b,identity,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(role_b,b,'CI-OPTIONS-'||role_b,'Synthetic recipient operator','organization');
 INSERT INTO eogp.role_permissions VALUES(b,role_b,'collaboration.manage'),(b,role_b,'event.manage');
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(b,actor_b,role_b,'organization',actor_b);
 INSERT INTO eogp.events(id,organization_id,event_code,title,created_by_membership_id) VALUES(event_b,b,'CI-OPTIONS-'||event_b,'Synthetic partner choice event',actor_b),(other_event,b,'CI-OPTIONS-'||other_event,'Synthetic unrelated event',actor_b);
 FOR idx IN 1..5 LOOP PERFORM eogp.accept_collaboration_grant(grants[idx],actor_b);END LOOP;
 DELETE FROM eogp.role_permissions WHERE organization_id=b AND role_id=role_b AND permission_code='collaboration.manage';
 SELECT to_jsonb(event) INTO before_event FROM eogp.events event WHERE organization_id=b AND id=event_b;
 PERFORM set_config('app.organization_id',a::text,true);PERFORM set_config('app.actor_membership_id',actor_a::text,true);
 PERFORM eogp.revoke_collaboration_grant(grants[2],actor_a,'Synthetic source revocation');
 UPDATE eogp.collaboration_grants SET valid_from=clock_timestamp()+interval '1 hour' WHERE organization_id=a AND id=grants[3];
 UPDATE eogp.collaboration_grants SET valid_from=clock_timestamp()-interval '2 hours',valid_until=clock_timestamp()-interval '1 hour' WHERE organization_id=a AND id=grants[4];
 PERFORM set_config('app.organization_id',b::text,true);PERFORM set_config('app.actor_membership_id',actor_b::text,true);
 SELECT jsonb_build_object('options',coalesce(jsonb_agg(option),'[]'::jsonb)) INTO result FROM jsonb_array_elements(eogp.list_event_partner_booking_options(b,event_b,actor_b,0)->'options') option WHERE (option->>'grantId')::uuid=ANY(grants);
 IF jsonb_array_length(result->'options')<>1 OR result#>>'{options,0,grantId}' IS DISTINCT FROM grants[1]::text OR result#>>'{options,0,providerName}'<>'CI Tenant A' THEN RAISE EXCEPTION 'partner chooser included unavailable/wrong-action grants or omitted permitted booking scope';END IF;
 IF strpos(result::text,'PRIVATE-CHOICE-MARKER')>0 OR strpos(result::text,'CI-EXTERNAL-CANCEL')>0 OR result#>'{options,0,projection}' IS NOT NULL THEN RAISE EXCEPTION 'chooser exposed provider record/configuration';END IF;
 BEGIN
  PERFORM eogp.create_event_booking_link(b,event_b,actor_b,a,booking,grants[2],'venue_for_event');RAISE EXCEPTION 'revoked option could be committed';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 link_id:=(eogp.create_event_booking_link(b,event_b,actor_b,a,booking,grants[1],'venue_for_event')->>'linkId')::uuid;
 IF eogp.list_event_partner_booking_options(b,event_b,actor_b,0)->'options' @> jsonb_build_array(jsonb_build_object('bookingId',booking,'bookingOwnerOrganizationId',a)) THEN RAISE EXCEPTION 'existing association remained selectable';END IF;
 PERFORM eogp.end_event_booking_link(b,event_b,actor_b,link_id);
 IF eogp.list_event_partner_booking_options(b,event_b,actor_b,0)->'options' @> jsonb_build_array(jsonb_build_object('bookingId',booking,'bookingOwnerOrganizationId',a)) THEN RAISE EXCEPTION 'terminal association was offered for reactivation';END IF;
 IF (SELECT to_jsonb(event) FROM eogp.events event WHERE organization_id=b AND id=event_b) IS DISTINCT FROM before_event THEN RAISE EXCEPTION 'partner linking mutated event facts';END IF;
 DELETE FROM eogp.role_permissions WHERE organization_id=b AND role_id=role_b AND permission_code='event.manage';
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(exact_role,b,'CI-OPTIONS-EXACT-'||exact_role,'Synthetic exact event operator','event');
 INSERT INTO eogp.role_permissions VALUES(b,exact_role,'event.manage');
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,scope_event_id,granted_by_membership_id) VALUES(b,actor_b,exact_role,'event',event_b,actor_b);
 PERFORM eogp.list_event_partner_booking_options(b,event_b,actor_b,0);
 BEGIN
  PERFORM eogp.list_event_partner_booking_options(b,other_event,actor_b,0);RAISE EXCEPTION 'exact event scope enumerated another event options';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN
  PERFORM eogp.list_event_partner_booking_options(b,event_b,actor_b,-1);RAISE EXCEPTION 'invalid option page accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 PERFORM set_config('app.organization_id',a::text,true);PERFORM set_config('app.actor_membership_id',actor_a::text,true);
 IF (SELECT to_jsonb(record) FROM eogp.booking_records record WHERE organization_id=a AND id=booking) IS DISTINCT FROM before_booking THEN RAISE EXCEPTION 'chooser/linking mutated provider booking';END IF;
 IF has_function_privilege('eventor_auth','eogp.list_event_partner_booking_options(uuid,uuid,uuid,integer)','EXECUTE') OR has_function_privilege('eventor_worker','eogp.list_event_partner_booking_options(uuid,uuid,uuid,integer)','EXECUTE') OR has_table_privilege('eventor_runtime','eogp.collaboration_grants','SELECT') THEN RAISE EXCEPTION 'chooser widened direct/foreign-role access';END IF;
END;
$test$;
ROLLBACK;
\echo 'Partner booking options enforce acceptance, validity, action, event scope, privacy and terminal history.'
