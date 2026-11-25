-- Event owners may end their association without authority to mutate the source booking.
CREATE FUNCTION eogp.assert_event_booking_link_end_permission(p_org uuid,p_event uuid,p_actor uuid,p_link uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
BEGIN
 IF eogp.current_organization_id() IS DISTINCT FROM p_org OR nullif(current_setting('app.actor_membership_id',true),'')::uuid IS DISTINCT FROM p_actor THEN RAISE EXCEPTION 'organization or actor context mismatch' USING ERRCODE='42501';END IF;
 PERFORM eogp.assert_event_command_permission(p_org,p_event,p_actor,'event.manage');
 IF p_event IS NULL OR p_link IS NULL THEN RAISE EXCEPTION 'event and link identities required' USING ERRCODE='22023';END IF;
 -- Same lock order as link creation and notice publication; an ending wins wholly before/after publication.
 PERFORM 1 FROM eogp.events WHERE organization_id=p_org AND id=p_event FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE='P0002';END IF;
 PERFORM 1 FROM eogp.booking_event_links WHERE organization_id=p_org AND event_id=p_event AND id=p_link;
 IF NOT FOUND THEN RAISE EXCEPTION 'event booking link not found' USING ERRCODE='P0002';END IF;
END;
$function$;
CREATE FUNCTION eogp.end_event_booking_link(p_org uuid,p_event uuid,p_actor uuid,p_link uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_link eogp.booking_event_links%ROWTYPE;
BEGIN
 PERFORM eogp.assert_event_booking_link_end_permission(p_org,p_event,p_actor,p_link);
 SELECT * INTO STRICT v_link FROM eogp.booking_event_links WHERE organization_id=p_org AND event_id=p_event AND id=p_link FOR UPDATE;
 IF v_link.status='revoked' THEN RAISE EXCEPTION 'revoked association cannot be relabelled as ended' USING ERRCODE='55000';END IF;
 IF v_link.status='active' THEN
  -- Existing trigger preserves authentic actor, immutable relation and one terminal audit.
  UPDATE eogp.booking_event_links SET status='ended',status_changed_by_membership_id=p_actor,status_change_reason_code='event_manager_ended'
   WHERE organization_id=p_org AND event_id=p_event AND id=p_link RETURNING * INTO v_link;
 END IF;
 RETURN jsonb_build_object('linkId',v_link.id,'eventId',v_link.event_id,'bookingOwnerOrganizationId',v_link.booking_owner_organization_id,
  'bookingId',v_link.booking_id,'collaborationGrantId',v_link.collaboration_grant_id,'relationshipKind',v_link.relationship_kind,'status',v_link.status,'createdAt',v_link.created_at);
END;
$function$;
REVOKE ALL ON FUNCTION eogp.assert_event_booking_link_end_permission(uuid,uuid,uuid,uuid),eogp.end_event_booking_link(uuid,uuid,uuid,uuid) FROM PUBLIC,eventor_auth,eventor_worker;
GRANT EXECUTE ON FUNCTION eogp.assert_event_booking_link_end_permission(uuid,uuid,uuid,uuid),eogp.end_event_booking_link(uuid,uuid,uuid,uuid) TO eventor_runtime;
