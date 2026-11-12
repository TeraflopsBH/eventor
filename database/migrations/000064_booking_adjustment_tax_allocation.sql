-- Explicit tax classification and deterministic allocation for every manual offer adjustment.
-- This remains jurisdiction-neutral: organizations select tax codes from their pinned profile.

CREATE FUNCTION eogp.allocate_booking_offer_adjustment_tax(
  p_organization_id uuid,
  p_price_list_revision_id uuid,
  p_line_items jsonb,
  p_adjustments jsonb,
  p_tax_basis text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_profile_revision_id uuid;
  v_profile_basis text;
  v_adjustment jsonb;
  v_code text;
  v_method text;
  v_kind text;
  v_amount numeric;
  v_signed_amount numeric;
  v_line record;
  v_total_base numeric;
  v_allocated numeric;
  v_share numeric;
  v_index integer;
  v_count integer;
  v_tax_lines jsonb:='[]'::jsonb;
  v_adjustments jsonb:='[]'::jsonb;
  v_allocations jsonb;
  v_adjustment_count integer:=0;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;

  SELECT revision.tax_profile_revision_id
    INTO v_profile_revision_id
    FROM eogp.booking_price_list_revisions revision
   WHERE revision.organization_id=p_organization_id
     AND revision.id=p_price_list_revision_id
     AND revision.state='published'
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'published price-list revision not found' USING ERRCODE='23503';
  END IF;
  -- Compatibility path: a price list without a tax profile retains the explicit
  -- invoice-level tax workflow and its historical adjustment payload.
  IF v_profile_revision_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT revision.tax_basis INTO v_profile_basis
    FROM eogp.booking_tax_profile_revisions revision
   WHERE revision.organization_id=p_organization_id
     AND revision.id=v_profile_revision_id
     AND revision.state='published'
   FOR SHARE;
  IF NOT FOUND OR v_profile_basis IS DISTINCT FROM p_tax_basis THEN
    RAISE EXCEPTION 'the pinned tax profile does not match the offer tax basis' USING ERRCODE='55000';
  END IF;

  IF jsonb_typeof(p_line_items)<>'array' OR jsonb_typeof(p_adjustments)<>'array' THEN
    RAISE EXCEPTION 'offer lines and adjustments must be JSON arrays' USING ERRCODE='22023';
  END IF;

  FOR v_adjustment IN SELECT value FROM jsonb_array_elements(p_adjustments) LOOP
    v_adjustment_count:=v_adjustment_count+1;
    v_kind:=v_adjustment->>'kind';
    v_method:=v_adjustment->>'allocationMethod';
    v_code:=nullif(btrim(v_adjustment->>'taxCode'),'');
    BEGIN
      v_amount:=(v_adjustment->>'amount')::numeric;
    EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN
      RAISE EXCEPTION 'adjustment % amount is invalid',v_adjustment_count USING ERRCODE='22023';
    END;
    IF v_amount IS NULL OR v_amount<=0 OR v_amount::text IN ('NaN','Infinity','-Infinity') THEN
      RAISE EXCEPTION 'adjustment % amount must be positive',v_adjustment_count USING ERRCODE='22023';
    END IF;

    v_allocations:='[]'::jsonb;
    IF v_profile_basis='not_applicable' THEN
      IF v_method IS DISTINCT FROM 'not_applicable' OR v_code IS NOT NULL THEN
        RAISE EXCEPTION 'adjustment % must explicitly use not_applicable allocation for this profile',v_adjustment_count
          USING ERRCODE='22023';
      END IF;
    ELSIF v_method='tax_code' THEN
      IF v_code IS NULL THEN
        RAISE EXCEPTION 'adjustment % requires a taxCode for tax_code allocation',v_adjustment_count
          USING ERRCODE='22023';
      END IF;
      v_signed_amount:=CASE WHEN v_kind='fee' THEN v_amount ELSE -v_amount END;
      v_tax_lines:=v_tax_lines||jsonb_build_array(jsonb_build_object(
        'itemCode','adjustment:'||(v_adjustment->>'code'),
        'lineTotal',v_signed_amount,'taxCode',v_code
      ));
      v_allocations:=jsonb_build_array(jsonb_build_object(
        'taxCode',v_code,'amount',v_signed_amount
      ));
    ELSIF v_method='proportional_to_lines' THEN
      IF v_code IS NOT NULL THEN
        RAISE EXCEPTION 'adjustment % must omit taxCode when using proportional_to_lines',v_adjustment_count
          USING ERRCODE='22023';
      END IF;
      SELECT coalesce(sum((line->>'lineTotal')::numeric),0)
        INTO v_total_base
        FROM jsonb_array_elements(p_line_items) AS source(line)
       WHERE nullif(line->>'taxCode','') IS NOT NULL
         AND (line->>'lineTotal')::numeric>0;
      SELECT count(*) INTO v_count
        FROM (
          SELECT line->>'taxCode'
            FROM jsonb_array_elements(p_line_items) AS source(line)
           WHERE nullif(line->>'taxCode','') IS NOT NULL
             AND (line->>'lineTotal')::numeric>0
           GROUP BY line->>'taxCode'
        ) codes;
      IF v_total_base<=0 OR v_count=0 THEN
        RAISE EXCEPTION 'adjustment % cannot be allocated proportionally without positively priced, classified lines',v_adjustment_count
          USING ERRCODE='22023';
      END IF;
      v_signed_amount:=CASE WHEN v_kind='fee' THEN v_amount ELSE -v_amount END;
      v_allocated:=0;
      v_index:=0;
      FOR v_line IN
        SELECT line->>'taxCode' AS tax_code,sum((line->>'lineTotal')::numeric) AS base_amount
          FROM jsonb_array_elements(p_line_items) AS source(line)
         WHERE nullif(line->>'taxCode','') IS NOT NULL
           AND (line->>'lineTotal')::numeric>0
         GROUP BY line->>'taxCode'
         ORDER BY line->>'taxCode'
      LOOP
        v_index:=v_index+1;
        IF v_index=v_count THEN
          v_share:=v_signed_amount-v_allocated;
        ELSE
          v_share:=round(v_signed_amount*v_line.base_amount/v_total_base,2);
          v_allocated:=v_allocated+v_share;
        END IF;
        v_tax_lines:=v_tax_lines||jsonb_build_array(jsonb_build_object(
          'itemCode','adjustment:'||(v_adjustment->>'code')||':'||v_line.tax_code,
          'lineTotal',v_share,'taxCode',v_line.tax_code
        ));
        v_allocations:=v_allocations||jsonb_build_array(jsonb_build_object(
          'taxCode',v_line.tax_code,'sourceBase',v_line.base_amount,'amount',v_share
        ));
      END LOOP;
    ELSE
      RAISE EXCEPTION 'adjustment % requires allocationMethod tax_code or proportional_to_lines',v_adjustment_count
        USING ERRCODE='22023';
    END IF;

    v_adjustments:=v_adjustments||jsonb_build_array(
      (v_adjustment-'taxCode'-'allocationMethod')||
      jsonb_build_object(
        'taxCode',v_code,
        'allocationMethod',v_method,
        'taxAllocations',v_allocations
      )
    );
  END LOOP;

  IF EXISTS (
    SELECT 1
      FROM jsonb_array_elements(p_line_items||v_tax_lines) AS source(line)
     WHERE nullif(line->>'taxCode','') IS NOT NULL
     GROUP BY line->>'taxCode'
    HAVING sum((line->>'lineTotal')::numeric)<0
  ) THEN
    RAISE EXCEPTION 'discounts and credits cannot reduce a tax-code base below zero' USING ERRCODE='22023';
  END IF;

  RETURN jsonb_build_object('taxLines',v_tax_lines,'adjustments',v_adjustments);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.allocate_booking_offer_adjustment_tax(uuid,uuid,jsonb,jsonb,text)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

-- Extend the offer-save command without changing its public signature or authorization boundary.
DO $migration$
DECLARE
  v_definition text;
  v_old text;
  v_new text;
BEGIN
  SELECT pg_get_functiondef(
    'eogp.save_booking_offer_revision(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,jsonb,jsonb,numeric,text,boolean)'::regprocedure
  ) INTO v_definition;

  v_old:='  v_tax_calculation jsonb;'||E'\n';
  v_new:=v_old||'  v_adjustment_tax jsonb;'||E'\n'||'  v_tax_lines jsonb;'||E'\n';
  IF position(v_old in v_definition)=0 THEN
    RAISE EXCEPTION 'tax calculation declaration anchor not found';
  END IF;
  v_definition:=replace(v_definition,v_old,v_new);

  v_old:='  END LOOP;'||E'\\n'||E'\\n'||'  IF v_subtotal < 0 OR v_subtotal > 999999999999.99 THEN';
  v_new:='  END LOOP;'||E'\\n'||E'\\n'
    ||'  v_adjustment_tax:=eogp.allocate_booking_offer_adjustment_tax('
    ||'p_organization_id,p_price_list_revision_id,v_lines,p_adjustments,p_tax_basis);'||E'\n'
    ||'  v_tax_lines:=v_lines;'||E'\n'
    ||'  IF v_adjustment_tax IS NOT NULL THEN'||E'\n'
    ||'    v_tax_lines:=v_lines||(v_adjustment_tax->''taxLines'');'||E'\n'
    ||'    v_adjustments:=v_adjustment_tax->''adjustments'';'||E'\n'
    ||'  END IF;'||E'\n'
    ||v_old;
  IF position(v_old in v_definition)=0 THEN
    RAISE EXCEPTION 'offer adjustment allocation insertion anchor not found';
  END IF;
  v_definition:=replace(v_definition,v_old,v_new);

  v_old:='p_organization_id,p_price_list_revision_id,p_currency,p_tax_basis,p_valid_until,v_lines,p_tax_amount)';
  v_new:='p_organization_id,p_price_list_revision_id,p_currency,p_tax_basis,p_valid_until,v_tax_lines,p_tax_amount)';
  IF position(v_old in v_definition)=0 THEN
    RAISE EXCEPTION 'tax helper invocation anchor not found';
  END IF;
  v_definition:=replace(v_definition,v_old,v_new);

  v_old:='  IF v_tax_calculation IS NOT NULL AND jsonb_array_length(p_adjustments)>0 AND p_tax_amount=0 THEN'||E'\n'
    ||'    RAISE EXCEPTION ''manual price adjustments require an explicit audited invoice tax override while a tax profile is selected'' USING ERRCODE=''22023'';'||E'\n'
    ||'  END IF;'||E'\n';
  IF position(v_old in v_definition)=0 THEN
    RAISE EXCEPTION 'legacy adjustment tax-block anchor not found';
  END IF;
  v_definition:=replace(v_definition,v_old,'');

  EXECUTE v_definition;
END;
$migration$;

REVOKE ALL ON FUNCTION eogp.save_booking_offer_revision(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,jsonb,jsonb,numeric,text,boolean)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.save_booking_offer_revision(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,jsonb,jsonb,numeric,text,boolean)
  TO eventor_runtime;
