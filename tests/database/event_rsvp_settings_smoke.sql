\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
DO $test$
DECLARE
 v_org CONSTANT uuid:='10000000-0000-0000-0000-00000000000a';
 v_actor CONSTANT uuid:='30000000-0000-0000-0000-00000000000a';
 v_created jsonb;v_event uuid;v_first jsonb;v_second jsonb;v_old uuid;v_invitation uuid:=gen_random_uuid();v_person uuid:=gen_random_uuid();v_participation uuid:=gen_random_uuid();v_invrev uuid:=gen_random_uuid();
BEGIN
 PERFORM set_config('app.organization_id',v_org::text,true);PERFORM set_config('app.actor_membership_id',v_actor::text,true);
 v_created:=eogp.create_organizer_event(v_org,v_actor,'RSVP-SETTINGS-SMOKE','Synthetic RSVP settings',NULL,'2031-01-18T10:00Z','2031-01-18T12:00Z','Europe/Sarajevo','{}','{}');
 v_event:=(v_created->>'eventId')::uuid;
 IF eogp.get_event_rsvp_settings(v_org,v_event,v_actor)->'policy'<>'null'::jsonb THEN RAISE EXCEPTION 'new event has implicit RSVP policy';END IF;
 v_first:=eogp.publish_event_rsvp_settings(v_org,v_event,v_actor,NULL,'["accepted","declined"]','2031-01-17T17:00Z',true,'Europe/Sarajevo');
 v_old:=(v_first->'policy'->>'revisionId')::uuid;
 IF v_first->>'timezoneName'<>'Europe/Sarajevo' OR v_first->'policy'->>'revisionNumber'<>'1' THEN RAISE EXCEPTION 'policy timezone or revision incorrect';END IF;
 INSERT INTO eogp.persons(id,organization_id,first_name,last_name,created_by_membership_id) VALUES(v_person,v_org,'Synthetic','RSVP guest',v_actor);
 INSERT INTO eogp.event_participations(id,organization_id,event_id,person_id,added_by_membership_id) VALUES(v_participation,v_org,v_event,v_person,v_actor);
 INSERT INTO eogp.invitations(id,organization_id,event_id,participation_id,created_by_membership_id) VALUES(v_invitation,v_org,v_event,v_participation,v_actor);
 INSERT INTO eogp.invitation_revisions(id,organization_id,event_id,invitation_id,revision_number,schedule_revision_id,rsvp_policy_revision_id,presentation_snapshot_ciphertext,created_by_membership_id,issued_at)
 VALUES(v_invrev,v_org,v_event,v_invitation,1,(v_created->>'scheduleRevisionId')::uuid,v_old,convert_to('ECP1'||repeat('x',64),'UTF8'),v_actor,clock_timestamp());
 UPDATE eogp.invitations SET status='active',current_revision_number=1,issued_at=clock_timestamp() WHERE organization_id=v_org AND id=v_invitation;
 v_second:=eogp.publish_event_rsvp_settings(v_org,v_event,v_actor,v_old,'["accepted","declined","tentative"]',NULL,false,'Europe/Sarajevo');
 IF v_second->'policy'->>'revisionNumber'<>'2' OR (v_second->'policy'->>'responseChangeAllowed')::boolean OR v_second->'policy'->'responseDeadline'<>'null'::jsonb THEN RAISE EXCEPTION 'new policy not applied';END IF;
 IF NOT EXISTS(SELECT 1 FROM eogp.invitation_revisions WHERE organization_id=v_org AND id=v_invrev AND rsvp_policy_revision_id=v_old)
  OR NOT EXISTS(SELECT 1 FROM eogp.rsvp_policy_revisions WHERE organization_id=v_org AND id=v_old AND allowed_responses='["accepted","declined"]'::jsonb AND response_deadline='2031-01-17T17:00Z' AND response_change_allowed) THEN RAISE EXCEPTION 'old invitation or policy was rewritten';END IF;
 BEGIN PERFORM eogp.publish_event_rsvp_settings(v_org,v_event,v_actor,v_old,'["accepted"]',NULL,true,'Europe/Sarajevo');RAISE EXCEPTION 'stale revision accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 BEGIN PERFORM eogp.publish_event_rsvp_settings(v_org,v_event,v_actor,(v_second->'policy'->>'revisionId')::uuid,'["accepted","accepted"]',NULL,true,'Europe/Sarajevo');RAISE EXCEPTION 'duplicate answer accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM eogp.publish_event_rsvp_settings(v_org,v_event,v_actor,NULL,'[]',NULL,true,'Europe/Sarajevo');RAISE EXCEPTION 'empty answers accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM eogp.publish_event_rsvp_settings(v_org,v_event,v_actor,NULL,'["other"]',NULL,true,'Europe/Sarajevo');RAISE EXCEPTION 'unknown answer accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM eogp.publish_event_rsvp_settings(v_org,v_event,v_actor,(v_second->'policy'->>'revisionId')::uuid,'["accepted"]',NULL,true,'UTC');RAISE EXCEPTION 'stale time zone accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 BEGIN PERFORM eogp.get_event_rsvp_settings('10000000-0000-0000-0000-00000000000b',v_event,v_actor);RAISE EXCEPTION 'cross-tenant read accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN UPDATE eogp.rsvp_policy_revisions SET response_change_allowed=false WHERE organization_id=v_org AND id=v_old;RAISE EXCEPTION 'published snapshot mutable';EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;END;
 IF EXISTS(SELECT 1 FROM eogp.event_capability_overrides WHERE organization_id=v_org AND event_id=v_event AND enabled)
  OR EXISTS(SELECT 1 FROM eogp.event_notification_campaigns WHERE organization_id=v_org AND event_id=v_event) THEN RAISE EXCEPTION 'publication enabled modules or sent notifications';END IF;
 IF (SELECT count(*) FROM eogp.audit_events WHERE organization_id=v_org AND aggregate_id=v_event AND action='event.rsvp_policy.published')<>2 THEN RAISE EXCEPTION 'publication audit missing';END IF;
 UPDATE eogp.rsvp_policies SET status='retired' WHERE organization_id=v_org AND id=(SELECT policy_id FROM eogp.rsvp_policy_revisions WHERE organization_id=v_org AND id=v_old);
 BEGIN PERFORM eogp.publish_event_rsvp_settings(v_org,v_event,v_actor,(v_second->'policy'->>'revisionId')::uuid,'["accepted"]',NULL,true,'Europe/Sarajevo');RAISE EXCEPTION 'retired policy reused';EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;END;
 UPDATE eogp.events SET status='archived' WHERE organization_id=v_org AND id=v_event;
 BEGIN PERFORM eogp.publish_event_rsvp_settings(v_org,v_event,v_actor,(v_second->'policy'->>'revisionId')::uuid,'["accepted"]',NULL,true,'Europe/Sarajevo');RAISE EXCEPTION 'terminal event accepted';EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;END;
 IF has_table_privilege('eventor_runtime','eogp.rsvp_policy_revisions','INSERT') OR has_function_privilege('eventor_auth','eogp.publish_event_rsvp_settings(uuid,uuid,uuid,uuid,jsonb,timestamptz,boolean,text)','EXECUTE') THEN RAISE EXCEPTION 'policy boundary grants too broad';END IF;
END;
$test$;
ROLLBACK;
\echo 'Event RSVP settings smoke passed.'
