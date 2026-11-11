-- Safe pre-send cancellation for explicitly queued notification campaigns.

ALTER TABLE eogp.event_notification_campaigns
  ADD COLUMN cancelled_at timestamptz,
  ADD COLUMN cancelled_by_organization_id uuid,
  ADD COLUMN cancelled_by_membership_id uuid,
  ADD CONSTRAINT event_notification_campaign_cancel_actor_fk
    FOREIGN KEY (cancelled_by_organization_id,cancelled_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id,id),
  ADD CONSTRAINT event_notification_campaign_cancel_actor_check
    CHECK ((cancelled_by_membership_id IS NULL)=(cancelled_by_organization_id IS NULL)),
  ADD CONSTRAINT event_notification_campaign_cancel_time_check
    CHECK ((cancelled_at IS NULL)=(cancelled_by_membership_id IS NULL));

ALTER TABLE eogp.event_notification_delivery_attempt_events
  DROP CONSTRAINT event_notification_delivery_attempt_events_status_check,
  ADD CONSTRAINT event_notification_delivery_attempt_events_status_check
    CHECK (status IN ('sending','sent','failed','uncertain','suppressed'));

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

  IF current_user='eventor_owner'
     AND OLD.status='confirmed' AND NEW.status='queued'
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

CREATE FUNCTION eogp.cancel_queued_event_notification_campaign(
  p_organization_id uuid,
  p_campaign_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_campaign eogp.event_notification_campaigns%ROWTYPE;
  v_suppressed integer;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;

  SELECT * INTO v_campaign
    FROM eogp.event_notification_campaigns
   WHERE organization_id=p_organization_id AND id=p_campaign_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'notification campaign not found' USING ERRCODE='P0002';
  END IF;
  PERFORM eogp.assert_event_command_permission(
    p_organization_id,v_campaign.event_id,p_actor_membership_id,'event.notifications.send'
  );

  IF v_campaign.status<>'queued' THEN
    RAISE EXCEPTION 'only a queued campaign that has not started can be cancelled'
      USING ERRCODE='55000';
  END IF;
  IF EXISTS (
    SELECT 1 FROM eogp.event_notification_delivery_attempt_claims claim
    JOIN eogp.event_notification_delivery_attempts attempt
      ON attempt.organization_id=claim.organization_id AND attempt.id=claim.attempt_id
    WHERE attempt.organization_id=p_organization_id AND attempt.campaign_id=p_campaign_id
  ) OR EXISTS (
    SELECT 1 FROM eogp.event_notification_delivery_attempts attempt
    JOIN eogp.event_notification_delivery_attempt_events event
      ON event.organization_id=attempt.organization_id AND event.attempt_id=attempt.id
    WHERE attempt.organization_id=p_organization_id AND attempt.campaign_id=p_campaign_id
      AND event.status IN ('sending','sent','uncertain')
  ) THEN
    RAISE EXCEPTION 'campaign delivery has already started and cannot be cancelled'
      USING ERRCODE='55000';
  END IF;

  UPDATE eogp.event_notification_campaigns
     SET status='cancelled',
         cancelled_at=clock_timestamp(),
         cancelled_by_organization_id=p_organization_id,
         cancelled_by_membership_id=p_actor_membership_id,
         delivery_completed_at=clock_timestamp()
   WHERE organization_id=p_organization_id AND id=p_campaign_id;

  INSERT INTO eogp.event_notification_delivery_attempt_events(
    organization_id,attempt_id,status,provider_name,failure_code
  )
  SELECT attempt.organization_id,attempt.id,'suppressed','smtp','CAMPAIGN_CANCELLED'
    FROM eogp.event_notification_delivery_attempts attempt
   WHERE attempt.organization_id=p_organization_id AND attempt.campaign_id=p_campaign_id
     AND attempt.status='queued'
     AND NOT EXISTS (
       SELECT 1 FROM eogp.event_notification_delivery_attempt_events event
        WHERE event.organization_id=attempt.organization_id AND event.attempt_id=attempt.id
     );
  GET DIAGNOSTICS v_suppressed=ROW_COUNT;

  IF NOT EXISTS (
    SELECT 1
      FROM eogp.event_notification_delivery_attempts attempt
      JOIN eogp.event_notification_campaigns campaign
        ON campaign.organization_id=attempt.organization_id AND campaign.id=attempt.campaign_id
      LEFT JOIN LATERAL (
        SELECT event.status FROM eogp.event_notification_delivery_attempt_events event
         WHERE event.organization_id=attempt.organization_id AND event.attempt_id=attempt.id
         ORDER BY event.created_at DESC,event.id DESC LIMIT 1
      ) latest ON true
     WHERE attempt.organization_id=p_organization_id
       AND campaign.status IN ('queued','sending')
       AND coalesce(latest.status,attempt.status) IN ('queued','sending')
  ) THEN
    DELETE FROM eogp.email_delivery_tenant_queue
     WHERE organization_id=p_organization_id;
  END IF;

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'event.notification_campaign.cancelled','event_notification_campaign',p_campaign_id,
    jsonb_build_object('suppressedAttempts',v_suppressed)
  );

  RETURN jsonb_build_object(
    'campaignId',p_campaign_id,'status','cancelled',
    'suppressedAttempts',v_suppressed,'cancelledAt',clock_timestamp()
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.cancel_queued_event_notification_campaign(uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.cancel_queued_event_notification_campaign(uuid,uuid,uuid)
TO eventor_runtime;
