-- Include the current booking revision in the authorized cancellation
-- request detail projection so the staff workspace can use optimistic
-- concurrency for preview and execution.
CREATE OR REPLACE FUNCTION eogp.get_booking_cancellation_requests_for_booking(
  p_organization_id uuid,
  p_booking_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_member_status text;
  v_items jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id
     OR nullif(current_setting('app.actor_membership_id',true),'')::uuid
          IS DISTINCT FROM p_actor_membership_id THEN
    RAISE EXCEPTION 'booking cancellation actor context mismatch' USING ERRCODE='42501';
  END IF;

  SELECT status INTO v_member_status
    FROM eogp.organization_memberships
   WHERE organization_id=p_organization_id AND id=p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_member_status<>'active' THEN
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
     AND role_permission.permission_code IN ('booking.cancellation.review','booking.cancellation.approve')
     AND (
       user_grant.scope_kind='organization'
       OR (user_grant.scope_kind='booking' AND user_grant.scope_booking_id=p_booking_id)
     )
   FOR SHARE OF user_grant,role_permission;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking cancellation review or approval permission is required for this booking'
      USING ERRCODE='42501';
  END IF;

  SELECT coalesce(jsonb_agg(item ORDER BY item->>'requestedAt' DESC,item->>'requestId'),'[]'::jsonb)
    INTO v_items
    FROM (
      SELECT jsonb_build_object(
        'requestId',request.id,
        'bookingId',request.booking_id,
        'bookingRevision',booking.revision_number,
        'requesterKind',request.requester_kind,
        'status',request.status,
        'reasonCode',request.reason_code,
        'explanationCiphertextBase64',CASE
          WHEN request.explanation_ciphertext IS NULL THEN NULL
          ELSE encode(request.explanation_ciphertext,'base64') END,
        'requestedAt',request.requested_at,
        'resolvedAt',request.resolved_at,
        'policyRevisionId',snapshot.cancellation_policy_revision_id,
        'decisions',coalesce((
          SELECT jsonb_agg(jsonb_build_object(
            'decision',decision.decision,
            'reason',decision.reason,
            'decidedAt',decision.decided_at
          ) ORDER BY decision.decided_at,decision.id)
          FROM eogp.booking_cancellation_decisions decision
          WHERE decision.organization_id=request.organization_id
            AND decision.booking_id=request.booking_id
            AND decision.cancellation_request_id=request.id
        ),'[]'::jsonb)
      ) AS item
      FROM eogp.booking_cancellation_requests request
      JOIN eogp.booking_records booking
        ON booking.organization_id=request.organization_id
       AND booking.id=request.booking_id
      LEFT JOIN eogp.booking_confirmed_snapshots snapshot
        ON snapshot.organization_id=request.organization_id
       AND snapshot.booking_id=request.booking_id
      WHERE request.organization_id=p_organization_id
        AND request.booking_id=p_booking_id
    ) page;
  RETURN v_items;
END;
$function$;
