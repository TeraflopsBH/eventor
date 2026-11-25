-- Preserve existing classification assignments through explicitly reviewed identity merges.
CREATE TABLE eogp.person_merge_label_transfers (
 organization_id uuid NOT NULL,merge_id uuid NOT NULL,label_id uuid NOT NULL,
 transferred_state_sha256 text NOT NULL CHECK(transferred_state_sha256 ~ '^[a-f0-9]{64}$'),
 PRIMARY KEY(organization_id,merge_id,label_id),
 FOREIGN KEY(organization_id,merge_id) REFERENCES eogp.person_merge_records(organization_id,id),
 FOREIGN KEY(organization_id,label_id) REFERENCES eogp.registry_labels(organization_id,id)
);
ALTER TABLE eogp.person_merge_label_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.person_merge_label_transfers FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON eogp.person_merge_label_transfers
 USING(organization_id=eogp.current_organization_id()) WITH CHECK(organization_id=eogp.current_organization_id());
REVOKE ALL ON eogp.person_merge_label_transfers FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
CREATE TRIGGER person_merge_label_transfers_append_only BEFORE UPDATE OR DELETE ON eogp.person_merge_label_transfers
 FOR EACH ROW EXECUTE FUNCTION eogp.reject_append_only_mutation();

CREATE FUNCTION eogp.guest_registry_label_assignment_hash_v1(p_assignment eogp.registry_person_label_assignments)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,eogp AS $function$
 SELECT encode(sha256(convert_to(jsonb_build_array((p_assignment).organization_id,(p_assignment).person_id,(p_assignment).label_id,
  (p_assignment).added_by_membership_id,extract(epoch from (p_assignment).added_at))::text,'UTF8')),'hex');
$function$;
REVOKE ALL ON FUNCTION eogp.guest_registry_label_assignment_hash_v1(eogp.registry_person_label_assignments) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

CREATE OR REPLACE FUNCTION eogp.guest_registry_merge_impact(p_org uuid,p_actor uuid,p_source eogp.persons,p_destination eogp.persons)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog,eogp AS $function$
DECLARE v_result jsonb;v_count integer;v_state text;
BEGIN
 v_result:=eogp.guest_registry_merge_impact_without_labels(p_org,p_actor,p_source,p_destination);
 SELECT count(*) INTO v_count FROM eogp.registry_person_label_assignments WHERE organization_id=p_org AND person_id=p_source.id;
 SELECT encode(sha256(convert_to(coalesce(string_agg(jsonb_build_array(eogp.guest_registry_label_assignment_hash_v1(assignment),extract(epoch from label.retired_at))::text,',' ORDER BY assignment.person_id,assignment.label_id),''),'UTF8')),'hex') INTO v_state
 FROM eogp.registry_person_label_assignments assignment JOIN eogp.registry_labels label ON label.organization_id=assignment.organization_id AND label.id=assignment.label_id
 WHERE assignment.organization_id=p_org AND assignment.person_id IN(p_source.id,p_destination.id);
 IF v_count>0 AND NOT (v_result ? 'blocker') AND (SELECT count(*) FROM eogp.registry_person_label_assignments WHERE organization_id=p_org AND person_id IN(p_source.id,p_destination.id))>100 THEN
  v_result:=v_result||jsonb_build_object('blocker','label_limit');
 END IF;
 IF NOT (v_result ? 'blocker') AND EXISTS(
  SELECT 1 FROM eogp.registry_person_label_assignments source JOIN eogp.registry_person_label_assignments destination
   ON destination.organization_id=source.organization_id AND destination.label_id=source.label_id
  WHERE source.organization_id=p_org AND source.person_id=p_source.id AND destination.person_id=p_destination.id
 ) THEN v_result:=v_result||jsonb_build_object('blocker','label_conflict');END IF;
 RETURN v_result||jsonb_build_object('labelCount',v_count,'labelState',v_state);
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.preview_guest_registry_merge(p_org uuid, p_actor uuid, p_source uuid, p_destination uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_source eogp.persons%ROWTYPE;
  v_destination eogp.persons%ROWTYPE;
  v_review uuid;
  v_impact jsonb;
BEGIN
  PERFORM eogp.assert_guest_registry_merge_permission(p_org, p_actor);
  IF p_source = p_destination THEN RAISE EXCEPTION 'choose two profiles' USING ERRCODE = '22023'; END IF;
  SELECT * INTO v_source FROM eogp.persons WHERE organization_id = p_org AND id = p_source;
  SELECT * INTO v_destination FROM eogp.persons WHERE organization_id = p_org AND id = p_destination;
  IF v_source.id IS NULL OR v_destination.id IS NULL THEN
    RAISE EXCEPTION 'person not found' USING ERRCODE = 'P0002';
  END IF;
  v_impact := eogp.guest_registry_merge_impact(p_org, p_actor, v_source, v_destination);
  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.registry.merge_reviewed', 'person', p_source,
    jsonb_build_object('destinationPersonId', p_destination, 'sourceRevision', v_source.revision,
      'destinationRevision', v_destination.revision, 'eligible', NOT (v_impact ? 'blocker'),
      'historicalReference', v_impact->>'historicalReference','contactReference',v_impact->>'contactReference','referenceState',v_impact->>'referenceState','labelState',v_impact->>'labelState')
  ) RETURNING id INTO v_review;
  RETURN jsonb_build_object(
    'labelCount',coalesce((v_impact->>'labelCount')::integer,0),
    'sourceLabels',eogp.registry_person_label_projection(p_org,p_source),
    'destinationLabels',eogp.registry_person_label_projection(p_org,p_destination),
    'reviewId', v_review,
    'source', eogp.guest_registry_person_projection(v_source),
    'destination', eogp.guest_registry_person_projection(v_destination),
    'blocker', v_impact->>'blocker',
    'contactCount',coalesce((v_impact->>'contactCount')::integer,0),
    'referenceCount',coalesce((v_impact->>'referenceCount')::integer,0),
    'historicalEvents', coalesce(v_impact->'historicalEvents', '[]'::jsonb),
    'historicalCount', coalesce((v_impact->>'historicalCount')::integer, 0)
  );
END;
$function$;

ALTER FUNCTION eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text,text) RENAME TO commit_guest_registry_merge_without_label_transfer;
REVOKE ALL ON FUNCTION eogp.commit_guest_registry_merge_without_label_transfer(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text,text) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
CREATE FUNCTION eogp.commit_guest_registry_merge(
 p_org uuid,p_actor uuid,p_source uuid,p_destination uuid,p_source_revision integer,p_destination_revision integer,
 p_reason text,p_review uuid,p_contact_resolution text,p_reference_resolution text,p_label_resolution text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_source eogp.persons%ROWTYPE;v_destination eogp.persons%ROWTYPE;v_impact jsonb;v_labels uuid[];v_result jsonb;
BEGIN
 PERFORM eogp.assert_guest_registry_merge_permission(p_org,p_actor);
 IF p_source=p_destination OR p_reason IS DISTINCT FROM 'duplicate_profile'
  OR (p_label_resolution IS NOT NULL AND p_label_resolution<>'move_to_destination')
  OR (p_contact_resolution IS NOT NULL AND p_contact_resolution<>'move_to_destination')
  OR (p_reference_resolution IS NOT NULL AND p_reference_resolution<>'move_to_destination') THEN
  RAISE EXCEPTION 'invalid Registry merge resolution' USING ERRCODE='22023';END IF;
 IF p_contact_resolution IS NOT NULL THEN PERFORM eogp.assert_guest_contact_permission(p_org,p_actor,true);END IF;
 IF p_reference_resolution IS NOT NULL THEN PERFORM eogp.assert_guest_reference_permission(p_org,p_actor,true);END IF;
 PERFORM 1 FROM eogp.persons WHERE organization_id=p_org AND id IN(p_source,p_destination) ORDER BY id FOR UPDATE;
 SELECT * INTO v_source FROM eogp.persons WHERE organization_id=p_org AND id=p_source;
 SELECT * INTO v_destination FROM eogp.persons WHERE organization_id=p_org AND id=p_destination;
 IF v_source.id IS NULL OR v_destination.id IS NULL THEN RAISE EXCEPTION 'person not found' USING ERRCODE='P0002';END IF;
 IF v_source.revision IS DISTINCT FROM p_source_revision OR v_destination.revision IS DISTINCT FROM p_destination_revision THEN RAISE EXCEPTION 'person revision conflict' USING ERRCODE='40001';END IF;
 PERFORM 1 FROM eogp.registry_labels WHERE organization_id=p_org AND id IN(
  SELECT label_id FROM eogp.registry_person_label_assignments WHERE organization_id=p_org AND person_id IN(p_source,p_destination)) ORDER BY id FOR SHARE;
 v_impact:=eogp.guest_registry_merge_impact(p_org,p_actor,v_source,v_destination);
 IF v_impact ? 'blocker' THEN RAISE EXCEPTION 'Registry merge has unresolved linked records or classifications' USING ERRCODE='55000';END IF;
 IF (v_impact->>'labelCount')::integer>0 THEN
  IF p_label_resolution IS DISTINCT FROM 'move_to_destination' THEN RAISE EXCEPTION 'explicit label transfer resolution required' USING ERRCODE='22023';END IF;
  IF NOT EXISTS(SELECT 1 FROM eogp.audit_events WHERE organization_id=p_org AND id=p_review
    AND actor_membership_id=p_actor AND action='guest.registry.merge_reviewed' AND aggregate_id=p_source
    AND safe_metadata @> jsonb_build_object('destinationPersonId',p_destination,'sourceRevision',p_source_revision,'destinationRevision',p_destination_revision,'eligible',true)
    AND safe_metadata->>'labelState' IS NOT DISTINCT FROM v_impact->>'labelState') THEN
   RAISE EXCEPTION 'reviewed label assignments changed' USING ERRCODE='40001';END IF;
 END IF;
 SELECT array_agg(label_id ORDER BY label_id) INTO v_labels FROM eogp.registry_person_label_assignments WHERE organization_id=p_org AND person_id=p_source;
 UPDATE eogp.registry_person_label_assignments SET person_id=p_destination WHERE organization_id=p_org AND person_id=p_source;
 v_result:=eogp.commit_guest_registry_merge_without_label_transfer(p_org,p_actor,p_source,p_destination,p_source_revision,p_destination_revision,p_reason,p_review,p_contact_resolution,p_reference_resolution);
 INSERT INTO eogp.person_merge_label_transfers(organization_id,merge_id,label_id,transferred_state_sha256)
  SELECT p_org,(v_result->>'mergeId')::uuid,label_id,eogp.guest_registry_label_assignment_hash_v1(assignment)
  FROM eogp.registry_person_label_assignments assignment WHERE organization_id=p_org AND person_id=p_destination AND label_id=ANY(v_labels);
 IF cardinality(v_labels)>0 THEN
  UPDATE eogp.person_merge_records SET resolution=resolution||'{"labels":"moved_unchanged"}'::jsonb WHERE organization_id=p_org AND id=(v_result->>'mergeId')::uuid;
  UPDATE eogp.persons SET revision=revision+1,updated_at=clock_timestamp() WHERE organization_id=p_org AND id=p_destination;
 END IF;
 RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.commit_guest_registry_merge(p_org uuid,p_actor uuid,p_source uuid,p_destination uuid,p_source_revision integer,p_destination_revision integer,p_reason text,p_review uuid,p_contact_resolution text,p_reference_resolution text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
 SELECT eogp.commit_guest_registry_merge(p_org,p_actor,p_source,p_destination,p_source_revision,p_destination_revision,p_reason,p_review,p_contact_resolution,p_reference_resolution,NULL::text);
$function$;

CREATE OR REPLACE FUNCTION eogp.commit_guest_registry_merge(p_org uuid,p_actor uuid,p_source uuid,p_destination uuid,p_source_revision integer,p_destination_revision integer,p_reason text,p_review uuid,p_contact_resolution text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
 SELECT eogp.commit_guest_registry_merge(p_org,p_actor,p_source,p_destination,p_source_revision,p_destination_revision,p_reason,p_review,p_contact_resolution,NULL::text,NULL::text);
$function$;

CREATE OR REPLACE FUNCTION eogp.commit_guest_registry_merge(p_org uuid,p_actor uuid,p_source uuid,p_destination uuid,p_source_revision integer,p_destination_revision integer,p_reason text,p_review uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
 SELECT eogp.commit_guest_registry_merge(p_org,p_actor,p_source,p_destination,p_source_revision,p_destination_revision,p_reason,p_review,NULL::text,NULL::text,NULL::text);
$function$;

REVOKE ALL ON FUNCTION eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text,text,text) TO eventor_runtime;

-- Shared guard for strict restoration and the separate current-contact/reference correction path.
CREATE FUNCTION eogp.prepare_registry_merge_label_restore(p_org uuid,p_actor uuid,p_merge uuid)
RETURNS eogp.person_merge_records LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_merge eogp.person_merge_records%ROWTYPE;
BEGIN
 PERFORM eogp.assert_guest_registry_merge_restore_permission(p_org,p_actor,p_merge);
 SELECT * INTO v_merge FROM eogp.person_merge_records WHERE organization_id=p_org AND id=p_merge FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'guest merge not found' USING ERRCODE='P0002';END IF;
 IF v_merge.restored_at IS NOT NULL THEN RETURN v_merge;END IF;
 PERFORM 1 FROM eogp.persons WHERE organization_id=p_org AND id IN(v_merge.source_person_id,v_merge.destination_person_id) ORDER BY id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM eogp.person_merge_label_transfers transfer
  LEFT JOIN eogp.registry_person_label_assignments assignment ON assignment.organization_id=transfer.organization_id
   AND assignment.person_id=v_merge.destination_person_id AND assignment.label_id=transfer.label_id
  WHERE transfer.organization_id=p_org AND transfer.merge_id=p_merge AND
   (assignment.label_id IS NULL OR eogp.guest_registry_label_assignment_hash_v1(assignment) IS DISTINCT FROM transfer.transferred_state_sha256))
 OR EXISTS(SELECT 1 FROM eogp.person_merge_label_transfers transfer JOIN eogp.registry_person_label_assignments assignment
   ON assignment.organization_id=transfer.organization_id AND assignment.label_id=transfer.label_id AND assignment.person_id=v_merge.source_person_id
   WHERE transfer.organization_id=p_org AND transfer.merge_id=p_merge) THEN
  RAISE EXCEPTION 'transferred label assignments changed or were removed; investigate before restoration' USING ERRCODE='P1911';
 END IF;
 RETURN v_merge;
END;
$function$;
CREATE FUNCTION eogp.return_registry_merge_labels(p_org uuid,p_merge eogp.person_merge_records)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,eogp AS $function$
DECLARE v_count integer;
BEGIN
 IF p_merge.restored_at IS NOT NULL THEN RETURN;END IF;
 UPDATE eogp.registry_person_label_assignments assignment SET person_id=p_merge.source_person_id
 FROM eogp.person_merge_label_transfers transfer WHERE transfer.organization_id=p_org AND transfer.merge_id=p_merge.id
  AND assignment.organization_id=p_org AND assignment.person_id=p_merge.destination_person_id AND assignment.label_id=transfer.label_id;
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count>0 THEN UPDATE eogp.persons SET revision=revision+1,updated_at=clock_timestamp() WHERE organization_id=p_org AND id=p_merge.destination_person_id;END IF;
END;
$function$;
REVOKE ALL ON FUNCTION eogp.prepare_registry_merge_label_restore(uuid,uuid,uuid),eogp.return_registry_merge_labels(uuid,eogp.person_merge_records) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

ALTER FUNCTION eogp.restore_guest_registry_merge(uuid,uuid,uuid) RENAME TO restore_guest_registry_merge_without_label_transfer;
CREATE FUNCTION eogp.restore_guest_registry_merge(p_org uuid,p_actor uuid,p_merge uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_merge eogp.person_merge_records%ROWTYPE;v_result jsonb;
BEGIN
 v_merge:=eogp.prepare_registry_merge_label_restore(p_org,p_actor,p_merge);
 v_result:=eogp.restore_guest_registry_merge_without_label_transfer(p_org,p_actor,p_merge);
 PERFORM eogp.return_registry_merge_labels(p_org,v_merge);
 RETURN v_result;
END;
$function$;
ALTER FUNCTION eogp.restore_guest_registry_merge_reviewed(uuid,uuid,uuid,uuid,uuid[],uuid[],boolean,text) RENAME TO restore_guest_registry_merge_reviewed_without_labels;
CREATE FUNCTION eogp.restore_guest_registry_merge_reviewed(p_org uuid,p_actor uuid,p_merge uuid,p_review uuid,p_contacts uuid[],p_references uuid[],p_keep_removed boolean,p_resolution text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_merge eogp.person_merge_records%ROWTYPE;v_result jsonb;
BEGIN
 v_merge:=eogp.prepare_registry_merge_label_restore(p_org,p_actor,p_merge);
 v_result:=eogp.restore_guest_registry_merge_reviewed_without_labels(p_org,p_actor,p_merge,p_review,p_contacts,p_references,p_keep_removed,p_resolution);
 PERFORM eogp.return_registry_merge_labels(p_org,v_merge);
 RETURN v_result;
END;
$function$;
ALTER FUNCTION eogp.preview_guest_registry_merge_restoration(uuid,uuid,uuid) RENAME TO preview_guest_registry_merge_restoration_without_labels;
CREATE FUNCTION eogp.preview_guest_registry_merge_restoration(p_org uuid,p_actor uuid,p_merge uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_result jsonb;v_labels jsonb;
BEGIN
 PERFORM eogp.prepare_registry_merge_label_restore(p_org,p_actor,p_merge);
 v_result:=eogp.preview_guest_registry_merge_restoration_without_labels(p_org,p_actor,p_merge);
 SELECT coalesce(jsonb_agg(jsonb_build_object('labelId',label.id,'label',label.label,'retired',label.retired_at IS NOT NULL) ORDER BY lower(label.label),label.id),'[]'::jsonb) INTO v_labels
 FROM eogp.person_merge_label_transfers transfer JOIN eogp.registry_labels label ON label.organization_id=transfer.organization_id AND label.id=transfer.label_id
 WHERE transfer.organization_id=p_org AND transfer.merge_id=p_merge;
 RETURN v_result||jsonb_build_object('labels',v_labels);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.restore_guest_registry_merge_without_label_transfer(uuid,uuid,uuid),
 eogp.restore_guest_registry_merge_reviewed_without_labels(uuid,uuid,uuid,uuid,uuid[],uuid[],boolean,text),
 eogp.preview_guest_registry_merge_restoration_without_labels(uuid,uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.restore_guest_registry_merge(uuid,uuid,uuid),
 eogp.restore_guest_registry_merge_reviewed(uuid,uuid,uuid,uuid,uuid[],uuid[],boolean,text),
 eogp.preview_guest_registry_merge_restoration(uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.restore_guest_registry_merge(uuid,uuid,uuid),
 eogp.restore_guest_registry_merge_reviewed(uuid,uuid,uuid,uuid,uuid[],uuid[],boolean,text),
 eogp.preview_guest_registry_merge_restoration(uuid,uuid,uuid) TO eventor_runtime;

-- Recreating the renamed compatibility overload creates a new function with default ACLs.
REVOKE ALL ON FUNCTION eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text,text),
 eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text),
 eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid) FROM PUBLIC,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text,text),
 eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text),
 eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid) TO eventor_runtime;
