-- Hash-only cross-tenant lookup for anonymous, purpose-bound offer capabilities.
-- The index has no RLS because the tenant is unknown until the unguessable token
-- hash is resolved. Direct access is revoked; only narrowly scoped SECURITY DEFINER
-- resolvers may use it.
CREATE TABLE eogp.booking_offer_capability_lookup (
    token_sha256 text PRIMARY KEY CHECK (token_sha256 ~ '^[0-9a-f]{64}$'),
    organization_id uuid NOT NULL,
    capability_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id,capability_id),
    FOREIGN KEY (organization_id,capability_id)
      REFERENCES eogp.external_action_capabilities(organization_id,id)
);

REVOKE ALL ON eogp.booking_offer_capability_lookup
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

CREATE FUNCTION eogp.index_booking_offer_capability()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
BEGIN
  IF NEW.action_code='offer_accept' AND NEW.offer_revision_id IS NOT NULL THEN
    INSERT INTO eogp.booking_offer_capability_lookup (
      token_sha256,organization_id,capability_id
    ) VALUES (
      NEW.token_sha256,NEW.organization_id,NEW.id
    );
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER booking_offer_capability_lookup_insert
  AFTER INSERT ON eogp.external_action_capabilities
  FOR EACH ROW EXECUTE FUNCTION eogp.index_booking_offer_capability();

-- Populate the private lookup for any offer capabilities created before
-- this migration is applied (for example, during staged deployment/replay).
INSERT INTO eogp.booking_offer_capability_lookup (
  token_sha256,organization_id,capability_id
)
SELECT capability.token_sha256,capability.organization_id,capability.id
  FROM eogp.external_action_capabilities capability
 WHERE capability.action_code='offer_accept'
   AND capability.offer_revision_id IS NOT NULL
ON CONFLICT (token_sha256) DO NOTHING;

REVOKE ALL ON FUNCTION eogp.index_booking_offer_capability()
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

CREATE OR REPLACE FUNCTION eogp.resolve_booking_offer_capability(
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
  SELECT jsonb_build_object(
    'organizationId',capability.organization_id,
    'offerId',revision.offer_id,
    'offerRevisionId',revision.id
  )
    INTO v_result
    FROM eogp.external_action_capabilities capability
    JOIN eogp.booking_offer_revisions revision
      ON revision.organization_id=capability.organization_id
     AND revision.id=capability.offer_revision_id
   WHERE capability.organization_id=v_organization_id
     AND capability.id=v_capability_id
     AND capability.token_sha256=p_token_sha256
     AND capability.action_code='offer_accept'
     AND revision.offer_id=p_offer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking offer capability not found'
      USING ERRCODE = 'P0002';
  END IF;
  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.resolve_booking_offer_capability(uuid,text)
  FROM PUBLIC,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.resolve_booking_offer_capability(uuid,text)
  TO eventor_runtime;

CREATE OR REPLACE FUNCTION eogp.decide_booking_offer_with_capability(
  p_offer_id uuid,
  p_token_sha256 text,
  p_decision text,
  p_idempotency_key_sha256 text,
  p_request_sha256 text,
  p_acceptance_name_ciphertext bytea,
  p_customer_note_ciphertext bytea,
  p_reason_code text,
  p_reason_ciphertext bytea
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_capability eogp.external_action_capabilities%ROWTYPE;
  v_organization_id uuid;
  v_capability_id uuid;
  v_offer eogp.booking_offers%ROWTYPE;
  v_revision eogp.booking_offer_revisions%ROWTYPE;
  v_latest_revision_id uuid;
  v_existing_request_sha256 text;
  v_existing_response jsonb;
  v_result jsonb;
  v_now timestamptz := clock_timestamp();
BEGIN
  IF p_offer_id IS NULL
     OR p_token_sha256 IS NULL OR p_token_sha256 !~ '^[0-9a-f]{64}$'
     OR p_idempotency_key_sha256 IS NULL OR p_idempotency_key_sha256 !~ '^[0-9a-f]{64}$'
     OR p_request_sha256 IS NULL OR p_request_sha256 !~ '^[0-9a-f]{64}$'
     OR p_decision NOT IN ('accepted','rejected') THEN
    RAISE EXCEPTION 'invalid external offer decision request'
      USING ERRCODE = '22023';
  END IF;

  IF p_decision = 'accepted' THEN
    IF p_reason_code IS NOT NULL OR p_reason_ciphertext IS NOT NULL THEN
      RAISE EXCEPTION 'acceptance cannot include a rejection reason'
        USING ERRCODE = '22023';
    END IF;
  ELSE
    IF p_reason_code IS NULL OR length(btrim(p_reason_code)) NOT BETWEEN 2 AND 100
       OR p_reason_ciphertext IS NULL OR octet_length(p_reason_ciphertext) <= 32
       OR substring(p_reason_ciphertext FROM 1 FOR 4) <> convert_to('ECP1','UTF8') THEN
      RAISE EXCEPTION 'a rejection reason and encrypted explanation are required'
        USING ERRCODE = '22023';
    END IF;
    IF p_acceptance_name_ciphertext IS NOT NULL THEN
      RAISE EXCEPTION 'rejection cannot include an acceptance name'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  IF p_acceptance_name_ciphertext IS NOT NULL
     AND (octet_length(p_acceptance_name_ciphertext) <= 32
          OR substring(p_acceptance_name_ciphertext FROM 1 FOR 4) <> convert_to('ECP1','UTF8')) THEN
    RAISE EXCEPTION 'acceptance name must use the ECP1 encrypted envelope'
      USING ERRCODE = '22023';
  END IF;
  IF p_customer_note_ciphertext IS NOT NULL
     AND (octet_length(p_customer_note_ciphertext) <= 32
          OR substring(p_customer_note_ciphertext FROM 1 FOR 4) <> convert_to('ECP1','UTF8')) THEN
    RAISE EXCEPTION 'customer note must use the ECP1 encrypted envelope'
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

  SELECT capability.*
    INTO v_capability
    FROM eogp.external_action_capabilities capability
   WHERE capability.organization_id=v_organization_id
     AND capability.id=v_capability_id
     AND capability.token_sha256=p_token_sha256
     AND capability.action_code='offer_accept'
     AND capability.offer_revision_id IS NOT NULL
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking offer capability not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM eogp.booking_offer_revisions revision
     WHERE revision.organization_id = v_capability.organization_id
       AND revision.id = v_capability.offer_revision_id
       AND revision.offer_id = p_offer_id
  ) THEN
    RAISE EXCEPTION 'booking offer capability does not match this offer'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT record.request_sha256,record.response_body
    INTO v_existing_request_sha256,v_existing_response
    FROM eogp.booking_offer_capability_idempotency record
   WHERE record.organization_id = v_capability.organization_id
     AND record.capability_id = v_capability.id
     AND record.idempotency_key_sha256 = p_idempotency_key_sha256
   FOR UPDATE;
  IF FOUND THEN
    IF v_existing_request_sha256 <> p_request_sha256 THEN
      RAISE EXCEPTION 'customer decision idempotency key was reused with a different request'
        USING ERRCODE = '55000';
    END IF;
    RETURN jsonb_set(v_existing_response,'{replayed}','true'::jsonb,true);
  END IF;

  IF v_capability.revoked_at IS NOT NULL
     OR v_capability.expires_at <= v_now
     OR v_capability.use_count >= v_capability.max_uses THEN
    RAISE EXCEPTION 'booking offer capability is expired, revoked or already used'
      USING ERRCODE = '55000';
  END IF;

  SELECT offer.*
    INTO v_offer
    FROM eogp.booking_offers offer
   WHERE offer.organization_id = v_capability.organization_id
     AND offer.id = p_offer_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking offer not found'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT revision.id
    INTO v_latest_revision_id
    FROM eogp.booking_offer_revisions revision
   WHERE revision.organization_id = v_capability.organization_id
     AND revision.offer_id = p_offer_id
   ORDER BY revision.revision_number DESC
   LIMIT 1;
  IF v_latest_revision_id IS DISTINCT FROM v_capability.offer_revision_id THEN
    RAISE EXCEPTION 'this offer revision has been superseded'
      USING ERRCODE = '55000';
  END IF;

  SELECT revision.*
    INTO v_revision
    FROM eogp.booking_offer_revisions revision
   WHERE revision.organization_id = v_capability.organization_id
     AND revision.id = v_capability.offer_revision_id
     AND revision.offer_id = p_offer_id
   FOR UPDATE;
  IF NOT FOUND OR v_revision.state <> 'issued' OR v_offer.status <> 'issued' THEN
    RAISE EXCEPTION 'booking offer is not awaiting a customer decision'
      USING ERRCODE = '55000';
  END IF;

  IF v_revision.valid_until IS NOT NULL AND v_revision.valid_until <= v_now THEN
    RAISE EXCEPTION 'booking offer has expired'
      USING ERRCODE = '55000';
  END IF;

  UPDATE eogp.booking_offer_revisions
     SET state = p_decision,
         accepted_at = CASE WHEN p_decision = 'accepted' THEN v_now ELSE NULL END
   WHERE organization_id = v_capability.organization_id
     AND id = v_revision.id;

  UPDATE eogp.booking_offers
     SET status = p_decision
   WHERE organization_id = v_capability.organization_id
     AND id = p_offer_id;

  UPDATE eogp.external_action_capabilities
     SET use_count = use_count + 1,
         revoked_at = v_now
   WHERE organization_id = v_capability.organization_id
     AND id = v_capability.id;

  INSERT INTO eogp.booking_offer_decision_history (
    organization_id,offer_id,offer_revision_id,decision,actor_kind,
    external_capability_id,reason_code,reason_ciphertext,
    customer_name_ciphertext,customer_note_ciphertext,occurred_at
  ) VALUES (
    v_capability.organization_id,p_offer_id,v_revision.id,p_decision,'external_capability',
    v_capability.id,p_reason_code,p_reason_ciphertext,
    p_acceptance_name_ciphertext,p_customer_note_ciphertext,v_now
  );

  INSERT INTO eogp.audit_events (
    organization_id,actor_external_capability_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata,occurred_at
  ) VALUES (
    v_capability.organization_id,v_capability.id,'external_capability',
    CASE WHEN p_decision = 'accepted' THEN 'booking.offer.accepted' ELSE 'booking.offer.rejected' END,
    'booking_offer',p_offer_id,
    CASE WHEN p_decision = 'accepted' THEN 'customer_accepted_offer' ELSE p_reason_code END,
    jsonb_build_object('offerRevisionId',v_revision.id,'decision',p_decision),
    v_now
  );

  v_result := jsonb_build_object(
    'offerId',p_offer_id,
    'offerRevisionId',v_revision.id,
    'decision',p_decision,
    'decidedAt',v_now,
    'replayed',false
  );

  INSERT INTO eogp.booking_offer_capability_idempotency (
    organization_id,capability_id,idempotency_key_sha256,request_sha256,response_body
  ) VALUES (
    v_capability.organization_id,v_capability.id,p_idempotency_key_sha256,p_request_sha256,v_result
  );

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.decide_booking_offer_with_capability(
  uuid,text,text,text,text,bytea,bytea,text,bytea
) FROM PUBLIC,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.decide_booking_offer_with_capability(
  uuid,text,text,text,text,bytea,bytea,text,bytea
) TO eventor_runtime;
