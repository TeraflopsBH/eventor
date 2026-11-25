\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
DO $test$
DECLARE
 a CONSTANT uuid:='10000000-0000-0000-0000-00000000000a';b CONSTANT uuid:='10000000-0000-0000-0000-00000000000b';booking CONSTANT uuid:='f0000000-0000-0000-0000-00000000000a';
 identity uuid:=gen_random_uuid();actor uuid:=gen_random_uuid();v_role uuid:=gen_random_uuid();booking_role uuid:=gen_random_uuid();v_grant uuid:=gen_random_uuid();result jsonb;before_booking jsonb;
BEGIN
 PERFORM set_config('app.organization_id',a::text,true);PERFORM set_config('app.actor_membership_id',actor::text,true);
 INSERT INTO eogp.users(id,email,display_name,status) VALUES(identity,'booking-proposal-'||identity::text||'@example.invalid','Synthetic booking proposal manager','active');
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(actor,a,identity,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(v_role,a,'CI-PROPOSE-'||v_role,'Synthetic collaboration manager','organization'),(booking_role,a,'CI-PROPOSE-BOOK-'||booking_role,'Synthetic exact booking manager','booking');
 INSERT INTO eogp.role_permissions VALUES(a,v_role,'collaboration.manage'),(a,booking_role,'booking.manage');
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(a,actor,v_role,'organization',actor);
 BEGIN
  PERFORM eogp.propose_booking_collaboration(a,booking,actor,v_grant,b,'Synthetic linking only',clock_timestamp(),NULL);RAISE EXCEPTION 'collaboration-only actor shared an unmanaged booking';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,scope_booking_id,granted_by_membership_id) VALUES(a,actor,booking_role,'booking',booking,actor);
 SELECT to_jsonb(record) INTO before_booking FROM eogp.booking_records record WHERE organization_id=a AND id=booking;
 result:=eogp.propose_booking_collaboration(a,booking,actor,v_grant,b,' Synthetic linking only ',clock_timestamp()-interval '1 hour',NULL);
 IF result->>'status'<>'proposed' OR result->>'bookingId' IS DISTINCT FROM booking::text OR result->>'granteeOrganizationId' IS DISTINCT FROM b::text
 OR result->'allowedActions' IS DISTINCT FROM '["booking.event.link"]'::jsonb OR result->'acceptedAt' IS DISTINCT FROM 'null'::jsonb OR result->'validUntil' IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'proposal projection/state invalid';END IF;
 IF NOT EXISTS(SELECT 1 FROM eogp.collaboration_grants WHERE organization_id=a AND id=v_grant AND scope_kind='booking' AND projection='{}'::jsonb AND purpose='Synthetic linking only' AND accepted_by_membership_id IS NULL)
 OR (SELECT count(*) FROM eogp.collaboration_grant_revisions WHERE organization_id=a AND grant_id=v_grant)<>1 THEN RAISE EXCEPTION 'proposal widened shared scope or lost initial revision';END IF;
 BEGIN
  PERFORM eogp.assert_booking_collaboration_proposal_permission(a,gen_random_uuid(),actor);RAISE EXCEPTION 'exact booking role reached another booking';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN
  PERFORM eogp.propose_booking_collaboration(a,booking,actor,gen_random_uuid(),a,'Synthetic same tenant',clock_timestamp(),NULL);RAISE EXCEPTION 'same-organization collaboration proposal accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN
  PERFORM eogp.propose_booking_collaboration(a,booking,actor,gen_random_uuid(),b,'Synthetic invalid period',clock_timestamp(),'infinity'::timestamptz);RAISE EXCEPTION 'infinite validity accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 DELETE FROM eogp.role_permissions WHERE organization_id=a AND role_id=v_role AND permission_code='collaboration.manage';
 BEGIN
  PERFORM eogp.assert_booking_collaboration_proposal_permission(a,booking,actor);RAISE EXCEPTION 'booking-only actor replayed a proposal';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 IF (SELECT to_jsonb(record) FROM eogp.booking_records record WHERE organization_id=a AND id=booking) IS DISTINCT FROM before_booking THEN RAISE EXCEPTION 'proposal changed booking facts';END IF;
 IF has_function_privilege('eventor_auth','eogp.propose_booking_collaboration(uuid,uuid,uuid,uuid,uuid,text,timestamptz,timestamptz)','EXECUTE') OR has_table_privilege('eventor_runtime','eogp.collaboration_grants','INSERT') THEN RAISE EXCEPTION 'proposal widened direct/foreign-role access';END IF;
END;
$test$;
ROLLBACK;
\echo 'Booking collaboration proposals require both authorities and preserve narrow unaccepted history.'
