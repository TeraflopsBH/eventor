-- Stable pre-submission Message-IDs let a signed Resend callback resolve
-- an SMTP attempt even when the DATA response was lost and the attempt became
-- uncertain. The Message-ID is append-only attempt metadata, not a recipient value.

CREATE UNIQUE INDEX event_notification_smtp_submission_message_reference_uidx
  ON eogp.event_notification_delivery_attempt_events(organization_id,provider_message_reference)
  WHERE provider_name='smtp' AND status='sending' AND source='worker'
    AND provider_message_reference IS NOT NULL;

CREATE FUNCTION eogp.prepare_resend_delivery_submission(
  p_organization_id uuid,
  p_attempt_id uuid
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_campaign_id uuid;
  v_host text;
  v_current_status text;
  v_reference text;
BEGIN
  IF session_user<>'eventor_worker'
     OR eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'Resend Message-ID preparation requires worker role and matching tenant context'
      USING ERRCODE='42501';
  END IF;

  SELECT campaign_id INTO v_campaign_id
    FROM eogp.event_notification_delivery_attempts
   WHERE organization_id=p_organization_id AND id=p_attempt_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'delivery attempt not found' USING ERRCODE='P0002'; END IF;

  PERFORM 1 FROM eogp.event_notification_campaigns
   WHERE organization_id=p_organization_id AND id=v_campaign_id FOR UPDATE;

  PERFORM 1
    FROM eogp.event_notification_delivery_attempts attempt
    JOIN eogp.event_notification_delivery_attempt_claims claim
      ON claim.organization_id=attempt.organization_id AND claim.attempt_id=attempt.id
   WHERE attempt.organization_id=p_organization_id AND attempt.id=p_attempt_id
     AND claim.lease_expires_at>clock_timestamp()
   FOR UPDATE OF attempt,claim;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'delivery attempt has no active worker claim'
      USING ERRCODE='55000';
  END IF;

  SELECT revision.settings->>'host' INTO v_host
    FROM eogp.event_notification_campaigns campaign
    JOIN eogp.organization_delivery_config_revisions revision
      ON revision.organization_id=campaign.organization_id
     AND revision.id=campaign.delivery_config_revision_id
   WHERE campaign.organization_id=p_organization_id AND campaign.id=v_campaign_id;
  IF lower(coalesce(v_host,''))<>'smtp.resend.com' THEN
    RAISE EXCEPTION 'stable Resend Message-ID requested for a non-Resend SMTP configuration'
      USING ERRCODE='55000';
  END IF;

  SELECT provider_message_reference INTO v_reference
    FROM eogp.event_notification_delivery_attempt_events
   WHERE organization_id=p_organization_id AND attempt_id=p_attempt_id
     AND provider_name='smtp' AND status='sending' AND source='worker'
     AND provider_message_reference IS NOT NULL
   ORDER BY created_at DESC,id DESC LIMIT 1;
  IF v_reference IS NOT NULL THEN RETURN v_reference; END IF;

  SELECT coalesce(latest.status,attempt.status) INTO v_current_status
    FROM eogp.event_notification_delivery_attempts attempt
    LEFT JOIN LATERAL (
      SELECT status FROM eogp.event_notification_delivery_attempt_events
       WHERE organization_id=p_organization_id AND attempt_id=p_attempt_id
       ORDER BY created_at DESC,id DESC LIMIT 1
    ) latest ON true
   WHERE attempt.organization_id=p_organization_id AND attempt.id=p_attempt_id;
  IF v_current_status<>'sending' THEN
    RAISE EXCEPTION 'Resend Message-ID can only be prepared for a sending attempt'
      USING ERRCODE='55000';
  END IF;

  -- Attempt UUIDs are globally unique. A deterministic RFC Message-ID makes
  -- retries of this preparation command idempotent without storing PII.
  v_reference:='<eventor-' || replace(p_attempt_id::text,'-','')
    || '@delivery.eventor.invalid>';

  INSERT INTO eogp.event_notification_delivery_attempt_events(
    organization_id,attempt_id,status,provider_name,
    provider_message_reference,source
  ) VALUES (
    p_organization_id,p_attempt_id,'sending','smtp',v_reference,'worker'
  );

  RETURN v_reference;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.prepare_resend_delivery_submission(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.prepare_resend_delivery_submission(uuid,uuid) TO eventor_worker;

-- Permit a provider-confirmed terminal outcome to refine a terminal
-- campaign summary, without permitting unrelated edits to a completed campaign.
CREATE OR REPLACE FUNCTION eogp.guard_event_notification_campaign_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path=pg_catalog
AS $function$
BEGIN
  IF current_user='eventor_worker'
     AND OLD.status='previewed' AND NEW.status='previewed'
     AND (to_jsonb(NEW)-'recipient_count')=(to_jsonb(OLD)-'recipient_count') THEN
    RETURN NEW;
  END IF;

  IF current_user='eventor_owner' AND OLD.status='previewed' AND NEW.status='confirmed'
     AND (to_jsonb(NEW)-ARRAY[
       'status','confirmed_by_organization_id','confirmed_by_membership_id',
       'confirmed_by_grant_owner_organization_id','confirmed_by_collaboration_grant_id','confirmed_at'
     ])=(to_jsonb(OLD)-ARRAY[
       'status','confirmed_by_organization_id','confirmed_by_membership_id',
       'confirmed_by_grant_owner_organization_id','confirmed_by_collaboration_grant_id','confirmed_at'
     ])
     AND NEW.confirmed_by_organization_id IS NOT NULL
     AND NEW.confirmed_by_membership_id IS NOT NULL
     AND NEW.confirmed_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF current_user='eventor_owner' AND OLD.status='confirmed' AND NEW.status='queued'
     AND (to_jsonb(NEW)-ARRAY[
       'status','delivery_config_revision_id','queued_by_organization_id',
       'queued_by_membership_id','queued_at'
     ])=(to_jsonb(OLD)-ARRAY[
       'status','delivery_config_revision_id','queued_by_organization_id',
       'queued_by_membership_id','queued_at'
     ])
     AND NEW.delivery_config_revision_id IS NOT NULL
     AND NEW.queued_by_organization_id IS NOT NULL
     AND NEW.queued_by_membership_id IS NOT NULL
     AND NEW.queued_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF current_user='eventor_owner' AND OLD.status IN ('queued','completed','partial','failed')
     AND NEW.status='queued'
     AND (to_jsonb(NEW)-ARRAY[
       'status','queued_by_organization_id','queued_by_membership_id','queued_at',
       'delivery_completed_at'
     ])=(to_jsonb(OLD)-ARRAY[
       'status','queued_by_organization_id','queued_by_membership_id','queued_at',
       'delivery_completed_at'
     ])
     AND NEW.queued_by_organization_id IS NOT NULL
     AND NEW.queued_by_membership_id IS NOT NULL
     AND NEW.queued_at IS NOT NULL
     AND NEW.delivery_completed_at IS NULL THEN
    RETURN NEW;
  END IF;

  IF current_user='eventor_owner' AND OLD.status IN ('completed','partial','failed')
     AND NEW.status IN ('completed','partial','failed')
     AND (to_jsonb(NEW)-ARRAY['status','delivery_completed_at'])
       =(to_jsonb(OLD)-ARRAY['status','delivery_completed_at'])
     AND NEW.delivery_completed_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF current_user='eventor_owner' AND OLD.status='queued' AND NEW.status='cancelled'
     AND (to_jsonb(NEW)-ARRAY[
       'status','cancelled_at','cancelled_by_organization_id',
       'cancelled_by_membership_id','delivery_completed_at'
     ])=(to_jsonb(OLD)-ARRAY[
       'status','cancelled_at','cancelled_by_organization_id',
       'cancelled_by_membership_id','delivery_completed_at'
     ])
     AND NEW.cancelled_at IS NOT NULL
     AND NEW.cancelled_by_organization_id IS NOT NULL
     AND NEW.cancelled_by_membership_id IS NOT NULL
     AND NEW.delivery_completed_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  IF current_user='eventor_owner'
     AND OLD.status IN ('queued','sending')
     AND NEW.status IN ('sending','completed','partial','failed')
     AND (to_jsonb(NEW)-ARRAY['status','delivery_started_at','delivery_completed_at'])
       =(to_jsonb(OLD)-ARRAY['status','delivery_started_at','delivery_completed_at']) THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'notification campaign transition is not authorized'
    USING ERRCODE='55000';
END;
$function$;


CREATE OR REPLACE FUNCTION eogp.record_verified_resend_delivery_webhook(
  p_organization_id uuid,
  p_endpoint_id uuid,
  p_provider_event_id text,
  p_provider_message_reference text,
  p_outcome text,
  p_payload_sha256 text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_endpoint_enabled boolean;
  v_attempt_id uuid;
  v_campaign_id uuid;
  v_campaign eogp.event_notification_campaigns%ROWTYPE;
  v_current_status text;
  v_existing eogp.event_notification_provider_events%ROWTYPE;
  v_inserted_id uuid;
  v_pending integer;
  v_sent integer;
  v_failed integer;
  v_uncertain integer;
  v_campaign_status text;
BEGIN
  IF session_user<>'eventor_runtime'
     OR eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'Resend webhook ingestion requires the API runtime role and matching tenant context'
      USING ERRCODE='42501';
  END IF;
  IF p_outcome NOT IN ('delivered','bounced')
     OR p_payload_sha256 !~ '^[0-9a-f]{64}$'
     OR length(coalesce(p_provider_event_id,'')) NOT BETWEEN 1 AND 500
     OR length(coalesce(p_provider_message_reference,'')) NOT BETWEEN 3 AND 500 THEN
    RAISE EXCEPTION 'invalid normalized Resend delivery event' USING ERRCODE='22023';
  END IF;

  SELECT enabled INTO v_endpoint_enabled
    FROM eogp.organization_resend_webhook_endpoints
   WHERE organization_id=p_organization_id AND id=p_endpoint_id;
  IF v_endpoint_enabled IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'Resend webhook endpoint is not active for this organization'
      USING ERRCODE='42501';
  END IF;

  -- A Message-ID is created and journaled before SMTP submission. It remains
  -- available even if the SMTP DATA result is lost and the attempt becomes
  -- uncertain. Successful attempts also retain it on the later sent event.
  SELECT DISTINCT attempt.id,campaign.id
    INTO v_attempt_id,v_campaign_id
    FROM eogp.event_notification_delivery_attempts attempt
    JOIN eogp.event_notification_campaigns campaign
      ON campaign.organization_id=attempt.organization_id AND campaign.id=attempt.campaign_id
    JOIN eogp.organization_delivery_config_revisions revision
      ON revision.organization_id=campaign.organization_id
     AND revision.id=campaign.delivery_config_revision_id
    JOIN eogp.event_notification_delivery_attempt_events reference_event
      ON reference_event.organization_id=attempt.organization_id
     AND reference_event.attempt_id=attempt.id
   WHERE attempt.organization_id=p_organization_id
     AND reference_event.provider_name='smtp'
     AND reference_event.provider_message_reference=p_provider_message_reference
     AND (
       (reference_event.status='sent')
       OR (reference_event.status='sending' AND reference_event.source='worker')
     )
     AND revision.settings->>'host'='smtp.resend.com'
   LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Resend Message-ID does not match a known SMTP attempt'
      USING ERRCODE='P0002';
  END IF;

  SELECT * INTO v_campaign
    FROM eogp.event_notification_campaigns
   WHERE organization_id=p_organization_id AND id=v_campaign_id
   FOR UPDATE;
  SELECT coalesce(latest.status,attempt.status) INTO v_current_status
    FROM eogp.event_notification_delivery_attempts attempt
    LEFT JOIN LATERAL (
      SELECT status FROM eogp.event_notification_delivery_attempt_events
       WHERE organization_id=p_organization_id AND attempt_id=v_attempt_id
       ORDER BY created_at DESC,id DESC LIMIT 1
    ) latest ON true
   WHERE attempt.organization_id=p_organization_id AND attempt.id=v_attempt_id
   FOR UPDATE OF attempt;

  -- Resend can notify very quickly. If the worker has not yet committed its
  -- SMTP result, ask the provider to retry the webhook rather than losing it.
  IF v_current_status='sending' THEN
    RAISE EXCEPTION 'SMTP submission is still in progress; retry the webhook'
      USING ERRCODE='40001';
  END IF;
  IF v_current_status NOT IN ('sent','uncertain','delivered','bounced') THEN
    RAISE EXCEPTION 'Resend event cannot override the current operator or delivery decision'
      USING ERRCODE='55000';
  END IF;
  IF v_current_status IN ('delivered','bounced') AND v_current_status<>p_outcome THEN
    RAISE EXCEPTION 'conflicting terminal Resend delivery outcome'
      USING ERRCODE='55000';
  END IF;

  INSERT INTO eogp.event_notification_provider_events(
    organization_id,provider_name,provider_event_id,attempt_id,outcome,payload_sha256
  ) VALUES (
    p_organization_id,'resend',p_provider_event_id,v_attempt_id,p_outcome,p_payload_sha256
  )
  ON CONFLICT (organization_id,provider_name,provider_event_id) DO NOTHING
  RETURNING id INTO v_inserted_id;

  IF v_inserted_id IS NULL THEN
    SELECT * INTO v_existing
      FROM eogp.event_notification_provider_events
     WHERE organization_id=p_organization_id
       AND provider_name='resend'
       AND provider_event_id=p_provider_event_id;
    IF v_existing.attempt_id IS DISTINCT FROM v_attempt_id
       OR v_existing.outcome IS DISTINCT FROM p_outcome
       OR v_existing.payload_sha256 IS DISTINCT FROM p_payload_sha256 THEN
      RAISE EXCEPTION 'Resend event identifier was replayed with different content'
        USING ERRCODE='23505';
    END IF;
    RETURN jsonb_build_object(
      'accepted',true,'duplicate',true,'attemptId',v_attempt_id,'status',v_existing.outcome
    );
  END IF;

  INSERT INTO eogp.event_notification_delivery_attempt_events(
    organization_id,attempt_id,status,provider_name,
    provider_message_reference,failure_code,source
  ) VALUES (
    p_organization_id,v_attempt_id,p_outcome,'resend',
    p_provider_message_reference,
    CASE WHEN p_outcome='bounced' THEN 'RESEND_BOUNCED' ELSE NULL END,
    'provider_callback'
  );

  -- A provider callback may be the first definitive outcome for an uncertain
  -- SMTP submission. Recompute the campaign state so progress is not left
  -- permanently partial after every recipient has a definitive outcome.
  SELECT count(*) FILTER (WHERE status IN ('queued','sending')),
         count(*) FILTER (WHERE status IN ('sent','delivered')),
         count(*) FILTER (WHERE status IN ('failed','bounced')),
         count(*) FILTER (WHERE status='uncertain')
    INTO v_pending,v_sent,v_failed,v_uncertain
    FROM (
      SELECT DISTINCT ON (attempt.recipient_id)
             coalesce(last_event.status,attempt.status) AS status
        FROM eogp.event_notification_delivery_attempts attempt
        LEFT JOIN LATERAL (
          SELECT event.status
            FROM eogp.event_notification_delivery_attempt_events event
           WHERE event.organization_id=attempt.organization_id
             AND event.attempt_id=attempt.id
           ORDER BY event.created_at DESC,event.id DESC LIMIT 1
        ) last_event ON true
       WHERE attempt.organization_id=p_organization_id
         AND attempt.campaign_id=v_campaign_id
       ORDER BY attempt.recipient_id,attempt.attempt_number DESC
    ) latest;

  IF v_pending=0 AND v_campaign.status IN
       ('queued','sending','completed','partial','failed') THEN
    v_campaign_status:=CASE
      WHEN v_failed=0 AND v_uncertain=0 THEN 'completed'
      WHEN v_sent>0 OR v_uncertain>0 THEN 'partial'
      ELSE 'failed'
    END;
    UPDATE eogp.event_notification_campaigns
       SET status=v_campaign_status,
           delivery_completed_at=coalesce(delivery_completed_at,clock_timestamp())
     WHERE organization_id=p_organization_id AND id=v_campaign_id;
  ELSE
    v_campaign_status:=v_campaign.status;
  END IF;

  RETURN jsonb_build_object(
    'accepted',true,'duplicate',false,'attemptId',v_attempt_id,
    'status',p_outcome,'campaignStatus',coalesce(v_campaign_status,v_campaign.status)
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.record_verified_resend_delivery_webhook(uuid,uuid,text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.record_verified_resend_delivery_webhook(uuid,uuid,text,text,text,text)
  TO eventor_runtime;
