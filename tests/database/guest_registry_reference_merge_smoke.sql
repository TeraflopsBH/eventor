-- Preserve exact source references without exposing values in merge evidence. All synthetic changes roll back.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
DO $test$
DECLARE
  v_org CONSTANT uuid:='10000000-0000-0000-0000-00000000000a';
  v_user uuid:=gen_random_uuid(); v_actor uuid:=gen_random_uuid(); v_role uuid:=gen_random_uuid();
  v_source uuid; v_destination uuid; v_other uuid; v_reference uuid:=gen_random_uuid(); v_contact uuid:=gen_random_uuid();
  v_destination_reference uuid; v_review jsonb; v_merge uuid; v_result jsonb; v_hash text;
  v_source_system text:='CI-MERGE-REF-183';
  v_cipher bytea:=convert_to('ECP1'||repeat('synthetic-reference-',3),'UTF8');
  v_changed_cipher bytea:=convert_to('ECP1'||repeat('changed-reference-',3),'UTF8');
  v_created_at timestamptz:=clock_timestamp();
BEGIN
  PERFORM set_config('app.organization_id',v_org::text,true);
  PERFORM set_config('app.actor_membership_id',v_actor::text,true);
  INSERT INTO eogp.users(id,email,display_name,status) VALUES(v_user,'reference-merge-'||v_user::text||'@example.invalid','Reference merge fixture','active');
  INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status,joined_at) VALUES(v_actor,v_org,v_user,'active',clock_timestamp());
  INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(v_role,v_org,'CI-REFERENCE-MERGE','Reference merge fixture','organization');
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
    SELECT v_org,v_role,code FROM unnest(ARRAY['guest.registry.read','guest.registry.manage','guest.registry.merge','guest.registry.contacts.manage']) code;
  INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id)
    VALUES(v_org,v_actor,v_role,'organization',v_actor);
  v_source:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Reference","lastName":"Source"}')->>'personId')::uuid;
  v_destination:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Reference","lastName":"Destination"}')->>'personId')::uuid;
  INSERT INTO eogp.person_identifiers(id,organization_id,person_id,identifier_kind,identifier_hash,encrypted_value,created_at)
    VALUES(v_reference,v_org,v_source,'external-ref-v1:'||v_source_system,repeat('1',64),v_cipher,v_created_at);
  INSERT INTO eogp.person_contact_points(id,organization_id,person_id,contact_kind,normalized_value_hash,encrypted_value,contact_consent)
    VALUES(v_contact,v_org,v_source,'email',repeat('7',64),v_cipher,'withdrawn');
  v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
  IF v_review->>'blocker' IS DISTINCT FROM 'reference_access_required' OR v_review->>'referenceCount'<>'0' THEN
    RAISE EXCEPTION 'merge-only staff received source-reference transfer access or counts'; END IF;
  INSERT INTO eogp.role_permissions VALUES(v_org,v_role,'guest.registry.references.manage');
  v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
  IF v_review->'blocker'<>'null'::jsonb OR v_review->>'referenceCount'<>'1' OR v_review->>'contactCount'<>'1' THEN
    RAISE EXCEPTION 'supported reference/contact combination was not eligible'; END IF;
  BEGIN
    PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,1,1,'duplicate_profile',(v_review->>'reviewId')::uuid);
    RAISE EXCEPTION 'eight-argument merge bypassed explicit reference resolution';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,1,1,'duplicate_profile',(v_review->>'reviewId')::uuid,'move_to_destination');
    RAISE EXCEPTION 'nine-argument merge bypassed explicit reference resolution';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,1,1,'duplicate_profile',(v_review->>'reviewId')::uuid,NULL,'move_to_destination');
    RAISE EXCEPTION 'reference-only resolution bypassed the contact choice';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  IF (SELECT person_id FROM eogp.person_identifiers WHERE id=v_reference)<>v_source THEN
    RAISE EXCEPTION 'failed combined resolution partially moved references'; END IF;
  PERFORM eogp.write_guest_registry_reference(v_org,v_actor,v_source,v_reference,1,'replace',v_source_system,repeat('2',64),v_changed_cipher);
  BEGIN
    PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,1,1,'duplicate_profile',(v_review->>'reviewId')::uuid,'move_to_destination','move_to_destination');
    RAISE EXCEPTION 'stale source-reference review was accepted';
  EXCEPTION WHEN serialization_failure THEN NULL; END;
  v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
  v_destination_reference:=(eogp.write_guest_registry_reference(v_org,v_actor,v_destination,NULL,1,'add','CI-DEST-MERGE-183',repeat('3',64),v_cipher)->>'referenceId')::uuid;
  BEGIN
    PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,2,1,'duplicate_profile',(v_review->>'reviewId')::uuid,'move_to_destination','move_to_destination');
    RAISE EXCEPTION 'stale destination reference set was accepted';
  EXCEPTION WHEN serialization_failure THEN NULL; END;
  v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
  v_merge:=(eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,2,2,'duplicate_profile',
    (v_review->>'reviewId')::uuid,'move_to_destination','move_to_destination')->>'mergeId')::uuid;
  IF NOT EXISTS(SELECT 1 FROM eogp.person_identifiers WHERE id=v_reference AND person_id=v_destination
      AND identifier_kind='external-ref-v1:'||v_source_system AND identifier_hash=repeat('2',64)
      AND encrypted_value=v_changed_cipher AND encryption_person_id=v_source AND created_at=v_created_at)
    OR NOT eogp.guest_import_reference_matches(v_org,v_destination,v_source_system,repeat('2',64))
    OR eogp.guest_import_reference_matches(v_org,v_source,v_source_system,repeat('2',64))
    OR (SELECT revision FROM eogp.persons WHERE id=v_destination)<>3
    OR has_table_privilege('eventor_runtime','eogp.person_merge_reference_transfers','SELECT,INSERT,UPDATE,DELETE')
    OR has_function_privilege('eventor_runtime','eogp.commit_guest_registry_merge_without_reference_transfer(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text)','EXECUTE')
    OR has_function_privilege('eventor_runtime','eogp.restore_guest_registry_merge_without_reference_transfer(uuid,uuid,uuid)','EXECUTE')
    OR has_function_privilege('eventor_runtime','eogp.guest_registry_reference_state_hash_v1(eogp.person_identifiers)','EXECUTE') THEN
    RAISE EXCEPTION 'reference transfer changed protected values, matching, revision or private boundaries'; END IF;
  DELETE FROM eogp.role_permissions WHERE organization_id=v_org AND role_id=v_role AND permission_code='guest.registry.references.manage';
  BEGIN
    PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);
    RAISE EXCEPTION 'reference merge restored without reference permission';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM eogp.assert_guest_registry_merge_restore_permission(v_org,v_actor,v_merge);
    RAISE EXCEPTION 'restoration replay bypassed reference permission';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  INSERT INTO eogp.role_permissions VALUES(v_org,v_role,'guest.registry.references.manage');
  SELECT eogp.guest_registry_reference_state_hash_v1(identifier) INTO v_hash FROM eogp.person_identifiers identifier WHERE id=v_reference;
  PERFORM set_config('TimeZone','Pacific/Auckland',true);
  PERFORM set_config('bytea_output','escape',true);
  IF (SELECT eogp.guest_registry_reference_state_hash_v1(identifier) FROM eogp.person_identifiers identifier WHERE id=v_reference)<>v_hash THEN
    RAISE EXCEPTION 'reference state evidence depended on session formatting'; END IF;
  PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);
  PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);
  IF NOT eogp.guest_import_reference_matches(v_org,v_source,v_source_system,repeat('2',64))
    OR eogp.guest_import_reference_matches(v_org,v_destination,v_source_system,repeat('2',64))
    OR NOT EXISTS(SELECT 1 FROM eogp.person_identifiers WHERE id=v_destination_reference AND person_id=v_destination)
    OR (SELECT revision FROM eogp.persons WHERE id=v_source)<>4 OR (SELECT revision FROM eogp.persons WHERE id=v_destination)<>4
    OR NOT EXISTS(SELECT 1 FROM eogp.person_contact_points WHERE id=v_contact AND person_id=v_source AND contact_consent='withdrawn' AND revision=3) THEN
    RAISE EXCEPTION 'combined restoration lost exact references, contacts or profile revision semantics'; END IF;
  -- Reference-only merges do not require contact-management authority.
  DELETE FROM eogp.role_permissions WHERE organization_id=v_org AND role_id=v_role AND permission_code='guest.registry.contacts.manage';
  v_other:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Reference","lastName":"Only"}')->>'personId')::uuid;
  PERFORM eogp.write_guest_registry_reference(v_org,v_actor,v_other,NULL,1,'add','CI-ONLY-MERGE-183',repeat('5',64),v_cipher);
  v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_other,v_destination);
  IF v_review->'blocker'<>'null'::jsonb OR v_review->>'contactCount'<>'0' THEN
    RAISE EXCEPTION 'reference-only merge unnecessarily required contact access'; END IF;
  v_result:=eogp.commit_guest_registry_merge(v_org,v_actor,v_other,v_destination,2,4,'duplicate_profile',
    (v_review->>'reviewId')::uuid,NULL,'move_to_destination');
  PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,(v_result->>'mergeId')::uuid);
  IF NOT eogp.guest_import_reference_matches(v_org,v_other,'CI-ONLY-MERGE-183',repeat('5',64))
    OR (SELECT revision FROM eogp.persons WHERE id=v_destination)<>6 THEN
    RAISE EXCEPTION 'reference-only restoration lost its identity or destination revision'; END IF;
  INSERT INTO eogp.role_permissions VALUES(v_org,v_role,'guest.registry.contacts.manage');
  v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
  v_merge:=(eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,4,6,'duplicate_profile',
    (v_review->>'reviewId')::uuid,'move_to_destination','move_to_destination')->>'mergeId')::uuid;
  PERFORM eogp.write_guest_registry_reference(v_org,v_actor,v_destination,v_reference,7,'replace',v_source_system,repeat('4',64),v_cipher);
  BEGIN
    PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);
    RAISE EXCEPTION 'restoration silently reassigned an edited reference';
  EXCEPTION WHEN SQLSTATE 'P1831' THEN NULL; END;
  IF (SELECT status FROM eogp.persons WHERE id=v_source)<>'merged'
    OR (SELECT person_id FROM eogp.person_contact_points WHERE id=v_contact)<>v_destination
    OR (SELECT restored_at FROM eogp.person_merge_records WHERE id=v_merge) IS NOT NULL THEN
    RAISE EXCEPTION 'reference conflict partially restored contacts or source'; END IF;
  PERFORM eogp.write_guest_registry_reference(v_org,v_actor,v_destination,v_reference,8,'remove',NULL,NULL,NULL);
  BEGIN
    PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);
    RAISE EXCEPTION 'restoration recreated a removed private reference';
  EXCEPTION WHEN SQLSTATE 'P1831' THEN NULL; END;
  IF EXISTS(SELECT 1 FROM eogp.person_identifiers WHERE id=v_reference) THEN RAISE EXCEPTION 'removed reference was resurrected'; END IF;
  BEGIN
    UPDATE eogp.person_merge_reference_transfers SET transferred_state_sha256=repeat('9',64) WHERE organization_id=v_org AND merge_id=v_merge;
    RAISE EXCEPTION 'reference transfer journal was mutable';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  v_other:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Unsupported","lastName":"Identifier"}')->>'personId')::uuid;
  INSERT INTO eogp.person_identifiers(organization_id,person_id,identifier_kind,identifier_hash,encrypted_value)
    VALUES(v_org,v_other,'unsupported-private-kind',repeat('8',64),v_cipher);
  IF eogp.preview_guest_registry_merge(v_org,v_actor,v_other,v_destination)->>'blocker' IS DISTINCT FROM 'source_has_linked_records' THEN
    RAISE EXCEPTION 'source-reference grant exposed an unsupported identifier merge'; END IF;
  BEGIN
    PERFORM eogp.preview_guest_registry_merge('10000000-0000-0000-0000-00000000000b',v_actor,v_other,v_destination);
    RAISE EXCEPTION 'reference merge crossed organizations';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END;
$test$;
ROLLBACK;
\echo 'Reviewed Registry reference merge smoke tests passed.'
