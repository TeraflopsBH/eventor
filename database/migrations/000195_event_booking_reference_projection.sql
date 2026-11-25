-- Show a local booking reference only under the actor's own booking-management scope.
CREATE INDEX booking_event_links_event_history_idx ON eogp.booking_event_links(organization_id,event_id,created_at DESC,id);
CREATE OR REPLACE FUNCTION eogp.list_event_booking_links(p_org uuid,p_event uuid,p_actor uuid,p_offset integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_rows jsonb;
BEGIN
 IF eogp.current_organization_id() IS DISTINCT FROM p_org OR nullif(current_setting('app.actor_membership_id',true),'')::uuid IS DISTINCT FROM p_actor THEN RAISE EXCEPTION 'organization or actor context mismatch' USING ERRCODE='42501';END IF;
 PERFORM eogp.assert_event_command_permission(p_org,p_event,p_actor,'event.manage');
 IF p_event IS NULL OR coalesce(p_offset,-1) NOT BETWEEN 0 AND 100000 THEN RAISE EXCEPTION 'invalid event association page' USING ERRCODE='22023';END IF;
 PERFORM 1 FROM eogp.events WHERE organization_id=p_org AND id=p_event;
 IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE='P0002';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('bookingCode',(SELECT record.booking_code FROM eogp.booking_records record WHERE record.organization_id=p_org AND record.id=link.booking_id AND link.booking_owner_organization_id=p_org AND EXISTS(
    SELECT 1 FROM eogp.user_role_grants assignment JOIN eogp.role_permissions permission ON permission.organization_id=assignment.organization_id AND permission.role_id=assignment.role_id
    WHERE assignment.organization_id=p_org AND assignment.membership_id=p_actor AND assignment.revoked_at IS NULL AND (assignment.expires_at IS NULL OR assignment.expires_at>statement_timestamp())
     AND permission.permission_code='booking.manage' AND (assignment.scope_kind='organization' OR (assignment.scope_kind='booking' AND assignment.scope_booking_id=record.id)))),'linkId',link.id,'eventId',link.event_id,'bookingOwnerOrganizationId',link.booking_owner_organization_id,'bookingId',link.booking_id,'collaborationGrantId',link.collaboration_grant_id,'relationshipKind',link.relationship_kind,'status',link.status,'createdAt',link.created_at) ORDER BY link.created_at DESC,link.id),'[]'::jsonb) INTO v_rows
 FROM(SELECT * FROM eogp.booking_event_links WHERE organization_id=p_org AND event_id=p_event ORDER BY created_at DESC,id LIMIT 51 OFFSET p_offset) link;
 INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,action,aggregate_type,aggregate_id)
 VALUES(p_org,p_org,p_actor,'membership','event.booking_links.viewed','event',p_event);
 RETURN jsonb_build_object('links',CASE WHEN jsonb_array_length(v_rows)>50 THEN v_rows-50 ELSE v_rows END,'nextOffset',CASE WHEN jsonb_array_length(v_rows)>50 AND p_offset<=99950 THEN p_offset+50 END);
END;
$function$;
