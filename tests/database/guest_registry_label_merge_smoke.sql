\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
DO $test$
DECLARE
 v_org CONSTANT uuid:='10000000-0000-0000-0000-00000000000a';
 v_actor uuid:=gen_random_uuid();v_user uuid:=gen_random_uuid();v_role uuid:=gen_random_uuid();
 v_source uuid;v_destination uuid;v_label uuid;v_retired uuid;v_keep uuid;v_revision integer;v_destination_revision integer;
 v_review jsonb;v_merge uuid;v_result jsonb;v_assignment jsonb;v_contact uuid:=gen_random_uuid();v_reference uuid:=gen_random_uuid();v_contact2 uuid:=gen_random_uuid();v_reference2 uuid:=gen_random_uuid();v_correction jsonb;
 v_cipher bytea:=convert_to('ECP1'||repeat('synthetic-label-merge-',4),'UTF8');v_source2 uuid;v_destination2 uuid;v_limit_source uuid;v_limit_destination uuid;v_limit_labels uuid[];
BEGIN
 PERFORM set_config('app.organization_id',v_org::text,true);PERFORM set_config('app.actor_membership_id',v_actor::text,true);
 INSERT INTO eogp.users(id,email,display_name,status) VALUES(v_user,'label-merge-'||v_user::text||'@example.invalid','Synthetic label merge operator','active');
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(v_actor,v_org,v_user,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(v_role,v_org,'CI-LABEL-MERGE','Synthetic label merge role','organization');
 INSERT INTO eogp.role_permissions SELECT v_org,v_role,code FROM unnest(ARRAY['guest.registry.read','guest.registry.manage','guest.registry.merge','guest.registry.contacts.manage','guest.registry.references.manage']) code;
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(v_org,v_actor,v_role,'organization',v_actor);
 v_source:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Synthetic","lastName":"Label source"}')->>'personId')::uuid;
 v_destination:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Synthetic","lastName":"Label destination"}')->>'personId')::uuid;
 v_label:=(eogp.write_registry_label(v_org,v_actor,NULL,'Synthetic VIP transfer')->>'labelId')::uuid;
 v_retired:=(eogp.write_registry_label(v_org,v_actor,NULL,'Synthetic retired transfer')->>'labelId')::uuid;
 v_keep:=(eogp.write_registry_label(v_org,v_actor,NULL,'Synthetic destination label')->>'labelId')::uuid;
 PERFORM eogp.set_registry_person_labels(v_org,v_actor,v_source,1,ARRAY[v_label,v_retired]);
 PERFORM eogp.set_registry_person_labels(v_org,v_actor,v_destination,1,ARRAY[v_keep]);
 INSERT INTO eogp.person_contact_points(id,organization_id,person_id,contact_kind,normalized_value_hash,encrypted_value,contact_consent)
 VALUES(v_contact,v_org,v_source,'email',repeat('d',64),v_cipher,'withdrawn');
 INSERT INTO eogp.person_identifiers(id,organization_id,person_id,identifier_kind,identifier_hash,encrypted_value)
 VALUES(v_reference,v_org,v_source,'external-ref-v1:LABEL-MERGE',repeat('d',64),v_cipher);
 v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
 -- Configuration retirement invalidates the review even without a profile revision change.
 PERFORM eogp.write_registry_label(v_org,v_actor,v_retired,NULL);
 BEGIN PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,2,2,'duplicate_profile',(v_review->>'reviewId')::uuid,'move_to_destination','move_to_destination','move_to_destination');RAISE EXCEPTION 'stale label configuration accepted';EXCEPTION WHEN serialization_failure THEN NULL;END;
 v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
 IF v_review->'blocker' IS DISTINCT FROM 'null'::jsonb OR v_review->>'labelCount' IS DISTINCT FROM '2' OR jsonb_array_length(v_review->'sourceLabels') IS DISTINCT FROM 2 THEN RAISE EXCEPTION 'classification review missing';END IF;
 BEGIN PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,2,2,'duplicate_profile',(v_review->>'reviewId')::uuid,'move_to_destination','move_to_destination');RAISE EXCEPTION 'legacy overload bypassed label choice';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 BEGIN PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,2,2,'duplicate_profile',(v_review->>'reviewId')::uuid);RAISE EXCEPTION 'oldest overload bypassed label choice';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 SELECT jsonb_object_agg(label_id::text,jsonb_build_array(added_by_membership_id,extract(epoch from added_at))) INTO v_assignment FROM eogp.registry_person_label_assignments WHERE organization_id=v_org AND person_id=v_source;
 v_result:=eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,2,2,'duplicate_profile',(v_review->>'reviewId')::uuid,'move_to_destination','move_to_destination','move_to_destination');v_merge:=(v_result->>'mergeId')::uuid;
 IF (SELECT jsonb_object_agg(label_id::text,jsonb_build_array(added_by_membership_id,extract(epoch from added_at))) FROM eogp.registry_person_label_assignments WHERE organization_id=v_org AND person_id=v_destination AND label_id IN(v_label,v_retired)) IS DISTINCT FROM v_assignment THEN RAISE EXCEPTION 'assignment metadata lost';END IF;
 IF (SELECT count(*) FROM eogp.person_merge_label_transfers WHERE organization_id=v_org AND merge_id=v_merge)<>2 OR NOT EXISTS(SELECT 1 FROM eogp.registry_person_label_assignments WHERE organization_id=v_org AND person_id=v_destination AND label_id=v_keep) THEN RAISE EXCEPTION 'journal or destination classification lost';END IF;
 PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);
 IF (SELECT jsonb_object_agg(label_id::text,jsonb_build_array(added_by_membership_id,extract(epoch from added_at))) FROM eogp.registry_person_label_assignments WHERE organization_id=v_org AND person_id=v_source) IS DISTINCT FROM v_assignment OR (SELECT person_id FROM eogp.person_contact_points WHERE id=v_contact) IS DISTINCT FROM v_source OR (SELECT person_id FROM eogp.person_identifiers WHERE id=v_reference) IS DISTINCT FROM v_source THEN RAISE EXCEPTION 'strict restoration lost linked records';END IF;
 PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge); -- no second transfer on idempotent restoration
 -- Overlapping classifications remain a reviewed conflict, never an implicit union.
 SELECT revision INTO v_destination_revision FROM eogp.persons WHERE organization_id=v_org AND id=v_destination;
 PERFORM eogp.set_registry_person_labels(v_org,v_actor,v_destination,v_destination_revision,ARRAY[v_keep,v_label]);
 v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
 IF v_review->>'blocker' IS DISTINCT FROM 'label_conflict' THEN RAISE EXCEPTION 'overlapping labels silently combined';END IF;
 -- A fresh disjoint pair exercises the separate reviewed current-contact restoration path.
 v_source2:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Synthetic","lastName":"Correction label source"}')->>'personId')::uuid;
 v_destination2:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Synthetic","lastName":"Correction label destination"}')->>'personId')::uuid;
 PERFORM eogp.set_registry_person_labels(v_org,v_actor,v_source2,1,ARRAY[v_label]);
 INSERT INTO eogp.person_contact_points(id,organization_id,person_id,contact_kind,normalized_value_hash,encrypted_value,contact_consent)
 VALUES(v_contact2,v_org,v_source2,'phone',repeat('e',64),v_cipher,'withdrawn');
 INSERT INTO eogp.person_identifiers(id,organization_id,person_id,identifier_kind,identifier_hash,encrypted_value)
 VALUES(v_reference2,v_org,v_source2,'external-ref-v1:LABEL-CORRECTION',repeat('e',64),v_cipher);

 v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source2,v_destination2);
 v_result:=eogp.commit_guest_registry_merge(v_org,v_actor,v_source2,v_destination2,2,1,'duplicate_profile',(v_review->>'reviewId')::uuid,'move_to_destination','move_to_destination','move_to_destination');v_merge:=(v_result->>'mergeId')::uuid;
 UPDATE eogp.person_contact_points SET contact_consent='restricted',revision=revision+1,updated_at=clock_timestamp() WHERE organization_id=v_org AND id=v_contact2;
 UPDATE eogp.person_identifiers SET encrypted_value=v_cipher||convert_to('synthetic-edit','UTF8') WHERE organization_id=v_org AND id=v_reference2;
 v_correction:=eogp.preview_guest_registry_merge_restoration(v_org,v_actor,v_merge);
 IF jsonb_array_length(v_correction->'labels') IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'restoration omitted returning labels';END IF;
 PERFORM eogp.restore_guest_registry_merge_reviewed(v_org,v_actor,v_merge,(v_correction->>'reviewId')::uuid,ARRAY[v_contact2],ARRAY[v_reference2],false,'return_selected_current_records');
 IF NOT EXISTS(SELECT 1 FROM eogp.registry_person_label_assignments WHERE organization_id=v_org AND person_id=v_source2 AND label_id=v_label) THEN RAISE EXCEPTION 'reviewed correction orphaned labels';END IF;
 IF NOT EXISTS(SELECT 1 FROM eogp.person_contact_points WHERE organization_id=v_org AND id=v_contact2 AND person_id=v_source2 AND contact_consent='restricted') OR NOT EXISTS(SELECT 1 FROM eogp.person_identifiers WHERE organization_id=v_org AND id=v_reference2 AND person_id=v_source2 AND encryption_person_id=v_destination2) THEN RAISE EXCEPTION 'reviewed correction lost current linked facts';END IF;

 -- Removing and re-adding an assignment cannot bypass its original-state guard.
 SELECT revision INTO v_revision FROM eogp.persons WHERE organization_id=v_org AND id=v_source2;
 SELECT revision INTO v_destination_revision FROM eogp.persons WHERE organization_id=v_org AND id=v_destination2;
 v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source2,v_destination2);
 v_result:=eogp.commit_guest_registry_merge(v_org,v_actor,v_source2,v_destination2,v_revision,v_destination_revision,'duplicate_profile',(v_review->>'reviewId')::uuid,'move_to_destination','move_to_destination','move_to_destination');v_merge:=(v_result->>'mergeId')::uuid;
 v_correction:=eogp.preview_guest_registry_merge_restoration(v_org,v_actor,v_merge);
 SELECT revision INTO v_destination_revision FROM eogp.persons WHERE organization_id=v_org AND id=v_destination2;
 PERFORM eogp.set_registry_person_labels(v_org,v_actor,v_destination2,v_destination_revision,ARRAY[]::uuid[]);
 BEGIN PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);RAISE EXCEPTION 'removed labels restored automatically';EXCEPTION WHEN SQLSTATE 'P1911' THEN NULL;END;
 BEGIN PERFORM eogp.restore_guest_registry_merge_reviewed(v_org,v_actor,v_merge,(v_correction->>'reviewId')::uuid,ARRAY[]::uuid[],ARRAY[]::uuid[],false,'return_selected_current_records');RAISE EXCEPTION 'reviewed path bypassed label guard';EXCEPTION WHEN SQLSTATE 'P1911' THEN NULL;END;
 IF NOT EXISTS(SELECT 1 FROM eogp.persons WHERE organization_id=v_org AND id=v_source2 AND status='merged') OR (SELECT person_id FROM eogp.person_contact_points WHERE organization_id=v_org AND id=v_contact2) IS DISTINCT FROM v_destination2 OR (SELECT person_id FROM eogp.person_identifiers WHERE organization_id=v_org AND id=v_reference2) IS DISTINCT FROM v_destination2 THEN RAISE EXCEPTION 'blocked label restoration partially moved linked records';END IF;
 PERFORM eogp.set_registry_person_labels(v_org,v_actor,v_destination2,v_destination_revision+1,ARRAY[v_label]);
 BEGIN PERFORM eogp.preview_guest_registry_merge_restoration(v_org,v_actor,v_merge);RAISE EXCEPTION 're-added assignment bypassed state guard';EXCEPTION WHEN SQLSTATE 'P1911' THEN NULL;END;
 v_limit_source:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Synthetic","lastName":"Label limit source"}')->>'personId')::uuid;
 v_limit_destination:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Synthetic","lastName":"Label limit destination"}')->>'personId')::uuid;
 WITH inserted AS (INSERT INTO eogp.registry_labels(organization_id,label) SELECT v_org,'Synthetic merge limit '||series::text FROM generate_series(1,100) series RETURNING id) SELECT array_agg(id) INTO v_limit_labels FROM inserted;
 PERFORM eogp.set_registry_person_labels(v_org,v_actor,v_limit_source,1,v_limit_labels);
 PERFORM eogp.set_registry_person_labels(v_org,v_actor,v_limit_destination,1,ARRAY[v_keep]);
 v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_limit_source,v_limit_destination);
 IF v_review->>'blocker' IS DISTINCT FROM 'label_limit' THEN RAISE EXCEPTION 'combined assignment limit ignored';END IF;
 BEGIN PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_limit_source,v_limit_destination,2,2,'duplicate_profile',(v_review->>'reviewId')::uuid,NULL,NULL,'move_to_destination');RAISE EXCEPTION 'over-limit labels merged';EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL;END;
 BEGIN UPDATE eogp.person_merge_label_transfers SET transferred_state_sha256=repeat('0',64) WHERE organization_id=v_org AND merge_id=v_merge;RAISE EXCEPTION 'transfer journal mutable';EXCEPTION WHEN object_not_in_prerequisite_state OR insufficient_privilege THEN NULL;END;
 PERFORM set_config('app.organization_id','10000000-0000-0000-0000-00000000000b',true);
 BEGIN PERFORM eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);RAISE EXCEPTION 'cross-tenant classification review accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 PERFORM set_config('app.organization_id',v_org::text,true);
 DELETE FROM eogp.role_permissions WHERE organization_id=v_org AND role_id=v_role AND permission_code='guest.registry.contacts.manage';
 BEGIN PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,2,2,'duplicate_profile',(v_review->>'reviewId')::uuid,'move_to_destination',NULL,'move_to_destination');RAISE EXCEPTION 'requested contact transfer bypassed its field permission';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 INSERT INTO eogp.role_permissions VALUES(v_org,v_role,'guest.registry.contacts.manage');
 DELETE FROM eogp.role_permissions WHERE organization_id=v_org AND role_id=v_role AND permission_code='guest.registry.references.manage';
 BEGIN PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,2,2,'duplicate_profile',(v_review->>'reviewId')::uuid,NULL,'move_to_destination','move_to_destination');RAISE EXCEPTION 'requested reference transfer bypassed its field permission';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 DELETE FROM eogp.role_permissions WHERE organization_id=v_org AND role_id=v_role AND permission_code='guest.registry.manage';
 BEGIN PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);RAISE EXCEPTION 'restoration after revocation exposed label state';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 IF has_table_privilege('eventor_runtime','eogp.person_merge_label_transfers','SELECT,INSERT,UPDATE,DELETE') OR has_function_privilege('eventor_runtime','eogp.commit_guest_registry_merge_without_label_transfer(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text,text)','EXECUTE') OR has_function_privilege('eventor_runtime','eogp.restore_guest_registry_merge_reviewed_without_labels(uuid,uuid,uuid,uuid,uuid[],uuid[],boolean,text)','EXECUTE') THEN RAISE EXCEPTION 'private label transfer boundary exposed';END IF;
END;
$test$;
ROLLBACK;
\echo 'Reviewed Registry label merge and restoration smoke passed.'
