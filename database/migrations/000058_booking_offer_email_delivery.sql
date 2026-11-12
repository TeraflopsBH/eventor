-- Explicit, queued email delivery for issued booking offers.
-- The raw customer capability is encrypted before it enters this queue; the
-- database stores neither the raw token nor a reusable public URL.

CREATE TABLE eogp.booking_offer_email_deliveries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  offer_id uuid NOT NULL,
  offer_revision_id uuid NOT NULL,
  idempotency_key_sha256 text NOT NULL
    CHECK (idempotency_key_sha256 ~ '^[0-9a-f]{64}$'),
  capability_token_sha256 text NOT NULL
    CHECK (capability_token_sha256 ~ '^[0-9a-f]{64}$'),
  capability_ciphertext bytea NOT NULL
    CHECK (octet_length(capability_ciphertext) > 32
       AND substring(capability_ciphertext FROM 1 FOR 4) = convert_to('ECP1','UTF8')),
  recipient_ciphertext bytea NOT NULL
    CHECK (octet_length(recipient_ciphertext) > 32
       AND substring(recipient_ciphertext FROM 1 FOR 4) = convert_to('ECP1','UTF8')),
  delivery_config_revision_id uuid NOT NULL,
  requested_by_membership_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'queued'
    CHECK (status IN ('queued','sending','sent','failed','uncertain')),
  attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count BETWEEN 0 AND 5),
  next_attempt_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  lease_expires_at timestamptz,
  last_failure_code text,
  provider_message_reference text,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  sent_at timestamptz,
  UNIQUE (organization_id,id),
  UNIQUE (organization_id,idempotency_key_sha256),
  FOREIGN KEY (organization_id,offer_id)
    REFERENCES eogp.booking_offers(organization_id,id),
  FOREIGN KEY (organization_id,offer_revision_id)
    REFERENCES eogp.booking_offer_revisions(organization_id,id),
  FOREIGN KEY (organization_id,delivery_config_revision_id)
    REFERENCES eogp.organization_delivery_config_revisions(organization_id,id),
  FOREIGN KEY (organization_id,requested_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id,id),
  CHECK ((status='sending') = (lease_expires_at IS NOT NULL)),
  CHECK ((status='sent') = (sent_at IS NOT NULL))
);

CREATE INDEX booking_offer_email_delivery_ready_idx
  ON eogp.booking_offer_email_deliveries(organization_id,next_attempt_at,created_at)
  WHERE status='queued';

ALTER TABLE eogp.booking_offer_email_deliveries ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.booking_offer_email_deliveries FORCE ROW LEVEL SECURITY;
CREATE POLICY booking_offer_email_delivery_tenant
  ON eogp.booking_offer_email_deliveries
  USING (organization_id=eogp.current_organization_id())
  WITH CHECK (organization_id=eogp.current_organization_id());
REVOKE ALL ON eogp.booking_offer_email_deliveries
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

CREATE TABLE eogp.booking_offer_email_delivery_tenant_queue (
  organization_id uuid PRIMARY KEY REFERENCES eogp.organizations(id),
  available_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
REVOKE ALL ON eogp.booking_offer_email_delivery_tenant_queue
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
GRANT SELECT ON eogp.booking_offer_email_delivery_tenant_queue TO eventor_worker;

CREATE FUNCTION eogp.queue_booking_offer_email_delivery(
  p_organization_id uuid,
  p_offer_id uuid,
  p_actor_membership_id uuid,
  p_idempotency_key_sha256 text,
  p_capability_token_sha256 text,
  p_capability_ciphertext bytea
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_revision eogp.booking_offer_revisions%ROWTYPE;
  v_delivery_config_revision_id uuid;
  v_recipient_ciphertext bytea;
  v_existing eogp.booking_offer_email_deliveries%ROWTYPE;
  v_delivery_id uuid;
  v_created boolean := false;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  IF p_idempotency_key_sha256 IS NULL OR p_idempotency_key_sha256 !~ '^[0-9a-f]{64}$'
     OR p_capability_token_sha256 IS NULL OR p_capability_token_sha256 !~ '^[0-9a-f]{64}$'
     OR p_capability_ciphertext IS NULL OR octet_length(p_capability_ciphertext)<=32
     OR substring(p_capability_ciphertext FROM 1 FOR 4)<>convert_to('ECP1','UTF8') THEN
    RAISE EXCEPTION 'invalid offer email delivery request' USING ERRCODE='22023';
  END IF;

  SELECT revision.* INTO v_revision
    FROM eogp.booking_offers offer
    JOIN eogp.booking_offer_revisions revision
      ON revision.organization_id=offer.organization_id AND revision.offer_id=offer.id
   WHERE offer.organization_id=p_organization_id AND offer.id=p_offer_id
     AND offer.status='issued' AND revision.state='issued'
     AND revision.revision_number=(
       SELECT max(latest.revision_number)
         FROM eogp.booking_offer_revisions latest
        WHERE latest.organization_id=p_organization_id AND latest.offer_id=p_offer_id
     )
   FOR UPDATE OF offer,revision;
  IF NOT FOUND OR v_revision.valid_until IS NULL OR v_revision.valid_until<=clock_timestamp() THEN
    RAISE EXCEPTION 'only a current, unexpired issued offer can be emailed' USING ERRCODE='55000';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM eogp.external_action_capabilities capability
     WHERE capability.organization_id=p_organization_id
       AND capability.offer_revision_id=v_revision.id
       AND capability.action_code='offer_accept'
       AND capability.token_sha256=p_capability_token_sha256
       AND capability.revoked_at IS NULL
       AND capability.expires_at>clock_timestamp()
       AND capability.use_count<capability.max_uses
  ) THEN
    RAISE EXCEPTION 'the supplied customer review capability is not active for this offer revision'
      USING ERRCODE='42501';
  END IF;

  SELECT inquiry.requester_email_ciphertext INTO v_recipient_ciphertext
    FROM eogp.booking_offers offer
    JOIN eogp.booking_drafts draft
      ON draft.organization_id=offer.organization_id AND draft.id=offer.draft_id
    JOIN eogp.booking_inquiries inquiry
      ON inquiry.organization_id=draft.organization_id AND inquiry.id=draft.source_inquiry_id
   WHERE offer.organization_id=p_organization_id AND offer.id=p_offer_id;
  IF v_recipient_ciphertext IS NULL
     OR octet_length(v_recipient_ciphertext)<=32
     OR substring(v_recipient_ciphertext FROM 1 FOR 4)<>convert_to('ECP1','UTF8') THEN
    RAISE EXCEPTION 'the source inquiry has no usable encrypted email address' USING ERRCODE='55000';
  END IF;

  SELECT head.revision_id INTO v_delivery_config_revision_id
    FROM eogp.organization_delivery_config_heads head
    JOIN eogp.organization_delivery_config_revisions config
      ON config.organization_id=head.organization_id AND config.id=head.revision_id
   WHERE head.organization_id=p_organization_id AND head.channel='email'
     AND head.delivery_enabled=true AND config.provider='smtp'
     AND (config.settings->>'authMode'<>'password' OR config.credentials_ciphertext IS NOT NULL);
  IF v_delivery_config_revision_id IS NULL THEN
    RAISE EXCEPTION 'organization SMTP delivery is not enabled; send a successful test email first'
      USING ERRCODE='55000';
  END IF;

  INSERT INTO eogp.booking_offer_email_deliveries(
    organization_id,offer_id,offer_revision_id,idempotency_key_sha256,
    capability_token_sha256,capability_ciphertext,recipient_ciphertext,
    delivery_config_revision_id,requested_by_membership_id
  ) VALUES (
    p_organization_id,p_offer_id,v_revision.id,p_idempotency_key_sha256,
    p_capability_token_sha256,p_capability_ciphertext,v_recipient_ciphertext,
    v_delivery_config_revision_id,p_actor_membership_id
  )
  ON CONFLICT (organization_id,idempotency_key_sha256) DO NOTHING
  RETURNING id INTO v_delivery_id;
  IF v_delivery_id IS NOT NULL THEN
    v_created := true;
  ELSE
    SELECT * INTO v_existing
      FROM eogp.booking_offer_email_deliveries
     WHERE organization_id=p_organization_id
       AND idempotency_key_sha256=p_idempotency_key_sha256
     FOR UPDATE;
    IF v_existing.offer_id IS DISTINCT FROM p_offer_id
       OR v_existing.offer_revision_id IS DISTINCT FROM v_revision.id
       OR v_existing.capability_token_sha256 IS DISTINCT FROM p_capability_token_sha256 THEN
      RAISE EXCEPTION 'idempotency key already used for a different offer email' USING ERRCODE='23505';
    END IF;
    v_delivery_id := v_existing.id;
  END IF;

  IF v_created THEN
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
      'booking.offer.email_queued','booking_offer',p_offer_id,
      jsonb_build_object('offerRevisionId',v_revision.id,'deliveryId',v_delivery_id,
        'deliveryConfigRevisionId',v_delivery_config_revision_id)
    );
  END IF;

  RETURN jsonb_build_object(
    'deliveryId',v_delivery_id,
    'offerId',p_offer_id,
    'offerRevisionId',v_revision.id,
    'status',coalesce(v_existing.status,'queued'),
    'created',v_created
  );
END;
$function$;

CREATE FUNCTION eogp.discover_pending_booking_offer_email_tenants()
RETURNS TABLE(organization_id uuid)
LANGUAGE plpgsql
SET search_path=pg_catalog,eogp
AS $function$
BEGIN
  IF session_user<>'eventor_worker' THEN
    RAISE EXCEPTION 'offer email discovery requires eventor_worker' USING ERRCODE='42501';
  END IF;
  RETURN QUERY
    SELECT queue.organization_id
      FROM eogp.booking_offer_email_delivery_tenant_queue queue
     WHERE queue.available_at<=clock_timestamp()
     ORDER BY queue.available_at,queue.organization_id
     LIMIT 1000;
END;
$function$;

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

  UPDATE eogp.booking_offer_email_deliveries
     SET status='uncertain',lease_expires_at=NULL,
         last_failure_code='SMTP_UNKNOWN',updated_at=clock_timestamp()
   WHERE organization_id=p_organization_id AND status='sending'
     AND lease_expires_at<=clock_timestamp();

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
         config.settings->>'replyTo',revision.valid_until,revision.currency,revision.total_amount
    FROM eogp.organization_delivery_config_revisions config
    JOIN eogp.booking_offer_revisions revision
      ON revision.organization_id=v_delivery.organization_id
     AND revision.id=v_delivery.offer_revision_id
   WHERE config.organization_id=p_organization_id
     AND config.id=v_delivery.delivery_config_revision_id;
END;
$function$;

CREATE FUNCTION eogp.complete_booking_offer_email_delivery(
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

  RETURN jsonb_build_object(
    'deliveryId',p_delivery_id,
    'status',CASE WHEN p_outcome='sent' THEN 'sent'
                  WHEN p_outcome='uncertain' THEN 'uncertain'
                  WHEN v_retry THEN 'queued' ELSE 'failed' END,
    'retryScheduled',p_outcome='failed' AND v_retry
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.queue_booking_offer_email_delivery(uuid,uuid,uuid,text,text,bytea)
  FROM PUBLIC,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.discover_pending_booking_offer_email_tenants()
  FROM PUBLIC,eventor_runtime,eventor_auth;
REVOKE ALL ON FUNCTION eogp.claim_booking_offer_email_delivery(uuid),
  eogp.complete_booking_offer_email_delivery(uuid,uuid,text,text,text)
  FROM PUBLIC,eventor_runtime,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.queue_booking_offer_email_delivery(uuid,uuid,uuid,text,text,bytea)
  TO eventor_runtime;
GRANT EXECUTE ON FUNCTION eogp.discover_pending_booking_offer_email_tenants(),
  eogp.claim_booking_offer_email_delivery(uuid),
  eogp.complete_booking_offer_email_delivery(uuid,uuid,text,text,text)
  TO eventor_worker;
