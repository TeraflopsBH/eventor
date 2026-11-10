-- Organizer review and explicit confirmation of fixed notification campaign snapshots.
-- Confirmation is a human authorization step; it does not queue or deliver messages.

CREATE FUNCTION eogp.get_event_notification_campaign_review(
  p_organization_id uuid,
  p_campaign_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_event_id uuid;
  v_result jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;

  SELECT campaign.event_id
    INTO v_event_id
    FROM eogp.event_notification_campaigns AS campaign
   WHERE campaign.organization_id = p_organization_id
     AND campaign.id = p_campaign_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'notification campaign not found' USING ERRCODE = 'P0002';
  END IF;

  PERFORM eogp.assert_event_command_permission(
    p_organization_id, v_event_id, p_actor_membership_id,
    'event.cancellation.notifications.preview'
  );

  SELECT jsonb_build_object(
    'campaignId', campaign.id,
    'eventId', campaign.event_id,
    'eventDecisionId', campaign.event_decision_id,
    'purpose', campaign.purpose,
    'audienceKind', campaign.audience_kind,
    'status', campaign.status,
    'recipientCount', campaign.recipient_count,
    'actualRecipientCount', (
      SELECT count(*) FROM eogp.event_notification_recipients AS recipient
       WHERE recipient.organization_id = campaign.organization_id
         AND recipient.campaign_id = campaign.id
    ),
    'recipientsByChannel', (
      SELECT coalesce(jsonb_object_agg(channel_counts.channel, channel_counts.total), '{}'::jsonb)
        FROM (
          SELECT recipient.channel, count(*) AS total
            FROM eogp.event_notification_recipients AS recipient
           WHERE recipient.organization_id = campaign.organization_id
             AND recipient.campaign_id = campaign.id
           GROUP BY recipient.channel
        ) AS channel_counts
    ),
    'exclusionCount', (
      SELECT count(*) FROM eogp.event_notification_exclusions AS exclusion
       WHERE exclusion.organization_id = campaign.organization_id
         AND exclusion.campaign_id = campaign.id
    ),
    'exclusionsByReason', (
      SELECT coalesce(jsonb_object_agg(reason_counts.exclusion_reason, reason_counts.total), '{}'::jsonb)
        FROM (
          SELECT exclusion.exclusion_reason, count(*) AS total
            FROM eogp.event_notification_exclusions AS exclusion
           WHERE exclusion.organization_id = campaign.organization_id
             AND exclusion.campaign_id = campaign.id
           GROUP BY exclusion.exclusion_reason
        ) AS reason_counts
    ),
    'recipients', (
      SELECT coalesce(jsonb_agg(jsonb_build_object(
        'participationId', recipient.participation_id,
        'invitationId', recipient.invitation_id,
        'channel', recipient.channel,
        'qualificationReason', recipient.qualification_reason
      ) ORDER BY recipient.created_at, recipient.id), '[]'::jsonb)
        FROM eogp.event_notification_recipients AS recipient
       WHERE recipient.organization_id = campaign.organization_id
         AND recipient.campaign_id = campaign.id
    ),
    'template', jsonb_build_object(
      'revisionId', template_revision.id,
      'revisionNumber', template_revision.revision_number,
      'locale', template_revision.locale,
      'subjectTemplate', template_revision.subject_template,
      'bodyTemplate', template_revision.body_template,
      'state', template_revision.state,
      'publishedAt', template_revision.published_at
    ),
    'audienceRulesSnapshot', campaign.audience_rules_snapshot,
    'createdAt', campaign.created_at,
    'confirmedAt', campaign.confirmed_at
  )
    INTO v_result
    FROM eogp.event_notification_campaigns AS campaign
    JOIN eogp.notification_template_revisions AS template_revision
      ON template_revision.organization_id = campaign.organization_id
     AND template_revision.id = campaign.template_revision_id
   WHERE campaign.organization_id = p_organization_id
     AND campaign.id = p_campaign_id;

  RETURN v_result;
END;
$function$;

CREATE FUNCTION eogp.confirm_event_notification_campaign(
  p_organization_id uuid,
  p_campaign_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_campaign eogp.event_notification_campaigns%ROWTYPE;
  v_event_status text;
  v_actual_recipient_count integer;
  v_decision_kind text;
  v_new_status text;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_campaign
    FROM eogp.event_notification_campaigns
   WHERE organization_id = p_organization_id
     AND id = p_campaign_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'notification campaign not found' USING ERRCODE = 'P0002';
  END IF;

  PERFORM eogp.assert_event_command_permission(
    p_organization_id, v_campaign.event_id, p_actor_membership_id,
    'event.cancellation.notifications.send'
  );

  IF v_campaign.status <> 'previewed' THEN
    RAISE EXCEPTION 'only a previewed notification campaign can be confirmed'
      USING ERRCODE = '55000';
  END IF;

  SELECT event.status, decision.decision_kind
    INTO v_event_status, v_decision_kind
    FROM eogp.events AS event
    JOIN eogp.event_decisions AS decision
      ON decision.organization_id = event.organization_id
     AND decision.event_id = event.id
   WHERE event.organization_id = p_organization_id
     AND event.id = v_campaign.event_id
     AND decision.id = v_campaign.event_decision_id
     AND NOT EXISTS (
       SELECT 1 FROM eogp.event_decisions AS newer
        WHERE newer.organization_id = decision.organization_id
          AND newer.event_id = decision.event_id
          AND (newer.effective_at, newer.id) > (decision.effective_at, decision.id)
     )
   FOR UPDATE OF event;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'campaign decision is no longer the current event decision'
      USING ERRCODE = '55000';
  END IF;

  IF (v_decision_kind = 'cancelled' AND v_event_status <> 'cancelled')
     OR (v_decision_kind = 'postponed' AND v_event_status <> 'postponed')
     OR (v_decision_kind = 'rescheduled' AND v_event_status IN ('cancelled','completed','archived')) THEN
    RAISE EXCEPTION 'campaign decision no longer matches the event lifecycle'
      USING ERRCODE = '55000';
  END IF;

  SELECT count(*)::integer
    INTO v_actual_recipient_count
    FROM eogp.event_notification_recipients
   WHERE organization_id = p_organization_id
     AND campaign_id = p_campaign_id;
  IF v_campaign.recipient_count IS DISTINCT FROM v_actual_recipient_count THEN
    RAISE EXCEPTION 'campaign recipient snapshot is incomplete or inconsistent'
      USING ERRCODE = '55000';
  END IF;

  IF NOT EXISTS (
    SELECT 1
      FROM eogp.notification_template_revisions AS revision
      JOIN eogp.notification_templates AS template
        ON template.organization_id = revision.organization_id
       AND template.id = revision.template_id
     WHERE revision.organization_id = p_organization_id
       AND revision.id = v_campaign.template_revision_id
       AND revision.state = 'published'
       AND template.status = 'active'
  ) THEN
    RAISE EXCEPTION 'campaign template revision is no longer published and active'
      USING ERRCODE = '55000';
  END IF;

  UPDATE eogp.event_notification_campaigns
     SET status = 'confirmed',
         confirmed_by_organization_id = p_organization_id,
         confirmed_by_membership_id = p_actor_membership_id,
         confirmed_at = clock_timestamp()
   WHERE organization_id = p_organization_id
     AND id = p_campaign_id;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_organization_id, p_organization_id, p_actor_membership_id, 'membership',
    'event.notification_campaign.confirmed', 'event_notification_campaign', p_campaign_id,
    jsonb_build_object(
      'eventId', v_campaign.event_id,
      'eventDecisionId', v_campaign.event_decision_id,
      'purpose', v_campaign.purpose,
      'audienceKind', v_campaign.audience_kind,
      'recipientCount', v_actual_recipient_count,
      'templateRevisionId', v_campaign.template_revision_id
    )
  );

  RETURN jsonb_build_object(
    'campaignId', p_campaign_id,
    'eventId', v_campaign.event_id,
    'status', 'confirmed',
    'recipientCount', v_actual_recipient_count,
    'confirmedAt', clock_timestamp(),
    'deliveryQueued', false
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.get_event_notification_campaign_review(uuid,uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.confirm_event_notification_campaign(uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.get_event_notification_campaign_review(uuid,uuid,uuid),
  eogp.confirm_event_notification_campaign(uuid,uuid,uuid) TO eventor_runtime;

-- The runtime may inspect the campaign and its immutable recipient/exclusion
-- snapshots, but only the command function can confirm or mutate campaign rows.
REVOKE INSERT, UPDATE, DELETE ON
  eogp.event_notification_campaigns,
  eogp.event_notification_recipients,
  eogp.event_notification_exclusions,
  eogp.event_notification_delivery_attempts
FROM eventor_runtime;
GRANT SELECT ON
  eogp.event_notification_campaigns,
  eogp.event_notification_recipients,
  eogp.event_notification_exclusions,
  eogp.event_notification_delivery_attempts
TO eventor_runtime;

CREATE FUNCTION eogp.guard_event_notification_campaign_update()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  IF current_user = 'eventor_worker'
     AND OLD.status = 'previewed'
     AND NEW.status = 'previewed'
     AND (to_jsonb(NEW) - 'recipient_count') = (to_jsonb(OLD) - 'recipient_count') THEN
    RETURN NEW;
  END IF;

  IF current_user = 'eventor_owner'
     AND OLD.status = 'previewed'
     AND NEW.status = 'confirmed'
     AND (to_jsonb(NEW) - ARRAY[
       'status','confirmed_by_organization_id','confirmed_by_membership_id',
       'confirmed_by_grant_owner_organization_id','confirmed_by_collaboration_grant_id',
       'confirmed_at'
     ]) = (to_jsonb(OLD) - ARRAY[
       'status','confirmed_by_organization_id','confirmed_by_membership_id',
       'confirmed_by_grant_owner_organization_id','confirmed_by_collaboration_grant_id',
       'confirmed_at'
     ])
     AND NEW.confirmed_by_organization_id IS NOT NULL
     AND NEW.confirmed_by_membership_id IS NOT NULL
     AND NEW.confirmed_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'notification campaigns may only receive worker recipient-count updates or an authorized preview confirmation'
    USING ERRCODE = '55000';
END;
$function$;

CREATE TRIGGER event_notification_campaign_update_guard
  BEFORE UPDATE ON eogp.event_notification_campaigns
  FOR EACH ROW EXECUTE FUNCTION eogp.guard_event_notification_campaign_update();


-- A confirmed campaign is a fixed snapshot: no later worker or privileged
-- application path may append recipients or exclusions to it.
CREATE OR REPLACE FUNCTION eogp.protect_queued_event_notification_recipients()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_campaign_id uuid;
  v_organization_id uuid;
  v_campaign_status text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_campaign_id := OLD.campaign_id;
    v_organization_id := OLD.organization_id;
  ELSE
    v_campaign_id := NEW.campaign_id;
    v_organization_id := NEW.organization_id;
  END IF;

  SELECT status
    INTO v_campaign_status
    FROM eogp.event_notification_campaigns
   WHERE organization_id = v_organization_id
     AND id = v_campaign_id;

  IF v_campaign_status IN ('confirmed','queued','sending','completed','partial','failed','cancelled') THEN
    RAISE EXCEPTION 'confirmed or queued notification campaign recipients are immutable'
      USING ERRCODE = '55000';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE FUNCTION eogp.protect_confirmed_event_notification_exclusions()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_campaign_status text;
BEGIN
  SELECT status
    INTO v_campaign_status
    FROM eogp.event_notification_campaigns
   WHERE organization_id = NEW.organization_id
     AND id = NEW.campaign_id;

  IF v_campaign_status IN ('confirmed','queued','sending','completed','partial','failed','cancelled') THEN
    RAISE EXCEPTION 'confirmed or queued notification campaign exclusions are immutable'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER event_notification_exclusions_audience_guard
  BEFORE INSERT ON eogp.event_notification_exclusions
  FOR EACH ROW EXECUTE FUNCTION eogp.protect_confirmed_event_notification_exclusions();
