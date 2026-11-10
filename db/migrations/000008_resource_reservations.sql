-- Eventor migration 000008: 000008_resource_reservations.sql
-- Apply only through scripts/db/apply-migrations.sh so the checksum ledger is updated.
BEGIN;
SET LOCAL search_path TO eogp, public;

SET LOCAL search_path TO eogp, public;

CREATE TABLE eogp.venue_space_time_blocks (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id         uuid NOT NULL,
  venue_space_id          uuid NOT NULL,
  booking_draft_revision_id uuid,
  booking_id              uuid,
  maintenance_window_id    uuid,
  block_kind              text NOT NULL CHECK (block_kind IN ('hold','setup','rehearsal','event_use','teardown','buffer','maintenance','closure')),
  status                  text NOT NULL CHECK (status IN ('held','confirmed','maintenance','blocked','released','cancelled','consumed','expired')),
  starts_at               timestamptz NOT NULL,
  ends_at                 timestamptz NOT NULL,
  expires_at              timestamptz,
  idempotency_key         text,
  created_at              timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at              timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  FOREIGN KEY (organization_id, venue_space_id)
    REFERENCES eogp.venue_spaces(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, booking_draft_revision_id)
    REFERENCES eogp.booking_draft_revisions(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, booking_id)
    REFERENCES eogp.booking_records(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, maintenance_window_id)
    REFERENCES eogp.maintenance_windows(organization_id, id) ON DELETE RESTRICT,
  CHECK (ends_at > starts_at),
  CHECK (num_nonnulls(booking_draft_revision_id, booking_id, maintenance_window_id) = 1),
  CHECK (status <> 'held' OR expires_at IS NOT NULL),
  CHECK (status = 'held' OR expires_at IS NULL)
);

ALTER TABLE eogp.venue_space_time_blocks
  ADD CONSTRAINT venue_space_time_no_overlap
  EXCLUDE USING gist (
    organization_id WITH =,
    venue_space_id WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&
  )
  WHERE (status IN ('held','confirmed','maintenance','blocked'));

CREATE INDEX venue_space_time_blocks_booking_idx
  ON eogp.venue_space_time_blocks(organization_id, booking_id)
  WHERE booking_id IS NOT NULL;

CREATE INDEX venue_space_time_blocks_expiry_idx
  ON eogp.venue_space_time_blocks(expires_at)
  WHERE status = 'held';

CREATE TABLE eogp.resource_reservations (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id   uuid NOT NULL,
  resource_pool_id  uuid,
  resource_unit_id  uuid,
  booking_resource_line_id uuid NOT NULL,
  starts_at         timestamptz NOT NULL,
  ends_at           timestamptz NOT NULL,
  quantity          numeric(14,3) NOT NULL CHECK (quantity > 0),
  status            text NOT NULL CHECK (status IN ('held','confirmed','released','cancelled','consumed','expired')),
  expires_at        timestamptz,
  created_at        timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at        timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  FOREIGN KEY (organization_id, resource_pool_id)
    REFERENCES eogp.resource_pools(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, resource_unit_id)
    REFERENCES eogp.resource_units(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, booking_resource_line_id)
    REFERENCES eogp.booking_resource_lines(organization_id, id) ON DELETE RESTRICT,
  CHECK (ends_at > starts_at),
  CHECK (num_nonnulls(resource_pool_id, resource_unit_id) = 1),
  CHECK (status <> 'held' OR expires_at IS NOT NULL),
  CHECK (status = 'held' OR expires_at IS NULL),
  CHECK (resource_unit_id IS NULL OR quantity = 1)
);

ALTER TABLE eogp.resource_reservations
  ADD CONSTRAINT resource_unit_time_no_overlap
  EXCLUDE USING gist (
    organization_id WITH =,
    resource_unit_id WITH =,
    tstzrange(starts_at, ends_at, '[)') WITH &&
  )
  WHERE (resource_unit_id IS NOT NULL AND status IN ('held','confirmed'));

CREATE INDEX resource_reservations_pool_time_idx
  ON eogp.resource_reservations(organization_id, resource_pool_id, starts_at, ends_at)
  WHERE resource_pool_id IS NOT NULL AND status IN ('held','confirmed');

CREATE FUNCTION eogp.enforce_pooled_resource_capacity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = eogp, pg_temp
AS $$
DECLARE
  v_capacity numeric(14,3);
  v_mode text;
  v_line_pool uuid;
  v_peak numeric(14,3);
BEGIN
  IF NEW.resource_pool_id IS NULL OR NEW.status NOT IN ('held','confirmed') THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND (OLD.resource_pool_id IS DISTINCT FROM NEW.resource_pool_id
          OR OLD.resource_unit_id IS DISTINCT FROM NEW.resource_unit_id
          OR OLD.organization_id IS DISTINCT FROM NEW.organization_id) THEN
    RAISE EXCEPTION 'Reservation target is immutable; release and create a new reservation'
      USING ERRCODE = '23514';
  END IF;

  SELECT reservation_mode, capacity_quantity
    INTO v_mode, v_capacity
    FROM eogp.resource_pools
   WHERE organization_id = NEW.organization_id
     AND id = NEW.resource_pool_id
   FOR UPDATE;

  IF NOT FOUND OR v_mode <> 'pooled' THEN
    RAISE EXCEPTION 'Pooled reservation must reference an active pooled resource'
      USING ERRCODE = '23503';
  END IF;

  SELECT resource_pool_id
    INTO v_line_pool
    FROM eogp.booking_resource_lines
   WHERE organization_id = NEW.organization_id
     AND id = NEW.booking_resource_line_id;

  IF v_line_pool IS DISTINCT FROM NEW.resource_pool_id THEN
    RAISE EXCEPTION 'Reservation pool does not match its booking resource line'
      USING ERRCODE = '23514';
  END IF;

  WITH existing AS (
    SELECT starts_at, ends_at, quantity
      FROM eogp.resource_reservations
     WHERE organization_id = NEW.organization_id
       AND resource_pool_id = NEW.resource_pool_id
       AND status IN ('held','confirmed')
       AND id <> COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
       AND tstzrange(starts_at, ends_at, '[)') && tstzrange(NEW.starts_at, NEW.ends_at, '[)')
  ),
  points AS (
    SELECT NEW.starts_at AS point
    UNION
    SELECT GREATEST(starts_at, NEW.starts_at) FROM existing
    UNION
    SELECT LEAST(ends_at, NEW.ends_at) FROM existing
  ),
  segments AS (
    SELECT DISTINCT point FROM points WHERE point < NEW.ends_at
  ),
  usage_at_point AS (
    SELECT s.point, COALESCE(SUM(e.quantity), 0) AS existing_quantity
      FROM segments s
      LEFT JOIN existing e ON e.starts_at <= s.point AND e.ends_at > s.point
     GROUP BY s.point
  )
  SELECT COALESCE(MAX(existing_quantity + NEW.quantity), NEW.quantity)
    INTO v_peak
    FROM usage_at_point;

  IF v_peak > v_capacity THEN
    RAISE EXCEPTION 'Pooled resource capacity exceeded: peak %, capacity %', v_peak, v_capacity
      USING ERRCODE = '23P01';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER resource_reservations_pool_capacity_trg
BEFORE INSERT OR UPDATE OF resource_pool_id, resource_unit_id, booking_resource_line_id,
                           starts_at, ends_at, quantity, status
ON eogp.resource_reservations
FOR EACH ROW
EXECUTE FUNCTION eogp.enforce_pooled_resource_capacity();

INSERT INTO eogp.schema_migrations(version, filename, checksum_sha256)
VALUES ('000008', '000008_resource_reservations.sql', :'migration_checksum');
COMMIT;
