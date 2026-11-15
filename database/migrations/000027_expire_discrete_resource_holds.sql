-- Expire both pooled and individually tracked unit holds.
-- resource_reservations.resource_pool_id is NULL for discrete-unit rows, so
-- resolve their pool through resource_units before taking the shared pool lock.
CREATE OR REPLACE FUNCTION eogp.expire_resource_holds(p_organization_id uuid)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_count bigint := 0;
  v_pool_id uuid;
  v_changed bigint;
BEGIN
  IF nullif(current_setting('app.organization_id', true), '')::uuid
     IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;

  FOR v_pool_id IN
    SELECT DISTINCT coalesce(reservation.resource_pool_id, unit.resource_pool_id)
      FROM eogp.resource_reservations AS reservation
      LEFT JOIN eogp.resource_units AS unit
        ON unit.organization_id = reservation.organization_id
       AND unit.id = reservation.resource_unit_id
     WHERE reservation.organization_id = p_organization_id
       AND reservation.status = 'held'
       AND reservation.expires_at <= clock_timestamp()
     ORDER BY 1
  LOOP
    -- Match the locking order used by reservation creation. This serializes
    -- expiry with pooled and unit reservation attempts in the same inventory.
    PERFORM 1
      FROM eogp.resource_pools
     WHERE organization_id = p_organization_id
       AND id = v_pool_id
     FOR UPDATE;

    UPDATE eogp.resource_reservations AS reservation
       SET status = 'expired'
     WHERE reservation.organization_id = p_organization_id
       AND reservation.status = 'held'
       AND reservation.expires_at <= clock_timestamp()
       AND (
         reservation.resource_pool_id = v_pool_id
         OR reservation.resource_unit_id IN (
           SELECT unit.id
             FROM eogp.resource_units AS unit
            WHERE unit.organization_id = p_organization_id
              AND unit.resource_pool_id = v_pool_id
         )
       );
    GET DIAGNOSTICS v_changed = ROW_COUNT;
    v_count := v_count + v_changed;
  END LOOP;

  RETURN v_count;
END;
$function$;

-- Preserve the worker-only execution boundary established in migration 000022.
REVOKE ALL ON FUNCTION eogp.expire_resource_holds(uuid)
  FROM PUBLIC, eventor_runtime, eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.expire_resource_holds(uuid) TO eventor_worker;
