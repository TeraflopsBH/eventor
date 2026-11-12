\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','11111111-1111-4111-8111-111111111111',true);

DO $test$
DECLARE
  v_org uuid := '11111111-1111-4111-8111-111111111111';
  v_profile uuid;
  v_profile_revision uuid;
  v_price_list uuid;
  v_price_revision uuid;
  v_allocation jsonb;
  v_calculation jsonb;
  v_lines jsonb;
  v_adjustments jsonb;
  v_tax_amount numeric;
  v_bad_code_rejected boolean := false;
  v_negative_base_rejected boolean := false;
  v_manual_profile uuid;
  v_manual_profile_revision uuid;
  v_manual_list uuid;
  v_manual_price_revision uuid;
  v_na_profile uuid;
  v_na_profile_revision uuid;
  v_na_list uuid;
  v_na_price_revision uuid;
  v_na_allocation jsonb;
  v_na_calculation jsonb;
BEGIN
  -- Exclusive profile: standard 20%, reduced 5%, manual and three zero-rate codes.
  INSERT INTO eogp.booking_tax_profiles(organization_id,code,name)
  VALUES(v_org,'ci-adjustment-'||gen_random_uuid()::text,'CI adjustment allocation')
  RETURNING id INTO v_profile;
  INSERT INTO eogp.booking_tax_profile_revisions(
    organization_id,tax_profile_id,revision_number,currency,tax_basis,
    rounding_method,rounding_scale,tax_codes,state,published_at
  ) VALUES(
    v_org,v_profile,1,'USD','exclusive','invoice_total',2,
    '[
      {"taxCode":"STANDARD","label":"Standard","treatment":"percentage","rate":20},
      {"taxCode":"REDUCED","label":"Reduced","treatment":"percentage","rate":5},
      {"taxCode":"MANUAL","label":"Manual","treatment":"manual"},
      {"taxCode":"A","label":"A","treatment":"zero_rated"},
      {"taxCode":"B","label":"B","treatment":"zero_rated"},
      {"taxCode":"C","label":"C","treatment":"zero_rated"}
    ]'::jsonb,'published',clock_timestamp()
  ) RETURNING id INTO v_profile_revision;

  INSERT INTO eogp.booking_price_lists(organization_id,code,name)
  VALUES(v_org,'ci-adjustment-'||gen_random_uuid()::text,'CI adjustment price list')
  RETURNING id INTO v_price_list;
  INSERT INTO eogp.booking_price_list_revisions(
    organization_id,price_list_id,revision_number,currency,tax_basis,state,published_at,tax_profile_revision_id
  ) VALUES(v_org,v_price_list,1,'USD','exclusive','published',clock_timestamp(),v_profile_revision)
  RETURNING id INTO v_price_revision;

  v_lines := '[
    {"itemCode":"line-standard","lineTotal":100.00,"taxCode":"STANDARD"},
    {"itemCode":"line-reduced","lineTotal":100.00,"taxCode":"REDUCED"}
  ]'::jsonb;
  v_adjustments := '[
    {"code":"discount-proportional","label":"Proportional discount","kind":"discount","amount":10.00,"allocationMethod":"proportional_to_lines"},
    {"code":"fee-standard","label":"Standard fee","kind":"fee","amount":5.00,"allocationMethod":"tax_code","taxCode":"STANDARD"},
    {"code":"credit-reduced","label":"Reduced credit","kind":"credit","amount":2.00,"allocationMethod":"tax_code","taxCode":"REDUCED"}
  ]'::jsonb;

  v_allocation := eogp.allocate_booking_offer_adjustment_tax(
    v_org,v_price_revision,v_lines,v_adjustments,'exclusive'
  );
  IF jsonb_array_length(v_allocation->'adjustments')<>3
     OR v_allocation->'adjustments'->0->>'allocationMethod'<>'proportional_to_lines'
     OR (v_allocation->'adjustments'->0->'taxAllocations'->0->>'amount')::numeric<>-5.00
     OR (v_allocation->'adjustments'->1->'taxAllocations'->0->>'amount')::numeric<>5.00
     OR (v_allocation->'adjustments'->2->'taxAllocations'->0->>'amount')::numeric<>-2.00 THEN
    RAISE EXCEPTION 'adjustment allocation snapshot is incorrect: %',v_allocation;
  END IF;

  v_calculation := eogp.calculate_booking_offer_tax(
    v_org,v_price_revision,'USD','exclusive',clock_timestamp()+interval '1 day',
    v_lines||(v_allocation->'taxLines'),0
  );
  v_tax_amount := (v_calculation->>'taxAmount')::numeric;
  IF v_tax_amount<>25.65 THEN
    RAISE EXCEPTION 'exclusive tax after mixed allocations should be 25.65, got % (%).',v_tax_amount,v_calculation;
  END IF;

  -- Residual-cent rule: earlier buckets round to zero; final alphabetic bucket receives the cent.
  v_allocation := eogp.allocate_booking_offer_adjustment_tax(
    v_org,v_price_revision,
    '[
      {"itemCode":"a","lineTotal":1.00,"taxCode":"A"},
      {"itemCode":"b","lineTotal":1.00,"taxCode":"B"},
      {"itemCode":"c","lineTotal":1.00,"taxCode":"C"}
    ]'::jsonb,
    '[{"code":"one-cent","label":"One cent","kind":"discount","amount":0.01,"allocationMethod":"proportional_to_lines"}]'::jsonb,
    'exclusive'
  );
  IF (v_allocation->'adjustments'->0->'taxAllocations'->0->>'amount')::numeric<>0
     OR (v_allocation->'adjustments'->0->'taxAllocations'->1->>'amount')::numeric<>0
     OR (v_allocation->'adjustments'->0->'taxAllocations'->2->>'amount')::numeric<>-0.01 THEN
    RAISE EXCEPTION 'proportional residual cent was not assigned deterministically: %',v_allocation;
  END IF;

  -- Unknown adjustment tax codes must be rejected against the pinned profile.
  BEGIN
    PERFORM eogp.allocate_booking_offer_adjustment_tax(
      v_org,v_price_revision,v_lines,
      '[{"code":"bad-code","label":"Bad code","kind":"fee","amount":1.00,"allocationMethod":"tax_code","taxCode":"NOT_CONFIGURED"}]'::jsonb,
      'exclusive'
    );
  EXCEPTION WHEN SQLSTATE '22023' THEN
    v_bad_code_rejected:=true;
  END;
  IF NOT v_bad_code_rejected THEN
    RAISE EXCEPTION 'an adjustment tax code absent from the pinned profile was accepted';
  END IF;

  -- Discounts may not make any individual tax-code taxable base negative.
  BEGIN
    PERFORM eogp.allocate_booking_offer_adjustment_tax(
      v_org,v_price_revision,v_lines,
      '[{"code":"too-large","label":"Too large","kind":"discount","amount":201.00,"allocationMethod":"tax_code","taxCode":"STANDARD"}]'::jsonb,
      'exclusive'
    );
  EXCEPTION WHEN SQLSTATE '22023' THEN
    v_negative_base_rejected:=true;
  END;
  IF NOT v_negative_base_rejected THEN
    RAISE EXCEPTION 'a discount that creates a negative tax-code base was accepted';
  END IF;

  -- Manual tax treatment remains an audited invoice-level override, not a percentage calculation.
  INSERT INTO eogp.booking_tax_profiles(organization_id,code,name)
  VALUES(v_org,'ci-manual-'||gen_random_uuid()::text,'CI manual tax')
  RETURNING id INTO v_manual_profile;
  INSERT INTO eogp.booking_tax_profile_revisions(
    organization_id,tax_profile_id,revision_number,currency,tax_basis,
    tax_codes,state,published_at
  ) VALUES(v_org,v_manual_profile,1,'USD','exclusive',
    '[{"taxCode":"MANUAL","label":"Manual","treatment":"manual"}]'::jsonb,'published',clock_timestamp())
  RETURNING id INTO v_manual_profile_revision;
  INSERT INTO eogp.booking_price_lists(organization_id,code,name)
  VALUES(v_org,'ci-manual-'||gen_random_uuid()::text,'CI manual price list')
  RETURNING id INTO v_manual_list;
  INSERT INTO eogp.booking_price_list_revisions(
    organization_id,price_list_id,revision_number,currency,tax_basis,state,published_at,tax_profile_revision_id
  ) VALUES(v_org,v_manual_list,1,'USD','exclusive','published',clock_timestamp(),v_manual_profile_revision)
  RETURNING id INTO v_manual_price_revision;

  v_allocation:=eogp.allocate_booking_offer_adjustment_tax(
    v_org,v_manual_price_revision,
    '[{"itemCode":"manual-line","lineTotal":100.00,"taxCode":"MANUAL"}]'::jsonb,
    '[{"code":"manual-discount","label":"Manual discount","kind":"discount","amount":10.00,"allocationMethod":"tax_code","taxCode":"MANUAL"}]'::jsonb,
    'exclusive'
  );
  v_calculation:=eogp.calculate_booking_offer_tax(
    v_org,v_manual_price_revision,'USD','exclusive',clock_timestamp()+interval '1 day',
    '[{"itemCode":"manual-line","lineTotal":100.00,"taxCode":"MANUAL"}]'::jsonb||(v_allocation->'taxLines'),7.25
  );
  IF v_calculation->>'calculationMethod'<>'manual_override'
     OR (v_calculation->>'taxAmount')::numeric<>7.25 THEN
    RAISE EXCEPTION 'manual tax override behaviour changed: %',v_calculation;
  END IF;

  -- Not-applicable profiles require explicit not_applicable treatment and always calculate zero.
  INSERT INTO eogp.booking_tax_profiles(organization_id,code,name)
  VALUES(v_org,'ci-na-'||gen_random_uuid()::text,'CI not applicable tax')
  RETURNING id INTO v_na_profile;
  INSERT INTO eogp.booking_tax_profile_revisions(
    organization_id,tax_profile_id,revision_number,currency,tax_basis,
    tax_codes,state,published_at
  ) VALUES(v_org,v_na_profile,1,'USD','not_applicable','[]'::jsonb,'published',clock_timestamp())
  RETURNING id INTO v_na_profile_revision;
  INSERT INTO eogp.booking_price_lists(organization_id,code,name)
  VALUES(v_org,'ci-na-'||gen_random_uuid()::text,'CI not applicable price list')
  RETURNING id INTO v_na_list;
  INSERT INTO eogp.booking_price_list_revisions(
    organization_id,price_list_id,revision_number,currency,tax_basis,state,published_at,tax_profile_revision_id
  ) VALUES(v_org,v_na_list,1,'USD','not_applicable','published',clock_timestamp(),v_na_profile_revision)
  RETURNING id INTO v_na_price_revision;

  v_na_allocation:=eogp.allocate_booking_offer_adjustment_tax(
    v_org,v_na_price_revision,'[]'::jsonb,
    '[{"code":"na-fee","label":"Not applicable fee","kind":"fee","amount":3.00,"allocationMethod":"not_applicable"}]'::jsonb,
    'not_applicable'
  );
  v_na_calculation:=eogp.calculate_booking_offer_tax(
    v_org,v_na_price_revision,'USD','not_applicable',clock_timestamp()+interval '1 day','[]'::jsonb,0
  );
  IF v_na_calculation->>'calculationMethod'<>'not_applicable'
     OR (v_na_calculation->>'taxAmount')::numeric<>0
     OR v_na_allocation->'adjustments'->0->>'allocationMethod'<>'not_applicable' THEN
    RAISE EXCEPTION 'not-applicable adjustment handling is incorrect: %, %',v_na_allocation,v_na_calculation;
  END IF;

  RAISE NOTICE 'booking tax adjustment calculation fixtures passed';
END;
$test$;

ROLLBACK;
