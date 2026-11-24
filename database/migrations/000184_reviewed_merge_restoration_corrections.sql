-- Preserve the original merge journals; append explicit resolution of current record ownership.
CREATE TABLE eogp.person_merge_restoration_records (
  organization_id uuid NOT NULL,
  merge_id uuid NOT NULL,
  actor_membership_id uuid NOT NULL,
  review_audit_id uuid NOT NULL,
  reviewed_state_sha256 text NOT NULL CHECK(reviewed_state_sha256 ~ '^[a-f0-9]{64}$'),
  resolution jsonb NOT NULL CHECK(jsonb_typeof(resolution)='object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(organization_id,merge_id),
  FOREIGN KEY(organization_id,merge_id) REFERENCES eogp.person_merge_records(organization_id,id),
  FOREIGN KEY(organization_id,actor_membership_id) REFERENCES eogp.organization_memberships(organization_id,id)
);
ALTER TABLE eogp.person_merge_restoration_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.person_merge_restoration_records FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON eogp.person_merge_restoration_records
  USING(organization_id=eogp.current_organization_id()) WITH CHECK(organization_id=eogp.current_organization_id());
REVOKE ALL ON eogp.person_merge_restoration_records FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
CREATE TRIGGER person_merge_restoration_records_append_only_guard BEFORE UPDATE OR DELETE ON eogp.person_merge_restoration_records
  FOR EACH ROW EXECUTE FUNCTION eogp.reject_append_only_mutation();

CREATE FUNCTION eogp.guest_registry_restoration_state(p_org uuid,p_merge eogp.person_merge_records)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_source eogp.persons%ROWTYPE; v_destination eogp.persons%ROWTYPE;
  v_contacts jsonb; v_references jsonb; v_contact_state jsonb; v_reference_state jsonb;
BEGIN
  SELECT * INTO v_source FROM eogp.persons WHERE organization_id=p_org AND id=p_merge.source_person_id;
  SELECT * INTO v_destination FROM eogp.persons WHERE organization_id=p_org AND id=p_merge.destination_person_id;
  IF v_source.id IS NULL OR v_destination.id IS NULL OR v_source.status<>'merged'
    OR v_source.merged_into_person_id IS DISTINCT FROM v_destination.id OR v_source.revision<>p_merge.source_revision+1
    OR v_destination.status='merged' THEN
    RAISE EXCEPTION 'merge identity state changed' USING ERRCODE='40001';
  END IF;
  IF EXISTS(SELECT 1 FROM eogp.person_contact_points WHERE organization_id=p_org AND person_id=v_source.id)
    OR EXISTS(SELECT 1 FROM eogp.person_identifiers WHERE organization_id=p_org AND person_id=v_source.id) THEN
    RAISE EXCEPTION 'merged source has unexpected records' USING ERRCODE='55000';
  END IF;
  IF EXISTS(
    SELECT 1 FROM eogp.person_merge_contact_transfers transfer LEFT JOIN eogp.person_contact_points contact
      ON contact.organization_id=transfer.organization_id AND contact.id=transfer.contact_id
    WHERE transfer.organization_id=p_org AND transfer.merge_id=p_merge.id
      AND (contact.id IS NULL OR contact.person_id<>v_destination.id OR contact.contact_kind NOT IN ('email','phone'))
  ) OR EXISTS(
    SELECT 1 FROM eogp.person_merge_reference_transfers transfer LEFT JOIN eogp.person_identifiers identifier
      ON identifier.organization_id=transfer.organization_id AND identifier.id=transfer.reference_id
    WHERE transfer.organization_id=p_org AND transfer.merge_id=p_merge.id AND identifier.id IS NOT NULL
      AND (identifier.person_id<>v_destination.id OR identifier.identifier_kind !~ '^external-ref-v1:[A-Z0-9][A-Z0-9_-]{0,39}$')
  ) THEN RAISE EXCEPTION 'transferred record ownership or kind changed' USING ERRCODE='55000'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('contactId',contact.id,'revision',contact.revision,
      'changed',contact.revision<>transfer.transferred_revision) ORDER BY contact.id),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_array(contact.id,contact.person_id,contact.revision) ORDER BY contact.id),'[]'::jsonb)
    INTO v_contacts,v_contact_state
    FROM eogp.person_merge_contact_transfers transfer JOIN eogp.person_contact_points contact
      ON contact.organization_id=transfer.organization_id AND contact.id=transfer.contact_id
    WHERE transfer.organization_id=p_org AND transfer.merge_id=p_merge.id;
  SELECT coalesce(jsonb_agg(jsonb_build_object('referenceId',transfer.reference_id,'missing',identifier.id IS NULL,
      'changed',identifier.id IS NULL OR eogp.guest_registry_reference_state_hash_v1(identifier) IS DISTINCT FROM transfer.transferred_state_sha256)
      ORDER BY transfer.reference_id),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_array(transfer.reference_id,CASE WHEN identifier.id IS NULL THEN 'missing'
      ELSE eogp.guest_registry_reference_state_hash_v1(identifier) END) ORDER BY transfer.reference_id),'[]'::jsonb)
    INTO v_references,v_reference_state
    FROM eogp.person_merge_reference_transfers transfer LEFT JOIN eogp.person_identifiers identifier
      ON identifier.organization_id=transfer.organization_id AND identifier.id=transfer.reference_id
    WHERE transfer.organization_id=p_org AND transfer.merge_id=p_merge.id;
  RETURN jsonb_build_object('source',eogp.guest_registry_person_projection(v_source),'destination',eogp.guest_registry_person_projection(v_destination),
    'contacts',v_contacts,'references',v_references,'missingReferenceCount',(SELECT count(*) FROM jsonb_array_elements(v_references) item WHERE (item->>'missing')::boolean),
    'stateHash',encode(sha256(convert_to(jsonb_build_array(p_merge.id,v_source.id,v_destination.id,v_source.revision,v_destination.revision,v_contact_state,v_reference_state)::text,'UTF8')),'hex'));
END;
$function$;
REVOKE ALL ON FUNCTION eogp.guest_registry_restoration_state(uuid,eogp.person_merge_records) FROM PUBLIC,eventor_runtime;

CREATE FUNCTION eogp.preview_guest_registry_merge_restoration(p_org uuid,p_actor uuid,p_merge uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp
AS $function$
DECLARE v_merge eogp.person_merge_records%ROWTYPE; v_state jsonb; v_review uuid;
BEGIN
  PERFORM eogp.assert_guest_registry_merge_restore_permission(p_org,p_actor,p_merge);
  SELECT * INTO v_merge FROM eogp.person_merge_records WHERE organization_id=p_org AND id=p_merge FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'guest merge not found' USING ERRCODE='P0002'; END IF;
  IF v_merge.restored_at IS NOT NULL THEN RAISE EXCEPTION 'merge is already restored' USING ERRCODE='55000'; END IF;
  PERFORM 1 FROM eogp.persons WHERE organization_id=p_org AND id IN(v_merge.source_person_id,v_merge.destination_person_id) ORDER BY id FOR SHARE;
  v_state:=eogp.guest_registry_restoration_state(p_org,v_merge);
  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,action,aggregate_type,aggregate_id,safe_metadata)
    VALUES(p_org,p_org,p_actor,'membership','guest.registry.merge_restoration_reviewed','person',v_merge.source_person_id,
      jsonb_build_object('mergeId',p_merge,'destinationPersonId',v_merge.destination_person_id,'stateHash',v_state->>'stateHash',
        'sourceRevision',v_state#>'{source,revision}','destinationRevision',v_state#>'{destination,revision}',
        'contactCount',jsonb_array_length(v_state->'contacts'),'referenceCount',jsonb_array_length(v_state->'references'),
        'missingReferenceCount',v_state->'missingReferenceCount')) RETURNING id INTO v_review;
  RETURN (v_state-'stateHash')||jsonb_build_object('reviewId',v_review);
END;
$function$;

CREATE FUNCTION eogp.restore_guest_registry_merge_reviewed(
  p_org uuid,p_actor uuid,p_merge uuid,p_review uuid,p_contacts uuid[],p_references uuid[],p_keep_removed boolean,p_resolution text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_merge eogp.person_merge_records%ROWTYPE; v_state jsonb; v_result jsonb; v_resolution jsonb; v_moved integer;
BEGIN
  PERFORM eogp.assert_guest_registry_merge_restore_permission(p_org,p_actor,p_merge);
  IF p_resolution IS DISTINCT FROM 'return_selected_current_records' OR p_contacts IS NULL OR p_references IS NULL OR p_keep_removed IS NULL
    OR array_position(p_contacts,NULL) IS NOT NULL OR array_position(p_references,NULL) IS NOT NULL
    OR cardinality(p_contacts)<>(SELECT count(DISTINCT id) FROM unnest(p_contacts) id)
    OR cardinality(p_references)<>(SELECT count(DISTINCT id) FROM unnest(p_references) id) THEN
    RAISE EXCEPTION 'invalid restoration choices' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_merge FROM eogp.person_merge_records WHERE organization_id=p_org AND id=p_merge FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'guest merge not found' USING ERRCODE='P0002'; END IF;
  IF v_merge.restored_at IS NOT NULL THEN RAISE EXCEPTION 'merge is already restored' USING ERRCODE='55000'; END IF;
  PERFORM 1 FROM eogp.persons WHERE organization_id=p_org AND id IN(v_merge.source_person_id,v_merge.destination_person_id) ORDER BY id FOR UPDATE;
  PERFORM 1 FROM eogp.person_contact_points contact WHERE contact.organization_id=p_org AND contact.id IN(
    SELECT contact_id FROM eogp.person_merge_contact_transfers WHERE organization_id=p_org AND merge_id=p_merge) ORDER BY contact.id FOR UPDATE;
  PERFORM 1 FROM eogp.person_identifiers identifier WHERE identifier.organization_id=p_org AND identifier.id IN(
    SELECT reference_id FROM eogp.person_merge_reference_transfers WHERE organization_id=p_org AND merge_id=p_merge) ORDER BY identifier.id FOR UPDATE;
  v_state:=eogp.guest_registry_restoration_state(p_org,v_merge);
  IF NOT EXISTS(SELECT 1 FROM eogp.audit_events WHERE organization_id=p_org AND id=p_review AND actor_membership_id=p_actor
    AND aggregate_id=v_merge.source_person_id AND action='guest.registry.merge_restoration_reviewed'
    AND safe_metadata @> jsonb_build_object('mergeId',p_merge,'stateHash',v_state->>'stateHash')) THEN
    RAISE EXCEPTION 'restoration review changed' USING ERRCODE='P1841';
  END IF;
  IF EXISTS(SELECT 1 FROM unnest(p_contacts) selected(id) WHERE NOT EXISTS(
      SELECT 1 FROM eogp.person_merge_contact_transfers WHERE organization_id=p_org AND merge_id=p_merge AND contact_id=selected.id))
    OR EXISTS(SELECT 1 FROM unnest(p_references) selected(id) WHERE NOT EXISTS(
      SELECT 1 FROM eogp.person_merge_reference_transfers transfer JOIN eogp.person_identifiers identifier
        ON identifier.organization_id=transfer.organization_id AND identifier.id=transfer.reference_id
      WHERE transfer.organization_id=p_org AND transfer.merge_id=p_merge AND transfer.reference_id=selected.id))
    OR ((v_state->>'missingReferenceCount')::integer>0 AND NOT p_keep_removed) THEN
    RAISE EXCEPTION 'select current records and acknowledge removed references' USING ERRCODE='22023';
  END IF;
  v_resolution:=jsonb_build_object('mode','reviewed_current_state','returnedContactIds',to_jsonb(p_contacts),'returnedReferenceIds',to_jsonb(p_references),
    'keptContactIds',coalesce((SELECT jsonb_agg(contact_id ORDER BY contact_id) FROM eogp.person_merge_contact_transfers
      WHERE organization_id=p_org AND merge_id=p_merge AND NOT(contact_id=ANY(p_contacts))),'[]'::jsonb),
    'keptReferenceIds',coalesce((SELECT jsonb_agg(transfer.reference_id ORDER BY transfer.reference_id) FROM eogp.person_merge_reference_transfers transfer
      JOIN eogp.person_identifiers identifier ON identifier.organization_id=transfer.organization_id AND identifier.id=transfer.reference_id
      WHERE transfer.organization_id=p_org AND transfer.merge_id=p_merge AND NOT(transfer.reference_id=ANY(p_references))),'[]'::jsonb),
    'removedReferenceIds',coalesce((SELECT jsonb_agg(transfer.reference_id ORDER BY transfer.reference_id) FROM eogp.person_merge_reference_transfers transfer
      LEFT JOIN eogp.person_identifiers identifier ON identifier.organization_id=transfer.organization_id AND identifier.id=transfer.reference_id
      WHERE transfer.organization_id=p_org AND transfer.merge_id=p_merge AND identifier.id IS NULL),'[]'::jsonb));
  -- Reuse only the private name/lifecycle transition after the full current-state review; strict old restore commands remain unchanged.
  v_result:=eogp.restore_guest_registry_merge_without_contact_transfer(p_org,p_actor,p_merge);
  UPDATE eogp.person_contact_points SET person_id=v_merge.source_person_id,revision=revision+1,updated_at=clock_timestamp()
    WHERE organization_id=p_org AND person_id=v_merge.destination_person_id AND id=ANY(p_contacts);
  GET DIAGNOSTICS v_moved=ROW_COUNT;
  IF v_moved<>cardinality(p_contacts) THEN RAISE EXCEPTION 'contact restoration state changed' USING ERRCODE='P1841'; END IF;
  UPDATE eogp.person_identifiers SET person_id=v_merge.source_person_id
    WHERE organization_id=p_org AND person_id=v_merge.destination_person_id AND id=ANY(p_references);
  GET DIAGNOSTICS v_moved=ROW_COUNT;
  IF v_moved<>cardinality(p_references) THEN RAISE EXCEPTION 'reference restoration state changed' USING ERRCODE='P1841'; END IF;
  IF v_moved>0 THEN UPDATE eogp.persons SET revision=revision+1,updated_at=clock_timestamp() WHERE organization_id=p_org AND id=v_merge.destination_person_id; END IF;
  INSERT INTO eogp.person_merge_restoration_records(organization_id,merge_id,actor_membership_id,review_audit_id,reviewed_state_sha256,resolution)
    VALUES(p_org,p_merge,p_actor,p_review,v_state->>'stateHash',v_resolution);
  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,action,aggregate_type,aggregate_id,safe_metadata)
    VALUES(p_org,p_org,p_actor,'membership','guest.registry.merge_restoration_applied','person',v_merge.source_person_id,
      jsonb_build_object('mergeId',p_merge,'reviewId',p_review,'returnedContactCount',cardinality(p_contacts),
        'returnedReferenceCount',cardinality(p_references),'removedReferenceCount',v_state->'missingReferenceCount'));
  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.preview_guest_registry_merge_restoration(uuid,uuid,uuid),
  eogp.restore_guest_registry_merge_reviewed(uuid,uuid,uuid,uuid,uuid[],uuid[],boolean,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.preview_guest_registry_merge_restoration(uuid,uuid,uuid),
  eogp.restore_guest_registry_merge_reviewed(uuid,uuid,uuid,uuid,uuid[],uuid[],boolean,text) TO eventor_runtime;

CREATE OR REPLACE FUNCTION eogp.list_guest_registry_merges(p_org uuid, p_actor uuid, p_offset integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_rows jsonb;
BEGIN
  PERFORM eogp.assert_guest_registry_merge_permission(p_org, p_actor);
  IF coalesce(p_offset, -1) NOT BETWEEN 0 AND 100000 THEN
    RAISE EXCEPTION 'invalid merge history offset' USING ERRCODE = '22023';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'mergeId', merge.id,
    'sourceName', concat_ws(' ', source.first_name, source.last_name),
    'destinationName', concat_ws(' ', destination.first_name, destination.last_name),
    'mergedAt', merge.merged_at, 'restoredAt', merge.restored_at,
    'restorationMode',CASE WHEN merge.restored_at IS NULL THEN NULL WHEN EXISTS(
      SELECT 1 FROM eogp.person_merge_restoration_records correction WHERE correction.organization_id=p_org AND correction.merge_id=merge.id
    ) THEN 'reviewed_current_state' ELSE 'unchanged' END
  ) ORDER BY merge.merged_at DESC, merge.id), '[]'::jsonb)
  INTO v_rows
  FROM (
    SELECT * FROM eogp.person_merge_records WHERE organization_id = p_org
    ORDER BY merged_at DESC, id LIMIT 51 OFFSET p_offset
  ) merge
  JOIN eogp.persons source ON source.organization_id = merge.organization_id AND source.id = merge.source_person_id
  JOIN eogp.persons destination ON destination.organization_id = merge.organization_id AND destination.id = merge.destination_person_id;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id
  ) VALUES (p_org, p_org, p_actor, 'membership', 'guest.registry.merge_history_viewed', 'organization', p_org);
  RETURN jsonb_build_object(
    'merges', CASE WHEN jsonb_array_length(v_rows) > 50 THEN v_rows - 50 ELSE v_rows END,
    'nextOffset', CASE WHEN jsonb_array_length(v_rows) > 50 AND p_offset < 100000 THEN p_offset + 50 END
  );
END;
$function$;

