-- Queue-driven expiry for issued booking offers. The queue is deliberately
-- tenant-key-only; the worker discovers due tenants globally, then expires
-- offers inside a tenant-scoped SECURITY DEFINER command.
CREATE TABLE eogp.booking_offer_expiry_tenant_queue (
  organization_id uuid PRIMARY KEY,
  available_at timestamptz NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

REVOKE ALL ON eogp.booking_offer_expiry_tenant_queue
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

CREATE FUNCTION eogp.refresh_booking_offer_expiry_tenant_queue(
  p_organization_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_next_expiry timestamptz;
BEGIN
  SELECT min(revision.valid_until)
    INTO v_next_expiry
    FROM eogp.booking_offers offer
    JOIN LATERAL (
      SELECT item.state,item.valid_until
        FROM eogp.booking_offer_revisions item
       WHERE item.organization_id=offer.organization_id
         AND item.offer_id=offer.id
       ORDER BY item.revision_number DESC
       LIMIT 1
    ) revision ON true
   WHERE offer.organization_id=p_organization_id
     AND offer.status='issued'
     AND revision.state='issued'
     AND revision.valid_until IS NOT NULL;

  IF v_next_expiry IS NULL THEN
    DELETE FROM eogp.booking_offer_expiry_tenant_queue
     WHERE organization_id=p_organization_id;
  ELSE
    INSERT INTO eogp.booking_offer_expiry_tenant_queue(
      organization_id,available_at,updated_at
    ) VALUES (p_organization_id,v_next_expiry,clock_timestamp())
    ON CONFLICT (organization_id) DO UPDATE
      SET available_at=EXCLUDED.available_at,
          updated_at=EXCLUDED.updated_at;
  END IF;
END;
$function$;

CREATE FUNCTION eogp.booking_offer_expiry_queue_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_organization_id uuid;
BEGIN
  v_organization_id := CASE WHEN TG_OP='DELETE' THEN OLD.organization_id ELSE NEW.organization_id END;
  PERFORM eogp.refresh_booking_offer_expiry_tenant_queue(v_organization_id);
  IF TG_OP='DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER booking_offer_expiry_queue_offer
AFTER INSERT OR UPDATE OF status ON eogp.booking_offers
FOR EACH ROW EXECUTE FUNCTION eogp.booking_offer_expiry_queue_trigger();

CREATE TRIGGER booking_offer_expiry_queue_revision
AFTER INSERT OR UPDATE OF state,valid_until ON eogp.booking_offer_revisions
FOR EACH ROW EXECUTE FUNCTION eogp.booking_offer_expiry_queue_trigger();

CREATE FUNCTION eogp.discover_due_booking_offer_expiry_tenants()
RETURNS TABLE(organization_id uuid)
LANGUAGE plpgsql
SET search_path=pg_catalog,eogp
AS $function$
BEGIN
  IF session_user<>'eventor_worker' THEN
    RAISE EXCEPTION 'booking offer expiry discovery requires eventor_worker'
      USING ERRCODE='42501';
  END IF;
  RETURN QUERY
    SELECT queue.organization_id
      FROM eogp.booking_offer_expiry_tenant_queue queue
     WHERE queue.available_at<=clock_timestamp()
     ORDER BY queue.available_at,queue.organization_id
     LIMIT 1000;
END;
$function$;

CREATE FUNCTION eogp.expire_due_booking_offers(
  p_organization_id uuid,
  p_limit integer DEFAULT 100
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_offer record;
  v_now timestamptz;
  v_expired integer := 0;
BEGIN
  IF session_user<>'eventor_worker'
     OR eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'booking offer expiry requires worker role and matching tenant context'
      USING ERRCODE='42501';
  END IF;
  IF p_limit IS NULL OR p_limit NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION 'expiry batch limit must be between 1 and 500'
      USING ERRCODE='22023';
  END IF;

  FOR v_offer IN
    SELECT offer.id AS offer_id,revision.id AS revision_id
      FROM eogp.booking_offers offer
      JOIN LATERAL (
        SELECT item.id,item.state,item.valid_until
          FROM eogp.booking_offer_revisions item
         WHERE item.organization_id=offer.organization_id
           AND item.offer_id=offer.id
         ORDER BY item.revision_number DESC
         LIMIT 1
      ) revision ON true
     WHERE offer.organization_id=p_organization_id
       AND offer.status='issued'
       AND revision.state='issued'
       AND revision.valid_until<=clock_timestamp()
     ORDER BY revision.valid_until,offer.id
     FOR UPDATE OF offer SKIP LOCKED
     LIMIT p_limit
  LOOP
    v_now := clock_timestamp();

    UPDATE eogp.booking_offer_revisions
       SET state='expired'
     WHERE organization_id=p_organization_id
       AND id=v_offer.revision_id
       AND state='issued';

    UPDATE eogp.booking_offers
       SET status='expired'
     WHERE organization_id=p_organization_id
       AND id=v_offer.offer_id
       AND status='issued';

    UPDATE eogp.external_action_capabilities
       SET use_count=max_uses,
           revoked_at=coalesce(revoked_at,v_now)
     WHERE organization_id=p_organization_id
       AND offer_revision_id=v_offer.revision_id
       AND action_code='offer_accept'
       AND revoked_at IS NULL;

    INSERT INTO eogp.booking_offer_decision_history(
      organization_id,offer_id,offer_revision_id,decision,actor_kind,
      reason_code,occurred_at
    ) VALUES (
      p_organization_id,v_offer.offer_id,v_offer.revision_id,'expired','system',
      'offer_expired_by_scheduled_sweep',v_now
    );

    INSERT INTO eogp.audit_events(
      organization_id,actor_kind,action,aggregate_type,aggregate_id,
      reason_code,safe_metadata,occurred_at
    ) VALUES (
      p_organization_id,'system','booking.offer.expired','booking_offer',v_offer.offer_id,
      'offer_expired_by_scheduled_sweep',
      jsonb_build_object('offerRevisionId',v_offer.revision_id,'source','worker_expiry_sweep'),
      v_now
    );

    v_expired := v_expired+1;
  END LOOP;

  PERFORM eogp.refresh_booking_offer_expiry_tenant_queue(p_organization_id);
  RETURN v_expired;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.refresh_booking_offer_expiry_tenant_queue(uuid)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.booking_offer_expiry_queue_trigger()
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.discover_due_booking_offer_expiry_tenants()
  FROM PUBLIC,eventor_runtime,eventor_auth;
REVOKE ALL ON FUNCTION eogp.expire_due_booking_offers(uuid,integer)
  FROM PUBLIC,eventor_runtime,eventor_auth;

GRANT SELECT ON eogp.booking_offer_expiry_tenant_queue TO eventor_worker;
GRANT EXECUTE ON FUNCTION eogp.discover_due_booking_offer_expiry_tenants(),
  eogp.expire_due_booking_offers(uuid,integer)
  TO eventor_worker;
