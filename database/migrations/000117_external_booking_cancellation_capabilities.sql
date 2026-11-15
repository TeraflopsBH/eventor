-- Purpose-bound customer cancellation/status capabilities.
-- Bearer tokens are looked up by hash only; direct access to the lookup and
-- idempotency tables is never granted to application roles.
CREATE TABLE eogp.external_booking_action_capability_lookup (
  token_sha256 text PRIMARY KEY CHECK (token_sha256 ~ '^[0-9a-f]{64}$'),
  organization_id uuid NOT NULL,
  capability_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id,capability_id),
  FOREIGN KEY (organization_id,capability_id)
    REFERENCES eogp.external_action_capabilities(organization_id,id)
);

REVOKE ALL ON eogp.external_booking_action_capability_lookup
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

CREATE FUNCTION eogp.index_external_booking_action_capability()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
BEGIN
  IF NEW.action_code IN ('booking_cancellation_request','booking_cancellation_status')
     AND NEW.booking_id IS NOT NULL THEN
    INSERT INTO eogp.external_booking_action_capability_lookup(
      token_sha256,organization_id,capability_id
    ) VALUES(NEW.token_sha256,NEW.organization_id,NEW.id);
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER external_booking_action_capability_lookup_insert
  AFTER INSERT ON eogp.external_action_capabilities
  FOR EACH ROW EXECUTE FUNCTION eogp.index_external_booking_action_capability();

REVOKE ALL ON FUNCTION eogp.index_external_booking_action_capability()
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

CREATE TABLE eogp.booking_cancellation_capability_idempotency (
  organization_id uuid NOT NULL,
  capability_id uuid NOT NULL,
  idempotency_key_sha256 text NOT NULL CHECK (idempotency_key_sha256 ~ '^[0-9a-f]{64}$'),
  request_sha256 text NOT NULL CHECK (request_sha256 ~ '^[0-9a-f]{64}$'),
  response_body jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (organization_id,capability_id,idempotency_key_sha256),
  FOREIGN KEY (organization_id,capability_id)
    REFERENCES eogp.external_action_capabilities(organization_id,id)
);

ALTER TABLE eogp.booking_cancellation_capability_idempotency ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.booking_cancellation_capability_idempotency FORCE ROW LEVEL SECURITY;
CREATE POLICY booking_cancellation_capability_idempotency_tenant_isolation
  ON eogp.booking_cancellation_capability_idempotency
  USING (organization_id=eogp.current_organization_id())
  WITH CHECK (organization_id=eogp.current_organization_id());
REVOKE ALL ON eogp.booking_cancellation_capability_idempotency
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

CREATE FUNCTION eogp.issue_external_booking_action_capability(
  p_organization_id uuid,
  p_booking_id uuid,
  p_booking_contact_id uuid,
  p_actor_membership_id uuid,
  p_action_code text,
  p_token_sha256 text,
  p_expires_at timestamptz,
  p_max_uses integer
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_booking_status text;
  v_capability_id uuid:=gen_random_uuid();
  v_now timestamptz:=clock_timestamp();
BEGIN
  PERFORM eogp.assert_booking_cancellation_permission(
    p_organization_id,p_booking_id,p_actor_membership_id,'booking.manage'
  );
  IF p_action_code NOT IN ('booking_cancellation_request','booking_cancellation_status')
     OR p_token_sha256 IS NULL OR p_token_sha256 !~ '^[0-9a-f]{64}$'
     OR p_expires_at IS NULL OR p_expires_at<=v_now
     OR p_expires_at>v_now+interval '180 days'
     OR p_max_uses IS NULL OR p_max_uses NOT BETWEEN 1 AND 20
     OR (p_action_code='booking_cancellation_request' AND p_max_uses<>1) THEN
    RAISE EXCEPTION 'external booking action capability parameters are invalid' USING ERRCODE='22023';
  END IF;

  SELECT status INTO v_booking_status
    FROM eogp.booking_records
   WHERE organization_id=p_organization_id AND id=p_booking_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking not found' USING ERRCODE='P0002';
  END IF;
  IF p_action_code='booking_cancellation_request' AND v_booking_status<>'confirmed' THEN
    RAISE EXCEPTION 'cancellation request capability requires a confirmed booking' USING ERRCODE='55000';
  END IF;

  PERFORM 1
    FROM eogp.booking_party_contacts contact
   WHERE contact.organization_id=p_organization_id
     AND contact.booking_id=p_booking_id
     AND contact.id=p_booking_contact_id
     AND contact.authorized_actions @> ARRAY[p_action_code]::text[]
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking contact is not authorized for this external action' USING ERRCODE='42501';
  END IF;

  -- Issuing a successor link invalidates older links for the same contact/action.
  UPDATE eogp.external_action_capabilities
     SET revoked_at=v_now
   WHERE organization_id=p_organization_id
     AND booking_id=p_booking_id
     AND booking_contact_id=p_booking_contact_id
     AND action_code=p_action_code
     AND revoked_at IS NULL;

  INSERT INTO eogp.external_action_capabilities(
    id,organization_id,booking_id,booking_contact_id,action_code,
    token_sha256,issued_at,expires_at,max_uses,created_by_membership_id
  ) VALUES(
    v_capability_id,p_organization_id,p_booking_id,p_booking_contact_id,p_action_code,
    p_token_sha256,v_now,p_expires_at,p_max_uses,p_actor_membership_id
  );

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata,occurred_at
  ) VALUES(
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.external_action_capability.issued','booking',p_booking_id,
    'external_booking_action_capability_issued',
    jsonb_build_object('capabilityId',v_capability_id,'bookingContactId',p_booking_contact_id,
      'actionCode',p_action_code,'expiresAt',p_expires_at,'maxUses',p_max_uses),v_now
  );

  RETURN jsonb_build_object(
    'capabilityId',v_capability_id,'bookingId',p_booking_id,
    'bookingContactId',p_booking_contact_id,'action',p_action_code,
    'expiresAt',p_expires_at,'maxUses',p_max_uses,'state','active'
  );
END;
$function$;

CREATE FUNCTION eogp.revoke_external_booking_action_capability(
  p_organization_id uuid,
  p_booking_id uuid,
  p_capability_id uuid,
  p_actor_membership_id uuid,
  p_reason text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_capability eogp.external_action_capabilities%ROWTYPE;
  v_now timestamptz:=clock_timestamp();
BEGIN
  PERFORM eogp.assert_booking_cancellation_permission(
    p_organization_id,p_booking_id,p_actor_membership_id,'booking.manage'
  );
  IF p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 3 AND 1000 THEN
    RAISE EXCEPTION 'a revocation reason between 3 and 1000 characters is required' USING ERRCODE='22023';
  END IF;

  SELECT * INTO v_capability
    FROM eogp.external_action_capabilities
   WHERE organization_id=p_organization_id
     AND booking_id=p_booking_id
     AND id=p_capability_id
     AND action_code IN ('booking_cancellation_request','booking_cancellation_status')
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'external booking action capability not found' USING ERRCODE='P0002';
  END IF;

  IF v_capability.revoked_at IS NULL THEN
    UPDATE eogp.external_action_capabilities
       SET revoked_at=v_now
     WHERE organization_id=p_organization_id AND id=p_capability_id;
    INSERT INTO eogp.audit_events(
      organization_id,actor_organization_id,actor_membership_id,actor_kind,
      action,aggregate_type,aggregate_id,reason_code,safe_metadata,occurred_at
    ) VALUES(
      p_organization_id,p_organization_id,p_actor_membership_id,'membership',
      'booking.external_action_capability.revoked','booking',p_booking_id,
      'external_booking_action_capability_revoked',
      jsonb_build_object('capabilityId',p_capability_id,'reason',btrim(p_reason)),v_now
    );
  END IF;

  RETURN jsonb_build_object(
    'capabilityId',p_capability_id,'bookingId',p_booking_id,
    'state','revoked','revokedAt',coalesce(v_capability.revoked_at,v_now)
  );
END;
$function$;

CREATE FUNCTION eogp.resolve_external_booking_action_capability(
  p_token_sha256 text,
  p_action_code text
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
  IF p_token_sha256 IS NULL OR p_token_sha256 !~ '^[0-9a-f]{64}$'
     OR p_action_code NOT IN ('booking_cancellation_request','booking_cancellation_status') THEN
    RAISE EXCEPTION 'invalid external booking action capability' USING ERRCODE='22023';
  END IF;
  SELECT organization_id,capability_id
    INTO v_organization_id,v_capability_id
    FROM eogp.external_booking_action_capability_lookup
   WHERE token_sha256=p_token_sha256;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'external booking action capability not found' USING ERRCODE='P0002';
  END IF;

  PERFORM set_config('app.organization_id',v_organization_id::text,true);
  SELECT jsonb_build_object(
    'organizationId',capability.organization_id,
    'bookingId',booking.id,
    'bookingCode',booking.booking_code,
    'bookingStatus',booking.status,
    'action',capability.action_code,
    'expiresAt',capability.expires_at,
    'cancellationTerms',policy.public_terms,
    'latestCancellationRequest',(
      SELECT jsonb_build_object(
        'requestId',request.id,'status',request.status,
        'requestedAt',request.requested_at,'resolvedAt',request.resolved_at
      )
      FROM eogp.booking_cancellation_requests request
      WHERE request.organization_id=booking.organization_id
        AND request.booking_id=booking.id
      ORDER BY request.requested_at DESC,request.id DESC
      LIMIT 1
    )
  )
    INTO v_result
    FROM eogp.external_action_capabilities capability
    JOIN eogp.booking_records booking
      ON booking.organization_id=capability.organization_id
     AND booking.id=capability.booking_id
    LEFT JOIN eogp.booking_confirmed_snapshots snapshot
      ON snapshot.organization_id=booking.organization_id
     AND snapshot.booking_id=booking.id
    LEFT JOIN eogp.cancellation_policy_revisions policy
      ON policy.organization_id=snapshot.organization_id
     AND policy.id=snapshot.cancellation_policy_revision_id
   WHERE capability.organization_id=v_organization_id
     AND capability.id=v_capability_id
     AND capability.token_sha256=p_token_sha256
     AND capability.action_code=p_action_code
     AND capability.revoked_at IS NULL
     AND capability.expires_at>clock_timestamp()
     AND capability.use_count<capability.max_uses
     AND (p_action_code<>'booking_cancellation_request' OR booking.status='confirmed');
  IF NOT FOUND THEN
    RAISE EXCEPTION 'external booking action capability is expired, revoked or unavailable' USING ERRCODE='55000';
  END IF;
  RETURN v_result;
END;
$function$;

CREATE FUNCTION eogp.submit_external_booking_cancellation_request(
  p_token_sha256 text,
  p_idempotency_key_sha256 text,
  p_request_sha256 text,
  p_reason_code text,
  p_explanation_ciphertext bytea
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
  v_now timestamptz:=clock_timestamp();
  v_result jsonb;
  v_next_use_count integer;
BEGIN
  IF p_token_sha256 IS NULL OR p_token_sha256 !~ '^[0-9a-f]{64}$'
     OR p_idempotency_key_sha256 IS NULL OR p_idempotency_key_sha256 !~ '^[0-9a-f]{64}$'
     OR p_request_sha256 IS NULL OR p_request_sha256 !~ '^[0-9a-f]{64}$'
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

REVOKE ALL ON FUNCTION eogp.issue_external_booking_action_capability(uuid,uuid,uuid,uuid,text,text,timestamptz,integer),
  eogp.revoke_external_booking_action_capability(uuid,uuid,uuid,uuid,text),
  eogp.resolve_external_booking_action_capability(text,text),
  eogp.submit_external_booking_cancellation_request(text,text,text,text,bytea)
  FROM PUBLIC,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.issue_external_booking_action_capability(uuid,uuid,uuid,uuid,text,text,timestamptz,integer),
  eogp.revoke_external_booking_action_capability(uuid,uuid,uuid,uuid,text),
  eogp.resolve_external_booking_action_capability(text,text),
  eogp.submit_external_booking_cancellation_request(text,text,text,text,bytea)
  TO eventor_runtime;
