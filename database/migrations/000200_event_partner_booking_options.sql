-- Event managers may discover only accepted booking scopes already shared with their organization.
CREATE FUNCTION eogp.list_event_partner_booking_options(p_org uuid,p_event uuid,p_actor uuid,p_offset integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_rows jsonb;
BEGIN
 IF eogp.current_organization_id() IS DISTINCT FROM p_org OR nullif(current_setting('app.actor_membership_id',true),'')::uuid IS DISTINCT FROM p_actor THEN RAISE EXCEPTION 'organization or actor context mismatch' USING ERRCODE='42501';END IF;
 PERFORM eogp.assert_event_command_permission(p_org,p_event,p_actor,'event.manage');
 IF p_event IS NULL OR coalesce(p_offset,-1) NOT BETWEEN 0 AND 100000 THEN RAISE EXCEPTION 'invalid partner booking page' USING ERRCODE='22023';END IF;
 PERFORM 1 FROM eogp.events WHERE organization_id=p_org AND id=p_event;
 IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE='P0002';END IF;
 SELECT coalesce(jsonb_agg(jsonb_build_object('grantId',choice.id,'bookingOwnerOrganizationId',choice.organization_id,'bookingId',choice.scope_booking_id,
  'providerName',choice.grantor_display_name,'purpose',choice.purpose) ORDER BY choice.created_at DESC,choice.id),'[]'::jsonb) INTO v_rows
 FROM(SELECT grant_row.* FROM eogp.collaboration_grants grant_row WHERE grant_row.grantee_organization_id=p_org AND grant_row.organization_id<>p_org
  AND grant_row.scope_kind='booking' AND grant_row.status='active' AND grant_row.accepted_by_membership_id IS NOT NULL
  AND grant_row.valid_from<=statement_timestamp() AND (grant_row.valid_until IS NULL OR grant_row.valid_until>statement_timestamp())
  AND grant_row.allowed_actions @> ARRAY['booking.event.link']::text[]
  AND NOT EXISTS(SELECT 1 FROM eogp.booking_event_links link WHERE link.organization_id=p_org AND link.event_id=p_event AND link.booking_owner_organization_id=grant_row.organization_id AND link.booking_id=grant_row.scope_booking_id)
  ORDER BY grant_row.created_at DESC,grant_row.id LIMIT 51 OFFSET p_offset) choice;
 INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,action,aggregate_type,aggregate_id)
 VALUES(p_org,p_org,p_actor,'membership','event.partner_booking_options.viewed','event',p_event);
 RETURN jsonb_build_object('options',CASE WHEN jsonb_array_length(v_rows)>50 THEN v_rows-50 ELSE v_rows END,'nextOffset',CASE WHEN jsonb_array_length(v_rows)>50 AND p_offset<=99950 THEN p_offset+50 END);
END;
$function$;
REVOKE ALL ON FUNCTION eogp.list_event_partner_booking_options(uuid,uuid,uuid,integer) FROM PUBLIC,eventor_auth,eventor_worker;
GRANT EXECUTE ON FUNCTION eogp.list_event_partner_booking_options(uuid,uuid,uuid,integer) TO eventor_runtime;
