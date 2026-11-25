\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
DO $test$
DECLARE
 v_org CONSTANT uuid:='10000000-0000-0000-0000-00000000000a';
 v_actor uuid:=gen_random_uuid();v_user uuid:=gen_random_uuid();v_role uuid:=gen_random_uuid();
 v_source uuid;v_destination uuid;v_third uuid;v_other uuid;v_out uuid;v_in uuid;v_mutual uuid;v_ended uuid;v_keep uuid;v_self uuid;v_duplicate uuid;
 v_comb_source uuid;v_comb_dest uuid;v_comb_rel uuid;v_comb_label uuid;v_comb_contact uuid:=gen_random_uuid();v_comb_reference uuid:=gen_random_uuid();
 v_cipher bytea:=convert_to('ECP1'||repeat('synthetic-relationship-merge-',4),'UTF8');
 v_review jsonb;v_result jsonb;v_merge uuid;v_correction jsonb;v_before jsonb;v_revision integer;v_dest_revision integer;
BEGIN
 PERFORM set_config('app.organization_id',v_org::text,true);PERFORM set_config('app.actor_membership_id',v_actor::text,true);
 INSERT INTO eogp.users(id,email,display_name,status) VALUES(v_user,'relationship-merge-'||v_user::text||'@example.invalid','Synthetic relationship merge operator','active');
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(v_actor,v_org,v_user,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(v_role,v_org,'CI-RELATIONSHIP-MERGE','Synthetic relationship merge role','organization');
 INSERT INTO eogp.role_permissions SELECT v_org,v_role,code FROM unnest(ARRAY['guest.registry.read','guest.registry.manage','guest.registry.merge','guest.registry.relationships.manage']) code;
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(v_org,v_actor,v_role,'organization',v_actor);
 v_source:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Synthetic","lastName":"Relationship source"}')->>'personId')::uuid;
 v_destination:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Synthetic","lastName":"Relationship destination"}')->>'personId')::uuid;
 v_third:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Synthetic","lastName":"Related third"}')->>'personId')::uuid;
 v_other:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Synthetic","lastName":"Unrelated fourth"}')->>'personId')::uuid;
 v_out:=(eogp.write_guest_registry_relationship(v_org,v_actor,v_source,NULL,v_third,'assistant','directed')->>'relationshipId')::uuid;
 v_in:=(eogp.write_guest_registry_relationship(v_org,v_actor,v_third,NULL,v_source,'delegate','directed')->>'relationshipId')::uuid;
 v_mutual:=(eogp.write_guest_registry_relationship(v_org,v_actor,v_source,NULL,v_third,'family','mutual')->>'relationshipId')::uuid;
 v_ended:=(eogp.write_guest_registry_relationship(v_org,v_actor,v_source,NULL,v_other,'colleague','mutual')->>'relationshipId')::uuid;
 PERFORM eogp.write_guest_registry_relationship(v_org,v_actor,v_source,v_ended,NULL,NULL,NULL);
 v_keep:=(eogp.write_guest_registry_relationship(v_org,v_actor,v_destination,NULL,v_other,'colleague','mutual')->>'relationshipId')::uuid;
 SELECT jsonb_object_agg(id::text,to_jsonb(link)) INTO v_before FROM eogp.person_relationships link WHERE organization_id=v_org AND id IN(v_out,v_in,v_mutual,v_ended,v_keep);
 v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
 IF v_review->'blocker' IS DISTINCT FROM 'null'::jsonb OR v_review->>'relationshipCount' IS DISTINCT FROM '3' OR jsonb_array_length(v_review->'sourceRelationships') IS DISTINCT FROM 3 OR jsonb_array_length(v_review->'destinationRelationships') IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'relationship review incorrect: %',v_review;END IF;
 BEGIN PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,1,1,'duplicate_profile',(v_review->>'reviewId')::uuid,NULL,NULL,NULL);RAISE EXCEPTION 'legacy overload moved relationships without choice';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
 DELETE FROM eogp.role_permissions WHERE organization_id=v_org AND role_id=v_role AND permission_code='guest.registry.relationships.manage';
 v_result:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
 IF v_result->>'blocker' IS DISTINCT FROM 'relationship_access_required' OR v_result->'sourceRelationships' IS DISTINCT FROM '[]'::jsonb OR v_result->'destinationRelationships' IS DISTINCT FROM '[]'::jsonb THEN RAISE EXCEPTION 'unauthorized relationship review disclosed links';END IF;
 BEGIN PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,1,1,'duplicate_profile',(v_review->>'reviewId')::uuid,NULL,NULL,NULL,'move_to_destination');RAISE EXCEPTION 'revoked relationship authority accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 INSERT INTO eogp.role_permissions VALUES(v_org,v_role,'guest.registry.relationships.manage');
 v_result:=eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,1,1,'duplicate_profile',(v_review->>'reviewId')::uuid,NULL,NULL,NULL,'move_to_destination');v_merge:=(v_result->>'mergeId')::uuid;
 IF NOT EXISTS(SELECT 1 FROM eogp.person_relationships WHERE id=v_out AND from_person_id=v_destination AND to_person_id=v_third) OR NOT EXISTS(SELECT 1 FROM eogp.person_relationships WHERE id=v_in AND from_person_id=v_third AND to_person_id=v_destination) OR NOT EXISTS(SELECT 1 FROM eogp.person_relationships WHERE id=v_mutual AND from_person_id=least(v_destination,v_third) AND to_person_id=greatest(v_destination,v_third)) THEN RAISE EXCEPTION 'relationship directions lost';END IF;
 IF EXISTS(SELECT 1 FROM eogp.person_relationships link WHERE id IN(v_out,v_in,v_mutual) AND (to_jsonb(link)-'from_person_id'-'to_person_id') IS DISTINCT FROM ((v_before->(id::text))-'from_person_id'-'to_person_id')) OR (SELECT to_jsonb(link) FROM eogp.person_relationships link WHERE id=v_ended) IS DISTINCT FROM v_before->(v_ended::text) OR (SELECT to_jsonb(link) FROM eogp.person_relationships link WHERE id=v_keep) IS DISTINCT FROM v_before->(v_keep::text) THEN RAISE EXCEPTION 'metadata, ended history or unrelated destination link changed';END IF;
 v_correction:=eogp.preview_guest_registry_merge_restoration(v_org,v_actor,v_merge);
 IF jsonb_array_length(v_correction->'relationships') IS DISTINCT FROM 3 THEN RAISE EXCEPTION 'correction preview missing returning links';END IF;
 DELETE FROM eogp.role_permissions WHERE organization_id=v_org AND role_id=v_role AND permission_code='guest.registry.relationships.manage';
 BEGIN PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);RAISE EXCEPTION 'restore after relationship revocation accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM eogp.preview_guest_registry_merge_restoration(v_org,v_actor,v_merge);RAISE EXCEPTION 'correction preview after relationship revocation accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 INSERT INTO eogp.role_permissions VALUES(v_org,v_role,'guest.registry.relationships.manage');
 PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);
 PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);
 IF (SELECT jsonb_object_agg(id::text,to_jsonb(link)) FROM eogp.person_relationships link WHERE organization_id=v_org AND id IN(v_out,v_in,v_mutual,v_ended,v_keep)) IS DISTINCT FROM v_before THEN RAISE EXCEPTION 'strict restoration lost original relationship facts';END IF;
 -- Ending all source links still stales a new review, even through the legacy no-choice overload.
 BEGIN
  v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
  SELECT revision INTO v_revision FROM eogp.persons WHERE id=v_source;
  SELECT revision INTO v_dest_revision FROM eogp.persons WHERE id=v_destination;
  PERFORM eogp.write_guest_registry_relationship(v_org,v_actor,v_source,v_out,NULL,NULL,NULL);
  PERFORM eogp.write_guest_registry_relationship(v_org,v_actor,v_source,v_in,NULL,NULL,NULL);
  PERFORM eogp.write_guest_registry_relationship(v_org,v_actor,v_source,v_mutual,NULL,NULL,NULL);
  BEGIN PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,v_revision,v_dest_revision,'duplicate_profile',(v_review->>'reviewId')::uuid);RAISE EXCEPTION 'all-ended source links bypassed review binding';EXCEPTION WHEN serialization_failure THEN NULL;END;
  RAISE EXCEPTION 'rollback synthetic ended-link case' USING ERRCODE='P9999';
 EXCEPTION WHEN SQLSTATE 'P9999' THEN NULL;
 END;
 -- Relationships that would become self-links or duplicate an active link stay blocked.
 v_self:=(eogp.write_guest_registry_relationship(v_org,v_actor,v_source,NULL,v_destination,'partner','mutual')->>'relationshipId')::uuid;
 IF eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination)->>'blocker' IS DISTINCT FROM 'relationship_self_link' THEN RAISE EXCEPTION 'self-link not blocked';END IF;
 PERFORM eogp.write_guest_registry_relationship(v_org,v_actor,v_source,v_self,NULL,NULL,NULL);
 v_duplicate:=(eogp.write_guest_registry_relationship(v_org,v_actor,v_destination,NULL,v_third,'family','mutual')->>'relationshipId')::uuid;
 IF eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination)->>'blocker' IS DISTINCT FROM 'relationship_conflict' THEN RAISE EXCEPTION 'duplicate active link not blocked';END IF;
 PERFORM eogp.write_guest_registry_relationship(v_org,v_actor,v_destination,v_duplicate,NULL,NULL,NULL);
 SELECT revision INTO v_revision FROM eogp.persons WHERE id=v_source;
 SELECT revision INTO v_dest_revision FROM eogp.persons WHERE id=v_destination;
 -- Directed duplicates are blocked, while the opposite direction remains a distinct fact.
 v_duplicate:=(eogp.write_guest_registry_relationship(v_org,v_actor,v_destination,NULL,v_third,'assistant','directed')->>'relationshipId')::uuid;
 IF eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination)->>'blocker' IS DISTINCT FROM 'relationship_conflict' THEN RAISE EXCEPTION 'directed duplicate not blocked';END IF;
 PERFORM eogp.write_guest_registry_relationship(v_org,v_actor,v_destination,v_duplicate,NULL,NULL,NULL);
 v_duplicate:=(eogp.write_guest_registry_relationship(v_org,v_actor,v_third,NULL,v_destination,'assistant','directed')->>'relationshipId')::uuid;
 IF eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination)->'blocker' IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'opposite direction was treated as a duplicate';END IF;
 PERFORM eogp.write_guest_registry_relationship(v_org,v_actor,v_destination,v_duplicate,NULL,NULL,NULL);
 -- Ending a source link does not update the person revision; its fingerprint must still invalidate review.
 v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
 PERFORM eogp.write_guest_registry_relationship(v_org,v_actor,v_source,v_out,NULL,NULL,NULL);
 BEGIN PERFORM eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,v_revision,v_dest_revision,'duplicate_profile',(v_review->>'reviewId')::uuid,NULL,NULL,NULL,'move_to_destination');RAISE EXCEPTION 'ended source link did not stale review';EXCEPTION WHEN serialization_failure THEN NULL;END;
 v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
 v_result:=eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,v_revision,v_dest_revision,'duplicate_profile',(v_review->>'reviewId')::uuid,NULL,NULL,NULL,'move_to_destination');v_merge:=(v_result->>'mergeId')::uuid;
 v_correction:=eogp.preview_guest_registry_merge_restoration(v_org,v_actor,v_merge);
 PERFORM eogp.restore_guest_registry_merge_reviewed(v_org,v_actor,v_merge,(v_correction->>'reviewId')::uuid,ARRAY[]::uuid[],ARRAY[]::uuid[],false,'return_selected_current_records');
 IF NOT EXISTS(SELECT 1 FROM eogp.person_relationships WHERE id=v_in AND to_person_id=v_source) THEN RAISE EXCEPTION 'reviewed restoration orphaned relationship';END IF;
 -- A later legitimate end blocks every restoration path without undoing that end.
 SELECT revision INTO v_revision FROM eogp.persons WHERE id=v_source;
 SELECT revision INTO v_dest_revision FROM eogp.persons WHERE id=v_destination;
 v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_source,v_destination);
 v_result:=eogp.commit_guest_registry_merge(v_org,v_actor,v_source,v_destination,v_revision,v_dest_revision,'duplicate_profile',(v_review->>'reviewId')::uuid,NULL,NULL,NULL,'move_to_destination');v_merge:=(v_result->>'mergeId')::uuid;
 v_correction:=eogp.preview_guest_registry_merge_restoration(v_org,v_actor,v_merge);
 BEGIN
  DELETE FROM eogp.person_relationships WHERE id=v_in;
  BEGIN PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);RAISE EXCEPTION 'missing transferred relationship recreated';EXCEPTION WHEN SQLSTATE 'P1921' THEN NULL;END;
  RAISE EXCEPTION 'rollback synthetic missing-link case' USING ERRCODE='P9999';
 EXCEPTION WHEN SQLSTATE 'P9999' THEN NULL;
 END;
 BEGIN
  UPDATE eogp.person_relationships SET relationship_kind='other' WHERE id=v_in;
  BEGIN PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);RAISE EXCEPTION 'edited transferred relationship overwritten';EXCEPTION WHEN SQLSTATE 'P1921' THEN NULL;END;
  RAISE EXCEPTION 'rollback synthetic edited-link case' USING ERRCODE='P9999';
 EXCEPTION WHEN SQLSTATE 'P9999' THEN NULL;
 END;
 PERFORM eogp.write_guest_registry_relationship(v_org,v_actor,v_destination,v_in,NULL,NULL,NULL);
 BEGIN PERFORM eogp.restore_guest_registry_merge(v_org,v_actor,v_merge);RAISE EXCEPTION 'ended transferred link restored';EXCEPTION WHEN SQLSTATE 'P1921' THEN NULL;END;
 BEGIN PERFORM eogp.preview_guest_registry_merge_restoration(v_org,v_actor,v_merge);RAISE EXCEPTION 'ended link allowed correction review';EXCEPTION WHEN SQLSTATE 'P1921' THEN NULL;END;
 BEGIN PERFORM eogp.restore_guest_registry_merge_reviewed(v_org,v_actor,v_merge,(v_correction->>'reviewId')::uuid,ARRAY[]::uuid[],ARRAY[]::uuid[],false,'return_selected_current_records');RAISE EXCEPTION 'reviewed path bypassed ended-link guard';EXCEPTION WHEN SQLSTATE 'P1921' THEN NULL;END;
 IF NOT EXISTS(SELECT 1 FROM eogp.persons WHERE id=v_source AND status='merged') OR NOT EXISTS(SELECT 1 FROM eogp.person_relationships WHERE id=v_mutual AND v_destination IN(from_person_id,to_person_id)) THEN RAISE EXCEPTION 'refused restoration partially applied';END IF;
 BEGIN UPDATE eogp.person_merge_relationship_transfers SET transferred_state_sha256=repeat('0',64) WHERE merge_id=v_merge;RAISE EXCEPTION 'relationship journal mutable';EXCEPTION WHEN object_not_in_prerequisite_state OR insufficient_privilege THEN NULL;END;
 -- Compose all four linked-record transfers and return them through reviewed correction.
 INSERT INTO eogp.role_permissions VALUES(v_org,v_role,'guest.registry.contacts.manage'),(v_org,v_role,'guest.registry.references.manage');
 v_comb_source:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Synthetic","lastName":"Combined source"}')->>'personId')::uuid;
 v_comb_dest:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Synthetic","lastName":"Combined destination"}')->>'personId')::uuid;
 v_comb_rel:=(eogp.write_guest_registry_relationship(v_org,v_actor,v_comb_source,NULL,v_third,'family','mutual')->>'relationshipId')::uuid;
 v_comb_label:=(eogp.write_registry_label(v_org,v_actor,NULL,'Synthetic combined relationship label')->>'labelId')::uuid;
 PERFORM eogp.set_registry_person_labels(v_org,v_actor,v_comb_source,1,ARRAY[v_comb_label]);
 INSERT INTO eogp.person_contact_points(id,organization_id,person_id,contact_kind,normalized_value_hash,encrypted_value,contact_consent) VALUES(v_comb_contact,v_org,v_comb_source,'email',repeat('f',64),v_cipher,'withdrawn');
 INSERT INTO eogp.person_identifiers(id,organization_id,person_id,identifier_kind,identifier_hash,encrypted_value) VALUES(v_comb_reference,v_org,v_comb_source,'external-ref-v1:REL-COMBINED',repeat('f',64),v_cipher);
 v_review:=eogp.preview_guest_registry_merge(v_org,v_actor,v_comb_source,v_comb_dest);
 v_result:=eogp.commit_guest_registry_merge(v_org,v_actor,v_comb_source,v_comb_dest,2,1,'duplicate_profile',(v_review->>'reviewId')::uuid,'move_to_destination','move_to_destination','move_to_destination','move_to_destination');v_merge:=(v_result->>'mergeId')::uuid;
 IF NOT EXISTS(SELECT 1 FROM eogp.person_relationships WHERE id=v_comb_rel AND v_comb_dest IN(from_person_id,to_person_id)) OR NOT EXISTS(SELECT 1 FROM eogp.registry_person_label_assignments WHERE person_id=v_comb_dest AND label_id=v_comb_label) OR (SELECT person_id FROM eogp.person_contact_points WHERE id=v_comb_contact) IS DISTINCT FROM v_comb_dest OR (SELECT person_id FROM eogp.person_identifiers WHERE id=v_comb_reference) IS DISTINCT FROM v_comb_dest THEN RAISE EXCEPTION 'combined transfer omitted a linked record';END IF;
 v_correction:=eogp.preview_guest_registry_merge_restoration(v_org,v_actor,v_merge);
 PERFORM eogp.restore_guest_registry_merge_reviewed(v_org,v_actor,v_merge,(v_correction->>'reviewId')::uuid,ARRAY[v_comb_contact],ARRAY[v_comb_reference],false,'return_selected_current_records');
 IF NOT EXISTS(SELECT 1 FROM eogp.person_relationships WHERE id=v_comb_rel AND v_comb_source IN(from_person_id,to_person_id)) OR NOT EXISTS(SELECT 1 FROM eogp.registry_person_label_assignments WHERE person_id=v_comb_source AND label_id=v_comb_label) OR NOT EXISTS(SELECT 1 FROM eogp.person_contact_points WHERE id=v_comb_contact AND person_id=v_comb_source AND contact_consent='withdrawn') OR (SELECT person_id FROM eogp.person_identifiers WHERE id=v_comb_reference) IS DISTINCT FROM v_comb_source THEN RAISE EXCEPTION 'combined correction omitted or changed a linked record';END IF;
 PERFORM set_config('app.organization_id','10000000-0000-0000-0000-00000000000b',true);
 BEGIN PERFORM eogp.preview_guest_registry_merge_restoration(v_org,v_actor,v_merge);RAISE EXCEPTION 'cross-tenant restoration review accepted';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 IF has_table_privilege('eventor_runtime','eogp.person_merge_relationship_transfers','SELECT,INSERT,UPDATE,DELETE') OR has_function_privilege('eventor_runtime','eogp.commit_guest_registry_merge_without_relationship_transfer(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text,text,text)','EXECUTE') THEN RAISE EXCEPTION 'private relationship boundary exposed';END IF;
END;
$test$;
ROLLBACK;
\echo 'Reviewed Registry relationship merge and restoration smoke passed.'
