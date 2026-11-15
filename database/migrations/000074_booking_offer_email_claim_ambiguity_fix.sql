-- Qualify UPDATE RETURNING columns that collide with RETURNS TABLE output variables.
-- Without qualification, PL/pgSQL cannot resolve offer_id in the expired/stale CTEs.
DROP FUNCTION eogp.claim_booking_offer_email_delivery(uuid);

CREATE FUNCTION eogp.claim_booking_offer_email_delivery(
  p_organization_id uuid
) RETURNS TABLE(
  delivery_id uuid,offer_id uuid,offer_revision_id uuid,
  capability_ciphertext bytea,recipient_ciphertext bytea,
  credentials_ciphertext bytea,smtp_settings jsonb,
  sender_email text,sender_name text,reply_to text,
  valid_until timestamptz,currency text,total_amount numeric
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
    UPDATE eogp.booking_offer_email_deliveries delivery
       SET status='uncertain',lease_expires_at=NULL,
           last_failure_code='SMTP_UNKNOWN',updated_at=clock_timestamp()
     WHERE organization_id=p_organization_id AND status='sending'
       AND lease_expires_at<=clock_timestamp()
     RETURNING delivery.id,delivery.offer_id,delivery.offer_revision_id
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
     RETURNING delivery.id,delivery.offer_id,delivery.offer_revision_id
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
         config.settings->>'replyTo',revision.valid_until,revision.currency::text,revision.total_amount
    FROM eogp.organization_delivery_config_revisions config
    JOIN eogp.booking_offer_revisions revision
      ON revision.organization_id=v_delivery.organization_id
     AND revision.id=v_delivery.offer_revision_id
   WHERE config.organization_id=p_organization_id
     AND config.id=v_delivery.delivery_config_revision_id;
END;
$function$;


REVOKE ALL ON FUNCTION eogp.claim_booking_offer_email_delivery(uuid) FROM PUBLIC,eventor_runtime,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.claim_booking_offer_email_delivery(uuid) TO eventor_worker;
