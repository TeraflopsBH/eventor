-- Complete the staff-approved booking cancellation path. This migration
-- preserves the policy revision pinned at confirmation, uses the existing
-- reservation-release command, and deliberately leaves financial settlement
-- as a recorded manual follow-up rather than moving money.

CREATE OR REPLACE FUNCTION eogp.assert_booking_cancellation_permission(
  p_organization_id uuid,
  p_booking_id uuid,
  p_actor_membership_id uuid,
  p_permission_code text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
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
  IF p_permission_code IS NULL OR p_permission_code NOT IN (
    'booking.manage',
    'booking.cancellation.request',
    'booking.cancellation.review',
    'booking.cancellation.approve',
    'booking.cancellation.execute',
    'booking.cancellation.override'
  ) THEN
    RAISE EXCEPTION 'unsupported booking cancellation permission' USING ERRCODE='22023';
  END IF;

  SELECT status INTO v_member_status
    FROM eogp.organization_memberships
   WHERE organization_id=p_organization_id
     AND id=p_actor_membership_id
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
     AND role_permission.permission_code=p_permission_code
     AND (
       user_grant.scope_kind='organization'
       OR (user_grant.scope_kind='booking' AND user_grant.scope_booking_id=p_booking_id)
     )
   FOR SHARE OF user_grant,role_permission;
  IF NOT FOUND THEN
    RAISE EXCEPTION '% permission is required for this booking',p_permission_code
      USING ERRCODE='42501';
  END IF;
END;
$function$;

-- Customer requests are only valid for policy modes that actually enter the
-- venue review workflow. Self-service requires a separate atomic external
-- execution command and must never silently become a pending request.
CREATE FUNCTION eogp.assert_booking_cancellation_request_policy(
  p_organization_id uuid,
  p_booking_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_customer_mode text;
  v_policy_state text;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;

  SELECT revision.customer_mode,revision.state
    INTO v_customer_mode,v_policy_state
    FROM eogp.booking_confirmed_snapshots snapshot
    JOIN eogp.cancellation_policy_revisions revision
      ON revision.organization_id=snapshot.organization_id
     AND revision.id=snapshot.cancellation_policy_revision_id
   WHERE snapshot.organization_id=p_organization_id
     AND snapshot.booking_id=p_booking_id
   FOR SHARE OF snapshot,revision;
  IF NOT FOUND OR v_policy_state NOT IN ('published','retired') THEN
    RAISE EXCEPTION 'confirmed booking has no published pinned cancellation policy' USING ERRCODE='55000';
  END IF;
  IF v_customer_mode='self_service' THEN
    RAISE EXCEPTION 'self-service cancellation requires the dedicated direct-execution workflow' USING ERRCODE='55000';
  END IF;
  IF v_customer_mode NOT IN ('request_only','approval_required') THEN
    RAISE EXCEPTION 'confirmed booking cancellation policy mode is not supported for requests' USING ERRCODE='55000';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.assert_booking_cancellation_request_policy(uuid,uuid),
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

-- Replace request-id-first authorization with booking-scoped authorization
-- before the request row is looked up or locked.
REVOKE ALL ON FUNCTION eogp.assert_booking_cancellation_request_permission(uuid,uuid,uuid,text)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
DROP FUNCTION eogp.assert_booking_cancellation_request_permission(uuid,uuid,uuid,text);

CREATE FUNCTION eogp.assert_booking_cancellation_request_permission(
  p_organization_id uuid,
  p_booking_id uuid,
  p_request_id uuid,
  p_actor_membership_id uuid,
  p_permission_code text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_cancellation_permission(
    p_organization_id,p_booking_id,p_actor_membership_id,p_permission_code
  );
  PERFORM 1
    FROM eogp.booking_cancellation_requests request
   WHERE request.organization_id=p_organization_id
     AND request.booking_id=p_booking_id
     AND request.id=p_request_id
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking cancellation request not found' USING ERRCODE='P0002';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.decide_booking_cancellation_request(uuid,uuid,uuid,text,text)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
DROP FUNCTION eogp.decide_booking_cancellation_request(uuid,uuid,uuid,text,text);

CREATE FUNCTION eogp.decide_booking_cancellation_request(
  p_organization_id uuid,
  p_booking_id uuid,
  p_request_id uuid,
  p_actor_membership_id uuid,
  p_decision text,
  p_reason text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_request eogp.booking_cancellation_requests%ROWTYPE;
  v_decision_id uuid:=gen_random_uuid();
  v_decided_at timestamptz:=clock_timestamp();
  v_permission text;
  v_next_status text;
  v_resolved_at timestamptz;
BEGIN
  IF p_decision IS NULL OR p_decision NOT IN ('approved','rejected','returned_for_changes') THEN
    RAISE EXCEPTION 'unsupported booking cancellation decision' USING ERRCODE='22023';
  END IF;
  IF p_reason IS NULL OR length(btrim(p_reason)) NOT BETWEEN 3 AND 1000 THEN
    RAISE EXCEPTION 'a decision reason between 3 and 1000 characters is required' USING ERRCODE='22023';
  END IF;

  v_permission:=CASE WHEN p_decision='returned_for_changes'
    THEN 'booking.cancellation.review' ELSE 'booking.cancellation.approve' END;
  PERFORM eogp.assert_booking_cancellation_permission(
    p_organization_id,p_booking_id,p_actor_membership_id,v_permission
  );

  SELECT * INTO v_request
    FROM eogp.booking_cancellation_requests
   WHERE organization_id=p_organization_id
     AND booking_id=p_booking_id
     AND id=p_request_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking cancellation request not found' USING ERRCODE='P0002';
  END IF;
  IF v_request.status NOT IN ('submitted','under_review') THEN
    RAISE EXCEPTION 'only submitted or under-review requests may be decided' USING ERRCODE='55000';
  END IF;

  v_next_status:=CASE WHEN p_decision='returned_for_changes' THEN 'submitted' ELSE p_decision END;
  v_resolved_at:=CASE WHEN p_decision='returned_for_changes' THEN NULL ELSE v_decided_at END;

  INSERT INTO eogp.booking_cancellation_decisions(
    id,organization_id,booking_id,cancellation_request_id,decision,
    actor_membership_id,reason,decided_at
  ) VALUES(
    v_decision_id,p_organization_id,p_booking_id,p_request_id,
    p_decision,p_actor_membership_id,btrim(p_reason),v_decided_at
  );

  UPDATE eogp.booking_cancellation_requests
     SET status=v_next_status,resolved_at=v_resolved_at
   WHERE organization_id=p_organization_id
     AND booking_id=p_booking_id
     AND id=p_request_id;

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.cancellation.request_decided','booking_cancellation_request',p_request_id,
    'booking_cancellation_request_decided',
    jsonb_build_object('bookingId',p_booking_id,'decision',p_decision,'nextStatus',v_next_status)
  );

  RETURN jsonb_build_object(
    'requestId',p_request_id,'bookingId',p_booking_id,
    'decisionId',v_decision_id,'decision',p_decision,'status',v_next_status,
    'decidedAt',v_decided_at
  );
END;
$function$;

CREATE FUNCTION eogp.preview_booking_cancellation(
  p_organization_id uuid,
  p_booking_id uuid,
  p_actor_membership_id uuid,
  p_expected_booking_revision integer,
  p_cancellation_request_id uuid DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_booking eogp.booking_records%ROWTYPE;
  v_snapshot eogp.booking_confirmed_snapshots%ROWTYPE;
  v_policy eogp.cancellation_policy_revisions%ROWTYPE;
  v_request eogp.booking_cancellation_requests%ROWTYPE;
  v_space_ids uuid[];
  v_resource_count bigint;
  v_space_count bigint;
BEGIN
  PERFORM eogp.assert_booking_cancellation_permission(
    p_organization_id,p_booking_id,p_actor_membership_id,'booking.cancellation.review'
  );

  SELECT * INTO v_booking
    FROM eogp.booking_records
   WHERE organization_id=p_organization_id AND id=p_booking_id
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking not found' USING ERRCODE='P0002';
  END IF;
  IF v_booking.status<>'confirmed' THEN
    RAISE EXCEPTION 'only confirmed bookings can be previewed for cancellation' USING ERRCODE='55000';
  END IF;
  IF p_expected_booking_revision IS NULL
     OR p_expected_booking_revision<>v_booking.revision_number THEN
    RAISE EXCEPTION 'booking revision changed; refresh the cancellation preview' USING ERRCODE='40001';
  END IF;

  SELECT * INTO v_snapshot
    FROM eogp.booking_confirmed_snapshots
   WHERE organization_id=p_organization_id AND booking_id=p_booking_id
   FOR SHARE;
  IF NOT FOUND OR v_snapshot.cancellation_policy_revision_id IS NULL THEN
    RAISE EXCEPTION 'confirmed booking has no pinned cancellation policy' USING ERRCODE='55000';
  END IF;

  SELECT * INTO v_policy
    FROM eogp.cancellation_policy_revisions
   WHERE organization_id=p_organization_id
     AND id=v_snapshot.cancellation_policy_revision_id
   FOR SHARE;
  IF NOT FOUND OR v_policy.state NOT IN ('published','retired') THEN
    RAISE EXCEPTION 'pinned cancellation policy revision is unavailable' USING ERRCODE='55000';
  END IF;

  IF p_cancellation_request_id IS NOT NULL THEN
    SELECT * INTO v_request
      FROM eogp.booking_cancellation_requests
     WHERE organization_id=p_organization_id
       AND booking_id=p_booking_id
       AND id=p_cancellation_request_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'booking cancellation request not found' USING ERRCODE='P0002';
    END IF;
  END IF;

  SELECT count(*) FILTER (WHERE active.reservation_kind='resource'),
         count(*) FILTER (WHERE active.reservation_kind='space')
    INTO v_resource_count,v_space_count
    FROM (
      SELECT 'resource'::text AS reservation_kind
        FROM eogp.resource_reservations reservation
       WHERE reservation.organization_id=p_organization_id
         AND reservation.booking_id=p_booking_id
         AND reservation.status IN ('held','confirmed')
         AND reservation.ends_at>clock_timestamp()
      UNION ALL
      SELECT 'space'::text AS reservation_kind
        FROM eogp.venue_space_time_blocks reservation
       WHERE reservation.organization_id=p_organization_id
         AND reservation.booking_id=p_booking_id
         AND reservation.status='confirmed'
         AND reservation.ends_at>clock_timestamp()
    ) active;

  SELECT coalesce(array_agg(reservation.id ORDER BY reservation.id),ARRAY[]::uuid[])
    INTO v_space_ids
    FROM eogp.venue_space_time_blocks reservation
   WHERE reservation.organization_id=p_organization_id
     AND reservation.booking_id=p_booking_id
     AND reservation.status='confirmed'
     AND reservation.ends_at>clock_timestamp();

  RETURN jsonb_build_object(
    'bookingId',p_booking_id,
    'bookingCode',v_booking.booking_code,
    'bookingStatus',v_booking.status,
    'bookingRevision',v_booking.revision_number,
    'cancellationRequestId',p_cancellation_request_id,
    'requestStatus',CASE WHEN p_cancellation_request_id IS NULL THEN NULL ELSE v_request.status END,
    'policyRevisionId',v_policy.id,
    'customerMode',v_policy.customer_mode,
    'publicTerms',v_policy.public_terms,
    'approvalRules',v_policy.approval_rules,
    'commercialRules',v_policy.commercial_rules,
    'noticeRules',v_policy.notice_rules,
    'priceSnapshot',v_snapshot.price_snapshot,
    'reservationRelease',jsonb_build_object(
      'resourceReservationIds',to_jsonb(ARRAY(
        SELECT reservation.id
          FROM eogp.resource_reservations reservation
         WHERE reservation.organization_id=p_organization_id
           AND reservation.booking_id=p_booking_id
           AND reservation.status IN ('held','confirmed')
           AND reservation.ends_at>clock_timestamp()
         ORDER BY reservation.id
      )),
      'spaceReservationIds',to_jsonb(v_space_ids),
      'resourceReservationCount',(
        SELECT count(*) FROM eogp.resource_reservations reservation
         WHERE reservation.organization_id=p_organization_id
           AND reservation.booking_id=p_booking_id
           AND reservation.status IN ('held','confirmed')
           AND reservation.ends_at>clock_timestamp()
      ),
      'spaceReservationCount',v_space_count,
      'totalReservationCount',v_resource_count+v_space_count
    ),
    'commercialEvaluation',jsonb_build_object(
      'state','manual_review_required',
      'automaticFeeCalculation',false,
      'calculatedFee',NULL,
      'moneyMovementExecuted',false,
      'note','The exact confirmed price and pinned commercial rules are preserved. No fee, deposit, refund or credit is inferred or moved automatically.'
    ),
    'selfServiceExecutionAvailable',false
  );
END;
$function$;

CREATE FUNCTION eogp.execute_booking_cancellation(
  p_organization_id uuid,
  p_booking_id uuid,
  p_cancellation_request_id uuid,
  p_actor_membership_id uuid,
  p_expected_booking_revision integer,
  p_reason_code text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_booking eogp.booking_records%ROWTYPE;
  v_request eogp.booking_cancellation_requests%ROWTYPE;
  v_snapshot eogp.booking_confirmed_snapshots%ROWTYPE;
  v_policy eogp.cancellation_policy_revisions%ROWTYPE;
  v_existing_effect eogp.booking_cancellation_effects%ROWTYPE;
  v_reservation_ids uuid[];
  v_reservations_released bigint:=0;
  v_effect_id uuid:=gen_random_uuid();
  v_followup_id uuid:=gen_random_uuid();
  v_now timestamptz:=clock_timestamp();
  v_consequence_snapshot jsonb;
BEGIN
  IF p_reason_code IS NULL OR length(btrim(p_reason_code)) NOT BETWEEN 3 AND 1000 THEN
    RAISE EXCEPTION 'cancellation execution reason must contain 3 to 1000 characters' USING ERRCODE='22023';
  END IF;
  PERFORM eogp.assert_booking_cancellation_permission(
    p_organization_id,p_booking_id,p_actor_membership_id,'booking.cancellation.execute'
  );

  SELECT * INTO v_booking
    FROM eogp.booking_records
   WHERE organization_id=p_organization_id AND id=p_booking_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking not found' USING ERRCODE='P0002';
  END IF;

  -- The booking lock serializes concurrent execution attempts. Re-check the
  -- immutable effect after acquiring it so a racing retry returns the first
  -- committed result instead of failing on the now-cancelled booking.
  SELECT * INTO v_existing_effect
    FROM eogp.booking_cancellation_effects
   WHERE organization_id=p_organization_id AND booking_id=p_booking_id;
  IF FOUND THEN
    IF v_existing_effect.cancellation_request_id<>p_cancellation_request_id THEN
      RAISE EXCEPTION 'booking already has an effective cancellation for another request' USING ERRCODE='55000';
    END IF;
    RETURN jsonb_build_object(
      'bookingId',p_booking_id,'cancellationRequestId',p_cancellation_request_id,
      'effectId',v_existing_effect.id,'effectiveAt',v_existing_effect.effective_at,
      'resourceReleaseCompletedAt',v_existing_effect.resource_release_completed_at,
      'replayed',true
    );
  END IF;

  IF v_booking.status<>'confirmed' THEN
    RAISE EXCEPTION 'only confirmed bookings can be effectively cancelled' USING ERRCODE='55000';
  END IF;
  IF p_expected_booking_revision IS NULL
     OR p_expected_booking_revision<>v_booking.revision_number THEN
    RAISE EXCEPTION 'booking revision changed; refresh the cancellation preview' USING ERRCODE='40001';
  END IF;

  SELECT * INTO v_request
    FROM eogp.booking_cancellation_requests
   WHERE organization_id=p_organization_id
     AND booking_id=p_booking_id
     AND id=p_cancellation_request_id
   FOR UPDATE;
  IF NOT FOUND OR v_request.status<>'approved' THEN
    RAISE EXCEPTION 'an approved cancellation request for this booking is required' USING ERRCODE='55000';
  END IF;

  SELECT * INTO v_snapshot
    FROM eogp.booking_confirmed_snapshots
   WHERE organization_id=p_organization_id AND booking_id=p_booking_id
   FOR SHARE;
  IF NOT FOUND OR v_snapshot.cancellation_policy_revision_id IS NULL THEN
    RAISE EXCEPTION 'confirmed booking has no pinned cancellation policy' USING ERRCODE='55000';
  END IF;
  SELECT * INTO v_policy
    FROM eogp.cancellation_policy_revisions
   WHERE organization_id=p_organization_id
     AND id=v_snapshot.cancellation_policy_revision_id
   FOR SHARE;
  IF NOT FOUND OR v_policy.state<>'published' THEN
    RAISE EXCEPTION 'pinned cancellation policy revision is unavailable' USING ERRCODE='55000';
  END IF;
  IF v_policy.customer_mode='self_service' THEN
    RAISE EXCEPTION 'self-service policy must use the dedicated customer execution workflow' USING ERRCODE='55000';
  END IF;

  SELECT coalesce(array_agg(reservation_id ORDER BY reservation_id),ARRAY[]::uuid[])
    INTO v_reservation_ids
    FROM (
      SELECT reservation.id AS reservation_id
        FROM eogp.resource_reservations reservation
       WHERE reservation.organization_id=p_organization_id
         AND reservation.booking_id=p_booking_id
         AND reservation.status IN ('held','confirmed')
         AND reservation.ends_at>v_now
      UNION
      SELECT reservation.id AS reservation_id
        FROM eogp.venue_space_time_blocks reservation
       WHERE reservation.organization_id=p_organization_id
         AND reservation.booking_id=p_booking_id
         AND reservation.status='confirmed'
         AND reservation.ends_at>v_now
    ) reservations;

  UPDATE eogp.booking_records
     SET status='cancelled',cancelled_at=v_now,revision_number=revision_number+1
   WHERE organization_id=p_organization_id AND id=p_booking_id;

  UPDATE eogp.booking_cancellation_requests
     SET status='effective',resolved_at=v_now
   WHERE organization_id=p_organization_id
     AND booking_id=p_booking_id
     AND id=p_cancellation_request_id;

  IF cardinality(v_reservation_ids)>0 THEN
    v_reservations_released:=eogp.release_booking_reservations(
      p_organization_id,p_booking_id,v_reservation_ids,
      p_actor_membership_id,btrim(p_reason_code)
    );
  END IF;

  INSERT INTO eogp.booking_status_history(
    organization_id,booking_id,previous_status,new_status,actor_membership_id,
    reason_code,details,occurred_at
  ) VALUES(
    p_organization_id,p_booking_id,v_booking.status,'cancelled',
    p_actor_membership_id,btrim(p_reason_code),
    jsonb_build_object('cancellationRequestId',p_cancellation_request_id,'policyRevisionId',v_policy.id),
    v_now
  );

  v_consequence_snapshot:=jsonb_build_object(
    'evaluationState','manual_review_required',
    'policyRevisionId',v_policy.id,
    'customerMode',v_policy.customer_mode,
    'publicTerms',v_policy.public_terms,
    'approvalRules',v_policy.approval_rules,
    'commercialRules',v_policy.commercial_rules,
    'noticeRules',v_policy.notice_rules,
    'confirmedPriceSnapshot',v_snapshot.price_snapshot,
    'automaticFeeCalculation',false,
    'calculatedFee',NULL,
    'moneyMovementExecuted',false,
    'manualFollowUpRequired',true,
    'manualFollowUpReason','Review the pinned commercial rules and any deposit, fee, balance, refund or credit obligation. Eventor has not moved money.'
  );

  INSERT INTO eogp.booking_cancellation_effects(
    id,organization_id,booking_id,cancellation_request_id,policy_revision_id,
    effective_at,commercial_consequence_snapshot,resource_release_completed_at,
    executed_by_membership_id,executed_by_kind
  ) VALUES(
    v_effect_id,p_organization_id,p_booking_id,p_cancellation_request_id,v_policy.id,
    v_now,v_consequence_snapshot,v_now,p_actor_membership_id,'membership'
  );

  INSERT INTO eogp.booking_cancellation_followups(
    id,organization_id,cancellation_effect_id,followup_kind,status,notes_internal
  ) VALUES(
    v_followup_id,p_organization_id,v_effect_id,'other','open',
    'Review the pinned cancellation commercial rules and record any manually verified fee, deposit, balance, refund or credit outcome. No financial transaction was initiated by Eventor.'
  );

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata,occurred_at
  ) VALUES(
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.cancellation.effective','booking',p_booking_id,
    btrim(p_reason_code),
    jsonb_build_object(
      'cancellationRequestId',p_cancellation_request_id,
      'cancellationEffectId',v_effect_id,
      'policyRevisionId',v_policy.id,
      'reservationsReleased',v_reservations_released,
      'manualFollowUpId',v_followup_id
    ),v_now
  );

  RETURN jsonb_build_object(
    'bookingId',p_booking_id,
    'cancellationRequestId',p_cancellation_request_id,
    'effectId',v_effect_id,
    'followupId',v_followup_id,
    'status','cancelled',
    'effectiveAt',v_now,
    'reservationsReleased',v_reservations_released,
    'commercialEvaluationState','manual_review_required',
    'moneyMovementExecuted',false,
    'replayed',false
  );
END;
$function$;

REVOKE ALL ON FUNCTION
  eogp.assert_booking_cancellation_permission(uuid,uuid,uuid,text),
  eogp.assert_booking_cancellation_request_permission(uuid,uuid,uuid,uuid,text),
  eogp.decide_booking_cancellation_request(uuid,uuid,uuid,uuid,text,text),
  eogp.preview_booking_cancellation(uuid,uuid,uuid,integer,uuid),
  eogp.execute_booking_cancellation(uuid,uuid,uuid,uuid,integer,text)
  FROM PUBLIC,eventor_worker,eventor_auth;

GRANT EXECUTE ON FUNCTION
  eogp.assert_booking_cancellation_request_permission(uuid,uuid,uuid,uuid,text),
  eogp.decide_booking_cancellation_request(uuid,uuid,uuid,uuid,text,text),
  eogp.preview_booking_cancellation(uuid,uuid,uuid,integer,uuid),
  eogp.execute_booking_cancellation(uuid,uuid,uuid,uuid,integer,text)
  TO eventor_runtime;

-- Enforce the pinned policy inside the only two commands that create a new
-- submitted request. Historical/effective rows and integrity fixtures remain
-- importable without fabricating a current policy.
CREATE OR REPLACE FUNCTION eogp.submit_booking_cancellation_request(
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
  PERFORM eogp.assert_booking_cancellation_request_policy(p_organization_id,p_booking_id);
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


CREATE OR REPLACE FUNCTION eogp.submit_external_booking_cancellation_request(
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
  PERFORM eogp.assert_booking_cancellation_request_policy(v_organization_id,v_booking.id);
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


