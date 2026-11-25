-- Explicit transfer of non-conflicting active Registry relationships.
CREATE TABLE eogp.person_merge_relationship_transfers (
 organization_id uuid NOT NULL,merge_id uuid NOT NULL,relationship_id uuid NOT NULL,
 original_from_person_id uuid NOT NULL,original_to_person_id uuid NOT NULL,
 transferred_state_sha256 text NOT NULL CHECK(transferred_state_sha256 ~ '^[a-f0-9]{64}$'),
 PRIMARY KEY(organization_id,merge_id,relationship_id),
 FOREIGN KEY(organization_id,merge_id) REFERENCES eogp.person_merge_records(organization_id,id),
 FOREIGN KEY(organization_id,original_from_person_id) REFERENCES eogp.persons(organization_id,id),
 FOREIGN KEY(organization_id,original_to_person_id) REFERENCES eogp.persons(organization_id,id)
);
ALTER TABLE eogp.person_merge_relationship_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.person_merge_relationship_transfers FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON eogp.person_merge_relationship_transfers USING(organization_id=eogp.current_organization_id()) WITH CHECK(organization_id=eogp.current_organization_id());
REVOKE ALL ON eogp.person_merge_relationship_transfers FROM PUBLIC,eventor_runtime,eventor_auth,eventor_worker;
CREATE TRIGGER person_merge_relationship_transfers_append_only BEFORE UPDATE OR DELETE ON eogp.person_merge_relationship_transfers FOR EACH ROW EXECUTE FUNCTION eogp.reject_append_only_mutation();
CREATE FUNCTION eogp.registry_relationship_state_hash_v1(p_link eogp.person_relationships)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,eogp AS $function$
 SELECT encode(sha256(convert_to(jsonb_build_array((p_link).organization_id,(p_link).id,(p_link).from_person_id,(p_link).to_person_id,(p_link).relationship_kind,(p_link).directionality,extract(epoch from (p_link).created_at),(p_link).created_by_membership_id,extract(epoch from (p_link).ended_at),(p_link).ended_by_membership_id)::text,'UTF8')),'hex');
$function$;
REVOKE ALL ON FUNCTION eogp.registry_relationship_state_hash_v1(eogp.person_relationships) FROM PUBLIC,eventor_runtime,eventor_auth,eventor_worker;

CREATE OR REPLACE FUNCTION eogp.guest_registry_merge_impact_without_labels(
  p_org uuid, p_actor uuid, p_source eogp.persons, p_destination eogp.persons
) RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_link record;
  v_events jsonb := '[]'::jsonb;
  v_count integer := 0;
  v_reference text;
  v_contact_count integer := 0;
  v_contact_reference text;
  v_reference_count integer:=0;
  v_reference_state text;
BEGIN
  IF p_source.status <> 'active' OR p_destination.status <> 'active' THEN
    RETURN jsonb_build_object('blocker', 'inactive_profile');
  END IF;
  IF EXISTS (SELECT 1 FROM eogp.persons WHERE organization_id = p_org AND merged_into_person_id = p_source.id) THEN
    RETURN jsonb_build_object('blocker', 'source_has_linked_records');
  END IF;


  SELECT count(*) INTO v_reference_count FROM eogp.person_identifiers WHERE organization_id=p_org AND person_id=p_source.id;
  IF v_reference_count>0 THEN
    BEGIN
      PERFORM eogp.assert_guest_reference_permission(p_org,p_actor,true);
    EXCEPTION WHEN insufficient_privilege THEN
      RETURN jsonb_build_object('blocker','reference_access_required');
    END;
    IF EXISTS (SELECT 1 FROM eogp.person_identifiers WHERE organization_id=p_org AND person_id=p_source.id
      AND identifier_kind !~ '^external-ref-v1:[A-Z0-9][A-Z0-9_-]{0,39}$') THEN
      RETURN jsonb_build_object('blocker','source_has_linked_records');
    END IF;
    SELECT encode(sha256(convert_to(string_agg(eogp.guest_registry_reference_state_hash_v1(identifier),',' ORDER BY identifier.id),'UTF8')),'hex')
      INTO v_reference_state FROM eogp.person_identifiers identifier
      WHERE identifier.organization_id=p_org AND identifier.person_id IN(p_source.id,p_destination.id)
        AND identifier.identifier_kind ~ '^external-ref-v1:[A-Z0-9][A-Z0-9_-]{0,39}$';
  END IF;
  SELECT count(*) INTO v_contact_count FROM eogp.person_contact_points
  WHERE organization_id=p_org AND person_id=p_source.id;
  IF v_contact_count>0 THEN
    BEGIN
      PERFORM eogp.assert_guest_contact_permission(p_org,p_actor,true);
    EXCEPTION WHEN insufficient_privilege THEN
      RETURN jsonb_build_object('blocker','contact_access_required');
    END;
    IF EXISTS (SELECT 1 FROM eogp.person_contact_points WHERE organization_id=p_org AND person_id=p_source.id
      AND contact_kind NOT IN ('email','phone')) THEN
      RETURN jsonb_build_object('blocker','source_has_linked_records');
    END IF;
    IF EXISTS (SELECT 1 FROM eogp.person_contact_points WHERE organization_id=p_org AND person_id=p_source.id
        GROUP BY contact_kind,normalized_value_hash HAVING count(*)>1)
      OR EXISTS (SELECT 1 FROM eogp.person_contact_points WHERE organization_id=p_org AND person_id=p_source.id
        GROUP BY contact_kind HAVING count(*) FILTER(WHERE is_primary)>1) THEN
      RETURN jsonb_build_object('blocker','contact_conflict');
    END IF;
    IF EXISTS (
      SELECT 1 FROM eogp.person_contact_points source
      JOIN eogp.person_contact_points destination ON destination.organization_id=source.organization_id
        AND destination.person_id=p_destination.id AND destination.contact_kind=source.contact_kind
      WHERE source.organization_id=p_org AND source.person_id=p_source.id
        AND (destination.normalized_value_hash=source.normalized_value_hash OR (source.is_primary AND destination.is_primary))
    ) THEN
      RETURN jsonb_build_object('blocker','contact_conflict');
    END IF;
    -- Contact commands lock their parent profile. Commit locks both parents before recomputing this fingerprint.
    SELECT encode(sha256(convert_to(string_agg(id::text||':'||revision::text||':'||person_id::text,',' ORDER BY id),'UTF8')),'hex')
      INTO v_contact_reference FROM eogp.person_contact_points
      WHERE organization_id=p_org AND person_id IN (p_source.id,p_destination.id);
  END IF;

  FOR v_link IN
    SELECT participation.id, event.id AS event_id, event.event_code, event.title, event.status,
      participation.status AS participation_status
    FROM eogp.event_participations participation
    JOIN eogp.events event ON event.organization_id = participation.organization_id AND event.id = participation.event_id
    WHERE participation.organization_id = p_org AND participation.person_id = p_source.id
    ORDER BY participation.id
  LOOP
    BEGIN
      PERFORM eogp.assert_event_guest_list_access(p_org, v_link.event_id, p_actor);
    EXCEPTION WHEN insufficient_privilege THEN
      RETURN jsonb_build_object('blocker', 'event_history_access_required');
    END;
    IF v_link.status NOT IN ('completed', 'cancelled', 'archived') THEN
      RETURN jsonb_build_object('blocker', 'source_has_linked_records');
    END IF;
    IF EXISTS (
      SELECT 1 FROM eogp.event_participations other
      JOIN eogp.persons person ON person.organization_id = other.organization_id AND person.id = other.person_id
      WHERE other.organization_id = p_org AND other.event_id = v_link.event_id
        AND (other.person_id = p_destination.id OR person.merged_into_person_id = p_destination.id)
    ) THEN
      RETURN jsonb_build_object('blocker', 'event_history_overlap');
    END IF;
    v_count := v_count + 1;
    -- Bind the review to the exact preserved participation references without storing them in audit metadata.
    v_reference := encode(sha256(convert_to(coalesce(v_reference, '') || v_link.id::text, 'UTF8')), 'hex');
    IF v_count <= 50 THEN
      v_events := v_events || jsonb_build_array(jsonb_build_object(
        'eventId', v_link.event_id, 'eventCode', v_link.event_code, 'eventTitle', v_link.title,
        'eventStatus', v_link.status, 'status', v_link.participation_status
      ));
    END IF;
  END LOOP;
  RETURN jsonb_build_object('historicalEvents', v_events, 'historicalCount', v_count, 'historicalReference', v_reference,
    'contactCount',v_contact_count,'contactReference',v_contact_reference,
    'referenceCount',v_reference_count,'referenceState',v_reference_state);
END;
$function$;



-- Retain label guards; remove only the old unconditional active-relationship blocker above.
ALTER FUNCTION eogp.guest_registry_merge_impact(uuid,uuid,eogp.persons,eogp.persons) RENAME TO guest_registry_merge_impact_without_relationships;
CREATE FUNCTION eogp.guest_registry_merge_impact(p_org uuid,p_actor uuid,p_source eogp.persons,p_destination eogp.persons)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog,eogp AS $function$
DECLARE v_result jsonb;v_count integer;v_state text;
BEGIN
 v_result:=eogp.guest_registry_merge_impact_without_relationships(p_org,p_actor,p_source,p_destination);
 SELECT count(*) INTO v_count FROM eogp.person_relationships WHERE organization_id=p_org AND ended_at IS NULL AND p_source.id IN(from_person_id,to_person_id);
 IF v_count>0 THEN
  BEGIN PERFORM eogp.assert_guest_registry_relationship_permission(p_org,p_actor,true);
  EXCEPTION WHEN insufficient_privilege THEN RETURN v_result||jsonb_build_object('blocker','relationship_access_required','relationshipCount',0);END;
  IF NOT(v_result ? 'blocker') AND EXISTS(SELECT 1 FROM eogp.person_relationships WHERE organization_id=p_org AND ended_at IS NULL AND p_source.id IN(from_person_id,to_person_id) AND p_destination.id IN(from_person_id,to_person_id)) THEN
   v_result:=v_result||jsonb_build_object('blocker','relationship_self_link');
  END IF;
  IF NOT(v_result ? 'blocker') AND EXISTS(
   SELECT 1 FROM eogp.person_relationships source JOIN eogp.person_relationships destination
    ON destination.organization_id=source.organization_id AND destination.ended_at IS NULL
     AND destination.relationship_kind=source.relationship_kind AND destination.directionality=source.directionality
   WHERE source.organization_id=p_org AND source.ended_at IS NULL AND p_source.id IN(source.from_person_id,source.to_person_id)
    AND destination.from_person_id=CASE WHEN source.directionality='mutual' THEN least(p_destination.id,CASE WHEN source.from_person_id=p_source.id THEN source.to_person_id ELSE source.from_person_id END) ELSE CASE WHEN source.from_person_id=p_source.id THEN p_destination.id ELSE source.from_person_id END END
    AND destination.to_person_id=CASE WHEN source.directionality='mutual' THEN greatest(p_destination.id,CASE WHEN source.from_person_id=p_source.id THEN source.to_person_id ELSE source.from_person_id END) ELSE CASE WHEN source.to_person_id=p_source.id THEN p_destination.id ELSE source.to_person_id END END
  ) THEN v_result:=v_result||jsonb_build_object('blocker','relationship_conflict');END IF;
 END IF;
 SELECT encode(sha256(convert_to(coalesce(string_agg(eogp.registry_relationship_state_hash_v1(link),',' ORDER BY id),''),'UTF8')),'hex') INTO v_state FROM eogp.person_relationships link
 WHERE organization_id=p_org AND ended_at IS NULL AND (p_source.id IN(from_person_id,to_person_id) OR p_destination.id IN(from_person_id,to_person_id));
 RETURN v_result||jsonb_build_object('relationshipCount',v_count,'relationshipState',v_state);
END;
$function$;
REVOKE ALL ON FUNCTION eogp.guest_registry_merge_impact(uuid,uuid,eogp.persons,eogp.persons),eogp.guest_registry_merge_impact_without_relationships(uuid,uuid,eogp.persons,eogp.persons) FROM PUBLIC,eventor_runtime,eventor_auth,eventor_worker;

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
      'historicalReference', v_impact->>'historicalReference','contactReference',v_impact->>'contactReference','referenceState',v_impact->>'referenceState','labelState',v_impact->>'labelState','relationshipState',v_impact->>'relationshipState')
  ) RETURNING id INTO v_review;
  RETURN jsonb_build_object(
    'relationshipCount',coalesce((v_impact->>'relationshipCount')::integer,0),
    'sourceRelationships',CASE WHEN coalesce((v_impact->>'relationshipCount')::integer,0)>0 THEN (SELECT coalesce(jsonb_agg(item),'[]'::jsonb) FROM jsonb_array_elements(eogp.read_guest_registry_relationships(p_org,p_actor,p_source)->'relationships') item WHERE item->>'endedAt' IS NULL) ELSE '[]'::jsonb END,
    'destinationRelationships',CASE WHEN coalesce((v_impact->>'relationshipCount')::integer,0)>0 THEN (SELECT coalesce(jsonb_agg(item),'[]'::jsonb) FROM jsonb_array_elements(eogp.read_guest_registry_relationships(p_org,p_actor,p_destination)->'relationships') item WHERE item->>'endedAt' IS NULL) ELSE '[]'::jsonb END,
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


ALTER FUNCTION eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text,text,text) RENAME TO commit_guest_registry_merge_without_relationship_transfer;
REVOKE ALL ON FUNCTION eogp.commit_guest_registry_merge_without_relationship_transfer(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text,text,text) FROM PUBLIC,eventor_runtime,eventor_auth,eventor_worker;
CREATE FUNCTION eogp.commit_guest_registry_merge(p_org uuid,p_actor uuid,p_source uuid,p_destination uuid,p_source_revision integer,p_destination_revision integer,p_reason text,p_review uuid,p_contact_resolution text,p_reference_resolution text,p_label_resolution text,p_relationship_resolution text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_source eogp.persons%ROWTYPE;v_destination eogp.persons%ROWTYPE;v_impact jsonb;v_result jsonb;v_original jsonb;v_ids uuid[];
BEGIN
 PERFORM eogp.assert_guest_registry_merge_permission(p_org,p_actor);
 IF p_relationship_resolution IS NOT NULL AND p_relationship_resolution<>'move_to_destination' THEN RAISE EXCEPTION 'invalid relationship resolution' USING ERRCODE='22023';END IF;
 IF p_relationship_resolution IS NOT NULL THEN PERFORM eogp.assert_guest_registry_relationship_permission(p_org,p_actor,true);END IF;
 IF p_contact_resolution IS NOT NULL THEN PERFORM eogp.assert_guest_contact_permission(p_org,p_actor,true);END IF;
 IF p_reference_resolution IS NOT NULL THEN PERFORM eogp.assert_guest_reference_permission(p_org,p_actor,true);END IF;
 PERFORM 1 FROM eogp.persons WHERE organization_id=p_org AND id IN(p_source,p_destination) ORDER BY id FOR UPDATE;
 SELECT * INTO v_source FROM eogp.persons WHERE organization_id=p_org AND id=p_source;
 SELECT * INTO v_destination FROM eogp.persons WHERE organization_id=p_org AND id=p_destination;
 IF v_source.id IS NULL OR v_destination.id IS NULL THEN RAISE EXCEPTION 'person not found' USING ERRCODE='P0002';END IF;
 IF v_source.revision IS DISTINCT FROM p_source_revision OR v_destination.revision IS DISTINCT FROM p_destination_revision THEN RAISE EXCEPTION 'person revision conflict' USING ERRCODE='40001';END IF;
 -- Ending an existing link locks its row; creation locks a parent. Hold both boundaries before rechecking.
 PERFORM 1 FROM eogp.person_relationships WHERE organization_id=p_org AND ended_at IS NULL AND (p_source IN(from_person_id,to_person_id) OR p_destination IN(from_person_id,to_person_id)) ORDER BY id FOR UPDATE;
 v_impact:=eogp.guest_registry_merge_impact(p_org,p_actor,v_source,v_destination);
 IF v_impact ? 'blocker' THEN RAISE EXCEPTION 'unresolved Registry merge records' USING ERRCODE='55000';END IF;
 IF (v_impact->>'relationshipCount')::integer>0 AND p_relationship_resolution IS DISTINCT FROM 'move_to_destination' THEN RAISE EXCEPTION 'explicit relationship transfer required' USING ERRCODE='22023';END IF;
 IF (v_impact->>'relationshipCount')::integer>0 OR p_relationship_resolution IS NOT NULL OR EXISTS(SELECT 1 FROM eogp.audit_events WHERE organization_id=p_org AND id=p_review AND safe_metadata ? 'relationshipState') THEN
  IF NOT EXISTS(SELECT 1 FROM eogp.audit_events WHERE organization_id=p_org AND id=p_review AND actor_membership_id=p_actor AND action='guest.registry.merge_reviewed' AND aggregate_id=p_source
   AND safe_metadata @> jsonb_build_object('destinationPersonId',p_destination,'sourceRevision',p_source_revision,'destinationRevision',p_destination_revision,'eligible',true)
   AND safe_metadata->>'relationshipState' IS NOT DISTINCT FROM v_impact->>'relationshipState') THEN RAISE EXCEPTION 'relationship review stale' USING ERRCODE='40001';END IF;
 END IF;
 SELECT array_agg(id ORDER BY id),jsonb_object_agg(id::text,jsonb_build_array(from_person_id,to_person_id)) INTO v_ids,v_original FROM eogp.person_relationships WHERE organization_id=p_org AND ended_at IS NULL AND p_source IN(from_person_id,to_person_id);
 UPDATE eogp.person_relationships SET
  from_person_id=CASE WHEN directionality='mutual' THEN least(p_destination,CASE WHEN from_person_id=p_source THEN to_person_id ELSE from_person_id END) ELSE CASE WHEN from_person_id=p_source THEN p_destination ELSE from_person_id END END,
  to_person_id=CASE WHEN directionality='mutual' THEN greatest(p_destination,CASE WHEN from_person_id=p_source THEN to_person_id ELSE from_person_id END) ELSE CASE WHEN to_person_id=p_source THEN p_destination ELSE to_person_id END END
 WHERE organization_id=p_org AND id=ANY(v_ids);
 v_result:=eogp.commit_guest_registry_merge_without_relationship_transfer(p_org,p_actor,p_source,p_destination,p_source_revision,p_destination_revision,p_reason,p_review,p_contact_resolution,p_reference_resolution,p_label_resolution);
 INSERT INTO eogp.person_merge_relationship_transfers SELECT p_org,(v_result->>'mergeId')::uuid,id,(v_original->(id::text)->>0)::uuid,(v_original->(id::text)->>1)::uuid,eogp.registry_relationship_state_hash_v1(link) FROM eogp.person_relationships link WHERE organization_id=p_org AND id=ANY(v_ids);
 IF cardinality(v_ids)>0 THEN
  UPDATE eogp.person_merge_records SET resolution=resolution||'{"relationships":"moved_unchanged"}'::jsonb WHERE organization_id=p_org AND id=(v_result->>'mergeId')::uuid;
  UPDATE eogp.persons SET revision=revision+1,updated_at=clock_timestamp() WHERE organization_id=p_org AND id=p_destination;
 END IF;
 RETURN v_result;
END;
$function$;
CREATE FUNCTION eogp.commit_guest_registry_merge(p_org uuid,p_actor uuid,p_source uuid,p_destination uuid,p_source_revision integer,p_destination_revision integer,p_reason text,p_review uuid,p_contact_resolution text,p_reference_resolution text,p_label_resolution text)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
 SELECT eogp.commit_guest_registry_merge(p_org,p_actor,p_source,p_destination,p_source_revision,p_destination_revision,p_reason,p_review,p_contact_resolution,p_reference_resolution,p_label_resolution,NULL::text);
$function$;
REVOKE ALL ON FUNCTION eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text,text,text),eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text,text,text,text) FROM PUBLIC,eventor_auth,eventor_worker;
GRANT EXECUTE ON FUNCTION eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text,text,text),eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text,text,text,text) TO eventor_runtime;

ALTER FUNCTION eogp.assert_guest_registry_merge_restore_permission(uuid,uuid,uuid) RENAME TO assert_registry_merge_restore_without_relationships;
CREATE FUNCTION eogp.assert_guest_registry_merge_restore_permission(p_org uuid,p_actor uuid,p_merge uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
BEGIN
 PERFORM eogp.assert_registry_merge_restore_without_relationships(p_org,p_actor,p_merge);
 IF EXISTS(SELECT 1 FROM eogp.person_merge_relationship_transfers WHERE organization_id=p_org AND merge_id=p_merge) THEN PERFORM eogp.assert_guest_registry_relationship_permission(p_org,p_actor,true);END IF;
END;
$function$;
REVOKE ALL ON FUNCTION eogp.assert_registry_merge_restore_without_relationships(uuid,uuid,uuid),eogp.assert_guest_registry_merge_restore_permission(uuid,uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_auth,eventor_worker;
GRANT EXECUTE ON FUNCTION eogp.assert_guest_registry_merge_restore_permission(uuid,uuid,uuid) TO eventor_runtime;
CREATE FUNCTION eogp.prepare_registry_merge_relationship_restore(p_org uuid,p_actor uuid,p_merge uuid)
RETURNS eogp.person_merge_records LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_merge eogp.person_merge_records%ROWTYPE;
BEGIN
 PERFORM eogp.assert_guest_registry_merge_restore_permission(p_org,p_actor,p_merge);
 SELECT * INTO v_merge FROM eogp.person_merge_records WHERE organization_id=p_org AND id=p_merge FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'merge not found' USING ERRCODE='P0002';END IF;
 IF v_merge.restored_at IS NOT NULL THEN RETURN v_merge;END IF;
 PERFORM 1 FROM eogp.persons WHERE organization_id=p_org AND id IN(v_merge.source_person_id,v_merge.destination_person_id) ORDER BY id FOR UPDATE;
 PERFORM 1 FROM eogp.person_relationships WHERE organization_id=p_org AND id IN(SELECT relationship_id FROM eogp.person_merge_relationship_transfers WHERE organization_id=p_org AND merge_id=p_merge) ORDER BY id FOR UPDATE;
 IF EXISTS(SELECT 1 FROM eogp.person_merge_relationship_transfers transfer LEFT JOIN eogp.person_relationships link ON link.organization_id=transfer.organization_id AND link.id=transfer.relationship_id WHERE transfer.organization_id=p_org AND transfer.merge_id=p_merge AND (link.id IS NULL OR eogp.registry_relationship_state_hash_v1(link) IS DISTINCT FROM transfer.transferred_state_sha256)) THEN
  RAISE EXCEPTION 'transferred relationships changed' USING ERRCODE='P1921';END IF;
 RETURN v_merge;
END;
$function$;
CREATE FUNCTION eogp.return_registry_merge_relationships(p_org uuid,p_merge eogp.person_merge_records)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,eogp AS $function$
DECLARE v_count integer;
BEGIN
 IF p_merge.restored_at IS NOT NULL THEN RETURN;END IF;
 UPDATE eogp.person_relationships link SET from_person_id=transfer.original_from_person_id,to_person_id=transfer.original_to_person_id
 FROM eogp.person_merge_relationship_transfers transfer WHERE transfer.organization_id=p_org AND transfer.merge_id=p_merge.id AND link.organization_id=p_org AND link.id=transfer.relationship_id;
 GET DIAGNOSTICS v_count=ROW_COUNT;
 IF v_count>0 THEN UPDATE eogp.persons SET revision=revision+1,updated_at=clock_timestamp() WHERE organization_id=p_org AND id=p_merge.destination_person_id;END IF;
END;
$function$;
REVOKE ALL ON FUNCTION eogp.prepare_registry_merge_relationship_restore(uuid,uuid,uuid),eogp.return_registry_merge_relationships(uuid,eogp.person_merge_records) FROM PUBLIC,eventor_runtime,eventor_auth,eventor_worker;

ALTER FUNCTION eogp.restore_guest_registry_merge(uuid,uuid,uuid) RENAME TO restore_guest_registry_merge_without_relationships;
CREATE FUNCTION eogp.restore_guest_registry_merge(p_org uuid,p_actor uuid,p_merge uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_merge eogp.person_merge_records%ROWTYPE;v_result jsonb;
BEGIN
 v_merge:=eogp.prepare_registry_merge_relationship_restore(p_org,p_actor,p_merge);
 v_result:=eogp.restore_guest_registry_merge_without_relationships(p_org,p_actor,p_merge);
 PERFORM eogp.return_registry_merge_relationships(p_org,v_merge);
 RETURN v_result;
END;
$function$;
REVOKE ALL ON FUNCTION eogp.restore_guest_registry_merge_without_relationships(uuid,uuid,uuid),eogp.restore_guest_registry_merge(uuid,uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_auth,eventor_worker;
GRANT EXECUTE ON FUNCTION eogp.restore_guest_registry_merge(uuid,uuid,uuid) TO eventor_runtime;

ALTER FUNCTION eogp.restore_guest_registry_merge_reviewed(uuid,uuid,uuid,uuid,uuid[],uuid[],boolean,text) RENAME TO restore_guest_registry_merge_reviewed_without_relationships;
CREATE FUNCTION eogp.restore_guest_registry_merge_reviewed(p_org uuid,p_actor uuid,p_merge uuid,p_review uuid,p_contacts uuid[],p_references uuid[],p_keep_removed boolean,p_resolution text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_merge eogp.person_merge_records%ROWTYPE;v_result jsonb;
BEGIN
 v_merge:=eogp.prepare_registry_merge_relationship_restore(p_org,p_actor,p_merge);
 v_result:=eogp.restore_guest_registry_merge_reviewed_without_relationships(p_org,p_actor,p_merge,p_review,p_contacts,p_references,p_keep_removed,p_resolution);
 PERFORM eogp.return_registry_merge_relationships(p_org,v_merge);
 RETURN v_result;
END;
$function$;
REVOKE ALL ON FUNCTION eogp.restore_guest_registry_merge_reviewed_without_relationships(uuid,uuid,uuid,uuid,uuid[],uuid[],boolean,text),eogp.restore_guest_registry_merge_reviewed(uuid,uuid,uuid,uuid,uuid[],uuid[],boolean,text) FROM PUBLIC,eventor_runtime,eventor_auth,eventor_worker;
GRANT EXECUTE ON FUNCTION eogp.restore_guest_registry_merge_reviewed(uuid,uuid,uuid,uuid,uuid[],uuid[],boolean,text) TO eventor_runtime;

ALTER FUNCTION eogp.preview_guest_registry_merge_restoration(uuid,uuid,uuid) RENAME TO preview_guest_registry_merge_restoration_without_relationships;
CREATE FUNCTION eogp.preview_guest_registry_merge_restoration(p_org uuid,p_actor uuid,p_merge uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_merge eogp.person_merge_records%ROWTYPE;v_result jsonb;v_relationships jsonb;
BEGIN
 v_merge:=eogp.prepare_registry_merge_relationship_restore(p_org,p_actor,p_merge);
 v_result:=eogp.preview_guest_registry_merge_restoration_without_relationships(p_org,p_actor,p_merge);
 SELECT coalesce(jsonb_agg(item),'[]'::jsonb) INTO v_relationships FROM jsonb_array_elements(
 CASE WHEN EXISTS(SELECT 1 FROM eogp.person_merge_relationship_transfers WHERE organization_id=p_org AND merge_id=p_merge)
 THEN eogp.read_guest_registry_relationships(p_org,p_actor,v_merge.destination_person_id)->'relationships' ELSE '[]'::jsonb END) item
 WHERE EXISTS(SELECT 1 FROM eogp.person_merge_relationship_transfers WHERE organization_id=p_org AND merge_id=p_merge AND relationship_id=(item->>'relationshipId')::uuid);
 RETURN v_result||jsonb_build_object('relationships',v_relationships);
END;
$function$;
REVOKE ALL ON FUNCTION eogp.preview_guest_registry_merge_restoration_without_relationships(uuid,uuid,uuid),eogp.preview_guest_registry_merge_restoration(uuid,uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_auth,eventor_worker;
GRANT EXECUTE ON FUNCTION eogp.preview_guest_registry_merge_restoration(uuid,uuid,uuid) TO eventor_runtime;
