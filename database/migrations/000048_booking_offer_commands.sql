-- Booking offer preparation, successor revisions and explicit issuance.
-- Customer capabilities are created only when staff explicitly issues a prepared revision.

CREATE UNIQUE INDEX booking_offers_one_per_draft_uq
  ON eogp.booking_offers (organization_id, draft_id);

CREATE FUNCTION eogp.assert_booking_commercial_permission(
  p_organization_id uuid,
  p_actor_membership_id uuid,
  p_permission_codes text[]
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_status text;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;
  IF p_permission_codes IS NULL OR cardinality(p_permission_codes) = 0
     OR NOT p_permission_codes <@ ARRAY['booking.manage','booking.approve','booking.confirm']::text[] THEN
    RAISE EXCEPTION 'unsupported booking commercial permission' USING ERRCODE = '22023';
  END IF;

  SELECT membership.status INTO v_status
    FROM eogp.organization_memberships membership
   WHERE membership.organization_id = p_organization_id
     AND membership.id = p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_status <> 'active' THEN
    RAISE EXCEPTION 'active organization membership is required' USING ERRCODE = '42501';
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
     AND role_permission.permission_code = ANY(p_permission_codes)
   FOR SHARE OF user_grant, role_permission;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking commercial permission is required' USING ERRCODE = '42501';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.assert_booking_commercial_permission(uuid,uuid,text[])
  FROM PUBLIC, eventor_runtime, eventor_worker, eventor_auth;

CREATE FUNCTION eogp.save_booking_offer_revision(
  p_organization_id uuid,
  p_draft_revision_id uuid,
  p_actor_membership_id uuid,
  p_offer_id uuid,
  p_price_list_revision_id uuid,
  p_cancellation_policy_revision_id uuid,
  p_approval_policy_revision_id uuid,
  p_currency text,
  p_tax_basis text,
  p_valid_until timestamptz,
  p_line_items jsonb,
  p_adjustments jsonb,
  p_tax_amount numeric,
  p_internal_reason text,
  p_supersede_current boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_draft_id uuid;
  v_draft_status text;
  v_current_revision_id uuid;
  v_revision_number integer;
  v_target_revision_number integer;
  v_offer_id uuid := p_offer_id;
  v_offer_status text;
  v_previous_revision_id uuid;
  v_previous_state text;
  v_previous_revision_number integer;
  v_currency char(3);
  v_tax_basis text;
  v_effective_from timestamptz;
  v_effective_until timestamptz;
  v_policy_terms text;
  v_approval_rules jsonb := '[]'::jsonb;
  v_line jsonb;
  v_item_code text;
  v_quantity numeric;
  v_unit_amount numeric;
  v_price_item eogp.booking_price_items%ROWTYPE;
  v_line_total numeric;
  v_line_count integer := 0;
  v_adjustment_count integer := 0;
  v_subtotal numeric := 0;
  v_total numeric := 0;
  v_tax numeric;
  v_lines jsonb := '[]'::jsonb;
  v_adjustments jsonb := '[]'::jsonb;
  v_adjustment_amount numeric;
  v_adjustment_kind text;
  v_adjustment_label text;
  v_adjustment_code text;
  v_space_lines jsonb;
  v_resource_lines jsonb;
  v_requested_start timestamptz;
  v_requested_end timestamptz;
  v_timezone text;
  v_revision_id uuid := gen_random_uuid();
BEGIN
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id, p_actor_membership_id, ARRAY['booking.manage']::text[]
  );

  IF p_currency IS NULL OR p_currency !~ '^[A-Z]{3}$'
     OR p_tax_basis IS NULL OR p_tax_basis NOT IN ('inclusive','exclusive','not_applicable','to_be_confirmed')
     OR p_valid_until IS NULL OR p_valid_until <= clock_timestamp()
     OR p_tax_amount IS NULL OR p_tax_amount < 0
     OR p_tax_amount > 999999999999.99
     OR p_tax_amount::text IN ('NaN','Infinity','-Infinity')
     OR scale(trim_scale(p_tax_amount)) > 2 THEN
    RAISE EXCEPTION 'offer currency, tax basis, validity or tax amount is invalid'
      USING ERRCODE = '22023';
  END IF;
  v_tax := p_tax_amount;
  IF p_line_items IS NULL OR jsonb_typeof(p_line_items) <> 'array' THEN
    RAISE EXCEPTION 'offer line items must be a JSON array' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_line_items) > 100 THEN
    RAISE EXCEPTION 'offer line items cannot contain more than 100 entries' USING ERRCODE = '22023';
  END IF;
  IF p_adjustments IS NULL OR jsonb_typeof(p_adjustments) <> 'array' THEN
    RAISE EXCEPTION 'offer adjustments must be a JSON array' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_adjustments) > 50 THEN
    RAISE EXCEPTION 'offer adjustments cannot contain more than 50 entries' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_line_items) = 0 AND jsonb_array_length(p_adjustments) = 0 THEN
    RAISE EXCEPTION 'an offer must contain at least one priced item or adjustment'
      USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_adjustments) > 0
     AND (p_internal_reason IS NULL OR length(btrim(p_internal_reason)) < 3) THEN
    RAISE EXCEPTION 'a reason is required when manual price adjustments are included'
      USING ERRCODE = '22023';
  END IF;

  SELECT draft.id, draft.status, draft.current_revision_number,
         revision.id, revision.revision_number, revision.requested_start, revision.requested_end,
         revision.timezone_name
    INTO v_draft_id, v_draft_status, v_revision_number,
         v_current_revision_id, v_target_revision_number, v_requested_start, v_requested_end, v_timezone
    FROM eogp.booking_draft_revisions revision
    JOIN eogp.booking_drafts draft
      ON draft.organization_id = revision.organization_id
     AND draft.id = revision.draft_id
   WHERE revision.organization_id = p_organization_id
     AND revision.id = p_draft_revision_id
   FOR UPDATE OF draft;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking draft revision not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_draft_status <> 'draft' OR v_current_revision_id IS DISTINCT FROM p_draft_revision_id
     OR v_revision_number IS DISTINCT FROM v_target_revision_number THEN
    RAISE EXCEPTION 'offers can be prepared only from the current revision of an editable draft'
      USING ERRCODE = '55000';
  END IF;

  SELECT revision.currency, revision.tax_basis, revision.effective_from, revision.effective_until
    INTO v_currency, v_tax_basis, v_effective_from, v_effective_until
    FROM eogp.booking_price_list_revisions revision
   WHERE revision.organization_id = p_organization_id
     AND revision.id = p_price_list_revision_id
     AND revision.state = 'published'
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'published price-list revision not found' USING ERRCODE = '23503';
  END IF;
  IF v_currency <> p_currency OR v_tax_basis <> p_tax_basis THEN
    RAISE EXCEPTION 'offer currency and tax basis must match the selected price-list revision'
      USING ERRCODE = '22023';
  END IF;
  IF (v_effective_from IS NOT NULL AND v_effective_from > clock_timestamp())
     OR (v_effective_until IS NOT NULL AND v_effective_until <= p_valid_until) THEN
    RAISE EXCEPTION 'price-list revision must remain effective through the offer validity period'
      USING ERRCODE = '55000';
  END IF;

  SELECT policy_revision.public_terms
    INTO v_policy_terms
    FROM eogp.cancellation_policy_revisions policy_revision
    JOIN eogp.cancellation_policies policy
      ON policy.organization_id = policy_revision.organization_id
     AND policy.id = policy_revision.cancellation_policy_id
   WHERE policy_revision.organization_id = p_organization_id
     AND policy_revision.id = p_cancellation_policy_revision_id
     AND policy_revision.state = 'published'
     AND policy.status = 'active'
   FOR SHARE OF policy_revision, policy;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'published active cancellation-policy revision not found' USING ERRCODE = '23503';
  END IF;

  IF p_approval_policy_revision_id IS NOT NULL THEN
    SELECT policy_revision.rules INTO v_approval_rules
      FROM eogp.booking_approval_policy_revisions policy_revision
      JOIN eogp.booking_approval_policies policy
        ON policy.organization_id = policy_revision.organization_id
       AND policy.id = policy_revision.policy_id
     WHERE policy_revision.organization_id = p_organization_id
       AND policy_revision.id = p_approval_policy_revision_id
       AND policy_revision.state = 'published'
       AND policy.status = 'active'
     FOR SHARE OF policy_revision, policy;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'published active approval-policy revision not found' USING ERRCODE = '23503';
    END IF;
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'venueSpaceId',line.venue_space_id,
    'blockKind',line.block_kind,
    'startsAt',line.starts_at,
    'endsAt',line.ends_at,
    'requestedCapacity',line.requested_capacity
  ) ORDER BY line.starts_at,line.id),'[]'::jsonb)
    INTO v_space_lines
    FROM eogp.booking_draft_space_lines line
   WHERE line.organization_id=p_organization_id
     AND line.draft_revision_id=p_draft_revision_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'resourceTypeId',line.resource_type_id,
    'lineCode',line.line_code,
    'label',line.label_snapshot,
    'requestedQuantity',line.requested_quantity,
    'values',line.value_snapshot
  ) ORDER BY line.line_code,line.id),'[]'::jsonb)
    INTO v_resource_lines
    FROM eogp.booking_resource_lines line
   WHERE line.organization_id=p_organization_id
     AND line.draft_revision_id=p_draft_revision_id;

  FOR v_line IN SELECT value FROM jsonb_array_elements(p_line_items)
  LOOP
    v_line_count := v_line_count + 1;
    IF jsonb_typeof(v_line) <> 'object'
       OR jsonb_typeof(v_line->'itemCode') <> 'string'
       OR jsonb_typeof(v_line->'quantity') IS DISTINCT FROM 'number' THEN
      RAISE EXCEPTION 'offer line % must contain itemCode and quantity', v_line_count
        USING ERRCODE = '22023';
    END IF;
    v_item_code := v_line->>'itemCode';
    BEGIN
      v_quantity := (v_line->>'quantity')::numeric;
    EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RAISE EXCEPTION 'offer line % quantity is invalid', v_line_count USING ERRCODE = '22023';
    END;
    IF v_item_code IS NULL OR length(btrim(v_item_code)) = 0 OR length(v_item_code) > 100
       OR v_quantity <= 0 OR v_quantity::text IN ('NaN','Infinity','-Infinity')
       OR scale(trim_scale(v_quantity)) > 3 THEN
      RAISE EXCEPTION 'offer line % item code or quantity is invalid', v_line_count USING ERRCODE = '22023';
    END IF;

    SELECT * INTO v_price_item
      FROM eogp.booking_price_items item
     WHERE item.organization_id = p_organization_id
       AND item.price_list_revision_id = p_price_list_revision_id
       AND item.item_code = v_item_code
     FOR SHARE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'offer line % refers to an item outside the selected published price list', v_line_count
        USING ERRCODE = '23503';
    END IF;
    IF v_quantity IS NULL OR v_quantity < v_price_item.quantity_min
       OR (v_price_item.quantity_max IS NOT NULL AND v_quantity > v_price_item.quantity_max) THEN
      RAISE EXCEPTION 'offer line % quantity is outside the configured price-list bounds', v_line_count
        USING ERRCODE = '22023';
    END IF;
    v_unit_amount := v_price_item.unit_amount;
    v_adjustment_label := v_price_item.label;
    v_adjustment_code := v_price_item.unit;

    v_line_total := round(v_quantity * v_unit_amount, 2);
    IF v_line_total > 999999999999.99
       OR v_subtotal + v_line_total > 999999999999.99 THEN
      RAISE EXCEPTION 'offer line total or subtotal exceeds the supported amount range'
        USING ERRCODE = '22023';
    END IF;
    v_subtotal := v_subtotal + v_line_total;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'itemCode', v_item_code,
      'label', v_adjustment_label,
      'unit', v_adjustment_code,
      'quantity', v_quantity,
      'unitAmount', v_unit_amount,
      'lineTotal', v_line_total,
      'taxCode', v_price_item.tax_code
    ));
  END LOOP;

  FOR v_line IN SELECT value FROM jsonb_array_elements(p_adjustments)
  LOOP
    v_adjustment_count := v_adjustment_count + 1;
    IF jsonb_typeof(v_line) <> 'object'
       OR jsonb_typeof(v_line->'code') <> 'string'
       OR jsonb_typeof(v_line->'label') <> 'string'
       OR jsonb_typeof(v_line->'kind') <> 'string'
       OR jsonb_typeof(v_line->'amount') IS DISTINCT FROM 'number' THEN
      RAISE EXCEPTION 'offer adjustment % is incomplete', v_adjustment_count USING ERRCODE = '22023';
    END IF;
    v_adjustment_code := btrim(v_line->>'code');
    v_adjustment_label := btrim(v_line->>'label');
    v_adjustment_kind := v_line->>'kind';
    BEGIN
      v_adjustment_amount := (v_line->>'amount')::numeric;
    EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RAISE EXCEPTION 'offer adjustment % amount is invalid', v_adjustment_count USING ERRCODE = '22023';
    END;
    IF length(v_adjustment_code) NOT BETWEEN 1 AND 80
       OR length(v_adjustment_label) NOT BETWEEN 1 AND 250
       OR v_adjustment_kind NOT IN ('fee','discount','credit')
       OR v_adjustment_amount <= 0 OR v_adjustment_amount > 999999999999.99
       OR v_adjustment_amount::text IN ('NaN','Infinity','-Infinity')
       OR scale(trim_scale(v_adjustment_amount)) > 2 THEN
      RAISE EXCEPTION 'offer adjustment % has invalid values', v_adjustment_count USING ERRCODE = '22023';
    END IF;
    IF v_adjustment_kind = 'fee' THEN
      v_subtotal := v_subtotal + v_adjustment_amount;
    ELSE
      v_subtotal := v_subtotal - v_adjustment_amount;
    END IF;
    IF v_subtotal < 0 OR v_subtotal > 999999999999.99 THEN
      RAISE EXCEPTION 'offer adjustments produce a subtotal outside the supported amount range'
        USING ERRCODE = '22023';
    END IF;
    v_adjustments := v_adjustments || jsonb_build_array(jsonb_build_object(
      'code',v_adjustment_code,'label',v_adjustment_label,
      'kind',v_adjustment_kind,'amount',v_adjustment_amount
    ));
  END LOOP;

  IF v_subtotal < 0 OR v_subtotal > 999999999999.99 THEN
    RAISE EXCEPTION 'offer subtotal is outside the supported range' USING ERRCODE = '22023';
  END IF;
  IF p_tax_basis = 'not_applicable' AND v_tax <> 0 THEN
    RAISE EXCEPTION 'tax amount must be zero when tax is not applicable' USING ERRCODE = '22023';
  END IF;
  IF p_tax_basis = 'to_be_confirmed' AND v_tax <> 0 THEN
    RAISE EXCEPTION 'tax amount must remain zero until the tax basis is confirmed' USING ERRCODE = '22023';
  END IF;
  IF v_tax > 0 THEN
    IF p_internal_reason IS NULL OR length(btrim(p_internal_reason)) < 3 THEN
      RAISE EXCEPTION 'a reason is required for a manually supplied tax amount'
        USING ERRCODE = '22023';
    END IF;
    PERFORM eogp.assert_booking_commercial_permission(
      p_organization_id,p_actor_membership_id,ARRAY['booking.approve']::text[]
    );
  END IF;
  IF p_tax_basis = 'inclusive' AND v_tax > v_subtotal THEN
    RAISE EXCEPTION 'included tax cannot exceed the offer subtotal' USING ERRCODE = '22023';
  END IF;
  IF p_tax_basis = 'exclusive' THEN
    v_total := v_subtotal + v_tax;
  ELSE
    -- For inclusive prices taxAmount is an informational component already
    -- included in the line prices and is not added to the payable total.
    v_total := v_subtotal;
  END IF;
  IF v_total > 999999999999.99 THEN
    RAISE EXCEPTION 'offer total is outside the supported range' USING ERRCODE = '22023';
  END IF;

  IF v_offer_id IS NULL THEN
    INSERT INTO eogp.booking_offers (organization_id,draft_id,status)
    VALUES (p_organization_id,v_draft_id,'prepared')
    RETURNING id INTO v_offer_id;
  ELSE
    SELECT offer.draft_id, offer.status
      INTO v_current_revision_id, v_offer_status
      FROM eogp.booking_offers offer
     WHERE offer.organization_id = p_organization_id
       AND offer.id = v_offer_id
     FOR UPDATE;
    IF NOT FOUND OR v_current_revision_id IS DISTINCT FROM v_draft_id THEN
      RAISE EXCEPTION 'booking offer not found for this draft' USING ERRCODE = 'P0002';
    END IF;
  END IF;

  SELECT revision.id, revision.revision_number, revision.state
    INTO v_previous_revision_id, v_previous_revision_number, v_previous_state
    FROM eogp.booking_offer_revisions revision
   WHERE revision.organization_id = p_organization_id
     AND revision.offer_id = v_offer_id
   ORDER BY revision.revision_number DESC
   LIMIT 1
   FOR UPDATE;

  IF FOUND THEN
    IF v_previous_state IN ('draft','issued') THEN
      IF NOT p_supersede_current THEN
        RAISE EXCEPTION 'the current prepared or issued offer must be explicitly superseded before creating a successor'
          USING ERRCODE = '55000';
      END IF;
      IF p_internal_reason IS NULL OR length(btrim(p_internal_reason)) < 3 THEN
        RAISE EXCEPTION 'a reason is required to supersede the current offer'
          USING ERRCODE = '22023';
      END IF;
      UPDATE eogp.booking_offer_revisions
         SET state = 'withdrawn'
       WHERE organization_id = p_organization_id
         AND id = v_previous_revision_id;
      INSERT INTO eogp.booking_offer_decision_history (
        organization_id,offer_id,offer_revision_id,decision,actor_kind,actor_membership_id,reason_code
      ) VALUES (
        p_organization_id,v_offer_id,v_previous_revision_id,'superseded','membership',
        p_actor_membership_id,'offer_superseded'
      );
    ELSIF v_previous_state NOT IN ('rejected','expired','withdrawn') THEN
      RAISE EXCEPTION 'an accepted offer cannot be replaced by a successor offer'
        USING ERRCODE = '55000';
    END IF;
    UPDATE eogp.booking_offers SET status='prepared'
     WHERE organization_id = p_organization_id AND id = v_offer_id;
  END IF;

  INSERT INTO eogp.booking_offer_revisions (
    id,organization_id,offer_id,revision_number,draft_revision_id,
    price_list_revision_id,cancellation_policy_revision_id,
    approval_policy_revision_id,approval_requirements_snapshot,
    terms_snapshot,currency,subtotal,tax_amount,total_amount,valid_until,state
  ) VALUES (
    v_revision_id,p_organization_id,v_offer_id,coalesce(v_previous_revision_number,0)+1,
    p_draft_revision_id,p_price_list_revision_id,p_cancellation_policy_revision_id,
    p_approval_policy_revision_id,v_approval_rules,
    jsonb_build_object(
      'draftRevisionId',p_draft_revision_id,
      'requestedStart',v_requested_start,
      'requestedEnd',v_requested_end,
      'timezone',v_timezone,
      'spaceLines',v_space_lines,
      'resourceLines',v_resource_lines,
      'currency',p_currency,
      'taxBasis',p_tax_basis,
      'lineItems',v_lines,
      'adjustments',v_adjustments,
      'subtotal',v_subtotal,
      'taxAmount',v_tax,
      'totalAmount',v_total,
      'cancellationTerms',v_policy_terms,
      'internalReason',null
    ),
    p_currency,v_subtotal,v_tax,v_total,p_valid_until,'draft'
  );

  INSERT INTO eogp.audit_events (
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.offer.prepared','booking_offer',v_offer_id,'offer_prepared',
    jsonb_build_object(
      'offerRevisionId',v_revision_id,
      'draftRevisionId',p_draft_revision_id,
      'revisionNumber',coalesce(v_previous_revision_number,0)+1,
      'currency',p_currency,
      'totalAmount',v_total,
      'lineItemCount',v_line_count,
      'adjustmentCount',v_adjustment_count
    )
  );

  RETURN jsonb_build_object(
    'offerId',v_offer_id,
    'offerRevisionId',v_revision_id,
    'draftRevisionId',p_draft_revision_id,
    'revisionNumber',coalesce(v_previous_revision_number,0)+1,
    'state','draft',
    'currency',p_currency,
    'taxBasis',p_tax_basis,
    'subtotal',v_subtotal,
    'taxAmount',v_tax,
    'totalAmount',v_total,
    'validUntil',p_valid_until
  );
END;
$function$;

CREATE FUNCTION eogp.issue_booking_offer(
  p_organization_id uuid,
  p_offer_id uuid,
  p_actor_membership_id uuid,
  p_capability_token_sha256 text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_offer eogp.booking_offers%ROWTYPE;
  v_revision eogp.booking_offer_revisions%ROWTYPE;
  v_draft_status text;
  v_current_draft_revision_number integer;
  v_offer_draft_id uuid;
  v_price_state text;
  v_price_effective_from timestamptz;
  v_price_effective_until timestamptz;
  v_approval_state text;
  v_policy_status text;
  v_capability_id uuid := gen_random_uuid();
BEGIN
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  IF p_capability_token_sha256 IS NULL OR p_capability_token_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'offer capability token fingerprint is invalid' USING ERRCODE = '22023';
  END IF;

  SELECT offer.draft_id,draft.status,draft.current_revision_number
    INTO v_offer_draft_id,v_draft_status,v_current_draft_revision_number
    FROM eogp.booking_offers offer
    JOIN eogp.booking_drafts draft
      ON draft.organization_id=offer.organization_id
     AND draft.id=offer.draft_id
   WHERE offer.organization_id=p_organization_id AND offer.id=p_offer_id
   FOR UPDATE OF draft;
  IF NOT FOUND OR v_draft_status <> 'draft' THEN
    RAISE EXCEPTION 'offer draft is no longer editable' USING ERRCODE = '55000';
  END IF;

  SELECT * INTO v_offer
    FROM eogp.booking_offers
   WHERE organization_id=p_organization_id AND id=p_offer_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking offer not found' USING ERRCODE = 'P0002';
  END IF;
  SELECT * INTO v_revision
    FROM eogp.booking_offer_revisions
   WHERE organization_id=p_organization_id AND offer_id=p_offer_id
   ORDER BY revision_number DESC
   LIMIT 1
   FOR UPDATE;
  IF NOT FOUND OR v_revision.state <> 'draft' THEN
    RAISE EXCEPTION 'only the latest prepared offer revision can be issued'
      USING ERRCODE = '55000';
  END IF;
  IF v_revision.valid_until IS NULL OR v_revision.valid_until <= clock_timestamp() THEN
    RAISE EXCEPTION 'offer validity deadline must be in the future'
      USING ERRCODE = '22023';
  END IF;
  IF v_revision.terms_snapshot->>'taxBasis' = 'to_be_confirmed' THEN
    RAISE EXCEPTION 'tax basis must be confirmed before issuing a customer offer'
      USING ERRCODE = '55000';
  END IF;
  IF v_revision.approval_policy_revision_id IS NULL THEN
    RAISE EXCEPTION 'a published approval policy revision must be selected before issuing an offer'
      USING ERRCODE = '55000';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM eogp.booking_draft_revisions dr
     WHERE dr.organization_id=p_organization_id
       AND dr.id=v_revision.draft_revision_id
       AND dr.draft_id=v_offer.draft_id
       AND dr.revision_number=v_current_draft_revision_number
  ) THEN
    RAISE EXCEPTION 'offer is based on a stale draft revision' USING ERRCODE = '40001';
  END IF;

  SELECT revision.state,revision.effective_from,revision.effective_until
    INTO v_price_state,v_price_effective_from,v_price_effective_until
    FROM eogp.booking_price_list_revisions revision
   WHERE revision.organization_id=p_organization_id
     AND revision.id=v_revision.price_list_revision_id
   FOR SHARE;
  IF NOT FOUND OR v_price_state <> 'published'
     OR (v_price_effective_from IS NOT NULL AND v_price_effective_from > clock_timestamp())
     OR (v_price_effective_until IS NOT NULL AND v_price_effective_until <= v_revision.valid_until) THEN
    RAISE EXCEPTION 'the pinned price-list revision is no longer effective for the offer period'
      USING ERRCODE = '55000';
  END IF;

  SELECT policy_revision.state,policy.status
    INTO v_approval_state,v_policy_status
    FROM eogp.booking_approval_policy_revisions policy_revision
    JOIN eogp.booking_approval_policies policy
      ON policy.organization_id=policy_revision.organization_id
     AND policy.id=policy_revision.policy_id
   WHERE policy_revision.organization_id=p_organization_id
     AND policy_revision.id=v_revision.approval_policy_revision_id
   FOR SHARE OF policy_revision,policy;
  IF NOT FOUND OR v_approval_state <> 'published' OR v_policy_status <> 'active' THEN
    RAISE EXCEPTION 'the pinned approval policy is no longer published and active'
      USING ERRCODE = '55000';
  END IF;

  INSERT INTO eogp.external_action_capabilities (
    id,organization_id,offer_revision_id,action_code,token_sha256,
    expires_at,max_uses,created_by_membership_id
  ) VALUES (
    v_capability_id,p_organization_id,v_revision.id,'offer_accept',
    p_capability_token_sha256,v_revision.valid_until,1,p_actor_membership_id
  );

  UPDATE eogp.booking_offer_revisions
     SET state='issued',issued_at=clock_timestamp()
   WHERE organization_id=p_organization_id AND id=v_revision.id;
  UPDATE eogp.booking_offers SET status='issued'
   WHERE organization_id=p_organization_id AND id=p_offer_id;

  INSERT INTO eogp.audit_events (
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.offer.issued','booking_offer',p_offer_id,'offer_issued',
    jsonb_build_object(
      'offerRevisionId',v_revision.id,
      'revisionNumber',v_revision.revision_number,
      'validUntil',v_revision.valid_until,
      'externalCapabilityId',v_capability_id
    )
  );

  RETURN jsonb_build_object(
    'offerId',p_offer_id,
    'offerRevisionId',v_revision.id,
    'revisionNumber',v_revision.revision_number,
    'state','issued',
    'validUntil',v_revision.valid_until,
    'capabilityId',v_capability_id
  );
END;
$function$;

CREATE FUNCTION eogp.get_booking_offer(
  p_organization_id uuid,
  p_offer_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
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
    'draftId',offer.draft_id,
    'status',offer.status,
    'createdAt',offer.created_at,
    'currentRevision',(
      SELECT jsonb_build_object(
        'offerRevisionId',revision.id,
        'revisionNumber',revision.revision_number,
        'draftRevisionId',revision.draft_revision_id,
        'priceListRevisionId',revision.price_list_revision_id,
        'cancellationPolicyRevisionId',revision.cancellation_policy_revision_id,
        'approvalPolicyRevisionId',revision.approval_policy_revision_id,
        'approvalRequirements',revision.approval_requirements_snapshot,
        'currency',revision.currency,
        'subtotal',revision.subtotal,
        'taxAmount',revision.tax_amount,
        'totalAmount',revision.total_amount,
        'validUntil',revision.valid_until,
        'state',revision.state,
        'issuedAt',revision.issued_at,
        'acceptedAt',revision.accepted_at,
        'terms',revision.terms_snapshot
      )
        FROM eogp.booking_offer_revisions revision
       WHERE revision.organization_id=offer.organization_id
         AND revision.offer_id=offer.id
       ORDER BY revision.revision_number DESC
       LIMIT 1
    ),
    'revisionHistory',(
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'offerRevisionId',revision.id,
        'revisionNumber',revision.revision_number,
        'draftRevisionId',revision.draft_revision_id,
        'state',revision.state,
        'createdAt',revision.created_at,
        'issuedAt',revision.issued_at,
        'acceptedAt',revision.accepted_at
      ) ORDER BY revision.revision_number DESC),'[]'::jsonb)
        FROM eogp.booking_offer_revisions revision
       WHERE revision.organization_id=offer.organization_id
         AND revision.offer_id=offer.id
    ),
    'decisionHistory',(
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'decision',history.decision,
        'actorKind',history.actor_kind,
        'actorMembershipId',history.actor_membership_id,
        'reasonCode',history.reason_code,
        'occurredAt',history.occurred_at
      ) ORDER BY history.occurred_at,history.id),'[]'::jsonb)
        FROM eogp.booking_offer_decision_history history
       WHERE history.organization_id=offer.organization_id
         AND history.offer_id=offer.id
    )
  ) INTO v_result
    FROM eogp.booking_offers offer
   WHERE offer.organization_id=p_organization_id AND offer.id=p_offer_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking offer not found' USING ERRCODE = 'P0002';
  END IF;
  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.save_booking_offer_revision(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,jsonb,jsonb,numeric,text,boolean)
  FROM PUBLIC,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.issue_booking_offer(uuid,uuid,uuid,text)
  FROM PUBLIC,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.get_booking_offer(uuid,uuid,uuid)
  FROM PUBLIC,eventor_worker,eventor_auth;

GRANT EXECUTE ON FUNCTION eogp.save_booking_offer_revision(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,jsonb,jsonb,numeric,text,boolean),
  eogp.issue_booking_offer(uuid,uuid,uuid,text),
  eogp.get_booking_offer(uuid,uuid,uuid)
  TO eventor_runtime;

     OR p_tax_basis IS NULL OR p_tax_basis NOT IN ('inclusive','exclusive','not_applicable','to_be_confirmed')
     OR p_valid_until IS NULL OR p_valid_until <= clock_timestamp()
     OR p_tax_amount IS NULL OR p_tax_amount < 0
     OR p_tax_amount::text IN ('NaN','Infinity','-Infinity')
     OR scale(trim_scale(p_tax_amount)) > 2 THEN
    RAISE EXCEPTION 'offer currency, tax basis, validity or tax amount is invalid'
      USING ERRCODE = '22023';
  END IF;
  IF p_line_items IS NULL OR jsonb_typeof(p_line_items) <> 'array'
     OR jsonb_array_length(p_line_items) > 100
     OR p_adjustments IS NULL OR jsonb_typeof(p_adjustments) <> 'array'
     OR jsonb_array_length(p_adjustments) > 50 THEN
    RAISE EXCEPTION 'offer line items and adjustments must be bounded JSON arrays'
      USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_line_items) = 0 AND jsonb_array_length(p_adjustments) = 0 THEN
    RAISE EXCEPTION 'an offer must contain at least one priced item or adjustment'
      USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_adjustments) > 0
     AND (p_internal_reason IS NULL OR length(btrim(p_internal_reason)) < 3) THEN
    RAISE EXCEPTION 'a reason is required when manual price adjustments are included'
      USING ERRCODE = '22023';
  END IF;

  SELECT draft.id, draft.status, draft.current_revision_number,
         revision.id, revision.requested_start, revision.requested_end,
         revision.timezone_name
    INTO v_draft_id, v_draft_status, v_revision_number,
         v_current_revision_id, v_requested_start, v_requested_end, v_timezone
    FROM eogp.booking_draft_revisions revision
    JOIN eogp.booking_drafts draft
      ON draft.organization_id = revision.organization_id
     AND draft.id = revision.draft_id
   WHERE revision.organization_id = p_organization_id
     AND revision.id = p_draft_revision_id
   FOR UPDATE OF draft;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking draft revision not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_draft_status <> 'draft' OR v_current_revision_id IS DISTINCT FROM p_draft_revision_id THEN
    RAISE EXCEPTION 'offers can be prepared only from the current revision of an editable draft'
      USING ERRCODE = '55000';
  END IF;

  SELECT revision.currency, revision.tax_basis, revision.effective_from, revision.effective_until
    INTO v_currency, v_tax_basis, v_effective_from, v_effective_until
    FROM eogp.booking_price_list_revisions revision
   WHERE revision.organization_id = p_organization_id
     AND revision.id = p_price_list_revision_id
     AND revision.state = 'published'
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'published price-list revision not found' USING ERRCODE = '23503';
  END IF;
  IF v_currency <> p_currency OR v_tax_basis <> p_tax_basis THEN
    RAISE EXCEPTION 'offer currency and tax basis must match the selected price-list revision'
      USING ERRCODE = '22023';
  END IF;
  IF (v_effective_from IS NOT NULL AND v_effective_from > clock_timestamp())
     OR (v_effective_until IS NOT NULL AND v_effective_until <= p_valid_until) THEN
    RAISE EXCEPTION 'price-list revision must remain effective through the offer validity period'
      USING ERRCODE = '55000';
  END IF;

  SELECT policy_revision.public_terms
    INTO v_policy_terms
    FROM eogp.cancellation_policy_revisions policy_revision
    JOIN eogp.cancellation_policies policy
      ON policy.organization_id = policy_revision.organization_id
     AND policy.id = policy_revision.cancellation_policy_id
   WHERE policy_revision.organization_id = p_organization_id
     AND policy_revision.id = p_cancellation_policy_revision_id
     AND policy_revision.state = 'published'
     AND policy.status = 'active'
   FOR SHARE OF policy_revision, policy;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'published active cancellation-policy revision not found' USING ERRCODE = '23503';
  END IF;

  IF p_approval_policy_revision_id IS NOT NULL THEN
    SELECT policy_revision.rules INTO v_approval_rules
      FROM eogp.booking_approval_policy_revisions policy_revision
      JOIN eogp.booking_approval_policies policy
        ON policy.organization_id = policy_revision.organization_id
       AND policy.id = policy_revision.policy_id
     WHERE policy_revision.organization_id = p_organization_id
       AND policy_revision.id = p_approval_policy_revision_id
       AND policy_revision.state = 'published'
       AND policy.status = 'active'
     FOR SHARE OF policy_revision, policy;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'published active approval-policy revision not found' USING ERRCODE = '23503';
    END IF;
  END IF;

  FOR v_line IN SELECT value FROM jsonb_array_elements(p_line_items)
  LOOP
    v_line_count := v_line_count + 1;
    IF jsonb_typeof(v_line) <> 'object'
       OR jsonb_typeof(v_line->'itemCode') <> 'string'
       OR jsonb_typeof(v_line->'quantity') NOT IN ('number','string') THEN
      RAISE EXCEPTION 'offer line % must contain itemCode and quantity', v_line_count
        USING ERRCODE = '22023';
    END IF;
    v_item_code := v_line->>'itemCode';
    BEGIN
      v_quantity := (v_line->>'quantity')::numeric;
    EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RAISE EXCEPTION 'offer line % quantity is invalid', v_line_count USING ERRCODE = '22023';
    END;
    IF v_item_code IS NULL OR length(btrim(v_item_code)) = 0 OR length(v_item_code) > 100
       OR v_quantity <= 0 OR v_quantity::text IN ('NaN','Infinity','-Infinity')
       OR scale(trim_scale(v_quantity)) > 3 THEN
      RAISE EXCEPTION 'offer line % item code or quantity is invalid', v_line_count USING ERRCODE = '22023';
    END IF;

    SELECT item.unit_amount, item.quantity_min, item.quantity_max, item.label, item.unit
      INTO v_unit_amount, v_line_total, v_adjustment_amount, v_adjustment_label, v_adjustment_code
      FROM eogp.booking_price_items item
     WHERE item.organization_id = p_organization_id
       AND item.price_list_revision_id = p_price_list_revision_id
       AND item.item_code = v_item_code
     FOR SHARE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'offer line % refers to an item outside the selected published price list', v_line_count
        USING ERRCODE = '23503';
    END IF;
    IF v_quantity < v_line_total OR (v_adjustment_amount IS NOT NULL AND v_quantity > v_adjustment_amount) THEN
      RAISE EXCEPTION 'offer line % quantity is outside the configured price-list bounds', v_line_count
        USING ERRCODE = '22023';
    END IF;

    v_line_total := round(v_quantity * v_unit_amount, 2);
    v_subtotal := v_subtotal + v_line_total;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'itemCode', v_item_code,
      'label', v_adjustment_label,
      'unit', v_adjustment_code,
      'quantity', v_quantity,
      'unitAmount', v_unit_amount,
      'lineTotal', v_line_total,
      'taxCode', (SELECT item.tax_code FROM eogp.booking_price_items item
                   WHERE item.organization_id = p_organization_id
                     AND item.price_list_revision_id = p_price_list_revision_id
                     AND item.item_code = v_item_code)
    ));
  END LOOP;

  FOR v_line IN SELECT value FROM jsonb_array_elements(p_adjustments)
  LOOP
    v_adjustment_count := v_adjustment_count + 1;
    IF jsonb_typeof(v_line) <> 'object'
       OR jsonb_typeof(v_line->'code') <> 'string'
       OR jsonb_typeof(v_line->'label') <> 'string'
       OR jsonb_typeof(v_line->'kind') <> 'string'
       OR jsonb_typeof(v_line->'amount') NOT IN ('number','string') THEN
      RAISE EXCEPTION 'offer adjustment % is incomplete', v_adjustment_count USING ERRCODE = '22023';
    END IF;
    v_adjustment_code := btrim(v_line->>'code');
    v_adjustment_label := btrim(v_line->>'label');
    v_adjustment_kind := v_line->>'kind';
    BEGIN
      v_adjustment_amount := (v_line->>'amount')::numeric;
    EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RAISE EXCEPTION 'offer adjustment % amount is invalid', v_adjustment_count USING ERRCODE = '22023';
    END;
    IF length(v_adjustment_code) NOT BETWEEN 1 AND 80
       OR length(v_adjustment_label) NOT BETWEEN 1 AND 250
       OR v_adjustment_kind NOT IN ('fee','discount','credit')
       OR v_adjustment_amount <= 0 OR v_adjustment_amount::text IN ('NaN','Infinity','-Infinity')
       OR scale(trim_scale(v_adjustment_amount)) > 2 THEN
      RAISE EXCEPTION 'offer adjustment % has invalid values', v_adjustment_count USING ERRCODE = '22023';
    END IF;
    IF v_adjustment_kind = 'fee' THEN
      v_subtotal := v_subtotal + v_adjustment_amount;
    ELSE
      v_subtotal := v_subtotal - v_adjustment_amount;
    END IF;
    v_adjustments := v_adjustments || jsonb_build_array(jsonb_build_object(
      'code',v_adjustment_code,'label',v_adjustment_label,
      'kind',v_adjustment_kind,'amount',v_adjustment_amount
    ));
  END LOOP;

  IF v_subtotal < 0 OR v_subtotal > 99999999999999.99 THEN
    RAISE EXCEPTION 'offer subtotal is outside the supported range' USING ERRCODE = '22023';
  END IF;
  IF p_tax_basis = 'not_applicable' AND v_tax <> 0 THEN
    RAISE EXCEPTION 'tax amount must be zero when tax is not applicable' USING ERRCODE = '22023';
  END IF;
  IF p_tax_basis = 'to_be_confirmed' AND v_tax <> 0 THEN
    RAISE EXCEPTION 'tax amount must remain zero until the tax basis is confirmed' USING ERRCODE = '22023';
  END IF;
  IF p_tax_basis = 'exclusive' THEN
    v_total := v_subtotal + v_tax;
  ELSE
    -- For inclusive prices taxAmount is an informational component already
    -- included in the line prices and is not added to the payable total.
    v_total := v_subtotal;
  END IF;

  IF v_offer_id IS NULL THEN
    INSERT INTO eogp.booking_offers (organization_id,draft_id,status)
    VALUES (p_organization_id,v_draft_id,'prepared')
    RETURNING id INTO v_offer_id;
  ELSE
    SELECT offer.draft_id, offer.status
      INTO v_current_revision_id, v_offer_status
      FROM eogp.booking_offers offer
     WHERE offer.organization_id = p_organization_id
       AND offer.id = v_offer_id
     FOR UPDATE;
    IF NOT FOUND OR v_current_revision_id IS DISTINCT FROM v_draft_id THEN
      RAISE EXCEPTION 'booking offer not found for this draft' USING ERRCODE = 'P0002';
    END IF;
  END IF;

  SELECT revision.id, revision.revision_number, revision.state
    INTO v_previous_revision_id, v_previous_revision_number, v_previous_state
    FROM eogp.booking_offer_revisions revision
   WHERE revision.organization_id = p_organization_id
     AND revision.offer_id = v_offer_id
   ORDER BY revision.revision_number DESC
   LIMIT 1
   FOR UPDATE;

  IF FOUND THEN
    IF v_previous_state = 'draft' THEN
      RAISE EXCEPTION 'the prepared offer revision must be issued or explicitly withdrawn before creating a successor'
        USING ERRCODE = '55000';
    ELSIF v_previous_state = 'issued' THEN
      IF NOT p_supersede_current THEN
        RAISE EXCEPTION 'an issued offer must be explicitly superseded before creating a successor'
          USING ERRCODE = '55000';
      END IF;
      IF p_internal_reason IS NULL OR length(btrim(p_internal_reason)) < 3 THEN
        RAISE EXCEPTION 'a reason is required to supersede an issued offer'
          USING ERRCODE = '22023';
      END IF;
      UPDATE eogp.booking_offer_revisions
         SET state = 'withdrawn'
       WHERE organization_id = p_organization_id
         AND id = v_previous_revision_id;
      INSERT INTO eogp.booking_offer_decision_history (
        organization_id,offer_id,offer_revision_id,decision,actor_kind,actor_membership_id,reason_code
      ) VALUES (
        p_organization_id,v_offer_id,v_previous_revision_id,'superseded','membership',
        p_actor_membership_id,'offer_superseded'
      );
    ELSIF v_previous_state NOT IN ('rejected','expired','withdrawn') THEN
      RAISE EXCEPTION 'an accepted offer cannot be replaced by a successor offer'
        USING ERRCODE = '55000';
    END IF;
    UPDATE eogp.booking_offers SET status='prepared'
     WHERE organization_id = p_organization_id AND id = v_offer_id;
  END IF;

  INSERT INTO eogp.booking_offer_revisions (
    id,organization_id,offer_id,revision_number,draft_revision_id,
    price_list_revision_id,cancellation_policy_revision_id,
    approval_policy_revision_id,approval_requirements_snapshot,
    terms_snapshot,currency,subtotal,tax_amount,total_amount,valid_until,state
  ) VALUES (
    v_revision_id,p_organization_id,v_offer_id,coalesce(v_previous_revision_number,0)+1,
    p_draft_revision_id,p_price_list_revision_id,p_cancellation_policy_revision_id,
    p_approval_policy_revision_id,v_approval_rules,
    jsonb_build_object(
      'draftRevisionId',p_draft_revision_id,
      'requestedStart',v_requested_start,
      'requestedEnd',v_requested_end,
      'timezone',v_timezone,
      'currency',p_currency,
      'taxBasis',p_tax_basis,
      'lineItems',v_lines,
      'adjustments',v_adjustments,
      'subtotal',v_subtotal,
      'taxAmount',v_tax,
      'totalAmount',v_total,
      'cancellationTerms',v_policy_terms,
      'internalReason',null
    ),
    p_currency,v_subtotal,v_tax,v_total,p_valid_until,'draft'
  );

  INSERT INTO eogp.audit_events (
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.offer.prepared','booking_offer',v_offer_id,'offer_prepared',
    jsonb_build_object(
      'offerRevisionId',v_revision_id,
      'draftRevisionId',p_draft_revision_id,
      'revisionNumber',coalesce(v_previous_revision_number,0)+1,
      'currency',p_currency,
      'totalAmount',v_total,
      'lineItemCount',v_line_count,
      'adjustmentCount',v_adjustment_count
    )
  );

  RETURN jsonb_build_object(
    'offerId',v_offer_id,
    'offerRevisionId',v_revision_id,
    'draftRevisionId',p_draft_revision_id,
    'revisionNumber',coalesce(v_previous_revision_number,0)+1,
    'state','draft',
    'currency',p_currency,
    'taxBasis',p_tax_basis,
    'subtotal',v_subtotal,
    'taxAmount',v_tax,
    'totalAmount',v_total,
    'validUntil',p_valid_until
  );
END;
$function$;

CREATE FUNCTION eogp.issue_booking_offer(
  p_organization_id uuid,
  p_offer_id uuid,
  p_actor_membership_id uuid,
  p_capability_token_sha256 text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_offer eogp.booking_offers%ROWTYPE;
  v_revision eogp.booking_offer_revisions%ROWTYPE;
  v_draft_status text;
  v_current_draft_revision_number integer;
  v_price_state text;
  v_price_effective_from timestamptz;
  v_price_effective_until timestamptz;
  v_approval_state text;
  v_policy_status text;
  v_capability_id uuid := gen_random_uuid();
BEGIN
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  IF p_capability_token_sha256 IS NULL OR p_capability_token_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'offer capability token fingerprint is invalid' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_offer
    FROM eogp.booking_offers
   WHERE organization_id=p_organization_id AND id=p_offer_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking offer not found' USING ERRCODE = 'P0002';
  END IF;
  SELECT * INTO v_revision
    FROM eogp.booking_offer_revisions
   WHERE organization_id=p_organization_id AND offer_id=p_offer_id
   ORDER BY revision_number DESC
   LIMIT 1
   FOR UPDATE;
  IF NOT FOUND OR v_revision.state <> 'draft' THEN
    RAISE EXCEPTION 'only the latest prepared offer revision can be issued'
      USING ERRCODE = '55000';
  END IF;
  IF v_revision.valid_until IS NULL OR v_revision.valid_until <= clock_timestamp() THEN
    RAISE EXCEPTION 'offer validity deadline must be in the future'
      USING ERRCODE = '22023';
  END IF;
  IF v_revision.terms_snapshot->>'taxBasis' = 'to_be_confirmed' THEN
    RAISE EXCEPTION 'tax basis must be confirmed before issuing a customer offer'
      USING ERRCODE = '55000';
  END IF;
  IF v_revision.approval_policy_revision_id IS NULL THEN
    RAISE EXCEPTION 'a published approval policy revision must be selected before issuing an offer'
      USING ERRCODE = '55000';
  END IF;

  SELECT draft.status,draft.current_revision_number
    INTO v_draft_status,v_current_draft_revision_number
    FROM eogp.booking_drafts draft
   WHERE draft.organization_id=p_organization_id AND draft.id=v_offer.draft_id
   FOR UPDATE;
  IF NOT FOUND OR v_draft_status <> 'draft' THEN
    RAISE EXCEPTION 'offer draft is no longer editable' USING ERRCODE = '55000';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM eogp.booking_draft_revisions dr
     WHERE dr.organization_id=p_organization_id
       AND dr.id=v_revision.draft_revision_id
       AND dr.draft_id=v_offer.draft_id
       AND dr.revision_number=v_current_draft_revision_number
  ) THEN
    RAISE EXCEPTION 'offer is based on a stale draft revision' USING ERRCODE = '40001';
  END IF;

  SELECT revision.state,revision.effective_from,revision.effective_until
    INTO v_price_state,v_price_effective_from,v_price_effective_until
    FROM eogp.booking_price_list_revisions revision
   WHERE revision.organization_id=p_organization_id
     AND revision.id=v_revision.price_list_revision_id
   FOR SHARE;
  IF NOT FOUND OR v_price_state <> 'published'
     OR (v_price_effective_from IS NOT NULL AND v_price_effective_from > clock_timestamp())
     OR (v_price_effective_until IS NOT NULL AND v_price_effective_until <= v_revision.valid_until) THEN
    RAISE EXCEPTION 'the pinned price-list revision is no longer effective for the offer period'
      USING ERRCODE = '55000';
  END IF;

  SELECT policy_revision.state,policy.status
    INTO v_approval_state,v_policy_status
    FROM eogp.booking_approval_policy_revisions policy_revision
    JOIN eogp.booking_approval_policies policy
      ON policy.organization_id=policy_revision.organization_id
     AND policy.id=policy_revision.policy_id
   WHERE policy_revision.organization_id=p_organization_id
     AND policy_revision.id=v_revision.approval_policy_revision_id
   FOR SHARE OF policy_revision,policy;
  IF NOT FOUND OR v_approval_state <> 'published' OR v_policy_status <> 'active' THEN
    RAISE EXCEPTION 'the pinned approval policy is no longer published and active'
      USING ERRCODE = '55000';
  END IF;

  INSERT INTO eogp.external_action_capabilities (
    id,organization_id,offer_revision_id,action_code,token_sha256,
    expires_at,max_uses,created_by_membership_id
  ) VALUES (
    v_capability_id,p_organization_id,v_revision.id,'offer_accept',
    p_capability_token_sha256,v_revision.valid_until,1,p_actor_membership_id
  );

  UPDATE eogp.booking_offer_revisions
     SET state='issued',issued_at=clock_timestamp()
   WHERE organization_id=p_organization_id AND id=v_revision.id;
  UPDATE eogp.booking_offers SET status='issued'
   WHERE organization_id=p_organization_id AND id=p_offer_id;

  INSERT INTO eogp.audit_events (
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.offer.issued','booking_offer',p_offer_id,'offer_issued',
    jsonb_build_object(
      'offerRevisionId',v_revision.id,
      'revisionNumber',v_revision.revision_number,
      'validUntil',v_revision.valid_until,
      'externalCapabilityId',v_capability_id
    )
  );

  RETURN jsonb_build_object(
    'offerId',p_offer_id,
    'offerRevisionId',v_revision.id,
    'revisionNumber',v_revision.revision_number,
    'state','issued',
    'validUntil',v_revision.valid_until,
    'capabilityId',v_capability_id
  );
END;
$function$;

CREATE FUNCTION eogp.get_booking_offer(
  p_organization_id uuid,
  p_offer_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
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
    'draftId',offer.draft_id,
    'status',offer.status,
    'createdAt',offer.created_at,
    'currentRevision',(
      SELECT jsonb_build_object(
        'offerRevisionId',revision.id,
        'revisionNumber',revision.revision_number,
        'draftRevisionId',revision.draft_revision_id,
        'priceListRevisionId',revision.price_list_revision_id,
        'cancellationPolicyRevisionId',revision.cancellation_policy_revision_id,
        'approvalPolicyRevisionId',revision.approval_policy_revision_id,
        'approvalRequirements',revision.approval_requirements_snapshot,
        'currency',revision.currency,
        'subtotal',revision.subtotal,
        'taxAmount',revision.tax_amount,
        'totalAmount',revision.total_amount,
        'validUntil',revision.valid_until,
        'state',revision.state,
        'issuedAt',revision.issued_at,
        'acceptedAt',revision.accepted_at,
        'terms',revision.terms_snapshot
      )
        FROM eogp.booking_offer_revisions revision
       WHERE revision.organization_id=offer.organization_id
         AND revision.offer_id=offer.id
       ORDER BY revision.revision_number DESC
       LIMIT 1
    ),
    'revisionHistory',(
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'offerRevisionId',revision.id,
        'revisionNumber',revision.revision_number,
        'draftRevisionId',revision.draft_revision_id,
        'state',revision.state,
        'createdAt',revision.created_at,
        'issuedAt',revision.issued_at,
        'acceptedAt',revision.accepted_at
      ) ORDER BY revision.revision_number DESC),'[]'::jsonb)
        FROM eogp.booking_offer_revisions revision
       WHERE revision.organization_id=offer.organization_id
         AND revision.offer_id=offer.id
    ),
    'decisionHistory',(
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'decision',history.decision,
        'actorKind',history.actor_kind,
        'actorMembershipId',history.actor_membership_id,
        'reasonCode',history.reason_code,
        'occurredAt',history.occurred_at
      ) ORDER BY history.occurred_at,history.id),'[]'::jsonb)
        FROM eogp.booking_offer_decision_history history
       WHERE history.organization_id=offer.organization_id
         AND history.offer_id=offer.id
    )
  ) INTO v_result
    FROM eogp.booking_offers offer
   WHERE offer.organization_id=p_organization_id AND offer.id=p_offer_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking offer not found' USING ERRCODE = 'P0002';
  END IF;
  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.save_booking_offer_revision(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,jsonb,jsonb,numeric,text,boolean)
  FROM PUBLIC,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.issue_booking_offer(uuid,uuid,uuid,text)
  FROM PUBLIC,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.get_booking_offer(uuid,uuid,uuid)
  FROM PUBLIC,eventor_worker,eventor_auth;

GRANT EXECUTE ON FUNCTION eogp.save_booking_offer_revision(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,jsonb,jsonb,numeric,text,boolean),
  eogp.issue_booking_offer(uuid,uuid,uuid,text),
  eogp.get_booking_offer(uuid,uuid,uuid)
  TO eventor_runtime;
