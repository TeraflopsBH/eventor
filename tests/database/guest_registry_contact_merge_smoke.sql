-- Reversible contact transfer uses real permission and merge commands. Synthetic data rolls back.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_user uuid:=gen_random_uuid(); v_actor uuid:=gen_random_uuid(); v_role uuid:=gen_random_uuid();
  v_source uuid; v_destination uuid; v_contact uuid:=gen_random_uuid(); v_phone uuid:=gen_random_uuid();
  v_conflict uuid:=gen_random_uuid(); v_review jsonb; v_merge uuid; v_revision integer;
  v_cipher bytea:=convert_to('ECP1'||repeat('synthetic-contact-',3),'UTF8');
  v_verified_at timestamptz:=clock_timestamp();
BEGIN
  PERFORM set_config('app.organization_id',v_org::text,true);
  PERFORM set_config('app.actor_membership_id',v_actor::text,true);
  INSERT INTO eogp.users(id,email,display_name,status) VALUES(v_user,'contact-merge-'||v_user::text||'@example.invalid','Contact merge fixture','active');
  INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status,joined_at) VALUES(v_actor,v_org,v_user,'active',clock_timestamp());
  INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(v_role,v_org,'CI-CONTACT-MERGE','Contact merge fixture','organization');
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
    SELECT v_org,v_role,code FROM unnest(ARRAY['guest.registry.read','guest.registry.manage','guest.registry.merge']) code;
  INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id)
    VALUES(v_org,v_actor,v_role,'organization',v_actor);
  v_source:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Contact","lastName":"Source"}')->>'personId')::uuid;
  v_destination:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Contact","lastName":"Destination"}')->>'personId')::uuid;
  INSERT INTO eogp.person_contact_points(id,organization_id,person_id,contact_kind,normalized_value_hash,encrypted_value,
    is_primary,contact_consent,is_verified,verification_method,verified_at,verified_by_membership_id)
    VALUES(v_contact,v_org,v_source,'email',repeat('1',64),v_cipher,true,'restricted',true,'in_person',v_verified_at,v_actor);
  INSERT INTO eogp.person_contact_points(id,organization_id,person_id,contact_kind,normalized_value_hash,encrypted_value,is_primary,contact_consent)
    VALUES(v_phone,v_org,v_source,'phone',repeat('2',64),v_cipher,false,'withdrawn');
  v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
  IF v_review->>'blocker' IS DISTINCT FROM 'contact_access_required' OR v_review->>'contactCount'<>'0' THEN
    RAISE EXCEPTION 'merge-only staff received contact transfer access or counts';
  END IF;
  INSERT INTO eogp.role_permissions VALUES(v_org,v_role,'guest.registry.contacts.manage');
  INSERT INTO eogp.person_contact_points(id,organization_id,person_id,contact_kind,normalized_value_hash,encrypted_value)
    VALUES(v_conflict,v_org,v_source,'email',repeat('1',64),v_cipher);
  IF eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination)->>'blocker' IS DISTINCT FROM 'contact_conflict' THEN
    RAISE EXCEPTION 'duplicate legacy source contacts did not block merge'; END IF;
  UPDATE eogp.person_contact_points SET normalized_value_hash=repeat('4',64),is_primary=true WHERE id=v_conflict;
  IF eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination)->>'blocker' IS DISTINCT FROM 'contact_conflict' THEN
    RAISE EXCEPTION 'competing legacy source primaries did not block merge'; END IF;
  DELETE FROM eogp.person_contact_points WHERE id=v_conflict;
  v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
  IF v_review->'blocker'<>'null'::jsonb OR v_review->>'contactCount'<>'2' THEN RAISE EXCEPTION 'non-conflicting contacts were not eligible'; END IF;
  BEGIN
    PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,1,1,'duplicate_profile',(v_review->>'reviewId')::uuid);
    RAISE EXCEPTION 'legacy merge implicitly moved contacts';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  -- A child revision change invalidates the review even when person revisions are unchanged.
  PERFORM eogp.write_guest_registry_contact(v_org,v_actor,v_source,v_contact,1,NULL,NULL,NULL,'restricted',true);
  BEGIN
    PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,1,1,'duplicate_profile',(v_review->>'reviewId')::uuid,'move_to_destination');
    RAISE EXCEPTION 'stale source contact review was accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
  INSERT INTO eogp.person_contact_points(id,organization_id,person_id,contact_kind,normalized_value_hash,encrypted_value)
    VALUES(v_conflict,v_org,v_destination,'phone',repeat('3',64),v_cipher);
  BEGIN
    PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,1,1,'duplicate_profile',(v_review->>'reviewId')::uuid,'move_to_destination');
    RAISE EXCEPTION 'destination contact changes escaped review';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  DELETE FROM eogp.person_contact_points WHERE id=v_conflict;
  v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
  v_merge:=(eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,1,1,'duplicate_profile',
    (v_review->>'reviewId')::uuid,'move_to_destination')->>'mergeId')::uuid;
  IF (SELECT count(*) FROM eogp.person_merge_contact_transfers WHERE organization_id=v_org AND merge_id=v_merge)<>2
    OR NOT EXISTS(SELECT 1 FROM eogp.person_contact_points WHERE id=v_contact AND person_id=v_destination AND revision=3
      AND encrypted_value=v_cipher AND normalized_value_hash=repeat('1',64) AND contact_consent='restricted' AND is_primary
      AND is_verified AND verification_method='in_person' AND verified_at=v_verified_at AND verified_by_membership_id=v_actor)
    OR NOT EXISTS(SELECT 1 FROM eogp.person_contact_points WHERE id=v_phone AND person_id=v_destination AND contact_consent='withdrawn' AND NOT is_verified AND NOT is_primary)
    OR has_table_privilege('eventor_runtime','eogp.person_merge_contact_transfers','SELECT,INSERT,UPDATE,DELETE')
    OR has_function_privilege('eventor_runtime','eogp.commit_guest_registry_merge_without_contact_transfer(uuid,uuid,uuid,uuid,integer,integer,text,uuid)','EXECUTE')
    OR has_function_privilege('eventor_runtime','eogp.restore_guest_registry_merge_without_contact_transfer(uuid,uuid,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'contact transfer changed protected facts or exposed private commands/journal';
  END IF;
  DELETE FROM eogp.role_permissions WHERE organization_id=v_org AND role_id=v_role AND permission_code='guest.registry.contacts.manage';
  BEGIN
    PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);
    RAISE EXCEPTION 'contact merge restored without contact permission';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  BEGIN
    PERFORM eogp.assert_guest_registry_merge_restore_permission(v_org,v_actor,v_merge);
    RAISE EXCEPTION 'restoration replay escaped contact permission';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  INSERT INTO eogp.role_permissions VALUES(v_org,v_role,'guest.registry.contacts.manage');
  PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);
  PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);
  IF NOT EXISTS(SELECT 1 FROM eogp.person_contact_points WHERE id=v_contact AND person_id=v_source AND revision=4
    AND encrypted_value=v_cipher AND contact_consent='restricted' AND is_verified AND is_primary AND verified_at=v_verified_at)
    OR (SELECT status FROM eogp.persons WHERE id=v_source)<>'active' THEN
    RAISE EXCEPTION 'restoration did not return the same contacts and evidence exactly once';
  END IF;
  INSERT INTO eogp.person_contact_points(id,organization_id,person_id,contact_kind,normalized_value_hash,encrypted_value)
    VALUES(v_conflict,v_org,v_destination,'email',repeat('1',64),v_cipher);
  IF eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination)->>'blocker' IS DISTINCT FROM 'contact_conflict' THEN
    RAISE EXCEPTION 'duplicate contact value did not block merge'; END IF;
  UPDATE eogp.person_contact_points SET normalized_value_hash=repeat('4',64),is_primary=true WHERE id=v_conflict;
  IF eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination)->>'blocker' IS DISTINCT FROM 'contact_conflict' THEN
    RAISE EXCEPTION 'competing primary contacts did not block merge'; END IF;
  DELETE FROM eogp.person_contact_points WHERE id=v_conflict;
  v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
  v_merge:=(eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,3,1,'duplicate_profile',
    (v_review->>'reviewId')::uuid,'move_to_destination')->>'mergeId')::uuid;
  SELECT revision INTO v_revision FROM eogp.person_contact_points WHERE id=v_contact;
  PERFORM eogp.write_guest_registry_contact(v_org,v_actor,v_destination,v_contact,v_revision,NULL,NULL,NULL,'restricted',false);
  BEGIN
    PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);
    RAISE EXCEPTION 'restoration silently overwrote an edited transferred contact';
  EXCEPTION WHEN SQLSTATE 'P1821' THEN NULL; END;
  IF (SELECT status FROM eogp.persons WHERE id=v_source)<>'merged'
    OR (SELECT restored_at FROM eogp.person_merge_records WHERE id=v_merge) IS NOT NULL THEN
    RAISE EXCEPTION 'failed contact restoration partially changed merge state'; END IF;
  BEGIN
    UPDATE eogp.person_merge_contact_transfers SET transferred_revision=999 WHERE organization_id=v_org AND merge_id=v_merge;
    RAISE EXCEPTION 'contact transfer journal was mutable';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  BEGIN
    PERFORM eogp.preview_guest_registry_merge('10000000-0000-0000-0000-00000000000b',v_actor,v_source,v_destination);
    RAISE EXCEPTION 'contact merge crossed organizations';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END;
$test$;
ROLLBACK;
\echo 'Reviewed Registry contact merge smoke tests passed.'
