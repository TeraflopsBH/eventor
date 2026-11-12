-- Jurisdiction-neutral calculation against the exact tax-profile revision pinned by a price list.

-- Profile precision is configurable up to four decimals; preserve it in offer amounts.
ALTER TABLE eogp.booking_offer_revisions
  ALTER COLUMN tax_amount TYPE numeric(16,4) USING tax_amount::numeric(16,4),
  ALTER COLUMN total_amount TYPE numeric(16,4) USING total_amount::numeric(16,4);
-- Rates and classifications are organization-authored configuration; this migration seeds none.
-- Manual tax treatments deliberately require the existing audited invoice-level tax override.

CREATE FUNCTION eogp.calculate_booking_offer_tax(
  p_organization_id uuid,
  p_price_list_revision_id uuid,
  p_currency text,
  p_tax_basis text,
  p_valid_until timestamptz,
  p_line_items jsonb,
  p_manual_tax_amount numeric
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_profile_revision eogp.booking_tax_profile_revisions%ROWTYPE;
  v_profile_id uuid;
  v_line jsonb;
  v_code jsonb;
  v_tax_code text;
  v_treatment text;
  v_rate numeric;
  v_base numeric;
  v_raw numeric;
  v_raw_total numeric:=0;
  v_tax_total numeric:=0;
  v_line_tax numeric;
  v_code_raw numeric;
  v_code_tax numeric;
  v_breakdown jsonb:='[]'::jsonb;
  v_codes jsonb:='{}'::jsonb;
  v_manual boolean:=false;
  v_line_count integer:=0;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  -- The enclosing save_booking_offer_revision command performs the actor permission check.

  SELECT revision.tax_profile_revision_id INTO v_profile_id
    FROM eogp.booking_price_list_revisions revision
   WHERE revision.organization_id=p_organization_id
     AND revision.id=p_price_list_revision_id
     AND revision.state='published'
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'published price-list revision not found' USING ERRCODE='23503';
  END IF;
  IF v_profile_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT * INTO v_profile_revision
    FROM eogp.booking_tax_profile_revisions revision
   WHERE revision.organization_id=p_organization_id
     AND revision.id=v_profile_id
     AND revision.state='published'
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'the price list tax-profile revision is no longer available' USING ERRCODE='55000';
  END IF;
  IF v_profile_revision.currency<>p_currency
     OR v_profile_revision.tax_basis<>p_tax_basis
     OR (v_profile_revision.effective_from IS NOT NULL AND v_profile_revision.effective_from>clock_timestamp())
     OR (v_profile_revision.effective_until IS NOT NULL AND v_profile_revision.effective_until<=p_valid_until) THEN
    RAISE EXCEPTION 'tax profile currency, basis or effective window does not cover this offer' USING ERRCODE='55000';
  END IF;
  IF p_tax_basis='not_applicable' THEN
    RETURN jsonb_build_object(
      'profileRevisionId',v_profile_id,'currency',p_currency,'taxBasis',p_tax_basis,
      'roundingMethod',v_profile_revision.rounding_method,'roundingScale',v_profile_revision.rounding_scale,
      'calculationMethod','not_applicable','taxAmount',0,'taxCodes','[]'::jsonb
    );
  END IF;
  IF p_line_items IS NULL OR jsonb_typeof(p_line_items)<>'array' THEN
    RAISE EXCEPTION 'offer line items are required for tax calculation' USING ERRCODE='22023';
  END IF;

  FOR v_line IN SELECT value FROM jsonb_array_elements(p_line_items) LOOP
    v_line_count:=v_line_count+1;
    v_tax_code:=v_line->>'taxCode';
    IF v_tax_code IS NULL THEN
      RAISE EXCEPTION 'offer line % has no tax classification in the pinned price list',v_line_count USING ERRCODE='22023';
    END IF;
    SELECT value INTO v_code
      FROM jsonb_array_elements(v_profile_revision.tax_codes)
     WHERE value->>'taxCode'=v_tax_code;
    IF v_code IS NULL THEN
      RAISE EXCEPTION 'offer line % tax code is absent from the pinned tax profile',v_line_count USING ERRCODE='22023';
    END IF;
    v_treatment:=v_code->>'treatment';
    v_rate:=CASE WHEN v_code->'rate' IS NULL OR v_code->'rate'='null'::jsonb
      THEN NULL ELSE (v_code->>'rate')::numeric END;
    v_base:=(v_line->>'lineTotal')::numeric;
    IF v_treatment='manual' THEN
      v_manual:=true;
      v_raw:=0;
    ELSIF v_treatment='percentage' THEN
      IF p_tax_basis='inclusive' THEN
        v_raw:=v_base*v_rate/(100+v_rate);
      ELSE
        v_raw:=v_base*v_rate/100;
      END IF;
    ELSE
      v_raw:=0;
    END IF;
    v_raw_total:=v_raw_total+v_raw;
    v_codes:=jsonb_set(v_codes,ARRAY[v_tax_code],to_jsonb(
      coalesce((v_codes->>v_tax_code)::numeric,0)+v_raw
    ),true);
    IF v_profile_revision.rounding_method='per_line' THEN
      v_line_tax:=round(v_raw,v_profile_revision.rounding_scale);
      v_tax_total:=v_tax_total+v_line_tax;
    END IF;
    v_breakdown:=v_breakdown||jsonb_build_array(jsonb_build_object(
      'itemCode',v_line->>'itemCode','taxCode',v_tax_code,'treatment',v_treatment,
      'rate',v_rate,'taxableAmount',v_base,'unroundedTaxAmount',v_raw
    ));
  END LOOP;

  IF v_manual THEN
    IF p_manual_tax_amount IS NULL OR p_manual_tax_amount<=0 THEN
      RAISE EXCEPTION 'a manual tax amount is required for a tax code configured as manual' USING ERRCODE='22023';
    END IF;
    v_tax_total:=p_manual_tax_amount;
  ELSIF v_profile_revision.rounding_method='per_tax_code' THEN
    FOR v_tax_code IN SELECT key FROM jsonb_each(v_codes) LOOP
      v_code_raw:=(v_codes->>v_tax_code)::numeric;
      v_code_tax:=round(v_code_raw,v_profile_revision.rounding_scale);
      v_tax_total:=v_tax_total+v_code_tax;
    END LOOP;
  ELSIF v_profile_revision.rounding_method='invoice_total' THEN
    v_tax_total:=round(v_raw_total,v_profile_revision.rounding_scale);
  END IF;

  IF v_tax_total<0 OR v_tax_total>999999999999.99
     OR scale(trim_scale(v_tax_total))>4 THEN
    RAISE EXCEPTION 'calculated tax amount is outside the supported range' USING ERRCODE='22023';
  END IF;

  RETURN jsonb_build_object(
    'profileRevisionId',v_profile_id,'currency',p_currency,'taxBasis',p_tax_basis,
    'roundingMethod',v_profile_revision.rounding_method,'roundingScale',v_profile_revision.rounding_scale,
    'calculationMethod',CASE WHEN v_manual THEN 'manual_override' ELSE v_profile_revision.rounding_method END,
    'taxAmount',v_tax_total,'unroundedTaxAmount',v_raw_total,
    'taxCodes',v_breakdown
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.calculate_booking_offer_tax(uuid,uuid,text,text,timestamptz,jsonb,numeric)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

-- Extend the existing offer command in-place so calculation and offer creation remain
-- in one transaction. Fail the migration rather than silently applying a partial patch.
DO $migration$
DECLARE
  v_definition text;
  v_old text;
  v_new text;
  v_count integer;
BEGIN
  SELECT pg_get_functiondef(
    'eogp.save_booking_offer_revision(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,jsonb,jsonb,numeric,text,boolean)'::regprocedure
  ) INTO v_definition;

  v_old:='  v_tax numeric;'||E'\n';
  v_new:=v_old||'  v_tax_calculation jsonb;'||E'\n';
  IF position(v_old in v_definition)=0 THEN
    RAISE EXCEPTION 'offer command declaration anchor not found';
  END IF;
  v_definition:=replace(v_definition,v_old,v_new);

  v_old:='     OR scale(trim_scale(p_tax_amount)) > 2 THEN';
  v_new:='     OR scale(trim_scale(p_tax_amount)) > 4 THEN';
  IF position(v_old in v_definition)=0 THEN
    RAISE EXCEPTION 'offer command tax precision anchor not found';
  END IF;
  v_definition:=replace(v_definition,v_old,v_new);

  v_old:='  IF p_tax_basis = ''not_applicable'' AND v_tax <> 0 THEN';
  v_new:='  v_tax_calculation:=eogp.calculate_booking_offer_tax('
    ||'p_organization_id,p_price_list_revision_id,p_currency,p_tax_basis,p_valid_until,v_lines,p_tax_amount);'
    ||E'\n'
    ||'  IF v_tax_calculation IS NOT NULL AND jsonb_array_length(p_adjustments)>0 AND p_tax_amount=0 THEN'||E'\n'
    ||'    RAISE EXCEPTION ''manual price adjustments require an explicit audited invoice tax override while a tax profile is selected'' USING ERRCODE=''22023'';'||E'\n'
    ||'  END IF;'||E'\n'
    ||'  IF v_tax_calculation IS NOT NULL THEN'||E'\n'
    ||'    IF p_tax_amount>0 THEN'||E'\n'
    ||'      v_tax:=p_tax_amount;'||E'\n'
    ||'      v_tax_calculation:=jsonb_set(v_tax_calculation,''{taxAmount}'',to_jsonb(v_tax),true);'||E'\n'
    ||'      v_tax_calculation:=jsonb_set(v_tax_calculation,''{calculationMethod}'',''"manual_override"'',true);'||E'\n'
    ||'    ELSE'||E'\n'
    ||'      v_tax:=(v_tax_calculation->>''taxAmount'')::numeric;'||E'\n'
    ||'    END IF;'||E'\n'
    ||'  END IF;'||E'\n'
    ||v_old;
  IF position(v_old in v_definition)=0 THEN
    RAISE EXCEPTION 'offer command tax validation anchor not found';
  END IF;
  v_definition:=replace(v_definition,v_old,v_new);

  v_old:='      ''taxAmount'',v_tax,';
  v_new:='      ''taxAmount'',v_tax,'||E'\n'
    ||'      ''taxCalculation'',v_tax_calculation,';
  IF position(v_old in v_definition)=0 THEN
    RAISE EXCEPTION 'offer terms snapshot tax anchor not found';
  END IF;
  v_definition:=replace(v_definition,v_old,v_new);

  EXECUTE v_definition;
END;
$migration$;

REVOKE ALL ON FUNCTION eogp.save_booking_offer_revision(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,jsonb,jsonb,numeric,text,boolean)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.save_booking_offer_revision(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,text,timestamptz,jsonb,jsonb,numeric,text,boolean)
  TO eventor_runtime;

