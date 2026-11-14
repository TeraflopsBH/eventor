-- Add actionable, read-only alternatives to the booking-draft availability preview.
-- The original preview remains the single source of conflict/capacity evaluation.
ALTER FUNCTION eogp.preview_booking_draft_allocation_availability(
  uuid, uuid, uuid, jsonb, jsonb, timestamptz, timestamptz
) RENAME TO preview_booking_draft_allocation_availability_base;

REVOKE ALL ON FUNCTION eogp.preview_booking_draft_allocation_availability_base(
  uuid, uuid, uuid, jsonb, jsonb, timestamptz, timestamptz
) FROM PUBLIC, eventor_worker, eventor_auth, eventor_runtime;

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
  v_result jsonb;
  v_space_alternatives jsonb;
  v_resource_pools jsonb;
  v_resource_interval_valid boolean;
BEGIN
  v_result := eogp.preview_booking_draft_allocation_availability_base(
    p_organization_id, p_draft_id, p_actor_membership_id,
    p_space_lines, p_resource_lines, p_resource_starts_at, p_resource_ends_at
  );

  v_resource_interval_valid :=
    p_resource_starts_at IS NOT NULL
    AND p_resource_ends_at IS NOT NULL
    AND p_resource_ends_at > p_resource_starts_at;

  WITH proposed AS (
    SELECT item.value AS line, item.ordinality::integer AS line_number
      FROM jsonb_array_elements(p_space_lines) WITH ORDINALITY AS item(value, ordinality)
  ),
  alternatives AS (
    SELECT proposed.line_number,
           coalesce(jsonb_agg(jsonb_build_object(
             'venueSpaceId', candidate.id,
             'venueId', candidate.venue_id,
             'venueName', venue.name,
             'code', candidate.code,
             'name', candidate.name,
             'capacity', candidate.capacity
           ) ORDER BY lower(candidate.name), candidate.code), '[]'::jsonb) AS items
      FROM proposed
      JOIN eogp.venue_spaces source_space
        ON source_space.organization_id = p_organization_id
       AND source_space.id = (proposed.line->>'venueSpaceId')::uuid
      JOIN eogp.venue_spaces candidate
        ON candidate.organization_id = source_space.organization_id
       AND candidate.venue_id = source_space.venue_id
       AND candidate.id <> source_space.id
       AND candidate.status = 'active'
       AND (
         nullif(proposed.line->>'requestedCapacity', '') IS NULL
         OR candidate.capacity IS NULL
         OR candidate.capacity >= (proposed.line->>'requestedCapacity')::integer
       )
      JOIN eogp.venues venue
        ON venue.organization_id = candidate.organization_id
       AND venue.id = candidate.venue_id
       AND venue.status = 'active'
     WHERE NOT EXISTS (
       SELECT 1
         FROM proposed other
        WHERE other.line_number <> proposed.line_number
          AND (other.line->>'venueSpaceId')::uuid = candidate.id
          AND (other.line->>'startsAt')::timestamptz < (proposed.line->>'endsAt')::timestamptz
          AND (other.line->>'endsAt')::timestamptz > (proposed.line->>'startsAt')::timestamptz
     )
       AND NOT EXISTS (
       SELECT 1
         FROM eogp.venue_space_time_blocks block
        WHERE block.organization_id = p_organization_id
          AND block.venue_space_id = candidate.id
          AND block.starts_at < (proposed.line->>'endsAt')::timestamptz
          AND block.ends_at > (proposed.line->>'startsAt')::timestamptz
          AND (
            block.status IN ('confirmed','blocked')
            OR (block.status = 'held'
                AND block.expires_at > greatest(clock_timestamp(), (proposed.line->>'startsAt')::timestamptz))
          )
     )
     GROUP BY proposed.line_number
  )
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'index', line_number,
    'alternatives', items
  ) ORDER BY line_number), '[]'::jsonb)
    INTO v_space_alternatives
    FROM alternatives;

  IF v_resource_interval_valid THEN
    WITH proposed AS (
      SELECT (item.value->>'resourceTypeId')::uuid AS resource_type_id,
             item.ordinality::integer AS line_number
        FROM jsonb_array_elements(p_resource_lines) WITH ORDINALITY AS item(value, ordinality)
    ),
    pools AS (
      SELECT proposed.line_number,
             pool.id AS pool_id,
             pool.code,
             pool.name,
             venue.name AS venue_name,
             pool.capacity,
             coalesce(usage.peak_usage, 0)::bigint AS peak_usage
        FROM proposed
        JOIN eogp.resource_types resource_type
          ON resource_type.organization_id = p_organization_id
         AND resource_type.id = proposed.resource_type_id
         AND resource_type.reservable = true
        JOIN eogp.resource_pools pool
          ON pool.organization_id = p_organization_id
         AND pool.resource_type_id = proposed.resource_type_id
         AND pool.status = 'active'
        JOIN eogp.venues venue
          ON venue.organization_id = pool.organization_id
         AND venue.id = pool.venue_id
         AND venue.status = 'active'
        CROSS JOIN LATERAL (
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
                 OR (reservation.status = 'held'
                     AND reservation.expires_at > greatest(clock_timestamp(), p_resource_starts_at))
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
                 OR (reservation.status = 'held'
                     AND reservation.expires_at > greatest(clock_timestamp(), p_resource_starts_at))
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
          SELECT greatest(coalesce(max(in_use), 0), 0) AS peak_usage
            FROM running_usage
        ) usage
    )
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'index', line_number,
      'pools', pool_items
    ) ORDER BY line_number), '[]'::jsonb)
      INTO v_resource_pools
      FROM (
        SELECT line_number,
               jsonb_agg(jsonb_build_object(
                 'resourcePoolId', pool_id,
                 'code', code,
                 'name', name,
                 'venueName', venue_name,
                 'capacity', capacity,
                 'availableQuantity', greatest(capacity - peak_usage, 0)
               ) ORDER BY venue_name, name, code) AS pool_items
          FROM pools
         GROUP BY line_number
      ) grouped;
  ELSE
    v_resource_pools := '[]'::jsonb;
  END IF;

  RETURN v_result || jsonb_build_object(
    'spaceAlternatives', coalesce(v_space_alternatives, '[]'::jsonb),
    'resourcePools', coalesce(v_resource_pools, '[]'::jsonb)
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.preview_booking_draft_allocation_availability(
  uuid, uuid, uuid, jsonb, jsonb, timestamptz, timestamptz
) FROM PUBLIC, eventor_worker, eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.preview_booking_draft_allocation_availability(
  uuid, uuid, uuid, jsonb, jsonb, timestamptz, timestamptz
) TO eventor_runtime;

COMMENT ON FUNCTION eogp.preview_booking_draft_allocation_availability(
  uuid, uuid, uuid, jsonb, jsonb, timestamptz, timestamptz
) IS 'Read-only advisory availability preview including same-venue space alternatives and per-pool resource capacity. Does not place holds or guarantee availability.';
