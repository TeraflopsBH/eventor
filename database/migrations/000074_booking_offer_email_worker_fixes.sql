-- Repair the booking-offer email worker SQL contract without rewriting
-- checksum-verified historical migrations 000058 and 000065.
--
-- The claim function's output-column names overlap identifiers in UPDATE
-- RETURNING clauses. Prefer table columns for those references, return currency
-- as the declared text type, and attribute worker audit events to the supported
-- service_principal actor kind.

CREATE OR REPLACE FUNCTION eogp.claim_booking_offer_email_delivery(
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
#variable_conflict use_column
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
  SELECT p_organization_id,'service_principal','booking.offer.email_uncertain',
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
  SELECT p_organization_id,'service_principal','booking.offer.email_failed',
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
         config.settings->>'replyTo',revision.valid_until,revision.currency::text,revision.total_amount,
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

CREATE OR REPLACE FUNCTION eogp.complete_booking_offer_email_delivery(
  p_organization_id uuid,
  p_delivery_id uuid,
  p_outcome text,
  p_failure_code text DEFAULT NULL,
  p_provider_message_reference text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_delivery eogp.booking_offer_email_deliveries%ROWTYPE;
  v_retry boolean := false;
  v_next timestamptz;
BEGIN
  IF session_user<>'eventor_worker'
     OR eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'offer email completion requires worker role and matching tenant context'
      USING ERRCODE='42501';
  END IF;
  IF p_outcome NOT IN ('sent','failed','uncertain') THEN
    RAISE EXCEPTION 'invalid offer email outcome' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_delivery
    FROM eogp.booking_offer_email_deliveries
   WHERE organization_id=p_organization_id AND id=p_delivery_id
   FOR UPDATE;
  IF NOT FOUND OR v_delivery.status<>'sending' OR v_delivery.lease_expires_at<=clock_timestamp() THEN
    RAISE EXCEPTION 'offer email delivery lease is missing or expired' USING ERRCODE='55000';
  END IF;

  IF p_outcome='sent' THEN
    UPDATE eogp.booking_offer_email_deliveries
       SET status='sent',lease_expires_at=NULL,last_failure_code=NULL,
           provider_message_reference=left(p_provider_message_reference,998),
           sent_at=clock_timestamp(),updated_at=clock_timestamp()
     WHERE organization_id=p_organization_id AND id=p_delivery_id;
  ELSIF p_outcome='uncertain' THEN
    UPDATE eogp.booking_offer_email_deliveries
       SET status='uncertain',lease_expires_at=NULL,
           last_failure_code=left(coalesce(p_failure_code,'SMTP_UNKNOWN'),80),
           updated_at=clock_timestamp()
     WHERE organization_id=p_organization_id AND id=p_delivery_id;
  ELSE
    v_retry := p_failure_code IN ('SMTP_CONNECTION','SMTP_TIMEOUT','SMTP_4XX')
      AND v_delivery.attempt_count<5;
    v_next := clock_timestamp()+make_interval(secs =>
      least(3600,30 * power(2,greatest(0,v_delivery.attempt_count-1))::integer));
    UPDATE eogp.booking_offer_email_deliveries
       SET status=CASE WHEN v_retry THEN 'queued' ELSE 'failed' END,
           next_attempt_at=CASE WHEN v_retry THEN v_next ELSE next_attempt_at END,
           lease_expires_at=NULL,
           last_failure_code=left(coalesce(p_failure_code,'SMTP_UNKNOWN'),80),
           updated_at=clock_timestamp()
     WHERE organization_id=p_organization_id AND id=p_delivery_id;
  END IF;

  IF p_outcome='failed' AND v_retry THEN
    UPDATE eogp.booking_offer_email_delivery_tenant_queue
       SET available_at=least(available_at,v_next),updated_at=clock_timestamp()
     WHERE organization_id=p_organization_id;
  ELSE
    SELECT min(CASE WHEN status='queued' THEN next_attempt_at ELSE lease_expires_at END)
      INTO v_next
      FROM eogp.booking_offer_email_deliveries
     WHERE organization_id=p_organization_id AND status IN ('queued','sending');
    IF v_next IS NULL THEN
      DELETE FROM eogp.booking_offer_email_delivery_tenant_queue
       WHERE organization_id=p_organization_id;
    ELSE
      INSERT INTO eogp.booking_offer_email_delivery_tenant_queue(organization_id,available_at)
      VALUES (p_organization_id,v_next)
      ON CONFLICT (organization_id) DO UPDATE
        SET available_at=EXCLUDED.available_at,updated_at=clock_timestamp();
    END IF;
  END IF;

  INSERT INTO eogp.audit_events(
    organization_id,actor_kind,action,aggregate_type,aggregate_id,
    reason_code,safe_metadata,occurred_at
  ) VALUES (
    p_organization_id,'service_principal',
    CASE WHEN p_outcome='sent' THEN 'booking.offer.email_sent'
         WHEN p_outcome='uncertain' THEN 'booking.offer.email_uncertain'
         ELSE 'booking.offer.email_failed' END,
    'booking_offer',v_delivery.offer_id,
    CASE WHEN p_outcome='sent' THEN 'smtp_accepted'
         ELSE coalesce(p_failure_code,'SMTP_UNKNOWN') END,
    jsonb_build_object('deliveryId',p_delivery_id,'offerRevisionId',v_delivery.offer_revision_id,
      'status',CASE WHEN p_outcome='sent' THEN 'sent'
                    WHEN p_outcome='uncertain' THEN 'uncertain'
                    WHEN v_retry THEN 'queued' ELSE 'failed' END,
      'retryScheduled',p_outcome='failed' AND v_retry),
    clock_timestamp()
  );

  RETURN jsonb_build_object(
    'deliveryId',p_delivery_id,
    'status',CASE WHEN p_outcome='sent' THEN 'sent'
                  WHEN p_outcome='uncertain' THEN 'uncertain'
                  WHEN v_retry THEN 'queued' ELSE 'failed' END,
    'retryScheduled',p_outcome='failed' AND v_retry
  );
END;
$function$;
