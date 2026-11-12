-- Staff-visible offer email delivery history and explicit, bounded reconciliation.
-- Uncertain SMTP submissions remain non-retryable until an operator verifies
-- non-acceptance. A single operator-authorized retry is permitted per delivery.

ALTER TABLE eogp.booking_offer_email_deliveries
  ADD COLUMN manual_retry_count smallint NOT NULL DEFAULT 0
    CHECK (manual_retry_count BETWEEN 0 AND 1),
  ADD COLUMN last_operator_resolution text
    CHECK (last_operator_resolution IN ('confirmed_sent','confirmed_not_sent')),
  ADD COLUMN last_operator_reason text
    CHECK (last_operator_reason IS NULL OR length(last_operator_reason) BETWEEN 3 AND 1000),
  ADD COLUMN last_operator_membership_id uuid,
  ADD COLUMN last_operator_at timestamptz,
  ADD CONSTRAINT booking_offer_email_delivery_operator_membership_fk
    FOREIGN KEY (organization_id,last_operator_membership_id)
    REFERENCES eogp.organization_memberships(organization_id,id);

CREATE FUNCTION eogp.list_booking_offer_email_deliveries(
  p_organization_id uuid,
  p_offer_id uuid,
  p_actor_membership_id uuid,
  p_status text DEFAULT NULL,
  p_limit integer DEFAULT 25,
  p_offset integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_total integer;
  v_items jsonb;
  v_counts jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 100
     OR p_offset IS NULL OR p_offset NOT BETWEEN 0 AND 10000
     OR (p_status IS NOT NULL AND p_status NOT IN ('queued','sending','sent','failed','uncertain')) THEN
    RAISE EXCEPTION 'invalid offer email delivery page or status filter' USING ERRCODE='22023';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  IF NOT EXISTS (
    SELECT 1 FROM eogp.booking_offers offer
     WHERE offer.organization_id=p_organization_id AND offer.id=p_offer_id
  ) THEN
    RAISE EXCEPTION 'booking offer not found' USING ERRCODE='P0002';
  END IF;

  SELECT count(*)::integer INTO v_total
    FROM eogp.booking_offer_email_deliveries delivery
   WHERE delivery.organization_id=p_organization_id AND delivery.offer_id=p_offer_id
     AND (p_status IS NULL OR delivery.status=p_status);

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'deliveryId',page.id,
    'offerRevisionId',page.offer_revision_id,
    'status',page.status,
    'attemptCount',page.attempt_count,
    'manualRetryCount',page.manual_retry_count,
    'nextAttemptAt',page.next_attempt_at,
    'createdAt',page.created_at,
    'updatedAt',page.updated_at,
    'sentAt',page.sent_at,
    'lastFailureCode',page.last_failure_code,
    'lastOperatorResolution',page.last_operator_resolution,
    'lastOperatorReason',page.last_operator_reason,
    'lastOperatorAt',page.last_operator_at,
    'canReconcile',page.status='uncertain',
    'canRetry',page.status='failed'
      AND page.last_operator_resolution='confirmed_not_sent'
      AND page.manual_retry_count=0
      AND EXISTS (
        SELECT 1 FROM eogp.booking_offers offer
        JOIN eogp.booking_offer_revisions revision
          ON revision.organization_id=offer.organization_id AND revision.offer_id=offer.id
        WHERE offer.organization_id=page.organization_id AND offer.id=page.offer_id
          AND offer.status='issued' AND revision.id=page.offer_revision_id
          AND revision.state='issued' AND revision.valid_until>clock_timestamp()
          AND revision.revision_number=(
            SELECT max(latest.revision_number)
              FROM eogp.booking_offer_revisions latest
             WHERE latest.organization_id=offer.organization_id AND latest.offer_id=offer.id
          )
      )
  ) ORDER BY page.created_at DESC,page.id DESC),'[]'::jsonb)
    INTO v_items
    FROM (
      SELECT delivery.*
        FROM eogp.booking_offer_email_deliveries delivery
       WHERE delivery.organization_id=p_organization_id AND delivery.offer_id=p_offer_id
         AND (p_status IS NULL OR delivery.status=p_status)
       ORDER BY delivery.created_at DESC,delivery.id DESC
       OFFSET p_offset LIMIT p_limit
    ) page;

  SELECT coalesce(jsonb_object_agg(status,total),'{}'::jsonb)
    INTO v_counts
    FROM (
      SELECT delivery.status,count(*)::integer AS total
        FROM eogp.booking_offer_email_deliveries delivery
       WHERE delivery.organization_id=p_organization_id AND delivery.offer_id=p_offer_id
       GROUP BY delivery.status
    ) counts;

  RETURN jsonb_build_object(
    'items',v_items,
    'page',jsonb_build_object('limit',p_limit,'offset',p_offset,'total',v_total),
    'counts',v_counts
  );
END;
$function$;

CREATE FUNCTION eogp.reconcile_booking_offer_email_delivery(
  p_organization_id uuid,
  p_delivery_id uuid,
  p_actor_membership_id uuid,
  p_resolution text,
  p_reason text,
  p_provider_message_reference text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_delivery eogp.booking_offer_email_deliveries%ROWTYPE;
  v_status text;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  IF p_resolution IS NULL OR p_resolution NOT IN ('confirmed_sent','confirmed_not_sent')
     OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 3 AND 1000
     OR length(coalesce(p_provider_message_reference,''))>998
     OR (p_resolution='confirmed_not_sent' AND nullif(btrim(p_provider_message_reference),'') IS NOT NULL) THEN
    RAISE EXCEPTION 'invalid offer email reconciliation decision' USING ERRCODE='22023';
  END IF;

  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  SELECT * INTO v_delivery
    FROM eogp.booking_offer_email_deliveries
   WHERE organization_id=p_organization_id AND id=p_delivery_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking offer email delivery not found' USING ERRCODE='P0002';
  END IF;
  IF v_delivery.status<>'uncertain' THEN
    RAISE EXCEPTION 'only an uncertain offer email submission can be reconciled'
      USING ERRCODE='55000';
  END IF;

  v_status:=CASE p_resolution WHEN 'confirmed_sent' THEN 'sent' ELSE 'failed' END;
  UPDATE eogp.booking_offer_email_deliveries
     SET status=v_status,
         sent_at=CASE WHEN p_resolution='confirmed_sent' THEN coalesce(sent_at,clock_timestamp()) ELSE NULL END,
         provider_message_reference=CASE WHEN p_resolution='confirmed_sent'
           THEN coalesce(nullif(btrim(p_provider_message_reference),''),provider_message_reference)
           ELSE provider_message_reference END,
         last_failure_code=CASE WHEN p_resolution='confirmed_not_sent'
           THEN 'OPERATOR_CONFIRMED_NOT_SENT' ELSE NULL END,
         last_operator_resolution=p_resolution,
         last_operator_reason=btrim(p_reason),
         last_operator_membership_id=p_actor_membership_id,
         last_operator_at=clock_timestamp(),
         updated_at=clock_timestamp()
   WHERE organization_id=p_organization_id AND id=p_delivery_id;

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.offer.email_reconciled','booking_offer',v_delivery.offer_id,
    jsonb_build_object('deliveryId',p_delivery_id,'previousStatus','uncertain',
      'resolution',p_resolution,'resultingStatus',v_status,
      'providerMessageReferenceSupplied',nullif(btrim(p_provider_message_reference),'') IS NOT NULL,
      'reason',btrim(p_reason))
  );

  RETURN jsonb_build_object(
    'deliveryId',p_delivery_id,'previousStatus','uncertain',
    'status',v_status,'canRetry',p_resolution='confirmed_not_sent'
  );
END;
$function$;

CREATE FUNCTION eogp.retry_booking_offer_email_delivery(
  p_organization_id uuid,
  p_delivery_id uuid,
  p_actor_membership_id uuid,
  p_reason text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_delivery eogp.booking_offer_email_deliveries%ROWTYPE;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  IF length(btrim(coalesce(p_reason,''))) NOT BETWEEN 3 AND 1000 THEN
    RAISE EXCEPTION 'a retry reason between 3 and 1000 characters is required' USING ERRCODE='22023';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  SELECT * INTO v_delivery
    FROM eogp.booking_offer_email_deliveries
   WHERE organization_id=p_organization_id AND id=p_delivery_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking offer email delivery not found' USING ERRCODE='P0002';
  END IF;
  IF v_delivery.status IS DISTINCT FROM 'failed'
     OR v_delivery.last_operator_resolution IS DISTINCT FROM 'confirmed_not_sent'
     OR v_delivery.manual_retry_count>=1
     OR NOT EXISTS (
       SELECT 1
         FROM eogp.booking_offers offer
         JOIN eogp.booking_offer_revisions revision
           ON revision.organization_id=offer.organization_id AND revision.offer_id=offer.id
        WHERE offer.organization_id=p_organization_id
          AND offer.id=v_delivery.offer_id AND offer.status='issued'
          AND revision.id=v_delivery.offer_revision_id AND revision.state='issued'
          AND revision.valid_until>clock_timestamp()
          AND revision.revision_number=(
            SELECT max(latest.revision_number)
              FROM eogp.booking_offer_revisions latest
             WHERE latest.organization_id=offer.organization_id AND latest.offer_id=offer.id
          )
     ) THEN
    RAISE EXCEPTION 'offer email is not eligible for an operator-authorized retry'
      USING ERRCODE='55000';
  END IF;

  UPDATE eogp.booking_offer_email_deliveries
     SET status='queued',attempt_count=0,manual_retry_count=manual_retry_count+1,
         next_attempt_at=clock_timestamp(),lease_expires_at=NULL,
         last_failure_code=NULL,updated_at=clock_timestamp()
   WHERE organization_id=p_organization_id AND id=p_delivery_id;

  INSERT INTO eogp.booking_offer_email_delivery_tenant_queue(organization_id,available_at)
  VALUES (p_organization_id,clock_timestamp())
  ON CONFLICT (organization_id) DO UPDATE
    SET available_at=least(eogp.booking_offer_email_delivery_tenant_queue.available_at,EXCLUDED.available_at),
        updated_at=clock_timestamp();

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.offer.email_retry_authorized','booking_offer',v_delivery.offer_id,
    jsonb_build_object('deliveryId',p_delivery_id,'previousAttemptCount',v_delivery.attempt_count,
      'manualRetryCount',v_delivery.manual_retry_count+1,'reason',btrim(p_reason))
  );

  RETURN jsonb_build_object(
    'deliveryId',p_delivery_id,'status','queued',
    'manualRetryCount',v_delivery.manual_retry_count+1
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.list_booking_offer_email_deliveries(uuid,uuid,uuid,text,integer,integer),
  eogp.reconcile_booking_offer_email_delivery(uuid,uuid,uuid,text,text,text),
  eogp.retry_booking_offer_email_delivery(uuid,uuid,uuid,text)
  FROM PUBLIC,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.list_booking_offer_email_deliveries(uuid,uuid,uuid,text,integer,integer),
  eogp.reconcile_booking_offer_email_delivery(uuid,uuid,uuid,text,text,text),
  eogp.retry_booking_offer_email_delivery(uuid,uuid,uuid,text)
  TO eventor_runtime;
