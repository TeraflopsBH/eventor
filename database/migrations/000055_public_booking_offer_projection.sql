-- Non-consuming customer projection for the exact issued offer bound to a
-- purpose-specific, single-use capability. The projection deliberately omits
-- internal approval rules, actor details, contact data and internal reasons.
CREATE FUNCTION eogp.get_public_booking_offer_with_capability(
  p_offer_id uuid,
  p_token_sha256 text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_organization_id uuid;
  v_capability_id uuid;
  v_result jsonb;
BEGIN
  IF p_offer_id IS NULL OR p_token_sha256 IS NULL
     OR p_token_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid booking offer capability'
      USING ERRCODE = '22023';
  END IF;

  SELECT lookup.organization_id,lookup.capability_id
    INTO v_organization_id,v_capability_id
    FROM eogp.booking_offer_capability_lookup lookup
   WHERE lookup.token_sha256=p_token_sha256;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking offer capability not found'
      USING ERRCODE = 'P0002';
  END IF;

  PERFORM set_config('app.organization_id',v_organization_id::text,true);

  IF NOT EXISTS (
    SELECT 1
      FROM eogp.external_action_capabilities capability
     WHERE capability.organization_id=v_organization_id
       AND capability.id=v_capability_id
       AND capability.token_sha256=p_token_sha256
       AND capability.action_code='offer_accept'
       AND capability.offer_revision_id IS NOT NULL
       AND capability.revoked_at IS NULL
       AND capability.use_count < capability.max_uses
  ) THEN
    RAISE EXCEPTION 'booking offer capability is no longer active'
      USING ERRCODE = '55000';
  END IF;

  SELECT jsonb_build_object(
    'offerId',offer.id,
    'status',CASE
      WHEN revision.valid_until IS NOT NULL AND revision.valid_until<=clock_timestamp()
        THEN 'expired'
      ELSE 'issued'
    END,
    'revisionNumber',revision.revision_number,
    'currency',revision.currency,
    'subtotal',revision.subtotal,
    'taxAmount',revision.tax_amount,
    'totalAmount',revision.total_amount,
    'validUntil',revision.valid_until,
    'terms',jsonb_build_object(
      'requestedStart',revision.terms_snapshot->'requestedStart',
      'requestedEnd',revision.terms_snapshot->'requestedEnd',
      'timezone',revision.terms_snapshot->'timezone',
      'taxBasis',revision.terms_snapshot->>'taxBasis',
      'lineItems',(
        SELECT coalesce(jsonb_agg(jsonb_build_object(
          'label',items.item->>'label',
          'unit',items.item->>'unit',
          'quantity',(items.item->>'quantity')::numeric,
          'unitAmount',(items.item->>'unitAmount')::numeric,
          'lineTotal',(items.item->>'lineTotal')::numeric
        ) ORDER BY items.ordinality),'[]'::jsonb)
          FROM jsonb_array_elements(coalesce(revision.terms_snapshot->'lineItems','[]'::jsonb))
               WITH ORDINALITY AS items(item,ordinality)
      ),
      'adjustments',(
        SELECT coalesce(jsonb_agg(jsonb_build_object(
          'label',adjustments.adjustment->>'label',
          'kind',adjustments.adjustment->>'kind',
          'amount',(adjustments.adjustment->>'amount')::numeric
        ) ORDER BY adjustments.ordinality),'[]'::jsonb)
          FROM jsonb_array_elements(coalesce(revision.terms_snapshot->'adjustments','[]'::jsonb))
               WITH ORDINALITY AS adjustments(adjustment,ordinality)
      ),
      'spaces',(
        SELECT coalesce(jsonb_agg(jsonb_build_object(
          'code',space.code,
          'name',space.name,
          'blockKind',line.line->>'blockKind',
          'startsAt',line.line->'startsAt',
          'endsAt',line.line->'endsAt',
          'requestedCapacity',line.line->'requestedCapacity'
        ) ORDER BY line.ordinality),'[]'::jsonb)
          FROM jsonb_array_elements(coalesce(revision.terms_snapshot->'spaceLines','[]'::jsonb))
               WITH ORDINALITY AS line(line,ordinality)
          JOIN eogp.venue_spaces space
            ON space.organization_id=v_organization_id
           AND space.id=(line.line->>'venueSpaceId')::uuid
      ),
      'resources',(
        SELECT coalesce(jsonb_agg(jsonb_build_object(
          'label',resources.resource->>'label',
          'requestedQuantity',(resources.resource->>'requestedQuantity')::numeric
        ) ORDER BY resources.ordinality),'[]'::jsonb)
          FROM jsonb_array_elements(coalesce(revision.terms_snapshot->'resourceLines','[]'::jsonb))
               WITH ORDINALITY AS resources(resource,ordinality)
      ),
      'cancellationTerms',revision.terms_snapshot->>'cancellationTerms'
    )
  )
    INTO v_result
    FROM eogp.booking_offers offer
    JOIN eogp.booking_offer_revisions revision
      ON revision.organization_id=offer.organization_id
     AND revision.offer_id=offer.id
    JOIN eogp.external_action_capabilities capability
      ON capability.organization_id=revision.organization_id
     AND capability.offer_revision_id=revision.id
     AND capability.id=v_capability_id
   WHERE offer.organization_id=v_organization_id
     AND offer.id=p_offer_id
     AND revision.id=capability.offer_revision_id
     AND revision.state='issued'
     AND offer.status='issued'
     AND revision.id=(
       SELECT max(latest.id) FILTER (WHERE latest.revision_number=(
         SELECT max(numbered.revision_number)
           FROM eogp.booking_offer_revisions numbered
          WHERE numbered.organization_id=v_organization_id
            AND numbered.offer_id=p_offer_id
       ))
         FROM eogp.booking_offer_revisions latest
        WHERE latest.organization_id=v_organization_id
          AND latest.offer_id=p_offer_id
     );

  IF NOT FOUND THEN
    RAISE EXCEPTION 'the issued offer is not available for customer review'
      USING ERRCODE = 'P0002';
  END IF;
  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.get_public_booking_offer_with_capability(uuid,text)
  FROM PUBLIC,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.get_public_booking_offer_with_capability(uuid,text)
  TO eventor_runtime;
