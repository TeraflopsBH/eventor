REVOKE ALL ON eogp.booking_disruption_notices FROM PUBLIC,eventor_runtime;

CREATE FUNCTION eogp.list_booking_disruption_workspace(p_org uuid,p_actor uuid,p_offset integer,p_query text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_rows jsonb;
  v_query text := lower(btrim(coalesce(p_query,'')));
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_org
    OR nullif(current_setting('app.actor_membership_id',true),'')::uuid IS DISTINCT FROM p_actor THEN
    RAISE EXCEPTION 'organization or actor context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM 1 FROM eogp.organization_memberships WHERE organization_id=p_org AND id=p_actor AND status='active' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'active membership required' USING ERRCODE='42501'; END IF;
  IF coalesce(p_offset,-1) NOT BETWEEN 0 AND 100000 OR length(v_query)>80 THEN
    RAISE EXCEPTION 'invalid booking directory filter' USING ERRCODE='22023';
  END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object('bookingId',booking.id,'bookingCode',booking.booking_code,'status',booking.status)
    ORDER BY booking.confirmed_at DESC,booking.id),'[]'::jsonb) INTO v_rows
  FROM (
    SELECT record.id,record.booking_code,record.status,record.confirmed_at FROM eogp.booking_records record
    WHERE record.organization_id=p_org AND (v_query='' OR position(v_query in lower(record.booking_code))>0)
      AND EXISTS (
        SELECT 1 FROM eogp.user_role_grants assignment
        JOIN eogp.role_permissions permission ON permission.organization_id=assignment.organization_id AND permission.role_id=assignment.role_id
        WHERE assignment.organization_id=p_org AND assignment.membership_id=p_actor AND assignment.revoked_at IS NULL
          AND (assignment.expires_at IS NULL OR assignment.expires_at>statement_timestamp())
          AND permission.permission_code='booking.manage'
          AND (assignment.scope_kind='organization' OR (assignment.scope_kind='booking' AND assignment.scope_booking_id=record.id))
      )
    ORDER BY record.confirmed_at DESC,record.id LIMIT 51 OFFSET p_offset
  ) booking;
  RETURN jsonb_build_object('bookings',CASE WHEN jsonb_array_length(v_rows)>50 THEN v_rows-50 ELSE v_rows END,
    'nextOffset',CASE WHEN jsonb_array_length(v_rows)>50 AND p_offset<=99950 THEN p_offset+50 END);
END;
$function$;

CREATE FUNCTION eogp.read_booking_disruption_notices(p_org uuid,p_booking uuid,p_actor uuid,p_offset integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp
AS $function$
DECLARE v_notices jsonb;
BEGIN
  PERFORM eogp.assert_booking_cancellation_permission(p_org,p_booking,p_actor,'booking.manage');
  PERFORM 1 FROM eogp.booking_records WHERE organization_id=p_org AND id=p_booking FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'booking not found' USING ERRCODE='P0002'; END IF;
  IF coalesce(p_offset,-1) NOT BETWEEN 0 AND 100000 THEN RAISE EXCEPTION 'invalid notice offset' USING ERRCODE='22023'; END IF;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'noticeId',notice.id,'noticeCode',notice.notice_code,'reasonCategory',notice.reason_category,
    'publicSummary',notice.public_summary,'affectedFrom',notice.affected_from,'affectedUntil',notice.affected_until,
    'issuedAt',notice.issued_at
  ) ORDER BY notice.issued_at DESC,notice.id),'[]'::jsonb) INTO v_notices
  FROM (SELECT * FROM eogp.booking_disruption_notices WHERE organization_id=p_org AND booking_id=p_booking
    ORDER BY issued_at DESC,id LIMIT 51 OFFSET p_offset) notice;
  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,action,aggregate_type,aggregate_id)
  VALUES(p_org,p_org,p_actor,'membership','booking.disruption_notices.viewed','booking',p_booking);
  RETURN jsonb_build_object('notices',CASE WHEN jsonb_array_length(v_notices)>50 THEN v_notices-50 ELSE v_notices END,
    'nextOffset',CASE WHEN jsonb_array_length(v_notices)>50 AND p_offset<=99950 THEN p_offset+50 END);
END;
$function$;

CREATE FUNCTION eogp.record_booking_disruption_notice(
  p_org uuid,p_booking uuid,p_actor uuid,p_notice uuid,p_category text,p_summary text,p_from timestamptz,p_until timestamptz
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp
AS $function$
DECLARE v_notice eogp.booking_disruption_notices%ROWTYPE;
BEGIN
  PERFORM eogp.assert_booking_cancellation_permission(p_org,p_booking,p_actor,'booking.manage');
  PERFORM 1 FROM eogp.booking_records WHERE organization_id=p_org AND id=p_booking FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'booking not found' USING ERRCODE='P0002'; END IF;
  IF p_category IS NULL OR p_category !~ '^[a-z][a-z0-9_.-]{1,79}$'
    OR coalesce(length(btrim(p_summary)),0) NOT BETWEEN 1 AND 2000 OR regexp_replace(p_summary,E'[\n\r\t]','','g') ~ '[[:cntrl:]]'
    OR (p_from IS NOT NULL AND NOT isfinite(p_from)) OR (p_until IS NOT NULL AND NOT isfinite(p_until))
    OR (p_from IS NOT NULL AND p_until IS NOT NULL AND p_until<=p_from) THEN
    RAISE EXCEPTION 'invalid disruption notice' USING ERRCODE='22023';
  END IF;
  INSERT INTO eogp.booking_disruption_notices(id,organization_id,booking_id,notice_code,reason_category,public_summary,
    affected_from,affected_until,issued_by_membership_id)
  VALUES(p_notice,p_org,p_booking,'N-'||upper(p_notice::text),p_category,btrim(p_summary),p_from,p_until,p_actor)
  RETURNING * INTO v_notice;
  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,safe_metadata)
  VALUES(p_org,p_org,p_actor,'membership','booking.disruption_notice.recorded','booking_disruption_notice',p_notice,
    jsonb_build_object('bookingId',p_booking));
  RETURN jsonb_build_object('noticeId',v_notice.id,'noticeCode',v_notice.notice_code,'issuedAt',v_notice.issued_at);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.list_booking_disruption_workspace(uuid,uuid,integer,text),
  eogp.read_booking_disruption_notices(uuid,uuid,uuid,integer),
  eogp.record_booking_disruption_notice(uuid,uuid,uuid,uuid,text,text,timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.list_booking_disruption_workspace(uuid,uuid,integer,text),
  eogp.read_booking_disruption_notices(uuid,uuid,uuid,integer),
  eogp.record_booking_disruption_notice(uuid,uuid,uuid,uuid,text,text,timestamptz,timestamptz) TO eventor_runtime;
