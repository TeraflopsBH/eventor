-- Read-only, tenant-scoped booking cancellation review queue.
-- Request details intentionally exclude encrypted explanations and contact data.
CREATE FUNCTION eogp.assert_booking_cancellation_queue_permission(
  p_organization_id uuid,
  p_actor_membership_id uuid
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
  IF nullif(current_setting('app.actor_membership_id',true),'')::uuid
       IS DISTINCT FROM p_actor_membership_id THEN
    RAISE EXCEPTION 'actor membership context mismatch' USING ERRCODE='42501';
  END IF;
  SELECT status INTO v_member_status
    FROM eogp.organization_memberships
   WHERE organization_id=p_organization_id AND id=p_actor_membership_id
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
     AND user_grant.scope_kind='organization'
     AND user_grant.revoked_at IS NULL
     AND (user_grant.expires_at IS NULL OR user_grant.expires_at>clock_timestamp())
     AND role_permission.permission_code IN ('booking.cancellation.review','booking.cancellation.approve')
   FOR SHARE OF user_grant, role_permission;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking cancellation review or approval permission is required'
      USING ERRCODE='42501';
  END IF;
END;
$function$;

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
  PERFORM eogp.assert_booking_cancellation_queue_permission(
    p_organization_id, p_actor_membership_id
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
     AND ((p_status IS NULL AND request.status IN ('submitted','under_review','approved')) OR request.status = p_status);

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
        AND ((p_status IS NULL AND request.status IN ('submitted','under_review','approved')) OR request.status = p_status)
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

REVOKE ALL ON FUNCTION eogp.assert_booking_cancellation_queue_permission(uuid,uuid),
  eogp.get_booking_cancellation_requests(uuid,uuid,text,integer,integer)
  FROM PUBLIC, eventor_worker, eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.get_booking_cancellation_requests(uuid,uuid,text,integer,integer)
  TO eventor_runtime;
