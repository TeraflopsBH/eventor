INSERT INTO eogp.permissions (code, description, scope_kind, is_sensitive)
VALUES ('guest.registry.contacts.verify', 'Record or revoke evidence of contact ownership', 'organization', true);

ALTER TABLE eogp.person_contact_points
  ADD COLUMN verification_method text,
  ADD COLUMN verified_at timestamptz,
  ADD COLUMN verified_by_membership_id uuid,
  ADD CONSTRAINT person_contact_verifier_same_org FOREIGN KEY (organization_id, verified_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id),
  ADD CONSTRAINT person_contact_verification_evidence CHECK (
    (verification_method IS NULL AND verified_at IS NULL AND verified_by_membership_id IS NULL)
    OR (is_verified AND verification_method IS NOT NULL AND verified_at IS NOT NULL AND verified_by_membership_id IS NOT NULL
      AND (verification_method = 'in_person' OR (verification_method = 'callback' AND contact_kind = 'phone')))
  );

CREATE FUNCTION eogp.assert_guest_contact_verification_permission(p_org uuid, p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  PERFORM eogp.assert_guest_contact_permission(p_org, p_actor, false);
  PERFORM eogp.assert_event_command_permission(p_org, NULL, p_actor, 'guest.registry.contacts.verify');
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.read_guest_registry_contacts(p_org uuid, p_actor uuid, p_person uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_contacts jsonb;
  v_can_manage boolean := true;
  v_can_verify boolean := true;
BEGIN
  PERFORM eogp.assert_guest_contact_permission(p_org, p_actor, false);
  IF NOT EXISTS (SELECT 1 FROM eogp.persons WHERE organization_id = p_org AND id = p_person) THEN
    RAISE EXCEPTION 'person not found' USING ERRCODE = 'P0002';
  END IF;
  BEGIN
    PERFORM eogp.assert_guest_contact_permission(p_org, p_actor, true);
  EXCEPTION WHEN insufficient_privilege THEN v_can_manage := false;
  END;

  BEGIN
    PERFORM eogp.assert_guest_contact_verification_permission(p_org, p_actor);
  EXCEPTION WHEN insufficient_privilege THEN v_can_verify := false;
  END;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'contactId', id, 'kind', contact_kind, 'ciphertext', replace(encode(encrypted_value, 'base64'), E'\n', ''),
    'revision', revision, 'consent', contact_consent, 'primary', is_primary, 'verified', is_verified,
    'verification', CASE WHEN verified_at IS NOT NULL THEN
      jsonb_build_object('method', verification_method, 'at', verified_at)
    END
  ) ORDER BY is_primary DESC, created_at, id), '[]'::jsonb)
  INTO v_contacts FROM eogp.person_contact_points
  WHERE organization_id = p_org AND person_id = p_person AND contact_kind IN ('email', 'phone');

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id
  ) VALUES (p_org, p_org, p_actor, 'membership', 'guest.registry.contacts_viewed', 'person', p_person);
  RETURN jsonb_build_object('contacts', v_contacts, 'canManage', v_can_manage, 'canVerify', v_can_verify);
END;
$function$;

CREATE FUNCTION eogp.set_guest_registry_contact_verification(
  p_org uuid, p_actor uuid, p_person uuid, p_contact uuid, p_expected_revision integer, p_method text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_status text;
  v_contact eogp.person_contact_points%ROWTYPE;
BEGIN
  PERFORM eogp.assert_guest_contact_verification_permission(p_org, p_actor);
  SELECT status INTO v_status FROM eogp.persons WHERE organization_id = p_org AND id = p_person FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'person not found' USING ERRCODE = 'P0002'; END IF;
  IF v_status <> 'active' THEN RAISE EXCEPTION 'contact profile is not active' USING ERRCODE = '55000'; END IF;
  SELECT * INTO v_contact FROM eogp.person_contact_points
  WHERE organization_id = p_org AND person_id = p_person AND id = p_contact
    AND contact_kind IN ('email', 'phone') FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'contact not found' USING ERRCODE = 'P0002'; END IF;
  IF v_contact.revision IS DISTINCT FROM p_expected_revision THEN
    RAISE EXCEPTION 'contact revision conflict' USING ERRCODE = '40001';
  END IF;
  IF p_method IS NOT NULL THEN
    IF p_method NOT IN ('in_person', 'callback') OR (p_method = 'callback' AND v_contact.contact_kind <> 'phone') THEN
      RAISE EXCEPTION 'verification method does not apply to this contact' USING ERRCODE = '22023';
    END IF;
    IF v_contact.contact_consent = 'withdrawn' THEN
      RAISE EXCEPTION 'withdrawn contact cannot be verified' USING ERRCODE = '55000';
    END IF;
  END IF;
  IF v_contact.is_verified = (p_method IS NOT NULL) AND v_contact.verification_method IS NOT DISTINCT FROM p_method THEN
    RETURN jsonb_build_object('contactId', p_contact, 'revision', v_contact.revision, 'verified', v_contact.is_verified);
  END IF;

  UPDATE eogp.person_contact_points SET is_verified = p_method IS NOT NULL, verification_method = p_method,
    verified_at = CASE WHEN p_method IS NOT NULL THEN clock_timestamp() END,
    verified_by_membership_id = CASE WHEN p_method IS NOT NULL THEN p_actor END,
    revision = revision + 1, updated_at = clock_timestamp()
  WHERE organization_id = p_org AND person_id = p_person AND id = p_contact RETURNING * INTO v_contact;
  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_org, p_org, p_actor, 'membership',
    CASE WHEN p_method IS NULL THEN 'guest.registry.contact_verification_revoked' ELSE 'guest.registry.contact_verified' END,
    'person', p_person, jsonb_build_object('contactId', p_contact, 'kind', v_contact.contact_kind,
      'method', p_method, 'revision', v_contact.revision)
  );
  RETURN jsonb_build_object('contactId', p_contact, 'revision', v_contact.revision, 'verified', v_contact.is_verified);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.assert_guest_contact_verification_permission(uuid,uuid),
  eogp.set_guest_registry_contact_verification(uuid,uuid,uuid,uuid,integer,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.assert_guest_contact_verification_permission(uuid,uuid),
  eogp.set_guest_registry_contact_verification(uuid,uuid,uuid,uuid,integer,text) TO eventor_runtime;
