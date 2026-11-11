-- Permission-gated campaign listing and delivery operations projections.
-- All projections omit recipient destination/contact values and ciphertext.

CREATE INDEX event_notification_campaign_org_created_idx
  ON eogp.event_notification_campaigns(organization_id,created_at DESC,id DESC);

CREATE INDEX event_notification_attempt_campaign_recipient_idx
  ON eogp.event_notification_delivery_attempts(organization_id,campaign_id,recipient_id,attempt_number DESC);

CREATE OR REPLACE FUNCTION eogp.list_event_notification_campaigns(
  p_organization_id uuid,
  p_actor_membership_id uuid,
  p_status text DEFAULT NULL,
  p_limit integer DEFAULT 25,
  p_offset integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_campaign record;
  v_allowed boolean;
  v_total integer := 0;
  v_returned integer := 0;
  v_items jsonb := '[]'::jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  IF p_limit IS NULL OR p_limit<1 OR p_limit>100
     OR p_offset IS NULL OR p_offset<0 OR p_offset>10000 THEN
    RAISE EXCEPTION 'invalid campaign page bounds' USING ERRCODE='22023';
  END IF;
  IF p_status IS NOT NULL AND p_status NOT IN
    ('draft','previewed','confirmed','queued','sending','completed','partial','failed','cancelled') THEN
    RAISE EXCEPTION 'unsupported campaign status filter' USING ERRCODE='22023';
  END IF;

  FOR v_campaign IN
    SELECT campaign.id,campaign.event_id,campaign.purpose,campaign.audience_kind,
           campaign.status,campaign.recipient_count,campaign.created_at,campaign.confirmed_at,
           campaign.queued_at,campaign.delivery_started_at,campaign.delivery_completed_at,
           (SELECT count(*) FROM eogp.event_notification_recipients recipient
             WHERE recipient.organization_id=campaign.organization_id
               AND recipient.campaign_id=campaign.id) AS actual_recipient_count
      FROM eogp.event_notification_campaigns campaign
     WHERE campaign.organization_id=p_organization_id
       AND (p_status IS NULL OR campaign.status=p_status)
     ORDER BY campaign.created_at DESC,campaign.id DESC
  LOOP
    v_allowed:=true;
    BEGIN
      PERFORM eogp.assert_event_command_permission(
        p_organization_id,v_campaign.event_id,p_actor_membership_id,'event.notifications.preview'
      );
    EXCEPTION WHEN insufficient_privilege THEN
      v_allowed:=false;
    END;
    IF NOT v_allowed THEN CONTINUE; END IF;

    v_total:=v_total+1;
    IF v_total<=p_offset OR v_returned>=p_limit THEN CONTINUE; END IF;

    v_items:=v_items||jsonb_build_array(jsonb_build_object(
      'campaignId',v_campaign.id,
      'eventId',v_campaign.event_id,
      'purpose',v_campaign.purpose,
      'audienceKind',v_campaign.audience_kind,
      'status',v_campaign.status,
      'recipientCount',v_campaign.recipient_count,
      'actualRecipientCount',v_campaign.actual_recipient_count,
      'createdAt',v_campaign.created_at,
      'confirmedAt',v_campaign.confirmed_at,
      'queuedAt',v_campaign.queued_at,
      'deliveryStartedAt',v_campaign.delivery_started_at,
      'deliveryCompletedAt',v_campaign.delivery_completed_at
    ));
    v_returned:=v_returned+1;
  END LOOP;

  RETURN jsonb_build_object(
    'items',v_items,
    'page',jsonb_build_object('limit',p_limit,'offset',p_offset,'total',v_total)
  );
END;
$function$;

CREATE FUNCTION eogp.get_event_notification_campaign_progress(
  p_organization_id uuid,
  p_campaign_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_event_id uuid;
  v_result jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;

  SELECT event_id INTO v_event_id
    FROM eogp.event_notification_campaigns
   WHERE organization_id=p_organization_id AND id=p_campaign_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'notification campaign not found' USING ERRCODE='P0002';
  END IF;
  PERFORM eogp.assert_event_command_permission(
    p_organization_id,v_event_id,p_actor_membership_id,'event.notifications.preview'
  );

  WITH latest_per_recipient AS (
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
     WHERE attempt.organization_id=p_organization_id AND attempt.campaign_id=p_campaign_id
     ORDER BY attempt.recipient_id,attempt.attempt_number DESC
  ), status_counts AS (
    SELECT status,count(*)::integer AS total
      FROM latest_per_recipient GROUP BY status
  ), attempt_totals AS (
    SELECT count(*)::integer AS total
      FROM eogp.event_notification_delivery_attempts
     WHERE organization_id=p_organization_id AND campaign_id=p_campaign_id
  )
  SELECT jsonb_build_object(
    'campaignId',campaign.id,
    'eventId',campaign.event_id,
    'status',campaign.status,
    'purpose',campaign.purpose,
    'recipientCount',(SELECT count(*)::integer FROM eogp.event_notification_recipients
      WHERE organization_id=p_organization_id AND campaign_id=p_campaign_id),
    'attemptCount',(SELECT total FROM attempt_totals),
    'deliveryCounts',jsonb_build_object(
      'queued',coalesce((SELECT total FROM status_counts WHERE status='queued'),0),
      'sending',coalesce((SELECT total FROM status_counts WHERE status='sending'),0),
      'sent',(SELECT coalesce(sum(total),0) FROM status_counts WHERE status IN ('sent','delivered')),
      'failed',(SELECT coalesce(sum(total),0) FROM status_counts WHERE status IN ('failed','bounced')),
      'uncertain',coalesce((SELECT total FROM status_counts WHERE status='uncertain'),0),
      'suppressed',coalesce((SELECT total FROM status_counts WHERE status='suppressed'),0)
    ),
    'createdAt',campaign.created_at,
    'confirmedAt',campaign.confirmed_at,
    'queuedAt',campaign.queued_at,
    'deliveryStartedAt',campaign.delivery_started_at,
    'deliveryCompletedAt',campaign.delivery_completed_at
  ) INTO v_result
    FROM eogp.event_notification_campaigns campaign
   WHERE campaign.organization_id=p_organization_id AND campaign.id=p_campaign_id;

  RETURN v_result;
END;
$function$;

CREATE FUNCTION eogp.list_event_notification_campaign_deliveries(
  p_organization_id uuid,
  p_campaign_id uuid,
  p_actor_membership_id uuid,
  p_status text DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_event_id uuid;
  v_items jsonb;
  v_total integer;
  v_counts jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  IF p_limit IS NULL OR p_limit<1 OR p_limit>100
     OR p_offset IS NULL OR p_offset<0 OR p_offset>10000 THEN
    RAISE EXCEPTION 'invalid delivery page bounds' USING ERRCODE='22023';
  END IF;
  IF p_status IS NOT NULL AND p_status NOT IN
    ('queued','sending','sent','delivered','failed','bounced','uncertain','suppressed') THEN
    RAISE EXCEPTION 'unsupported delivery status filter' USING ERRCODE='22023';
  END IF;

  SELECT event_id INTO v_event_id
    FROM eogp.event_notification_campaigns
   WHERE organization_id=p_organization_id AND id=p_campaign_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'notification campaign not found' USING ERRCODE='P0002';
  END IF;
  PERFORM eogp.assert_event_command_permission(
    p_organization_id,v_event_id,p_actor_membership_id,'event.notifications.preview'
  );

  WITH attempt_projection AS (
    SELECT attempt.id AS attempt_id,attempt.recipient_id,recipient.channel,
           attempt.attempt_number,attempt.next_attempt_at,
           coalesce(last_event.status,attempt.status) AS status,
           last_event.failure_code,last_event.provider_name,
           first_sending.created_at AS sending_at,
           CASE WHEN last_event.status IN ('sent','failed','uncertain','suppressed','delivered','bounced')
                THEN last_event.created_at ELSE NULL END AS completed_at,
           EXISTS (
             SELECT 1 FROM eogp.event_notification_delivery_attempts later
              WHERE later.organization_id=attempt.organization_id
                AND later.campaign_id=attempt.campaign_id
                AND later.recipient_id=attempt.recipient_id
                AND later.attempt_number>attempt.attempt_number
           ) AS retry_scheduled
      FROM eogp.event_notification_delivery_attempts attempt
      JOIN eogp.event_notification_recipients recipient
        ON recipient.organization_id=attempt.organization_id
       AND recipient.campaign_id=attempt.campaign_id
       AND recipient.id=attempt.recipient_id
      LEFT JOIN LATERAL (
        SELECT event.status,event.failure_code,event.provider_name,event.created_at
          FROM eogp.event_notification_delivery_attempt_events event
         WHERE event.organization_id=attempt.organization_id AND event.attempt_id=attempt.id
         ORDER BY event.created_at DESC,event.id DESC LIMIT 1
      ) last_event ON true
      LEFT JOIN LATERAL (
        SELECT min(event.created_at) AS created_at
          FROM eogp.event_notification_delivery_attempt_events event
         WHERE event.organization_id=attempt.organization_id AND event.attempt_id=attempt.id
           AND event.status='sending'
      ) first_sending ON true
     WHERE attempt.organization_id=p_organization_id AND attempt.campaign_id=p_campaign_id
  ), filtered AS (
    SELECT * FROM attempt_projection WHERE p_status IS NULL OR status=p_status
  ), page AS (
    SELECT * FROM filtered
     ORDER BY next_attempt_at DESC,attempt_id DESC
     OFFSET p_offset LIMIT p_limit
  )
  SELECT
    (SELECT count(*)::integer FROM filtered),
    coalesce((SELECT jsonb_agg(jsonb_build_object(
      'attemptId',attempt_id,
      'recipientReference',recipient_id,
      'channel',channel,
      'attemptNumber',attempt_number,
      'status',status,
      'failureCode',failure_code,
      'provider',provider_name,
      'queuedForAt',next_attempt_at,
      'sendingAt',sending_at,
      'completedAt',completed_at,
      'retryScheduled',retry_scheduled
    ) ORDER BY next_attempt_at DESC,attempt_id DESC) FROM page),'[]'::jsonb),
    (SELECT coalesce(jsonb_object_agg(status,total),'{}'::jsonb)
       FROM (SELECT status,count(*)::integer AS total FROM attempt_projection GROUP BY status) counts)
  INTO v_total,v_items,v_counts;

  RETURN jsonb_build_object(
    'items',v_items,
    'page',jsonb_build_object('limit',p_limit,'offset',p_offset,'total',v_total),
    'counts',v_counts
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.list_event_notification_campaigns(uuid,uuid,text,integer,integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.get_event_notification_campaign_progress(uuid,uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.list_event_notification_campaign_deliveries(uuid,uuid,uuid,text,integer,integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.list_event_notification_campaigns(uuid,uuid,text,integer,integer),
  eogp.get_event_notification_campaign_progress(uuid,uuid,uuid),
  eogp.list_event_notification_campaign_deliveries(uuid,uuid,uuid,text,integer,integer)
TO eventor_runtime;
