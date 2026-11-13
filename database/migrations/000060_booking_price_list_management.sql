-- Organization-managed, versioned price-list authoring.
-- Reuses the existing price-list tables from migration 000004. Published revision
-- and child immutability are enforced by migration 000020's generic guards.

CREATE FUNCTION eogp.get_booking_price_lists(p_organization_id uuid,p_actor_membership_id uuid)
RETURNS jsonb
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
    'priceListId',p.id,'code',p.code,'name',p.name,'scopeKind',p.scope_kind,
    'scopeVenueId',p.scope_venue_id,'scopeSpaceId',p.scope_space_id,
    'status',p.status,'createdAt',p.created_at,
    'latestRevisionId',(SELECT r.id FROM eogp.booking_price_list_revisions r
      WHERE r.organization_id=p.organization_id AND r.price_list_id=p.id
      ORDER BY r.revision_number DESC LIMIT 1),
    'revisions',(SELECT coalesce(jsonb_agg(jsonb_build_object(
      'revisionId',r.id,'revisionNumber',r.revision_number,'currency',r.currency,
      'taxBasis',r.tax_basis,'state',r.state,'effectiveFrom',r.effective_from,
      'effectiveUntil',r.effective_until,'publishedAt',r.published_at,'createdAt',r.created_at,
      'items',(SELECT coalesce(jsonb_agg(jsonb_build_object(
        'itemCode',i.item_code,'label',i.label,'unit',i.unit,'unitAmount',i.unit_amount,
        'taxCode',i.tax_code,'quantityMin',i.quantity_min,'quantityMax',i.quantity_max
      ) ORDER BY i.item_code),'[]'::jsonb)
      FROM eogp.booking_price_items i
      WHERE i.organization_id=r.organization_id AND i.price_list_revision_id=r.id)
    ) ORDER BY r.revision_number DESC),'[]'::jsonb)
    FROM eogp.booking_price_list_revisions r
    WHERE r.organization_id=p.organization_id AND r.price_list_id=p.id)
  ) ORDER BY p.code),'[]'::jsonb)
  INTO v_result
  FROM eogp.booking_price_lists p
  WHERE p.organization_id=p_organization_id;
  RETURN v_result;
END;
$function$;

CREATE FUNCTION eogp.create_booking_price_list(
  p_organization_id uuid,p_actor_membership_id uuid,p_code text,p_name text,
  p_scope_kind text,p_scope_venue_id uuid,p_scope_space_id uuid,p_currency text,p_tax_basis text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE v_list_id uuid:=gen_random_uuid(); v_revision_id uuid:=gen_random_uuid();
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  IF p_code IS NULL OR length(btrim(p_code)) NOT BETWEEN 2 AND 80
     OR p_code !~ '^[A-Za-z0-9][A-Za-z0-9._-]*$'
     OR p_name IS NULL OR length(btrim(p_name)) NOT BETWEEN 1 AND 250
     OR p_scope_kind IS NULL OR p_scope_kind NOT IN ('organization','venue','space')
     OR p_currency IS NULL OR p_currency !~ '^[A-Z]{3}$'
     OR p_tax_basis IS NULL OR p_tax_basis NOT IN ('inclusive','exclusive','not_applicable','to_be_confirmed') THEN
    RAISE EXCEPTION 'price-list details are invalid' USING ERRCODE='22023';
  END IF;
  INSERT INTO eogp.booking_price_lists(id,organization_id,scope_kind,scope_venue_id,scope_space_id,code,name)
  VALUES(v_list_id,p_organization_id,p_scope_kind,p_scope_venue_id,p_scope_space_id,btrim(p_code),btrim(p_name));
  INSERT INTO eogp.booking_price_list_revisions(
    id,organization_id,price_list_id,revision_number,currency,tax_basis,state
  ) VALUES(v_revision_id,p_organization_id,v_list_id,1,p_currency,p_tax_basis,'draft');
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.price_list.created','booking_price_list',v_list_id,'price_list_created',
    jsonb_build_object('code',btrim(p_code),'revisionId',v_revision_id));
  RETURN jsonb_build_object('priceListId',v_list_id,'revisionId',v_revision_id,'revisionNumber',1,'state','draft');
END;
$function$;

CREATE FUNCTION eogp.create_booking_price_list_revision(
  p_organization_id uuid,p_price_list_id uuid,p_actor_membership_id uuid,
  p_currency text,p_tax_basis text,p_effective_from timestamptz,p_effective_until timestamptz
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_list eogp.booking_price_lists%ROWTYPE;
  v_latest eogp.booking_price_list_revisions%ROWTYPE;
  v_revision_id uuid:=gen_random_uuid(); v_number integer;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  IF p_currency IS NULL OR p_currency !~ '^[A-Z]{3}$'
     OR p_tax_basis IS NULL OR p_tax_basis NOT IN ('inclusive','exclusive','not_applicable','to_be_confirmed')
     OR (p_effective_from IS NOT NULL AND p_effective_until IS NOT NULL AND p_effective_until<=p_effective_from) THEN
    RAISE EXCEPTION 'price-list revision settings are invalid' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_list FROM eogp.booking_price_lists
   WHERE organization_id=p_organization_id AND id=p_price_list_id FOR UPDATE;
  IF NOT FOUND OR v_list.status<>'active' THEN
    RAISE EXCEPTION 'active price list not found' USING ERRCODE='P0002';
  END IF;
  SELECT * INTO v_latest FROM eogp.booking_price_list_revisions
   WHERE organization_id=p_organization_id AND price_list_id=p_price_list_id
   ORDER BY revision_number DESC LIMIT 1 FOR UPDATE;
  IF FOUND AND v_latest.state='draft' THEN
    RAISE EXCEPTION 'update the latest draft revision instead of creating another revision' USING ERRCODE='55000';
  END IF;
  v_number:=coalesce(v_latest.revision_number,0)+1;
  INSERT INTO eogp.booking_price_list_revisions(
    id,organization_id,price_list_id,revision_number,currency,tax_basis,state,effective_from,effective_until
  ) VALUES(v_revision_id,p_organization_id,p_price_list_id,v_number,p_currency,p_tax_basis,'draft',p_effective_from,p_effective_until);
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.price_list.revision_created','booking_price_list',p_price_list_id,'price_list_revision_created',
    jsonb_build_object('revisionId',v_revision_id,'revisionNumber',v_number));
  RETURN jsonb_build_object('priceListId',p_price_list_id,'revisionId',v_revision_id,'revisionNumber',v_number,'state','draft');
END;
$function$;

CREATE FUNCTION eogp.replace_booking_price_list_draft_items(
  p_organization_id uuid,p_price_list_id uuid,p_revision_id uuid,p_actor_membership_id uuid,
  p_currency text,p_tax_basis text,p_effective_from timestamptz,p_effective_until timestamptz,p_items jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_revision eogp.booking_price_list_revisions%ROWTYPE;
  v_latest_id uuid; v_item jsonb; v_code text; v_label text; v_unit text;
  v_amount numeric; v_min numeric; v_max numeric; v_tax_code text;
  v_codes text[]:=ARRAY[]::text[]; v_count integer:=0;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  IF p_currency IS NULL OR p_currency !~ '^[A-Z]{3}$'
     OR p_tax_basis IS NULL OR p_tax_basis NOT IN ('inclusive','exclusive','not_applicable','to_be_confirmed')
     OR (p_effective_from IS NOT NULL AND p_effective_until IS NOT NULL AND p_effective_until<=p_effective_from)
     OR p_items IS NULL OR jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items)>500 THEN
    RAISE EXCEPTION 'price-list revision payload is invalid' USING ERRCODE='22023';
  END IF;
  SELECT id INTO v_latest_id FROM eogp.booking_price_list_revisions
   WHERE organization_id=p_organization_id AND price_list_id=p_price_list_id
   ORDER BY revision_number DESC LIMIT 1;
  IF v_latest_id IS DISTINCT FROM p_revision_id THEN
    RAISE EXCEPTION 'only the latest price-list revision may be edited' USING ERRCODE='40001';
  END IF;
  SELECT * INTO v_revision FROM eogp.booking_price_list_revisions
   WHERE organization_id=p_organization_id AND price_list_id=p_price_list_id AND id=p_revision_id
   FOR UPDATE;
  IF NOT FOUND OR v_revision.state<>'draft' THEN
    RAISE EXCEPTION 'latest draft price-list revision is required' USING ERRCODE='55000';
  END IF;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    IF jsonb_typeof(v_item)<>'object'
       OR jsonb_typeof(v_item->'itemCode') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_item->'label') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_item->'unit') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_item->'unitAmount') IS DISTINCT FROM 'number'
       OR (v_item ? 'quantityMin' AND jsonb_typeof(v_item->'quantityMin') NOT IN ('number','null'))
       OR (v_item ? 'quantityMax' AND jsonb_typeof(v_item->'quantityMax') NOT IN ('number','null'))
       OR (v_item ? 'taxCode' AND jsonb_typeof(v_item->'taxCode') NOT IN ('string','null')) THEN
      RAISE EXCEPTION 'each price item requires itemCode, label, unit and numeric unitAmount' USING ERRCODE='22023';
    END IF;
    v_code:=btrim(v_item->>'itemCode'); v_label:=btrim(v_item->>'label'); v_unit:=btrim(v_item->>'unit');
    v_amount:=(v_item->>'unitAmount')::numeric;
    v_min:=coalesce((v_item->>'quantityMin')::numeric,1);
    v_max:=CASE WHEN v_item->'quantityMax' IS NULL OR v_item->'quantityMax'='null'::jsonb THEN NULL ELSE (v_item->>'quantityMax')::numeric END;
    v_tax_code:=nullif(btrim(v_item->>'taxCode'),'');
    IF length(v_code) NOT BETWEEN 1 AND 100 OR v_code !~ '^[A-Za-z0-9][A-Za-z0-9._-]*$'
       OR v_code=ANY(v_codes) OR length(v_label) NOT BETWEEN 1 AND 250 OR length(v_unit) NOT BETWEEN 1 AND 40
       OR v_amount<0 OR v_amount>999999999999.99 OR v_amount::text IN ('NaN','Infinity','-Infinity') OR scale(trim_scale(v_amount))>2
       OR v_min<0 OR v_min>999999999.999 OR v_min::text IN ('NaN','Infinity','-Infinity') OR scale(trim_scale(v_min))>3
       OR (v_max IS NOT NULL AND (v_max<v_min OR v_max>999999999.999 OR v_max::text IN ('NaN','Infinity','-Infinity') OR scale(trim_scale(v_max))>3))
       OR (v_tax_code IS NOT NULL AND length(v_tax_code)>80) THEN
      RAISE EXCEPTION 'price item values are invalid or duplicate' USING ERRCODE='22023';
    END IF;
    v_codes:=array_append(v_codes,v_code); v_count:=v_count+1;
  END LOOP;
  UPDATE eogp.booking_price_list_revisions
   SET currency=p_currency,tax_basis=p_tax_basis,effective_from=p_effective_from,effective_until=p_effective_until
   WHERE organization_id=p_organization_id AND id=p_revision_id;
  DELETE FROM eogp.booking_price_items
   WHERE organization_id=p_organization_id AND price_list_revision_id=p_revision_id;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    INSERT INTO eogp.booking_price_items(
      organization_id,price_list_revision_id,item_code,label,unit,unit_amount,tax_code,quantity_min,quantity_max
    ) VALUES(
      p_organization_id,p_revision_id,btrim(v_item->>'itemCode'),btrim(v_item->>'label'),btrim(v_item->>'unit'),
      (v_item->>'unitAmount')::numeric,nullif(btrim(v_item->>'taxCode'),''),
      coalesce((v_item->>'quantityMin')::numeric,1),
      CASE WHEN v_item->'quantityMax' IS NULL OR v_item->'quantityMax'='null'::jsonb THEN NULL ELSE (v_item->>'quantityMax')::numeric END
    );
  END LOOP;
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.price_list.draft_updated','booking_price_list',p_price_list_id,'price_list_draft_updated',
    jsonb_build_object('revisionId',p_revision_id,'revisionNumber',v_revision.revision_number,'itemCount',v_count));
  RETURN jsonb_build_object('priceListId',p_price_list_id,'revisionId',p_revision_id,'revisionNumber',v_revision.revision_number,'state','draft','itemCount',v_count);
END;
$function$;

CREATE FUNCTION eogp.publish_booking_price_list_revision(
  p_organization_id uuid,p_price_list_id uuid,p_revision_id uuid,p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_list eogp.booking_price_lists%ROWTYPE;
  v_revision eogp.booking_price_list_revisions%ROWTYPE;
  v_latest_id uuid; v_item_count integer; v_published_at timestamptz:=clock_timestamp();
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  SELECT * INTO v_list FROM eogp.booking_price_lists
   WHERE organization_id=p_organization_id AND id=p_price_list_id FOR UPDATE;
  IF NOT FOUND OR v_list.status<>'active' THEN
    RAISE EXCEPTION 'active price list not found' USING ERRCODE='P0002';
  END IF;
  SELECT id INTO v_latest_id FROM eogp.booking_price_list_revisions
   WHERE organization_id=p_organization_id AND price_list_id=p_price_list_id
   ORDER BY revision_number DESC LIMIT 1;
  IF v_latest_id IS DISTINCT FROM p_revision_id THEN
    RAISE EXCEPTION 'only the latest price-list revision may be published' USING ERRCODE='40001';
  END IF;
  SELECT * INTO v_revision FROM eogp.booking_price_list_revisions
   WHERE organization_id=p_organization_id AND price_list_id=p_price_list_id AND id=p_revision_id FOR UPDATE;
  IF NOT FOUND OR v_revision.state<>'draft' THEN
    RAISE EXCEPTION 'draft price-list revision is required' USING ERRCODE='55000';
  END IF;
  SELECT count(*) INTO v_item_count FROM eogp.booking_price_items
   WHERE organization_id=p_organization_id AND price_list_revision_id=p_revision_id;
  IF v_item_count=0 THEN
    RAISE EXCEPTION 'a price list must contain at least one item before publication' USING ERRCODE='22023';
  END IF;
  -- Effective bounds are eligibility metadata. Offers pin the exact selected revision;
  -- overlapping windows are allowed because published revisions cannot be amended.
  UPDATE eogp.booking_price_list_revisions
   SET state='published',published_at=v_published_at
   WHERE organization_id=p_organization_id AND id=p_revision_id;
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.price_list.published','booking_price_list',p_price_list_id,'price_list_published',
    jsonb_build_object('revisionId',p_revision_id,'revisionNumber',v_revision.revision_number,'itemCount',v_item_count));
  RETURN jsonb_build_object('priceListId',p_price_list_id,'revisionId',p_revision_id,
    'revisionNumber',v_revision.revision_number,'state','published','publishedAt',v_published_at);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.get_booking_price_lists(uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.create_booking_price_list(uuid,uuid,text,text,text,uuid,uuid,text,text) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.create_booking_price_list_revision(uuid,uuid,uuid,text,text,timestamptz,timestamptz) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.replace_booking_price_list_draft_items(uuid,uuid,uuid,uuid,text,text,timestamptz,timestamptz,jsonb) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.publish_booking_price_list_revision(uuid,uuid,uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON TABLE eogp.booking_price_lists,eogp.booking_price_list_revisions,eogp.booking_price_items
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.get_booking_price_lists(uuid,uuid),
  eogp.create_booking_price_list(uuid,uuid,text,text,text,uuid,uuid,text,text),
  eogp.create_booking_price_list_revision(uuid,uuid,uuid,text,text,timestamptz,timestamptz),
  eogp.replace_booking_price_list_draft_items(uuid,uuid,uuid,uuid,text,text,timestamptz,timestamptz,jsonb),
  eogp.publish_booking_price_list_revision(uuid,uuid,uuid,uuid)
  TO eventor_runtime;
