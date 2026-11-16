-- A consumed request capability remains read-only for the request it
-- created until its original expiry. This makes an ambiguous submission
-- recoverable from the original link; the consumed token can never submit
-- another request. A separate status capability is still issued normally.
CREATE OR REPLACE FUNCTION eogp.resolve_external_booking_action_capability(
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
     OR p_action_code IS NULL
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
        AND request.requester_contact_id=capability.booking_contact_id
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
     AND capability.expires_at>clock_timestamp()
     AND (
       (
         p_action_code='booking_cancellation_status'
         AND capability.revoked_at IS NULL
         AND capability.use_count<capability.max_uses
       )
       OR
       (
         p_action_code='booking_cancellation_request'
         AND (
           (
             capability.revoked_at IS NULL
             AND capability.use_count<capability.max_uses
             AND booking.status='confirmed'
           )
           OR
           (
             capability.use_count>=capability.max_uses
             AND EXISTS (
               SELECT 1
                 FROM eogp.booking_cancellation_requests own_request
                WHERE own_request.organization_id=capability.organization_id
                  AND own_request.booking_id=capability.booking_id
                  AND own_request.external_capability_id=capability.id
             )
           )
         )
       )
     );
  IF NOT FOUND THEN
    RAISE EXCEPTION 'external booking action capability is expired, revoked or unavailable' USING ERRCODE='55000';
  END IF;
  RETURN v_result;
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.get_external_booking_cancellation_request_status(
  p_token_sha256 text,
  p_request_id uuid
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
     OR p_request_id IS NULL THEN
    RAISE EXCEPTION 'invalid external cancellation status request' USING ERRCODE='22023';
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
    'requestId',request.id,
    'bookingCode',booking.booking_code,
    'status',request.status,
    'requestedAt',request.requested_at,
    'resolvedAt',request.resolved_at
  )
    INTO v_result
    FROM eogp.external_action_capabilities capability
    JOIN eogp.booking_cancellation_requests request
      ON request.organization_id=capability.organization_id
     AND request.booking_id=capability.booking_id
     AND request.requester_contact_id=capability.booking_contact_id
    JOIN eogp.booking_records booking
      ON booking.organization_id=request.organization_id
     AND booking.id=request.booking_id
   WHERE capability.organization_id=v_organization_id
     AND capability.id=v_capability_id
     AND capability.token_sha256=p_token_sha256
     AND capability.expires_at>clock_timestamp()
     AND request.id=p_request_id
     AND (
       (
         capability.action_code='booking_cancellation_status'
         AND capability.revoked_at IS NULL
       )
       OR
       (
         capability.action_code='booking_cancellation_request'
         AND capability.use_count>=capability.max_uses
         AND request.external_capability_id=capability.id
       )
     );
  IF NOT FOUND THEN
    RAISE EXCEPTION 'external cancellation status is not available to this capability' USING ERRCODE='P0002';
  END IF;
  RETURN v_result;
END;
$function$;
