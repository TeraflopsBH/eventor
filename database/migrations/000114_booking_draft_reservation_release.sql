-- Explicit, audited release of selected live holds while a booking draft is
-- being amended or reallocated. Confirmed bookings continue to use the
-- separate cancellation-only release command in migration 000026.

CREATE FUNCTION eogp.release_booking_draft_reservations(
  p_organization_id uuid,
  p_draft_revision_id uuid,
  p_reservation_ids uuid[],
  p_actor_membership_id uuid,
  p_reason_code text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_draft_id uuid;
  v_draft_status text;
  v_unique_id_count bigint;
  v_owned_id_count bigint;
  v_resource_count bigint := 0;
  v_space_count bigint := 0;
  v_resource_ids uuid[] := ARRAY[]::uuid[];
  v_space_ids uuid[] := ARRAY[]::uuid[];
  v_pool_id uuid;
BEGIN
  IF nullif(current_setting('app.organization_id', true), '')::uuid
       IS DISTINCT FROM p_organization_id
     OR nullif(current_setting('app.actor_membership_id', true), '')::uuid
       IS DISTINCT FROM p_actor_membership_id THEN
    RAISE EXCEPTION 'organization or staff actor context mismatch'
      USING ERRCODE = '42501';
  END IF;

  IF p_reservation_ids IS NULL
     OR cardinality(p_reservation_ids) = 0
     OR coalesce(array_ndims(p_reservation_ids), 1) <> 1
     OR array_position(p_reservation_ids, NULL::uuid) IS NOT NULL THEN
    RAISE EXCEPTION 'one or more non-null reservation IDs are required'
      USING ERRCODE = '22023';
  END IF;

  SELECT count(DISTINCT requested.reservation_id)
    INTO v_unique_id_count
    FROM unnest(p_reservation_ids) AS requested(reservation_id);
  IF v_unique_id_count <> cardinality(p_reservation_ids) THEN
    RAISE EXCEPTION 'reservation IDs must be unique'
      USING ERRCODE = '22023';
  END IF;

  IF p_reason_code IS NULL
     OR length(btrim(p_reason_code)) < 3
     OR length(p_reason_code) > 1000 THEN
    RAISE EXCEPTION 'release reason must contain between 3 and 1000 characters'
      USING ERRCODE = '22023';
  END IF;

  -- Draft authorization is organization-scoped because a draft has no
  -- booking_records row and cannot be targeted by a booking-scoped grant.
  PERFORM eogp.assert_booking_draft_permission(
    p_organization_id, NULL, p_actor_membership_id, 'booking.draft.manage'
  );

  -- Serialize with draft revision creation and offer preparation. A draft
  -- revision can be superseded and still have live holds that need cleanup.
  SELECT draft.id, draft.status
    INTO v_draft_id, v_draft_status
    FROM eogp.booking_drafts AS draft
    JOIN eogp.booking_draft_revisions AS revision
      ON revision.organization_id = draft.organization_id
     AND revision.draft_id = draft.id
   WHERE draft.organization_id = p_organization_id
     AND revision.id = p_draft_revision_id
   FOR UPDATE OF draft;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking draft revision not found'
      USING ERRCODE = 'P0002';
  END IF;
  IF v_draft_status <> 'draft' THEN
    RAISE EXCEPTION 'holds can be released only while the booking draft remains editable'
      USING ERRCODE = '55000';
  END IF;

  -- Once a customer has accepted an offer for this exact revision, its holds
  -- are part of the accepted commercial path and cannot be released here.
  IF EXISTS (
    SELECT 1
      FROM eogp.booking_offer_revisions AS offer_revision
     WHERE offer_revision.organization_id = p_organization_id
       AND offer_revision.draft_revision_id = p_draft_revision_id
       AND offer_revision.state = 'accepted'
  ) THEN
    RAISE EXCEPTION 'holds for an accepted offer revision cannot be released through draft amendment'
      USING ERRCODE = '55000';
  END IF;

  SELECT count(DISTINCT requested.reservation_id)
    INTO v_owned_id_count
    FROM unnest(p_reservation_ids) AS requested(reservation_id)
   WHERE EXISTS (
     SELECT 1
       FROM eogp.resource_reservations AS reservation
      WHERE reservation.organization_id = p_organization_id
        AND reservation.booking_draft_revision_id = p_draft_revision_id
        AND reservation.id = requested.reservation_id
   )
      OR EXISTS (
     SELECT 1
       FROM eogp.venue_space_time_blocks AS reservation
      WHERE reservation.organization_id = p_organization_id
        AND reservation.booking_draft_revision_id = p_draft_revision_id
        AND reservation.id = requested.reservation_id
   );
  IF v_owned_id_count <> cardinality(p_reservation_ids) THEN
    RAISE EXCEPTION 'every reservation ID must belong to the specified draft revision'
      USING ERRCODE = '42501';
  END IF;

  -- Follow the reservation-creation/expiry lock order: resource pool first,
  -- then venue spaces in stable ID order. Discrete units resolve to their pool.
  FOR v_pool_id IN
    SELECT DISTINCT coalesce(reservation.resource_pool_id, unit.resource_pool_id)
      FROM eogp.resource_reservations AS reservation
      LEFT JOIN eogp.resource_units AS unit
        ON unit.organization_id = reservation.organization_id
       AND unit.id = reservation.resource_unit_id
     WHERE reservation.organization_id = p_organization_id
       AND reservation.booking_draft_revision_id = p_draft_revision_id
       AND reservation.id = ANY(p_reservation_ids)
       AND coalesce(reservation.resource_pool_id, unit.resource_pool_id) IS NOT NULL
     ORDER BY 1
  LOOP
    PERFORM 1
      FROM eogp.resource_pools
     WHERE organization_id = p_organization_id
       AND id = v_pool_id
     FOR UPDATE;
  END LOOP;

  PERFORM space.id
    FROM eogp.venue_spaces AS space
   WHERE space.organization_id = p_organization_id
     AND EXISTS (
       SELECT 1
         FROM eogp.venue_space_time_blocks AS reservation
        WHERE reservation.organization_id = space.organization_id
          AND reservation.venue_space_id = space.id
          AND reservation.booking_draft_revision_id = p_draft_revision_id
          AND reservation.id = ANY(p_reservation_ids)
     )
   ORDER BY space.id
   FOR UPDATE OF space;

  WITH released AS (
    UPDATE eogp.resource_reservations
       SET status = 'released'
     WHERE organization_id = p_organization_id
       AND booking_draft_revision_id = p_draft_revision_id
       AND id = ANY(p_reservation_ids)
       AND status = 'held'
       AND expires_at > clock_timestamp()
     RETURNING id
  )
  SELECT count(*), coalesce(array_agg(id ORDER BY id), ARRAY[]::uuid[])
    INTO v_resource_count, v_resource_ids
    FROM released;

  WITH released AS (
    UPDATE eogp.venue_space_time_blocks
       SET status = 'released',
           updated_at = clock_timestamp()
     WHERE organization_id = p_organization_id
       AND booking_draft_revision_id = p_draft_revision_id
       AND id = ANY(p_reservation_ids)
       AND status = 'held'
       AND expires_at > clock_timestamp()
     RETURNING id
  )
  SELECT count(*), coalesce(array_agg(id ORDER BY id), ARRAY[]::uuid[])
    INTO v_space_count, v_space_ids
    FROM released;

  IF v_resource_count + v_space_count > 0 THEN
    INSERT INTO eogp.audit_events (
      organization_id, actor_organization_id, actor_membership_id,
      actor_kind, action, aggregate_type, aggregate_id, reason_code,
      safe_metadata
    ) VALUES (
      p_organization_id, p_organization_id, p_actor_membership_id,
      'membership', 'booking.draft.reservations.released',
      'booking_draft', v_draft_id, p_reason_code,
      jsonb_build_object(
        'draftRevisionId', p_draft_revision_id,
        'resourceReservationsReleased', v_resource_count,
        'spaceReservationsReleased', v_space_count,
        'resourceReservationIdsReleased', v_resource_ids,
        'spaceReservationIdsReleased', v_space_ids
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'draftId', v_draft_id,
    'draftRevisionId', p_draft_revision_id,
    'resourceReservationsReleased', v_resource_count,
    'spaceReservationsReleased', v_space_count,
    'resourceReservationIdsReleased', v_resource_ids,
    'spaceReservationIdsReleased', v_space_ids,
    'changed', (v_resource_count + v_space_count) > 0
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.release_booking_draft_reservations(uuid,uuid,uuid[],uuid,text)
  FROM PUBLIC, eventor_worker, eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.release_booking_draft_reservations(uuid,uuid,uuid[],uuid,text)
  TO eventor_runtime;
