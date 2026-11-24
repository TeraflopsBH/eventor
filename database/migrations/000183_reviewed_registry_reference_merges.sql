-- Source-reference keys are person-bound. Keep that original binding when only ownership changes.
ALTER TABLE eogp.person_identifiers ADD COLUMN encryption_person_id uuid;
-- The runner holds the migration transaction/table lock. Only the owner bypasses RLS for this backfill.
ALTER TABLE eogp.person_identifiers NO FORCE ROW LEVEL SECURITY;
UPDATE eogp.person_identifiers SET encryption_person_id=person_id;
ALTER TABLE eogp.person_identifiers FORCE ROW LEVEL SECURITY;
ALTER TABLE eogp.person_identifiers ALTER COLUMN encryption_person_id SET NOT NULL;
ALTER TABLE eogp.person_identifiers ADD CONSTRAINT person_identifier_encryption_identity_same_org
  FOREIGN KEY(organization_id,encryption_person_id) REFERENCES eogp.persons(organization_id,id);
CREATE FUNCTION eogp.set_person_identifier_encryption_binding()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,eogp
AS $function$
BEGIN
  NEW.encryption_person_id:=NEW.person_id;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION eogp.set_person_identifier_encryption_binding() FROM PUBLIC,eventor_runtime;
CREATE TRIGGER person_identifier_encryption_binding BEFORE INSERT OR UPDATE OF encrypted_value ON eogp.person_identifiers
  FOR EACH ROW EXECUTE FUNCTION eogp.set_person_identifier_encryption_binding();

-- Preserve source-system identifiers through explicitly reviewed identity merges.
-- Freeze a canonical v1 state hash: timestamp/bytea session formatting must not change restoration evidence.
CREATE FUNCTION eogp.guest_registry_reference_state_hash_v1(p_reference eogp.person_identifiers)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,eogp
AS $function$
  SELECT encode(sha256(convert_to(jsonb_build_array(
    (p_reference).id,(p_reference).organization_id,(p_reference).person_id,
    (p_reference).identifier_kind,(p_reference).identifier_hash,encode((p_reference).encrypted_value,'hex'),
    (p_reference).encryption_person_id,
    extract(epoch FROM (p_reference).created_at)
  )::text,'UTF8')),'hex');
$function$;
REVOKE ALL ON FUNCTION eogp.guest_registry_reference_state_hash_v1(eogp.person_identifiers) FROM PUBLIC,eventor_runtime;

CREATE TABLE eogp.person_merge_reference_transfers (
  organization_id uuid NOT NULL,
  merge_id uuid NOT NULL,
  reference_id uuid NOT NULL,
  transferred_state_sha256 text NOT NULL CHECK(transferred_state_sha256 ~ '^[a-f0-9]{64}$'),
  PRIMARY KEY(organization_id,merge_id,reference_id),
  FOREIGN KEY(organization_id,merge_id) REFERENCES eogp.person_merge_records(organization_id,id)
);
-- There is deliberately no current-identifier FK: a later authorized removal remains possible.
-- Missing or edited references block restoration; deleted private values are never recreated from this journal.
ALTER TABLE eogp.person_merge_reference_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.person_merge_reference_transfers FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON eogp.person_merge_reference_transfers
  USING(organization_id=eogp.current_organization_id()) WITH CHECK(organization_id=eogp.current_organization_id());
REVOKE ALL ON eogp.person_merge_reference_transfers FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
CREATE TRIGGER person_merge_reference_transfers_append_only_guard BEFORE UPDATE OR DELETE ON eogp.person_merge_reference_transfers
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
  v_reference_count integer:=0;
  v_reference_state text;
BEGIN
  IF p_source.status <> 'active' OR p_destination.status <> 'active' THEN
    RETURN jsonb_build_object('blocker', 'inactive_profile');
  END IF;
  IF EXISTS (SELECT 1 FROM eogp.persons WHERE organization_id = p_org AND merged_into_person_id = p_source.id)
    OR EXISTS (SELECT 1 FROM eogp.person_relationships WHERE organization_id = p_org AND ended_at IS NULL
      AND (from_person_id = p_source.id OR to_person_id = p_source.id)) THEN
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
      'historicalReference', v_impact->>'historicalReference','contactReference',v_impact->>'contactReference','referenceState',v_impact->>'referenceState')
  ) RETURNING id INTO v_review;
  RETURN jsonb_build_object(
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

ALTER FUNCTION eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text)
  RENAME TO commit_guest_registry_merge_without_reference_transfer;
REVOKE ALL ON FUNCTION eogp.commit_guest_registry_merge_without_reference_transfer(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text)
  FROM PUBLIC,eventor_runtime;

CREATE FUNCTION eogp.commit_guest_registry_merge(
  p_org uuid,p_actor uuid,p_source uuid,p_destination uuid,p_source_revision integer,p_destination_revision integer,
  p_reason text,p_review uuid,p_contact_resolution text,p_reference_resolution text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_source eogp.persons%ROWTYPE; v_destination eogp.persons%ROWTYPE;
  v_impact jsonb; v_references uuid[]; v_result jsonb;
BEGIN
  PERFORM eogp.assert_guest_registry_merge_permission(p_org,p_actor);
  IF p_source=p_destination OR p_reason IS DISTINCT FROM 'duplicate_profile'
    OR (p_reference_resolution IS NOT NULL AND p_reference_resolution<>'move_to_destination') THEN
    RAISE EXCEPTION 'invalid Registry merge resolution' USING ERRCODE='22023';
  END IF;
  IF p_reference_resolution IS NOT NULL THEN PERFORM eogp.assert_guest_reference_permission(p_org,p_actor,true); END IF;
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
      AND safe_metadata->>'referenceState' IS NOT DISTINCT FROM v_impact->>'referenceState'
      AND safe_metadata->>'contactReference' IS NOT DISTINCT FROM v_impact->>'contactReference'
      AND safe_metadata->>'historicalReference' IS NOT DISTINCT FROM v_impact->>'historicalReference'
  ) THEN
    RAISE EXCEPTION 'reviewed Registry references changed' USING ERRCODE='55000';
  END IF;
  IF (v_impact->>'referenceCount')::integer>0 AND p_reference_resolution IS DISTINCT FROM 'move_to_destination' THEN
    RAISE EXCEPTION 'explicit reference transfer resolution required' USING ERRCODE='22023';
  END IF;
  SELECT array_agg(id ORDER BY id) INTO v_references FROM eogp.person_identifiers
    WHERE organization_id=p_org AND person_id=p_source;
  UPDATE eogp.person_identifiers SET person_id=p_destination WHERE organization_id=p_org AND id=ANY(v_references);
  v_result:=eogp.commit_guest_registry_merge_without_reference_transfer(p_org,p_actor,p_source,p_destination,
    p_source_revision,p_destination_revision,p_reason,p_review,p_contact_resolution);
  INSERT INTO eogp.person_merge_reference_transfers(organization_id,merge_id,reference_id,transferred_state_sha256)
    SELECT p_org,(v_result->>'mergeId')::uuid,id,eogp.guest_registry_reference_state_hash_v1(identifier)
    FROM eogp.person_identifiers identifier WHERE organization_id=p_org AND id=ANY(v_references);
  IF cardinality(v_references)>0 THEN
    UPDATE eogp.person_merge_records SET resolution=resolution||'{"references":"moved_unchanged"}'::jsonb
      WHERE organization_id=p_org AND id=(v_result->>'mergeId')::uuid;
    -- Source revision advances in the merge transition; destination reference clients also need invalidation.
    UPDATE eogp.persons SET revision=revision+1,updated_at=clock_timestamp() WHERE organization_id=p_org AND id=p_destination;
  END IF;
  RETURN v_result;
END;
$function$;

-- Recreate both older public entry points so no compiled compatibility path bypasses reference resolution.
CREATE OR REPLACE FUNCTION eogp.commit_guest_registry_merge(
  p_org uuid,p_actor uuid,p_source uuid,p_destination uuid,p_source_revision integer,p_destination_revision integer,
  p_reason text,p_review uuid,p_contact_resolution text
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,eogp
AS $function$
  SELECT eogp.commit_guest_registry_merge(p_org,p_actor,p_source,p_destination,p_source_revision,p_destination_revision,p_reason,p_review,p_contact_resolution,NULL::text);
$function$;
CREATE OR REPLACE FUNCTION eogp.commit_guest_registry_merge(
  p_org uuid,p_actor uuid,p_source uuid,p_destination uuid,p_source_revision integer,p_destination_revision integer,p_reason text,p_review uuid
) RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,eogp
AS $function$
  SELECT eogp.commit_guest_registry_merge(p_org,p_actor,p_source,p_destination,p_source_revision,p_destination_revision,p_reason,p_review,NULL::text,NULL::text);
$function$;

CREATE OR REPLACE FUNCTION eogp.assert_guest_registry_merge_restore_permission(p_org uuid,p_actor uuid,p_merge uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp
AS $function$
BEGIN
  PERFORM eogp.assert_guest_registry_merge_permission(p_org,p_actor);
  IF EXISTS(SELECT 1 FROM eogp.person_merge_contact_transfers WHERE organization_id=p_org AND merge_id=p_merge) THEN
    PERFORM eogp.assert_guest_contact_permission(p_org,p_actor,true);
  END IF;
  IF EXISTS(SELECT 1 FROM eogp.person_merge_reference_transfers WHERE organization_id=p_org AND merge_id=p_merge) THEN
    PERFORM eogp.assert_guest_reference_permission(p_org,p_actor,true);
  END IF;
END;
$function$;

ALTER FUNCTION eogp.restore_guest_registry_merge(uuid,uuid,uuid) RENAME TO restore_guest_registry_merge_without_reference_transfer;
REVOKE ALL ON FUNCTION eogp.restore_guest_registry_merge_without_reference_transfer(uuid,uuid,uuid) FROM PUBLIC,eventor_runtime;
CREATE FUNCTION eogp.restore_guest_registry_merge(p_org uuid,p_actor uuid,p_merge uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp
AS $function$
DECLARE v_merge eogp.person_merge_records%ROWTYPE; v_result jsonb; v_count integer;
BEGIN
  PERFORM eogp.assert_guest_registry_merge_restore_permission(p_org,p_actor,p_merge);
  SELECT * INTO v_merge FROM eogp.person_merge_records WHERE organization_id=p_org AND id=p_merge FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'guest merge not found' USING ERRCODE='P0002'; END IF;
  IF v_merge.restored_at IS NOT NULL THEN RETURN eogp.restore_guest_registry_merge_without_reference_transfer(p_org,p_actor,p_merge); END IF;
  PERFORM 1 FROM eogp.persons WHERE organization_id=p_org AND id IN(v_merge.source_person_id,v_merge.destination_person_id)
    ORDER BY id FOR UPDATE;
  IF EXISTS (
    SELECT 1 FROM eogp.person_merge_reference_transfers transfer
    LEFT JOIN eogp.person_identifiers identifier ON identifier.organization_id=transfer.organization_id AND identifier.id=transfer.reference_id
    WHERE transfer.organization_id=p_org AND transfer.merge_id=p_merge
      AND (identifier.id IS NULL OR identifier.person_id<>v_merge.destination_person_id
        OR eogp.guest_registry_reference_state_hash_v1(identifier) IS DISTINCT FROM transfer.transferred_state_sha256)
  ) THEN
    RAISE EXCEPTION 'transferred references changed or were removed; review correction before restoring' USING ERRCODE='P1831';
  END IF;
  v_result:=eogp.restore_guest_registry_merge_without_reference_transfer(p_org,p_actor,p_merge);
  UPDATE eogp.person_identifiers identifier SET person_id=v_merge.source_person_id
    FROM eogp.person_merge_reference_transfers transfer
    WHERE transfer.organization_id=p_org AND transfer.merge_id=p_merge AND identifier.organization_id=p_org AND identifier.id=transfer.reference_id;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count>0 THEN
    UPDATE eogp.persons SET revision=revision+1,updated_at=clock_timestamp() WHERE organization_id=p_org AND id=v_merge.destination_person_id;
  END IF;
  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text,text),
  eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text),
  eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid),eogp.restore_guest_registry_merge(uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text,text),
  eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid,text),
  eogp.commit_guest_registry_merge(uuid,uuid,uuid,uuid,integer,integer,text,uuid),eogp.restore_guest_registry_merge(uuid,uuid,uuid) TO eventor_runtime;

CREATE OR REPLACE FUNCTION eogp.read_guest_registry_references(p_org uuid, p_actor uuid, p_person uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_revision integer;
  v_refs jsonb;
  v_can_manage boolean := true;
BEGIN
  PERFORM eogp.assert_guest_reference_permission(p_org, p_actor, false);
  SELECT revision INTO v_revision FROM eogp.persons WHERE organization_id = p_org AND id = p_person;
  IF NOT FOUND THEN RAISE EXCEPTION 'person not found' USING ERRCODE = 'P0002'; END IF;
  BEGIN
    PERFORM eogp.assert_guest_reference_permission(p_org, p_actor, true);
  EXCEPTION WHEN insufficient_privilege THEN v_can_manage := false;
  END;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'referenceId', id, 'source', substring(identifier_kind from 17), 'encryptionPersonId',encryption_person_id,
    'ciphertext', replace(encode(encrypted_value, 'base64'), E'\n', '')
  ) ORDER BY identifier_kind, created_at, id), '[]'::jsonb)
  INTO v_refs FROM eogp.person_identifiers
  WHERE organization_id = p_org AND person_id = p_person AND identifier_kind ~ '^external-ref-v1:[A-Z0-9][A-Z0-9_-]{0,39}$';
  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id
  ) VALUES (p_org, p_org, p_actor, 'membership', 'guest.registry.references_viewed', 'person', p_person);
  RETURN jsonb_build_object('references', v_refs, 'canManage', v_can_manage, 'profileRevision', v_revision);
END;
$function$;

