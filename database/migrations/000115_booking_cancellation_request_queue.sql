-- Read-only, tenant-scoped booking cancellation review queue.
-- Request details intentionally exclude encrypted explanations and contact data.
CREATE FUNCTION eogp.get_booking_cancellation_requests(
  p_organization_id uuid,
  p_actor_membership_id uuid,
  p_status text DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_items jsonb;
  v_total bigint;
BEGIN
  IF nullif(current_setting('app.organization_id', true), '')::uuid
       IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id, p_actor_membership_id, ARRAY['booking.manage']::text[]
  );
  IF p_status IS NOT NULL AND p_status NOT IN
      ('submitted','under_review','approved','rejected','withdrawn','expired','effective') THEN
    RAISE EXCEPTION 'invalid booking cancellation request status' USING ERRCODE = '22023';
  END IF;
  IF p_limit IS NULL OR p_limit < 1 OR p_limit > 100
     OR p_offset IS NULL OR p_offset < 0 OR p_offset > 100000 THEN
    RAISE EXCEPTION 'invalid booking cancellation queue pagination' USING ERRCODE = '22023';
  END IF;

  SELECT count(*)
    INTO v_total
    FROM eogp.booking_cancellation_requests request
   WHERE request.organization_id = p_organization_id
     AND (p_status IS NULL OR request.status = p_status);

  SELECT coalesce(jsonb_agg(item ORDER BY item->>'requestedAt' DESC, item->>'requestId'), '[]'::jsonb)
    INTO v_items
    FROM (
      SELECT jsonb_build_object(
        'requestId', request.id,
        'bookingId', booking.id,
        'bookingCode', booking.booking_code,
        'bookingStatus', booking.status,
        'requesterKind', request.requester_kind,
        'status', request.status,
        'reasonCode', request.reason_code,
        'requestedAt', request.requested_at,
        'resolvedAt', request.resolved_at,
        'policyRevisionId', snapshot.cancellation_policy_revision_id,
        'decisions', coalesce((
          SELECT jsonb_agg(jsonb_build_object(
            'decision', decision.decision,
            'reason', decision.reason,
            'decidedAt', decision.decided_at
          ) ORDER BY decision.decided_at, decision.id)
          FROM eogp.booking_cancellation_decisions decision
          WHERE decision.organization_id = request.organization_id
            AND decision.booking_id = request.booking_id
            AND decision.cancellation_request_id = request.id
        ), '[]'::jsonb)
      ) AS item
      FROM eogp.booking_cancellation_requests request
      JOIN eogp.booking_records booking
        ON booking.organization_id = request.organization_id
       AND booking.id = request.booking_id
      LEFT JOIN eogp.booking_confirmed_snapshots snapshot
        ON snapshot.organization_id = booking.organization_id
       AND snapshot.booking_id = booking.id
      WHERE request.organization_id = p_organization_id
        AND (p_status IS NULL OR request.status = p_status)
      ORDER BY request.requested_at DESC, request.id
      LIMIT p_limit OFFSET p_offset
    ) page;

  RETURN jsonb_build_object(
    'items', v_items,
    'total', v_total,
    'limit', p_limit,
    'offset', p_offset
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.get_booking_cancellation_requests(uuid,uuid,text,integer,integer)
  FROM PUBLIC, eventor_worker, eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.get_booking_cancellation_requests(uuid,uuid,text,integer,integer)
  TO eventor_runtime;
