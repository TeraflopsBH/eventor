-- Tenant-scoped catalogue projection for structured booking-draft allocation editing.
CREATE FUNCTION eogp.get_booking_draft_allocation_options(
  p_organization_id uuid,
  p_draft_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_spaces jsonb;
  v_resources jsonb;
BEGIN
  PERFORM eogp.assert_booking_draft_permission(
    p_organization_id, p_draft_id, p_actor_membership_id, 'booking.draft.read'
  );

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'venueSpaceId', space.id,
    'venueId', venue.id,
    'venueName', venue.name,
    'code', space.code,
    'name', space.name,
    'spaceKind', space.space_kind,
    'capacity', space.capacity
  ) ORDER BY lower(venue.name), lower(space.name), space.code), '[]'::jsonb)
    INTO v_spaces
    FROM eogp.venue_spaces space
    JOIN eogp.venues venue
      ON venue.organization_id = space.organization_id
     AND venue.id = space.venue_id
   WHERE space.organization_id = p_organization_id
     AND space.status = 'active'
     AND venue.status = 'active';

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'resourceTypeId', resource_type.id,
    'code', resource_type.code,
    'name', resource_type.name,
    'unitLabel', resource_type.unit_label,
    'capacity', coalesce(pool_totals.capacity, 0)
  ) ORDER BY lower(resource_type.name), resource_type.code), '[]'::jsonb)
    INTO v_resources
    FROM eogp.resource_types resource_type
    LEFT JOIN LATERAL (
      SELECT sum(pool.capacity)::integer AS capacity
        FROM eogp.resource_pools pool
        JOIN eogp.venues venue
          ON venue.organization_id = pool.organization_id
         AND venue.id = pool.venue_id
       WHERE pool.organization_id = p_organization_id
         AND pool.resource_type_id = resource_type.id
         AND pool.status = 'active'
         AND venue.status = 'active'
    ) pool_totals ON true
   WHERE resource_type.organization_id = p_organization_id
     AND resource_type.reservable = true;

  RETURN jsonb_build_object(
    'spaces', coalesce(v_spaces, '[]'::jsonb),
    'resources', coalesce(v_resources, '[]'::jsonb)
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.get_booking_draft_allocation_options(uuid,uuid,uuid)
  FROM PUBLIC, eventor_worker, eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.get_booking_draft_allocation_options(uuid,uuid,uuid)
  TO eventor_runtime;

COMMENT ON FUNCTION eogp.get_booking_draft_allocation_options(uuid,uuid,uuid) IS
  'Returns active same-organization venue spaces and reservable resource types for a readable booking draft. Resource capacity is the sum of active pools at active venues; final reservation availability remains server-authoritative.';
