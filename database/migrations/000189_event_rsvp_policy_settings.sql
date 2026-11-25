-- Staff-configured policy revisions. Issued invitations retain their pinned revision.
CREATE FUNCTION eogp.get_event_rsvp_settings(p_org uuid,p_event uuid,p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_event eogp.events%ROWTYPE;v_policy eogp.rsvp_policy_revisions%ROWTYPE;v_timezone text;
BEGIN
 PERFORM eogp.assert_event_command_permission(p_org,p_event,p_actor,'event.manage');
 SELECT * INTO v_event FROM eogp.events WHERE organization_id=p_org AND id=p_event;
 IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE='P0002';END IF;
 SELECT * INTO v_policy FROM eogp.rsvp_policy_revisions WHERE organization_id=p_org AND event_id=p_event AND state='published' ORDER BY revision_number DESC,id LIMIT 1;
 SELECT timezone_name INTO v_timezone FROM eogp.event_schedule_revisions WHERE organization_id=p_org AND id=eogp.current_event_schedule_revision_id(p_org,p_event);
 RETURN jsonb_build_object('eventId',p_event,'timezoneName',coalesce(v_timezone,v_event.timezone_name),'policy',CASE WHEN v_policy.id IS NULL THEN NULL ELSE jsonb_build_object(
  'revisionId',v_policy.id,'revisionNumber',v_policy.revision_number,'allowedResponses',v_policy.allowed_responses,
  'responseDeadline',v_policy.response_deadline,'responseChangeAllowed',v_policy.response_change_allowed) END);
END;
$function$;

CREATE FUNCTION eogp.publish_event_rsvp_settings(p_org uuid,p_event uuid,p_actor uuid,p_expected uuid,p_responses jsonb,p_deadline timestamptz,p_changes boolean,p_expected_timezone text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_event eogp.events%ROWTYPE;v_current eogp.rsvp_policy_revisions%ROWTYPE;v_policy uuid;v_revision integer;v_id uuid:=gen_random_uuid();v_timezone text;
BEGIN
 PERFORM eogp.assert_event_command_permission(p_org,p_event,p_actor,'event.manage');
 SELECT * INTO v_event FROM eogp.events WHERE organization_id=p_org AND id=p_event FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE='P0002';END IF;
 SELECT timezone_name INTO v_timezone FROM eogp.event_schedule_revisions WHERE organization_id=p_org AND id=eogp.current_event_schedule_revision_id(p_org,p_event);
 v_timezone:=coalesce(v_timezone,v_event.timezone_name);
 IF p_expected_timezone IS DISTINCT FROM v_timezone THEN RAISE EXCEPTION 'event time zone changed; reload before publishing' USING ERRCODE='40001';END IF;
 IF v_event.status IN ('completed','cancelled','archived') THEN RAISE EXCEPTION 'RSVP settings require an open event' USING ERRCODE='55000';END IF;
 IF p_responses IS NULL OR jsonb_typeof(p_responses)<>'array' OR p_changes IS NULL OR (p_deadline IS NOT NULL AND NOT isfinite(p_deadline)) THEN RAISE EXCEPTION 'invalid RSVP settings' USING ERRCODE='22023';END IF;
 IF jsonb_array_length(p_responses) NOT BETWEEN 1 AND 3
  OR EXISTS(SELECT 1 FROM jsonb_array_elements(p_responses) item WHERE item NOT IN ('"accepted"'::jsonb,'"declined"'::jsonb,'"tentative"'::jsonb))
  OR (SELECT count(DISTINCT item) FROM jsonb_array_elements(p_responses) item)<>jsonb_array_length(p_responses) THEN RAISE EXCEPTION 'invalid RSVP answers' USING ERRCODE='22023';END IF;
 SELECT * INTO v_current FROM eogp.rsvp_policy_revisions WHERE organization_id=p_org AND event_id=p_event AND state='published' ORDER BY revision_number DESC,id LIMIT 1;
 IF p_expected IS DISTINCT FROM v_current.id THEN RAISE EXCEPTION 'RSVP settings changed; reload before publishing' USING ERRCODE='40001';END IF;
 v_policy:=v_current.policy_id;
 IF v_policy IS NOT NULL THEN
  PERFORM 1 FROM eogp.rsvp_policies WHERE organization_id=p_org AND event_id=p_event AND id=v_policy AND status='active' FOR SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'current RSVP policy is retired' USING ERRCODE='55000';END IF;
 END IF;
 IF v_policy IS NULL THEN
  v_policy:=gen_random_uuid();
  INSERT INTO eogp.rsvp_policies(id,organization_id,event_id,code,name) VALUES(v_policy,p_org,p_event,'RSVP_'||replace(v_policy::text,'-',''),'Event RSVP');
 END IF;
 -- Higher than every existing event revision, including legacy multiple-policy data.
 SELECT coalesce(max(revision_number),0)+1 INTO v_revision FROM eogp.rsvp_policy_revisions WHERE organization_id=p_org AND event_id=p_event;
 INSERT INTO eogp.rsvp_policy_revisions(id,organization_id,event_id,policy_id,revision_number,allowed_responses,response_deadline,event_timezone,response_change_allowed,late_change_requires_staff,reminder_policy,state,published_at)
 VALUES(v_id,p_org,p_event,v_policy,v_revision,p_responses,p_deadline,v_timezone,p_changes,coalesce(v_current.late_change_requires_staff,true),coalesce(v_current.reminder_policy,'{}'::jsonb),'published',clock_timestamp());
 INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,action,aggregate_type,aggregate_id,safe_metadata)
 VALUES(p_org,p_org,p_actor,'membership','event.rsvp_policy.published','event',p_event,jsonb_build_object('revisionId',v_id,'previousRevisionId',v_current.id,'revisionNumber',v_revision));
 RETURN eogp.get_event_rsvp_settings(p_org,p_event,p_actor);
END;
$function$;
REVOKE ALL ON FUNCTION eogp.get_event_rsvp_settings(uuid,uuid,uuid),eogp.publish_event_rsvp_settings(uuid,uuid,uuid,uuid,jsonb,timestamptz,boolean,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.get_event_rsvp_settings(uuid,uuid,uuid),eogp.publish_event_rsvp_settings(uuid,uuid,uuid,uuid,jsonb,timestamptz,boolean,text) TO eventor_runtime;
-- Policy writes must go through the permissioned, revision-checked command.
REVOKE INSERT,UPDATE,DELETE ON eogp.rsvp_policies,eogp.rsvp_policy_revisions FROM eventor_runtime;
