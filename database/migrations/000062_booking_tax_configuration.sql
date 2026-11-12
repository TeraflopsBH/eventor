-- Organization-owned, versioned tax configuration.
-- This is a configuration catalogue, not a jurisdiction-specific tax calculator.
-- Offers pin the selected price-list revision, which in turn pins this exact revision.

CREATE TABLE eogp.booking_tax_profiles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
  code text NOT NULL,
  name text NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','retired')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id,id),
  UNIQUE (organization_id,code)
);

CREATE TABLE eogp.booking_tax_profile_revisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  tax_profile_id uuid NOT NULL,
  revision_number integer NOT NULL CHECK (revision_number>0),
  jurisdiction_code text,
  registration_identifier text,
  currency char(3) NOT NULL,
  tax_basis text NOT NULL CHECK (tax_basis IN ('inclusive','exclusive','not_applicable')),
  rounding_method text NOT NULL DEFAULT 'invoice_total'
    CHECK (rounding_method IN ('per_line','per_tax_code','invoice_total')),
  rounding_scale smallint NOT NULL DEFAULT 2 CHECK (rounding_scale BETWEEN 0 AND 4),
  tax_codes jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(tax_codes)='array'),
  effective_from timestamptz,
  effective_until timestamptz,
  state text NOT NULL DEFAULT 'draft' CHECK (state IN ('draft','published','retired')),
  published_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id,id),
  UNIQUE (organization_id,tax_profile_id,id),
  UNIQUE (organization_id,tax_profile_id,revision_number),
  FOREIGN KEY (organization_id,tax_profile_id)
    REFERENCES eogp.booking_tax_profiles(organization_id,id),
  CHECK (currency ~ '^[A-Z]{3}$'),
  CHECK (effective_until IS NULL OR effective_from IS NULL OR effective_until>effective_from),
  CHECK ((state IN ('published','retired'))=(published_at IS NOT NULL))
);

ALTER TABLE eogp.booking_price_list_revisions
  ADD COLUMN tax_profile_revision_id uuid,
  ADD CONSTRAINT booking_price_list_tax_profile_revision_fk
    FOREIGN KEY (organization_id,tax_profile_revision_id)
    REFERENCES eogp.booking_tax_profile_revisions(organization_id,id);

ALTER TABLE eogp.booking_tax_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.booking_tax_profiles FORCE ROW LEVEL SECURITY;
ALTER TABLE eogp.booking_tax_profile_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.booking_tax_profile_revisions FORCE ROW LEVEL SECURITY;
CREATE POLICY booking_tax_profiles_tenant_isolation ON eogp.booking_tax_profiles
  USING (organization_id=eogp.current_organization_id())
  WITH CHECK (organization_id=eogp.current_organization_id());
CREATE POLICY booking_tax_profile_revisions_tenant_isolation ON eogp.booking_tax_profile_revisions
  USING (organization_id=eogp.current_organization_id())
  WITH CHECK (organization_id=eogp.current_organization_id());

CREATE FUNCTION eogp.protect_published_booking_tax_profile_revision()
RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $function$
BEGIN
  IF OLD.state IN ('published','retired') OR OLD.published_at IS NOT NULL THEN
    RAISE EXCEPTION 'published tax profile revisions are immutable' USING ERRCODE='55000';
  END IF;
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$function$;
CREATE TRIGGER booking_tax_profile_revisions_published_immutable_guard
  BEFORE UPDATE OR DELETE ON eogp.booking_tax_profile_revisions
  FOR EACH ROW EXECUTE FUNCTION eogp.protect_published_booking_tax_profile_revision();

CREATE FUNCTION eogp.validate_booking_tax_codes(p_tax_codes jsonb)
RETURNS void LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $function$
DECLARE v_item jsonb; v_code text; v_label text; v_treatment text; v_rate numeric;
  v_codes text[]:=ARRAY[]::text[]; v_count integer:=0;
BEGIN
  IF p_tax_codes IS NULL OR jsonb_typeof(p_tax_codes)<>'array' OR jsonb_array_length(p_tax_codes)>200 THEN
    RAISE EXCEPTION 'tax codes must be an array of at most 200 entries' USING ERRCODE='22023';
  END IF;
  FOR v_item IN SELECT value FROM jsonb_array_elements(p_tax_codes) LOOP
    IF jsonb_typeof(v_item)<>'object'
       OR jsonb_typeof(v_item->'taxCode') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_item->'label') IS DISTINCT FROM 'string'
       OR jsonb_typeof(v_item->'treatment') IS DISTINCT FROM 'string'
       OR (v_item ? 'rate' AND jsonb_typeof(v_item->'rate') NOT IN ('number','null'))
       OR (v_item - 'taxCode' - 'label' - 'treatment' - 'rate') <> '{}'::jsonb THEN
      RAISE EXCEPTION 'each tax code requires taxCode, label and treatment' USING ERRCODE='22023';
    END IF;
    v_code:=btrim(v_item->>'taxCode'); v_label:=btrim(v_item->>'label');
    v_treatment:=v_item->>'treatment';
    v_rate:=CASE WHEN v_item->'rate' IS NULL OR v_item->'rate'='null'::jsonb THEN NULL ELSE (v_item->>'rate')::numeric END;
    IF v_code !~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$'
       OR v_code=ANY(v_codes) OR length(v_label) NOT BETWEEN 1 AND 200
       OR v_treatment NOT IN ('percentage','zero_rated','exempt','out_of_scope','manual')
       OR (v_treatment='percentage' AND (v_rate IS NULL OR v_rate<0 OR v_rate>100 OR scale(trim_scale(v_rate))>6))
       OR (v_treatment<>'percentage' AND v_rate IS NOT NULL) THEN
      RAISE EXCEPTION 'tax code values are invalid or duplicated' USING ERRCODE='22023';
    END IF;
    v_codes:=array_append(v_codes,v_code); v_count:=v_count+1;
  END LOOP;
END;
$function$;

CREATE FUNCTION eogp.get_booking_tax_profiles(p_organization_id uuid,p_actor_membership_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_result jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]);
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'taxProfileId',p.id,'code',p.code,'name',p.name,'status',p.status,'createdAt',p.created_at,
    'latestRevisionId',(SELECT r.id FROM eogp.booking_tax_profile_revisions r
      WHERE r.organization_id=p.organization_id AND r.tax_profile_id=p.id ORDER BY r.revision_number DESC LIMIT 1),
    'revisions',(SELECT coalesce(jsonb_agg(jsonb_build_object(
      'revisionId',r.id,'revisionNumber',r.revision_number,'jurisdictionCode',r.jurisdiction_code,
      'registrationIdentifier',r.registration_identifier,'currency',r.currency,'taxBasis',r.tax_basis,
      'roundingMethod',r.rounding_method,'roundingScale',r.rounding_scale,'taxCodes',r.tax_codes,
      'effectiveFrom',r.effective_from,'effectiveUntil',r.effective_until,'state',r.state,
      'publishedAt',r.published_at,'createdAt',r.created_at
    ) ORDER BY r.revision_number DESC),'[]'::jsonb)
      FROM eogp.booking_tax_profile_revisions r
      WHERE r.organization_id=p.organization_id AND r.tax_profile_id=p.id)
  ) ORDER BY p.code),'[]'::jsonb) INTO v_result
  FROM eogp.booking_tax_profiles p WHERE p.organization_id=p_organization_id;
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.get_booking_price_lists(p_organization_id uuid,p_actor_membership_id uuid)
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
      'taxBasis',r.tax_basis,'taxProfileRevisionId',r.tax_profile_revision_id,'state',r.state,'effectiveFrom',r.effective_from,
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

CREATE FUNCTION eogp.create_booking_tax_profile(
  p_organization_id uuid,p_actor_membership_id uuid,p_code text,p_name text,
  p_jurisdiction_code text,p_registration_identifier text,p_currency text,p_tax_basis text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_profile uuid:=gen_random_uuid(); v_revision uuid:=gen_random_uuid();
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]);
  IF p_code IS NULL OR length(btrim(p_code)) NOT BETWEEN 2 AND 80 OR p_code !~ '^[A-Za-z0-9][A-Za-z0-9._-]*$'
     OR p_name IS NULL OR length(btrim(p_name)) NOT BETWEEN 1 AND 250
     OR p_currency IS NULL OR p_currency !~ '^[A-Z]{3}$'
     OR p_tax_basis NOT IN ('inclusive','exclusive','not_applicable')
     OR (p_jurisdiction_code IS NOT NULL AND length(btrim(p_jurisdiction_code))>100)
     OR (p_registration_identifier IS NOT NULL AND length(btrim(p_registration_identifier))>120) THEN
    RAISE EXCEPTION 'tax profile details are invalid' USING ERRCODE='22023';
  END IF;
  INSERT INTO eogp.booking_tax_profiles(id,organization_id,code,name)
    VALUES(v_profile,p_organization_id,btrim(p_code),btrim(p_name));
  INSERT INTO eogp.booking_tax_profile_revisions(
    id,organization_id,tax_profile_id,revision_number,jurisdiction_code,registration_identifier,
    currency,tax_basis,state,tax_codes
  ) VALUES(v_revision,p_organization_id,v_profile,1,nullif(btrim(p_jurisdiction_code),''),
    nullif(btrim(p_registration_identifier),''),p_currency,p_tax_basis,'draft','[]'::jsonb);
  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata)
  VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.tax_profile.created','booking_tax_profile',v_profile,'tax_profile_created',
    jsonb_build_object('code',btrim(p_code),'revisionId',v_revision));
  RETURN jsonb_build_object('taxProfileId',v_profile,'revisionId',v_revision,'revisionNumber',1,'state','draft');
END;
$function$;

CREATE FUNCTION eogp.create_booking_tax_profile_revision(
  p_organization_id uuid,p_tax_profile_id uuid,p_actor_membership_id uuid,
  p_jurisdiction_code text,p_registration_identifier text,p_currency text,p_tax_basis text,
  p_rounding_method text,p_rounding_scale integer,p_effective_from timestamptz,p_effective_until timestamptz
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_profile eogp.booking_tax_profiles%ROWTYPE; v_latest eogp.booking_tax_profile_revisions%ROWTYPE;
  v_id uuid:=gen_random_uuid(); v_number integer;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]);
  IF p_currency IS NULL OR p_currency !~ '^[A-Z]{3}$'
     OR p_tax_basis IS NULL OR p_tax_basis NOT IN ('inclusive','exclusive','not_applicable')
     OR p_rounding_method IS NULL OR p_rounding_method NOT IN ('per_line','per_tax_code','invoice_total')
     OR p_rounding_scale IS NULL OR p_rounding_scale NOT BETWEEN 0 AND 4
     OR (p_jurisdiction_code IS NOT NULL AND length(btrim(p_jurisdiction_code))>100)
     OR (p_registration_identifier IS NOT NULL AND length(btrim(p_registration_identifier))>120)
     OR (p_effective_from IS NOT NULL AND p_effective_until IS NOT NULL AND p_effective_until<=p_effective_from) THEN
    RAISE EXCEPTION 'tax profile revision settings are invalid' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_profile FROM eogp.booking_tax_profiles WHERE organization_id=p_organization_id AND id=p_tax_profile_id FOR UPDATE;
  IF NOT FOUND OR v_profile.status<>'active' THEN RAISE EXCEPTION 'active tax profile not found' USING ERRCODE='P0002'; END IF;
  SELECT * INTO v_latest FROM eogp.booking_tax_profile_revisions
   WHERE organization_id=p_organization_id AND tax_profile_id=p_tax_profile_id
   ORDER BY revision_number DESC LIMIT 1 FOR UPDATE;
  IF v_latest.state='draft' THEN RAISE EXCEPTION 'update the latest draft tax profile revision instead' USING ERRCODE='55000'; END IF;
  v_number:=v_latest.revision_number+1;
  INSERT INTO eogp.booking_tax_profile_revisions(
    id,organization_id,tax_profile_id,revision_number,jurisdiction_code,registration_identifier,
    currency,tax_basis,rounding_method,rounding_scale,effective_from,effective_until,state,tax_codes
  ) VALUES(v_id,p_organization_id,p_tax_profile_id,v_number,nullif(btrim(p_jurisdiction_code),''),
    nullif(btrim(p_registration_identifier),''),p_currency,p_tax_basis,p_rounding_method,p_rounding_scale,
    p_effective_from,p_effective_until,'draft',v_latest.tax_codes);
  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata)
  VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.tax_profile.revision_created','booking_tax_profile',p_tax_profile_id,'tax_profile_revision_created',
    jsonb_build_object('revisionId',v_id,'revisionNumber',v_number));
  RETURN jsonb_build_object('taxProfileId',p_tax_profile_id,'revisionId',v_id,'revisionNumber',v_number,'state','draft');
END;
$function$;

CREATE FUNCTION eogp.update_booking_tax_profile_draft_revision(
  p_organization_id uuid,p_tax_profile_id uuid,p_revision_id uuid,p_actor_membership_id uuid,
  p_jurisdiction_code text,p_registration_identifier text,p_currency text,p_tax_basis text,
  p_rounding_method text,p_rounding_scale integer,p_effective_from timestamptz,p_effective_until timestamptz,p_tax_codes jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_revision eogp.booking_tax_profile_revisions%ROWTYPE; v_latest_id uuid;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]);
  IF p_currency IS NULL OR p_currency !~ '^[A-Z]{3}$'
     OR p_tax_basis IS NULL OR p_tax_basis NOT IN ('inclusive','exclusive','not_applicable')
     OR p_rounding_method IS NULL OR p_rounding_method NOT IN ('per_line','per_tax_code','invoice_total')
     OR p_rounding_scale IS NULL OR p_rounding_scale NOT BETWEEN 0 AND 4
     OR (p_jurisdiction_code IS NOT NULL AND length(btrim(p_jurisdiction_code))>100)
     OR (p_registration_identifier IS NOT NULL AND length(btrim(p_registration_identifier))>120)
     OR (p_effective_from IS NOT NULL AND p_effective_until IS NOT NULL AND p_effective_until<=p_effective_from) THEN
    RAISE EXCEPTION 'tax profile revision settings are invalid' USING ERRCODE='22023';
  END IF;
  PERFORM eogp.validate_booking_tax_codes(p_tax_codes);
  SELECT id INTO v_latest_id FROM eogp.booking_tax_profile_revisions
   WHERE organization_id=p_organization_id AND tax_profile_id=p_tax_profile_id
   ORDER BY revision_number DESC LIMIT 1;
  IF v_latest_id IS DISTINCT FROM p_revision_id THEN RAISE EXCEPTION 'only the latest tax profile revision may be edited' USING ERRCODE='40001'; END IF;
  SELECT * INTO v_revision FROM eogp.booking_tax_profile_revisions
   WHERE organization_id=p_organization_id AND tax_profile_id=p_tax_profile_id AND id=p_revision_id FOR UPDATE;
  IF NOT FOUND OR v_revision.state<>'draft' THEN RAISE EXCEPTION 'latest draft tax profile revision is required' USING ERRCODE='55000'; END IF;
  UPDATE eogp.booking_tax_profile_revisions SET
    jurisdiction_code=nullif(btrim(p_jurisdiction_code),''),registration_identifier=nullif(btrim(p_registration_identifier),''),
    currency=p_currency,tax_basis=p_tax_basis,rounding_method=p_rounding_method,rounding_scale=p_rounding_scale,
    effective_from=p_effective_from,effective_until=p_effective_until,tax_codes=p_tax_codes
  WHERE organization_id=p_organization_id AND id=p_revision_id;
  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata)
  VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.tax_profile.draft_updated','booking_tax_profile',p_tax_profile_id,'tax_profile_draft_updated',
    jsonb_build_object('revisionId',p_revision_id,'revisionNumber',v_revision.revision_number,'taxCodeCount',jsonb_array_length(p_tax_codes)));
  RETURN jsonb_build_object('taxProfileId',p_tax_profile_id,'revisionId',p_revision_id,
    'revisionNumber',v_revision.revision_number,'state','draft','taxCodeCount',jsonb_array_length(p_tax_codes));
END;
$function$;

CREATE FUNCTION eogp.publish_booking_tax_profile_revision(
  p_organization_id uuid,p_tax_profile_id uuid,p_revision_id uuid,p_actor_membership_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_profile eogp.booking_tax_profiles%ROWTYPE; v_revision eogp.booking_tax_profile_revisions%ROWTYPE;
  v_latest_id uuid; v_published timestamptz:=clock_timestamp();
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]);
  SELECT * INTO v_profile FROM eogp.booking_tax_profiles WHERE organization_id=p_organization_id AND id=p_tax_profile_id FOR UPDATE;
  IF NOT FOUND OR v_profile.status<>'active' THEN RAISE EXCEPTION 'active tax profile not found' USING ERRCODE='P0002'; END IF;
  SELECT id INTO v_latest_id FROM eogp.booking_tax_profile_revisions
   WHERE organization_id=p_organization_id AND tax_profile_id=p_tax_profile_id ORDER BY revision_number DESC LIMIT 1;
  IF v_latest_id IS DISTINCT FROM p_revision_id THEN RAISE EXCEPTION 'only the latest tax profile revision may be published' USING ERRCODE='40001'; END IF;
  SELECT * INTO v_revision FROM eogp.booking_tax_profile_revisions
   WHERE organization_id=p_organization_id AND tax_profile_id=p_tax_profile_id AND id=p_revision_id FOR UPDATE;
  IF NOT FOUND OR v_revision.state<>'draft' THEN RAISE EXCEPTION 'draft tax profile revision is required' USING ERRCODE='55000'; END IF;
  IF jsonb_array_length(v_revision.tax_codes)=0 AND v_revision.tax_basis<>'not_applicable' THEN
    RAISE EXCEPTION 'add at least one tax code or explicitly mark tax as not applicable before publication' USING ERRCODE='22023';
  END IF;
  IF jsonb_array_length(v_revision.tax_codes)>0 AND v_revision.tax_basis='not_applicable' THEN
    RAISE EXCEPTION 'a not-applicable tax profile cannot contain tax codes' USING ERRCODE='22023';
  END IF;
  UPDATE eogp.booking_tax_profile_revisions SET state='published',published_at=v_published
   WHERE organization_id=p_organization_id AND id=p_revision_id;
  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata)
  VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.tax_profile.published','booking_tax_profile',p_tax_profile_id,'tax_profile_published',
    jsonb_build_object('revisionId',p_revision_id,'revisionNumber',v_revision.revision_number,'taxCodeCount',jsonb_array_length(v_revision.tax_codes)));
  RETURN jsonb_build_object('taxProfileId',p_tax_profile_id,'revisionId',p_revision_id,
    'revisionNumber',v_revision.revision_number,'state','published','publishedAt',v_published);
END;
$function$;

CREATE FUNCTION eogp.set_booking_price_list_tax_profile_revision(
  p_organization_id uuid,p_price_list_id uuid,p_revision_id uuid,p_tax_profile_revision_id uuid,p_actor_membership_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_price eogp.booking_price_list_revisions%ROWTYPE; v_tax eogp.booking_tax_profile_revisions%ROWTYPE;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]);
  SELECT * INTO v_price FROM eogp.booking_price_list_revisions
   WHERE organization_id=p_organization_id AND price_list_id=p_price_list_id AND id=p_revision_id FOR UPDATE;
  IF NOT FOUND OR v_price.state<>'draft' OR p_revision_id IS DISTINCT FROM (
    SELECT id FROM eogp.booking_price_list_revisions WHERE organization_id=p_organization_id AND price_list_id=p_price_list_id ORDER BY revision_number DESC LIMIT 1
  ) THEN RAISE EXCEPTION 'latest draft price-list revision is required' USING ERRCODE='55000'; END IF;
  IF p_tax_profile_revision_id IS NOT NULL THEN
    SELECT tax_revision.* INTO v_tax
      FROM eogp.booking_tax_profile_revisions tax_revision
      JOIN eogp.booking_tax_profiles tax_profile
        ON tax_profile.organization_id=tax_revision.organization_id AND tax_profile.id=tax_revision.tax_profile_id
     WHERE tax_revision.organization_id=p_organization_id AND tax_revision.id=p_tax_profile_revision_id
       AND tax_revision.state='published' AND tax_profile.status='active' FOR SHARE OF tax_revision,tax_profile;
    IF NOT FOUND OR v_tax.currency<>v_price.currency OR v_tax.tax_basis<>v_price.tax_basis THEN
      RAISE EXCEPTION 'published tax profile revision must match price-list currency and tax basis' USING ERRCODE='22023';
    END IF;
    IF EXISTS (
      SELECT 1 FROM eogp.booking_price_items i
       WHERE i.organization_id=p_organization_id AND i.price_list_revision_id=p_revision_id
         AND i.tax_code IS NOT NULL
         AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_tax.tax_codes) t WHERE t->>'taxCode'=i.tax_code)
    ) THEN
      RAISE EXCEPTION 'existing price item taxCode is not present in the selected tax profile revision' USING ERRCODE='22023';
    END IF;
  END IF;
  UPDATE eogp.booking_price_list_revisions SET tax_profile_revision_id=p_tax_profile_revision_id
   WHERE organization_id=p_organization_id AND id=p_revision_id;
  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata)
  VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.price_list.tax_profile_selected','booking_price_list',p_price_list_id,'price_list_tax_profile_selected',
    jsonb_build_object('revisionId',p_revision_id,'taxProfileRevisionId',p_tax_profile_revision_id));
  RETURN jsonb_build_object('priceListId',p_price_list_id,'revisionId',p_revision_id,'taxProfileRevisionId',p_tax_profile_revision_id,'state','draft');
END;
$function$;

CREATE FUNCTION eogp.enforce_booking_price_list_tax_profile()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_tax eogp.booking_tax_profile_revisions%ROWTYPE; v_profile_status text;
BEGIN
  IF NEW.state='published' AND NEW.tax_profile_revision_id IS NOT NULL THEN
    SELECT r,p.status INTO v_tax,v_profile_status
      FROM eogp.booking_tax_profile_revisions r
      JOIN eogp.booking_tax_profiles p ON p.organization_id=r.organization_id AND p.id=r.tax_profile_id
     WHERE r.organization_id=NEW.organization_id AND r.id=NEW.tax_profile_revision_id;
    IF NOT FOUND OR v_tax.state<>'published' OR v_profile_status<>'active'
       OR v_tax.currency<>NEW.currency OR v_tax.tax_basis<>NEW.tax_basis
       OR (v_tax.effective_from IS NOT NULL AND (NEW.effective_from IS NULL OR v_tax.effective_from>NEW.effective_from))
       OR (NEW.effective_until IS NOT NULL AND v_tax.effective_until IS NOT NULL AND v_tax.effective_until<NEW.effective_until)
       OR (NEW.effective_until IS NULL AND v_tax.effective_until IS NOT NULL) THEN
      RAISE EXCEPTION 'selected published tax profile revision must match the price-list revision' USING ERRCODE='23514';
    END IF;
    IF EXISTS (
      SELECT 1 FROM eogp.booking_price_items i
       WHERE i.organization_id=NEW.organization_id AND i.price_list_revision_id=NEW.id
         AND i.tax_code IS NOT NULL
         AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_tax.tax_codes) t WHERE t->>'taxCode'=i.tax_code)
    ) THEN
      RAISE EXCEPTION 'every price item taxCode must exist in the selected tax profile revision' USING ERRCODE='23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
CREATE TRIGGER booking_price_list_tax_profile_publish_guard
  BEFORE UPDATE OF state ON eogp.booking_price_list_revisions
  FOR EACH ROW EXECUTE FUNCTION eogp.enforce_booking_price_list_tax_profile();

-- Enrich each new offer's terms with the immutable tax-profile revision selected by its price list.
CREATE FUNCTION eogp.snapshot_booking_offer_tax_profile()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_tax eogp.booking_tax_profile_revisions%ROWTYPE; v_profile eogp.booking_tax_profiles%ROWTYPE;
BEGIN
  SELECT r,p INTO v_tax,v_profile
    FROM eogp.booking_price_list_revisions price
    JOIN eogp.booking_tax_profile_revisions r
      ON r.organization_id=price.organization_id AND r.id=price.tax_profile_revision_id
    JOIN eogp.booking_tax_profiles p
      ON p.organization_id=r.organization_id AND p.id=r.tax_profile_id
   WHERE price.organization_id=NEW.organization_id AND price.id=NEW.price_list_revision_id;
  IF FOUND THEN
    NEW.terms_snapshot:=NEW.terms_snapshot || jsonb_build_object(
      'taxConfiguration',jsonb_build_object(
        'taxProfileId',v_profile.id,'taxProfileCode',v_profile.code,'taxProfileName',v_profile.name,
        'taxProfileRevisionId',v_tax.id,'taxProfileRevisionNumber',v_tax.revision_number,
        'jurisdictionCode',v_tax.jurisdiction_code,'registrationIdentifier',v_tax.registration_identifier,
        'currency',v_tax.currency,'taxBasis',v_tax.tax_basis,'roundingMethod',v_tax.rounding_method,
        'roundingScale',v_tax.rounding_scale,'taxCodes',v_tax.tax_codes
      )
    );
  ELSE
    NEW.terms_snapshot:=NEW.terms_snapshot || jsonb_build_object('taxConfiguration',NULL);
  END IF;
  RETURN NEW;
END;
$function$;
CREATE TRIGGER booking_offer_revision_tax_configuration_snapshot
  BEFORE INSERT ON eogp.booking_offer_revisions
  FOR EACH ROW EXECUTE FUNCTION eogp.snapshot_booking_offer_tax_profile();

REVOKE ALL ON eogp.booking_tax_profiles,eogp.booking_tax_profile_revisions FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.protect_published_booking_tax_profile_revision() FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.validate_booking_tax_codes(jsonb) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.get_booking_tax_profiles(uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.create_booking_tax_profile(uuid,uuid,text,text,text,text,text,text) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.create_booking_tax_profile_revision(uuid,uuid,uuid,text,text,text,text,text,integer,timestamptz,timestamptz) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.update_booking_tax_profile_draft_revision(uuid,uuid,uuid,uuid,text,text,text,text,text,integer,timestamptz,timestamptz,jsonb) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.publish_booking_tax_profile_revision(uuid,uuid,uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.set_booking_price_list_tax_profile_revision(uuid,uuid,uuid,uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.enforce_booking_price_list_tax_profile() FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.snapshot_booking_offer_tax_profile() FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.get_booking_tax_profiles(uuid,uuid),
  eogp.create_booking_tax_profile(uuid,uuid,text,text,text,text,text,text),
  eogp.create_booking_tax_profile_revision(uuid,uuid,uuid,text,text,text,text,text,integer,timestamptz,timestamptz),
  eogp.update_booking_tax_profile_draft_revision(uuid,uuid,uuid,uuid,text,text,text,text,text,integer,timestamptz,timestamptz,jsonb),
  eogp.publish_booking_tax_profile_revision(uuid,uuid,uuid,uuid),
  eogp.set_booking_price_list_tax_profile_revision(uuid,uuid,uuid,uuid,uuid)
  TO eventor_runtime;

     OR p_tax_basis IS NULL OR p_tax_basis NOT IN ('inclusive','exclusive','not_applicable')
     OR p_rounding_method IS NULL OR p_rounding_method NOT IN ('per_line','per_tax_code','invoice_total')
     OR p_rounding_scale IS NULL OR p_rounding_scale NOT BETWEEN 0 AND 4
     OR (p_jurisdiction_code IS NOT NULL AND length(btrim(p_jurisdiction_code))>100)
     OR (p_registration_identifier IS NOT NULL AND length(btrim(p_registration_identifier))>120)
     OR (p_effective_from IS NOT NULL AND p_effective_until IS NOT NULL AND p_effective_until<=p_effective_from) THEN
    RAISE EXCEPTION 'tax profile revision settings are invalid' USING ERRCODE='22023';
  END IF;
  PERFORM eogp.validate_booking_tax_codes(p_tax_codes);
  SELECT id INTO v_latest_id FROM eogp.booking_tax_profile_revisions
   WHERE organization_id=p_organization_id AND tax_profile_id=p_tax_profile_id
   ORDER BY revision_number DESC LIMIT 1;
  IF v_latest_id IS DISTINCT FROM p_revision_id THEN RAISE EXCEPTION 'only the latest tax profile revision may be edited' USING ERRCODE='40001'; END IF;
  SELECT * INTO v_revision FROM eogp.booking_tax_profile_revisions
   WHERE organization_id=p_organization_id AND tax_profile_id=p_tax_profile_id AND id=p_revision_id FOR UPDATE;
  IF NOT FOUND OR v_revision.state<>'draft' THEN RAISE EXCEPTION 'latest draft tax profile revision is required' USING ERRCODE='55000'; END IF;
  UPDATE eogp.booking_tax_profile_revisions SET
    jurisdiction_code=nullif(btrim(p_jurisdiction_code),''),registration_identifier=nullif(btrim(p_registration_identifier),''),
    currency=p_currency,tax_basis=p_tax_basis,rounding_method=p_rounding_method,rounding_scale=p_rounding_scale,
    effective_from=p_effective_from,effective_until=p_effective_until,tax_codes=p_tax_codes
  WHERE organization_id=p_organization_id AND id=p_revision_id;
  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata)
  VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.tax_profile.draft_updated','booking_tax_profile',p_tax_profile_id,'tax_profile_draft_updated',
    jsonb_build_object('revisionId',p_revision_id,'revisionNumber',v_revision.revision_number,'taxCodeCount',jsonb_array_length(p_tax_codes)));
  RETURN jsonb_build_object('taxProfileId',p_tax_profile_id,'revisionId',p_revision_id,
    'revisionNumber',v_revision.revision_number,'state','draft','taxCodeCount',jsonb_array_length(p_tax_codes));
END;
$function$;

CREATE FUNCTION eogp.publish_booking_tax_profile_revision(
  p_organization_id uuid,p_tax_profile_id uuid,p_revision_id uuid,p_actor_membership_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_profile eogp.booking_tax_profiles%ROWTYPE; v_revision eogp.booking_tax_profile_revisions%ROWTYPE;
  v_latest_id uuid; v_published timestamptz:=clock_timestamp();
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]);
  SELECT * INTO v_profile FROM eogp.booking_tax_profiles WHERE organization_id=p_organization_id AND id=p_tax_profile_id FOR UPDATE;
  IF NOT FOUND OR v_profile.status<>'active' THEN RAISE EXCEPTION 'active tax profile not found' USING ERRCODE='P0002'; END IF;
  SELECT id INTO v_latest_id FROM eogp.booking_tax_profile_revisions
   WHERE organization_id=p_organization_id AND tax_profile_id=p_tax_profile_id ORDER BY revision_number DESC LIMIT 1;
  IF v_latest_id IS DISTINCT FROM p_revision_id THEN RAISE EXCEPTION 'only the latest tax profile revision may be published' USING ERRCODE='40001'; END IF;
  SELECT * INTO v_revision FROM eogp.booking_tax_profile_revisions
   WHERE organization_id=p_organization_id AND tax_profile_id=p_tax_profile_id AND id=p_revision_id FOR UPDATE;
  IF NOT FOUND OR v_revision.state<>'draft' THEN RAISE EXCEPTION 'draft tax profile revision is required' USING ERRCODE='55000'; END IF;
  IF jsonb_array_length(v_revision.tax_codes)=0 AND v_revision.tax_basis<>'not_applicable' THEN
    RAISE EXCEPTION 'add at least one tax code or explicitly mark tax as not applicable before publication' USING ERRCODE='22023';
  END IF;
  IF jsonb_array_length(v_revision.tax_codes)>0 AND v_revision.tax_basis='not_applicable' THEN
    RAISE EXCEPTION 'a not-applicable tax profile cannot contain tax codes' USING ERRCODE='22023';
  END IF;
  UPDATE eogp.booking_tax_profile_revisions SET state='published',published_at=v_published
   WHERE organization_id=p_organization_id AND id=p_revision_id;
  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata)
  VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.tax_profile.published','booking_tax_profile',p_tax_profile_id,'tax_profile_published',
    jsonb_build_object('revisionId',p_revision_id,'revisionNumber',v_revision.revision_number,'taxCodeCount',jsonb_array_length(v_revision.tax_codes)));
  RETURN jsonb_build_object('taxProfileId',p_tax_profile_id,'revisionId',p_revision_id,
    'revisionNumber',v_revision.revision_number,'state','published','publishedAt',v_published);
END;
$function$;

CREATE FUNCTION eogp.set_booking_price_list_tax_profile_revision(
  p_organization_id uuid,p_price_list_id uuid,p_revision_id uuid,p_tax_profile_revision_id uuid,p_actor_membership_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_price eogp.booking_price_list_revisions%ROWTYPE; v_tax eogp.booking_tax_profile_revisions%ROWTYPE;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]);
  SELECT * INTO v_price FROM eogp.booking_price_list_revisions
   WHERE organization_id=p_organization_id AND price_list_id=p_price_list_id AND id=p_revision_id FOR UPDATE;
  IF NOT FOUND OR v_price.state<>'draft' OR p_revision_id IS DISTINCT FROM (
    SELECT id FROM eogp.booking_price_list_revisions WHERE organization_id=p_organization_id AND price_list_id=p_price_list_id ORDER BY revision_number DESC LIMIT 1
  ) THEN RAISE EXCEPTION 'latest draft price-list revision is required' USING ERRCODE='55000'; END IF;
  IF p_tax_profile_revision_id IS NOT NULL THEN
    SELECT tax_revision.* INTO v_tax
      FROM eogp.booking_tax_profile_revisions tax_revision
      JOIN eogp.booking_tax_profiles tax_profile
        ON tax_profile.organization_id=tax_revision.organization_id AND tax_profile.id=tax_revision.tax_profile_id
     WHERE tax_revision.organization_id=p_organization_id AND tax_revision.id=p_tax_profile_revision_id
       AND tax_revision.state='published' AND tax_profile.status='active' FOR SHARE OF tax_revision,tax_profile;
    IF NOT FOUND OR v_tax.currency<>v_price.currency OR v_tax.tax_basis<>v_price.tax_basis THEN
      RAISE EXCEPTION 'published tax profile revision must match price-list currency and tax basis' USING ERRCODE='22023';
    END IF;
    IF EXISTS (
      SELECT 1 FROM eogp.booking_price_items i
       WHERE i.organization_id=p_organization_id AND i.price_list_revision_id=p_revision_id
         AND i.tax_code IS NOT NULL
         AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_tax.tax_codes) t WHERE t->>'taxCode'=i.tax_code)
    ) THEN
      RAISE EXCEPTION 'existing price item taxCode is not present in the selected tax profile revision' USING ERRCODE='22023';
    END IF;
  END IF;
  UPDATE eogp.booking_price_list_revisions SET tax_profile_revision_id=p_tax_profile_revision_id
   WHERE organization_id=p_organization_id AND id=p_revision_id;
  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata)
  VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.price_list.tax_profile_selected','booking_price_list',p_price_list_id,'price_list_tax_profile_selected',
    jsonb_build_object('revisionId',p_revision_id,'taxProfileRevisionId',p_tax_profile_revision_id));
  RETURN jsonb_build_object('priceListId',p_price_list_id,'revisionId',p_revision_id,'taxProfileRevisionId',p_tax_profile_revision_id,'state','draft');
END;
$function$;

CREATE FUNCTION eogp.enforce_booking_price_list_tax_profile()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_tax eogp.booking_tax_profile_revisions%ROWTYPE; v_profile_status text;
BEGIN
  IF NEW.state='published' AND NEW.tax_profile_revision_id IS NOT NULL THEN
    SELECT r,p.status INTO v_tax,v_profile_status
      FROM eogp.booking_tax_profile_revisions r
      JOIN eogp.booking_tax_profiles p ON p.organization_id=r.organization_id AND p.id=r.tax_profile_id
     WHERE r.organization_id=NEW.organization_id AND r.id=NEW.tax_profile_revision_id;
    IF NOT FOUND OR v_tax.state<>'published' OR v_profile_status<>'active'
       OR v_tax.currency<>NEW.currency OR v_tax.tax_basis<>NEW.tax_basis
       OR (v_tax.effective_from IS NOT NULL AND (NEW.effective_from IS NULL OR v_tax.effective_from>NEW.effective_from))
       OR (NEW.effective_until IS NOT NULL AND v_tax.effective_until IS NOT NULL AND v_tax.effective_until<NEW.effective_until)
       OR (NEW.effective_until IS NULL AND v_tax.effective_until IS NOT NULL) THEN
      RAISE EXCEPTION 'selected published tax profile revision must match the price-list revision' USING ERRCODE='23514';
    END IF;
    IF EXISTS (
      SELECT 1 FROM eogp.booking_price_items i
       WHERE i.organization_id=NEW.organization_id AND i.price_list_revision_id=NEW.id
         AND i.tax_code IS NOT NULL
         AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_tax.tax_codes) t WHERE t->>'taxCode'=i.tax_code)
    ) THEN
      RAISE EXCEPTION 'every price item taxCode must exist in the selected tax profile revision' USING ERRCODE='23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
CREATE TRIGGER booking_price_list_tax_profile_publish_guard
  BEFORE UPDATE OF state ON eogp.booking_price_list_revisions
  FOR EACH ROW EXECUTE FUNCTION eogp.enforce_booking_price_list_tax_profile();

-- Enrich each new offer's terms with the immutable tax-profile revision selected by its price list.
CREATE FUNCTION eogp.snapshot_booking_offer_tax_profile()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_tax eogp.booking_tax_profile_revisions%ROWTYPE; v_profile eogp.booking_tax_profiles%ROWTYPE;
BEGIN
  SELECT r,p INTO v_tax,v_profile
    FROM eogp.booking_price_list_revisions price
    JOIN eogp.booking_tax_profile_revisions r
      ON r.organization_id=price.organization_id AND r.id=price.tax_profile_revision_id
    JOIN eogp.booking_tax_profiles p
      ON p.organization_id=r.organization_id AND p.id=r.tax_profile_id
   WHERE price.organization_id=NEW.organization_id AND price.id=NEW.price_list_revision_id;
  IF FOUND THEN
    NEW.terms_snapshot:=NEW.terms_snapshot || jsonb_build_object(
      'taxConfiguration',jsonb_build_object(
        'taxProfileId',v_profile.id,'taxProfileCode',v_profile.code,'taxProfileName',v_profile.name,
        'taxProfileRevisionId',v_tax.id,'taxProfileRevisionNumber',v_tax.revision_number,
        'jurisdictionCode',v_tax.jurisdiction_code,'registrationIdentifier',v_tax.registration_identifier,
        'currency',v_tax.currency,'taxBasis',v_tax.tax_basis,'roundingMethod',v_tax.rounding_method,
        'roundingScale',v_tax.rounding_scale,'taxCodes',v_tax.tax_codes
      )
    );
  ELSE
    NEW.terms_snapshot:=NEW.terms_snapshot || jsonb_build_object('taxConfiguration',NULL);
  END IF;
  RETURN NEW;
END;
$function$;
CREATE TRIGGER booking_offer_revision_tax_configuration_snapshot
  BEFORE INSERT ON eogp.booking_offer_revisions
  FOR EACH ROW EXECUTE FUNCTION eogp.snapshot_booking_offer_tax_profile();

REVOKE ALL ON eogp.booking_tax_profiles,eogp.booking_tax_profile_revisions FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.protect_published_booking_tax_profile_revision() FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.validate_booking_tax_codes(jsonb) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.get_booking_tax_profiles(uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.create_booking_tax_profile(uuid,uuid,text,text,text,text,text,text) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.create_booking_tax_profile_revision(uuid,uuid,uuid,text,text,text,text,text,integer,timestamptz,timestamptz) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.update_booking_tax_profile_draft_revision(uuid,uuid,uuid,uuid,text,text,text,text,text,integer,timestamptz,timestamptz,jsonb) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.publish_booking_tax_profile_revision(uuid,uuid,uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.set_booking_price_list_tax_profile_revision(uuid,uuid,uuid,uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.enforce_booking_price_list_tax_profile() FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.snapshot_booking_offer_tax_profile() FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.get_booking_tax_profiles(uuid,uuid),
  eogp.create_booking_tax_profile(uuid,uuid,text,text,text,text,text,text),
  eogp.create_booking_tax_profile_revision(uuid,uuid,uuid,text,text,text,text,text,integer,timestamptz,timestamptz),
  eogp.update_booking_tax_profile_draft_revision(uuid,uuid,uuid,uuid,text,text,text,text,text,integer,timestamptz,timestamptz,jsonb),
  eogp.publish_booking_tax_profile_revision(uuid,uuid,uuid,uuid),
  eogp.set_booking_price_list_tax_profile_revision(uuid,uuid,uuid,uuid,uuid)
  TO eventor_runtime;
