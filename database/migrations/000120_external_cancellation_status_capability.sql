-- Return a contact-scoped status capability with each successful external
-- cancellation request. The status token hash is persisted; the raw token is
-- derived by the API and is never written to PostgreSQL.
REVOKE ALL ON FUNCTION eogp.submit_external_booking_cancellation_request(text,text,text,text,bytea)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
DROP FUNCTION eogp.submit_external_booking_cancellation_request(text,text,text,text,bytea);

CREATE FUNCTION eogp.submit_external_booking_cancellation_request(
  p_token_sha256 text,
  p_idempotency_key_sha256 text,
  p_request_sha256 text,
  p_reason_code text,
  p_explanation_ciphertext bytea,
  p_status_token_sha256 text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_organization_id uuid;
  v_capability_id uuid;
  v_capability eogp.external_action_capabilities%ROWTYPE;
  v_booking eogp.booking_records%ROWTYPE;
  v_existing_request_sha256 text;
  v_existing_response jsonb;
  v_request_id uuid:=gen_random_uuid();
  v_status_capability_id uuid:=gen_random_uuid();
  v_now timestamptz:=clock_timestamp();
  v_result jsonb;
  v_next_use_count integer;
BEGIN
  IF p_token_sha256 IS NULL OR p_token_sha256 !~ '^[0-9a-f]{64}$'
     OR p_idempotency_key_sha256 IS NULL OR p_idempotency_key_sha256 !~ '^[0-9a-f]{64}$'
     OR p_request_sha256 IS NULL OR p_request_sha256 !~ '^[0-9a-f]{64}
     OR p_reason_code IS NULL OR length(btrim(p_reason_code)) NOT BETWEEN 2 AND 100
     OR p_reason_code NOT SIMILAR TO '[a-z][a-z0-9_]{1,99}'
     OR (p_explanation_ciphertext IS NOT NULL AND
         (octet_length(p_explanation_ciphertext)>16384
          OR substring(p_explanation_ciphertext FROM 1 FOR 3)<>convert_to('EV1','UTF8'))) THEN
    RAISE EXCEPTION 'external booking cancellation request is invalid' USING ERRCODE='22023';
  END IF;

  SELECT organization_id,capability_id
    INTO v_organization_id,v_capability_id
    FROM eogp.external_booking_action_capability_lookup
   WHERE token_sha256=p_token_sha256;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'external booking action capability not found' USING ERRCODE='P0002';
  END IF;
  PERFORM set_config('app.organization_id',v_organization_id::text,true);

  SELECT * INTO v_capability
    FROM eogp.external_action_capabilities
   WHERE organization_id=v_organization_id
     AND id=v_capability_id
     AND token_sha256=p_token_sha256
     AND action_code='booking_cancellation_request'
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'external booking action capability not found' USING ERRCODE='P0002';
  END IF;

  SELECT request_sha256,response_body
    INTO v_existing_request_sha256,v_existing_response
    FROM eogp.booking_cancellation_capability_idempotency
   WHERE organization_id=v_organization_id
     AND capability_id=v_capability_id
     AND idempotency_key_sha256=p_idempotency_key_sha256
   FOR UPDATE;
  IF FOUND THEN
    IF v_existing_request_sha256<>p_request_sha256 THEN
      RAISE EXCEPTION 'external cancellation idempotency key was reused with a different request' USING ERRCODE='55000';
    END IF;
    IF NOT EXISTS (
      SELECT 1
        FROM eogp.external_action_capabilities status_capability
       WHERE status_capability.organization_id=v_organization_id
         AND status_capability.id=(v_existing_response->>'statusCapabilityId')::uuid
         AND status_capability.token_sha256=p_status_token_sha256
         AND status_capability.action_code='booking_cancellation_status'
         AND status_capability.revoked_at IS NULL
    ) THEN
      RAISE EXCEPTION 'external cancellation status token does not match the original idempotent submission' USING ERRCODE='55000';
    END IF;
    RETURN jsonb_set(v_existing_response,'{replayed}','true'::jsonb,true);
  END IF;

  IF v_capability.revoked_at IS NOT NULL
     OR v_capability.expires_at<=v_now
     OR v_capability.use_count>=v_capability.max_uses THEN
    RAISE EXCEPTION 'external booking action capability is expired, revoked or already used' USING ERRCODE='55000';
  END IF;

  PERFORM 1
    FROM eogp.booking_party_contacts contact
   WHERE contact.organization_id=v_organization_id
     AND contact.booking_id=v_capability.booking_id
     AND contact.id=v_capability.booking_contact_id
     AND contact.authorized_actions @> ARRAY['booking_cancellation_request']::text[]
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'external booking contact is no longer authorized' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_booking
    FROM eogp.booking_records
   WHERE organization_id=v_organization_id AND id=v_capability.booking_id
   FOR UPDATE;
  IF NOT FOUND OR v_booking.status<>'confirmed' THEN
    RAISE EXCEPTION 'booking is no longer eligible for cancellation request' USING ERRCODE='55000';
  END IF;
  IF EXISTS (
    SELECT 1 FROM eogp.booking_cancellation_requests request
     WHERE request.organization_id=v_organization_id
       AND request.booking_id=v_booking.id
       AND request.status IN ('submitted','under_review','approved')
  ) THEN
    RAISE EXCEPTION 'an unresolved cancellation request already exists for this booking' USING ERRCODE='23505';
  END IF;

  INSERT INTO eogp.booking_cancellation_requests(
    id,organization_id,booking_id,requester_kind,requester_contact_id,
    external_capability_id,reason_code,explanation_ciphertext,status,requested_at
  ) VALUES(
    v_request_id,v_organization_id,v_booking.id,'external_contact',
    v_capability.booking_contact_id,v_capability.id,btrim(p_reason_code),
    p_explanation_ciphertext,'submitted',v_now
  );

  v_next_use_count:=v_capability.use_count+1;
  -- Issue a reusable, read-only status capability for this exact
  -- contact/request. The raw token is never stored; the API derives it
  -- deterministically from its server-side capability key and idempotency
  -- tuple so a safe replay can return the same link.
  INSERT INTO eogp.external_action_capabilities(
    id,organization_id,booking_id,booking_contact_id,action_code,
    token_sha256,issued_at,expires_at,max_uses,created_by_membership_id
  ) VALUES(
    v_status_capability_id,v_organization_id,v_booking.id,
    v_capability.booking_contact_id,'booking_cancellation_status',
    p_status_token_sha256,v_now,v_now+interval '30 days',1,
    v_capability.created_by_membership_id
  );

  UPDATE eogp.external_action_capabilities
     SET use_count=v_next_use_count,
         revoked_at=CASE WHEN v_next_use_count>=max_uses THEN v_now ELSE revoked_at END
   WHERE organization_id=v_organization_id AND id=v_capability.id;

  INSERT INTO eogp.audit_events(
    organization_id,actor_external_capability_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata,occurred_at
  ) VALUES(
    v_organization_id,v_capability.id,'external_capability',
    'booking.cancellation.requested','booking_cancellation_request',v_request_id,
    'customer_cancellation_requested',
    jsonb_build_object('bookingId',v_booking.id,'reasonCode',btrim(p_reason_code)),v_now
  );

  v_result:=jsonb_build_object(
    'requestId',v_request_id,'bookingCode',v_booking.booking_code,
    'statusCapabilityId',v_status_capability_id,
    'status','submitted','requestedAt',v_now,'replayed',false
  );
  INSERT INTO eogp.booking_cancellation_capability_idempotency(
    organization_id,capability_id,idempotency_key_sha256,request_sha256,response_body
  ) VALUES(
    v_organization_id,v_capability.id,p_idempotency_key_sha256,p_request_sha256,v_result
  );
  RETURN v_result;
END;
$function$;


     OR p_status_token_sha256 IS NULL OR p_status_token_sha256 !~ '^[0-9a-f]{64}
     OR p_reason_code IS NULL OR length(btrim(p_reason_code)) NOT BETWEEN 2 AND 100
     OR p_reason_code NOT SIMILAR TO '[a-z][a-z0-9_]{1,99}'
     OR (p_explanation_ciphertext IS NOT NULL AND
         (octet_length(p_explanation_ciphertext)>16384
          OR substring(p_explanation_ciphertext FROM 1 FOR 3)<>convert_to('EV1','UTF8'))) THEN
    RAISE EXCEPTION 'external booking cancellation request is invalid' USING ERRCODE='22023';
  END IF;

  SELECT organization_id,capability_id
    INTO v_organization_id,v_capability_id
    FROM eogp.external_booking_action_capability_lookup
   WHERE token_sha256=p_token_sha256;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'external booking action capability not found' USING ERRCODE='P0002';
  END IF;
  PERFORM set_config('app.organization_id',v_organization_id::text,true);

  SELECT * INTO v_capability
    FROM eogp.external_action_capabilities
   WHERE organization_id=v_organization_id
     AND id=v_capability_id
     AND token_sha256=p_token_sha256
     AND action_code='booking_cancellation_request'
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'external booking action capability not found' USING ERRCODE='P0002';
  END IF;

  SELECT request_sha256,response_body
    INTO v_existing_request_sha256,v_existing_response
    FROM eogp.booking_cancellation_capability_idempotency
   WHERE organization_id=v_organization_id
     AND capability_id=v_capability_id
     AND idempotency_key_sha256=p_idempotency_key_sha256
   FOR UPDATE;
  IF FOUND THEN
    IF v_existing_request_sha256<>p_request_sha256 THEN
      RAISE EXCEPTION 'external cancellation idempotency key was reused with a different request' USING ERRCODE='55000';
    END IF;
    RETURN jsonb_set(v_existing_response,'{replayed}','true'::jsonb,true);
  END IF;

  IF v_capability.revoked_at IS NOT NULL
     OR v_capability.expires_at<=v_now
     OR v_capability.use_count>=v_capability.max_uses THEN
    RAISE EXCEPTION 'external booking action capability is expired, revoked or already used' USING ERRCODE='55000';
  END IF;

  PERFORM 1
    FROM eogp.booking_party_contacts contact
   WHERE contact.organization_id=v_organization_id
     AND contact.booking_id=v_capability.booking_id
     AND contact.id=v_capability.booking_contact_id
     AND contact.authorized_actions @> ARRAY['booking_cancellation_request']::text[]
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'external booking contact is no longer authorized' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_booking
    FROM eogp.booking_records
   WHERE organization_id=v_organization_id AND id=v_capability.booking_id
   FOR UPDATE;
  IF NOT FOUND OR v_booking.status<>'confirmed' THEN
    RAISE EXCEPTION 'booking is no longer eligible for cancellation request' USING ERRCODE='55000';
  END IF;
  IF EXISTS (
    SELECT 1 FROM eogp.booking_cancellation_requests request
     WHERE request.organization_id=v_organization_id
       AND request.booking_id=v_booking.id
       AND request.status IN ('submitted','under_review','approved')
  ) THEN
    RAISE EXCEPTION 'an unresolved cancellation request already exists for this booking' USING ERRCODE='23505';
  END IF;

  INSERT INTO eogp.booking_cancellation_requests(
    id,organization_id,booking_id,requester_kind,requester_contact_id,
    external_capability_id,reason_code,explanation_ciphertext,status,requested_at
  ) VALUES(
    v_request_id,v_organization_id,v_booking.id,'external_contact',
    v_capability.booking_contact_id,v_capability.id,btrim(p_reason_code),
    p_explanation_ciphertext,'submitted',v_now
  );

  v_next_use_count:=v_capability.use_count+1;
  UPDATE eogp.external_action_capabilities
     SET use_count=v_next_use_count,
         revoked_at=CASE WHEN v_next_use_count>=max_uses THEN v_now ELSE revoked_at END
   WHERE organization_id=v_organization_id AND id=v_capability.id;

  INSERT INTO eogp.audit_events(
    organization_id,actor_external_capability_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata,occurred_at
  ) VALUES(
    v_organization_id,v_capability.id,'external_capability',
    'booking.cancellation.requested','booking_cancellation_request',v_request_id,
    'customer_cancellation_requested',
    jsonb_build_object('bookingId',v_booking.id,'reasonCode',btrim(p_reason_code)),v_now
  );

  v_result:=jsonb_build_object(
    'requestId',v_request_id,'bookingCode',v_booking.booking_code,
    'status','submitted','requestedAt',v_now,'replayed',false
  );
  INSERT INTO eogp.booking_cancellation_capability_idempotency(
    organization_id,capability_id,idempotency_key_sha256,request_sha256,response_body
  ) VALUES(
    v_organization_id,v_capability.id,p_idempotency_key_sha256,p_request_sha256,v_result
  );
  RETURN v_result;
END;
$function$;


     OR p_reason_code IS NULL OR length(btrim(p_reason_code)) NOT BETWEEN 2 AND 100
     OR p_reason_code NOT SIMILAR TO '[a-z][a-z0-9_]{1,99}'
     OR (p_explanation_ciphertext IS NOT NULL AND
         (octet_length(p_explanation_ciphertext)>16384
          OR substring(p_explanation_ciphertext FROM 1 FOR 3)<>convert_to('EV1','UTF8'))) THEN
    RAISE EXCEPTION 'external booking cancellation request is invalid' USING ERRCODE='22023';
  END IF;

  SELECT organization_id,capability_id
    INTO v_organization_id,v_capability_id
    FROM eogp.external_booking_action_capability_lookup
   WHERE token_sha256=p_token_sha256;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'external booking action capability not found' USING ERRCODE='P0002';
  END IF;
  PERFORM set_config('app.organization_id',v_organization_id::text,true);

  SELECT * INTO v_capability
    FROM eogp.external_action_capabilities
   WHERE organization_id=v_organization_id
     AND id=v_capability_id
     AND token_sha256=p_token_sha256
     AND action_code='booking_cancellation_request'
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'external booking action capability not found' USING ERRCODE='P0002';
  END IF;

  SELECT request_sha256,response_body
    INTO v_existing_request_sha256,v_existing_response
    FROM eogp.booking_cancellation_capability_idempotency
   WHERE organization_id=v_organization_id
     AND capability_id=v_capability_id
     AND idempotency_key_sha256=p_idempotency_key_sha256
   FOR UPDATE;
  IF FOUND THEN
    IF v_existing_request_sha256<>p_request_sha256 THEN
      RAISE EXCEPTION 'external cancellation idempotency key was reused with a different request' USING ERRCODE='55000';
    END IF;
    RETURN jsonb_set(v_existing_response,'{replayed}','true'::jsonb,true);
  END IF;

  IF v_capability.revoked_at IS NOT NULL
     OR v_capability.expires_at<=v_now
     OR v_capability.use_count>=v_capability.max_uses THEN
    RAISE EXCEPTION 'external booking action capability is expired, revoked or already used' USING ERRCODE='55000';
  END IF;

  PERFORM 1
    FROM eogp.booking_party_contacts contact
   WHERE contact.organization_id=v_organization_id
     AND contact.booking_id=v_capability.booking_id
     AND contact.id=v_capability.booking_contact_id
     AND contact.authorized_actions @> ARRAY['booking_cancellation_request']::text[]
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'external booking contact is no longer authorized' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_booking
    FROM eogp.booking_records
   WHERE organization_id=v_organization_id AND id=v_capability.booking_id
   FOR UPDATE;
  IF NOT FOUND OR v_booking.status<>'confirmed' THEN
    RAISE EXCEPTION 'booking is no longer eligible for cancellation request' USING ERRCODE='55000';
  END IF;
  IF EXISTS (
    SELECT 1 FROM eogp.booking_cancellation_requests request
     WHERE request.organization_id=v_organization_id
       AND request.booking_id=v_booking.id
       AND request.status IN ('submitted','under_review','approved')
  ) THEN
    RAISE EXCEPTION 'an unresolved cancellation request already exists for this booking' USING ERRCODE='23505';
  END IF;

  INSERT INTO eogp.booking_cancellation_requests(
    id,organization_id,booking_id,requester_kind,requester_contact_id,
    external_capability_id,reason_code,explanation_ciphertext,status,requested_at
  ) VALUES(
    v_request_id,v_organization_id,v_booking.id,'external_contact',
    v_capability.booking_contact_id,v_capability.id,btrim(p_reason_code),
    p_explanation_ciphertext,'submitted',v_now
  );

  v_next_use_count:=v_capability.use_count+1;
  UPDATE eogp.external_action_capabilities
     SET use_count=v_next_use_count,
         revoked_at=CASE WHEN v_next_use_count>=max_uses THEN v_now ELSE revoked_at END
   WHERE organization_id=v_organization_id AND id=v_capability.id;

  INSERT INTO eogp.audit_events(
    organization_id,actor_external_capability_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata,occurred_at
  ) VALUES(
    v_organization_id,v_capability.id,'external_capability',
    'booking.cancellation.requested','booking_cancellation_request',v_request_id,
    'customer_cancellation_requested',
    jsonb_build_object('bookingId',v_booking.id,'reasonCode',btrim(p_reason_code)),v_now
  );

  v_result:=jsonb_build_object(
    'requestId',v_request_id,'bookingCode',v_booking.booking_code,
    'status','submitted','requestedAt',v_now,'replayed',false
  );
  INSERT INTO eogp.booking_cancellation_capability_idempotency(
    organization_id,capability_id,idempotency_key_sha256,request_sha256,response_body
  ) VALUES(
    v_organization_id,v_capability.id,p_idempotency_key_sha256,p_request_sha256,v_result
  );
  RETURN v_result;
END;
$function$;


REVOKE ALL ON FUNCTION eogp.submit_external_booking_cancellation_request(text,text,text,text,bytea,text)
  FROM PUBLIC,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.submit_external_booking_cancellation_request(text,text,text,text,bytea,text)
  TO eventor_runtime;
