-- Align booking reservation release with the OpenAPI ReservationReleaseRequest.
-- The caller must identify the exact reservation rows to release; the command
-- never broadens a partial request into a booking-wide release.
CREATE FUNCTION eogp.release_booking_reservations(
  p_organization_id uuid,
  p_booking_id uuid,
  p_reservation_ids uuid[],
  p_actor_membership_id uuid,
  p_reason_code text
) RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_booking_status text;
  v_member_status text;
  v_unique_id_count bigint;
  v_owned_id_count bigint;
  v_resource_count bigint := 0;
  v_space_count bigint := 0;
  v_resource_ids uuid[] := ARRAY[]::uuid[];
  v_space_ids uuid[] := ARRAY[]::uuid[];
BEGIN
  IF nullif(current_setting('app.organization_id', true), '')::uuid
     IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;

  -- Mirror the request contract: at least one UUID, one-dimensional, unique,
  -- and no NULL elements. The API also enforces these constraints.
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

  SELECT status INTO v_booking_status
    FROM eogp.booking_records
   WHERE organization_id = p_organization_id
     AND id = p_booking_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_booking_status <> 'cancelled' THEN
    RAISE EXCEPTION 'reservations can be released only after booking cancellation'
      USING ERRCODE = '55000';
  END IF;

  SELECT status INTO v_member_status
    FROM eogp.organization_memberships
   WHERE organization_id = p_organization_id
     AND id = p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_member_status <> 'active' THEN
    RAISE EXCEPTION 'active booking-owner membership is required'
      USING ERRCODE = '42501';
  END IF;

  -- The same booking-scoped authorization used by the prior command is
  -- retained. Lock both grant and permission rows while the command runs.
  PERFORM 1
    FROM eogp.user_role_grants AS user_grant
    JOIN eogp.role_permissions AS role_permission
      ON role_permission.organization_id = user_grant.organization_id
     AND role_permission.role_id = user_grant.role_id
   WHERE user_grant.organization_id = p_organization_id
     AND user_grant.membership_id = p_actor_membership_id
     AND user_grant.revoked_at IS NULL
     AND (user_grant.expires_at IS NULL OR user_grant.expires_at > clock_timestamp())
     AND role_permission.permission_code = 'booking.cancellation.execute'
     AND (
       user_grant.scope_kind = 'organization'
       OR (user_grant.scope_kind = 'booking'
           AND user_grant.scope_booking_id = p_booking_id)
     )
   FOR SHARE OF user_grant, role_permission;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking.cancellation.execute permission is required for this booking'
      USING ERRCODE = '42501';
  END IF;

  -- IDs may identify either a resource reservation or a venue-space time
  -- block. Validate the entire request before changing anything. This keeps
  -- foreign/nonexistent IDs from producing a misleading partial success.
  SELECT count(DISTINCT requested.reservation_id)
    INTO v_owned_id_count
    FROM unnest(p_reservation_ids) AS requested(reservation_id)
   WHERE EXISTS (
     SELECT 1
       FROM eogp.resource_reservations AS resource_reservation
      WHERE resource_reservation.organization_id = p_organization_id
        AND resource_reservation.booking_id = p_booking_id
        AND resource_reservation.id = requested.reservation_id
   )
      OR EXISTS (
     SELECT 1
       FROM eogp.venue_space_time_blocks AS space_reservation
      WHERE space_reservation.organization_id = p_organization_id
        AND space_reservation.booking_id = p_booking_id
        AND space_reservation.id = requested.reservation_id
   );

  IF v_owned_id_count <> cardinality(p_reservation_ids) THEN
    RAISE EXCEPTION 'every reservation ID must belong to the specified booking'
      USING ERRCODE = '42501';
  END IF;

  WITH released AS (
    UPDATE eogp.resource_reservations
       SET status = 'released'
     WHERE organization_id = p_organization_id
       AND booking_id = p_booking_id
       AND id = ANY(p_reservation_ids)
       AND status IN ('held','confirmed')
       AND ends_at > clock_timestamp()
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
       AND booking_id = p_booking_id
       AND id = ANY(p_reservation_ids)
       AND status = 'confirmed'
       AND ends_at > clock_timestamp()
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
      'membership', 'booking.reservations.released', 'booking',
      p_booking_id, p_reason_code,
      jsonb_build_object(
        'resourceReservationsReleased', v_resource_count,
        'spaceReservationsReleased', v_space_count,
        'resourceReservationIdsReleased', v_resource_ids,
        'spaceReservationIdsReleased', v_space_ids
      )
    );
  END IF;

  -- A retry, or a request containing only ineligible/past/terminal rows,
  -- changes no rows and emits no additional audit event.
  RETURN v_resource_count + v_space_count;
END;
$function$;

-- Remove the former booking-wide overload so callers cannot accidentally
-- bypass the requested-ID boundary.
REVOKE ALL ON FUNCTION eogp.release_booking_reservations(uuid,uuid,uuid,text)
  FROM PUBLIC, eventor_runtime;
DROP FUNCTION eogp.release_booking_reservations(uuid,uuid,uuid,text);

REVOKE ALL ON FUNCTION eogp.release_booking_reservations(uuid,uuid,uuid[],uuid,text)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.release_booking_reservations(uuid,uuid,uuid[],uuid,text)
  TO eventor_runtime;
