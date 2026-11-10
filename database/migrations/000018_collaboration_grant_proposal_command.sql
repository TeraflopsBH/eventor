-- The API runtime has no direct DML on collaboration_grants.
-- This command validates the grantor actor and atomically records proposal,
-- revision 1 and audit provenance under the authorized grantor tenant.

CREATE FUNCTION eogp.propose_collaboration_grant(
  p_grant_id uuid,
  p_grantee_organization_id uuid,
  p_scope_kind text,
  p_scope_venue_id uuid,
  p_scope_space_id uuid,
  p_scope_booking_id uuid,
  p_purpose text,
  p_projection jsonb,
  p_allowed_actions text[],
  p_valid_from timestamptz,
  p_valid_until timestamptz,
  p_actor_membership_id uuid
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_organization_id uuid := eogp.current_organization_id();
  v_member_status text;
  v_grant_id uuid := coalesce(p_grant_id, gen_random_uuid());
BEGIN
  IF v_organization_id IS NULL OR p_grantee_organization_id IS NULL
     OR p_grantee_organization_id = v_organization_id THEN
    RAISE EXCEPTION 'grantor tenant and a different grantee tenant are required'
      USING ERRCODE = '22023';
  END IF;

  IF nullif(btrim(p_purpose), '') IS NULL
     OR p_projection IS NULL
     OR jsonb_typeof(p_projection) <> 'object'
     OR p_allowed_actions IS NULL
     OR cardinality(p_allowed_actions) = 0
     OR EXISTS (
       SELECT 1 FROM unnest(p_allowed_actions) AS a(action_code)
        WHERE action_code IS NULL OR nullif(btrim(action_code), '') IS NULL
     )
     OR p_valid_from IS NULL
     OR (p_valid_until IS NOT NULL AND p_valid_until <= p_valid_from) THEN
    RAISE EXCEPTION 'grant purpose, projection, actions and validity are invalid'
      USING ERRCODE = '22023';
  END IF;

  SELECT status
    INTO v_member_status
    FROM eogp.organization_memberships
   WHERE organization_id = v_organization_id
     AND id = p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_member_status <> 'active' THEN
    RAISE EXCEPTION 'active grantor membership is required'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO eogp.collaboration_grants (
    id, organization_id, grantee_organization_id, scope_kind,
    scope_venue_id, scope_space_id, scope_booking_id, purpose,
    projection, allowed_actions, status, valid_from, valid_until,
    proposed_by_membership_id
  ) VALUES (
    v_grant_id, v_organization_id, p_grantee_organization_id, p_scope_kind,
    p_scope_venue_id, p_scope_space_id, p_scope_booking_id, btrim(p_purpose),
    p_projection, p_allowed_actions, 'proposed', p_valid_from, p_valid_until,
    p_actor_membership_id
  );

  INSERT INTO eogp.collaboration_grant_revisions (
    organization_id, grant_id, revision_number, projection,
    allowed_actions, changed_by_membership_id
  ) VALUES (
    v_organization_id, v_grant_id, 1, p_projection,
    p_allowed_actions, p_actor_membership_id
  );

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id,
    actor_kind, action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    v_organization_id, v_organization_id, p_actor_membership_id,
    'membership', 'collaboration.grant.proposed',
    'collaboration_grant', v_grant_id,
    jsonb_build_object(
      'granteeOrganizationId', p_grantee_organization_id,
      'scopeKind', p_scope_kind
    )
  );

  RETURN v_grant_id;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.propose_collaboration_grant(
  uuid,uuid,text,uuid,uuid,uuid,text,jsonb,text[],timestamptz,timestamptz,uuid
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.propose_collaboration_grant(
  uuid,uuid,text,uuid,uuid,uuid,text,jsonb,text[],timestamptz,timestamptz,uuid
) TO eventor_runtime;
