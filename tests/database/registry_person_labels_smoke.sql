\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
DO $test$
DECLARE
 v_org CONSTANT uuid:='10000000-0000-0000-0000-00000000000a';v_other CONSTANT uuid:='10000000-0000-0000-0000-00000000000b';
 v_user uuid:=gen_random_uuid();v_actor uuid:=gen_random_uuid();v_role uuid:=gen_random_uuid();v_person uuid;v_destination uuid;v_label uuid;v_foreign uuid;v_result jsonb;v_review jsonb;v_audits integer;
BEGIN
 PERFORM set_config('app.organization_id',v_org::text,true);PERFORM set_config('app.actor_membership_id',v_actor::text,true);
 INSERT INTO eogp.users(id,email,display_name,status) VALUES(v_user,'label-'||v_user::text||'@example.invalid','Registry label fixture','active');
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(v_actor,v_org,v_user,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(v_role,v_org,'LABEL-FIXTURE','Registry label fixture','organization');
 INSERT INTO eogp.role_permissions SELECT v_org,v_role,code FROM unnest(ARRAY['guest.registry.read','guest.registry.manage','guest.registry.merge']) code;
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(v_org,v_actor,v_role,'organization',v_actor);
 v_person:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Label","lastName":"Fixture"}')->>'personId')::uuid;
 v_destination:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Other","lastName":"Fixture"}')->>'personId')::uuid;
 v_label:=(eogp.write_registry_label(v_org,v_actor,NULL,'VIP fixture')->>'labelId')::uuid;
 BEGIN PERFORM eogp.write_registry_label(v_org,v_actor,NULL,' vip FIXTURE ');RAISE EXCEPTION 'duplicate label accepted';EXCEPTION WHEN unique_violation THEN NULL;END;
 v_result:=eogp.set_registry_person_labels(v_org,v_actor,v_person,1,ARRAY[v_label]);
 IF v_result->>'revision'<>'2' OR NOT (eogp.list_registry_person_labels(v_org,v_actor,v_person)->'assignedLabelIds' @> jsonb_build_array(v_label)) THEN RAISE EXCEPTION 'label assignment missing'; END IF;
 IF NOT (eogp.read_guest_registry(v_org,v_actor,v_person,'',false,0)->'labels' @> jsonb_build_array(jsonb_build_object('labelId',v_label,'label','VIP fixture'))) THEN RAISE EXCEPTION 'Registry label badge missing';END IF;
 SELECT count(*) INTO v_audits FROM eogp.audit_events WHERE organization_id=v_org AND aggregate_id=v_person AND action='guest.registry.labels_changed';
 v_result:=eogp.set_registry_person_labels(v_org,v_actor,v_person,2,ARRAY[v_label]);
 IF v_result->>'revision'<>'2' OR v_audits<>(SELECT count(*) FROM eogp.audit_events WHERE organization_id=v_org AND aggregate_id=v_person AND action='guest.registry.labels_changed') THEN RAISE EXCEPTION 'unchanged labels churned history'; END IF;
 BEGIN PERFORM eogp.set_registry_person_labels(v_org,v_actor,v_person,1,ARRAY[]::uuid[]);RAISE EXCEPTION 'stale labels accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 BEGIN PERFORM eogp.set_registry_person_labels(v_org,v_actor,v_person,2,ARRAY[v_label,v_label]);RAISE EXCEPTION 'duplicate assignment accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 PERFORM set_config('app.organization_id',v_other::text,true);
 INSERT INTO eogp.registry_labels(organization_id,label) VALUES(v_other,'Other tenant label fixture') RETURNING id INTO v_foreign;
 PERFORM set_config('app.organization_id',v_org::text,true);
 BEGIN PERFORM eogp.set_registry_person_labels(v_org,v_actor,v_person,2,ARRAY[v_foreign]);RAISE EXCEPTION 'foreign label accepted';EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;END;
 PERFORM set_config('app.actor_membership_id',gen_random_uuid()::text,true);
 BEGIN PERFORM eogp.list_registry_person_labels(v_org,v_actor,v_person);RAISE EXCEPTION 'actor mismatch accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('app.actor_membership_id',v_actor::text,true);
 DELETE FROM eogp.role_permissions WHERE organization_id=v_org AND role_id=v_role AND permission_code IN('guest.registry.read','guest.registry.manage');
 BEGIN PERFORM eogp.list_registry_person_labels(v_org,v_actor,v_person);RAISE EXCEPTION 'revoked Registry permission ignored';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 INSERT INTO eogp.role_permissions SELECT v_org,v_role,code FROM unnest(ARRAY['guest.registry.read','guest.registry.manage']) code;
 v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_person,v_destination);
 IF v_review->'blocker' IS DISTINCT FROM 'null'::jsonb OR v_review->>'labelCount' IS DISTINCT FROM '1' THEN RAISE EXCEPTION 'labelled merge review unavailable';END IF;
 BEGIN PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_person,v_destination,2,1,'duplicate_profile',(v_review->>'reviewId')::uuid);RAISE EXCEPTION 'labelled source merged without explicit resolution';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 PERFORM eogp.write_registry_label(v_org,v_actor,v_label,NULL);
 PERFORM eogp.set_registry_person_labels(v_org,v_actor,v_person,2,ARRAY[v_label]);
 PERFORM eogp.set_registry_person_labels(v_org,v_actor,v_person,2,ARRAY[]::uuid[]);
 BEGIN PERFORM eogp.set_registry_person_labels(v_org,v_actor,v_person,3,ARRAY[v_label]);RAISE EXCEPTION 'retired label newly assigned';EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;END;
 IF has_table_privilege('eventor_runtime','eogp.registry_labels','SELECT') OR has_table_privilege('eventor_runtime','eogp.registry_person_label_assignments','UPDATE') OR has_function_privilege('eventor_runtime','eogp.guest_registry_merge_impact_without_labels(uuid,uuid,eogp.persons,eogp.persons)','EXECUTE') THEN RAISE EXCEPTION 'private labels or merge bypass exposed';END IF;
END;
$test$;
ROLLBACK;
\echo 'Registry person label smoke passed.'
