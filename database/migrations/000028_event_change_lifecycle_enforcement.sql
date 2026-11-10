-- Enforce event-change semantics at the database boundary.
-- Cancellation preserves guest history but closes old invitation/RSVP paths.
-- Postponement/rescheduling retires old schedule links and allows only the
-- replacement schedule to receive new invitation/RSVP activity.

CREATE FUNCTION eogp.guard_event_change_request_revision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_current_revision integer;
BEGIN
  SELECT current_revision
    INTO v_current_revision
    FROM eogp.events
   WHERE organization_id = NEW.organization_id
     AND id = NEW.event_id
   FOR SHARE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'event change request references an unknown event'
      USING ERRCODE = '23503';
  END IF;

  IF NEW.expected_event_revision <> v_current_revision THEN
    RAISE EXCEPTION 'event change request is based on a stale event revision'
      USING ERRCODE = '40001',
            DETAIL = format('expected revision %s, current revision is %s',
                            NEW.expected_event_revision, v_current_revision);
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER event_change_requests_revision_guard
  BEFORE INSERT ON eogp.event_change_requests
  FOR EACH ROW EXECUTE FUNCTION eogp.guard_event_change_request_revision();


CREATE FUNCTION eogp.guard_event_decision_semantics()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_change_kind text;
  v_request_status text;
  v_event_status text;
  v_expected_kind text;
  v_replacement_kind text;
BEGIN
  SELECT request.change_kind, request.status, event.status
    INTO v_change_kind, v_request_status, v_event_status
    FROM eogp.event_change_requests AS request
    JOIN eogp.events AS event
      ON event.organization_id = request.organization_id
     AND event.id = request.event_id
   WHERE request.organization_id = NEW.organization_id
     AND request.event_id = NEW.event_id
     AND request.id = NEW.source_change_request_id
   FOR SHARE OF request, event;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'event decision requires an existing change request'
      USING ERRCODE = '23503';
  END IF;

  IF v_request_status <> 'executed' THEN
    RAISE EXCEPTION 'event decision can be recorded only after the change request is executed'
      USING ERRCODE = '55000';
  END IF;

  v_expected_kind := CASE v_change_kind
    WHEN 'cancel' THEN 'cancelled'
    WHEN 'postpone' THEN 'postponed'
    WHEN 'reschedule' THEN 'rescheduled'
    ELSE NULL
  END;
  IF NEW.decision_kind IS DISTINCT FROM v_expected_kind THEN
    RAISE EXCEPTION 'event decision kind does not match its source change request'
      USING ERRCODE = '23514';
  END IF;

  IF (NEW.decision_kind = 'cancelled' AND v_event_status <> 'cancelled')
     OR (NEW.decision_kind = 'postponed' AND v_event_status <> 'postponed')
     OR (NEW.decision_kind = 'rescheduled' AND v_event_status NOT IN ('scheduled','active')) THEN
    RAISE EXCEPTION 'event status does not match the decision being recorded'
      USING ERRCODE = '23514';
  END IF;

  IF NEW.replacement_schedule_revision_id IS NOT NULL THEN
    SELECT schedule_kind
      INTO v_replacement_kind
      FROM eogp.event_schedule_revisions
     WHERE organization_id = NEW.organization_id
       AND event_id = NEW.event_id
       AND id = NEW.replacement_schedule_revision_id;
    IF NOT FOUND OR v_replacement_kind NOT IN ('reschedule','correction') THEN
      RAISE EXCEPTION 'replacement schedule must be a reschedule or correction revision'
        USING ERRCODE = '23514';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER event_decisions_semantics_guard
  BEFORE INSERT ON eogp.event_decisions
  FOR EACH ROW EXECUTE FUNCTION eogp.guard_event_decision_semantics();


CREATE FUNCTION eogp.guard_event_notification_campaign_semantics()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_decision_kind text;
  v_template_purpose text;
  v_template_state text;
  v_expected_purpose text[];
BEGIN
  IF jsonb_typeof(NEW.audience_rules_snapshot) IS DISTINCT FROM 'object' THEN
    RAISE EXCEPTION 'notification audience rules must be a JSON object'
      USING ERRCODE = '22023';
  END IF;

  SELECT decision.decision_kind
    INTO v_decision_kind
    FROM eogp.event_decisions AS decision
   WHERE decision.organization_id = NEW.organization_id
     AND decision.event_id = NEW.event_id
     AND decision.id = NEW.event_decision_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'notification campaign requires an event decision'
      USING ERRCODE = '23503';
  END IF;

  SELECT template.purpose, revision.state
    INTO v_template_purpose, v_template_state
    FROM eogp.notification_template_revisions AS revision
    JOIN eogp.notification_templates AS template
      ON template.organization_id = revision.organization_id
     AND template.id = revision.template_id
   WHERE revision.organization_id = NEW.organization_id
     AND revision.id = NEW.template_revision_id;
  IF NOT FOUND OR v_template_state <> 'published'
     OR v_template_purpose <> NEW.purpose THEN
    RAISE EXCEPTION 'notification campaign requires a published template for its exact purpose'
      USING ERRCODE = '23514';
  END IF;

  v_expected_purpose := CASE v_decision_kind
    WHEN 'cancelled' THEN ARRAY['event_cancellation']::text[]
    WHEN 'postponed' THEN ARRAY['event_postponement','rsvp_reconfirmation']::text[]
    WHEN 'rescheduled' THEN ARRAY['schedule_update','rsvp_reconfirmation']::text[]
    ELSE ARRAY[]::text[]
  END;
  IF NOT (NEW.purpose = ANY(v_expected_purpose)) THEN
    RAISE EXCEPTION 'notification campaign purpose does not match its event decision'
      USING ERRCODE = '23514';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER event_notification_campaign_semantics_guard
  BEFORE INSERT ON eogp.event_notification_campaigns
  FOR EACH ROW EXECUTE FUNCTION eogp.guard_event_notification_campaign_semantics();


-- Once queued, the audience definition and recipient set are a fixed snapshot.
CREATE FUNCTION eogp.protect_queued_event_notification_campaign()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  IF OLD.status IN ('queued','sending','completed','partial','failed','cancelled')
     AND (
       NEW.event_decision_id IS DISTINCT FROM OLD.event_decision_id
       OR NEW.purpose IS DISTINCT FROM OLD.purpose
       OR NEW.audience_kind IS DISTINCT FROM OLD.audience_kind
       OR NEW.template_revision_id IS DISTINCT FROM OLD.template_revision_id
       OR NEW.audience_rules_snapshot IS DISTINCT FROM OLD.audience_rules_snapshot
       OR NEW.recipient_count IS DISTINCT FROM OLD.recipient_count
     ) THEN
    RAISE EXCEPTION 'queued notification campaign audience is immutable'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER event_notification_campaign_audience_guard
  BEFORE UPDATE ON eogp.event_notification_campaigns
  FOR EACH ROW EXECUTE FUNCTION eogp.protect_queued_event_notification_campaign();


CREATE FUNCTION eogp.protect_queued_event_notification_recipients()
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

  IF v_campaign_status IN ('queued','sending','completed','partial','failed','cancelled') THEN
    RAISE EXCEPTION 'queued notification campaign recipients are immutable'
      USING ERRCODE = '55000';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER event_notification_recipients_audience_guard
  BEFORE INSERT OR UPDATE OR DELETE ON eogp.event_notification_recipients
  FOR EACH ROW EXECUTE FUNCTION eogp.protect_queued_event_notification_recipients();


-- Shared write guard for invitation revisions, links, deliveries and RSVP.
CREATE FUNCTION eogp.guard_event_guest_lifecycle_write()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_event_status text;
  v_required_schedule_id uuid;
  v_invitation_schedule_id uuid;
  v_link_revoked_at timestamptz;
  v_link_expires_at timestamptz;
  v_event_id uuid;
BEGIN
  v_event_id := NEW.event_id;
  SELECT status
    INTO v_event_status
    FROM eogp.events
   WHERE organization_id = NEW.organization_id
     AND id = v_event_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'guest operation references an unknown event'
      USING ERRCODE = '23503';
  END IF;

  IF v_event_status = 'postponed' THEN
    SELECT replacement_schedule_revision_id
      INTO v_required_schedule_id
      FROM eogp.event_decisions
     WHERE organization_id = NEW.organization_id
       AND event_id = v_event_id
       AND decision_kind IN ('postponed','rescheduled')
       AND replacement_schedule_revision_id IS NOT NULL
     ORDER BY effective_at DESC, id DESC
     LIMIT 1;
  ELSE
    SELECT replacement_schedule_revision_id
      INTO v_required_schedule_id
      FROM eogp.event_decisions
     WHERE organization_id = NEW.organization_id
       AND event_id = v_event_id
       AND decision_kind IN ('postponed','rescheduled')
       AND replacement_schedule_revision_id IS NOT NULL
     ORDER BY effective_at DESC, id DESC
     LIMIT 1;
  END IF;

  IF TG_TABLE_NAME = 'invitations' THEN
    IF v_event_status = 'cancelled'
       AND (
         TG_OP = 'INSERT'
         OR (NEW.status = 'active' AND OLD.status IS DISTINCT FROM NEW.status)
         OR NEW.current_revision_number > OLD.current_revision_number
       ) THEN
      RAISE EXCEPTION 'new invitation activity is disabled for a cancelled event'
        USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
  END IF;

  IF v_event_status = 'cancelled' THEN
    IF TG_TABLE_NAME = 'invitation_deliveries'
       AND NEW.status NOT IN ('queued','sending') THEN
      RETURN NEW;
    END IF;
    RAISE EXCEPTION 'guest invitation and RSVP activity is disabled for a cancelled event'
      USING ERRCODE = '55000';
  END IF;

  IF TG_TABLE_NAME = 'invitation_revisions' THEN
    v_invitation_schedule_id := NEW.schedule_revision_id;
  ELSIF TG_TABLE_NAME IN ('invitation_links','invitation_deliveries') THEN
    SELECT schedule_revision_id
      INTO v_invitation_schedule_id
      FROM eogp.invitation_revisions
     WHERE organization_id = NEW.organization_id
       AND event_id = NEW.event_id
       AND invitation_id = NEW.invitation_id
       AND id = CASE
         WHEN TG_TABLE_NAME = 'invitation_links' THEN NEW.invitation_revision_id
         ELSE NEW.invitation_revision_id
       END;
  ELSIF TG_TABLE_NAME = 'rsvp_responses' THEN
    v_invitation_schedule_id := NEW.schedule_revision_id;
  END IF;

  IF v_event_status = 'postponed' AND v_required_schedule_id IS NULL THEN
    RAISE EXCEPTION 'postponed event has no replacement schedule for guest activity'
      USING ERRCODE = '55000';
  END IF;

  IF v_required_schedule_id IS NOT NULL
     AND v_invitation_schedule_id IS DISTINCT FROM v_required_schedule_id
     AND (
       TG_TABLE_NAME IN ('invitation_revisions','invitation_links')
       OR (TG_TABLE_NAME = 'invitation_deliveries' AND NEW.status IN ('queued','sending'))
       OR TG_TABLE_NAME = 'rsvp_responses'
     ) THEN
    RAISE EXCEPTION 'guest activity must use the current replacement schedule revision'
      USING ERRCODE = '55000';
  END IF;

  IF TG_TABLE_NAME = 'rsvp_responses'
     AND NEW.source_channel = 'invitation_link' THEN
    SELECT revoked_at, expires_at
      INTO v_link_revoked_at, v_link_expires_at
      FROM eogp.invitation_links
     WHERE organization_id = NEW.organization_id
       AND event_id = NEW.event_id
       AND invitation_id = NEW.invitation_id
       AND id = NEW.invitation_link_id;
    IF NOT FOUND OR v_link_revoked_at IS NOT NULL
       OR v_link_expires_at <= clock_timestamp() THEN
      RAISE EXCEPTION 'invitation link is expired or revoked'
        USING ERRCODE = '55000';
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER invitations_event_lifecycle_guard
  BEFORE INSERT OR UPDATE ON eogp.invitations
  FOR EACH ROW EXECUTE FUNCTION eogp.guard_event_guest_lifecycle_write();

CREATE TRIGGER invitation_revisions_event_lifecycle_guard
  BEFORE INSERT ON eogp.invitation_revisions
  FOR EACH ROW EXECUTE FUNCTION eogp.guard_event_guest_lifecycle_write();

CREATE TRIGGER invitation_links_event_lifecycle_guard
  BEFORE INSERT ON eogp.invitation_links
  FOR EACH ROW EXECUTE FUNCTION eogp.guard_event_guest_lifecycle_write();

CREATE TRIGGER invitation_deliveries_event_lifecycle_guard
  BEFORE INSERT OR UPDATE ON eogp.invitation_deliveries
  FOR EACH ROW EXECUTE FUNCTION eogp.guard_event_guest_lifecycle_write();

CREATE TRIGGER rsvp_responses_event_lifecycle_guard
  BEFORE INSERT ON eogp.rsvp_responses
  FOR EACH ROW EXECUTE FUNCTION eogp.guard_event_guest_lifecycle_write();


-- A cancellation is organizer-side. It revokes existing invitation links,
-- suppresses pending invitation sends/retries and stops other queued campaigns.
-- It deliberately leaves invitation, RSVP and attendance history unchanged.
CREATE FUNCTION eogp.apply_event_cancellation_guest_suppression()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status AND NEW.status = 'cancelled' THEN
    UPDATE eogp.invitation_links
       SET revoked_at = clock_timestamp()
     WHERE organization_id = NEW.organization_id
       AND event_id = NEW.id
       AND revoked_at IS NULL;

    UPDATE eogp.invitation_deliveries
       SET status = 'suppressed',
           failure_code = coalesce(failure_code, 'event_cancelled')
     WHERE organization_id = NEW.organization_id
       AND event_id = NEW.id
       AND status IN ('queued','failed');

    UPDATE eogp.event_notification_campaigns
       SET status = 'cancelled'
     WHERE organization_id = NEW.organization_id
       AND event_id = NEW.id
       AND purpose <> 'event_cancellation'
       AND status IN ('draft','previewed','confirmed','queued');

    UPDATE eogp.event_notification_delivery_attempts AS attempt
       SET status = 'suppressed',
           failure_code = coalesce(attempt.failure_code, 'event_cancelled')
      FROM eogp.event_notification_campaigns AS campaign
     WHERE campaign.organization_id = attempt.organization_id
       AND campaign.id = attempt.campaign_id
       AND campaign.organization_id = NEW.organization_id
       AND campaign.event_id = NEW.id
       AND campaign.status = 'cancelled'
       AND attempt.status = 'queued';

    UPDATE eogp.admission_credentials
       SET status = 'revoked',
           revoked_at = coalesce(revoked_at, clock_timestamp())
     WHERE organization_id = NEW.organization_id
       AND event_id = NEW.id
       AND status = 'active';
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER events_cancellation_guest_suppression
  AFTER UPDATE OF status ON eogp.events
  FOR EACH ROW EXECUTE FUNCTION eogp.apply_event_cancellation_guest_suppression();


-- A committed postponement/reschedule retires links and pending sends tied
-- to the prior schedule, but preserves their delivery records.
CREATE FUNCTION eogp.retire_superseded_event_schedule_invites()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  IF NEW.decision_kind IN ('postponed','rescheduled')
     AND NEW.replacement_schedule_revision_id IS NOT NULL THEN
    UPDATE eogp.invitation_links AS link
       SET revoked_at = clock_timestamp()
      FROM eogp.invitation_revisions AS revision
     WHERE link.organization_id = NEW.organization_id
       AND link.event_id = NEW.event_id
       AND revision.organization_id = link.organization_id
       AND revision.event_id = link.event_id
       AND revision.invitation_id = link.invitation_id
       AND revision.id = link.invitation_revision_id
       AND revision.schedule_revision_id <> NEW.replacement_schedule_revision_id
       AND link.revoked_at IS NULL;

    UPDATE eogp.invitation_deliveries AS delivery
       SET status = 'suppressed',
           failure_code = coalesce(failure_code, 'event_schedule_superseded')
      FROM eogp.invitation_revisions AS revision
     WHERE delivery.organization_id = NEW.organization_id
       AND delivery.event_id = NEW.event_id
       AND revision.organization_id = delivery.organization_id
       AND revision.event_id = delivery.event_id
       AND revision.invitation_id = delivery.invitation_id
       AND revision.id = delivery.invitation_revision_id
       AND revision.schedule_revision_id <> NEW.replacement_schedule_revision_id
       AND delivery.status IN ('queued','failed');
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER event_decisions_retire_superseded_invites
  AFTER INSERT ON eogp.event_decisions
  FOR EACH ROW EXECUTE FUNCTION eogp.retire_superseded_event_schedule_invites();


REVOKE ALL ON FUNCTION eogp.guard_event_change_request_revision() FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.guard_event_decision_semantics() FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.guard_event_notification_campaign_semantics() FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.protect_queued_event_notification_campaign() FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.protect_queued_event_notification_recipients() FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.guard_event_guest_lifecycle_write() FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.apply_event_cancellation_guest_suppression() FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.retire_superseded_event_schedule_invites() FROM PUBLIC;

GRANT EXECUTE ON FUNCTION eogp.guard_event_change_request_revision(),
  eogp.guard_event_decision_semantics(),
  eogp.guard_event_notification_campaign_semantics(),
  eogp.protect_queued_event_notification_recipients(),
  eogp.guard_event_guest_lifecycle_write(),
  eogp.apply_event_cancellation_guest_suppression(),
  eogp.retire_superseded_event_schedule_invites()
  TO eventor_runtime, eventor_worker;
