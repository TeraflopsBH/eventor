-- Revoking a proposal must preserve that no recipient ever accepted it.
-- The existing authorized revoke command already permits proposed and active states.
ALTER TABLE eogp.collaboration_grants
 DROP CONSTRAINT collaboration_grants_check5,
 ADD CONSTRAINT collaboration_grants_effective_acceptance_check CHECK (
  status NOT IN ('active','expired') OR (accepted_at IS NOT NULL AND accepted_by_membership_id IS NOT NULL));
-- Acceptance actor/time pairing and revoked-status/time pairing remain enforced.

-- Explicit projections replace unrestricted direct runtime reads of grant configuration.
REVOKE ALL ON eogp.collaboration_grants FROM PUBLIC,eventor_runtime,eventor_auth,eventor_worker;
CREATE FUNCTION eogp.collaboration_grant_metadata(p_grant eogp.collaboration_grants)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog,eogp AS $function$
 SELECT jsonb_build_object('grantId',p_grant.id,'grantorOrganizationId',p_grant.organization_id,'granteeOrganizationId',p_grant.grantee_organization_id,
  'scopeKind',p_grant.scope_kind,'venueId',p_grant.scope_venue_id,'spaceId',p_grant.scope_space_id,'bookingId',p_grant.scope_booking_id,
  'purpose',p_grant.purpose,'allowedActions',p_grant.allowed_actions,'status',p_grant.status,'validFrom',p_grant.valid_from,'validUntil',p_grant.valid_until,
  'effective',p_grant.status='active' AND p_grant.valid_from<=statement_timestamp() AND (p_grant.valid_until IS NULL OR p_grant.valid_until>statement_timestamp()),
  'acceptedAt',p_grant.accepted_at,'revokedAt',p_grant.revoked_at,'createdAt',p_grant.created_at);
$function$;
CREATE FUNCTION eogp.list_staff_collaboration_grants(p_org uuid,p_actor uuid,p_offset integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_rows jsonb;
BEGIN
 PERFORM eogp.assert_collaboration_manage_permission(p_org,p_actor);
 IF coalesce(p_offset,-1) NOT BETWEEN 0 AND 100000 THEN RAISE EXCEPTION 'invalid collaboration grant page' USING ERRCODE='22023';END IF;
 SELECT coalesce(jsonb_agg(eogp.collaboration_grant_metadata(grant_row) ORDER BY grant_row.created_at DESC,grant_row.id),'[]'::jsonb) INTO v_rows
 FROM(SELECT * FROM eogp.collaboration_grants WHERE organization_id=p_org OR grantee_organization_id=p_org ORDER BY created_at DESC,id LIMIT 51 OFFSET p_offset) grant_row;
 INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,action,aggregate_type,aggregate_id)
 VALUES(p_org,p_org,p_actor,'membership','collaboration.grants.viewed','organization',p_org);
 RETURN jsonb_build_object('grants',CASE WHEN jsonb_array_length(v_rows)>50 THEN v_rows-50 ELSE v_rows END,'nextOffset',CASE WHEN jsonb_array_length(v_rows)>50 AND p_offset<=99950 THEN p_offset+50 END);
END;
$function$;
CREATE FUNCTION eogp.read_staff_collaboration_grant(p_org uuid,p_actor uuid,p_grant uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_grant eogp.collaboration_grants%ROWTYPE;
BEGIN
 PERFORM eogp.assert_collaboration_manage_permission(p_org,p_actor);
 SELECT * INTO v_grant FROM eogp.collaboration_grants WHERE id=p_grant AND (organization_id=p_org OR grantee_organization_id=p_org);
 IF NOT FOUND THEN RAISE EXCEPTION 'collaboration grant not found' USING ERRCODE='P0002';END IF;
 INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,action,aggregate_type,aggregate_id)
 VALUES(p_org,p_org,p_actor,'membership','collaboration.grant.viewed','collaboration_grant',p_grant);
 -- Projection is the deliberately shared scope configuration, not provider source records or revisions.
 RETURN eogp.collaboration_grant_metadata(v_grant)||jsonb_build_object('projection',v_grant.projection);
END;
$function$;
CREATE FUNCTION eogp.assert_staff_collaboration_action(p_org uuid,p_actor uuid,p_grant uuid,p_action text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_grant eogp.collaboration_grants%ROWTYPE;
BEGIN
 PERFORM eogp.assert_collaboration_manage_permission(p_org,p_actor);
 IF p_action IS NULL OR p_action NOT IN('accept','revoke') THEN RAISE EXCEPTION 'unsupported collaboration action' USING ERRCODE='22023';END IF;
 SELECT * INTO v_grant FROM eogp.collaboration_grants WHERE id=p_grant
  AND ((p_action='accept' AND grantee_organization_id=p_org) OR (p_action='revoke' AND organization_id=p_org)) FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'collaboration grant not found' USING ERRCODE='P0002';END IF;
 IF p_action='accept' AND (v_grant.status NOT IN('proposed','active') OR v_grant.valid_from>clock_timestamp() OR (v_grant.valid_until IS NOT NULL AND v_grant.valid_until<=clock_timestamp())
  OR (v_grant.status='active' AND v_grant.accepted_by_membership_id IS DISTINCT FROM p_actor)) THEN RAISE EXCEPTION 'grant is not available for this acceptance' USING ERRCODE='55000';END IF;
 IF p_action='revoke' AND v_grant.status NOT IN('proposed','active','revoked') THEN RAISE EXCEPTION 'grant cannot be revoked from its current state' USING ERRCODE='55000';END IF;
END;
$function$;
CREATE FUNCTION eogp.staff_collaboration_grant_action(p_org uuid,p_actor uuid,p_grant uuid,p_action text,p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_grant eogp.collaboration_grants%ROWTYPE;
BEGIN
 PERFORM eogp.assert_staff_collaboration_action(p_org,p_actor,p_grant,p_action);
 IF p_action='accept' THEN
  IF p_reason IS NOT NULL THEN RAISE EXCEPTION 'acceptance does not record a revocation reason' USING ERRCODE='22023';END IF;
  PERFORM eogp.accept_collaboration_grant(p_grant,p_actor);
 ELSE
  IF coalesce(length(btrim(p_reason)),0) NOT BETWEEN 3 AND 2000 OR p_reason ~ '[[:cntrl:]]' THEN RAISE EXCEPTION 'valid revocation reason required' USING ERRCODE='22023';END IF;
  PERFORM eogp.revoke_collaboration_grant(p_grant,p_actor,btrim(p_reason));
 END IF;
 SELECT * INTO STRICT v_grant FROM eogp.collaboration_grants WHERE id=p_grant AND (organization_id=p_org OR grantee_organization_id=p_org);
 RETURN eogp.collaboration_grant_metadata(v_grant);
END;
$function$;
REVOKE ALL ON FUNCTION eogp.collaboration_grant_metadata(eogp.collaboration_grants),eogp.list_staff_collaboration_grants(uuid,uuid,integer),
 eogp.read_staff_collaboration_grant(uuid,uuid,uuid),eogp.assert_staff_collaboration_action(uuid,uuid,uuid,text),eogp.staff_collaboration_grant_action(uuid,uuid,uuid,text,text)
 FROM PUBLIC,eventor_auth,eventor_worker;
REVOKE ALL ON FUNCTION eogp.collaboration_grant_metadata(eogp.collaboration_grants) FROM eventor_runtime;
GRANT EXECUTE ON FUNCTION eogp.list_staff_collaboration_grants(uuid,uuid,integer),eogp.read_staff_collaboration_grant(uuid,uuid,uuid),
 eogp.assert_staff_collaboration_action(uuid,uuid,uuid,text),eogp.staff_collaboration_grant_action(uuid,uuid,uuid,text,text) TO eventor_runtime;
