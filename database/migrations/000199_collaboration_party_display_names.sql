-- Each party explicitly publishes its own current name; no cross-tenant directory lookup/backfill.
ALTER TABLE eogp.collaboration_grants ADD COLUMN grantor_display_name text,ADD COLUMN grantee_display_name text;
CREATE FUNCTION eogp.capture_collaboration_party_names() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,eogp AS $function$
BEGIN
 IF TG_OP='INSERT' THEN
  IF eogp.current_organization_id() IS DISTINCT FROM NEW.organization_id THEN RAISE EXCEPTION 'grantor context required to capture its display name' USING ERRCODE='42501';END IF;
  SELECT name INTO STRICT NEW.grantor_display_name FROM eogp.organizations WHERE id=NEW.organization_id;
  NEW.grantee_display_name:=NULL;
 ELSE
  IF NEW.grantor_display_name IS DISTINCT FROM OLD.grantor_display_name OR NEW.grantee_display_name IS DISTINCT FROM OLD.grantee_display_name THEN
   RAISE EXCEPTION 'published party names are immutable' USING ERRCODE='55000';END IF;
  IF OLD.status='proposed' AND NEW.status='active' AND NEW.accepted_at IS NOT NULL AND NEW.accepted_by_membership_id IS NOT NULL THEN
   IF eogp.current_organization_id() IS DISTINCT FROM NEW.grantee_organization_id THEN RAISE EXCEPTION 'recipient context required to capture its display name' USING ERRCODE='42501';END IF;
   SELECT name INTO STRICT NEW.grantee_display_name FROM eogp.organizations WHERE id=NEW.grantee_organization_id;
  END IF;
 END IF;
 RETURN NEW;
END;
$function$;
CREATE TRIGGER collaboration_party_name_capture BEFORE INSERT OR UPDATE ON eogp.collaboration_grants
 FOR EACH ROW EXECUTE FUNCTION eogp.capture_collaboration_party_names();
REVOKE ALL ON FUNCTION eogp.capture_collaboration_party_names() FROM PUBLIC,eventor_runtime,eventor_auth,eventor_worker;
COMMENT ON COLUMN eogp.collaboration_grants.grantor_display_name IS 'Name published in the grantor context at proposal; null for legacy grants, never backfilled or rewritten.';
COMMENT ON COLUMN eogp.collaboration_grants.grantee_display_name IS 'Name published in the recipient context at acceptance; null before acceptance or for legacy grants, never backfilled or rewritten.';
CREATE OR REPLACE FUNCTION eogp.collaboration_grant_metadata(p_grant eogp.collaboration_grants)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog,eogp AS $function$
 SELECT jsonb_build_object('grantId',p_grant.id,'grantorOrganizationId',p_grant.organization_id,'granteeOrganizationId',p_grant.grantee_organization_id,
  'grantorDisplayName',p_grant.grantor_display_name,'granteeDisplayName',p_grant.grantee_display_name,
  'canAccept',p_grant.grantee_organization_id=eogp.current_organization_id() AND p_grant.status='proposed' AND p_grant.valid_from<=statement_timestamp() AND (p_grant.valid_until IS NULL OR p_grant.valid_until>statement_timestamp()),
  'canRevoke',p_grant.organization_id=eogp.current_organization_id() AND p_grant.status IN('proposed','active'),
  'scopeKind',p_grant.scope_kind,'venueId',p_grant.scope_venue_id,'spaceId',p_grant.scope_space_id,'bookingId',p_grant.scope_booking_id,
  'purpose',p_grant.purpose,'allowedActions',p_grant.allowed_actions,'status',p_grant.status,'validFrom',p_grant.valid_from,'validUntil',p_grant.valid_until,
  'effective',p_grant.status='active' AND p_grant.valid_from<=statement_timestamp() AND (p_grant.valid_until IS NULL OR p_grant.valid_until>statement_timestamp()),
  'acceptedAt',p_grant.accepted_at,'revokedAt',p_grant.revoked_at,'createdAt',p_grant.created_at);
$function$;

-- Bind interactive acceptance to the complete reviewed grant meaning, excluding lifecycle metadata.
CREATE FUNCTION eogp.collaboration_grant_review_fingerprint(p_grant eogp.collaboration_grants)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,eogp AS $function$
 SELECT encode(sha256(convert_to(jsonb_build_object('grantId',p_grant.id,'grantor',p_grant.organization_id,'grantee',p_grant.grantee_organization_id,
  'scopeKind',p_grant.scope_kind,'venueId',p_grant.scope_venue_id,'spaceId',p_grant.scope_space_id,'bookingId',p_grant.scope_booking_id,
  'purpose',p_grant.purpose,'allowedActions',p_grant.allowed_actions,'projection',p_grant.projection,
  'validFrom',extract(epoch FROM p_grant.valid_from),'validUntil',extract(epoch FROM p_grant.valid_until))::text,'UTF8')),'hex');
$function$;
CREATE OR REPLACE FUNCTION eogp.read_staff_collaboration_grant(p_org uuid,p_actor uuid,p_grant uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_grant eogp.collaboration_grants%ROWTYPE;
BEGIN
 PERFORM eogp.assert_collaboration_manage_permission(p_org,p_actor);
 SELECT * INTO v_grant FROM eogp.collaboration_grants WHERE id=p_grant AND (organization_id=p_org OR grantee_organization_id=p_org);
 IF NOT FOUND THEN RAISE EXCEPTION 'collaboration grant not found' USING ERRCODE='P0002';END IF;
 INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,action,aggregate_type,aggregate_id)
 VALUES(p_org,p_org,p_actor,'membership','collaboration.grant.viewed','collaboration_grant',p_grant);
 RETURN eogp.collaboration_grant_metadata(v_grant)||jsonb_build_object('projection',v_grant.projection,'reviewFingerprint',eogp.collaboration_grant_review_fingerprint(v_grant));
END;
$function$;
CREATE FUNCTION eogp.assert_reviewed_collaboration_acceptance(p_org uuid,p_actor uuid,p_grant uuid,p_expected text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_grant eogp.collaboration_grants%ROWTYPE;
BEGIN
 PERFORM eogp.assert_staff_collaboration_action(p_org,p_actor,p_grant,'accept');
 IF p_expected IS NULL OR p_expected !~ '^[a-f0-9]{64}$' THEN RAISE EXCEPTION 'valid grant review fingerprint required' USING ERRCODE='22023';END IF;
 SELECT * INTO STRICT v_grant FROM eogp.collaboration_grants WHERE id=p_grant AND grantee_organization_id=p_org;
 IF eogp.collaboration_grant_review_fingerprint(v_grant) IS DISTINCT FROM p_expected THEN RAISE EXCEPTION 'grant meaning changed; review it again' USING ERRCODE='55000';END IF;
END;
$function$;
CREATE FUNCTION eogp.accept_reviewed_collaboration_grant(p_org uuid,p_actor uuid,p_grant uuid,p_expected text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
BEGIN
 PERFORM eogp.assert_reviewed_collaboration_acceptance(p_org,p_actor,p_grant,p_expected);
 RETURN eogp.staff_collaboration_grant_action(p_org,p_actor,p_grant,'accept',NULL);
END;
$function$;
REVOKE ALL ON FUNCTION eogp.collaboration_grant_review_fingerprint(eogp.collaboration_grants),eogp.assert_reviewed_collaboration_acceptance(uuid,uuid,uuid,text),eogp.accept_reviewed_collaboration_grant(uuid,uuid,uuid,text) FROM PUBLIC,eventor_auth,eventor_worker;
REVOKE ALL ON FUNCTION eogp.collaboration_grant_review_fingerprint(eogp.collaboration_grants) FROM eventor_runtime;
GRANT EXECUTE ON FUNCTION eogp.assert_reviewed_collaboration_acceptance(uuid,uuid,uuid,text),eogp.accept_reviewed_collaboration_grant(uuid,uuid,uuid,text) TO eventor_runtime;
