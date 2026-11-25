-- A narrow proposal command: one managed booking and the existing link capability only.
CREATE FUNCTION eogp.assert_booking_collaboration_proposal_permission(p_org uuid,p_booking uuid,p_actor uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
BEGIN
 PERFORM eogp.assert_collaboration_manage_permission(p_org,p_actor);
 PERFORM eogp.assert_booking_cancellation_permission(p_org,p_booking,p_actor,'booking.manage');
 IF p_booking IS NULL THEN RAISE EXCEPTION 'booking required' USING ERRCODE='22023';END IF;
 PERFORM 1 FROM eogp.booking_records WHERE organization_id=p_org AND id=p_booking FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'booking not found' USING ERRCODE='P0002';END IF;
END;
$function$;
CREATE FUNCTION eogp.propose_booking_collaboration(p_org uuid,p_booking uuid,p_actor uuid,p_grant uuid,p_recipient uuid,p_purpose text,p_from timestamptz,p_until timestamptz)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_id uuid;v_grant eogp.collaboration_grants%ROWTYPE;
BEGIN
 PERFORM eogp.assert_booking_collaboration_proposal_permission(p_org,p_booking,p_actor);
 IF p_grant IS NULL OR p_recipient IS NULL OR p_recipient=p_org OR coalesce(length(btrim(p_purpose)),0) NOT BETWEEN 1 AND 1000
  OR p_purpose ~ '[[:cntrl:]]' OR p_from IS NULL OR NOT isfinite(p_from) OR (p_until IS NOT NULL AND (NOT isfinite(p_until) OR p_until<=p_from)) THEN
  RAISE EXCEPTION 'valid recipient, purpose and explicit validity required' USING ERRCODE='22023';END IF;
 v_id:=eogp.propose_collaboration_grant(p_grant,p_recipient,'booking',NULL,NULL,p_booking,btrim(p_purpose),'{}',ARRAY['booking.event.link'],p_from,p_until,p_actor);
 SELECT * INTO STRICT v_grant FROM eogp.collaboration_grants WHERE organization_id=p_org AND id=v_id;
 RETURN eogp.collaboration_grant_metadata(v_grant);
END;
$function$;
REVOKE ALL ON FUNCTION eogp.assert_booking_collaboration_proposal_permission(uuid,uuid,uuid),eogp.propose_booking_collaboration(uuid,uuid,uuid,uuid,uuid,text,timestamptz,timestamptz) FROM PUBLIC,eventor_auth,eventor_worker;
GRANT EXECUTE ON FUNCTION eogp.assert_booking_collaboration_proposal_permission(uuid,uuid,uuid),eogp.propose_booking_collaboration(uuid,uuid,uuid,uuid,uuid,text,timestamptz,timestamptz) TO eventor_runtime;
