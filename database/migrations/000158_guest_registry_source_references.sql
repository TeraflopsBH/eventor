INSERT INTO eogp.permissions (code, description, scope_kind, is_sensitive) VALUES
  ('guest.registry.references.read', 'Read Registry source-system references', 'organization', true),
  ('guest.registry.references.manage', 'Manage Registry source-system references', 'organization', true);

REVOKE ALL ON eogp.person_identifiers FROM PUBLIC, eventor_runtime;

CREATE FUNCTION eogp.assert_guest_reference_permission(p_org uuid, p_actor uuid, p_write boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  PERFORM eogp.assert_guest_registry_permission(p_org, p_actor, p_write);
  IF NOT p_write THEN
    BEGIN
      PERFORM eogp.assert_event_command_permission(p_org, NULL, p_actor, 'guest.registry.references.read');
      RETURN;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END IF;
  PERFORM eogp.assert_event_command_permission(p_org, NULL, p_actor, 'guest.registry.references.manage');
END;
$function$;

CREATE FUNCTION eogp.read_guest_registry_references(p_org uuid, p_actor uuid, p_person uuid)
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
    'referenceId', id, 'source', substring(identifier_kind from 17),
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

CREATE FUNCTION eogp.write_guest_registry_reference(
  p_org uuid, p_actor uuid, p_person uuid, p_reference uuid, p_revision integer, p_action text,
  p_source text, p_fingerprint text, p_ciphertext bytea
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_profile eogp.persons%ROWTYPE;
  v_reference eogp.person_identifiers%ROWTYPE;
  v_revision integer;
BEGIN
  PERFORM eogp.assert_guest_reference_permission(p_org, p_actor, true);
  SELECT * INTO v_profile FROM eogp.persons WHERE organization_id = p_org AND id = p_person FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'person not found' USING ERRCODE = 'P0002'; END IF;
  IF v_profile.revision IS DISTINCT FROM p_revision THEN
    RAISE EXCEPTION 'person revision conflict' USING ERRCODE = '40001';
  END IF;
  IF v_profile.status <> 'active' THEN RAISE EXCEPTION 'reference profile is not active' USING ERRCODE = '55000'; END IF;
  IF p_action IS NULL OR p_action NOT IN ('add', 'replace', 'remove') OR (p_action = 'add') <> (p_reference IS NULL) THEN
    RAISE EXCEPTION 'invalid reference operation' USING ERRCODE = '22023';
  END IF;
  IF p_action <> 'remove' AND (
    coalesce(p_source, '') !~ '^[A-Z0-9][A-Z0-9_-]{0,39}$'
    OR coalesce(p_fingerprint, '') !~ '^[a-f0-9]{64}$'
    OR p_ciphertext IS NULL OR octet_length(p_ciphertext) NOT BETWEEN 33 AND 160
    OR substring(p_ciphertext from 1 for 4) <> convert_to('ECP1', 'UTF8')
  ) THEN
    RAISE EXCEPTION 'invalid encrypted source reference' USING ERRCODE = '22023';
  END IF;

  IF p_action <> 'add' THEN
    SELECT * INTO v_reference FROM eogp.person_identifiers
    WHERE organization_id = p_org AND person_id = p_person AND id = p_reference
      AND identifier_kind ~ '^external-ref-v1:[A-Z0-9][A-Z0-9_-]{0,39}$' FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'source reference not found' USING ERRCODE = 'P0002'; END IF;
  END IF;

  IF p_action = 'add' THEN
    INSERT INTO eogp.person_identifiers (organization_id, person_id, identifier_kind, identifier_hash, encrypted_value)
    VALUES (p_org, p_person, 'external-ref-v1:' || p_source, p_fingerprint, p_ciphertext) RETURNING * INTO v_reference;
  ELSIF p_action = 'replace' THEN
    IF v_reference.identifier_kind = 'external-ref-v1:' || p_source AND v_reference.identifier_hash = p_fingerprint THEN
      RETURN jsonb_build_object('referenceId', v_reference.id, 'profileRevision', v_profile.revision);
    END IF;
    UPDATE eogp.person_identifiers SET identifier_kind = 'external-ref-v1:' || p_source,
      identifier_hash = p_fingerprint, encrypted_value = p_ciphertext
    WHERE organization_id = p_org AND person_id = p_person AND id = p_reference RETURNING * INTO v_reference;
  ELSE
    DELETE FROM eogp.person_identifiers WHERE organization_id = p_org AND person_id = p_person AND id = p_reference;
  END IF;

  UPDATE eogp.persons SET revision = revision + 1, updated_at = clock_timestamp()
  WHERE organization_id = p_org AND id = p_person RETURNING revision INTO v_revision;
  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership', 'guest.registry.reference.' || p_action, 'person', p_person,
    jsonb_build_object('referenceId', v_reference.id, 'revision', v_revision)
  );
  RETURN jsonb_build_object('referenceId', v_reference.id, 'profileRevision', v_revision);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.assert_guest_reference_permission(uuid,uuid,boolean),
  eogp.read_guest_registry_references(uuid,uuid,uuid),
  eogp.write_guest_registry_reference(uuid,uuid,uuid,uuid,integer,text,text,text,bytea) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.assert_guest_reference_permission(uuid,uuid,boolean),
  eogp.read_guest_registry_references(uuid,uuid,uuid),
  eogp.write_guest_registry_reference(uuid,uuid,uuid,uuid,integer,text,text,text,bytea) TO eventor_runtime;
