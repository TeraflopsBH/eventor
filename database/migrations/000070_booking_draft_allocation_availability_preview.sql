-- Advisory availability preview for proposed booking-draft allocations.
-- This function never creates or mutates reservations/holds. Final writes remain
-- protected by the reservation commands and exclusion/capacity constraints.
CREATE FUNCTION eogp.preview_booking_draft_allocation_availability(
  p_organization_id uuid,
  p_draft_id uuid,
  p_actor_membership_id uuid,
  p_space_lines jsonb,
  p_resource_lines jsonb,
  p_resource_starts_at timestamptz,
  p_resource_ends_at timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_spaces jsonb;
  v_resources jsonb;
  v_resource_interval_valid boolean;
  v_resource_interval_reason text;
BEGIN
  PERFORM eogp.assert_booking_draft_permission(
    p_organization_id, p_draft_id, p_actor_membership_id, 'booking.draft.read'
  );

  IF p_space_lines IS NULL OR jsonb_typeof(p_space_lines) <> 'array'
     OR jsonb_array_length(p_space_lines) > 50
     OR p_resource_lines IS NULL OR jsonb_typeof(p_resource_lines) <> 'array'
     OR jsonb_array_length(p_resource_lines) > 100 THEN
    RAISE EXCEPTION 'allocation preview requires bounded space/resource arrays'
      USING ERRCODE = '22023';
  END IF;

  v_resource_interval_valid :=
    p_resource_starts_at IS NOT NULL
    AND p_resource_ends_at IS NOT NULL
    AND p_resource_ends_at > p_resource_starts_at;
  v_resource_interval_reason := CASE
    WHEN p_resource_starts_at IS NULL OR p_resource_ends_at IS NULL THEN 'resource_interval_missing'
    ELSE 'resource_interval_invalid'
  END;

  WITH proposed AS (
    SELECT item.value AS line, item.ordinality::integer AS line_number
      FROM jsonb_array_elements(p_space_lines) WITH ORDINALITY AS item(value, ordinality)
  ),
  evaluated AS (
    SELECT proposed.line_number,
           proposed.line->>'venueSpaceId' AS venue_space_id,
           proposed.line->>'startsAt' AS starts_at,
           proposed.line->>'endsAt' AS ends_at,
           CASE WHEN space.id IS NULL THEN false ELSE true END AS space_active,
           coalesce(conflicts.items, '[]'::jsonb) AS conflicts
      FROM proposed
      LEFT JOIN eogp.venue_spaces space
        ON space.organization_id = p_organization_id
       AND space.id = (proposed.line->>'venueSpaceId')::uuid
       AND space.status = 'active'
       AND EXISTS (
         SELECT 1 FROM eogp.venues venue
          WHERE venue.organization_id = space.organization_id
            AND venue.id = space.venue_id
            AND venue.status = 'active'
       )
      LEFT JOIN LATERAL (
        SELECT jsonb_agg(jsonb_build_object(
          'kind', CASE WHEN block.reservation_kind = 'maintenance' THEN 'maintenance'
                       WHEN block.reservation_kind = 'booking' THEN 'confirmed_booking'
                       ELSE 'active_hold' END,
          'status', block.status,
          'startsAt', block.starts_at,
          'endsAt', block.ends_at
        ) ORDER BY block.starts_at) AS items
          FROM eogp.venue_space_time_blocks block
         WHERE block.organization_id = p_organization_id
           AND block.venue_space_id = (proposed.line->>'venueSpaceId')::uuid
           AND block.starts_at < (proposed.line->>'endsAt')::timestamptz
           AND block.ends_at > (proposed.line->>'startsAt')::timestamptz
           AND (
             block.status IN ('confirmed','blocked')
             OR (block.status = 'held' AND block.expires_at > greatest(clock_timestamp(), (proposed.line->>'startsAt')::timestamptz))
           )
      ) conflicts ON true
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'index', evaluated.line_number,
    'venueSpaceId', evaluated.venue_space_id,
    'available', evaluated.space_active AND jsonb_array_length(evaluated.conflicts) = 0,
    'reason', CASE WHEN NOT evaluated.space_active THEN 'space_unavailable'
                   WHEN jsonb_array_length(evaluated.conflicts) > 0 THEN 'space_conflict'
                   ELSE NULL END,
    'conflicts', evaluated.conflicts
  ) ORDER BY evaluated.line_number), '[]'::jsonb)
    INTO v_spaces
    FROM evaluated;

  IF NOT v_resource_interval_valid THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'index', item.ordinality,
      'resourceTypeId', item.value->>'resourceTypeId',
      'requestedQuantity', item.value->>'requestedQuantity',
      'checked', false,
      'available', NULL,
      'reason', v_resource_interval_reason,
      'availableQuantity', NULL
    ) ORDER BY item.ordinality), '[]'::jsonb)
      INTO v_resources
      FROM jsonb_array_elements(p_resource_lines) WITH ORDINALITY AS item(value, ordinality);
  ELSE
    WITH proposed AS (
      SELECT item.value AS line,
             item.ordinality::integer AS line_number,
             (item.value->>'resourceTypeId')::uuid AS resource_type_id,
             (item.value->>'requestedQuantity')::numeric AS requested_quantity
        FROM jsonb_array_elements(p_resource_lines) WITH ORDINALITY AS item(value, ordinality)
    ),
    demand AS (
      SELECT resource_type_id, sum(requested_quantity) AS requested_quantity
        FROM proposed
       GROUP BY resource_type_id
    ),
    pool_usage AS (
      SELECT pool.id AS pool_id,
             pool.resource_type_id,
             pool.capacity,
             coalesce((
               WITH events AS (
                 SELECT greatest(reservation.starts_at, p_resource_starts_at) AS event_at,
                        reservation.quantity::bigint AS delta
                   FROM eogp.resource_reservations reservation
                  WHERE reservation.organization_id = p_organization_id
                    AND (
                      reservation.resource_pool_id = pool.id
                      OR reservation.resource_unit_id IN (
                        SELECT unit.id FROM eogp.resource_units unit
                         WHERE unit.organization_id = p_organization_id
                           AND unit.resource_pool_id = pool.id
                      )
                    )
                    AND reservation.starts_at < p_resource_ends_at
                    AND reservation.ends_at > p_resource_starts_at
                    AND (
                      reservation.status IN ('confirmed','blocked')
                      OR (reservation.status = 'held' AND reservation.expires_at > greatest(clock_timestamp(), p_resource_starts_at))
                    )
                 UNION ALL
                 SELECT least(reservation.ends_at, p_resource_ends_at,
                              CASE WHEN reservation.status = 'held'
                                   THEN reservation.expires_at ELSE p_resource_ends_at END),
                        -reservation.quantity::bigint
                   FROM eogp.resource_reservations reservation
                  WHERE reservation.organization_id = p_organization_id
                    AND (
                      reservation.resource_pool_id = pool.id
                      OR reservation.resource_unit_id IN (
                        SELECT unit.id FROM eogp.resource_units unit
                         WHERE unit.organization_id = p_organization_id
                           AND unit.resource_pool_id = pool.id
                      )
                    )
                    AND reservation.starts_at < p_resource_ends_at
                    AND reservation.ends_at > p_resource_starts_at
                    AND (
                      reservation.status IN ('confirmed','blocked')
                      OR (reservation.status = 'held' AND reservation.expires_at > clock_timestamp())
                    )
               ),
               grouped_events AS (
                 SELECT event_at, sum(delta) AS delta
                   FROM events
                  WHERE event_at >= p_resource_starts_at
                    AND event_at <= p_resource_ends_at
                  GROUP BY event_at
               ),
               running_usage AS (
                 SELECT sum(delta) OVER (ORDER BY event_at ROWS UNBOUNDED PRECEDING) AS in_use
                   FROM grouped_events
               )
               SELECT greatest(coalesce(max(in_use), 0), 0) FROM running_usage
             ), 0)::integer AS peak_usage
        FROM eogp.resource_pools pool
        JOIN eogp.venues venue
          ON venue.organization_id = pool.organization_id
         AND venue.id = pool.venue_id
       WHERE pool.organization_id = p_organization_id
         AND pool.status = 'active'
         AND venue.status = 'active'
    ),
    availability AS (
      SELECT demand.resource_type_id,
             demand.requested_quantity,
             coalesce(sum(greatest(pool_usage.capacity - pool_usage.peak_usage, 0)), 0)::numeric
               AS available_quantity,
             count(pool_usage.pool_id)::integer AS active_pool_count
        FROM demand
        LEFT JOIN pool_usage ON pool_usage.resource_type_id = demand.resource_type_id
       GROUP BY demand.resource_type_id, demand.requested_quantity
    )
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'index', proposed.line_number,
      'resourceTypeId', proposed.resource_type_id,
      'requestedQuantity', proposed.requested_quantity,
      'totalRequestedQuantity', availability.requested_quantity,
      'availableQuantity', availability.available_quantity,
      'checked', true,
      'available', resource_type.id IS NOT NULL
                   AND availability.active_pool_count > 0
                   AND availability.requested_quantity <= availability.available_quantity,
      'reason', CASE WHEN resource_type.id IS NULL THEN 'resource_unavailable'
                     WHEN availability.active_pool_count = 0 THEN 'no_active_resource_pools'
                     WHEN availability.requested_quantity > availability.available_quantity THEN 'resource_capacity_conflict'
                     ELSE NULL END
    ) ORDER BY proposed.line_number), '[]'::jsonb)
      INTO v_resources
      FROM proposed
      JOIN availability ON availability.resource_type_id = proposed.resource_type_id
      LEFT JOIN eogp.resource_types resource_type
        ON resource_type.organization_id = p_organization_id
       AND resource_type.id = proposed.resource_type_id
       AND resource_type.reservable = true;
  END IF;

  RETURN jsonb_build_object(
    'spaces', coalesce(v_spaces, '[]'::jsonb),
    'resources', coalesce(v_resources, '[]'::jsonb),
    'resourceIntervalChecked', v_resource_interval_valid,
    'advisoryOnly', true,
    'checkedAt', clock_timestamp()
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.preview_booking_draft_allocation_availability(uuid,uuid,uuid,jsonb,jsonb,timestamptz,timestamptz)
  FROM PUBLIC, eventor_worker, eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.preview_booking_draft_allocation_availability(uuid,uuid,uuid,jsonb,jsonb,timestamptz,timestamptz)
  TO eventor_runtime;

COMMENT ON FUNCTION eogp.preview_booking_draft_allocation_availability(uuid,uuid,uuid,jsonb,jsonb,timestamptz,timestamptz) IS
  'Read-only advisory preview of active space-block overlaps and pooled-resource capacity for proposed draft allocations. Does not place holds or guarantee availability; reservation commands remain authoritative.';
