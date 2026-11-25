-- Turn the existing association aggregate into an authorized command boundary.
REVOKE ALL ON eogp.booking_event_links FROM PUBLIC,eventor_runtime,eventor_auth,eventor_worker;

CREATE FUNCTION eogp.assert_event_booking_link_permission(p_org uuid,p_event uuid,p_actor uuid,p_booking_owner uuid,p_booking uuid,p_grant uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
BEGIN
 IF eogp.current_organization_id() IS DISTINCT FROM p_org OR nullif(current_setting('app.actor_membership_id',true),'')::uuid IS DISTINCT FROM p_actor THEN
  RAISE EXCEPTION 'organization or actor context mismatch' USING ERRCODE='42501';END IF;
 PERFORM eogp.assert_event_command_permission(p_org,p_event,p_actor,'event.manage');
 IF p_event IS NULL OR p_booking_owner IS NULL OR p_booking IS NULL THEN RAISE EXCEPTION 'event and booking identities required' USING ERRCODE='22023';END IF;
 -- Serialize duplicate association creation before its audited BEFORE INSERT trigger runs.
 PERFORM 1 FROM eogp.events WHERE organization_id=p_org AND id=p_event FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE='P0002';END IF;
 IF p_booking_owner=p_org THEN
  IF p_grant IS NOT NULL THEN RAISE EXCEPTION 'same-organization links do not use a collaboration grant' USING ERRCODE='22023';END IF;
  PERFORM eogp.assert_booking_cancellation_permission(p_org,p_booking,p_actor,'booking.manage');
  PERFORM 1 FROM eogp.booking_records WHERE organization_id=p_org AND id=p_booking FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'booking not found' USING ERRCODE='P0002';END IF;
 ELSE
  PERFORM 1 FROM eogp.collaboration_grants WHERE organization_id=p_booking_owner AND grantee_organization_id=p_org AND id=p_grant
   AND scope_kind='booking' AND scope_booking_id=p_booking AND status='active'
   AND valid_from<=clock_timestamp() AND (valid_until IS NULL OR valid_until>clock_timestamp())
   AND allowed_actions @> ARRAY['booking.event.link']::text[] FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'active booking-scoped collaboration authority required' USING ERRCODE='42501';END IF;
 END IF;
END;
$function$;

CREATE FUNCTION eogp.create_event_booking_link(p_org uuid,p_event uuid,p_actor uuid,p_booking_owner uuid,p_booking uuid,p_grant uuid,p_kind text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_link eogp.booking_event_links%ROWTYPE;
BEGIN
 PERFORM eogp.assert_event_booking_link_permission(p_org,p_event,p_actor,p_booking_owner,p_booking,p_grant);
 IF p_kind IS NULL OR p_kind NOT IN('venue_for_event','service_for_event','other') THEN RAISE EXCEPTION 'invalid booking/event relationship' USING ERRCODE='22023';END IF;
 SELECT * INTO v_link FROM eogp.booking_event_links WHERE organization_id=p_org AND event_id=p_event AND booking_owner_organization_id=p_booking_owner AND booking_id=p_booking FOR UPDATE;
 IF FOUND THEN
  IF v_link.status<>'active' OR v_link.relationship_kind IS DISTINCT FROM p_kind OR v_link.collaboration_grant_id IS DISTINCT FROM p_grant THEN
   RAISE EXCEPTION 'existing association requires separate correction' USING ERRCODE='55000';END IF;
 ELSE
  INSERT INTO eogp.booking_event_links(organization_id,booking_owner_organization_id,booking_id,event_id,grant_owner_organization_id,collaboration_grant_id,relationship_kind,created_by_membership_id)
  VALUES(p_org,p_booking_owner,p_booking,p_event,CASE WHEN p_booking_owner<>p_org THEN p_booking_owner ELSE NULL END,p_grant,p_kind,p_actor) RETURNING * INTO v_link;
 END IF;
 RETURN jsonb_build_object('linkId',v_link.id,'eventId',v_link.event_id,'bookingOwnerOrganizationId',v_link.booking_owner_organization_id,'bookingId',v_link.booking_id,'collaborationGrantId',v_link.collaboration_grant_id,'relationshipKind',v_link.relationship_kind,'status',v_link.status,'createdAt',v_link.created_at);
END;
$function$;

CREATE FUNCTION eogp.list_event_booking_links(p_org uuid,p_event uuid,p_actor uuid,p_offset integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_rows jsonb;
BEGIN
 IF eogp.current_organization_id() IS DISTINCT FROM p_org OR nullif(current_setting('app.actor_membership_id',true),'')::uuid IS DISTINCT FROM p_actor THEN RAISE EXCEPTION 'organization or actor context mismatch' USING ERRCODE='42501';END IF;
 PERFORM eogp.assert_event_command_permission(p_org,p_event,p_actor,'event.manage');
 IF p_event IS NULL OR coalesce(p_offset,-1) NOT BETWEEN 0 AND 100000 THEN RAISE EXCEPTION 'invalid event association page' USING ERRCODE='22023';END IF;
 PERFORM 1 FROM eogp.events WHERE organization_id=p_org AND id=p_event;
 IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE='P0002';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('linkId',link.id,'eventId',link.event_id,'bookingOwnerOrganizationId',link.booking_owner_organization_id,'bookingId',link.booking_id,'collaborationGrantId',link.collaboration_grant_id,'relationshipKind',link.relationship_kind,'status',link.status,'createdAt',link.created_at) ORDER BY link.created_at DESC,link.id),'[]'::jsonb) INTO v_rows
 FROM(SELECT * FROM eogp.booking_event_links WHERE organization_id=p_org AND event_id=p_event ORDER BY created_at DESC,id LIMIT 51 OFFSET p_offset) link;
 INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,action,aggregate_type,aggregate_id)
 VALUES(p_org,p_org,p_actor,'membership','event.booking_links.viewed','event',p_event);
 RETURN jsonb_build_object('links',CASE WHEN jsonb_array_length(v_rows)>50 THEN v_rows-50 ELSE v_rows END,'nextOffset',CASE WHEN jsonb_array_length(v_rows)>50 AND p_offset<100000 THEN p_offset+50 END);
END;
$function$;
REVOKE ALL ON FUNCTION eogp.assert_event_booking_link_permission(uuid,uuid,uuid,uuid,uuid,uuid),eogp.create_event_booking_link(uuid,uuid,uuid,uuid,uuid,uuid,text),eogp.list_event_booking_links(uuid,uuid,uuid,integer) FROM PUBLIC,eventor_auth,eventor_worker;
GRANT EXECUTE ON FUNCTION eogp.assert_event_booking_link_permission(uuid,uuid,uuid,uuid,uuid,uuid),eogp.create_event_booking_link(uuid,uuid,uuid,uuid,uuid,uuid,text),eogp.list_event_booking_links(uuid,uuid,uuid,integer) TO eventor_runtime;
