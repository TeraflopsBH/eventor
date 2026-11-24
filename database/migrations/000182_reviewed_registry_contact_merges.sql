-- Reviewed, reversible transfer of non-conflicting Registry contacts.
ALTER TABLE eogp.person_merge_records ADD CONSTRAINT person_merge_records_org_id_key UNIQUE(organization_id,id);
CREATE TABLE eogp.person_merge_contact_transfers (
  organization_id uuid NOT NULL,
  merge_id uuid NOT NULL,
  contact_id uuid NOT NULL,
  transferred_revision integer NOT NULL CHECK(transferred_revision>1),
  PRIMARY KEY(organization_id,merge_id,contact_id),
  FOREIGN KEY(organization_id,merge_id) REFERENCES eogp.person_merge_records(organization_id,id),
  FOREIGN KEY(organization_id,contact_id) REFERENCES eogp.person_contact_points(organization_id,id)
);
ALTER TABLE eogp.person_merge_contact_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.person_merge_contact_transfers FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON eogp.person_merge_contact_transfers
  USING(organization_id=eogp.current_organization_id()) WITH CHECK(organization_id=eogp.current_organization_id());
REVOKE ALL ON eogp.person_merge_contact_transfers FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
CREATE TRIGGER person_merge_contact_transfers_append_only_guard BEFORE UPDATE OR DELETE ON eogp.person_merge_contact_transfers
  FOR EACH ROW EXECUTE FUNCTION eogp.reject_append_only_mutation();

CREATE OR REPLACE FUNCTION eogp.guest_registry_merge_impact(
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
BEGIN
  IF p_source.status <> 'active' OR p_destination.status <> 'active' THEN
    RETURN jsonb_build_object('blocker', 'inactive_profile');
  END IF;
  IF EXISTS (SELECT 1 FROM eogp.person_identifiers WHERE organization_id = p_org AND person_id = p_source.id)
    OR EXISTS (SELECT 1 FROM eogp.persons WHERE organization_id = p_org AND merged_into_person_id = p_source.id)
    OR EXISTS (SELECT 1 FROM eogp.person_relationships WHERE organization_id = p_org AND ended_at IS NULL
      AND (from_person_id = p_source.id OR to_person_id = p_source.id)) THEN
    RETURN jsonb_build_object('blocker', 'source_has_linked_records');
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
    'contactCount',v_contact_count,'contactReference',v_contact_reference);
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
      'historicalReference', v_impact->>'historicalReference','contactReference',v_impact->>'contactReference')
  ) RETURNING id INTO v_review;
  RETURN jsonb_build_object(
    'reviewId', v_review,
    'source', eogp.guest_registry_person_projection(v_source),
    'destination', eogp.guest_registry_person_projection(v_destination),
    'blocker', v_impact->>'blocker',
    'contactCount',coalesce((v_impact->>'contactCount')::integer,0),
    'historicalEvents', coalesce(v_impact->'historicalEvents', '[]'::jsonb),
    'historicalCount', coalesce((v_impact->>'historicalCount')::integer, 0)
  );
END;
$function$;

-- Keep the established name/history transition private and reuse its checks after contact transfer.
ALTER FUNCTION eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid)
  RENAME TO commit_guest_registry_merge_without_contact_transfer;
REVOKE ALL ON FUNCTION eogp.commit_guest_registry_merge_without_contact_transfer(uuid,uuid,uuid,uuid,integer,integer,text,uuid)
  FROM PUBLIC,eventor_runtime;

CREATE FUNCTION eogp.commit_guest_registry_merge(
  p_org uuid,p_actor uuid,p_source uuid,p_destination uuid,p_source_revision integer,p_destination_revision integer,
  p_reason text,p_review uuid,p_contact_resolution text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_source eogp.persons%ROWTYPE;
  v_destination eogp.persons%ROWTYPE;
  v_impact jsonb;
  v_contacts uuid[];
  v_result jsonb;
BEGIN
  PERFORM eogp.assert_guest_registry_merge_permission(p_org,p_actor);
  IF p_source=p_destination OR p_reason IS DISTINCT FROM 'duplicate_profile' THEN
    RAISE EXCEPTION 'invalid guest merge request' USING ERRCODE='22023';
  END IF;
  IF p_contact_resolution IS NOT NULL AND p_contact_resolution<>'move_to_destination' THEN
    RAISE EXCEPTION 'invalid contact resolution' USING ERRCODE='22023';
  END IF;
  IF p_contact_resolution IS NOT NULL THEN PERFORM eogp.assert_guest_contact_permission(p_org,p_actor,true); END IF;
  PERFORM 1 FROM eogp.persons WHERE organization_id=p_org AND id IN(p_source,p_destination) ORDER BY id FOR UPDATE;
  SELECT * INTO v_source FROM eogp.persons WHERE organization_id=p_org AND id=p_source;
  SELECT * INTO v_destination FROM eogp.persons WHERE organization_id=p_org AND id=p_destination;
  IF v_source.id IS NULL OR v_destination.id IS NULL THEN RAISE EXCEPTION 'person not found' USING ERRCODE='P0002'; END IF;
  IF v_source.revision IS DISTINCT FROM p_source_revision OR v_destination.revision IS DISTINCT FROM p_destination_revision THEN
    RAISE EXCEPTION 'person revision conflict' USING ERRCODE='40001';
  END IF;
  v_impact:=eogp.guest_registry_merge_impact(p_org,p_actor,v_source,v_destination);
  IF v_impact ? 'blocker' OR NOT EXISTS (
    SELECT 1 FROM eogp.audit_events WHERE organization_id=p_org AND id=p_review
      AND actor_membership_id=p_actor AND aggregate_id=p_source AND action='guest.registry.merge_reviewed'
      AND safe_metadata @> jsonb_build_object('destinationPersonId',p_destination,'sourceRevision',p_source_revision,
        'destinationRevision',p_destination_revision,'eligible',true)
      AND safe_metadata->>'contactReference' IS NOT DISTINCT FROM v_impact->>'contactReference'
      AND safe_metadata->>'historicalReference' IS NOT DISTINCT FROM v_impact->>'historicalReference'
  ) THEN
    RAISE EXCEPTION 'reviewed profiles or contacts changed' USING ERRCODE='55000';
  END IF;
  IF (v_impact->>'contactCount')::integer>0 AND p_contact_resolution IS DISTINCT FROM 'move_to_destination' THEN
    RAISE EXCEPTION 'explicit contact transfer resolution required' USING ERRCODE='22023';
  END IF;
  SELECT array_agg(id ORDER BY id) INTO v_contacts FROM eogp.person_contact_points
    WHERE organization_id=p_org AND person_id=p_source;
  UPDATE eogp.person_contact_points SET person_id=p_destination,revision=revision+1,updated_at=clock_timestamp()
    WHERE organization_id=p_org AND id=ANY(v_contacts);
  v_result:=eogp.commit_guest_registry_merge_without_contact_transfer(p_org,p_actor,p_source,p_destination,
    p_source_revision,p_destination_revision,p_reason,p_review);
  INSERT INTO eogp.person_merge_contact_transfers(organization_id,merge_id,contact_id,transferred_revision)
    SELECT p_org,(v_result->>'mergeId')::uuid,id,revision FROM eogp.person_contact_points
    WHERE organization_id=p_org AND id=ANY(v_contacts);
  IF cardinality(v_contacts)>0 THEN
    UPDATE eogp.person_merge_records SET resolution=resolution||'{"contacts":"moved_unchanged"}'::jsonb
      WHERE organization_id=p_org AND id=(v_result->>'mergeId')::uuid;
  END IF;
  RETURN v_result;
END;
$function$;

-- Preserve existing callers. Omitting contact resolution cannot move linked contacts.
CREATE FUNCTION eogp.commit_guest_registry_merge(
  p_org uuid,p_actor uuid,p_source uuid,p_destination uuid,p_source_revision integer,p_destination_revision integer,p_reason text,p_review uuid
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,eogp
AS $function$
  SELECT eogp.commit_guest_registry_merge(p_org,p_actor,p_source,p_destination,p_source_revision,p_destination_revision,p_reason,p_review,NULL);
$function$;

CREATE FUNCTION eogp.assert_guest_registry_merge_restore_permission(p_org uuid,p_actor uuid,p_merge uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp
AS $function$
BEGIN
  PERFORM eogp.assert_guest_registry_merge_permission(p_org,p_actor);
  IF EXISTS(SELECT 1 FROM eogp.person_merge_contact_transfers WHERE organization_id=p_org AND merge_id=p_merge) THEN
    PERFORM eogp.assert_guest_contact_permission(p_org,p_actor,true);
  END IF;
END;
$function$;

ALTER FUNCTION eogp.restore_guest_registry_merge(uuid,uuid,uuid) RENAME TO restore_guest_registry_merge_without_contact_transfer;
REVOKE ALL ON FUNCTION eogp.restore_guest_registry_merge_without_contact_transfer(uuid,uuid,uuid) FROM PUBLIC,eventor_runtime;
CREATE FUNCTION eogp.restore_guest_registry_merge(p_org uuid,p_actor uuid,p_merge uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp
AS $function$
DECLARE v_merge eogp.person_merge_records%ROWTYPE; v_result jsonb;
BEGIN
  PERFORM eogp.assert_guest_registry_merge_restore_permission(p_org,p_actor,p_merge);
  SELECT * INTO v_merge FROM eogp.person_merge_records WHERE organization_id=p_org AND id=p_merge FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'guest merge not found' USING ERRCODE='P0002'; END IF;
  IF v_merge.restored_at IS NOT NULL THEN RETURN eogp.restore_guest_registry_merge_without_contact_transfer(p_org,p_actor,p_merge); END IF;
  PERFORM 1 FROM eogp.persons WHERE organization_id=p_org AND id IN(v_merge.source_person_id,v_merge.destination_person_id)
    ORDER BY id FOR UPDATE;
  IF EXISTS (
    SELECT 1 FROM eogp.person_merge_contact_transfers transfer
    LEFT JOIN eogp.person_contact_points contact ON contact.organization_id=transfer.organization_id AND contact.id=transfer.contact_id
    WHERE transfer.organization_id=p_org AND transfer.merge_id=p_merge
      AND (contact.id IS NULL OR contact.person_id<>v_merge.destination_person_id OR contact.revision<>transfer.transferred_revision)
  ) THEN
    RAISE EXCEPTION 'transferred contacts changed; review correction before restoring' USING ERRCODE='P1821';
  END IF;
  v_result:=eogp.restore_guest_registry_merge_without_contact_transfer(p_org,p_actor,p_merge);
  UPDATE eogp.person_contact_points contact SET person_id=v_merge.source_person_id,revision=contact.revision+1,updated_at=clock_timestamp()
    FROM eogp.person_merge_contact_transfers transfer
    WHERE transfer.organization_id=p_org AND transfer.merge_id=p_merge AND contact.organization_id=p_org AND contact.id=transfer.contact_id;
  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text),
  eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid),
  eogp.assert_guest_registry_merge_restore_permission(uuid,uuid,uuid),eogp.restore_guest_registry_merge(uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text),
  eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid),
  eogp.assert_guest_registry_merge_restore_permission(uuid,uuid,uuid),eogp.restore_guest_registry_merge(uuid,uuid,uuid) TO eventor_runtime;
