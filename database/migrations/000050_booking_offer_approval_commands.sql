-- Evaluate and decide approvals against the immutable, policy-pinned offer revision.
ALTER TABLE eogp.booking_offers
  ADD COLUMN created_by_membership_id uuid,
  ADD CONSTRAINT booking_offers_created_by_membership_fk
    FOREIGN KEY (organization_id,created_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id,id);

CREATE UNIQUE INDEX booking_offer_approval_actor_rule_uq
  ON eogp.booking_offer_approval_decisions
    (organization_id,offer_revision_id,rule_code,actor_membership_id);

CREATE FUNCTION eogp.capture_booking_offer_creator()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_actor_id uuid;
BEGIN
  IF NEW.created_by_membership_id IS NULL THEN
    v_actor_id := nullif(current_setting('app.actor_membership_id',true),'')::uuid;
    IF v_actor_id IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM eogp.organization_memberships membership
         WHERE membership.organization_id=NEW.organization_id
           AND membership.id=v_actor_id
           AND membership.status='active'
      ) THEN
        RAISE EXCEPTION 'offer creator must be an active organization membership'
          USING ERRCODE = '42501';
      END IF;
      NEW.created_by_membership_id := v_actor_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER booking_offers_creator_attribution
  BEFORE INSERT ON eogp.booking_offers
  FOR EACH ROW EXECUTE FUNCTION eogp.capture_booking_offer_creator();

REVOKE ALL ON FUNCTION eogp.capture_booking_offer_creator()
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

CREATE FUNCTION eogp.evaluate_booking_offer_approval_requirements(
  p_rules jsonb,
  p_terms jsonb
) RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path = pg_catalog
AS $function$
DECLARE
  v_rule jsonb;
  v_condition jsonb;
  v_code text;
  v_kind text;
  v_permission text;
  v_separation boolean;
  v_required integer;
  v_amount numeric;
  v_total numeric;
  v_discount_total numeric := 0;
  v_currency text;
  v_adjustment_kind text;
  v_matches boolean;
  v_result jsonb := '[]'::jsonb;
  v_seen_codes text[] := ARRAY[]::text[];
BEGIN
  IF p_rules IS NULL OR jsonb_typeof(p_rules) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'approval policy rules must be a JSON array'
      USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_rules) > 50 THEN
    RAISE EXCEPTION 'approval policy cannot contain more than 50 rules'
      USING ERRCODE = '22023';
  END IF;
  IF jsonb_typeof(p_terms) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'offer commercial terms must be a JSON object'
      USING ERRCODE = '22023';
  END IF;

  BEGIN
    v_total := (p_terms->>'totalAmount')::numeric;
  EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
    RAISE EXCEPTION 'offer total is invalid for approval evaluation'
      USING ERRCODE = '22023';
  END;
  v_currency := p_terms->>'currency';

  SELECT coalesce(sum((adjustment->>'amount')::numeric),0)
    INTO v_discount_total
    FROM jsonb_array_elements(coalesce(p_terms->'adjustments','[]'::jsonb)) AS adjustments(adjustment)
   WHERE adjustments.adjustment->>'kind' IN ('discount','credit');

  FOR v_rule IN SELECT value FROM jsonb_array_elements(p_rules)
  LOOP
    IF jsonb_typeof(v_rule) IS DISTINCT FROM 'object'
       OR jsonb_typeof(v_rule->'code') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_rule->'condition') IS DISTINCT FROM 'object'
       OR jsonb_typeof(v_rule->'requiredApprovals') IS DISTINCT FROM 'number'
       OR jsonb_typeof(v_rule->'permission') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_rule->'separationOfDuties') IS DISTINCT FROM 'boolean' THEN
      RAISE EXCEPTION 'approval rule must define code, condition, requiredApprovals, permission and separationOfDuties'
        USING ERRCODE = '22023';
    END IF;
    v_code := btrim(v_rule->>'code');
    v_condition := v_rule->'condition';
    v_kind := v_condition->>'kind';
    v_permission := v_rule->>'permission';
    v_separation := (v_rule->>'separationOfDuties')::boolean;
    BEGIN
      v_required := (v_rule->>'requiredApprovals')::integer;
    EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RAISE EXCEPTION 'approval rule requiredApprovals must be an integer'
        USING ERRCODE = '22023';
    END;

    IF length(v_code) NOT BETWEEN 1 AND 100
       OR v_code = ANY(v_seen_codes)
       OR v_required NOT BETWEEN 1 AND 10
       OR v_permission <> 'booking.approve' THEN
      RAISE EXCEPTION 'approval rule code, approval count or permission is invalid'
        USING ERRCODE = '22023';
    END IF;
    v_seen_codes := array_append(v_seen_codes,v_code);

    v_matches := false;
    CASE v_kind
      WHEN 'always' THEN
        v_matches := true;
      WHEN 'total_at_least' THEN
        IF jsonb_typeof(v_condition->'amount') IS DISTINCT FROM 'number'
           OR jsonb_typeof(v_condition->'currency') IS DISTINCT FROM 'string'
           OR v_condition->>'currency' <> v_currency THEN
          RAISE EXCEPTION 'total_at_least requires a positive amount and the offer currency'
            USING ERRCODE = '22023';
        END IF;
        v_amount := (v_condition->>'amount')::numeric;
        IF v_amount <= 0 OR v_amount::text IN ('NaN','Infinity','-Infinity') THEN
          RAISE EXCEPTION 'approval threshold amount must be positive'
            USING ERRCODE = '22023';
        END IF;
        v_matches := v_total >= v_amount;
      WHEN 'discount_at_least' THEN
        IF jsonb_typeof(v_condition->'amount') IS DISTINCT FROM 'number' THEN
          RAISE EXCEPTION 'discount_at_least requires a numeric amount'
            USING ERRCODE = '22023';
        END IF;
        v_amount := (v_condition->>'amount')::numeric;
        IF v_amount <= 0 OR v_amount::text IN ('NaN','Infinity','-Infinity') THEN
          RAISE EXCEPTION 'discount threshold amount must be positive'
            USING ERRCODE = '22023';
        END IF;
        v_matches := v_discount_total >= v_amount;
      WHEN 'adjustment_present' THEN
        IF v_condition ? 'adjustmentKind' THEN
          v_adjustment_kind := v_condition->>'adjustmentKind';
          IF v_adjustment_kind NOT IN ('fee','discount','credit') THEN
            RAISE EXCEPTION 'adjustment_present has an invalid adjustmentKind'
              USING ERRCODE = '22023';
          END IF;
          SELECT EXISTS (
            SELECT 1 FROM jsonb_array_elements(coalesce(p_terms->'adjustments','[]'::jsonb)) AS adjustments(adjustment)
             WHERE adjustments.adjustment->>'kind'=v_adjustment_kind
          ) INTO v_matches;
        ELSE
          v_matches := jsonb_array_length(coalesce(p_terms->'adjustments','[]'::jsonb)) > 0;
        END IF;
      ELSE
        RAISE EXCEPTION 'unsupported approval policy condition kind'
          USING ERRCODE = '22023';
    END CASE;

    IF v_matches THEN
      v_result := v_result || jsonb_build_array(jsonb_build_object(
        'code',v_code,
        'condition',v_condition,
        'requiredApprovals',v_required,
        'permission',v_permission,
        'separationOfDuties',v_separation
      ));
    END IF;
  END LOOP;
  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.evaluate_booking_offer_approval_requirements(jsonb,jsonb)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

CREATE FUNCTION eogp.pin_booking_offer_approval_requirements()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_rules jsonb;
BEGIN
  IF NEW.approval_policy_revision_id IS NULL THEN
    NEW.approval_requirements_snapshot := '[]'::jsonb;
    RETURN NEW;
  END IF;

  SELECT policy_revision.rules INTO v_rules
    FROM eogp.booking_approval_policy_revisions policy_revision
    JOIN eogp.booking_approval_policies policy
      ON policy.organization_id=policy_revision.organization_id
     AND policy.id=policy_revision.policy_id
   WHERE policy_revision.organization_id=NEW.organization_id
     AND policy_revision.id=NEW.approval_policy_revision_id
     AND policy_revision.state='published'
     AND policy.status='active'
   FOR SHARE OF policy_revision,policy;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'offer must pin a published active approval policy revision'
      USING ERRCODE = '23503';
  END IF;

  NEW.approval_requirements_snapshot :=
    eogp.evaluate_booking_offer_approval_requirements(v_rules,NEW.terms_snapshot);
  RETURN NEW;
END;
$function$;

CREATE TRIGGER booking_offer_approval_requirements_pin
  BEFORE INSERT ON eogp.booking_offer_revisions
  FOR EACH ROW EXECUTE FUNCTION eogp.pin_booking_offer_approval_requirements();

REVOKE ALL ON FUNCTION eogp.pin_booking_offer_approval_requirements()
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

CREATE FUNCTION eogp.decide_booking_offer_approval(
  p_organization_id uuid,
  p_offer_id uuid,
  p_offer_revision_id uuid,
  p_actor_membership_id uuid,
  p_rule_code text,
  p_decision text,
  p_reason text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_offer eogp.booking_offers%ROWTYPE;
  v_revision eogp.booking_offer_revisions%ROWTYPE;
  v_rule jsonb;
  v_required integer;
  v_separation boolean;
  v_approved_count integer;
  v_blocked_count integer;
  v_actor_status text;
BEGIN
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.approve']::text[]
  );
  IF p_rule_code IS NULL OR length(btrim(p_rule_code)) NOT BETWEEN 1 AND 100
     OR p_decision NOT IN ('approved','rejected','returned_for_changes')
     OR p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 3 AND 2000 THEN
    RAISE EXCEPTION 'offer approval decision is invalid'
      USING ERRCODE = '22023';
  END IF;

  SELECT offer.* INTO v_offer
    FROM eogp.booking_offers offer
   WHERE offer.organization_id=p_organization_id AND offer.id=p_offer_id
   FOR UPDATE;
  IF NOT FOUND OR v_offer.status NOT IN ('issued','accepted') THEN
    RAISE EXCEPTION 'offer is not in a state that accepts approval decisions'
      USING ERRCODE = '55000';
  END IF;

  SELECT revision.* INTO v_revision
    FROM eogp.booking_offer_revisions revision
   WHERE revision.organization_id=p_organization_id
     AND revision.id=p_offer_revision_id
     AND revision.offer_id=p_offer_id
   FOR UPDATE;
  IF NOT FOUND OR v_revision.state NOT IN ('issued','accepted') THEN
    RAISE EXCEPTION 'offer revision is not awaiting or holding approval decisions'
      USING ERRCODE = '55000';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM eogp.booking_offer_revisions latest
     WHERE latest.organization_id=p_organization_id
       AND latest.offer_id=p_offer_id
       AND latest.id=p_offer_revision_id
       AND latest.revision_number=(
         SELECT max(item.revision_number) FROM eogp.booking_offer_revisions item
          WHERE item.organization_id=p_organization_id AND item.offer_id=p_offer_id
       )
  ) THEN
    RAISE EXCEPTION 'approval decisions must apply to the current offer revision'
      USING ERRCODE = '55000';
  END IF;

  SELECT requirement.value INTO v_rule
    FROM jsonb_array_elements(v_revision.approval_requirements_snapshot) AS requirement(value)
   WHERE requirement.value->>'code'=p_rule_code;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'this offer revision has no approval requirement with that rule code'
      USING ERRCODE = '22023';
  END IF;
  v_required := (v_rule->>'requiredApprovals')::integer;
  v_separation := (v_rule->>'separationOfDuties')::boolean;

  SELECT membership.status INTO v_actor_status
    FROM eogp.organization_memberships membership
   WHERE membership.organization_id=p_organization_id
     AND membership.id=p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_actor_status <> 'active' THEN
    RAISE EXCEPTION 'active approver membership is required'
      USING ERRCODE = '42501';
  END IF;

  IF v_separation AND v_offer.created_by_membership_id IS NOT NULL
     AND v_offer.created_by_membership_id=p_actor_membership_id THEN
    RAISE EXCEPTION 'offer creator cannot approve this offer under its separation-of-duties rule'
      USING ERRCODE = '42501';
  END IF;

  SELECT count(*) FILTER (WHERE decision.decision='approved')::integer,
         count(*) FILTER (WHERE decision.decision<>'approved')::integer
    INTO v_approved_count,v_blocked_count
    FROM eogp.booking_offer_approval_decisions decision
   WHERE decision.organization_id=p_organization_id
     AND decision.offer_revision_id=p_offer_revision_id
     AND decision.rule_code=p_rule_code;
  IF v_blocked_count > 0 OR v_approved_count >= v_required THEN
    RAISE EXCEPTION 'approval requirement is already blocked or satisfied'
      USING ERRCODE = '55000';
  END IF;

  INSERT INTO eogp.booking_offer_approval_decisions (
    organization_id,offer_id,offer_revision_id,rule_code,decision,actor_membership_id,reason
  ) VALUES (
    p_organization_id,p_offer_id,p_offer_revision_id,p_rule_code,p_decision,p_actor_membership_id,btrim(p_reason)
  );

  SELECT count(*)::integer INTO v_approved_count
    FROM eogp.booking_offer_approval_decisions decision
   WHERE decision.organization_id=p_organization_id
     AND decision.offer_revision_id=p_offer_revision_id
     AND decision.rule_code=p_rule_code
     AND decision.decision='approved';

  INSERT INTO eogp.audit_events (
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.offer.approval.'||p_decision,'booking_offer',p_offer_id,'offer_approval_decision',
    jsonb_build_object(
      'offerRevisionId',p_offer_revision_id,
      'ruleCode',p_rule_code,
      'decision',p_decision,
      'approvedCount',v_approved_count,
      'requiredApprovals',v_required
    )
  );

  RETURN jsonb_build_object(
    'offerId',p_offer_id,
    'offerRevisionId',p_offer_revision_id,
    'ruleCode',p_rule_code,
    'decision',p_decision,
    'approvedCount',v_approved_count,
    'requiredApprovals',v_required,
    'satisfied',p_decision='approved' AND v_approved_count>=v_required
  );
END;
$function$;

CREATE FUNCTION eogp.get_booking_offer_approval_status(
  p_organization_id uuid,
  p_offer_id uuid,
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
    p_organization_id,p_actor_membership_id,
    ARRAY['booking.manage','booking.approve','booking.confirm']::text[]
  );

  SELECT jsonb_build_object(
    'offerId',offer.id,
    'offerRevisionId',revision.id,
    'requirements',(
      SELECT coalesce(jsonb_agg(
        jsonb_build_object(
          'ruleCode',requirements.requirement->>'code',
          'condition',requirements.requirement->'condition',
          'requiredApprovals',(requirements.requirement->>'requiredApprovals')::integer,
          'separationOfDuties',(requirements.requirement->>'separationOfDuties')::boolean,
          'approvedCount',(
            SELECT count(*)::integer
              FROM eogp.booking_offer_approval_decisions decision
             WHERE decision.organization_id=offer.organization_id
               AND decision.offer_revision_id=revision.id
               AND decision.rule_code=requirement->>'code'
               AND decision.decision='approved'
          ),
          'blocked',EXISTS(
            SELECT 1
              FROM eogp.booking_offer_approval_decisions decision
             WHERE decision.organization_id=offer.organization_id
               AND decision.offer_revision_id=revision.id
               AND decision.rule_code=requirement->>'code'
               AND decision.decision<>'approved'
          ),
          'decisions',(
            SELECT coalesce(jsonb_agg(jsonb_build_object(
              'membershipId',decision.actor_membership_id,
              'decision',decision.decision,
              'reason',decision.reason,
              'decidedAt',decision.decided_at
            ) ORDER BY decision.decided_at,decision.id),'[]'::jsonb)
              FROM eogp.booking_offer_approval_decisions decision
             WHERE decision.organization_id=offer.organization_id
               AND decision.offer_revision_id=revision.id
               AND decision.rule_code=requirement->>'code'
          )
        )
      ),'[]'::jsonb)
        FROM jsonb_array_elements(revision.approval_requirements_snapshot) AS requirements(requirement)
    )
  )
    INTO v_result
    FROM eogp.booking_offers offer
    JOIN LATERAL (
      SELECT item.*
        FROM eogp.booking_offer_revisions item
       WHERE item.organization_id=offer.organization_id
         AND item.offer_id=offer.id
       ORDER BY item.revision_number DESC
       LIMIT 1
    ) revision ON true
   WHERE offer.organization_id=p_organization_id
     AND offer.id=p_offer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking offer not found'
      USING ERRCODE = 'P0002';
  END IF;
  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.decide_booking_offer_approval(uuid,uuid,uuid,uuid,text,text,text)
  FROM PUBLIC,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.get_booking_offer_approval_status(uuid,uuid,uuid)
  FROM PUBLIC,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.decide_booking_offer_approval(uuid,uuid,uuid,uuid,text,text,text),
  eogp.get_booking_offer_approval_status(uuid,uuid,uuid)
  TO eventor_runtime;
