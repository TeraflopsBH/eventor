-- Explicit same-organization publication into the existing event-owned receipt aggregate.
REVOKE ALL ON eogp.event_disruption_resolutions FROM PUBLIC,eventor_runtime,eventor_auth,eventor_worker;
ALTER TABLE eogp.event_disruption_resolutions
 DROP CONSTRAINT event_disruption_resolutions_collaboration_grant_id_check,
 ADD CONSTRAINT event_disruption_receipt_source_scope CHECK (
  (source_provider_organization_id=organization_id AND collaboration_grant_id IS NULL AND grant_owner_organization_id IS NULL)
  OR (source_provider_organization_id<>organization_id AND collaboration_grant_id IS NOT NULL AND grant_owner_organization_id IS NOT DISTINCT FROM source_provider_organization_id)),
 ADD CONSTRAINT event_disruption_receipt_source_key UNIQUE(organization_id,event_id,source_provider_organization_id,source_booking_notice_id);
-- Duplicate legacy receipts deliberately stop migration for explicit reconciliation; never discard history.
CREATE FUNCTION eogp.guard_event_disruption_receipt_provenance() RETURNS trigger
LANGUAGE plpgsql SET search_path=pg_catalog,eogp AS $function$
BEGIN
 IF TG_OP='DELETE' THEN RAISE EXCEPTION 'event disruption provenance is retained' USING ERRCODE='55000';END IF;
 IF ROW(NEW.id,NEW.organization_id,NEW.event_id,NEW.source_provider_organization_id,NEW.source_booking_notice_id,NEW.source_notice_snapshot,NEW.grant_owner_organization_id,NEW.collaboration_grant_id,NEW.created_at)
  IS DISTINCT FROM ROW(OLD.id,OLD.organization_id,OLD.event_id,OLD.source_provider_organization_id,OLD.source_booking_notice_id,OLD.source_notice_snapshot,OLD.grant_owner_organization_id,OLD.collaboration_grant_id,OLD.created_at) THEN
  RAISE EXCEPTION 'event disruption provenance is immutable' USING ERRCODE='55000';END IF;
 IF OLD.acknowledged_at IS NOT NULL AND ROW(NEW.acknowledged_at,NEW.acknowledged_by_membership_id) IS DISTINCT FROM ROW(OLD.acknowledged_at,OLD.acknowledged_by_membership_id) THEN
  RAISE EXCEPTION 'first acknowledgement is immutable' USING ERRCODE='55000';END IF;
 RETURN NEW;
END;
$function$;
CREATE TRIGGER event_disruption_receipt_provenance_guard BEFORE UPDATE OR DELETE ON eogp.event_disruption_resolutions
 FOR EACH ROW EXECUTE FUNCTION eogp.guard_event_disruption_receipt_provenance();

CREATE FUNCTION eogp.event_disruption_receipt_projection(p_receipt eogp.event_disruption_resolutions)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,eogp AS $function$
 SELECT jsonb_build_object('noticeId',p_receipt.id,'eventId',p_receipt.event_id,'sourceProviderOrganizationId',p_receipt.source_provider_organization_id,
  'sourceBookingNoticeId',p_receipt.source_booking_notice_id,'status',p_receipt.status,'resolutionKind',p_receipt.resolution_kind,
  'createdAt',p_receipt.created_at,'acknowledgedAt',p_receipt.acknowledged_at,
  'sourceNotice',CASE WHEN p_receipt.source_notice_snapshot->'snapshotVersion'='1'::jsonb THEN jsonb_build_object(
   'noticeCode',p_receipt.source_notice_snapshot->'noticeCode','reasonCategory',p_receipt.source_notice_snapshot->'reasonCategory',
   'publicSummary',p_receipt.source_notice_snapshot->'publicSummary','affectedFrom',p_receipt.source_notice_snapshot->'affectedFrom',
   'affectedUntil',p_receipt.source_notice_snapshot->'affectedUntil','issuedAt',p_receipt.source_notice_snapshot->'issuedAt') END);
$function$;

CREATE FUNCTION eogp.assert_local_disruption_publication(p_org uuid,p_event uuid,p_actor uuid,p_booking uuid,p_notice uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
BEGIN
 PERFORM eogp.assert_event_booking_link_permission(p_org,p_event,p_actor,p_org,p_booking,NULL);
 PERFORM 1 FROM eogp.booking_event_links WHERE organization_id=p_org AND event_id=p_event
  AND booking_owner_organization_id=p_org AND booking_id=p_booking AND status='active' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'active local booking/event association required' USING ERRCODE='55000';END IF;
 PERFORM 1 FROM eogp.booking_disruption_notices WHERE organization_id=p_org AND booking_id=p_booking AND id=p_notice;
 IF NOT FOUND THEN RAISE EXCEPTION 'booking notice not found' USING ERRCODE='P0002';END IF;
END;
$function$;
CREATE FUNCTION eogp.publish_local_event_disruption(p_org uuid,p_event uuid,p_actor uuid,p_booking uuid,p_notice uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_receipt eogp.event_disruption_resolutions%ROWTYPE;v_source eogp.booking_disruption_notices%ROWTYPE;
BEGIN
 -- Event lock in the permission helper serializes duplicate publications before audit insertion.
 PERFORM eogp.assert_local_disruption_publication(p_org,p_event,p_actor,p_booking,p_notice);
 SELECT * INTO v_receipt FROM eogp.event_disruption_resolutions WHERE organization_id=p_org AND event_id=p_event
  AND source_provider_organization_id=p_org AND source_booking_notice_id=p_notice;
 IF NOT FOUND THEN
  SELECT * INTO STRICT v_source FROM eogp.booking_disruption_notices WHERE organization_id=p_org AND booking_id=p_booking AND id=p_notice;
  INSERT INTO eogp.event_disruption_resolutions(organization_id,event_id,source_provider_organization_id,source_booking_notice_id,source_notice_snapshot)
  VALUES(p_org,p_event,p_org,p_notice,jsonb_build_object('snapshotVersion',1,'noticeCode',v_source.notice_code,'reasonCategory',v_source.reason_category,
   'publicSummary',v_source.public_summary,'affectedFrom',v_source.affected_from,'affectedUntil',v_source.affected_until,'issuedAt',v_source.issued_at)) RETURNING * INTO v_receipt;
  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,action,aggregate_type,aggregate_id,safe_metadata)
  VALUES(p_org,p_org,p_actor,'membership','event.disruption_notice.published','event_disruption_notice',v_receipt.id,jsonb_build_object('eventId',p_event,'sourceBookingNoticeId',p_notice));
 END IF;
 RETURN eogp.event_disruption_receipt_projection(v_receipt);
END;
$function$;
CREATE FUNCTION eogp.list_event_disruption_notices(p_org uuid,p_event uuid,p_actor uuid,p_offset integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_rows jsonb;
BEGIN
 IF eogp.current_organization_id() IS DISTINCT FROM p_org OR nullif(current_setting('app.actor_membership_id',true),'')::uuid IS DISTINCT FROM p_actor THEN RAISE EXCEPTION 'organization or actor context mismatch' USING ERRCODE='42501';END IF;
 PERFORM eogp.assert_event_command_permission(p_org,p_event,p_actor,'event.manage');
 IF p_event IS NULL OR coalesce(p_offset,-1) NOT BETWEEN 0 AND 100000 THEN RAISE EXCEPTION 'invalid event notice page' USING ERRCODE='22023';END IF;
 PERFORM 1 FROM eogp.events WHERE organization_id=p_org AND id=p_event;
 IF NOT FOUND THEN RAISE EXCEPTION 'event not found' USING ERRCODE='P0002';END IF;
 SELECT coalesce(jsonb_agg(eogp.event_disruption_receipt_projection(receipt) ORDER BY receipt.created_at DESC,receipt.id),'[]'::jsonb) INTO v_rows
 FROM(SELECT * FROM eogp.event_disruption_resolutions WHERE organization_id=p_org AND event_id=p_event ORDER BY created_at DESC,id LIMIT 51 OFFSET p_offset) receipt;
 INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,action,aggregate_type,aggregate_id)
 VALUES(p_org,p_org,p_actor,'membership','event.disruption_notices.viewed','event',p_event);
 RETURN jsonb_build_object('notices',CASE WHEN jsonb_array_length(v_rows)>50 THEN v_rows-50 ELSE v_rows END,'nextOffset',CASE WHEN jsonb_array_length(v_rows)>50 AND p_offset<=99950 THEN p_offset+50 END);
END;
$function$;
CREATE FUNCTION eogp.assert_event_disruption_receipt_permission(p_org uuid,p_notice uuid,p_actor uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_event uuid;
BEGIN
 IF eogp.current_organization_id() IS DISTINCT FROM p_org OR nullif(current_setting('app.actor_membership_id',true),'')::uuid IS DISTINCT FROM p_actor THEN RAISE EXCEPTION 'organization or actor context mismatch' USING ERRCODE='42501';END IF;
 SELECT event_id INTO v_event FROM eogp.event_disruption_resolutions WHERE organization_id=p_org AND id=p_notice;
 IF NOT FOUND THEN RAISE EXCEPTION 'event notice not found' USING ERRCODE='P0002';END IF;
 PERFORM eogp.assert_event_command_permission(p_org,v_event,p_actor,'event.manage');
 RETURN v_event;
END;
$function$;
CREATE FUNCTION eogp.acknowledge_event_disruption(p_org uuid,p_notice uuid,p_actor uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_event uuid;v_receipt eogp.event_disruption_resolutions%ROWTYPE;
BEGIN
 v_event:=eogp.assert_event_disruption_receipt_permission(p_org,p_notice,p_actor);
 SELECT * INTO STRICT v_receipt FROM eogp.event_disruption_resolutions WHERE organization_id=p_org AND id=p_notice FOR UPDATE;
 IF v_receipt.status='received' THEN
  UPDATE eogp.event_disruption_resolutions SET status='acknowledged',acknowledged_by_membership_id=p_actor,acknowledged_at=clock_timestamp()
   WHERE organization_id=p_org AND id=p_notice RETURNING * INTO v_receipt;
  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,action,aggregate_type,aggregate_id,safe_metadata)
  VALUES(p_org,p_org,p_actor,'membership','event.disruption_notice.acknowledged','event_disruption_notice',p_notice,jsonb_build_object('eventId',v_event));
 END IF;
 -- Later resolution states and the first acknowledgement are never rewound by retries.
 RETURN eogp.event_disruption_receipt_projection(v_receipt);
END;
$function$;
REVOKE ALL ON FUNCTION eogp.guard_event_disruption_receipt_provenance(),eogp.event_disruption_receipt_projection(eogp.event_disruption_resolutions),
 eogp.assert_local_disruption_publication(uuid,uuid,uuid,uuid,uuid),eogp.publish_local_event_disruption(uuid,uuid,uuid,uuid,uuid),
 eogp.list_event_disruption_notices(uuid,uuid,uuid,integer),eogp.assert_event_disruption_receipt_permission(uuid,uuid,uuid),eogp.acknowledge_event_disruption(uuid,uuid,uuid)
 FROM PUBLIC,eventor_auth,eventor_worker;
REVOKE ALL ON FUNCTION eogp.guard_event_disruption_receipt_provenance(),eogp.event_disruption_receipt_projection(eogp.event_disruption_resolutions) FROM eventor_runtime;
GRANT EXECUTE ON FUNCTION eogp.assert_local_disruption_publication(uuid,uuid,uuid,uuid,uuid),eogp.publish_local_event_disruption(uuid,uuid,uuid,uuid,uuid),
 eogp.list_event_disruption_notices(uuid,uuid,uuid,integer),eogp.assert_event_disruption_receipt_permission(uuid,uuid,uuid),eogp.acknowledge_event_disruption(uuid,uuid,uuid) TO eventor_runtime;
