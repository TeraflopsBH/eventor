INSERT INTO eogp.permissions (code, description, scope_kind, is_sensitive) VALUES
  ('guest.registry.contacts.read', 'Read organizer guest contact values', 'organization', true),
  ('guest.registry.contacts.manage', 'Manage organizer guest contact values and consent', 'organization', true);

ALTER TABLE eogp.person_contact_points ADD COLUMN revision integer NOT NULL DEFAULT 1 CHECK (revision > 0);
REVOKE ALL ON eogp.person_contact_points FROM eventor_runtime;

CREATE FUNCTION eogp.assert_guest_contact_permission(p_org uuid, p_actor uuid, p_write boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  PERFORM eogp.assert_guest_registry_permission(p_org, p_actor, false);
  IF NOT p_write THEN
    BEGIN
      PERFORM eogp.assert_event_command_permission(p_org, NULL, p_actor, 'guest.registry.contacts.read');
      RETURN;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END IF;
  PERFORM eogp.assert_event_command_permission(p_org, NULL, p_actor, 'guest.registry.contacts.manage');
END;
$function$;

CREATE FUNCTION eogp.read_guest_registry_contacts(p_org uuid, p_actor uuid, p_person uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_contacts jsonb;
  v_can_manage boolean := true;
BEGIN
  PERFORM eogp.assert_guest_contact_permission(p_org, p_actor, false);
  IF NOT EXISTS (SELECT 1 FROM eogp.persons WHERE organization_id = p_org AND id = p_person) THEN
    RAISE EXCEPTION 'person not found' USING ERRCODE = 'P0002';
  END IF;
  BEGIN
    PERFORM eogp.assert_guest_contact_permission(p_org, p_actor, true);
  EXCEPTION WHEN insufficient_privilege THEN v_can_manage := false;
  END;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'contactId', id, 'kind', contact_kind, 'ciphertext', replace(encode(encrypted_value, 'base64'), E'\n', ''),
    'revision', revision, 'consent', contact_consent, 'primary', is_primary, 'verified', is_verified
  ) ORDER BY is_primary DESC, created_at, id), '[]'::jsonb)
  INTO v_contacts FROM eogp.person_contact_points
  WHERE organization_id = p_org AND person_id = p_person AND contact_kind IN ('email', 'phone');

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id
  ) VALUES (p_org, p_org, p_actor, 'membership', 'guest.registry.contacts_viewed', 'person', p_person);
  RETURN jsonb_build_object('contacts', v_contacts, 'canManage', v_can_manage);
END;
$function$;

CREATE FUNCTION eogp.write_guest_registry_contact(
  p_org uuid, p_actor uuid, p_person uuid, p_contact uuid, p_revision integer,
  p_kind text, p_fingerprint text, p_ciphertext bytea, p_consent text, p_primary boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_person_status text;
  v_contact eogp.person_contact_points%ROWTYPE;
  v_kind text;
BEGIN
  PERFORM eogp.assert_guest_contact_permission(p_org, p_actor, true);
  SELECT status INTO v_person_status FROM eogp.persons WHERE organization_id = p_org AND id = p_person FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'person not found' USING ERRCODE = 'P0002'; END IF;
  IF v_person_status <> 'active' THEN RAISE EXCEPTION 'contact profile is not active' USING ERRCODE = '55000'; END IF;

  IF p_consent IS NULL OR p_consent NOT IN ('unknown', 'permitted', 'restricted', 'withdrawn')
     OR p_primary IS NULL OR (p_primary AND p_consent = 'withdrawn') THEN
    RAISE EXCEPTION 'invalid contact preferences' USING ERRCODE = '22023';
  END IF;

  IF p_contact IS NULL THEN
    IF p_kind IS NULL OR p_kind NOT IN ('email', 'phone')
       OR coalesce(p_fingerprint, '') !~ '^[0-9a-f]{64}$'
       OR p_ciphertext IS NULL OR octet_length(p_ciphertext) NOT BETWEEN 33 AND 2048
       OR substring(p_ciphertext from 1 for 4) <> convert_to('ECP1', 'UTF8') THEN
      RAISE EXCEPTION 'invalid encrypted contact' USING ERRCODE = '22023';
    END IF;
    IF EXISTS (SELECT 1 FROM eogp.person_contact_points WHERE organization_id = p_org AND person_id = p_person
        AND contact_kind = p_kind AND normalized_value_hash = p_fingerprint) THEN
      RAISE EXCEPTION 'contact value already exists on this profile' USING ERRCODE = '23505';
    END IF;
    v_kind := p_kind;
  ELSE
    SELECT * INTO v_contact FROM eogp.person_contact_points
    WHERE organization_id = p_org AND person_id = p_person AND id = p_contact
      AND contact_kind IN ('email', 'phone')
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'contact not found' USING ERRCODE = 'P0002'; END IF;
    IF p_revision IS DISTINCT FROM v_contact.revision THEN
      RAISE EXCEPTION 'contact revision conflict' USING ERRCODE = '40001';
    END IF;
    v_kind := v_contact.contact_kind;
  END IF;

  IF p_primary AND EXISTS (
    SELECT 1 FROM eogp.person_contact_points WHERE organization_id = p_org AND person_id = p_person
      AND contact_kind = v_kind AND is_primary AND id IS DISTINCT FROM p_contact
  ) THEN
    RAISE EXCEPTION 'clear the current primary contact first' USING ERRCODE = '55000';
  END IF;

  IF p_contact IS NULL THEN
    INSERT INTO eogp.person_contact_points (
      organization_id, person_id, contact_kind, normalized_value_hash, encrypted_value, is_primary, contact_consent
    ) VALUES (p_org, p_person, v_kind, p_fingerprint, p_ciphertext, p_primary, p_consent) RETURNING * INTO v_contact;
  ELSE
    UPDATE eogp.person_contact_points
    SET contact_consent = p_consent, is_primary = p_primary, revision = revision + 1, updated_at = clock_timestamp()
    WHERE organization_id = p_org AND person_id = p_person AND id = p_contact RETURNING * INTO v_contact;
  END IF;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership',
    CASE WHEN p_contact IS NULL THEN 'guest.registry.contact_added' ELSE 'guest.registry.contact_preferences_updated' END,
    'person', p_person, jsonb_build_object('contactId', v_contact.id, 'kind', v_kind, 'revision', v_contact.revision)
  );
  RETURN jsonb_build_object('contactId', v_contact.id, 'revision', v_contact.revision);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.assert_guest_contact_permission(uuid,uuid,boolean), eogp.read_guest_registry_contacts(uuid,uuid,uuid),
  eogp.write_guest_registry_contact(uuid,uuid,uuid,uuid,integer,text,text,bytea,text,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.assert_guest_contact_permission(uuid,uuid,boolean), eogp.read_guest_registry_contacts(uuid,uuid,uuid),
  eogp.write_guest_registry_contact(uuid,uuid,uuid,uuid,integer,text,text,bytea,text,boolean) TO eventor_runtime;
