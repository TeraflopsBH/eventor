-- Atomic booking confirmation from one accepted and approved offer revision.
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA eogp;

CREATE UNIQUE INDEX booking_records_source_offer_revision_uq
  ON eogp.booking_records (organization_id,source_offer_revision_id);

CREATE FUNCTION eogp.confirm_booking_from_offer(
  p_organization_id uuid,
  p_draft_revision_id uuid,
  p_actor_membership_id uuid,
  p_confirmation_reason text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_draft eogp.booking_drafts%ROWTYPE;
  v_offer eogp.booking_offers%ROWTYPE;
  v_revision eogp.booking_offer_revisions%ROWTYPE;
  v_existing_booking eogp.booking_records%ROWTYPE;
  v_booking_id uuid := gen_random_uuid();
  v_booking_code text := 'BKG-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,12));
  v_customer_terms jsonb;
  v_price_snapshot jsonb;
  v_snapshot_document jsonb;
  v_snapshot_sha256 text;
  v_acceptance_at timestamptz;
  v_accepted_name_ciphertext bytea;
  v_requester_name_ciphertext bytea;
  v_requester_email_hash text;
  v_requester_email_ciphertext bytea;
  v_requester_phone_hash text;
  v_requester_phone_ciphertext bytea;
  v_source_inquiry_id uuid;
  v_expected_space_lines bigint;
  v_active_space_holds bigint;
  v_expected_resource_holds bigint;
  v_converted_resource_holds bigint;
  v_converted_space_holds bigint;
  v_reservation_result jsonb;
  v_requirement jsonb;
  v_required_approvals integer;
  v_approved_count integer;
  v_blocked_count integer;
  v_member_status text;
  v_space_line record;
  v_resource_line record;
  v_period_count bigint;
BEGIN
  IF nullif(current_setting('app.organization_id',true),'')::uuid
     IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;
  IF p_confirmation_reason IS NULL
     OR length(btrim(p_confirmation_reason)) NOT BETWEEN 3 AND 2000 THEN
    RAISE EXCEPTION 'a confirmation reason between 3 and 2000 characters is required'
      USING ERRCODE = '22023';
  END IF;

  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.confirm']::text[]
  );

  SELECT membership.status INTO v_member_status
    FROM eogp.organization_memberships membership
   WHERE membership.organization_id=p_organization_id
     AND membership.id=p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_member_status <> 'active' THEN
    RAISE EXCEPTION 'active booking confirmer membership is required'
      USING ERRCODE = '42501';
  END IF;

  -- Lock the draft first. Offer preparation and draft revisions use the same
  -- draft -> offer ordering so a stale revision cannot race confirmation.
  SELECT draft.* INTO v_draft
    FROM eogp.booking_drafts draft
    JOIN eogp.booking_draft_revisions revision
      ON revision.organization_id=draft.organization_id
     AND revision.draft_id=draft.id
   WHERE draft.organization_id=p_organization_id
     AND revision.id=p_draft_revision_id
   FOR UPDATE OF draft;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking draft revision not found'
      USING ERRCODE = 'P0002';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM eogp.booking_draft_revisions revision
     WHERE revision.organization_id=p_organization_id
       AND revision.id=p_draft_revision_id
       AND revision.draft_id=v_draft.id
       AND revision.revision_number=v_draft.current_revision_number
  ) THEN
    RAISE EXCEPTION 'booking confirmation requires the current draft revision'
      USING ERRCODE = '40001';
  END IF;

  SELECT offer.* INTO v_offer
    FROM eogp.booking_offers offer
   WHERE offer.organization_id=p_organization_id
     AND offer.draft_id=v_draft.id
   FOR UPDATE;
  IF NOT FOUND OR v_offer.status <> 'accepted' THEN
    RAISE EXCEPTION 'an accepted booking offer is required for confirmation'
      USING ERRCODE = '55000';
  END IF;

  SELECT revision.* INTO v_revision
    FROM eogp.booking_offer_revisions revision
   WHERE revision.organization_id=p_organization_id
     AND revision.offer_id=v_offer.id
     AND revision.draft_revision_id=p_draft_revision_id
   ORDER BY revision.revision_number DESC
   LIMIT 1
   FOR UPDATE;
  IF NOT FOUND OR v_revision.state <> 'accepted' THEN
    RAISE EXCEPTION 'the exact draft revision must have an accepted offer revision'
      USING ERRCODE = '55000';
  END IF;
  IF EXISTS (
    SELECT 1 FROM eogp.booking_offer_revisions newer
     WHERE newer.organization_id=p_organization_id
       AND newer.offer_id=v_offer.id
       AND newer.revision_number>v_revision.revision_number
  ) THEN
    RAISE EXCEPTION 'an older offer revision cannot be confirmed after a successor exists'
      USING ERRCODE = '55000';
  END IF;

  -- A customer acceptance event is mandatory and must target this exact
  -- revision. Staff-created drafts without an inquiry still need an accepted
  -- customer name to create a booking party contact snapshot.
  SELECT history.occurred_at,history.customer_name_ciphertext
    INTO v_acceptance_at,v_accepted_name_ciphertext
    FROM eogp.booking_offer_decision_history history
   WHERE history.organization_id=p_organization_id
     AND history.offer_id=v_offer.id
     AND history.offer_revision_id=v_revision.id
     AND history.decision='accepted'
     AND history.actor_kind='external_capability'
   ORDER BY history.occurred_at DESC
   LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'customer acceptance evidence for this offer revision is missing'
      USING ERRCODE = '55000';
  END IF;

  -- All matching approval requirements are evaluated from the offer's pinned
  -- snapshot. No later policy publication can change these requirements.
  FOR v_requirement IN
    SELECT value FROM jsonb_array_elements(v_revision.approval_requirements_snapshot)
  LOOP
    v_required_approvals := (v_requirement->>'requiredApprovals')::integer;
    SELECT count(*) FILTER (WHERE decision.decision='approved')::integer,
           count(*) FILTER (WHERE decision.decision<>'approved')::integer
      INTO v_approved_count,v_blocked_count
      FROM eogp.booking_offer_approval_decisions decision
     WHERE decision.organization_id=p_organization_id
       AND decision.offer_revision_id=v_revision.id
       AND decision.rule_code=v_requirement->>'code';

    IF v_blocked_count>0 OR v_approved_count<v_required_approvals THEN
      RAISE EXCEPTION 'the offer does not satisfy every required approval rule'
        USING ERRCODE = '55000',
              DETAIL = format('approval rule %s has %s of %s required approvals',
                v_requirement->>'code',v_approved_count,v_required_approvals);
    END IF;
  END LOOP;

  SELECT booking.* INTO v_existing_booking
    FROM eogp.booking_records booking
   WHERE booking.organization_id=p_organization_id
     AND booking.source_offer_revision_id=v_revision.id
   FOR UPDATE;
  IF FOUND THEN
    IF v_existing_booking.status <> 'confirmed' THEN
      RAISE EXCEPTION 'an existing booking from this offer revision is not confirmable'
        USING ERRCODE = '55000';
    END IF;
    RETURN jsonb_build_object(
      'bookingId',v_existing_booking.id,
      'bookingCode',v_existing_booking.booking_code,
      'status',v_existing_booking.status,
      'offerId',v_offer.id,
      'offerRevisionId',v_revision.id,
      'draftRevisionId',p_draft_revision_id,
      'replayed',true
    );
  END IF;

  IF v_draft.status <> 'draft' THEN
    RAISE EXCEPTION 'booking draft is no longer editable and no matching confirmed booking exists'
      USING ERRCODE = '55000';
  END IF;

  -- Final preflight: every requested space must still have its exact live hold.
  SELECT count(*) INTO v_expected_space_lines
    FROM eogp.booking_draft_space_lines line
   WHERE line.organization_id=p_organization_id
     AND line.draft_revision_id=p_draft_revision_id;
  SELECT count(*) INTO v_active_space_holds
    FROM eogp.venue_space_time_blocks block
   WHERE block.organization_id=p_organization_id
     AND block.booking_draft_revision_id=p_draft_revision_id
     AND block.reservation_kind='draft_hold'
     AND block.status='held'
     AND block.expires_at>clock_timestamp();
  IF v_expected_space_lines <> v_active_space_holds THEN
    RAISE EXCEPTION 'one or more required venue-space holds are missing or expired'
      USING ERRCODE = '23P01';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM eogp.booking_draft_space_lines line
      LEFT JOIN eogp.venue_spaces space
        ON space.organization_id=line.organization_id
       AND space.id=line.venue_space_id
     WHERE line.organization_id=p_organization_id
       AND line.draft_revision_id=p_draft_revision_id
       AND (
         space.id IS NULL OR space.status<>'active'
         OR NOT EXISTS (
           SELECT 1
             FROM eogp.venue_space_time_blocks block
            WHERE block.organization_id=line.organization_id
              AND block.booking_draft_revision_id=p_draft_revision_id
              AND block.reservation_kind='draft_hold'
              AND block.venue_space_id=line.venue_space_id
              AND block.starts_at=line.starts_at
              AND block.ends_at=line.ends_at
              AND block.status='held'
              AND block.expires_at>clock_timestamp()
         )
       )
  ) THEN
    RAISE EXCEPTION 'a required space is inactive or its exact requested interval is not held'
      USING ERRCODE = '23P01';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM eogp.venue_space_time_blocks block
     WHERE block.organization_id=p_organization_id
       AND block.booking_draft_revision_id=p_draft_revision_id
       AND block.reservation_kind='draft_hold'
       AND block.status='held'
       AND block.expires_at>clock_timestamp()
       AND NOT EXISTS (
         SELECT 1 FROM eogp.booking_draft_space_lines line
          WHERE line.organization_id=block.organization_id
            AND line.draft_revision_id=p_draft_revision_id
            AND line.venue_space_id=block.venue_space_id
            AND line.starts_at=block.starts_at
            AND line.ends_at=block.ends_at
       )
  ) THEN
    RAISE EXCEPTION 'an active venue-space hold is not represented by the offer draft revision'
      USING ERRCODE = '23P01';
  END IF;

  -- Unassigned holds are valid while a draft is being allocated, but they
  -- must never be converted into confirmed booking occupancy. Every live hold
  -- must be attributable to one of the commercial resource lines.
  IF EXISTS (
    SELECT 1
      FROM eogp.resource_reservations reservation
     WHERE reservation.organization_id=p_organization_id
       AND reservation.booking_draft_revision_id=p_draft_revision_id
       AND reservation.booking_resource_line_id IS NULL
       AND reservation.status='held'
       AND reservation.expires_at>clock_timestamp()
  ) THEN
    RAISE EXCEPTION 'an active resource hold is not represented by a booking resource line'
      USING ERRCODE = '23P01';
  END IF;

  -- Every requested resource line needs live holds at every represented
  -- interval. Split pooled/discrete holds may satisfy the same interval together.
  SELECT count(*) INTO v_expected_resource_holds
    FROM eogp.resource_reservations reservation
   WHERE reservation.organization_id=p_organization_id
     AND reservation.booking_draft_revision_id=p_draft_revision_id
     AND reservation.status='held'
     AND reservation.expires_at>clock_timestamp();
  FOR v_resource_line IN
    SELECT line.id,line.resource_type_id,line.requested_quantity,line.line_code
      FROM eogp.booking_resource_lines line
     WHERE line.organization_id=p_organization_id
       AND line.draft_revision_id=p_draft_revision_id
     ORDER BY line.line_code,line.id
     FOR UPDATE
  LOOP
    SELECT count(*) INTO v_period_count
      FROM (
        SELECT reservation.starts_at,reservation.ends_at,
               sum(reservation.quantity)::numeric AS held_quantity
          FROM eogp.resource_reservations reservation
         WHERE reservation.organization_id=p_organization_id
           AND reservation.booking_draft_revision_id=p_draft_revision_id
           AND reservation.booking_resource_line_id=v_resource_line.id
           AND reservation.status='held'
           AND reservation.expires_at>clock_timestamp()
         GROUP BY reservation.starts_at,reservation.ends_at
        HAVING sum(reservation.quantity)::numeric<v_resource_line.requested_quantity
      ) deficient_intervals;
    IF v_period_count>0 OR NOT EXISTS (
      SELECT 1 FROM eogp.resource_reservations reservation
       WHERE reservation.organization_id=p_organization_id
         AND reservation.booking_draft_revision_id=p_draft_revision_id
         AND reservation.booking_resource_line_id=v_resource_line.id
         AND reservation.status='held'
         AND reservation.expires_at>clock_timestamp()
    ) THEN
      RAISE EXCEPTION 'a requested resource line is not fully covered by live reservations'
        USING ERRCODE = '23P01',
              DETAIL = format('resource line %s (%s) has insufficient held quantity',
                v_resource_line.line_code,v_resource_line.id);
    END IF;
  END LOOP;

  -- Copy requester identity from the immutable source inquiry when present.
  -- Directly-created drafts can instead use the customer acceptance name.
  SELECT draft.source_inquiry_id INTO v_source_inquiry_id
    FROM eogp.booking_drafts draft
   WHERE draft.organization_id=p_organization_id AND draft.id=v_draft.id;

  IF v_source_inquiry_id IS NOT NULL THEN
    SELECT inquiry.requester_name_ciphertext,
           inquiry.requester_email_hash,inquiry.requester_email_ciphertext,
           inquiry.requester_phone_hash,inquiry.requester_phone_ciphertext
      INTO v_requester_name_ciphertext,
           v_requester_email_hash,v_requester_email_ciphertext,
           v_requester_phone_hash,v_requester_phone_ciphertext
      FROM eogp.booking_inquiries inquiry
     WHERE inquiry.organization_id=p_organization_id
       AND inquiry.id=v_source_inquiry_id
     FOR SHARE;
    IF NOT FOUND OR v_requester_name_ciphertext IS NULL THEN
      RAISE EXCEPTION 'source inquiry requester snapshot is unavailable'
        USING ERRCODE = '55000';
    END IF;
  ELSE
    v_requester_name_ciphertext := v_accepted_name_ciphertext;
    v_requester_email_hash := NULL;
    v_requester_email_ciphertext := NULL;
    v_requester_phone_hash := NULL;
    v_requester_phone_ciphertext := NULL;
    IF v_requester_name_ciphertext IS NULL THEN
      RAISE EXCEPTION 'direct booking drafts require the customer to provide an acceptance name'
        USING ERRCODE = '55000';
    END IF;
  END IF;

  v_customer_terms := v_revision.terms_snapshot || jsonb_build_object(
    'offerId',v_offer.id,
    'offerRevisionId',v_revision.id,
    'draftRevisionId',p_draft_revision_id,
    'customerAcceptedAt',v_acceptance_at
  );
  v_price_snapshot := jsonb_build_object(
    'currency',v_revision.currency,
    'subtotal',v_revision.subtotal,
    'taxAmount',v_revision.tax_amount,
    'totalAmount',v_revision.total_amount,
    'terms',v_revision.terms_snapshot
  );
  v_snapshot_document := jsonb_build_object(
    'customerTerms',v_customer_terms,
    'price',v_price_snapshot,
    'cancellationPolicyRevisionId',v_revision.cancellation_policy_revision_id
  );
  v_snapshot_sha256 := encode(
    eogp.digest(convert_to(v_snapshot_document::text,'UTF8'),'sha256'),
    'hex'
  );

  INSERT INTO eogp.booking_records (
    id,organization_id,booking_code,source_offer_revision_id,status,revision_number
  ) VALUES (
    v_booking_id,p_organization_id,v_booking_code,v_revision.id,'confirmed',1
  );

  INSERT INTO eogp.booking_resource_lines (
    organization_id,booking_id,draft_revision_id,resource_type_id,line_code,
    label_snapshot,requested_quantity,approved_quantity,value_snapshot
  )
  SELECT line.organization_id,v_booking_id,NULL,line.resource_type_id,line.line_code,
         line.label_snapshot,line.requested_quantity,line.requested_quantity,line.value_snapshot
    FROM eogp.booking_resource_lines line
   WHERE line.organization_id=p_organization_id
     AND line.draft_revision_id=p_draft_revision_id
   ORDER BY line.line_code,line.id;

  INSERT INTO eogp.booking_confirmed_snapshots (
    organization_id,booking_id,offer_revision_id,cancellation_policy_revision_id,
    customer_terms_snapshot,price_snapshot,confirmed_by_membership_id,
    snapshot_sha256
  ) VALUES (
    p_organization_id,v_booking_id,v_revision.id,v_revision.cancellation_policy_revision_id,
    v_customer_terms,v_price_snapshot,p_actor_membership_id,v_snapshot_sha256
  );

  INSERT INTO eogp.booking_party_contacts (
    organization_id,booking_id,party_role,display_name_ciphertext,
    email_hash,email_ciphertext,phone_hash,phone_ciphertext,is_primary
  ) VALUES (
    p_organization_id,v_booking_id,
    CASE WHEN v_source_inquiry_id IS NULL THEN 'authorized_booking_contact' ELSE 'requester' END,
    v_requester_name_ciphertext,
    v_requester_email_hash,v_requester_email_ciphertext,
    v_requester_phone_hash,v_requester_phone_ciphertext,
    true
  );

  INSERT INTO eogp.booking_status_history (
    organization_id,booking_id,previous_status,new_status,
    actor_membership_id,reason_code,details
  ) VALUES (
    p_organization_id,v_booking_id,NULL,'confirmed',
    p_actor_membership_id,'offer_accepted_booking_confirmed',
    jsonb_build_object(
      'offerRevisionId',v_revision.id,
      'draftRevisionId',p_draft_revision_id,
      'confirmationReason',btrim(p_confirmation_reason)
    )
  );

  -- The existing command serializes pooled capacity and discrete-unit
  -- exclusion constraints, expires stale holds and converts live holds.
  v_reservation_result := eogp.confirm_booking_reservations(
    p_organization_id,p_draft_revision_id,v_booking_id,
    p_actor_membership_id,'offer_accepted_booking_confirmed'
  );
  v_converted_resource_holds := coalesce((v_reservation_result->>'resourceReservationsConfirmed')::bigint,0);
  v_converted_space_holds := coalesce((v_reservation_result->>'spaceReservationsConfirmed')::bigint,0);
  IF v_converted_resource_holds<>v_expected_resource_holds
     OR v_converted_space_holds<>v_active_space_holds THEN
    RAISE EXCEPTION 'one or more reservation holds expired or could not be converted during final confirmation'
      USING ERRCODE = '23P01';
  END IF;

  UPDATE eogp.booking_drafts
     SET status='confirmed',updated_at=clock_timestamp()
   WHERE organization_id=p_organization_id
     AND id=v_draft.id
     AND status='draft';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking draft state changed during confirmation'
      USING ERRCODE = '40001';
  END IF;

  INSERT INTO eogp.audit_events (
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.confirmed','booking',v_booking_id,'offer_accepted_booking_confirmed',
    jsonb_build_object(
      'bookingCode',v_booking_code,
      'offerId',v_offer.id,
      'offerRevisionId',v_revision.id,
      'draftRevisionId',p_draft_revision_id,
      'spaceReservationsConfirmed',v_converted_space_holds,
      'resourceReservationsConfirmed',v_converted_resource_holds
    )
  );

  RETURN jsonb_build_object(
    'bookingId',v_booking_id,
    'bookingCode',v_booking_code,
    'status','confirmed',
    'offerId',v_offer.id,
    'offerRevisionId',v_revision.id,
    'draftRevisionId',p_draft_revision_id,
    'confirmedAt',clock_timestamp(),
    'spaceReservationsConfirmed',v_converted_space_holds,
    'resourceReservationsConfirmed',v_converted_resource_holds,
    'replayed',false
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.confirm_booking_from_offer(uuid,uuid,uuid,text)
  FROM PUBLIC,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.confirm_booking_from_offer(uuid,uuid,uuid,text)
  TO eventor_runtime;
