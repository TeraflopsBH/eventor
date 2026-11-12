-- Organization-managed, versioned approval-policy authoring.
-- Published revisions remain immutable; new edits are appended as new revisions.

CREATE FUNCTION eogp.validate_booking_approval_policy_rules(p_rules jsonb)
RETURNS void
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog
AS $function$
DECLARE
  v_rule jsonb;
  v_condition jsonb;
  v_code text;
  v_kind text;
  v_amount numeric;
  v_required numeric;
  v_seen_codes text[] := ARRAY[]::text[];
BEGIN
  IF p_rules IS NULL OR jsonb_typeof(p_rules) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'approval policy rules must be a JSON array' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_rules) > 50 THEN
    RAISE EXCEPTION 'approval policy cannot contain more than 50 rules' USING ERRCODE = '22023';
  END IF;

  FOR v_rule IN SELECT value FROM jsonb_array_elements(p_rules)
  LOOP
    IF jsonb_typeof(v_rule) IS DISTINCT FROM 'object'
       OR jsonb_typeof(v_rule->'code') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_rule->'condition') IS DISTINCT FROM 'object'
       OR jsonb_typeof(v_rule->'requiredApprovals') IS DISTINCT FROM 'number'
       OR jsonb_typeof(v_rule->'permission') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_rule->'separationOfDuties') IS DISTINCT FROM 'boolean' THEN
      RAISE EXCEPTION 'each approval rule must define code, condition, requiredApprovals, permission and separationOfDuties'
        USING ERRCODE = '22023';
    END IF;

    v_code := btrim(v_rule->>'code');
    IF length(v_code) NOT BETWEEN 1 AND 100
       OR v_code = ANY(v_seen_codes)
       OR v_rule->>'permission' <> 'booking.approve' THEN
      RAISE EXCEPTION 'approval rule code must be unique and permission must be booking.approve'
        USING ERRCODE = '22023';
    END IF;
    v_seen_codes := array_append(v_seen_codes,v_code);

    v_required := (v_rule->>'requiredApprovals')::numeric;
    IF v_required <> trunc(v_required) OR v_required NOT BETWEEN 1 AND 10 THEN
      RAISE EXCEPTION 'requiredApprovals must be an integer from 1 to 10' USING ERRCODE = '22023';
    END IF;

    v_condition := v_rule->'condition';
    IF jsonb_typeof(v_condition->'kind') IS DISTINCT FROM 'string' THEN
      RAISE EXCEPTION 'approval condition must define a string kind' USING ERRCODE = '22023';
    END IF;
    v_kind := v_condition->>'kind';

    CASE v_kind
      WHEN 'always' THEN
        NULL;
      WHEN 'total_at_least' THEN
        IF jsonb_typeof(v_condition->'amount') IS DISTINCT FROM 'number'
           OR jsonb_typeof(v_condition->'currency') IS DISTINCT FROM 'string'
           OR (v_condition->>'currency') !~ '^[A-Z]{3}$' THEN
          RAISE EXCEPTION 'total_at_least requires a positive amount and an ISO currency code' USING ERRCODE = '22023';
        END IF;
        v_amount := (v_condition->>'amount')::numeric;
        IF v_amount <= 0 OR v_amount::text IN ('NaN','Infinity','-Infinity') THEN
          RAISE EXCEPTION 'total_at_least amount must be positive and finite' USING ERRCODE = '22023';
        END IF;
      WHEN 'discount_at_least' THEN
        IF jsonb_typeof(v_condition->'amount') IS DISTINCT FROM 'number' THEN
          RAISE EXCEPTION 'discount_at_least requires a numeric amount' USING ERRCODE = '22023';
        END IF;
        v_amount := (v_condition->>'amount')::numeric;
        IF v_amount <= 0 OR v_amount::text IN ('NaN','Infinity','-Infinity') THEN
          RAISE EXCEPTION 'discount_at_least amount must be positive and finite' USING ERRCODE = '22023';
        END IF;
      WHEN 'adjustment_present' THEN
        IF v_condition ? 'adjustmentKind'
           AND (jsonb_typeof(v_condition->'adjustmentKind') IS DISTINCT FROM 'string'
             OR v_condition->>'adjustmentKind' NOT IN ('fee','discount','credit')) THEN
          RAISE EXCEPTION 'adjustment_present adjustmentKind must be fee, discount or credit' USING ERRCODE = '22023';
        END IF;
      ELSE
        RAISE EXCEPTION 'unsupported approval condition kind' USING ERRCODE = '22023';
    END CASE;
  END LOOP;
END;
$function$;

CREATE FUNCTION eogp.get_booking_approval_policies(
  p_organization_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );

  SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      'policyId',policy.id,
      'code',policy.code,
      'name',policy.name,
      'status',policy.status,
      'createdAt',policy.created_at,
      'latestRevisionId',(
        SELECT revision.id
          FROM eogp.booking_approval_policy_revisions revision
         WHERE revision.organization_id=policy.organization_id
           AND revision.policy_id=policy.id
         ORDER BY revision.revision_number DESC
         LIMIT 1
      ),
      'revisions',(
        SELECT coalesce(jsonb_agg(jsonb_build_object(
          'revisionId',revision.id,
          'revisionNumber',revision.revision_number,
          'state',revision.state,
          'rules',revision.rules,
          'publishedAt',revision.published_at,
          'createdAt',revision.created_at
        ) ORDER BY revision.revision_number DESC),'[]'::jsonb)
          FROM eogp.booking_approval_policy_revisions revision
         WHERE revision.organization_id=policy.organization_id
           AND revision.policy_id=policy.id
      )
    ) ORDER BY policy.code
  ),'[]'::jsonb)
    INTO v_result
    FROM eogp.booking_approval_policies policy
   WHERE policy.organization_id=p_organization_id;

  RETURN v_result;
END;
$function$;

CREATE FUNCTION eogp.create_booking_approval_policy(
  p_organization_id uuid,
  p_actor_membership_id uuid,
  p_code text,
  p_name text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_policy_id uuid := gen_random_uuid();
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  IF p_code IS NULL OR length(btrim(p_code)) NOT BETWEEN 2 AND 80
     OR p_name IS NULL OR length(btrim(p_name)) NOT BETWEEN 1 AND 250 THEN
    RAISE EXCEPTION 'policy code and name are invalid' USING ERRCODE = '22023';
  END IF;

  INSERT INTO eogp.booking_approval_policies(id,organization_id,code,name)
  VALUES(v_policy_id,p_organization_id,btrim(p_code),btrim(p_name));

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.approval_policy.created','booking_approval_policy',v_policy_id,
    'approval_policy_created',jsonb_build_object('code',btrim(p_code))
  );

  RETURN jsonb_build_object(
    'policyId',v_policy_id,'state','active'
  );
END;
$function$;

CREATE FUNCTION eogp.create_booking_approval_policy_revision(
  p_organization_id uuid,
  p_policy_id uuid,
  p_actor_membership_id uuid,
  p_rules jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_policy eogp.booking_approval_policies%ROWTYPE;
  v_latest eogp.booking_approval_policy_revisions%ROWTYPE;
  v_revision_id uuid := gen_random_uuid();
  v_revision_number integer;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  PERFORM eogp.validate_booking_approval_policy_rules(p_rules);

  SELECT * INTO v_policy
    FROM eogp.booking_approval_policies
   WHERE organization_id=p_organization_id AND id=p_policy_id
   FOR UPDATE;
  IF NOT FOUND OR v_policy.status <> 'active' THEN
    RAISE EXCEPTION 'active booking approval policy not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_latest
    FROM eogp.booking_approval_policy_revisions
   WHERE organization_id=p_organization_id AND policy_id=p_policy_id
   ORDER BY revision_number DESC
   LIMIT 1
   FOR UPDATE;
  v_revision_number := coalesce(v_latest.revision_number,0)+1;

  INSERT INTO eogp.booking_approval_policy_revisions(
    id,organization_id,policy_id,revision_number,state,rules
  ) VALUES(v_revision_id,p_organization_id,p_policy_id,v_revision_number,'draft',p_rules);

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.approval_policy.revision_created','booking_approval_policy',p_policy_id,
    'approval_policy_revision_created',
    jsonb_build_object('revisionId',v_revision_id,'revisionNumber',v_revision_number,'ruleCount',jsonb_array_length(p_rules))
  );

  RETURN jsonb_build_object(
    'policyId',p_policy_id,'revisionId',v_revision_id,'revisionNumber',v_revision_number,'state','draft'
  );
END;
$function$;

CREATE FUNCTION eogp.publish_booking_approval_policy_revision(
  p_organization_id uuid,
  p_policy_id uuid,
  p_revision_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_policy eogp.booking_approval_policies%ROWTYPE;
  v_revision eogp.booking_approval_policy_revisions%ROWTYPE;
  v_latest_revision_id uuid;
  v_published_at timestamptz := clock_timestamp();
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );

  SELECT * INTO v_policy
    FROM eogp.booking_approval_policies
   WHERE organization_id=p_organization_id AND id=p_policy_id
   FOR UPDATE;
  IF NOT FOUND OR v_policy.status <> 'active' THEN
    RAISE EXCEPTION 'active booking approval policy not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT revision.id INTO v_latest_revision_id
    FROM eogp.booking_approval_policy_revisions revision
   WHERE revision.organization_id=p_organization_id
     AND revision.policy_id=p_policy_id
   ORDER BY revision.revision_number DESC
   LIMIT 1;
  IF v_latest_revision_id IS DISTINCT FROM p_revision_id THEN
    RAISE EXCEPTION 'only the latest policy revision may be published' USING ERRCODE = '40001';
  END IF;

  SELECT * INTO v_revision
    FROM eogp.booking_approval_policy_revisions
   WHERE organization_id=p_organization_id AND policy_id=p_policy_id AND id=p_revision_id
   FOR UPDATE;
  IF NOT FOUND OR v_revision.state <> 'draft' THEN
    RAISE EXCEPTION 'draft approval policy revision is required' USING ERRCODE = '55000';
  END IF;
  PERFORM eogp.validate_booking_approval_policy_rules(v_revision.rules);

  UPDATE eogp.booking_approval_policy_revisions
     SET state='published',published_at=v_published_at
   WHERE organization_id=p_organization_id AND id=p_revision_id;

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.approval_policy.published','booking_approval_policy',p_policy_id,
    'approval_policy_published',jsonb_build_object('revisionId',p_revision_id,'revisionNumber',v_revision.revision_number)
  );

  RETURN jsonb_build_object(
    'policyId',p_policy_id,'revisionId',p_revision_id,
    'revisionNumber',v_revision.revision_number,'state','published','publishedAt',v_published_at
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.validate_booking_approval_policy_rules(jsonb)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.get_booking_approval_policies(uuid,uuid)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.create_booking_approval_policy(uuid,uuid,text,text)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.create_booking_approval_policy_revision(uuid,uuid,uuid,jsonb)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.publish_booking_approval_policy_revision(uuid,uuid,uuid,uuid)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

GRANT EXECUTE ON FUNCTION eogp.get_booking_approval_policies(uuid,uuid),
  eogp.create_booking_approval_policy(uuid,uuid,text,text),
  eogp.create_booking_approval_policy_revision(uuid,uuid,uuid,jsonb),
  eogp.publish_booking_approval_policy_revision(uuid,uuid,uuid,uuid)
  TO eventor_runtime;
