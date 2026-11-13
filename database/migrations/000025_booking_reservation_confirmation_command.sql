-- Atomic conversion of draft holds into confirmed booking reservations.
-- Runtime has no UPDATE grant on reservation rows; this narrow command owns the
-- conversion and records one actor/reason audit event.
CREATE FUNCTION eogp.confirm_booking_reservations(
  p_organization_id uuid,
  p_booking_draft_revision_id uuid,
  p_booking_id uuid,
  p_actor_membership_id uuid,
  p_reason_code text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_booking_status text;
  v_offer_revision_id uuid;
  v_offer_draft_revision_id uuid;
  v_offer_state text;
  v_snapshot_offer_revision_id uuid;
  v_member_status text;
  v_resource eogp.resource_reservations%ROWTYPE;
  v_source_line eogp.booking_resource_lines%ROWTYPE;
  v_booking_line_ids uuid[];
  v_booking_line_id uuid;
  v_resource_count bigint := 0;
  v_space_count bigint := 0;
  v_expired_resource_count bigint := 0;
  v_expired_space_count bigint := 0;
BEGIN
  IF nullif(current_setting('app.organization_id', true), '')::uuid
     IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;
  IF p_reason_code IS NULL OR length(btrim(p_reason_code)) = 0 THEN
    RAISE EXCEPTION 'booking confirmation reason is required' USING ERRCODE = '22023';
  END IF;

  SELECT status, source_offer_revision_id
    INTO v_booking_status, v_offer_revision_id
    FROM eogp.booking_records
   WHERE organization_id = p_organization_id AND id = p_booking_id
   FOR UPDATE;
  IF NOT FOUND OR v_booking_status <> 'confirmed' THEN
    RAISE EXCEPTION 'a confirmed booking is required for reservation conversion'
      USING ERRCODE = '55000';
  END IF;

  SELECT draft_revision_id, state
    INTO v_offer_draft_revision_id, v_offer_state
    FROM eogp.booking_offer_revisions
   WHERE organization_id = p_organization_id AND id = v_offer_revision_id
   FOR SHARE;
  IF NOT FOUND
     OR v_offer_draft_revision_id IS DISTINCT FROM p_booking_draft_revision_id
     OR v_offer_state <> 'accepted' THEN
    RAISE EXCEPTION 'booking must originate from the accepted offer revision for this draft'
      USING ERRCODE = '23514';
  END IF;

  SELECT offer_revision_id INTO v_snapshot_offer_revision_id
    FROM eogp.booking_confirmed_snapshots
   WHERE organization_id = p_organization_id AND booking_id = p_booking_id
   FOR SHARE;
  IF NOT FOUND OR v_snapshot_offer_revision_id IS DISTINCT FROM v_offer_revision_id THEN
    RAISE EXCEPTION 'booking confirmed snapshot must pin the source offer revision'
      USING ERRCODE = '23514';
  END IF;

  SELECT status INTO v_member_status
    FROM eogp.organization_memberships
   WHERE organization_id = p_organization_id AND id = p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_member_status <> 'active' THEN
    RAISE EXCEPTION 'active booking-owner membership is required'
      USING ERRCODE = '42501';
  END IF;

  PERFORM 1
    FROM eogp.user_role_grants AS user_grant
    JOIN eogp.role_permissions AS role_permission
      ON role_permission.organization_id = user_grant.organization_id
     AND role_permission.role_id = user_grant.role_id
   WHERE user_grant.organization_id = p_organization_id
     AND user_grant.membership_id = p_actor_membership_id
     AND user_grant.revoked_at IS NULL
     AND (user_grant.expires_at IS NULL OR user_grant.expires_at > clock_timestamp())
     AND role_permission.permission_code = 'booking.confirm'
     AND (user_grant.scope_kind = 'organization'
       OR (user_grant.scope_kind = 'booking' AND user_grant.scope_booking_id = p_booking_id))
   FOR SHARE OF user_grant, role_permission;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'booking.confirm permission is required for this booking'
      USING ERRCODE = '42501';
  END IF;

  UPDATE eogp.resource_reservations
     SET status = 'expired'
   WHERE organization_id = p_organization_id
     AND booking_draft_revision_id = p_booking_draft_revision_id
     AND status = 'held' AND expires_at <= clock_timestamp();
  GET DIAGNOSTICS v_expired_resource_count = ROW_COUNT;

  UPDATE eogp.venue_space_time_blocks
     SET status = 'expired', updated_at = clock_timestamp()
   WHERE organization_id = p_organization_id
     AND booking_draft_revision_id = p_booking_draft_revision_id
     AND status = 'held' AND expires_at <= clock_timestamp();
  GET DIAGNOSTICS v_expired_space_count = ROW_COUNT;

  FOR v_resource IN
    SELECT reservation.*
      FROM eogp.resource_reservations AS reservation
     WHERE reservation.organization_id = p_organization_id
       AND reservation.booking_draft_revision_id = p_booking_draft_revision_id
       AND reservation.status = 'held'
       AND reservation.expires_at > clock_timestamp()
     ORDER BY reservation.resource_pool_id NULLS LAST,
              reservation.resource_unit_id NULLS LAST, reservation.id
     FOR UPDATE OF reservation
  LOOP
    v_booking_line_id := NULL;

    IF v_resource.booking_resource_line_id IS NOT NULL THEN
      SELECT * INTO v_source_line
        FROM eogp.booking_resource_lines
       WHERE organization_id = p_organization_id
         AND id = v_resource.booking_resource_line_id
         AND draft_revision_id = p_booking_draft_revision_id
       FOR SHARE;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'draft reservation resource line does not belong to the confirmed draft'
          USING ERRCODE = '23503';
      END IF;

      SELECT array_agg(line.id ORDER BY line.id) INTO v_booking_line_ids
        FROM eogp.booking_resource_lines AS line
       WHERE line.organization_id = p_organization_id
         AND line.booking_id = p_booking_id
         AND line.draft_revision_id IS NULL
         AND line.resource_type_id = v_source_line.resource_type_id
         AND line.line_code = v_source_line.line_code;
      IF coalesce(cardinality(v_booking_line_ids), 0) <> 1 THEN
        RAISE EXCEPTION 'draft resource line must map to exactly one booking resource line'
          USING ERRCODE = '23514',
                DETAIL = format('draft line %s maps to %s booking lines',
                  v_source_line.id, coalesce(cardinality(v_booking_line_ids), 0));
      END IF;
      v_booking_line_id := v_booking_line_ids[1];
    END IF;

    UPDATE eogp.resource_reservations SET status = 'released'
     WHERE organization_id = p_organization_id AND id = v_resource.id AND status = 'held';

    IF v_resource.resource_pool_id IS NOT NULL THEN
      PERFORM eogp.reserve_pooled_resource(
        p_organization_id, v_resource.resource_pool_id, NULL, p_booking_id,
        v_booking_line_id, v_resource.starts_at, v_resource.ends_at,
        v_resource.quantity, NULL, 'confirm-' || v_resource.id::text
      );
    ELSE
      PERFORM eogp.reserve_resource_unit(
        p_organization_id, v_resource.resource_unit_id, NULL, p_booking_id,
        NULL, v_booking_line_id, v_resource.starts_at, v_resource.ends_at,
        NULL, 'confirm-' || v_resource.id::text
      );
    END IF;
    v_resource_count := v_resource_count + 1;
  END LOOP;

  UPDATE eogp.venue_space_time_blocks
     SET reservation_kind = 'booking',
         booking_draft_revision_id = NULL,
         booking_id = p_booking_id,
         status = 'confirmed',
         expires_at = NULL,
         updated_at = clock_timestamp()
   WHERE organization_id = p_organization_id
     AND booking_draft_revision_id = p_booking_draft_revision_id
     AND status = 'held' AND expires_at > clock_timestamp();
  GET DIAGNOSTICS v_space_count = ROW_COUNT;

  IF v_resource_count + v_space_count > 0 THEN
    INSERT INTO eogp.audit_events (
      organization_id, actor_organization_id, actor_membership_id, actor_kind,
      action, aggregate_type, aggregate_id, reason_code, safe_metadata
    ) VALUES (
      p_organization_id, p_organization_id, p_actor_membership_id, 'membership',
      'booking.reservations.confirmed', 'booking', p_booking_id, p_reason_code,
      jsonb_build_object(
        'resourceReservationsConfirmed', v_resource_count,
        'spaceReservationsConfirmed', v_space_count,
        'expiredResourceHolds', v_expired_resource_count,
        'expiredSpaceHolds', v_expired_space_count
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'bookingId', p_booking_id,
    'resourceReservationsConfirmed', v_resource_count,
    'spaceReservationsConfirmed', v_space_count,
    'expiredResourceHolds', v_expired_resource_count,
    'expiredSpaceHolds', v_expired_space_count,
    'changed', (v_resource_count + v_space_count + v_expired_resource_count + v_expired_space_count) > 0
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.confirm_booking_reservations(uuid,uuid,uuid,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.confirm_booking_reservations(uuid,uuid,uuid,uuid,text)
  TO eventor_runtime;
