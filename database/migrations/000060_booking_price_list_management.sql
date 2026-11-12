-- Organization-managed price lists: audited draft authoring and immutable publication.
-- The original price-list tables are retained; this migration adds a permission-checked
-- command boundary and makes published pricing revisions immutable.

CREATE FUNCTION eogp.guard_booking_price_list_revision()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog,eogp
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'price-list revisions cannot be deleted' USING ERRCODE = '55000';
  END IF;
  IF OLD.state <> 'draft' THEN
    RAISE EXCEPTION 'published price-list revisions are immutable' USING ERRCODE = '55000';
  END IF;
  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.price_list_id IS DISTINCT FROM OLD.price_list_id
     OR NEW.id IS DISTINCT FROM OLD.id
     OR NEW.revision_number IS DISTINCT FROM OLD.revision_number
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'price-list revision identity is immutable' USING ERRCODE = '55000';
  END IF;
  IF NEW.state NOT IN ('draft','published')
     OR (NEW.state = 'draft' AND NEW.published_at IS NOT NULL)
     OR (NEW.state = 'published' AND NEW.published_at IS NULL) THEN
    RAISE EXCEPTION 'invalid price-list revision transition' USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER booking_price_list_revision_guard
  BEFORE UPDATE OR DELETE ON eogp.booking_price_list_revisions
  FOR EACH ROW EXECUTE FUNCTION eogp.guard_booking_price_list_revision();

CREATE FUNCTION eogp.guard_booking_price_item_revision()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_revision_id uuid;
  v_state text;
BEGIN
  IF TG_OP = 'UPDATE' AND (
    NEW.organization_id IS DISTINCT FROM OLD.organization_id
    OR NEW.price_list_revision_id IS DISTINCT FROM OLD.price_list_revision_id
    OR NEW.id IS DISTINCT FROM OLD.id
  ) THEN
    RAISE EXCEPTION 'price-list item identity is immutable' USING ERRCODE = '55000';
  END IF;
  v_revision_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.price_list_revision_id ELSE NEW.price_list_revision_id END;
  SELECT state INTO v_state
    FROM eogp.booking_price_list_revisions
   WHERE organization_id = CASE WHEN TG_OP = 'DELETE' THEN OLD.organization_id ELSE NEW.organization_id END
     AND id = v_revision_id;
  IF v_state IS DISTINCT FROM 'draft' THEN
    RAISE EXCEPTION 'price-list items may only change while their revision is a draft' USING ERRCODE = '55000';
  END IF;
  RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
END;
$function$;

CREATE TRIGGER booking_price_item_revision_guard
  BEFORE INSERT OR UPDATE OR DELETE ON eogp.booking_price_items
  FOR EACH ROW EXECUTE FUNCTION eogp.guard_booking_price_item_revision();

CREATE FUNCTION eogp.get_booking_price_lists(
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
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'priceListId',price_list.id,
    'code',price_list.code,
    'name',price_list.name,
    'scopeKind',price_list.scope_kind,
    'scopeVenueId',price_list.scope_venue_id,
    'scopeSpaceId',price_list.scope_space_id,
    'status',price_list.status,
    'createdAt',price_list.created_at,
    'latestRevisionId',(
      SELECT revision.id FROM eogp.booking_price_list_revisions revision
       WHERE revision.organization_id=price_list.organization_id
         AND revision.price_list_id=price_list.id
       ORDER BY revision.revision_number DESC LIMIT 1
    ),
    'revisions',(
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'revisionId',revision.id,
        'revisionNumber',revision.revision_number,
        'currency',revision.currency,
        'taxBasis',revision.tax_basis,
        'state',revision.state,
        'effectiveFrom',revision.effective_from,
        'effectiveUntil',revision.effective_until,
        'publishedAt',revision.published_at,
        'createdAt',revision.created_at,
        'items',(
          SELECT coalesce(jsonb_agg(jsonb_build_object(
            'itemCode',item.item_code,
            'label',item.label,
            'unit',item.unit,
            'unitAmount',item.unit_amount,
            'taxCode',item.tax_code,
            'quantityMin',item.quantity_min,
            'quantityMax',item.quantity_max
          ) ORDER BY item.item_code),'[]'::jsonb)
            FROM eogp.booking_price_items item
           WHERE item.organization_id=revision.organization_id
             AND item.price_list_revision_id=revision.id
        )
      ) ORDER BY revision.revision_number DESC),'[]'::jsonb)
        FROM eogp.booking_price_list_revisions revision
       WHERE revision.organization_id=price_list.organization_id
         AND revision.price_list_id=price_list.id
    )
  ) ORDER BY price_list.code),'[]'::jsonb)
    INTO v_result
    FROM eogp.booking_price_lists price_list
   WHERE price_list.organization_id=p_organization_id;

  RETURN v_result;
END;
$function$;

CREATE FUNCTION eogp.create_booking_price_list(
  p_organization_id uuid,
  p_actor_membership_id uuid,
  p_code text,
  p_name text,
  p_scope_kind text,
  p_scope_venue_id uuid,
  p_scope_space_id uuid,
  p_currency text,
  p_tax_basis text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_price_list_id uuid := gen_random_uuid();
  v_revision_id uuid := gen_random_uuid();
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  IF p_code IS NULL OR length(btrim(p_code)) NOT BETWEEN 2 AND 80
     OR p_code !~ '^[A-Za-z0-9][A-Za-z0-9._-]*$'
     OR p_name IS NULL OR length(btrim(p_name)) NOT BETWEEN 1 AND 250
     OR p_scope_kind NOT IN ('organization','venue','space')
     OR p_currency !~ '^[A-Z]{3}$'
     OR p_tax_basis NOT IN ('inclusive','exclusive','not_applicable','to_be_confirmed') THEN
    RAISE EXCEPTION 'price-list details are invalid' USING ERRCODE = '22023';
  END IF;

  INSERT INTO eogp.booking_price_lists(
    id,organization_id,scope_kind,scope_venue_id,scope_space_id,code,name
  ) VALUES (
    v_price_list_id,p_organization_id,p_scope_kind,p_scope_venue_id,p_scope_space_id,btrim(p_code),btrim(p_name)
  );

  INSERT INTO eogp.booking_price_list_revisions(
    id,organization_id,price_list_id,revision_number,currency,tax_basis,state
  ) VALUES (
    v_revision_id,p_organization_id,v_price_list_id,1,p_currency,p_tax_basis,'draft'
  );

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.price_list.created','booking_price_list',v_price_list_id,
    'price_list_created',jsonb_build_object('code',btrim(p_code),'revisionId',v_revision_id)
  );

  RETURN jsonb_build_object(
    'priceListId',v_price_list_id,'revisionId',v_revision_id,
    'revisionNumber',1,'state','draft'
  );
END;
$function$;

CREATE FUNCTION eogp.create_booking_price_list_revision(
  p_organization_id uuid,
  p_price_list_id uuid,
  p_actor_membership_id uuid,
  p_currency text,
  p_tax_basis text,
  p_effective_from timestamptz,
  p_effective_until timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_price_list eogp.booking_price_lists%ROWTYPE;
  v_latest eogp.booking_price_list_revisions%ROWTYPE;
  v_revision_id uuid := gen_random_uuid();
  v_revision_number integer;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  IF p_currency !~ '^[A-Z]{3}$'
     OR p_tax_basis NOT IN ('inclusive','exclusive','not_applicable','to_be_confirmed')
     OR (p_effective_from IS NOT NULL AND p_effective_until IS NOT NULL AND p_effective_until <= p_effective_from) THEN
    RAISE EXCEPTION 'price-list revision settings are invalid' USING ERRCODE = '22023';
  END IF;

  SELECT * INTO v_price_list
    FROM eogp.booking_price_lists
   WHERE organization_id=p_organization_id AND id=p_price_list_id
   FOR UPDATE;
  IF NOT FOUND OR v_price_list.status <> 'active' THEN
    RAISE EXCEPTION 'active price list not found' USING ERRCODE = 'P0002';
  END IF;
  SELECT * INTO v_latest
    FROM eogp.booking_price_list_revisions
   WHERE organization_id=p_organization_id AND price_list_id=p_price_list_id
   ORDER BY revision_number DESC LIMIT 1 FOR UPDATE;
  IF FOUND AND v_latest.state='draft' THEN
    RAISE EXCEPTION 'update the latest draft revision instead of creating another revision' USING ERRCODE = '55000';
  END IF;
  v_revision_number := coalesce(v_latest.revision_number,0)+1;

  INSERT INTO eogp.booking_price_list_revisions(
    id,organization_id,price_list_id,revision_number,currency,tax_basis,state,effective_from,effective_until
  ) VALUES (
    v_revision_id,p_organization_id,p_price_list_id,v_revision_number,p_currency,p_tax_basis,'draft',p_effective_from,p_effective_until
  );

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.price_list.revision_created','booking_price_list',p_price_list_id,
    'price_list_revision_created',jsonb_build_object('revisionId',v_revision_id,'revisionNumber',v_revision_number)
  );

  RETURN jsonb_build_object(
    'priceListId',p_price_list_id,'revisionId',v_revision_id,
    'revisionNumber',v_revision_number,'state','draft'
  );
END;
$function$;

CREATE FUNCTION eogp.replace_booking_price_list_draft_items(
  p_organization_id uuid,
  p_price_list_id uuid,
  p_revision_id uuid,
  p_actor_membership_id uuid,
  p_currency text,
  p_tax_basis text,
  p_effective_from timestamptz,
  p_effective_until timestamptz,
  p_items jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_revision eogp.booking_price_list_revisions%ROWTYPE;
  v_latest_revision_id uuid;
  v_item jsonb;
  v_code text;
  v_label text;
  v_unit text;
  v_amount numeric;
  v_min numeric;
  v_max numeric;
  v_tax_code text;
  v_codes text[] := ARRAY[]::text[];
  v_count integer := 0;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  IF p_currency !~ '^[A-Z]{3}$'
     OR p_tax_basis NOT IN ('inclusive','exclusive','not_applicable','to_be_confirmed')
     OR (p_effective_from IS NOT NULL AND p_effective_until IS NOT NULL AND p_effective_until <= p_effective_from)
     OR p_items IS NULL OR jsonb_typeof(p_items) IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_items) > 500 THEN
    RAISE EXCEPTION 'price-list revision payload is invalid' USING ERRCODE = '22023';
  END IF;

  SELECT revision.id INTO v_latest_revision_id
    FROM eogp.booking_price_list_revisions revision
   WHERE revision.organization_id=p_organization_id AND revision.price_list_id=p_price_list_id
   ORDER BY revision.revision_number DESC LIMIT 1;
  IF v_latest_revision_id IS DISTINCT FROM p_revision_id THEN
    RAISE EXCEPTION 'only the latest price-list revision may be edited' USING ERRCODE = '40001';
  END IF;
  SELECT * INTO v_revision
    FROM eogp.booking_price_list_revisions
   WHERE organization_id=p_organization_id AND price_list_id=p_price_list_id AND id=p_revision_id
   FOR UPDATE;
  IF NOT FOUND OR v_revision.state <> 'draft' THEN
    RAISE EXCEPTION 'latest draft price-list revision is required' USING ERRCODE = '55000';
  END IF;

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    IF jsonb_typeof(v_item) IS DISTINCT FROM 'object'
       OR jsonb_typeof(v_item->'itemCode') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_item->'label') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_item->'unit') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_item->'unitAmount') IS DISTINCT FROM 'number' THEN
      RAISE EXCEPTION 'each price item requires itemCode, label, unit and numeric unitAmount' USING ERRCODE = '22023';
    END IF;
    v_code := btrim(v_item->>'itemCode');
    v_label := btrim(v_item->>'label');
    v_unit := btrim(v_item->>'unit');
    v_amount := (v_item->>'unitAmount')::numeric;
    v_min := CASE WHEN v_item ? 'quantityMin' THEN (v_item->>'quantityMin')::numeric ELSE 1 END;
    v_max := CASE WHEN v_item->'quantityMax' IS NULL OR v_item->'quantityMax' = 'null'::jsonb THEN NULL ELSE (v_item->>'quantityMax')::numeric END;
    v_tax_code := nullif(btrim(v_item->>'taxCode'),'');
    IF length(v_code) NOT BETWEEN 1 AND 100 OR v_code !~ '^[A-Za-z0-9][A-Za-z0-9._-]*$'
       OR v_code = ANY(v_codes)
       OR length(v_label) NOT BETWEEN 1 AND 250
       OR length(v_unit) NOT BETWEEN 1 AND 40
       OR v_amount < 0 OR v_amount::text IN ('NaN','Infinity','-Infinity')
       OR v_min < 0 OR v_min::text IN ('NaN','Infinity','-Infinity')
       OR (v_max IS NOT NULL AND (v_max < v_min OR v_max::text IN ('NaN','Infinity','-Infinity')))
       OR (v_tax_code IS NOT NULL AND length(v_tax_code) > 80) THEN
      RAISE EXCEPTION 'price item values are invalid or duplicate' USING ERRCODE = '22023';
    END IF;
    v_codes := array_append(v_codes,v_code);
    v_count := v_count+1;
  END LOOP;

  UPDATE eogp.booking_price_list_revisions
     SET currency=p_currency,tax_basis=p_tax_basis,
         effective_from=p_effective_from,effective_until=p_effective_until
   WHERE organization_id=p_organization_id AND id=p_revision_id;
  DELETE FROM eogp.booking_price_items
   WHERE organization_id=p_organization_id AND price_list_revision_id=p_revision_id;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO eogp.booking_price_items(
      organization_id,price_list_revision_id,item_code,label,unit,unit_amount,tax_code,quantity_min,quantity_max
    ) VALUES (
      p_organization_id,p_revision_id,btrim(v_item->>'itemCode'),btrim(v_item->>'label'),
      btrim(v_item->>'unit'),(v_item->>'unitAmount')::numeric,
      nullif(btrim(v_item->>'taxCode'),''),coalesce((v_item->>'quantityMin')::numeric,1),
      CASE WHEN v_item->'quantityMax' IS NULL OR v_item->'quantityMax'='null'::jsonb THEN NULL ELSE (v_item->>'quantityMax')::numeric END
    );
  END LOOP;

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.price_list.draft_updated','booking_price_list',p_price_list_id,
    'price_list_draft_updated',
    jsonb_build_object('revisionId',p_revision_id,'revisionNumber',v_revision.revision_number,'itemCount',v_count)
  );

  RETURN jsonb_build_object(
    'priceListId',p_price_list_id,'revisionId',p_revision_id,
    'revisionNumber',v_revision.revision_number,'state','draft','itemCount',v_count
  );
END;
$function$;

CREATE FUNCTION eogp.publish_booking_price_list_revision(
  p_organization_id uuid,
  p_price_list_id uuid,
  p_revision_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_price_list eogp.booking_price_lists%ROWTYPE;
  v_revision eogp.booking_price_list_revisions%ROWTYPE;
  v_latest_revision_id uuid;
  v_item_count integer;
  v_published_at timestamptz := clock_timestamp();
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  SELECT * INTO v_price_list
    FROM eogp.booking_price_lists
   WHERE organization_id=p_organization_id AND id=p_price_list_id
   FOR UPDATE;
  IF NOT FOUND OR v_price_list.status <> 'active' THEN
    RAISE EXCEPTION 'active price list not found' USING ERRCODE = 'P0002';
  END IF;
  SELECT revision.id INTO v_latest_revision_id
    FROM eogp.booking_price_list_revisions revision
   WHERE revision.organization_id=p_organization_id AND revision.price_list_id=p_price_list_id
   ORDER BY revision.revision_number DESC LIMIT 1;
  IF v_latest_revision_id IS DISTINCT FROM p_revision_id THEN
    RAISE EXCEPTION 'only the latest price-list revision may be published' USING ERRCODE = '40001';
  END IF;
  SELECT * INTO v_revision
    FROM eogp.booking_price_list_revisions
   WHERE organization_id=p_organization_id AND price_list_id=p_price_list_id AND id=p_revision_id
   FOR UPDATE;
  IF NOT FOUND OR v_revision.state <> 'draft' THEN
    RAISE EXCEPTION 'draft price-list revision is required' USING ERRCODE = '55000';
  END IF;
  SELECT count(*) INTO v_item_count
    FROM eogp.booking_price_items
   WHERE organization_id=p_organization_id AND price_list_revision_id=p_revision_id;
  IF v_item_count=0 THEN
    RAISE EXCEPTION 'a price list must contain at least one item before publication' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM eogp.booking_price_list_revisions existing
     WHERE existing.organization_id=p_organization_id
       AND existing.price_list_id=p_price_list_id
       AND existing.state='published'
       AND coalesce(existing.effective_from,'-infinity'::timestamptz) < coalesce(v_revision.effective_until,'infinity'::timestamptz)
       AND coalesce(v_revision.effective_from,'-infinity'::timestamptz) < coalesce(existing.effective_until,'infinity'::timestamptz)
  ) THEN
    RAISE EXCEPTION 'published price-list effective periods cannot overlap' USING ERRCODE = '23P01';
  END IF;

  UPDATE eogp.booking_price_list_revisions
     SET state='published',published_at=v_published_at
   WHERE organization_id=p_organization_id AND id=p_revision_id;

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.price_list.published','booking_price_list',p_price_list_id,
    'price_list_published',jsonb_build_object(
      'revisionId',p_revision_id,'revisionNumber',v_revision.revision_number,'itemCount',v_item_count
    )
  );

  RETURN jsonb_build_object(
    'priceListId',p_price_list_id,'revisionId',p_revision_id,
    'revisionNumber',v_revision.revision_number,'state','published','publishedAt',v_published_at
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.guard_booking_price_list_revision() FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.guard_booking_price_item_revision() FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
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
