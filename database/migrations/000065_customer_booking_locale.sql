-- Persist the language explicitly selected for a customer interaction and
-- carry the resolved locale into the public offer projection and delivery job.

ALTER TABLE eogp.organizations
  ADD COLUMN default_locale text NOT NULL DEFAULT 'en'
  CHECK (default_locale IN ('bs-BA','en'));

ALTER TABLE eogp.booking_inquiries
  ADD COLUMN customer_locale text;

UPDATE eogp.booking_inquiries inquiry
   SET customer_locale=organization.default_locale
  FROM eogp.organizations organization
 WHERE organization.id=inquiry.organization_id;

ALTER TABLE eogp.booking_inquiries
  ALTER COLUMN customer_locale SET NOT NULL,
  ADD CONSTRAINT booking_inquiries_customer_locale_check
    CHECK (customer_locale IN ('bs-BA','en'));

CREATE FUNCTION eogp.default_booking_inquiry_customer_locale()
RETURNS trigger
LANGUAGE plpgsql
SET search_path=pg_catalog,eogp
AS $function$
BEGIN
  IF NEW.customer_locale IS NULL THEN
    SELECT default_locale INTO NEW.customer_locale
      FROM eogp.organizations
     WHERE id=NEW.organization_id;
    NEW.customer_locale:=coalesce(NEW.customer_locale,'en');
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.default_booking_inquiry_customer_locale()
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

CREATE TRIGGER booking_inquiries_default_customer_locale
BEFORE INSERT ON eogp.booking_inquiries
FOR EACH ROW EXECUTE FUNCTION eogp.default_booking_inquiry_customer_locale();

-- Keep the original submission command stable for already-running API instances.
-- The wrapper applies an explicitly supplied, validated interaction locale after
-- the original idempotent command has resolved or created the inquiry.
CREATE FUNCTION eogp.submit_public_booking_inquiry_with_locale(
  p_organization_slug text,
  p_form_code text,
  p_form_revision_id uuid,
  p_source_fingerprint text,
  p_key_fingerprint text,
  p_request_fingerprint text,
  p_submitted_values_ciphertext bytea,
  p_requester_name_ciphertext bytea,
  p_requester_email_hash text,
  p_requester_email_ciphertext bytea,
  p_requester_phone_hash text,
  p_requester_phone_ciphertext bytea,
  p_requested_start timestamptz,
  p_requested_end timestamptz,
  p_requested_timezone text,
  p_customer_locale text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_result jsonb;
  v_inquiry_id uuid;
BEGIN
  IF p_customer_locale IS NOT NULL
     AND p_customer_locale NOT IN ('bs-BA','en') THEN
    RAISE EXCEPTION 'unsupported customer locale' USING ERRCODE='22023';
  END IF;

  SELECT eogp.submit_public_booking_inquiry(
    p_organization_slug,p_form_code,p_form_revision_id,
    p_source_fingerprint,p_key_fingerprint,p_request_fingerprint,
    p_submitted_values_ciphertext,p_requester_name_ciphertext,
    p_requester_email_hash,p_requester_email_ciphertext,
    p_requester_phone_hash,p_requester_phone_ciphertext,
    p_requested_start,p_requested_end,p_requested_timezone
  ) INTO v_result;

  IF v_result ? 'inquiryId' THEN
    v_inquiry_id:=(v_result->>'inquiryId')::uuid;
    UPDATE eogp.booking_inquiries
       SET customer_locale=coalesce(p_customer_locale,customer_locale)
     WHERE organization_id=eogp.current_organization_id()
       AND id=v_inquiry_id;
  END IF;
  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.submit_public_booking_inquiry_with_locale(
  text,text,uuid,text,text,text,bytea,bytea,text,bytea,text,bytea,timestamptz,timestamptz,text,text
) FROM PUBLIC,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.submit_public_booking_inquiry_with_locale(
  text,text,uuid,text,text,text,bytea,bytea,text,bytea,text,bytea,timestamptz,timestamptz,text,text
) TO eventor_runtime;

-- Non-consuming customer projection for the exact issued offer bound to a
-- purpose-specific, single-use capability. The projection deliberately omits
-- internal approval rules, actor details, contact data and internal reasons.
CREATE OR REPLACE FUNCTION eogp.get_public_booking_offer_with_capability(
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
    'customerLocale',coalesce(inquiry.customer_locale,organization.default_locale,'en'),
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
    JOIN eogp.booking_drafts draft
      ON draft.organization_id=offer.organization_id
     AND draft.id=offer.draft_id
    LEFT JOIN eogp.booking_inquiries inquiry
      ON inquiry.organization_id=draft.organization_id
     AND inquiry.id=draft.source_inquiry_id
    JOIN eogp.organizations organization
      ON organization.id=offer.organization_id
    JOIN eogp.external_action_capabilities capability
      ON capability.organization_id=revision.organization_id
     AND capability.offer_revision_id=revision.id
     AND capability.id=v_capability_id
   WHERE offer.organization_id=v_organization_id
     AND offer.id=p_offer_id
     AND revision.id=capability.offer_revision_id
     AND revision.state='issued'
     AND offer.status='issued'
     AND revision.revision_number=(
       SELECT max(latest.revision_number)
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


DROP FUNCTION eogp.claim_booking_offer_email_delivery(uuid);

CREATE FUNCTION eogp.claim_booking_offer_email_delivery(
  p_organization_id uuid
) RETURNS TABLE(
  delivery_id uuid,offer_id uuid,offer_revision_id uuid,
  capability_ciphertext bytea,recipient_ciphertext bytea,
  credentials_ciphertext bytea,smtp_settings jsonb,
  sender_email text,sender_name text,reply_to text,
  valid_until timestamptz,currency text,total_amount numeric,customer_locale text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_delivery eogp.booking_offer_email_deliveries%ROWTYPE;
  v_next_available timestamptz;
BEGIN
  IF session_user<>'eventor_worker'
     OR eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'offer email claim requires worker role and matching tenant context'
      USING ERRCODE='42501';
  END IF;

  WITH expired AS (
    UPDATE eogp.booking_offer_email_deliveries
       SET status='uncertain',lease_expires_at=NULL,
           last_failure_code='SMTP_UNKNOWN',updated_at=clock_timestamp()
     WHERE organization_id=p_organization_id AND status='sending'
       AND lease_expires_at<=clock_timestamp()
     RETURNING id,offer_id,offer_revision_id
  )
  INSERT INTO eogp.audit_events(
    organization_id,actor_kind,action,aggregate_type,aggregate_id,
    reason_code,safe_metadata,occurred_at
  )
  SELECT p_organization_id,'system','booking.offer.email_uncertain',
         'booking_offer',expired.offer_id,'SMTP_UNKNOWN',
         jsonb_build_object('deliveryId',expired.id,'offerRevisionId',expired.offer_revision_id,
           'source','expired_worker_lease'),
         clock_timestamp()
    FROM expired;

  WITH stale AS (
    UPDATE eogp.booking_offer_email_deliveries delivery
       SET status='failed',last_failure_code='OFFER_NO_LONGER_CURRENT',
           updated_at=clock_timestamp()
     WHERE delivery.organization_id=p_organization_id
       AND delivery.status='queued'
       AND NOT EXISTS (
       SELECT 1
         FROM eogp.booking_offers offer
         JOIN eogp.booking_offer_revisions revision
           ON revision.organization_id=offer.organization_id AND revision.offer_id=offer.id
        WHERE offer.organization_id=delivery.organization_id
          AND offer.id=delivery.offer_id AND offer.status='issued'
          AND revision.id=delivery.offer_revision_id AND revision.state='issued'
          AND revision.valid_until>clock_timestamp()
          AND revision.revision_number=(
            SELECT max(latest.revision_number)
              FROM eogp.booking_offer_revisions latest
             WHERE latest.organization_id=offer.organization_id AND latest.offer_id=offer.id
          )
     )
     RETURNING id,offer_id,offer_revision_id
  )
  INSERT INTO eogp.audit_events(
    organization_id,actor_kind,action,aggregate_type,aggregate_id,
    reason_code,safe_metadata,occurred_at
  )
  SELECT p_organization_id,'system','booking.offer.email_failed',
         'booking_offer',stale.offer_id,'OFFER_NO_LONGER_CURRENT',
         jsonb_build_object('deliveryId',stale.id,'offerRevisionId',stale.offer_revision_id,
           'source','offer_no_longer_current'),
         clock_timestamp()
    FROM stale;

  SELECT delivery.* INTO v_delivery
    FROM eogp.booking_offer_email_deliveries delivery
   WHERE delivery.organization_id=p_organization_id
     AND delivery.status='queued'
     AND delivery.next_attempt_at<=clock_timestamp()
   ORDER BY delivery.next_attempt_at,delivery.created_at,delivery.id
   FOR UPDATE SKIP LOCKED
   LIMIT 1;
  IF NOT FOUND THEN
    SELECT min(CASE WHEN delivery.status='queued' THEN delivery.next_attempt_at
                    ELSE delivery.lease_expires_at END)
      INTO v_next_available
      FROM eogp.booking_offer_email_deliveries delivery
     WHERE delivery.organization_id=p_organization_id
       AND delivery.status IN ('queued','sending');
    IF v_next_available IS NULL THEN
      DELETE FROM eogp.booking_offer_email_delivery_tenant_queue
       WHERE organization_id=p_organization_id;
    ELSE
      UPDATE eogp.booking_offer_email_delivery_tenant_queue
         SET available_at=v_next_available,updated_at=clock_timestamp()
       WHERE organization_id=p_organization_id;
    END IF;
    RETURN;
  END IF;

  UPDATE eogp.booking_offer_email_deliveries
     SET status='sending',attempt_count=attempt_count+1,
         lease_expires_at=clock_timestamp()+interval '5 minutes',
         updated_at=clock_timestamp()
   WHERE organization_id=p_organization_id AND id=v_delivery.id;

  RETURN QUERY
  SELECT v_delivery.id,v_delivery.offer_id,v_delivery.offer_revision_id,
         v_delivery.capability_ciphertext,v_delivery.recipient_ciphertext,
         config.credentials_ciphertext,config.settings,
         config.settings->>'senderEmail',config.settings->>'senderName',
         config.settings->>'replyTo',revision.valid_until,revision.currency,revision.total_amount,
         coalesce(inquiry.customer_locale,organization.default_locale,'en')
    FROM eogp.organization_delivery_config_revisions config
    JOIN eogp.booking_offer_revisions revision
      ON revision.organization_id=v_delivery.organization_id
     AND revision.id=v_delivery.offer_revision_id
    JOIN eogp.booking_offers offer
      ON offer.organization_id=v_delivery.organization_id
     AND offer.id=v_delivery.offer_id
    JOIN eogp.booking_drafts draft
      ON draft.organization_id=offer.organization_id
     AND draft.id=offer.draft_id
    LEFT JOIN eogp.booking_inquiries inquiry
      ON inquiry.organization_id=draft.organization_id
     AND inquiry.id=draft.source_inquiry_id
    JOIN eogp.organizations organization
      ON organization.id=v_delivery.organization_id
   WHERE config.organization_id=p_organization_id
     AND config.id=v_delivery.delivery_config_revision_id;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.claim_booking_offer_email_delivery(uuid)
  FROM PUBLIC,eventor_runtime,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.claim_booking_offer_email_delivery(uuid)
  TO eventor_worker;
