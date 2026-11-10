-- Unified space occupancy and resource reservation primitives.
CREATE TABLE eogp.venue_space_time_blocks (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    venue_space_id uuid NOT NULL,
    booking_draft_revision_id uuid,
    booking_id uuid,
    maintenance_window_id uuid,
    reservation_kind text NOT NULL CHECK (reservation_kind IN ('draft_hold','booking','maintenance')),
    status text NOT NULL CHECK (status IN ('held','confirmed','blocked','expired','released','cancelled')),
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    expires_at timestamptz,
    idempotency_key text NOT NULL,
    actor_membership_id uuid,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, idempotency_key),
    FOREIGN KEY (organization_id, venue_space_id) REFERENCES eogp.venue_spaces(organization_id, id),
    FOREIGN KEY (organization_id, booking_draft_revision_id)
      REFERENCES eogp.booking_draft_revisions(organization_id, id),
    FOREIGN KEY (organization_id, booking_id) REFERENCES eogp.booking_records(organization_id, id),
    FOREIGN KEY (organization_id, maintenance_window_id)
      REFERENCES eogp.maintenance_windows(organization_id, id),
    FOREIGN KEY (organization_id, actor_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    CHECK (ends_at > starts_at),
    CHECK (num_nonnulls(booking_draft_revision_id, booking_id, maintenance_window_id) = 1),
    CHECK (
      (reservation_kind = 'draft_hold' AND booking_draft_revision_id IS NOT NULL AND status IN ('held','expired','released','cancelled'))
      OR (reservation_kind = 'booking' AND booking_id IS NOT NULL AND status IN ('confirmed','released','cancelled'))
      OR (reservation_kind = 'maintenance' AND maintenance_window_id IS NOT NULL AND status IN ('blocked','released','cancelled'))
    ),
    CHECK ((status = 'held') = (expires_at IS NOT NULL))
);
ALTER TABLE eogp.venue_space_time_blocks
  ADD CONSTRAINT venue_space_no_active_overlap
  EXCLUDE USING gist (
    organization_id WITH =,
    venue_space_id WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&
  )
  WHERE (status IN ('held','confirmed','blocked'));

CREATE INDEX venue_space_blocks_booking_idx
  ON eogp.venue_space_time_blocks (organization_id, booking_id, starts_at)
  WHERE booking_id IS NOT NULL;
CREATE INDEX venue_space_blocks_expiry_idx
  ON eogp.venue_space_time_blocks (expires_at)
  WHERE status = 'held';

CREATE TABLE eogp.resource_reservations (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    resource_pool_id uuid,
    resource_unit_id uuid,
    booking_draft_revision_id uuid,
    booking_id uuid,
    maintenance_window_id uuid,
    booking_resource_line_id uuid,
    quantity integer NOT NULL DEFAULT 1 CHECK (quantity > 0),
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    status text NOT NULL CHECK (status IN ('held','confirmed','blocked','expired','released','cancelled')),
    expires_at timestamptz,
    idempotency_key text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, idempotency_key),
    FOREIGN KEY (organization_id, resource_pool_id) REFERENCES eogp.resource_pools(organization_id, id),
    FOREIGN KEY (organization_id, resource_unit_id) REFERENCES eogp.resource_units(organization_id, id),
    FOREIGN KEY (organization_id, booking_draft_revision_id)
      REFERENCES eogp.booking_draft_revisions(organization_id, id),
    FOREIGN KEY (organization_id, booking_id) REFERENCES eogp.booking_records(organization_id, id),
    FOREIGN KEY (organization_id, maintenance_window_id)
      REFERENCES eogp.maintenance_windows(organization_id, id),
    FOREIGN KEY (organization_id, booking_resource_line_id)
      REFERENCES eogp.booking_resource_lines(organization_id, id),
    CHECK (ends_at > starts_at),
    CHECK (num_nonnulls(resource_pool_id, resource_unit_id) = 1),
    CHECK (num_nonnulls(booking_draft_revision_id, booking_id, maintenance_window_id) = 1),
    CHECK ((status = 'held') = (expires_at IS NOT NULL)),
    CHECK (status <> 'blocked' OR maintenance_window_id IS NOT NULL)
);

ALTER TABLE eogp.resource_reservations
  ADD CONSTRAINT resource_unit_no_active_overlap
  EXCLUDE USING gist (
    organization_id WITH =,
    resource_unit_id WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&
  )
  WHERE (resource_unit_id IS NOT NULL AND status IN ('held','confirmed','blocked'));

CREATE INDEX resource_reservations_pool_time_idx
  ON eogp.resource_reservations (organization_id, resource_pool_id, starts_at, ends_at)
  WHERE resource_pool_id IS NOT NULL AND status IN ('held','confirmed','blocked');
CREATE INDEX resource_reservations_expiry_idx
  ON eogp.resource_reservations (expires_at)
  WHERE status = 'held';

CREATE FUNCTION eogp.reserve_pooled_resource(
    p_organization_id uuid,
    p_resource_pool_id uuid,
    p_booking_draft_revision_id uuid,
    p_booking_id uuid,
    p_booking_resource_line_id uuid,
    p_starts_at timestamptz,
    p_ends_at timestamptz,
    p_quantity integer,
    p_expires_at timestamptz,
    p_idempotency_key text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
    v_capacity integer;
    v_peak bigint;
    v_reservation_id uuid := gen_random_uuid();
BEGIN
    IF nullif(current_setting('app.organization_id', true), '')::uuid
       IS DISTINCT FROM p_organization_id THEN
        RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
    END IF;
    IF p_ends_at <= p_starts_at OR p_quantity <= 0 THEN
        RAISE EXCEPTION 'invalid reservation interval or quantity' USING ERRCODE = '22023';
    END IF;
    IF num_nonnulls(p_booking_draft_revision_id, p_booking_id) <> 1 THEN
        RAISE EXCEPTION 'exactly one draft revision or booking is required' USING ERRCODE = '22023';
    END IF;
    IF p_idempotency_key IS NULL OR length(p_idempotency_key) < 8 THEN
        RAISE EXCEPTION 'a valid idempotency key is required' USING ERRCODE = '22023';
    END IF;

    SELECT capacity INTO v_capacity
      FROM eogp.resource_pools
     WHERE organization_id = p_organization_id
       AND id = p_resource_pool_id
       AND status = 'active'
     FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'resource pool not found or inactive' USING ERRCODE = 'P0002';
    END IF;

    UPDATE eogp.resource_reservations
       SET status = 'expired'
     WHERE organization_id = p_organization_id
       AND resource_pool_id = p_resource_pool_id
       AND status = 'held'
       AND expires_at <= clock_timestamp();

    WITH reservation_events AS (
      SELECT GREATEST(r.starts_at, p_starts_at) AS event_at, r.quantity::bigint AS delta
        FROM eogp.resource_reservations r
       WHERE r.organization_id = p_organization_id
         AND r.resource_pool_id = p_resource_pool_id
         AND r.status IN ('held','confirmed','blocked')
         AND r.ends_at > p_starts_at
         AND r.starts_at < p_ends_at
      UNION ALL
      SELECT LEAST(r.ends_at, p_ends_at), -r.quantity::bigint
        FROM eogp.resource_reservations r
       WHERE r.organization_id = p_organization_id
         AND r.resource_pool_id = p_resource_pool_id
         AND r.status IN ('held','confirmed','blocked')
         AND r.ends_at > p_starts_at
         AND r.starts_at < p_ends_at
      UNION ALL SELECT p_starts_at, p_quantity::bigint
      UNION ALL SELECT p_ends_at, -p_quantity::bigint
    ),
    grouped_events AS (
      SELECT event_at, sum(delta) AS delta
        FROM reservation_events
       GROUP BY event_at
    ),
    running_usage AS (
      SELECT sum(delta) OVER (ORDER BY event_at ROWS UNBOUNDED PRECEDING) AS in_use
        FROM grouped_events
    )
    SELECT coalesce(max(in_use), 0) INTO v_peak FROM running_usage;

    IF v_peak > v_capacity THEN
        RAISE EXCEPTION 'resource pool capacity exceeded'
          USING ERRCODE = '23P01',
                DETAIL = format('peak requested usage %s exceeds capacity %s', v_peak, v_capacity);
    END IF;

    INSERT INTO eogp.resource_reservations (
      id, organization_id, resource_pool_id,
      booking_draft_revision_id, booking_id, booking_resource_line_id,
      quantity, starts_at, ends_at, status, expires_at, idempotency_key
    ) VALUES (
      v_reservation_id, p_organization_id, p_resource_pool_id,
      p_booking_draft_revision_id, p_booking_id, p_booking_resource_line_id,
      p_quantity, p_starts_at, p_ends_at,
      CASE WHEN p_expires_at IS NULL THEN 'confirmed' ELSE 'held' END,
      p_expires_at, p_idempotency_key
    );
    RETURN v_reservation_id;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.reserve_pooled_resource(uuid,uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,timestamptz,text) FROM PUBLIC;
