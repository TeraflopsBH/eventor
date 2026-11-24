-- Review current transferred records, preserve their facts, and never recreate removed references.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
DO $test$
DECLARE
  v_org CONSTANT uuid:='10000000-0000-0000-0000-00000000000a';
  v_user uuid:=gen_random_uuid(); v_actor uuid:=gen_random_uuid(); v_other_user uuid:=gen_random_uuid(); v_other_actor uuid:=gen_random_uuid(); v_role uuid:=gen_random_uuid();
  v_source uuid; v_destination uuid; v_keep_source uuid; v_missing_source uuid; v_merge uuid; v_other_merge uuid;
  v_contact uuid:=gen_random_uuid(); v_kept_contact uuid:=gen_random_uuid(); v_other_contact uuid:=gen_random_uuid(); v_keep_contact uuid;
  v_reference uuid; v_removed uuid; v_other_reference uuid; v_missing_reference uuid;
  v_review jsonb; v_result jsonb; v_before_contact jsonb; v_before_reference jsonb; v_resolution jsonb; v_dest_revision integer;
  v_cipher bytea:=convert_to('ECP1'||repeat('current-record-',4),'UTF8');
  v_changed_cipher bytea:=convert_to('ECP1'||repeat('edited-record-',4),'UTF8');
BEGIN
  PERFORM set_config('app.organization_id',v_org::text,true);
  PERFORM set_config('app.actor_membership_id',v_actor::text,true);
  INSERT INTO eogp.users(id,email,display_name,status) VALUES
    (v_user,'restore-'||v_user::text||'@example.invalid','Restoration fixture','active'),
    (v_other_user,'restore-'||v_other_user::text||'@example.invalid','Other restoration fixture','active');
  INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status,joined_at) VALUES
    (v_actor,v_org,v_user,'active',clock_timestamp()),(v_other_actor,v_org,v_other_user,'active',clock_timestamp());
  INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(v_role,v_org,'CI-REVIEWED-RESTORATION','Reviewed restoration fixture','organization');
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
    SELECT v_org,v_role,code FROM unnest(ARRAY['guest.registry.read','guest.registry.manage','guest.registry.merge','guest.registry.contacts.manage','guest.registry.references.manage']) code;
  INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id)
    VALUES(v_org,v_actor,v_role,'organization',v_actor),(v_org,v_other_actor,v_role,'organization',v_actor);
  v_source:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Correction","lastName":"Source"}')->>'personId')::uuid;
  v_destination:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Correction","lastName":"Destination"}')->>'personId')::uuid;
  INSERT INTO eogp.person_contact_points(id,organization_id,person_id,contact_kind,normalized_value_hash,encrypted_value,is_primary,contact_consent,
    is_verified,verification_method,verified_at,verified_by_membership_id)
    VALUES(v_contact,v_org,v_source,'email',repeat('1',64),v_cipher,true,'restricted',true,'in_person',clock_timestamp(),v_actor);
  INSERT INTO eogp.person_contact_points(id,organization_id,person_id,contact_kind,normalized_value_hash,encrypted_value,contact_consent)
    VALUES(v_kept_contact,v_org,v_source,'phone',repeat('2',64),v_cipher,'permitted'),
      (v_other_contact,v_org,v_destination,'email',repeat('9',64),v_cipher,'permitted');
  v_reference:=(eogp.write_guest_registry_reference(v_org,v_actor,v_source,NULL,1,'add','CI-CORRECTION-A',repeat('1',64),v_cipher)->>'referenceId')::uuid;
  v_removed:=(eogp.write_guest_registry_reference(v_org,v_actor,v_source,NULL,2,'add','CI-CORRECTION-B',repeat('2',64),v_cipher)->>'referenceId')::uuid;
  v_other_reference:=(eogp.write_guest_registry_reference(v_org,v_actor,v_destination,NULL,1,'add','CI-CORRECTION-DEST',repeat('9',64),v_cipher)->>'referenceId')::uuid;
  v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
  v_merge:=(eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,3,2,'duplicate_profile',(v_review->>'reviewId')::uuid,
    'move_to_destination','move_to_destination')->>'mergeId')::uuid;
  PERFORM eogp.write_guest_registry_contact(v_org,v_actor,v_destination,v_contact,2,NULL,NULL,NULL,'withdrawn',false);
  PERFORM eogp.write_guest_registry_contact(v_org,v_actor,v_destination,v_kept_contact,2,NULL,NULL,NULL,'unknown',false);
  PERFORM eogp.write_guest_registry_reference(v_org,v_actor,v_destination,v_reference,3,'replace','CI-CORRECTION-A',repeat('3',64),v_changed_cipher);
  PERFORM eogp.write_guest_registry_reference(v_org,v_actor,v_destination,v_removed,4,'remove',NULL,NULL,NULL);
  BEGIN
    PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);
    RAISE EXCEPTION 'strict restoration unexpectedly accepted changed records';
  EXCEPTION WHEN SQLSTATE 'P1831' THEN NULL; END;
  v_review:=eogp.preview_guest_registry_merge_restoration(v_org,v_actor,v_merge);
  IF v_review ? 'stateHash' OR v_review->>'missingReferenceCount'<>'1'
    OR jsonb_array_length(v_review->'contacts')<>2 OR jsonb_array_length(v_review->'references')<>2
    OR NOT (v_review->'references' @> jsonb_build_array(jsonb_build_object('referenceId',v_removed,'missing',true,'changed',true))) THEN
    RAISE EXCEPTION 'review lost current-state annotations or exposed private state evidence'; END IF;
  DELETE FROM eogp.role_permissions WHERE organization_id=v_org AND role_id=v_role AND permission_code='guest.registry.references.manage';
  BEGIN
    PERFORM eogp.preview_guest_registry_merge_restoration(v_org,v_actor,v_merge);
    RAISE EXCEPTION 'review exposed reference state without permission';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM eogp.restore_guest_registry_merge_reviewed(v_org,v_actor,v_merge,(v_review->>'reviewId')::uuid,ARRAY[v_contact],ARRAY[v_reference],true,'return_selected_current_records');
    RAISE EXCEPTION 'reviewed apply bypassed revoked reference authority';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  INSERT INTO eogp.role_permissions VALUES(v_org,v_role,'guest.registry.references.manage');
  DELETE FROM eogp.role_permissions WHERE organization_id=v_org AND role_id=v_role AND permission_code='guest.registry.contacts.manage';
  BEGIN
    PERFORM eogp.restore_guest_registry_merge_reviewed(v_org,v_actor,v_merge,(v_review->>'reviewId')::uuid,ARRAY[]::uuid[],ARRAY[v_reference],true,'return_selected_current_records');
    RAISE EXCEPTION 'keeping contacts bypassed original contact authority';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  INSERT INTO eogp.role_permissions VALUES(v_org,v_role,'guest.registry.contacts.manage');
  PERFORM eogp.write_guest_registry_contact(v_org,v_actor,v_destination,v_kept_contact,3,NULL,NULL,NULL,'restricted',false);
  BEGIN
    PERFORM eogp.restore_guest_registry_merge_reviewed(v_org,v_actor,v_merge,(v_review->>'reviewId')::uuid,ARRAY[v_contact],ARRAY[v_reference],true,'return_selected_current_records');
    RAISE EXCEPTION 'a kept record changed without invalidating the review';
  EXCEPTION WHEN SQLSTATE 'P1841' THEN NULL; END;
  v_review:=eogp.preview_guest_registry_merge_restoration(v_org,v_actor,v_merge);
  BEGIN
    PERFORM eogp.restore_guest_registry_merge_reviewed(v_org,v_actor,v_merge,(v_review->>'reviewId')::uuid,ARRAY[v_other_contact],ARRAY[v_reference],true,'return_selected_current_records');
    RAISE EXCEPTION 'review returned a contact outside this merge journal';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM eogp.restore_guest_registry_merge_reviewed(v_org,v_actor,v_merge,(v_review->>'reviewId')::uuid,ARRAY[v_contact],ARRAY[v_other_reference],true,'return_selected_current_records');
    RAISE EXCEPTION 'review returned a destination reference outside this merge';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM eogp.restore_guest_registry_merge_reviewed(v_org,v_actor,v_merge,(v_review->>'reviewId')::uuid,ARRAY[v_contact],ARRAY[v_removed],true,'return_selected_current_records');
    RAISE EXCEPTION 'review selected a removed reference for return';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM eogp.restore_guest_registry_merge_reviewed(v_org,v_actor,v_merge,(v_review->>'reviewId')::uuid,ARRAY[v_contact,v_contact],ARRAY[v_reference],true,'return_selected_current_records');
    RAISE EXCEPTION 'duplicate contact choices were accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM eogp.restore_guest_registry_merge_reviewed(v_org,v_actor,v_merge,(v_review->>'reviewId')::uuid,ARRAY[v_contact],ARRAY[v_reference],false,'return_selected_current_records');
    RAISE EXCEPTION 'removed references were not explicitly acknowledged';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  PERFORM set_config('app.actor_membership_id',v_other_actor::text,true);
  BEGIN
    PERFORM eogp.restore_guest_registry_merge_reviewed(v_org,v_other_actor,v_merge,(v_review->>'reviewId')::uuid,ARRAY[v_contact],ARRAY[v_reference],true,'return_selected_current_records');
    RAISE EXCEPTION 'another actor reused the restoration review';
  EXCEPTION WHEN SQLSTATE 'P1841' THEN NULL; END;
  PERFORM set_config('app.actor_membership_id',v_actor::text,true);
  IF (SELECT status FROM eogp.persons WHERE id=v_source)<>'merged' OR (SELECT person_id FROM eogp.person_contact_points WHERE id=v_contact)<>v_destination THEN
    RAISE EXCEPTION 'rejected choices partially restored source data'; END IF;
  SELECT to_jsonb(contact)-ARRAY['person_id','revision','updated_at'] INTO v_before_contact FROM eogp.person_contact_points contact WHERE id=v_contact;
  SELECT to_jsonb(identifier)-'person_id' INTO v_before_reference FROM eogp.person_identifiers identifier WHERE id=v_reference;
  v_result:=eogp.restore_guest_registry_merge_reviewed(v_org,v_actor,v_merge,(v_review->>'reviewId')::uuid,ARRAY[v_contact],ARRAY[v_reference],true,'return_selected_current_records');
  IF v_result->>'status'<>'restored' OR (SELECT revision FROM eogp.persons WHERE id=v_source)<>5 OR (SELECT revision FROM eogp.persons WHERE id=v_destination)<>6
    OR NOT EXISTS(SELECT 1 FROM eogp.person_contact_points contact WHERE id=v_contact AND person_id=v_source AND revision=4
      AND to_jsonb(contact)-ARRAY['person_id','revision','updated_at']=v_before_contact)
    OR NOT EXISTS(SELECT 1 FROM eogp.person_identifiers identifier WHERE id=v_reference AND person_id=v_source AND encryption_person_id=v_destination
      AND to_jsonb(identifier)-'person_id'=v_before_reference)
    OR (SELECT person_id FROM eogp.person_contact_points WHERE id=v_kept_contact)<>v_destination
    OR (SELECT revision FROM eogp.person_contact_points WHERE id=v_kept_contact)<>4
    OR (SELECT person_id FROM eogp.person_identifiers WHERE id=v_other_reference)<>v_destination
    OR EXISTS(SELECT 1 FROM eogp.person_identifiers WHERE id=v_removed) THEN
    RAISE EXCEPTION 'reviewed restoration reset current facts, moved unselected records or recreated removed values'; END IF;
  SELECT resolution INTO STRICT v_resolution FROM eogp.person_merge_restoration_records WHERE organization_id=v_org AND merge_id=v_merge;
  IF NOT (v_resolution @> jsonb_build_object('mode','reviewed_current_state','returnedContactIds',jsonb_build_array(v_contact),
    'returnedReferenceIds',jsonb_build_array(v_reference),'keptContactIds',jsonb_build_array(v_kept_contact),'removedReferenceIds',jsonb_build_array(v_removed)))
    OR has_table_privilege('eventor_runtime','eogp.person_merge_restoration_records','SELECT,INSERT,UPDATE,DELETE')
    OR has_function_privilege('eventor_runtime','eogp.guest_registry_restoration_state(uuid,eogp.person_merge_records)','EXECUTE')
    OR NOT EXISTS(SELECT 1 FROM jsonb_array_elements(eogp.list_guest_registry_merges(v_org,v_actor,0)->'merges') entry
      WHERE entry->>'mergeId'=v_merge::text AND entry->>'restorationMode'='reviewed_current_state') THEN
    RAISE EXCEPTION 'reviewed resolution lost its immutable evidence or history marker'; END IF;
  PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);
  IF (SELECT person_id FROM eogp.person_contact_points WHERE id=v_kept_contact)<>v_destination
    OR (SELECT revision FROM eogp.person_contact_points WHERE id=v_contact)<>4 THEN
    RAISE EXCEPTION 'legacy restore replay moved kept records or repeated the correction'; END IF;
  BEGIN
    UPDATE eogp.person_merge_restoration_records SET resolution='{}' WHERE organization_id=v_org AND merge_id=v_merge;
    RAISE EXCEPTION 'reviewed correction evidence was mutable';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  BEGIN
    PERFORM eogp.restore_guest_registry_merge_reviewed(v_org,v_actor,v_merge,(v_review->>'reviewId')::uuid,ARRAY[v_contact],ARRAY[v_reference],true,'return_selected_current_records');
    RAISE EXCEPTION 'a second reviewed command changed an already restored merge';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;

  -- Keeping every changed contact is an explicit valid choice and does not need reference authority.
  DELETE FROM eogp.role_permissions WHERE organization_id=v_org AND role_id=v_role AND permission_code='guest.registry.references.manage';
  v_keep_source:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Keep","lastName":"Current contacts"}')->>'personId')::uuid;
  v_keep_contact:=(eogp.write_guest_registry_contact(v_org,v_actor,v_keep_source,NULL,NULL,'email',repeat('8',64),v_cipher,'restricted',false)->>'contactId')::uuid;
  SELECT revision INTO v_dest_revision FROM eogp.persons WHERE id=v_destination;
  v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_keep_source,v_destination);
  v_other_merge:=(eogp.commit_guest_registry_merge(v_org,v_actor,v_keep_source,v_destination,1,v_dest_revision,'duplicate_profile',(v_review->>'reviewId')::uuid,'move_to_destination')->>'mergeId')::uuid;
  PERFORM eogp.write_guest_registry_contact(v_org,v_actor,v_destination,v_keep_contact,2,NULL,NULL,NULL,'withdrawn',false);
  v_review:=eogp.preview_guest_registry_merge_restoration(v_org,v_actor,v_other_merge);
  PERFORM eogp.restore_guest_registry_merge_reviewed(v_org,v_actor,v_other_merge,(v_review->>'reviewId')::uuid,ARRAY[]::uuid[],ARRAY[]::uuid[],false,'return_selected_current_records');
  IF (SELECT status FROM eogp.persons WHERE id=v_keep_source)<>'active'
    OR EXISTS(SELECT 1 FROM eogp.person_contact_points WHERE organization_id=v_org AND person_id=v_keep_source)
    OR (SELECT person_id FROM eogp.person_contact_points WHERE id=v_keep_contact)<>v_destination
    OR (SELECT revision FROM eogp.person_contact_points WHERE id=v_keep_contact)<>3
    OR (SELECT revision FROM eogp.persons WHERE id=v_destination)<>v_dest_revision THEN
    RAISE EXCEPTION 'keeping all current records changed their values or ownership'; END IF;

  -- Missing-reference-only correction needs no contact authority and must leave the reference absent.
  INSERT INTO eogp.role_permissions VALUES(v_org,v_role,'guest.registry.references.manage');
  DELETE FROM eogp.role_permissions WHERE organization_id=v_org AND role_id=v_role AND permission_code='guest.registry.contacts.manage';
  v_missing_source:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Removed","lastName":"Reference only"}')->>'personId')::uuid;
  v_missing_reference:=(eogp.write_guest_registry_reference(v_org,v_actor,v_missing_source,NULL,1,'add','CI-CORRECTION-MISSING',repeat('8',64),v_cipher)->>'referenceId')::uuid;
  SELECT revision INTO v_dest_revision FROM eogp.persons WHERE id=v_destination;
  v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_missing_source,v_destination);
  v_other_merge:=(eogp.commit_guest_registry_merge(v_org,v_actor,v_missing_source,v_destination,2,v_dest_revision,'duplicate_profile',
    (v_review->>'reviewId')::uuid,NULL,'move_to_destination')->>'mergeId')::uuid;
  PERFORM eogp.write_guest_registry_reference(v_org,v_actor,v_destination,v_missing_reference,v_dest_revision+1,'remove',NULL,NULL,NULL);
  v_review:=eogp.preview_guest_registry_merge_restoration(v_org,v_actor,v_other_merge);
  PERFORM eogp.restore_guest_registry_merge_reviewed(v_org,v_actor,v_other_merge,(v_review->>'reviewId')::uuid,ARRAY[]::uuid[],ARRAY[]::uuid[],true,'return_selected_current_records');
  IF (SELECT status FROM eogp.persons WHERE id=v_missing_source)<>'active' OR EXISTS(SELECT 1 FROM eogp.person_identifiers WHERE id=v_missing_reference) THEN
    RAISE EXCEPTION 'missing-reference correction failed or recreated a private value'; END IF;
  BEGIN
    PERFORM eogp.preview_guest_registry_merge_restoration('10000000-0000-0000-0000-00000000000b',v_actor,v_other_merge);
    RAISE EXCEPTION 'restoration review crossed organizations';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END;
$test$;
ROLLBACK;
\echo 'Reviewed Registry restoration correction smoke tests passed.'
