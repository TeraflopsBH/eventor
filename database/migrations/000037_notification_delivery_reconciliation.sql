-- Audited operator reconciliation and provider-neutral verified delivery events.
-- SMTP acceptance remains distinct from provider-confirmed delivery/bounce.
-- Uncertain submissions are never automatically retried.

INSERT INTO eogp.permissions (code, description, scope_kind, is_sensitive) VALUES
  ('event.notifications.delivery.manage','Reconcile and explicitly retry event notification deliveries','event',true)
ON CONFLICT (code) DO NOTHING;

ALTER TABLE eogp.event_notification_delivery_attempt_events
  DROP CONSTRAINT event_notification_delivery_attempt_events_status_check,
  ADD CONSTRAINT event_notification_delivery_attempt_events_status_check
    CHECK (status IN ('sending','sent','failed','uncertain','delivered','bounced')),
  ADD COLUMN source text NOT NULL DEFAULT 'worker'
    CHECK (source IN ('worker','operator','provider_callback')),
  ADD COLUMN actor_membership_id uuid,
  ADD CONSTRAINT event_notification_delivery_attempt_events_actor_fk
    FOREIGN KEY (organization_id,actor_membership_id)
    REFERENCES eogp.organization_memberships(organization_id,id);

CREATE TABLE eogp.event_notification_provider_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  provider_name text NOT NULL CHECK (provider_name ~ '^[a-z][a-z0-9_-]{0,63}$'),
  provider_event_id text NOT NULL CHECK (length(provider_event_id) BETWEEN 1 AND 500),
  attempt_id uuid NOT NULL,
  outcome text NOT NULL CHECK (outcome IN ('delivered','bounced')),
  payload_sha256 text NOT NULL CHECK (payload_sha256 ~ '^[0-9a-f]{64}$'),
  received_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id,id),
  UNIQUE (organization_id,provider_name,provider_event_id),
  FOREIGN KEY (organization_id,attempt_id)
    REFERENCES eogp.event_notification_delivery_attempts(organization_id,id)
);
ALTER TABLE eogp.event_notification_provider_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.event_notification_provider_events FORCE ROW LEVEL SECURITY;
CREATE POLICY event_notification_provider_events_tenant
  ON eogp.event_notification_provider_events
  USING (organization_id=eogp.current_organization_id())
  WITH CHECK (organization_id=eogp.current_organization_id());
REVOKE ALL ON eogp.event_notification_provider_events FROM PUBLIC,eventor_runtime,eventor_worker;
CREATE TRIGGER event_notification_provider_events_append_only_guard
  BEFORE UPDATE OR DELETE ON eogp.event_notification_provider_events
  FOR EACH ROW EXECUTE FUNCTION eogp.reject_append_only_mutation();

-- Called only by eventor_worker after a provider-specific adapter has verified
-- the callback signature and normalized the provider event. Raw callback bodies
-- and contact destinations are deliberately not persisted.
CREATE FUNCTION eogp.record_verified_notification_provider_event(
  p_organization_id uuid,
  p_provider_name text,
  p_provider_event_id text,
  p_attempt_id uuid,
  p_provider_message_reference text,
  p_outcome text,
  p_payload_sha256 text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_campaign_id uuid;
  v_provider_reference text;
  v_event_provider text;
  v_current_status text;
  v_existing eogp.event_notification_provider_events%ROWTYPE;
  v_inserted_id uuid;
BEGIN
  IF session_user<>'eventor_worker'
     OR eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'provider event ingestion requires worker role and matching tenant context'
      USING ERRCODE='42501';
  END IF;
  IF p_outcome NOT IN ('delivered','bounced')
     OR p_payload_sha256 !~ '^[0-9a-f]{64}$'
     OR p_provider_name !~ '^[a-z][a-z0-9_-]{0,63}$'
     OR length(p_provider_event_id) NOT BETWEEN 1 AND 500 THEN
    RAISE EXCEPTION 'invalid normalized provider event' USING ERRCODE='22023';
  END IF;

  SELECT campaign.id INTO v_campaign_id
    FROM eogp.event_notification_delivery_attempts attempt
    JOIN eogp.event_notification_campaigns campaign
      ON campaign.organization_id=attempt.organization_id AND campaign.id=attempt.campaign_id
   WHERE attempt.organization_id=p_organization_id AND attempt.id=p_attempt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'delivery attempt not found' USING ERRCODE='P0002'; END IF;
  PERFORM 1 FROM eogp.event_notification_campaigns
   WHERE organization_id=p_organization_id AND id=v_campaign_id FOR UPDATE;
  PERFORM 1 FROM eogp.event_notification_delivery_attempts
   WHERE organization_id=p_organization_id AND id=p_attempt_id FOR UPDATE;

  SELECT event.provider_message_reference,event.provider_name,event.status
    INTO v_provider_reference,v_event_provider,v_current_status
    FROM eogp.event_notification_delivery_attempt_events event
   WHERE event.organization_id=p_organization_id AND event.attempt_id=p_attempt_id
   ORDER BY event.created_at DESC,event.id DESC LIMIT 1;
  IF v_event_provider IS DISTINCT FROM p_provider_name
     OR v_provider_reference IS DISTINCT FROM p_provider_message_reference
     OR v_provider_reference IS NULL OR v_provider_reference='' THEN
    RAISE EXCEPTION 'provider event does not match a known provider submission'
      USING ERRCODE='55000';
  END IF;
  IF v_current_status NOT IN ('sent','delivered','bounced') THEN
    RAISE EXCEPTION 'provider event cannot resolve the current delivery state'
      USING ERRCODE='55000';
  END IF;

  INSERT INTO eogp.event_notification_provider_events(
    organization_id,provider_name,provider_event_id,attempt_id,outcome,payload_sha256
  ) VALUES (
    p_organization_id,p_provider_name,p_provider_event_id,p_attempt_id,p_outcome,p_payload_sha256
  )
  ON CONFLICT (organization_id,provider_name,provider_event_id) DO NOTHING
  RETURNING id INTO v_inserted_id;

  IF v_inserted_id IS NULL THEN
    SELECT * INTO v_existing FROM eogp.event_notification_provider_events
     WHERE organization_id=p_organization_id AND provider_name=p_provider_name
       AND provider_event_id=p_provider_event_id;
    IF v_existing.attempt_id IS DISTINCT FROM p_attempt_id
       OR v_existing.outcome IS DISTINCT FROM p_outcome
       OR v_existing.payload_sha256 IS DISTINCT FROM p_payload_sha256 THEN
      RAISE EXCEPTION 'provider event identifier was replayed with different content'
        USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object('accepted',true,'duplicate',true,'attemptId',p_attempt_id,
      'status',v_existing.outcome);
  END IF;

  IF v_current_status IN ('delivered','bounced') AND v_current_status<>p_outcome THEN
    RAISE EXCEPTION 'conflicting terminal provider delivery outcome'
      USING ERRCODE='55000';
  END IF;

  INSERT INTO eogp.event_notification_delivery_attempt_events(
    organization_id,attempt_id,status,provider_name,provider_message_reference,source
  ) VALUES (
    p_organization_id,p_attempt_id,p_outcome,p_provider_name,v_provider_reference,'provider_callback'
  );

  RETURN jsonb_build_object('accepted',true,'duplicate',false,'attemptId',p_attempt_id,'status',p_outcome);
END;
$function$;

CREATE FUNCTION eogp.reconcile_notification_delivery_attempt(
  p_organization_id uuid,
  p_attempt_id uuid,
  p_actor_membership_id uuid,
  p_resolution text,
  p_reason text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_attempt eogp.event_notification_delivery_attempts%ROWTYPE;
  v_campaign eogp.event_notification_campaigns%ROWTYPE;
  v_current_status text;
  v_target_status text;
  v_pending integer;
  v_failed integer;
  v_uncertain integer;
  v_sent integer;
  v_campaign_status text;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  IF p_resolution NOT IN ('confirmed_sent','confirmed_not_sent','confirmed_delivered','confirmed_bounced')
     OR length(btrim(coalesce(p_reason,''))) NOT BETWEEN 3 AND 1000 THEN
    RAISE EXCEPTION 'invalid delivery reconciliation decision' USING ERRCODE='22023';
  END IF;

  SELECT campaign.* INTO v_campaign
    FROM eogp.event_notification_delivery_attempts attempt
    JOIN eogp.event_notification_campaigns campaign
      ON campaign.organization_id=attempt.organization_id AND campaign.id=attempt.campaign_id
   WHERE attempt.organization_id=p_organization_id AND attempt.id=p_attempt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'delivery attempt not found' USING ERRCODE='P0002'; END IF;
  PERFORM 1 FROM eogp.event_notification_campaigns
   WHERE organization_id=p_organization_id AND id=v_campaign.id FOR UPDATE;
  PERFORM eogp.assert_event_command_permission(
    p_organization_id,v_campaign.event_id,p_actor_membership_id,'event.notifications.delivery.manage'
  );
  SELECT * INTO v_attempt FROM eogp.event_notification_delivery_attempts
   WHERE organization_id=p_organization_id AND id=p_attempt_id FOR UPDATE;

  SELECT coalesce(event.status,v_attempt.status) INTO v_current_status
    FROM (SELECT 1) seed
    LEFT JOIN LATERAL (
      SELECT status FROM eogp.event_notification_delivery_attempt_events
       WHERE organization_id=p_organization_id AND attempt_id=p_attempt_id
       ORDER BY created_at DESC,id DESC LIMIT 1
    ) event ON true;
  IF v_current_status NOT IN ('uncertain','failed')
     OR EXISTS (
       SELECT 1 FROM eogp.event_notification_delivery_attempts later
        WHERE later.organization_id=p_organization_id
          AND later.campaign_id=v_attempt.campaign_id
          AND later.recipient_id=v_attempt.recipient_id
          AND later.attempt_number>v_attempt.attempt_number
     ) THEN
    RAISE EXCEPTION 'only the latest uncertain or failed attempt can be reconciled'
      USING ERRCODE='55000';
  END IF;
  v_target_status:=CASE p_resolution
    WHEN 'confirmed_sent' THEN 'sent'
    WHEN 'confirmed_not_sent' THEN 'failed'
    WHEN 'confirmed_delivered' THEN 'delivered'
    WHEN 'confirmed_bounced' THEN 'bounced'
  END;

  INSERT INTO eogp.event_notification_delivery_attempt_events(
    organization_id,attempt_id,status,provider_name,failure_code,source,actor_membership_id
  ) VALUES (
    p_organization_id,p_attempt_id,v_target_status,'operator',
    CASE WHEN v_target_status='failed' THEN 'OPERATOR_CONFIRMED_NOT_SENT' ELSE NULL END,
    'operator',p_actor_membership_id
  );
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'event.notification_delivery.reconciled','event_notification_delivery_attempt',p_attempt_id,
    jsonb_build_object('campaignId',v_campaign.id,'previousStatus',v_current_status,
      'resolution',p_resolution,'resultingStatus',v_target_status,'reason',btrim(p_reason))
  );

  SELECT count(*) FILTER (WHERE status IN ('queued','sending')),
         count(*) FILTER (WHERE status IN ('failed','bounced')),
         count(*) FILTER (WHERE status='uncertain'),
         count(*) FILTER (WHERE status IN ('sent','delivered'))
    INTO v_pending,v_failed,v_uncertain,v_sent
    FROM (
      SELECT DISTINCT ON (attempt.recipient_id) coalesce(last_event.status,attempt.status) AS status
        FROM eogp.event_notification_delivery_attempts attempt
        LEFT JOIN LATERAL (
          SELECT status FROM eogp.event_notification_delivery_attempt_events
           WHERE organization_id=attempt.organization_id AND attempt_id=attempt.id
           ORDER BY created_at DESC,id DESC LIMIT 1
        ) last_event ON true
       WHERE attempt.organization_id=p_organization_id AND attempt.campaign_id=v_campaign.id
       ORDER BY attempt.recipient_id,attempt.attempt_number DESC
    ) latest;
  IF v_pending=0 THEN
    v_campaign_status:=CASE WHEN v_failed=0 AND v_uncertain=0 THEN 'completed'
      WHEN v_sent>0 OR v_uncertain>0 THEN 'partial' ELSE 'failed' END;
    UPDATE eogp.event_notification_campaigns
       SET status=v_campaign_status,delivery_completed_at=coalesce(delivery_completed_at,clock_timestamp())
     WHERE organization_id=p_organization_id AND id=v_campaign.id
       AND status IN ('queued','sending','completed','partial','failed');
  END IF;

  RETURN jsonb_build_object('attemptId',p_attempt_id,'previousStatus',v_current_status,
    'status',v_target_status,'campaignStatus',coalesce(v_campaign_status,v_campaign.status));
END;
$function$;

CREATE FUNCTION eogp.retry_failed_notification_delivery_attempt(
  p_organization_id uuid,
  p_attempt_id uuid,
  p_actor_membership_id uuid,
  p_reason text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_attempt eogp.event_notification_delivery_attempts%ROWTYPE;
  v_campaign eogp.event_notification_campaigns%ROWTYPE;
  v_current_status text;
  v_new_attempt_id uuid;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  IF length(btrim(coalesce(p_reason,''))) NOT BETWEEN 3 AND 1000 THEN
    RAISE EXCEPTION 'a retry reason between 3 and 1000 characters is required' USING ERRCODE='22023';
  END IF;
  SELECT campaign.* INTO v_campaign
    FROM eogp.event_notification_delivery_attempts attempt
    JOIN eogp.event_notification_campaigns campaign
      ON campaign.organization_id=attempt.organization_id AND campaign.id=attempt.campaign_id
   WHERE attempt.organization_id=p_organization_id AND attempt.id=p_attempt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'delivery attempt not found' USING ERRCODE='P0002'; END IF;
  PERFORM 1 FROM eogp.event_notification_campaigns
   WHERE organization_id=p_organization_id AND id=v_campaign.id FOR UPDATE;
  PERFORM eogp.assert_event_command_permission(
    p_organization_id,v_campaign.event_id,p_actor_membership_id,'event.notifications.delivery.manage'
  );
  PERFORM eogp.assert_event_command_permission(
    p_organization_id,v_campaign.event_id,p_actor_membership_id,'event.notifications.send'
  );
  SELECT * INTO v_attempt FROM eogp.event_notification_delivery_attempts
   WHERE organization_id=p_organization_id AND id=p_attempt_id FOR UPDATE;
  SELECT coalesce(event.status,v_attempt.status) INTO v_current_status
    FROM (SELECT 1) seed
    LEFT JOIN LATERAL (
      SELECT status FROM eogp.event_notification_delivery_attempt_events
       WHERE organization_id=p_organization_id AND attempt_id=p_attempt_id
       ORDER BY created_at DESC,id DESC LIMIT 1
    ) event ON true;
  IF v_current_status<>'failed' OR v_campaign.status='cancelled'
     OR v_attempt.attempt_number>=5
     OR EXISTS (
       SELECT 1 FROM eogp.event_notification_delivery_attempts later
        WHERE later.organization_id=p_organization_id
          AND later.campaign_id=v_attempt.campaign_id
          AND later.recipient_id=v_attempt.recipient_id
          AND later.attempt_number>v_attempt.attempt_number
     ) THEN
    RAISE EXCEPTION 'delivery attempt is not eligible for an operator retry'
      USING ERRCODE='55000';
  END IF;

  INSERT INTO eogp.event_notification_delivery_attempts(
    organization_id,campaign_id,recipient_id,attempt_number,status,next_attempt_at
  ) VALUES (
    p_organization_id,v_attempt.campaign_id,v_attempt.recipient_id,
    v_attempt.attempt_number+1,'queued',clock_timestamp()
  ) RETURNING id INTO v_new_attempt_id;

  UPDATE eogp.event_notification_campaigns
     SET status='queued',delivery_completed_at=NULL
   WHERE organization_id=p_organization_id AND id=v_campaign.id
     AND status IN ('completed','partial','failed','queued');
  INSERT INTO eogp.email_delivery_tenant_queue(organization_id,available_at)
  VALUES (p_organization_id,clock_timestamp())
  ON CONFLICT (organization_id) DO UPDATE
    SET available_at=least(eogp.email_delivery_tenant_queue.available_at,EXCLUDED.available_at);
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'event.notification_delivery.retry_authorized','event_notification_delivery_attempt',v_new_attempt_id,
    jsonb_build_object('campaignId',v_campaign.id,'previousAttemptId',p_attempt_id,
      'attemptNumber',v_attempt.attempt_number+1,'reason',btrim(p_reason))
  );
  RETURN jsonb_build_object('attemptId',v_new_attempt_id,'previousAttemptId',p_attempt_id,
    'attemptNumber',v_attempt.attempt_number+1,'status','queued');
END;
$function$;

REVOKE ALL ON FUNCTION eogp.record_verified_notification_provider_event(uuid,text,text,uuid,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.reconcile_notification_delivery_attempt(uuid,uuid,uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.retry_failed_notification_delivery_attempt(uuid,uuid,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.record_verified_notification_provider_event(uuid,text,text,uuid,text,text,text)
  TO eventor_worker;
GRANT EXECUTE ON FUNCTION eogp.reconcile_notification_delivery_attempt(uuid,uuid,uuid,text,text),
  eogp.retry_failed_notification_delivery_attempt(uuid,uuid,uuid,text)
  TO eventor_runtime;
