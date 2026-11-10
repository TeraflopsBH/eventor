-- Forward-only remediation for high-risk findings in PR #26.
-- Do not rewrite migrations 000001–000021: this migration preserves their checksum history.

-- SECURITY DEFINER expiry commands are worker-only. PostgreSQL grants
-- EXECUTE to PUBLIC by default; a later grant to eventor_worker is additive.
REVOKE ALL ON FUNCTION eogp.expire_space_holds(uuid)
  FROM PUBLIC, eventor_runtime, eventor_auth;
REVOKE ALL ON FUNCTION eogp.expire_resource_holds(uuid)
  FROM PUBLIC, eventor_runtime, eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.expire_space_holds(uuid),
  eogp.expire_resource_holds(uuid) TO eventor_worker;

-- The pooled reservation idempotency comparison must include the resource
-- line. Otherwise the same key can be replayed against another line and
-- silently return a reservation belonging to the first line.
CREATE OR REPLACE FUNCTION eogp.reserve_pooled_resource(
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
    v_existing eogp.resource_reservations%ROWTYPE;
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
    PERFORM pg_advisory_xact_lock(hashtextextended(p_organization_id::text || ':' || p_idempotency_key, 0));
    IF (p_booking_draft_revision_id IS NOT NULL AND (p_expires_at IS NULL OR p_expires_at <= clock_timestamp()))
       OR (p_booking_id IS NOT NULL AND p_expires_at IS NOT NULL) THEN
        RAISE EXCEPTION 'draft reservations require a future expiry; confirmed bookings must not expire' USING ERRCODE = '22023';
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

    SELECT * INTO v_existing
      FROM eogp.resource_reservations
     WHERE organization_id = p_organization_id
       AND idempotency_key = p_idempotency_key
     FOR UPDATE;
    IF FOUND THEN
      IF v_existing.resource_pool_id = p_resource_pool_id
         AND v_existing.resource_unit_id IS NULL
         AND v_existing.booking_draft_revision_id IS NOT DISTINCT FROM p_booking_draft_revision_id
         AND v_existing.booking_id IS NOT DISTINCT FROM p_booking_id
         AND v_existing.booking_resource_line_id IS NOT DISTINCT FROM p_booking_resource_line_id
         AND v_existing.quantity = p_quantity
         AND v_existing.starts_at = p_starts_at
         AND v_existing.ends_at = p_ends_at
         AND v_existing.expires_at IS NOT DISTINCT FROM p_expires_at THEN
        RETURN v_existing.id;
      END IF;
      RAISE EXCEPTION 'idempotency key was previously used for a different reservation payload'
        USING ERRCODE = '22023';
    END IF;

    IF p_booking_resource_line_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM eogp.booking_resource_lines l
       WHERE l.organization_id = p_organization_id
         AND l.id = p_booking_resource_line_id
         AND l.draft_revision_id IS NOT DISTINCT FROM p_booking_draft_revision_id
         AND l.booking_id IS NOT DISTINCT FROM p_booking_id
         AND l.resource_type_id = (
           SELECT rp.resource_type_id
             FROM eogp.resource_pools rp
            WHERE rp.organization_id = p_organization_id
              AND rp.id = p_resource_pool_id
         )
         AND (
           (p_booking_draft_revision_id IS NOT NULL AND p_quantity <= l.requested_quantity)
           OR
           (p_booking_id IS NOT NULL AND l.approved_quantity IS NOT NULL AND p_quantity <= l.approved_quantity)
         )
    ) THEN
      RAISE EXCEPTION 'resource line does not belong to the supplied booking/draft revision'
        USING ERRCODE = '23503';
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
         AND (r.status <> 'held' OR r.expires_at > clock_timestamp())
         AND r.ends_at > p_starts_at
         AND r.starts_at < p_ends_at
      UNION ALL
      SELECT LEAST(r.ends_at, p_ends_at), -r.quantity::bigint
        FROM eogp.resource_reservations r
       WHERE r.organization_id = p_organization_id
         AND r.resource_pool_id = p_resource_pool_id
         AND r.status IN ('held','confirmed','blocked')
         AND (r.status <> 'held' OR r.expires_at > clock_timestamp())
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
      CASE WHEN p_booking_draft_revision_id IS NOT NULL THEN 'held' ELSE 'confirmed' END,
      p_expires_at, p_idempotency_key
    );
    RETURN v_reservation_id;
END;
$function$;

-- One invariant covers pooled and individually tracked units. The pool row is
-- locked before checking, so both reservation functions serialize against the
-- same capacity. A per-line advisory lock additionally serializes identical
-- booking lines even when inventory is drawn from different pools.
CREATE FUNCTION eogp.enforce_resource_reservation_capacity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_pool_id uuid;
  v_capacity integer;
  v_peak bigint;
  v_line_limit numeric;
  v_line_peak numeric;
BEGIN
  IF NEW.resource_pool_id IS NOT NULL THEN
    v_pool_id := NEW.resource_pool_id;
  ELSE
    SELECT resource_pool_id INTO v_pool_id
      FROM eogp.resource_units
     WHERE organization_id = NEW.organization_id
       AND id = NEW.resource_unit_id;
  END IF;

  IF v_pool_id IS NULL THEN
    RAISE EXCEPTION 'reservation must resolve to a resource pool'
      USING ERRCODE = '23503';
  END IF;

  SELECT capacity INTO v_capacity
    FROM eogp.resource_pools
   WHERE organization_id = NEW.organization_id
     AND id = v_pool_id
     AND status = 'active'
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'resource pool not found or inactive'
      USING ERRCODE = 'P0002';
  END IF;

  -- Expire every stale hold in this pool, including holds represented by
  -- individual units. This prevents an expired unit hold from blocking the
  -- discrete-unit exclusion constraint or consuming pooled capacity.
  UPDATE eogp.resource_reservations AS r
     SET status = 'expired'
   WHERE r.organization_id = NEW.organization_id
     AND r.status = 'held'
     AND r.expires_at <= clock_timestamp()
     AND (
       r.resource_pool_id = v_pool_id
       OR r.resource_unit_id IN (
         SELECT u.id FROM eogp.resource_units AS u
          WHERE u.organization_id = NEW.organization_id
            AND u.resource_pool_id = v_pool_id
       )
     );

  IF NEW.booking_resource_line_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(
      NEW.organization_id::text || ':resource-line:' || NEW.booking_resource_line_id::text, 0
    ));

    SELECT CASE
             WHEN NEW.booking_draft_revision_id IS NOT NULL THEN line.requested_quantity
             WHEN NEW.booking_id IS NOT NULL THEN line.approved_quantity
             ELSE NULL
           END
      INTO v_line_limit
      FROM eogp.booking_resource_lines AS line
     WHERE line.organization_id = NEW.organization_id
       AND line.id = NEW.booking_resource_line_id
     FOR UPDATE;

    IF NOT FOUND OR v_line_limit IS NULL OR v_line_limit <= 0 THEN
      RAISE EXCEPTION 'resource line has no applicable requested/approved quantity'
        USING ERRCODE = '23514';
    END IF;
  END IF;

  -- Peak simultaneous usage across both pooled reservations and unit
  -- reservations. Unit rows store resource_pool_id as NULL, so resolve them
  -- through resource_units before summing.
  WITH reservation_events AS (
    SELECT GREATEST(r.starts_at, NEW.starts_at) AS event_at, r.quantity::bigint AS delta
      FROM eogp.resource_reservations AS r
      LEFT JOIN eogp.resource_units AS u
        ON u.organization_id = r.organization_id
       AND u.id = r.resource_unit_id
     WHERE r.organization_id = NEW.organization_id
       AND coalesce(r.resource_pool_id, u.resource_pool_id) = v_pool_id
       AND r.status IN ('held','confirmed','blocked')
       AND (r.status <> 'held' OR r.expires_at > clock_timestamp())
       AND r.ends_at > NEW.starts_at AND r.starts_at < NEW.ends_at
    UNION ALL
    SELECT LEAST(r.ends_at, NEW.ends_at), -r.quantity::bigint
      FROM eogp.resource_reservations AS r
      LEFT JOIN eogp.resource_units AS u
        ON u.organization_id = r.organization_id
       AND u.id = r.resource_unit_id
     WHERE r.organization_id = NEW.organization_id
       AND coalesce(r.resource_pool_id, u.resource_pool_id) = v_pool_id
       AND r.status IN ('held','confirmed','blocked')
       AND (r.status <> 'held' OR r.expires_at > clock_timestamp())
       AND r.ends_at > NEW.starts_at AND r.starts_at < NEW.ends_at
    UNION ALL SELECT NEW.starts_at, NEW.quantity::bigint
    UNION ALL SELECT NEW.ends_at, -NEW.quantity::bigint
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
    RAISE EXCEPTION 'resource pool capacity exceeded across pooled and discrete reservations'
      USING ERRCODE = '23P01',
            DETAIL = format('peak combined usage %s exceeds capacity %s', v_peak, v_capacity);
  END IF;

  IF NEW.booking_resource_line_id IS NOT NULL THEN
    WITH reservation_events AS (
      SELECT GREATEST(r.starts_at, NEW.starts_at) AS event_at, r.quantity::bigint AS delta
        FROM eogp.resource_reservations AS r
       WHERE r.organization_id = NEW.organization_id
         AND r.booking_resource_line_id = NEW.booking_resource_line_id
         AND r.status IN ('held','confirmed','blocked')
         AND (r.status <> 'held' OR r.expires_at > clock_timestamp())
         AND r.ends_at > NEW.starts_at AND r.starts_at < NEW.ends_at
      UNION ALL
      SELECT LEAST(r.ends_at, NEW.ends_at), -r.quantity::bigint
        FROM eogp.resource_reservations AS r
       WHERE r.organization_id = NEW.organization_id
         AND r.booking_resource_line_id = NEW.booking_resource_line_id
         AND r.status IN ('held','confirmed','blocked')
         AND (r.status <> 'held' OR r.expires_at > clock_timestamp())
         AND r.ends_at > NEW.starts_at AND r.starts_at < NEW.ends_at
      UNION ALL SELECT NEW.starts_at, NEW.quantity::bigint
      UNION ALL SELECT NEW.ends_at, -NEW.quantity::bigint
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
    SELECT coalesce(max(in_use), 0) INTO v_line_peak FROM running_usage;

    IF v_line_peak > v_line_limit THEN
      RAISE EXCEPTION 'booking resource line quantity exceeded'
        USING ERRCODE = '23514',
              DETAIL = format('peak line usage %s exceeds line limit %s', v_line_peak, v_line_limit);
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER resource_reservations_capacity_guard
  BEFORE INSERT ON eogp.resource_reservations
  FOR EACH ROW EXECUTE FUNCTION eogp.enforce_resource_reservation_capacity();

REVOKE ALL ON FUNCTION eogp.enforce_resource_reservation_capacity() FROM PUBLIC;

-- Space holds must have a live expiry. Terminal rows cannot be revived or
-- rewritten. A draft hold may be atomically converted in place into the
-- booking row that replaces it, retaining the GiST exclusion continuously.
CREATE FUNCTION eogp.guard_venue_space_time_block_transition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_hold_to_booking boolean := false;
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'space reservation history cannot be deleted'
      USING ERRCODE = '55000';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'held'
       AND (NEW.reservation_kind <> 'draft_hold'
            OR NEW.expires_at IS NULL
            OR NEW.expires_at <= clock_timestamp()) THEN
      RAISE EXCEPTION 'a new space hold requires a future expiry'
        USING ERRCODE = '22023';
    END IF;
    IF NEW.status = 'expired'
       AND (NEW.expires_at IS NULL OR NEW.expires_at > clock_timestamp()) THEN
      RAISE EXCEPTION 'a space hold cannot start expired before its expiry time'
        USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.organization_id IS DISTINCT FROM OLD.organization_id
     OR NEW.venue_space_id IS DISTINCT FROM OLD.venue_space_id
     OR NEW.idempotency_key IS DISTINCT FROM OLD.idempotency_key
     OR NEW.actor_membership_id IS DISTINCT FROM OLD.actor_membership_id
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'space reservation identity and creator fields are immutable'
      USING ERRCODE = '55000';
  END IF;

  v_hold_to_booking :=
       OLD.reservation_kind = 'draft_hold'
   AND OLD.status = 'held'
   AND NEW.reservation_kind = 'booking'
   AND NEW.status = 'confirmed'
   AND OLD.booking_draft_revision_id IS NOT NULL
   AND NEW.booking_draft_revision_id IS NULL
   AND OLD.booking_id IS NULL
   AND NEW.booking_id IS NOT NULL
   AND OLD.maintenance_window_id IS NULL
   AND NEW.maintenance_window_id IS NULL
   AND NEW.expires_at IS NULL
   AND NEW.starts_at = OLD.starts_at
   AND NEW.ends_at = OLD.ends_at;

  IF OLD.reservation_kind IS DISTINCT FROM NEW.reservation_kind
     OR OLD.booking_draft_revision_id IS DISTINCT FROM NEW.booking_draft_revision_id
     OR OLD.booking_id IS DISTINCT FROM NEW.booking_id
     OR OLD.maintenance_window_id IS DISTINCT FROM NEW.maintenance_window_id THEN
    IF NOT v_hold_to_booking THEN
      RAISE EXCEPTION 'space reservation origin cannot be rewritten'
        USING ERRCODE = '55000';
    END IF;
  END IF;

  IF OLD.status IN ('expired','released','cancelled') THEN
    IF to_jsonb(NEW) IS DISTINCT FROM to_jsonb(OLD) THEN
      RAISE EXCEPTION 'terminal space reservations are immutable'
        USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
  END IF;

  IF OLD.status = 'held' AND NEW.status NOT IN ('held','expired','released','cancelled')
     AND NOT v_hold_to_booking THEN
    RAISE EXCEPTION 'invalid draft-hold lifecycle transition'
      USING ERRCODE = '55000';
  ELSIF OLD.status = 'confirmed' AND NEW.status NOT IN ('confirmed','released','cancelled') THEN
    RAISE EXCEPTION 'invalid booking-space lifecycle transition'
      USING ERRCODE = '55000';
  ELSIF OLD.status = 'blocked' AND NEW.status NOT IN ('blocked','released','cancelled') THEN
    RAISE EXCEPTION 'invalid maintenance-space lifecycle transition'
      USING ERRCODE = '55000';
  END IF;

  IF NEW.status = 'held'
     AND (NEW.reservation_kind <> 'draft_hold'
          OR NEW.expires_at IS NULL
          OR NEW.expires_at <= clock_timestamp()) THEN
    RAISE EXCEPTION 'an active space hold requires a future expiry'
      USING ERRCODE = '22023';
  END IF;
  IF NEW.status = 'expired'
     AND (NEW.expires_at IS NULL OR NEW.expires_at > clock_timestamp()) THEN
    RAISE EXCEPTION 'a space hold cannot expire before its expiry time'
      USING ERRCODE = '22023';
  END IF;
  IF NEW.status IN ('released','cancelled')
     AND (NEW.starts_at IS DISTINCT FROM OLD.starts_at
          OR NEW.ends_at IS DISTINCT FROM OLD.ends_at) THEN
    RAISE EXCEPTION 'release/cancellation cannot rewrite the occupied interval'
      USING ERRCODE = '55000';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER venue_space_time_blocks_lifecycle_guard
  BEFORE INSERT OR UPDATE OR DELETE ON eogp.venue_space_time_blocks
  FOR EACH ROW EXECUTE FUNCTION eogp.guard_venue_space_time_block_transition();

REVOKE DELETE ON eogp.venue_space_time_blocks FROM eventor_runtime, eventor_worker;

-- Cancellation consequences must use the policy revision pinned in the
-- confirmed booking snapshot, including the explicit no-policy (NULL) case.
CREATE FUNCTION eogp.enforce_booking_cancellation_pinned_policy()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_pinned_policy_revision_id uuid;
BEGIN
  SELECT snapshot.cancellation_policy_revision_id
    INTO v_pinned_policy_revision_id
    FROM eogp.booking_confirmed_snapshots AS snapshot
   WHERE snapshot.organization_id = NEW.organization_id
     AND snapshot.booking_id = NEW.booking_id
   FOR SHARE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'confirmed booking snapshot is required before applying cancellation effects'
      USING ERRCODE = '23503';
  END IF;

  IF NEW.policy_revision_id IS DISTINCT FROM v_pinned_policy_revision_id THEN
    RAISE EXCEPTION 'cancellation effect policy must match the booking-confirmed snapshot'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER booking_cancellation_effects_pinned_policy_guard
  BEFORE INSERT ON eogp.booking_cancellation_effects
  FOR EACH ROW EXECUTE FUNCTION eogp.enforce_booking_cancellation_pinned_policy();

REVOKE ALL ON FUNCTION eogp.enforce_booking_cancellation_pinned_policy() FROM PUBLIC;

-- Share creation needs an actual snapshot capability, not merely any active
-- collaboration grant whose venue scope happens to match.
CREATE FUNCTION eogp.require_venue_snapshot_share_action()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_allowed_actions text[];
BEGIN
  SELECT allowed_actions INTO v_allowed_actions
    FROM eogp.collaboration_grants
   WHERE organization_id = NEW.organization_id
     AND grantee_organization_id = NEW.event_owner_organization_id
     AND id = NEW.collaboration_grant_id
   FOR SHARE;

  IF NOT FOUND
     OR NOT (v_allowed_actions && ARRAY['venue.snapshot.read','venue.snapshot.use']::text[]) THEN
    RAISE EXCEPTION 'collaboration grant must include venue.snapshot.read or venue.snapshot.use'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER venue_snapshot_shares_action_guard
  BEFORE INSERT ON eogp.venue_snapshot_shares
  FOR EACH ROW EXECUTE FUNCTION eogp.require_venue_snapshot_share_action();

REVOKE ALL ON FUNCTION eogp.require_venue_snapshot_share_action() FROM PUBLIC;

-- Source SELECT is allowed by either read or use. The point-of-use snapshot
-- and session-binding guards continue to require venue.snapshot.use.
CREATE OR REPLACE FUNCTION eogp.has_active_venue_snapshot_share(
  p_source_organization_id uuid,
  p_source_revision_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
  SELECT EXISTS (
    SELECT 1
      FROM eogp.venue_snapshot_shares AS share
      JOIN eogp.collaboration_grants AS collab
        ON collab.organization_id = share.organization_id
       AND collab.grantee_organization_id = share.event_owner_organization_id
       AND collab.id = share.collaboration_grant_id
     WHERE share.organization_id = p_source_organization_id
       AND share.venue_space_revision_id = p_source_revision_id
       AND share.event_owner_organization_id = eogp.current_organization_id()
       AND share.status = 'active'
       AND (share.expires_at IS NULL OR share.expires_at > statement_timestamp())
       AND collab.status = 'active'
       AND collab.valid_from <= statement_timestamp()
       AND (collab.valid_until IS NULL OR collab.valid_until > statement_timestamp())
       AND collab.allowed_actions && ARRAY['venue.snapshot.read','venue.snapshot.use']::text[]
  );
$function$;

-- Serialize child writes with publication. FOR SHARE conflicts with the
-- parent UPDATE that publishes/retires a revision.
CREATE OR REPLACE FUNCTION eogp.assert_revision_parent_mutable(
  p_table_name text,
  p_row jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_organization_id uuid := (p_row ->> 'organization_id')::uuid;
  v_state text;
  v_published_at timestamptz;
  v_parent_id uuid;
BEGIN
  IF v_organization_id IS NULL
     OR v_organization_id <> eogp.current_organization_id() THEN
    RAISE EXCEPTION 'tenant context is required to modify revision children'
      USING ERRCODE = '42501';
  END IF;

  CASE p_table_name
    WHEN 'config_catalogue_revision_options' THEN
      v_parent_id := (p_row ->> 'catalogue_revision_id')::uuid;
      SELECT state, published_at INTO v_state, v_published_at
        FROM eogp.config_catalogue_revisions
       WHERE organization_id = v_organization_id AND id = v_parent_id
       FOR SHARE;
    WHEN 'booking_form_catalogue_bindings' THEN
      v_parent_id := (p_row ->> 'form_revision_id')::uuid;
      SELECT state, published_at INTO v_state, v_published_at
        FROM eogp.booking_form_revisions
       WHERE organization_id = v_organization_id AND id = v_parent_id
       FOR SHARE;
    WHEN 'booking_price_items' THEN
      v_parent_id := (p_row ->> 'price_list_revision_id')::uuid;
      SELECT state, published_at INTO v_state, v_published_at
        FROM eogp.booking_price_list_revisions
       WHERE organization_id = v_organization_id AND id = v_parent_id
       FOR SHARE;
    WHEN 'floor_plan_assets' THEN
      v_parent_id := (p_row ->> 'venue_space_revision_id')::uuid;
      SELECT NULL::text, published_at INTO v_state, v_published_at
        FROM eogp.venue_space_revisions
       WHERE organization_id = v_organization_id AND id = v_parent_id
       FOR SHARE;
    WHEN 'spatial_layers' THEN
      v_parent_id := (p_row ->> 'venue_space_revision_id')::uuid;
      SELECT NULL::text, published_at INTO v_state, v_published_at
        FROM eogp.venue_space_revisions
       WHERE organization_id = v_organization_id AND id = v_parent_id
       FOR SHARE;
    WHEN 'spatial_objects' THEN
      v_parent_id := (p_row ->> 'layer_id')::uuid;
      SELECT NULL::text, revision.published_at INTO v_state, v_published_at
        FROM eogp.spatial_layers AS layer
        JOIN eogp.venue_space_revisions AS revision
          ON revision.organization_id = layer.organization_id
         AND revision.id = layer.venue_space_revision_id
       WHERE layer.organization_id = v_organization_id
         AND layer.id = v_parent_id
       FOR SHARE OF layer, revision;
    ELSE
      RAISE EXCEPTION 'unsupported revision-child table: %', p_table_name
        USING ERRCODE = '22023';
  END CASE;

  IF FOUND AND (v_state IN ('published','retired') OR v_published_at IS NOT NULL) THEN
    RAISE EXCEPTION 'children of published revision %.% are immutable', 'eogp', p_table_name
      USING ERRCODE = '55000';
  END IF;
END;
$function$;

-- An object must be copied under the snapshot layer that represents its
-- actual source layer; matching "some approved layer" is not enough.
CREATE OR REPLACE FUNCTION eogp.enforce_snapshot_object_projection()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_source_organization_id uuid;
  v_revision_id uuid;
  v_approved_layers jsonb;
BEGIN
  SELECT snapshot.source_organization_id,
         snapshot.source_space_revision_id,
         share.approved_layers
    INTO v_source_organization_id, v_revision_id, v_approved_layers
    FROM eogp.event_venue_snapshots AS snapshot
    JOIN eogp.venue_snapshot_shares AS share
      ON share.organization_id = snapshot.share_owner_organization_id
     AND share.event_owner_organization_id = snapshot.organization_id
     AND share.event_id = snapshot.event_id
     AND share.id = snapshot.snapshot_share_id
   WHERE snapshot.organization_id = NEW.organization_id
     AND snapshot.id = NEW.snapshot_id
   FOR SHARE OF share;

  IF NOT FOUND
     OR NEW.source_object_id IS NULL
     OR NOT EXISTS (
       SELECT 1
         FROM eogp.event_venue_snapshot_layers AS copied_layer
         JOIN eogp.spatial_objects AS source_object
           ON source_object.organization_id = v_source_organization_id
          AND source_object.id = NEW.source_object_id
         JOIN eogp.spatial_layers AS source_layer
           ON source_layer.organization_id = source_object.organization_id
          AND source_layer.id = source_object.layer_id
        WHERE copied_layer.organization_id = NEW.organization_id
          AND copied_layer.snapshot_id = NEW.snapshot_id
          AND copied_layer.id = NEW.snapshot_layer_id
          AND copied_layer.source_layer_id = source_layer.id
          AND source_layer.venue_space_revision_id = v_revision_id
          AND v_approved_layers @> jsonb_build_array(source_layer.id::text)
     ) THEN
    RAISE EXCEPTION 'snapshot object must map to the copied layer for its provider-approved source layer'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.assert_revision_parent_mutable(text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.has_active_venue_snapshot_share(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.enforce_snapshot_object_projection() FROM PUBLIC;

-- Narrow database path for the OpenAPI reservation-release operation. The
-- booking must already be cancelled; the command releases only still-future
-- resource and space claims, records one audit event when it changes rows,
-- and returns zero on retries.
CREATE FUNCTION eogp.release_booking_reservations(
  p_organization_id uuid,
  p_booking_id uuid,
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
  v_resource_count bigint := 0;
  v_space_count bigint := 0;
BEGIN
  IF nullif(current_setting('app.organization_id', true), '')::uuid
     IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;
  IF p_reason_code IS NULL OR length(btrim(p_reason_code)) = 0 THEN
    RAISE EXCEPTION 'release reason is required' USING ERRCODE = '22023';
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

  UPDATE eogp.resource_reservations
     SET status = 'released'
   WHERE organization_id = p_organization_id
     AND booking_id = p_booking_id
     AND status IN ('held','confirmed')
     AND ends_at > clock_timestamp();
  GET DIAGNOSTICS v_resource_count = ROW_COUNT;

  UPDATE eogp.venue_space_time_blocks
     SET status = 'released',
         updated_at = clock_timestamp()
   WHERE organization_id = p_organization_id
     AND booking_id = p_booking_id
     AND status = 'confirmed'
     AND ends_at > clock_timestamp();
  GET DIAGNOSTICS v_space_count = ROW_COUNT;

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
        'spaceReservationsReleased', v_space_count
      )
    );
  END IF;

  RETURN v_resource_count + v_space_count;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.release_booking_reservations(uuid,uuid,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.release_booking_reservations(uuid,uuid,uuid,text)
  TO eventor_runtime;

