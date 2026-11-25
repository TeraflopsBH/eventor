\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
DO $test$
DECLARE
 org CONSTANT uuid:='10000000-0000-0000-0000-00000000000a';other_org CONSTANT uuid:='10000000-0000-0000-0000-00000000000b';
 booking CONSTANT uuid:='f0000000-0000-0000-0000-00000000000a';actor uuid:=gen_random_uuid();identity uuid:=gen_random_uuid();v_role uuid:=gen_random_uuid();
 exact_role uuid:=gen_random_uuid();exact_grant uuid;event_id uuid:=gen_random_uuid();other_event uuid:=gen_random_uuid();source_id uuid:=gen_random_uuid();missing uuid:=gen_random_uuid();
 result jsonb;replayed jsonb;receipt uuid;original_ack timestamptz;before_event jsonb;before_booking jsonb;
BEGIN
 PERFORM set_config('app.organization_id',org::text,true);PERFORM set_config('app.actor_membership_id',actor::text,true);
 INSERT INTO eogp.users(id,email,display_name,status) VALUES(identity,'notice-inbox-'||identity::text||'@example.invalid','Synthetic disruption operator','active');
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(actor,org,identity,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(v_role,org,'CI-INBOX-'||v_role,'Synthetic event and booking manager','organization'),(exact_role,org,'CI-INBOX-EXACT-'||exact_role,'Synthetic exact event manager','event');
 INSERT INTO eogp.role_permissions VALUES(org,v_role,'event.manage'),(org,v_role,'booking.manage'),(org,exact_role,'event.manage');
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(org,actor,v_role,'organization',actor);
 INSERT INTO eogp.events(id,organization_id,event_code,title,created_by_membership_id) VALUES(event_id,org,'CI-INBOX-'||event_id,'Synthetic disruption recipient',actor),(other_event,org,'CI-INBOX-'||other_event,'Synthetic unrelated event',actor);
 INSERT INTO eogp.booking_disruption_notices(id,organization_id,booking_id,notice_code,reason_category,public_summary,operational_summary,issued_by_membership_id)
 VALUES(source_id,org,booking,'CI-NOTICE','synthetic_disruption','Synthetic public availability update','PRIVATE-OPERATIONAL-MARKER',actor);
 SELECT to_jsonb(e) INTO before_event FROM eogp.events e WHERE organization_id=org AND id=event_id;
 SELECT to_jsonb(b) INTO before_booking FROM eogp.booking_records b WHERE organization_id=org AND id=booking;
 BEGIN
  PERFORM eogp.publish_local_event_disruption(org,event_id,actor,booking,source_id);
  RAISE EXCEPTION 'publication without association accepted';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 PERFORM eogp.create_event_booking_link(org,event_id,actor,org,booking,NULL,'venue_for_event');
 BEGIN
  PERFORM eogp.publish_local_event_disruption(org,event_id,actor,booking,missing);
  RAISE EXCEPTION 'missing source notice accepted';
 EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL;END;
 result:=eogp.publish_local_event_disruption(org,event_id,actor,booking,source_id);receipt:=(result->>'noticeId')::uuid;
 replayed:=eogp.publish_local_event_disruption(org,event_id,actor,booking,source_id);
 IF result IS DISTINCT FROM replayed OR result->>'status'<>'received' OR result#>>'{sourceNotice,publicSummary}'<>'Synthetic public availability update' OR strpos(result::text,'PRIVATE-OPERATIONAL-MARKER')>0 THEN RAISE EXCEPTION 'publication snapshot/retry mismatch';END IF;
 IF (SELECT count(*) FROM eogp.audit_events WHERE organization_id=org AND action='event.disruption_notice.published' AND aggregate_id=receipt)<>1 THEN RAISE EXCEPTION 'duplicate publication audits';END IF;
 -- Event-only staff can read the deliberately published snapshot, but cannot publish even on retries.
 DELETE FROM eogp.role_permissions WHERE organization_id=org AND role_id=v_role AND permission_code='booking.manage';
 IF eogp.list_event_disruption_notices(org,event_id,actor,0)#>>'{notices,0,noticeId}'<>receipt::text THEN RAISE EXCEPTION 'event inbox unavailable without booking scope';END IF;
 BEGIN
  PERFORM eogp.publish_local_event_disruption(org,event_id,actor,booking,source_id);
  RAISE EXCEPTION 'revoked source authority permitted duplicate publication';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 result:=eogp.acknowledge_event_disruption(org,receipt,actor);original_ack:=(result->>'acknowledgedAt')::timestamptz;
 IF result->>'status'<>'acknowledged' OR original_ack IS NULL THEN RAISE EXCEPTION 'acknowledgement missing';END IF;
 IF eogp.acknowledge_event_disruption(org,receipt,actor) IS DISTINCT FROM result THEN RAISE EXCEPTION 'retry rewrote acknowledgement';END IF;
 IF (SELECT count(*) FROM eogp.audit_events WHERE organization_id=org AND action='event.disruption_notice.acknowledged' AND aggregate_id=receipt)<>1 THEN RAISE EXCEPTION 'duplicate acknowledgement audits';END IF;
 UPDATE eogp.event_disruption_resolutions SET status='in_progress',resolution_notes_ciphertext=decode('abcd','hex') WHERE organization_id=org AND id=receipt;
 IF eogp.acknowledge_event_disruption(org,receipt,actor)->>'status'<>'in_progress' THEN RAISE EXCEPTION 'acknowledgement rewound resolution';END IF;
 BEGIN
  UPDATE eogp.event_disruption_resolutions SET source_notice_snapshot='{}' WHERE organization_id=org AND id=receipt;
  RAISE EXCEPTION 'snapshot mutation accepted';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 BEGIN
  UPDATE eogp.event_disruption_resolutions SET acknowledged_at=clock_timestamp() WHERE organization_id=org AND id=receipt;
  RAISE EXCEPTION 'first acknowledgement mutation accepted';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 BEGIN
  DELETE FROM eogp.event_disruption_resolutions WHERE organization_id=org AND id=receipt;
  RAISE EXCEPTION 'receipt deletion accepted';
 EXCEPTION WHEN SQLSTATE '55000' THEN NULL;END;
 -- Unsupported historical formats never expose arbitrary JSON or ciphertext.
 INSERT INTO eogp.event_disruption_resolutions(organization_id,event_id,source_provider_organization_id,source_booking_notice_id,source_notice_snapshot,resolution_notes_ciphertext)
 VALUES(org,other_event,org,missing,'{"privateLegacy":"PRIVATE-LEGACY-MARKER"}',decode('cafe','hex'));
 result:=eogp.list_event_disruption_notices(org,other_event,actor,0);
 IF result#>'{notices,0,sourceNotice}' IS DISTINCT FROM 'null'::jsonb OR strpos(result::text,'PRIVATE-LEGACY-MARKER')>0 OR strpos(result::text,'ciphertext')>0 THEN RAISE EXCEPTION 'legacy/internal receipt data leaked';END IF;
 INSERT INTO eogp.event_disruption_resolutions(organization_id,event_id,source_provider_organization_id,source_booking_notice_id,source_notice_snapshot)
 SELECT org,other_event,org,gen_random_uuid(),'{}'::jsonb FROM generate_series(1,50);
 result:=eogp.list_event_disruption_notices(org,other_event,actor,0);
 IF jsonb_array_length(result->'notices')<>50 OR result->>'nextOffset'<>'50' THEN RAISE EXCEPTION 'first receipt page invalid';END IF;
 result:=eogp.list_event_disruption_notices(org,other_event,actor,50);
 IF jsonb_array_length(result->'notices')<>1 OR result->'nextOffset' IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'last receipt page invalid';END IF;
 BEGIN
  PERFORM eogp.list_event_disruption_notices(org,event_id,actor,-1);RAISE EXCEPTION 'invalid receipt offset accepted';
 EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 -- Replace broad authority with an unrelated exact-event grant; no access to this receipt.
 DELETE FROM eogp.role_permissions WHERE organization_id=org AND role_id=v_role AND permission_code='event.manage';
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,scope_event_id,granted_by_membership_id)
 VALUES(org,actor,exact_role,'event',other_event,actor) RETURNING id INTO exact_grant;
 BEGIN
  PERFORM eogp.acknowledge_event_disruption(org,receipt,actor);RAISE EXCEPTION 'wrong event scope acknowledged receipt';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN
  PERFORM eogp.list_event_disruption_notices(org,event_id,actor,0);RAISE EXCEPTION 'wrong event scope read receipt';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 UPDATE eogp.user_role_grants SET scope_event_id=event_id WHERE organization_id=org AND id=exact_grant;
 IF eogp.list_event_disruption_notices(org,event_id,actor,0)#>>'{notices,0,noticeId}'<>receipt::text THEN RAISE EXCEPTION 'exact event scope not honored';END IF;
 UPDATE eogp.user_role_grants SET revoked_at=clock_timestamp() WHERE organization_id=org AND id=exact_grant;
 BEGIN
  PERFORM eogp.acknowledge_event_disruption(org,receipt,actor);RAISE EXCEPTION 'revoked event scope acknowledged receipt';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('app.organization_id',other_org::text,true);
 BEGIN
  PERFORM eogp.acknowledge_event_disruption(org,receipt,actor);RAISE EXCEPTION 'forged organization context accepted';
 EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('app.actor_membership_id','30000000-0000-0000-0000-00000000000b',true);
 BEGIN
  PERFORM eogp.acknowledge_event_disruption(other_org,receipt,'30000000-0000-0000-0000-00000000000b');RAISE EXCEPTION 'foreign tenant receipt was discoverable';
 EXCEPTION WHEN SQLSTATE 'P0002' THEN NULL;END;
 PERFORM set_config('app.actor_membership_id',actor::text,true);
 PERFORM set_config('app.organization_id',org::text,true);
 IF (SELECT to_jsonb(e) FROM eogp.events e WHERE organization_id=org AND id=event_id) IS DISTINCT FROM before_event
 OR (SELECT to_jsonb(b) FROM eogp.booking_records b WHERE organization_id=org AND id=booking) IS DISTINCT FROM before_booking THEN RAISE EXCEPTION 'notice workflow changed event/booking facts';END IF;
 IF has_table_privilege('eventor_runtime','eogp.event_disruption_resolutions','SELECT') OR has_table_privilege('eventor_runtime','eogp.event_disruption_resolutions','UPDATE')
 OR has_function_privilege('eventor_auth','eogp.acknowledge_event_disruption(uuid,uuid,uuid)','EXECUTE')
 OR has_function_privilege('eventor_worker','eogp.publish_local_event_disruption(uuid,uuid,uuid,uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'direct/foreign-role access exposed';END IF;
END;
$test$;
ROLLBACK;
\echo 'Event disruption publication, snapshot, acknowledgement, provenance and authorization smoke passed.'
