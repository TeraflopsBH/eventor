-- Organization-managed, versioned cancellation-policy authoring.
-- Existing offer revisions and confirmed booking snapshots pin exact policy revision IDs;
-- publishing a successor never rewrites those historical snapshots.

CREATE FUNCTION eogp.validate_booking_cancellation_policy_revision(
  p_customer_mode text,p_public_terms text,
  p_approval_rules jsonb,p_commercial_rules jsonb,p_notice_rules jsonb
) RETURNS void
LANGUAGE plpgsql IMMUTABLE
SET search_path=pg_catalog
AS $function$
BEGIN
  IF p_customer_mode IS NULL OR p_customer_mode NOT IN ('request_only','approval_required','self_service')
     OR p_public_terms IS NULL OR length(btrim(p_public_terms)) NOT BETWEEN 1 AND 10000
     OR p_approval_rules IS NULL OR jsonb_typeof(p_approval_rules) IS DISTINCT FROM 'object'
     OR p_commercial_rules IS NULL OR jsonb_typeof(p_commercial_rules) IS DISTINCT FROM 'object'
     OR p_notice_rules IS NULL OR jsonb_typeof(p_notice_rules) IS DISTINCT FROM 'object'
     OR octet_length(p_approval_rules::text)>20000
     OR octet_length(p_commercial_rules::text)>20000
     OR octet_length(p_notice_rules::text)>20000 THEN
    RAISE EXCEPTION 'cancellation policy revision is invalid' USING ERRCODE='22023';
  END IF;
END;
$function$;

CREATE FUNCTION eogp.get_booking_cancellation_policies(
  p_organization_id uuid,p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE v_result jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'policyId',policy.id,'code',policy.code,'name',policy.name,'status',policy.status,
    'latestRevisionId',(SELECT revision.id FROM eogp.cancellation_policy_revisions revision
      WHERE revision.organization_id=policy.organization_id
        AND revision.cancellation_policy_id=policy.id
      ORDER BY revision.revision_number DESC LIMIT 1),
    'revisions',(SELECT coalesce(jsonb_agg(jsonb_build_object(
      'revisionId',revision.id,'revisionNumber',revision.revision_number,
      'customerMode',revision.customer_mode,'publicTerms',revision.public_terms,
      'approvalRules',revision.approval_rules,'commercialRules',revision.commercial_rules,
      'noticeRules',revision.notice_rules,'state',revision.state,
      'publishedAt',revision.published_at,'createdAt',revision.created_at
    ) ORDER BY revision.revision_number DESC),'[]'::jsonb)
      FROM eogp.cancellation_policy_revisions revision
      WHERE revision.organization_id=policy.organization_id
        AND revision.cancellation_policy_id=policy.id)
  ) ORDER BY policy.code),'[]'::jsonb)
  INTO v_result FROM eogp.cancellation_policies policy
  WHERE policy.organization_id=p_organization_id;
  RETURN v_result;
END;
$function$;

CREATE FUNCTION eogp.create_booking_cancellation_policy(
  p_organization_id uuid,p_actor_membership_id uuid,p_code text,p_name text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE v_policy_id uuid:=gen_random_uuid();
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  IF p_code IS NULL OR length(btrim(p_code)) NOT BETWEEN 2 AND 80
     OR p_code !~ '^[A-Za-z0-9][A-Za-z0-9._-]*$'
     OR p_name IS NULL OR length(btrim(p_name)) NOT BETWEEN 1 AND 250 THEN
    RAISE EXCEPTION 'cancellation policy code and name are invalid' USING ERRCODE='22023';
  END IF;
  INSERT INTO eogp.cancellation_policies(id,organization_id,code,name)
  VALUES(v_policy_id,p_organization_id,btrim(p_code),btrim(p_name));
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.cancellation_policy.created','cancellation_policy',v_policy_id,
    'cancellation_policy_created',jsonb_build_object('code',btrim(p_code)));
  RETURN jsonb_build_object('policyId',v_policy_id,'state','active');
END;
$function$;

CREATE FUNCTION eogp.create_booking_cancellation_policy_revision(
  p_organization_id uuid,p_policy_id uuid,p_actor_membership_id uuid,
  p_customer_mode text,p_public_terms text,p_approval_rules jsonb,
  p_commercial_rules jsonb,p_notice_rules jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_policy eogp.cancellation_policies%ROWTYPE;
  v_latest eogp.cancellation_policy_revisions%ROWTYPE;
  v_revision_id uuid:=gen_random_uuid(); v_number integer;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  PERFORM eogp.validate_booking_cancellation_policy_revision(
    p_customer_mode,p_public_terms,p_approval_rules,p_commercial_rules,p_notice_rules
  );
  SELECT * INTO v_policy FROM eogp.cancellation_policies
   WHERE organization_id=p_organization_id AND id=p_policy_id FOR UPDATE;
  IF NOT FOUND OR v_policy.status<>'active' THEN
    RAISE EXCEPTION 'active cancellation policy not found' USING ERRCODE='P0002';
  END IF;
  SELECT * INTO v_latest FROM eogp.cancellation_policy_revisions
   WHERE organization_id=p_organization_id AND cancellation_policy_id=p_policy_id
   ORDER BY revision_number DESC LIMIT 1 FOR UPDATE;
  IF FOUND AND v_latest.state='draft' THEN
    RAISE EXCEPTION 'update the latest draft revision instead of creating another revision' USING ERRCODE='55000';
  END IF;
  v_number:=coalesce(v_latest.revision_number,0)+1;
  INSERT INTO eogp.cancellation_policy_revisions(
    id,organization_id,cancellation_policy_id,revision_number,customer_mode,
    approval_rules,commercial_rules,notice_rules,public_terms,state
  ) VALUES(v_revision_id,p_organization_id,p_policy_id,v_number,p_customer_mode,
    p_approval_rules,p_commercial_rules,p_notice_rules,btrim(p_public_terms),'draft');
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.cancellation_policy.revision_created','cancellation_policy',p_policy_id,
    'cancellation_policy_revision_created',
    jsonb_build_object('revisionId',v_revision_id,'revisionNumber',v_number));
  RETURN jsonb_build_object('policyId',p_policy_id,'revisionId',v_revision_id,'revisionNumber',v_number,'state','draft');
END;
$function$;

CREATE FUNCTION eogp.update_booking_cancellation_policy_draft_revision(
  p_organization_id uuid,p_policy_id uuid,p_revision_id uuid,p_actor_membership_id uuid,
  p_customer_mode text,p_public_terms text,p_approval_rules jsonb,
  p_commercial_rules jsonb,p_notice_rules jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_policy eogp.cancellation_policies%ROWTYPE;
  v_revision eogp.cancellation_policy_revisions%ROWTYPE;
  v_latest_id uuid;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  PERFORM eogp.validate_booking_cancellation_policy_revision(
    p_customer_mode,p_public_terms,p_approval_rules,p_commercial_rules,p_notice_rules
  );
  SELECT * INTO v_policy FROM eogp.cancellation_policies
   WHERE organization_id=p_organization_id AND id=p_policy_id FOR UPDATE;
  IF NOT FOUND OR v_policy.status<>'active' THEN
    RAISE EXCEPTION 'active cancellation policy not found' USING ERRCODE='P0002';
  END IF;
  SELECT id INTO v_latest_id FROM eogp.cancellation_policy_revisions
   WHERE organization_id=p_organization_id AND cancellation_policy_id=p_policy_id
   ORDER BY revision_number DESC LIMIT 1;
  IF v_latest_id IS DISTINCT FROM p_revision_id THEN
    RAISE EXCEPTION 'only the latest draft revision may be updated' USING ERRCODE='40001';
  END IF;
  SELECT * INTO v_revision FROM eogp.cancellation_policy_revisions
   WHERE organization_id=p_organization_id AND cancellation_policy_id=p_policy_id AND id=p_revision_id
   FOR UPDATE;
  IF NOT FOUND OR v_revision.state<>'draft' THEN
    RAISE EXCEPTION 'latest draft cancellation policy revision is required' USING ERRCODE='55000';
  END IF;
  UPDATE eogp.cancellation_policy_revisions SET
    customer_mode=p_customer_mode,public_terms=btrim(p_public_terms),
    approval_rules=p_approval_rules,commercial_rules=p_commercial_rules,notice_rules=p_notice_rules
   WHERE organization_id=p_organization_id AND id=p_revision_id;
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.cancellation_policy.draft_updated','cancellation_policy',p_policy_id,
    'cancellation_policy_draft_updated',jsonb_build_object('revisionId',p_revision_id,'revisionNumber',v_revision.revision_number));
  RETURN jsonb_build_object('policyId',p_policy_id,'revisionId',p_revision_id,'revisionNumber',v_revision.revision_number,'state','draft');
END;
$function$;

CREATE FUNCTION eogp.publish_booking_cancellation_policy_revision(
  p_organization_id uuid,p_policy_id uuid,p_revision_id uuid,p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_policy eogp.cancellation_policies%ROWTYPE;
  v_revision eogp.cancellation_policy_revisions%ROWTYPE;
  v_latest_id uuid; v_published_at timestamptz:=clock_timestamp();
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  SELECT * INTO v_policy FROM eogp.cancellation_policies
   WHERE organization_id=p_organization_id AND id=p_policy_id FOR UPDATE;
  IF NOT FOUND OR v_policy.status<>'active' THEN
    RAISE EXCEPTION 'active cancellation policy not found' USING ERRCODE='P0002';
  END IF;
  SELECT id INTO v_latest_id FROM eogp.cancellation_policy_revisions
   WHERE organization_id=p_organization_id AND cancellation_policy_id=p_policy_id
   ORDER BY revision_number DESC LIMIT 1;
  IF v_latest_id IS DISTINCT FROM p_revision_id THEN
    RAISE EXCEPTION 'only the latest policy revision may be published' USING ERRCODE='40001';
  END IF;
  SELECT * INTO v_revision FROM eogp.cancellation_policy_revisions
   WHERE organization_id=p_organization_id AND cancellation_policy_id=p_policy_id AND id=p_revision_id
   FOR UPDATE;
  IF NOT FOUND OR v_revision.state<>'draft' THEN
    RAISE EXCEPTION 'draft cancellation policy revision is required' USING ERRCODE='55000';
  END IF;
  PERFORM eogp.validate_booking_cancellation_policy_revision(
    v_revision.customer_mode,v_revision.public_terms,v_revision.approval_rules,
    v_revision.commercial_rules,v_revision.notice_rules
  );
  UPDATE eogp.cancellation_policy_revisions
   SET state='published',published_at=v_published_at
   WHERE organization_id=p_organization_id AND id=p_revision_id;
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.cancellation_policy.published','cancellation_policy',p_policy_id,
    'cancellation_policy_published',jsonb_build_object('revisionId',p_revision_id,'revisionNumber',v_revision.revision_number));
  RETURN jsonb_build_object('policyId',p_policy_id,'revisionId',p_revision_id,
    'revisionNumber',v_revision.revision_number,'state','published','publishedAt',v_published_at);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.validate_booking_cancellation_policy_revision(text,text,jsonb,jsonb,jsonb)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.get_booking_cancellation_policies(uuid,uuid)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.create_booking_cancellation_policy(uuid,uuid,text,text)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.create_booking_cancellation_policy_revision(uuid,uuid,uuid,text,text,jsonb,jsonb,jsonb)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.update_booking_cancellation_policy_draft_revision(uuid,uuid,uuid,uuid,text,text,jsonb,jsonb,jsonb)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.publish_booking_cancellation_policy_revision(uuid,uuid,uuid,uuid)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON TABLE eogp.cancellation_policies,eogp.cancellation_policy_revisions
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

GRANT EXECUTE ON FUNCTION eogp.get_booking_cancellation_policies(uuid,uuid),
  eogp.create_booking_cancellation_policy(uuid,uuid,text,text),
  eogp.create_booking_cancellation_policy_revision(uuid,uuid,uuid,text,text,jsonb,jsonb,jsonb),
  eogp.update_booking_cancellation_policy_draft_revision(uuid,uuid,uuid,uuid,text,text,jsonb,jsonb,jsonb),
  eogp.publish_booking_cancellation_policy_revision(uuid,uuid,uuid,uuid)
  TO eventor_runtime;
