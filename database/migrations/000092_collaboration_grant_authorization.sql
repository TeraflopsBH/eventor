-- Collaboration grant proposal, acceptance and revocation require a scoped organization manager.
-- A normal active membership is not sufficient to grant another organization access.

CREATE FUNCTION eogp.assert_collaboration_manage_permission(
  p_organization_id uuid,
  p_actor_membership_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_membership_status text;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id
     OR nullif(current_setting('app.actor_membership_id', true), '')::uuid
          IS DISTINCT FROM p_actor_membership_id THEN
    RAISE EXCEPTION 'organization or staff actor context mismatch' USING ERRCODE = '42501';
  END IF;

  SELECT membership.status INTO v_membership_status
    FROM eogp.organization_memberships membership
   WHERE membership.organization_id = p_organization_id
     AND membership.id = p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_membership_status <> 'active' THEN
    RAISE EXCEPTION 'active collaboration manager membership is required' USING ERRCODE = '42501';
  END IF;

  PERFORM 1
    FROM eogp.user_role_grants user_grant
    JOIN eogp.role_permissions role_permission
      ON role_permission.organization_id = user_grant.organization_id
     AND role_permission.role_id = user_grant.role_id
   WHERE user_grant.organization_id = p_organization_id
     AND user_grant.membership_id = p_actor_membership_id
     AND user_grant.scope_kind = 'organization'
     AND user_grant.revoked_at IS NULL
     AND (user_grant.expires_at IS NULL OR user_grant.expires_at > clock_timestamp())
     AND role_permission.permission_code = 'collaboration.manage'
   FOR SHARE OF user_grant, role_permission;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'collaboration.manage permission is required' USING ERRCODE = '42501';
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.propose_collaboration_grant(
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
  IF nullif(current_setting('app.actor_membership_id', true), '')::uuid
       IS DISTINCT FROM p_actor_membership_id THEN
    RAISE EXCEPTION 'staff actor context mismatch' USING ERRCODE = '42501';
  END IF;
  IF v_organization_id IS NULL OR p_grantee_organization_id IS NULL
     OR p_grantee_organization_id = v_organization_id THEN
    RAISE EXCEPTION 'grantor tenant and a different grantee tenant are required'
      USING ERRCODE = '22023';
  END IF;

  PERFORM eogp.assert_collaboration_manage_permission(v_organization_id,p_actor_membership_id);

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

CREATE OR REPLACE FUNCTION eogp.accept_collaboration_grant(
  p_grant_id uuid,
  p_actor_membership_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_organization_id uuid := eogp.current_organization_id();
  v_member_status text;
  v_grantor_organization_id uuid;
  v_status text;
  v_accepted_by uuid;
  v_valid_from timestamptz;
  v_valid_until timestamptz;
BEGIN
  IF v_organization_id IS NULL THEN
    RAISE EXCEPTION 'tenant context is required' USING ERRCODE = '42501';
  END IF;

  PERFORM eogp.assert_collaboration_manage_permission(v_organization_id,p_actor_membership_id);

  SELECT organization_id, status, accepted_by_membership_id, valid_from, valid_until
    INTO v_grantor_organization_id, v_status, v_accepted_by, v_valid_from, v_valid_until
    FROM eogp.collaboration_grants
   WHERE id = p_grant_id
     AND grantee_organization_id = v_organization_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'collaboration grant not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_status = 'active' AND v_accepted_by = p_actor_membership_id THEN
    RETURN;
  END IF;
  IF v_status <> 'proposed' THEN
    RAISE EXCEPTION 'collaboration grant is not awaiting acceptance' USING ERRCODE = '55000';
  END IF;
  IF v_valid_from > clock_timestamp() OR (v_valid_until IS NOT NULL AND v_valid_until <= clock_timestamp()) THEN
    RAISE EXCEPTION 'collaboration grant is outside its acceptance window' USING ERRCODE = '55000';
  END IF;

  UPDATE eogp.collaboration_grants
     SET status = 'active',
         accepted_by_membership_id = p_actor_membership_id,
         accepted_at = clock_timestamp()
   WHERE organization_id = v_grantor_organization_id
     AND id = p_grant_id;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action,
    aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    v_organization_id, v_organization_id, p_actor_membership_id, 'membership',
    'collaboration.grant.accepted', 'collaboration_grant', p_grant_id,
    jsonb_build_object('grantorOrganizationId', v_grantor_organization_id)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.revoke_collaboration_grant(
  p_grant_id uuid,
  p_actor_membership_id uuid,
  p_reason text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_organization_id uuid := eogp.current_organization_id();
  v_member_status text;
  v_status text;
BEGIN
  IF v_organization_id IS NULL OR nullif(trim(p_reason), '') IS NULL THEN
    RAISE EXCEPTION 'tenant context and revocation reason are required' USING ERRCODE = '22023';
  END IF;

  PERFORM eogp.assert_collaboration_manage_permission(v_organization_id,p_actor_membership_id);

  SELECT status INTO v_status
    FROM eogp.collaboration_grants
   WHERE organization_id = v_organization_id
     AND id = p_grant_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'collaboration grant not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_status = 'revoked' THEN
    RETURN;
  END IF;
  IF v_status NOT IN ('proposed','active') THEN
    RAISE EXCEPTION 'collaboration grant cannot be revoked from its current state' USING ERRCODE = '55000';
  END IF;

  UPDATE eogp.collaboration_grants
     SET status = 'revoked',
         revoked_at = clock_timestamp()
   WHERE organization_id = v_organization_id
     AND id = p_grant_id;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind, action,
    aggregate_type, aggregate_id, reason_code, safe_metadata
  ) VALUES (
    v_organization_id, v_organization_id, p_actor_membership_id, 'membership',
    'collaboration.grant.revoked', 'collaboration_grant', p_grant_id, 'grant_revoked',
    jsonb_build_object('reason', p_reason)
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.assert_collaboration_manage_permission(uuid,uuid)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
