-- Booking cancellation request submission and staff decision commands.
-- Request explanations remain optional ciphertext; no plaintext contact data is projected.
CREATE FUNCTION eogp.assert_booking_cancellation_permission(
  p_organization_id uuid,
  p_booking_id uuid,
  p_actor_membership_id uuid,
  p_permission_code text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_member_status text;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  IF p_permission_code NOT IN (
    'booking.cancellation.request',
    'booking.cancellation.review',
    'booking.cancellation.approve'
  ) THEN
    RAISE EXCEPTION 'unsupported booking cancellation permission' USING ERRCODE='22023';
  END IF;

  SELECT status INTO v_member_status
    FROM eogp.organization_memberships
   WHERE organization_id=p_organization_id
     AND id=p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_member_status <> 'active' THEN
    RAISE EXCEPTION 'active organization membership is required' USING ERRCODE='42501';
  END IF;

  PERFORM 1
    FROM eogp.user_role_grants user_grant
    JOIN eogp.role_permissions role_permission
      ON role_permission.organization_id=user_grant.organization_id
     AND role_permission.role_id=user_grant.role_id
   WHERE user_grant.organization_id=p_organization_id
     AND user_grant.membership_id=p_actor_membership_id
     AND user_grant.revoked_at IS NULL
     AND (user_grant.expires_at IS NULL OR user_grant.expires_at>clock_timestamp())
     AND role_permission.permission_code=p_permission_code
     AND (
       user_grant.scope_kind='organization'
       OR (user_grant.scope_kind='booking' AND user_grant.scope_booking_id=p_booking_id)
     )
   FOR SHARE OF user_grant, role_permission;
  IF NOT FOUND THEN
    RAISE EXCEPTION '% permission is required for this booking',p_permission_code
      USING ERRCODE='42501';
  END IF;
END;
$function$;

CREATE FUNCTION eogp.submit_booking_cancellation_request(
  p_organization_id uuid,
  p_booking_id uuid,
  p_actor_membership_id uuid,
  p_reason_code text,
  p_explanation_ciphertext bytea DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_booking eogp.booking_records%ROWTYPE;
  v_request_id uuid:=gen_random_uuid();
  v_requested_at timestamptz:=clock_timestamp();
BEGIN
  PERFORM eogp.assert_booking_cancellation_permission(
    p_organization_id,p_booking_id,p_actor_membership_id,'booking.cancellation.request'
  );
  IF p_reason_code IS NULL
     OR length(btrim(p_reason_code)) NOT BETWEEN 2 AND 100
     OR p_reason_code NOT SIMILAR TO '[a-z][a-z0-9_]{1,99}'
     OR (p_explanation_ciphertext IS NOT NULL AND octet_length(p_explanation_ciphertext)>16384) THEN
    RAISE EXCEPTION 'cancellation request reason or explanation is invalid' USING ERRCODE='22023';
  END IF;

  SELECT * INTO v_booking
    FROM eogp.booking_records
   WHERE organization_id=p_organization_id AND id=p_booking_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking not found' USING ERRCODE='P0002';
  END IF;
  IF v_booking.status <> 'confirmed' THEN
    RAISE EXCEPTION 'only confirmed bookings may receive a cancellation request' USING ERRCODE='55000';
  END IF;
  IF EXISTS (
    SELECT 1 FROM eogp.booking_cancellation_requests request
     WHERE request.organization_id=p_organization_id
       AND request.booking_id=p_booking_id
       AND request.status IN ('submitted','under_review','approved')
  ) THEN
    RAISE EXCEPTION 'an unresolved cancellation request already exists for this booking' USING ERRCODE='23505';
  END IF;

  INSERT INTO eogp.booking_cancellation_requests(
    id,organization_id,booking_id,requester_kind,requester_membership_id,
    reason_code,explanation_ciphertext,status,requested_at
  ) VALUES (
    v_request_id,p_organization_id,p_booking_id,'organization_member',
    p_actor_membership_id,btrim(p_reason_code),p_explanation_ciphertext,'submitted',v_requested_at
  );

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.cancellation.requested','booking_cancellation_request',v_request_id,
    'booking_cancellation_requested',
    jsonb_build_object('bookingId',p_booking_id,'requesterKind','organization_member','reasonCode',btrim(p_reason_code))
  );

  RETURN jsonb_build_object(
    'requestId',v_request_id,'bookingId',p_booking_id,'status','submitted',
    'reasonCode',btrim(p_reason_code),'requestedAt',v_requested_at
  );
END;
$function$;

CREATE FUNCTION eogp.decide_booking_cancellation_request(
  p_organization_id uuid,
  p_request_id uuid,
  p_actor_membership_id uuid,
  p_decision text,
  p_reason text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_request eogp.booking_cancellation_requests%ROWTYPE;
  v_decision_id uuid:=gen_random_uuid();
  v_decided_at timestamptz:=clock_timestamp();
  v_permission text;
  v_next_status text;
  v_resolved_at timestamptz;
BEGIN
  IF p_decision NOT IN ('approved','rejected','returned_for_changes') THEN
    RAISE EXCEPTION 'unsupported booking cancellation decision' USING ERRCODE='22023';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 3 AND 1000 THEN
    RAISE EXCEPTION 'a decision reason between 3 and 1000 characters is required' USING ERRCODE='22023';
  END IF;

  SELECT * INTO v_request
    FROM eogp.booking_cancellation_requests
   WHERE organization_id=p_organization_id AND id=p_request_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking cancellation request not found' USING ERRCODE='P0002';
  END IF;

  v_permission:=CASE WHEN p_decision='returned_for_changes'
    THEN 'booking.cancellation.review' ELSE 'booking.cancellation.approve' END;
  PERFORM eogp.assert_booking_cancellation_permission(
    p_organization_id,v_request.booking_id,p_actor_membership_id,v_permission
  );

  IF v_request.status NOT IN ('submitted','under_review') THEN
    RAISE EXCEPTION 'only submitted or under-review requests may be decided' USING ERRCODE='55000';
  END IF;

  v_next_status:=CASE WHEN p_decision='returned_for_changes' THEN 'submitted' ELSE p_decision END;
  v_resolved_at:=CASE WHEN p_decision='returned_for_changes' THEN NULL ELSE v_decided_at END;

  INSERT INTO eogp.booking_cancellation_decisions(
    id,organization_id,booking_id,cancellation_request_id,decision,
    actor_membership_id,reason,decided_at
  ) VALUES (
    v_decision_id,p_organization_id,v_request.booking_id,p_request_id,
    p_decision,p_actor_membership_id,btrim(p_reason),v_decided_at
  );

  UPDATE eogp.booking_cancellation_requests
     SET status=v_next_status,resolved_at=v_resolved_at
   WHERE organization_id=p_organization_id AND id=p_request_id;

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.cancellation.request_decided','booking_cancellation_request',p_request_id,
    'booking_cancellation_request_decided',
    jsonb_build_object('bookingId',v_request.booking_id,'decision',p_decision,'nextStatus',v_next_status)
  );

  RETURN jsonb_build_object(
    'requestId',p_request_id,'bookingId',v_request.booking_id,
    'decisionId',v_decision_id,'decision',p_decision,'status',v_next_status,
    'decidedAt',v_decided_at
  );
END;
$function$;

-- All cancellation lifecycle writes must pass through the audited command boundary.
-- Runtime keeps tenant-scoped SELECT access for queue/history projections only.
REVOKE INSERT, UPDATE, DELETE ON
  eogp.booking_cancellation_requests,
  eogp.booking_cancellation_decisions,
  eogp.booking_cancellation_effects,
  eogp.booking_disruption_notices
FROM eventor_runtime, eventor_worker, eventor_auth;

REVOKE ALL ON FUNCTION eogp.assert_booking_cancellation_permission(uuid,uuid,uuid,text)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.submit_booking_cancellation_request(uuid,uuid,uuid,text,bytea)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.decide_booking_cancellation_request(uuid,uuid,uuid,text,text)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.submit_booking_cancellation_request(uuid,uuid,uuid,text,bytea),
  eogp.decide_booking_cancellation_request(uuid,uuid,uuid,text,text)
  TO eventor_runtime;

     OR (p_explanation_ciphertext IS NOT NULL AND octet_length(p_explanation_ciphertext)>16384) THEN
    RAISE EXCEPTION 'cancellation request reason or explanation is invalid' USING ERRCODE='22023';
  END IF;

  SELECT * INTO v_booking
    FROM eogp.booking_records
   WHERE organization_id=p_organization_id AND id=p_booking_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking not found' USING ERRCODE='P0002';
  END IF;
  IF v_booking.status <> 'confirmed' THEN
    RAISE EXCEPTION 'only confirmed bookings may receive a cancellation request' USING ERRCODE='55000';
  END IF;
  IF EXISTS (
    SELECT 1 FROM eogp.booking_cancellation_requests request
     WHERE request.organization_id=p_organization_id
       AND request.booking_id=p_booking_id
       AND request.status IN ('submitted','under_review','approved')
  ) THEN
    RAISE EXCEPTION 'an unresolved cancellation request already exists for this booking' USING ERRCODE='23505';
  END IF;

  INSERT INTO eogp.booking_cancellation_requests(
    id,organization_id,booking_id,requester_kind,requester_membership_id,
    reason_code,explanation_ciphertext,status,requested_at
  ) VALUES (
    v_request_id,p_organization_id,p_booking_id,'organization_member',
    p_actor_membership_id,btrim(p_reason_code),p_explanation_ciphertext,'submitted',v_requested_at
  );

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.cancellation.requested','booking_cancellation_request',v_request_id,
    'booking_cancellation_requested',
    jsonb_build_object('bookingId',p_booking_id,'requesterKind','organization_member','reasonCode',btrim(p_reason_code))
  );

  RETURN jsonb_build_object(
    'requestId',v_request_id,'bookingId',p_booking_id,'status','submitted',
    'reasonCode',btrim(p_reason_code),'requestedAt',v_requested_at
  );
END;
$function$;

CREATE FUNCTION eogp.decide_booking_cancellation_request(
  p_organization_id uuid,
  p_request_id uuid,
  p_actor_membership_id uuid,
  p_decision text,
  p_reason text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_request eogp.booking_cancellation_requests%ROWTYPE;
  v_decision_id uuid:=gen_random_uuid();
  v_decided_at timestamptz:=clock_timestamp();
  v_permission text;
  v_next_status text;
  v_resolved_at timestamptz;
BEGIN
  IF p_decision NOT IN ('approved','rejected','returned_for_changes') THEN
    RAISE EXCEPTION 'unsupported booking cancellation decision' USING ERRCODE='22023';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 3 AND 1000 THEN
    RAISE EXCEPTION 'a decision reason between 3 and 1000 characters is required' USING ERRCODE='22023';
  END IF;

  SELECT * INTO v_request
    FROM eogp.booking_cancellation_requests
   WHERE organization_id=p_organization_id AND id=p_request_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking cancellation request not found' USING ERRCODE='P0002';
  END IF;

  v_permission:=CASE WHEN p_decision='returned_for_changes'
    THEN 'booking.cancellation.review' ELSE 'booking.cancellation.approve' END;
  PERFORM eogp.assert_booking_cancellation_permission(
    p_organization_id,v_request.booking_id,p_actor_membership_id,v_permission
  );

  IF v_request.status NOT IN ('submitted','under_review') THEN
    RAISE EXCEPTION 'only submitted or under-review requests may be decided' USING ERRCODE='55000';
  END IF;

  v_next_status:=CASE WHEN p_decision='returned_for_changes' THEN 'submitted' ELSE p_decision END;
  v_resolved_at:=CASE WHEN p_decision='returned_for_changes' THEN NULL ELSE v_decided_at END;

  INSERT INTO eogp.booking_cancellation_decisions(
    id,organization_id,booking_id,cancellation_request_id,decision,
    actor_membership_id,reason,decided_at
  ) VALUES (
    v_decision_id,p_organization_id,v_request.booking_id,p_request_id,
    p_decision,p_actor_membership_id,btrim(p_reason),v_decided_at
  );

  UPDATE eogp.booking_cancellation_requests
     SET status=v_next_status,resolved_at=v_resolved_at
   WHERE organization_id=p_organization_id AND id=p_request_id;

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.cancellation.request_decided','booking_cancellation_request',p_request_id,
    'booking_cancellation_request_decided',
    jsonb_build_object('bookingId',v_request.booking_id,'decision',p_decision,'nextStatus',v_next_status)
  );

  RETURN jsonb_build_object(
    'requestId',p_request_id,'bookingId',v_request.booking_id,
    'decisionId',v_decision_id,'decision',p_decision,'status',v_next_status,
    'decidedAt',v_decided_at
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.assert_booking_cancellation_permission(uuid,uuid,uuid,text)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.submit_booking_cancellation_request(uuid,uuid,uuid,text,bytea)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.decide_booking_cancellation_request(uuid,uuid,uuid,text,text)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.submit_booking_cancellation_request(uuid,uuid,uuid,text,bytea),
  eogp.decide_booking_cancellation_request(uuid,uuid,uuid,text,text)
  TO eventor_runtime;
