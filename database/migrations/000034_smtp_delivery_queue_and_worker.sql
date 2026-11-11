-- Explicit SMTP verification, campaign queueing and tenant-aware email delivery.
-- Campaign confirmation remains non-delivering. A successful, explicit SMTP test
-- enables the current config revision; a separate queue command authorizes sends.

ALTER TABLE eogp.organization_delivery_config_heads
  ADD COLUMN delivery_enabled boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION eogp.set_organization_email_delivery_config(
  p_organization_id uuid,
  p_actor_membership_id uuid,
  p_settings jsonb,
  p_credentials_ciphertext bytea DEFAULT NULL,
  p_replace_credentials boolean DEFAULT false,
  p_clear_credentials boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_previous_ciphertext bytea;
  v_next_ciphertext bytea;
  v_revision integer;
  v_revision_id uuid := gen_random_uuid();
  v_settings jsonb;
  v_host text;
  v_sender text;
  v_reply_to text;
  v_auth_mode text;
  v_security text;
  v_port integer;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_event_command_permission(
    p_organization_id, NULL, p_actor_membership_id, 'organization.delivery.manage'
  );

  IF jsonb_typeof(p_settings) IS DISTINCT FROM 'object'
     OR (p_settings - ARRAY[
       'host','port','transportSecurity','authMode','senderEmail',
       'senderName','replyTo','connectionTimeoutMs'
     ]) <> '{}'::jsonb THEN
    RAISE EXCEPTION 'invalid SMTP settings object' USING ERRCODE = '22023';
  END IF;

  v_host := lower(btrim(coalesce(p_settings ->> 'host','')));
  v_sender := lower(btrim(coalesce(p_settings ->> 'senderEmail','')));
  v_reply_to := lower(btrim(coalesce(p_settings ->> 'replyTo','')));
  v_auth_mode := coalesce(p_settings ->> 'authMode','');
  v_security := coalesce(p_settings ->> 'transportSecurity','');
  BEGIN
    v_port := (p_settings ->> 'port')::integer;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'SMTP port must be an integer' USING ERRCODE = '22023';
  END;

  IF length(v_host) < 1 OR length(v_host) > 253
     OR v_host !~ '^[a-z0-9][a-z0-9.-]*[a-z0-9]$'
     OR v_port NOT BETWEEN 1 AND 65535
     OR v_security NOT IN ('starttls','implicit_tls')
     OR v_auth_mode NOT IN ('none','password')
     OR v_sender !~ '^[^[:space:]<>@]+@[^[:space:]<>@]+\\.[^[:space:]<>@]+$'
     OR (v_reply_to <> '' AND v_reply_to !~ '^[^[:space:]<>@]+@[^[:space:]<>@]+\\.[^[:space:]<>@]+$')
     OR coalesce((p_settings ->> 'connectionTimeoutMs')::integer,15000) NOT BETWEEN 1000 AND 60000
     OR length(coalesce(p_settings ->> 'senderName','')) > 200 THEN
    RAISE EXCEPTION 'SMTP settings failed validation' USING ERRCODE = '22023';
  END IF;

  IF p_replace_credentials AND p_clear_credentials THEN
    RAISE EXCEPTION 'credentials cannot be replaced and cleared together' USING ERRCODE = '22023';
  END IF;
  IF p_replace_credentials AND (
    p_credentials_ciphertext IS NULL OR octet_length(p_credentials_ciphertext) < 33
    OR substring(p_credentials_ciphertext FROM 1 FOR 4) <> convert_to('EDC1','UTF8')
  ) THEN
    RAISE EXCEPTION 'a valid EDC1 credential envelope is required' USING ERRCODE = '22023';
  END IF;
  IF NOT p_replace_credentials AND p_credentials_ciphertext IS NOT NULL THEN
    RAISE EXCEPTION 'credential ciphertext requires replace_credentials' USING ERRCODE = '22023';
  END IF;

  SELECT revision.credentials_ciphertext
    INTO v_previous_ciphertext
    FROM eogp.organization_delivery_config_heads AS head
    JOIN eogp.organization_delivery_config_revisions AS revision
      ON revision.organization_id = head.organization_id
     AND revision.id = head.revision_id
   WHERE head.organization_id = p_organization_id
     AND head.channel = 'email'
   FOR UPDATE OF head;

  IF p_clear_credentials THEN v_next_ciphertext := NULL;
  ELSIF p_replace_credentials THEN v_next_ciphertext := p_credentials_ciphertext;
  ELSE v_next_ciphertext := v_previous_ciphertext;
  END IF;

  IF v_auth_mode = 'password' AND v_next_ciphertext IS NULL THEN
    RAISE EXCEPTION 'SMTP password authentication requires configured credentials' USING ERRCODE = '22023';
  END IF;
  IF v_auth_mode = 'none' AND v_next_ciphertext IS NOT NULL THEN
    RAISE EXCEPTION 'SMTP credentials must be cleared when authentication is disabled' USING ERRCODE = '22023';
  END IF;

  SELECT coalesce(max(revision),0) + 1 INTO v_revision
    FROM eogp.organization_delivery_config_revisions
   WHERE organization_id = p_organization_id AND channel = 'email';

  v_settings := jsonb_build_object(
    'host',v_host,'port',v_port,'transportSecurity',v_security,
    'authMode',v_auth_mode,'senderEmail',v_sender,
    'senderName',coalesce(p_settings ->> 'senderName',''),
    'replyTo',nullif(v_reply_to,''),
    'connectionTimeoutMs',coalesce((p_settings ->> 'connectionTimeoutMs')::integer,15000)
  );

  INSERT INTO eogp.organization_delivery_config_revisions (
    id, organization_id, channel, revision, provider, settings,
    credentials_ciphertext, created_by_membership_id
  ) VALUES (
    v_revision_id,p_organization_id,'email',v_revision,'smtp',
    v_settings,v_next_ciphertext,p_actor_membership_id
  );

  INSERT INTO eogp.organization_delivery_config_heads (
    organization_id,channel,revision_id,delivery_enabled
  ) VALUES (p_organization_id,'email',v_revision_id,false)
  ON CONFLICT (organization_id,channel) DO UPDATE
    SET revision_id = EXCLUDED.revision_id,
        delivery_enabled = false,
        updated_at = clock_timestamp();

  INSERT INTO eogp.audit_events (
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'organization.delivery.email_configured','organization_delivery_config',v_revision_id,
    jsonb_build_object(
      'channel','email','provider','smtp','revision',v_revision,
      'host',v_host,'port',v_port,'transportSecurity',v_security,
      'authMode',v_auth_mode,'credentialsConfigured',v_next_ciphertext IS NOT NULL,
      'deliveryEnabled',false
    )
  );

  RETURN jsonb_build_object(
    'channel','email','provider','smtp','revision',v_revision,
    'settings',v_settings,'credentialsConfigured',v_next_ciphertext IS NOT NULL,
    'deliveryEnabled',false,'updatedAt',clock_timestamp()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.get_organization_email_delivery_config(
  p_organization_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE v_result jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;
  PERFORM eogp.assert_event_command_permission(
    p_organization_id,NULL,p_actor_membership_id,'organization.delivery.manage'
  );
  SELECT jsonb_build_object(
    'channel',revision.channel,'provider',revision.provider,
    'revision',revision.revision,'settings',revision.settings,
    'credentialsConfigured',revision.credentials_ciphertext IS NOT NULL,
    'deliveryEnabled',head.delivery_enabled,'updatedAt',revision.created_at
  ) INTO v_result
  FROM eogp.organization_delivery_config_heads AS head
  JOIN eogp.organization_delivery_config_revisions AS revision
    ON revision.organization_id=head.organization_id AND revision.id=head.revision_id
  WHERE head.organization_id=p_organization_id AND head.channel='email';
  RETURN coalesce(v_result,jsonb_build_object(
    'channel','email','configured',false,
    'credentialsConfigured',false,'deliveryEnabled',false
  ));
END;
$function$;

CREATE TABLE eogp.organization_delivery_test_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  config_revision_id uuid NOT NULL,
  idempotency_key_sha256 text NOT NULL CHECK (idempotency_key_sha256 ~ '^[0-9a-f]{64}$'),
  recipient_sha256 text NOT NULL CHECK (recipient_sha256 ~ '^[0-9a-f]{64}$'),
  status text NOT NULL CHECK (status IN ('pending','succeeded','failed')),
  failure_code text,
  created_by_membership_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  completed_at timestamptz,
  UNIQUE (organization_id,id),
  UNIQUE (organization_id,idempotency_key_sha256),
  FOREIGN KEY (organization_id,config_revision_id)
    REFERENCES eogp.organization_delivery_config_revisions(organization_id,id),
  FOREIGN KEY (organization_id,created_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id,id),
  CHECK ((status='pending') = (completed_at IS NULL))
);
ALTER TABLE eogp.organization_delivery_test_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.organization_delivery_test_requests FORCE ROW LEVEL SECURITY;
CREATE POLICY organization_delivery_test_tenant
  ON eogp.organization_delivery_test_requests
  USING (organization_id=eogp.current_organization_id())
  WITH CHECK (organization_id=eogp.current_organization_id());
REVOKE ALL ON eogp.organization_delivery_test_requests FROM PUBLIC,eventor_runtime,eventor_worker;

CREATE FUNCTION eogp.begin_organization_email_delivery_test(
  p_organization_id uuid,
  p_actor_membership_id uuid,
  p_idempotency_sha256 text,
  p_recipient_sha256 text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
DECLARE
  v_revision eogp.organization_delivery_config_revisions%ROWTYPE;
  v_request_id uuid;
  v_status text;
  v_existing_recipient_hash text;
  v_existing_revision_id uuid;
  v_created boolean := false;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_event_command_permission(
    p_organization_id,NULL,p_actor_membership_id,'organization.delivery.manage'
  );
  IF p_idempotency_sha256 !~ '^[0-9a-f]{64}$' OR p_recipient_sha256 !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'invalid delivery test fingerprint' USING ERRCODE='22023';
  END IF;

  SELECT revision.* INTO v_revision
  FROM eogp.organization_delivery_config_heads head
  JOIN eogp.organization_delivery_config_revisions revision
    ON revision.organization_id=head.organization_id AND revision.id=head.revision_id
  WHERE head.organization_id=p_organization_id AND head.channel='email';
  IF NOT FOUND THEN RAISE EXCEPTION 'SMTP configuration is missing' USING ERRCODE='55000'; END IF;
  IF v_revision.settings->>'authMode'='password' AND v_revision.credentials_ciphertext IS NULL THEN
    RAISE EXCEPTION 'SMTP credentials are missing' USING ERRCODE='55000';
  END IF;

  INSERT INTO eogp.organization_delivery_test_requests(
    organization_id,config_revision_id,idempotency_key_sha256,recipient_sha256,
    status,created_by_membership_id
  ) VALUES (
    p_organization_id,v_revision.id,p_idempotency_sha256,p_recipient_sha256,
    'pending',p_actor_membership_id
  )
  ON CONFLICT (organization_id,idempotency_key_sha256) DO NOTHING
  RETURNING id INTO v_request_id;
  IF v_request_id IS NOT NULL THEN
    v_created := true;
    v_status := 'pending';
  ELSE
    SELECT id,status,recipient_sha256,config_revision_id
      INTO v_request_id,v_status,v_existing_recipient_hash,v_existing_revision_id
      FROM eogp.organization_delivery_test_requests
     WHERE organization_id=p_organization_id
       AND idempotency_key_sha256=p_idempotency_sha256;
    IF v_existing_recipient_hash IS DISTINCT FROM p_recipient_sha256
       OR v_existing_revision_id IS DISTINCT FROM v_revision.id THEN
      RAISE EXCEPTION 'idempotency key already used for a different SMTP test request'
        USING ERRCODE='23505';
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'requestId',v_request_id,'status',v_status,'created',v_created,
    'configRevisionId',v_revision.id,
    'settings',CASE WHEN v_created THEN v_revision.settings ELSE NULL END,
    'credentialsCiphertextBase64',CASE WHEN v_created AND v_revision.credentials_ciphertext IS NOT NULL
      THEN encode(v_revision.credentials_ciphertext,'base64') ELSE NULL END
  );
END;
$function$;

CREATE FUNCTION eogp.complete_organization_email_delivery_test(
  p_organization_id uuid,
  p_actor_membership_id uuid,
  p_request_id uuid,
  p_succeeded boolean,
  p_failure_code text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_request eogp.organization_delivery_test_requests%ROWTYPE;
  v_enabled boolean := false;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_event_command_permission(
    p_organization_id,NULL,p_actor_membership_id,'organization.delivery.manage'
  );
  SELECT * INTO v_request FROM eogp.organization_delivery_test_requests
   WHERE organization_id=p_organization_id AND id=p_request_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'SMTP test request not found' USING ERRCODE='P0002'; END IF;
  IF v_request.status <> 'pending' THEN
    RETURN jsonb_build_object('requestId',p_request_id,'status',v_request.status,'deliveryEnabled',false);
  END IF;

  UPDATE eogp.organization_delivery_test_requests
     SET status=CASE WHEN p_succeeded THEN 'succeeded' ELSE 'failed' END,
         failure_code=CASE WHEN p_succeeded THEN NULL ELSE left(coalesce(p_failure_code,'SMTP_UNKNOWN'),80) END,
         completed_at=clock_timestamp()
   WHERE organization_id=p_organization_id AND id=p_request_id;

  IF p_succeeded THEN
    UPDATE eogp.organization_delivery_config_heads
       SET delivery_enabled=true,updated_at=clock_timestamp()
     WHERE organization_id=p_organization_id AND channel='email'
       AND revision_id=v_request.config_revision_id;
    v_enabled := FOUND;
  END IF;

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    CASE WHEN p_succeeded THEN 'organization.delivery.email_test_succeeded'
         ELSE 'organization.delivery.email_test_failed' END,
    'organization_delivery_test',p_request_id,
    jsonb_build_object('configRevisionId',v_request.config_revision_id,
      'failureCode',CASE WHEN p_succeeded THEN NULL ELSE p_failure_code END,
      'deliveryEnabled',v_enabled)
  );

  RETURN jsonb_build_object(
    'requestId',p_request_id,
    'status',CASE WHEN p_succeeded THEN 'succeeded' ELSE 'failed' END,
    'deliveryEnabled',v_enabled
  );
END;
$function$;

ALTER TABLE eogp.event_notification_campaigns
  ADD COLUMN delivery_config_revision_id uuid,
  ADD COLUMN queued_by_organization_id uuid,
  ADD COLUMN queued_by_membership_id uuid,
  ADD COLUMN queued_at timestamptz,
  ADD COLUMN delivery_started_at timestamptz,
  ADD COLUMN delivery_completed_at timestamptz,
  ADD CONSTRAINT event_notification_campaign_delivery_config_fk
    FOREIGN KEY (organization_id,delivery_config_revision_id)
    REFERENCES eogp.organization_delivery_config_revisions(organization_id,id),
  ADD CONSTRAINT event_notification_campaign_queued_by_fk
    FOREIGN KEY (queued_by_organization_id,queued_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id,id),
  ADD CONSTRAINT event_notification_campaign_queue_state_check
    CHECK (
      (status NOT IN ('queued','sending','completed','partial','failed')
        OR (delivery_config_revision_id IS NOT NULL AND queued_at IS NOT NULL
            AND queued_by_membership_id IS NOT NULL))
    ),
  ADD CONSTRAINT event_notification_campaign_queue_actor_check
    CHECK ((queued_by_membership_id IS NULL)=(queued_by_organization_id IS NULL));

ALTER TABLE eogp.event_notification_delivery_attempts
  DROP CONSTRAINT event_notification_delivery_attempts_status_check,
  ADD CONSTRAINT event_notification_delivery_attempts_status_check
    CHECK (status IN ('queued','sending','sent','delivered','failed','bounced','suppressed','uncertain')),
  ALTER COLUMN attempted_at DROP NOT NULL,
  ALTER COLUMN attempted_at DROP DEFAULT,
  ADD COLUMN next_attempt_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  ADD COLUMN lease_expires_at timestamptz;

CREATE INDEX event_notification_delivery_ready_idx
  ON eogp.event_notification_delivery_attempts(organization_id,next_attempt_at,id)
  WHERE status='queued';

-- A minimal cross-tenant discovery index. The worker can see only tenant IDs
-- and due times, never campaign contents or recipient/contact data.
CREATE TABLE eogp.email_delivery_tenant_queue (
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
  available_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (organization_id)
);
ALTER TABLE eogp.email_delivery_tenant_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.email_delivery_tenant_queue FORCE ROW LEVEL SECURITY;
CREATE POLICY email_delivery_queue_tenant
  ON eogp.email_delivery_tenant_queue
  USING (organization_id=eogp.current_organization_id())
  WITH CHECK (organization_id=eogp.current_organization_id());
CREATE POLICY email_delivery_queue_worker_discovery
  ON eogp.email_delivery_tenant_queue
  FOR SELECT TO eventor_worker USING (true);
REVOKE ALL ON eogp.email_delivery_tenant_queue FROM PUBLIC,eventor_runtime,eventor_worker;
GRANT SELECT (organization_id,available_at)
  ON eogp.email_delivery_tenant_queue TO eventor_worker;

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

CREATE FUNCTION eogp.queue_event_notification_campaign(
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
  v_config_revision_id uuid;
  v_event_status text;
  v_decision_kind text;
  v_recipient_count integer;
  v_email_count integer;
  v_sms_count integer;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_campaign FROM eogp.event_notification_campaigns
   WHERE organization_id=p_organization_id AND id=p_campaign_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'notification campaign not found' USING ERRCODE='P0002'; END IF;
  PERFORM eogp.assert_event_command_permission(
    p_organization_id,v_campaign.event_id,p_actor_membership_id,'event.notifications.send'
  );
  IF v_campaign.status<>'confirmed' THEN
    RAISE EXCEPTION 'only a confirmed campaign can be queued' USING ERRCODE='55000';
  END IF;

  SELECT head.revision_id INTO v_config_revision_id
    FROM eogp.organization_delivery_config_heads head
    JOIN eogp.organization_delivery_config_revisions revision
      ON revision.organization_id=head.organization_id AND revision.id=head.revision_id
   WHERE head.organization_id=p_organization_id AND head.channel='email'
     AND head.delivery_enabled=true AND revision.provider='smtp'
     AND (revision.settings->>'authMode'<>'password' OR revision.credentials_ciphertext IS NOT NULL);
  IF v_config_revision_id IS NULL THEN
    RAISE EXCEPTION 'organization SMTP delivery is not enabled; send a successful test email first'
      USING ERRCODE='55000';
  END IF;

  SELECT count(*)::integer,
         count(*) FILTER (WHERE channel='email')::integer,
         count(*) FILTER (WHERE channel='sms')::integer
    INTO v_recipient_count,v_email_count,v_sms_count
    FROM eogp.event_notification_recipients
   WHERE organization_id=p_organization_id AND campaign_id=p_campaign_id;
  IF v_campaign.recipient_count IS DISTINCT FROM v_recipient_count THEN
    RAISE EXCEPTION 'campaign recipient snapshot is incomplete or inconsistent' USING ERRCODE='55000';
  END IF;
  IF v_email_count=0 THEN
    RAISE EXCEPTION 'campaign has no email recipients; no SMS provider is configured' USING ERRCODE='55000';
  END IF;

  SELECT event.status,decision.decision_kind
    INTO v_event_status,v_decision_kind
    FROM eogp.events event
    JOIN eogp.event_decisions decision
      ON decision.organization_id=event.organization_id AND decision.event_id=event.id
   WHERE event.organization_id=p_organization_id AND event.id=v_campaign.event_id
     AND decision.id=v_campaign.event_decision_id
     AND NOT EXISTS (
       SELECT 1 FROM eogp.event_decisions newer
        WHERE newer.organization_id=decision.organization_id AND newer.event_id=decision.event_id
          AND (newer.effective_at,newer.id)>(decision.effective_at,decision.id)
     )
   FOR UPDATE OF event;
  IF NOT FOUND
     OR (v_decision_kind='cancelled' AND v_event_status<>'cancelled')
     OR (v_decision_kind='postponed' AND v_event_status<>'postponed')
     OR (v_decision_kind='rescheduled' AND v_event_status IN ('cancelled','completed','archived')) THEN
    RAISE EXCEPTION 'campaign decision is no longer current for this event' USING ERRCODE='55000';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM eogp.notification_template_revisions revision
    JOIN eogp.notification_templates template
      ON template.organization_id=revision.organization_id AND template.id=revision.template_id
    WHERE revision.organization_id=p_organization_id
      AND revision.id=v_campaign.template_revision_id
      AND revision.state='published' AND template.status='active'
  ) THEN
    RAISE EXCEPTION 'campaign template is no longer active and published' USING ERRCODE='55000';
  END IF;

  UPDATE eogp.event_notification_campaigns
     SET status='queued',delivery_config_revision_id=v_config_revision_id,
         queued_by_organization_id=p_organization_id,
         queued_by_membership_id=p_actor_membership_id,
         queued_at=clock_timestamp()
   WHERE organization_id=p_organization_id AND id=p_campaign_id;

  INSERT INTO eogp.event_notification_delivery_attempts(
    organization_id,campaign_id,recipient_id,attempt_number,status,next_attempt_at,failure_code
  )
  SELECT recipient.organization_id,recipient.campaign_id,recipient.id,1,
         CASE WHEN recipient.channel='email' THEN 'queued' ELSE 'suppressed' END,
         clock_timestamp(),
         CASE WHEN recipient.channel='email' THEN NULL ELSE 'SMS_CHANNEL_NOT_CONFIGURED' END
    FROM eogp.event_notification_recipients recipient
   WHERE recipient.organization_id=p_organization_id AND recipient.campaign_id=p_campaign_id;

  INSERT INTO eogp.email_delivery_tenant_queue(organization_id,available_at)
  VALUES (p_organization_id,clock_timestamp())
  ON CONFLICT (organization_id) DO UPDATE
    SET available_at=least(eogp.email_delivery_tenant_queue.available_at,EXCLUDED.available_at);

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'event.notification_campaign.queued','event_notification_campaign',p_campaign_id,
    jsonb_build_object('deliveryConfigRevisionId',v_config_revision_id,
      'emailRecipientCount',v_email_count,'smsSuppressedCount',v_sms_count)
  );

  RETURN jsonb_build_object(
    'campaignId',p_campaign_id,'status','queued',
    'emailRecipientCount',v_email_count,'smsSuppressedCount',v_sms_count,
    'deliveryConfigRevisionId',v_config_revision_id,'queuedAt',clock_timestamp()
  );
END;
$function$;

CREATE FUNCTION eogp.discover_pending_email_delivery_tenants()
RETURNS TABLE(organization_id uuid)
LANGUAGE plpgsql
SET search_path=pg_catalog,eogp
AS $function$
BEGIN
  IF session_user<>'eventor_worker' THEN
    RAISE EXCEPTION 'delivery tenant discovery requires eventor_worker' USING ERRCODE='42501';
  END IF;
  RETURN QUERY
    SELECT queue.organization_id
      FROM eogp.email_delivery_tenant_queue queue
     WHERE queue.available_at<=clock_timestamp()
     ORDER BY queue.available_at,queue.organization_id
     LIMIT 1000;
END;
$function$;

CREATE FUNCTION eogp.claim_next_email_delivery(
  p_organization_id uuid
) RETURNS TABLE(
  attempt_id uuid,campaign_id uuid,recipient_id uuid,
  destination_ciphertext bytea,credentials_ciphertext bytea,
  smtp_settings jsonb,sender_email text,sender_name text,reply_to text,
  subject_template text,body_template text,event_title text,event_code text,
  event_status text,decision_kind text,campaign_purpose text,
  starts_at timestamptz,ends_at timestamptz,timezone_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE v_attempt record;
BEGIN
  IF session_user<>'eventor_worker'
     OR eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'delivery claim requires worker role and matching tenant context'
      USING ERRCODE='42501';
  END IF;

  UPDATE eogp.event_notification_delivery_attempts
     SET status='uncertain',failure_code='SMTP_UNKNOWN',lease_expires_at=NULL
   WHERE organization_id=p_organization_id
     AND status='sending' AND lease_expires_at<clock_timestamp();

  UPDATE eogp.event_notification_campaigns campaign
     SET status='partial',delivery_completed_at=clock_timestamp()
   WHERE campaign.organization_id=p_organization_id
     AND campaign.status='sending'
     AND NOT EXISTS (
       SELECT 1 FROM eogp.event_notification_delivery_attempts attempt
        WHERE attempt.organization_id=campaign.organization_id
          AND attempt.campaign_id=campaign.id
          AND attempt.status IN ('queued','sending')
     );

  SELECT attempt.id AS attempt_id,attempt.organization_id,attempt.campaign_id,
         attempt.recipient_id,campaign.event_id,campaign.template_revision_id,
         campaign.delivery_config_revision_id
    INTO v_attempt
    FROM eogp.event_notification_delivery_attempts attempt
    JOIN eogp.event_notification_campaigns campaign
      ON campaign.organization_id=attempt.organization_id AND campaign.id=attempt.campaign_id
    JOIN eogp.event_notification_recipients recipient
      ON recipient.organization_id=attempt.organization_id AND recipient.campaign_id=attempt.campaign_id
     AND recipient.id=attempt.recipient_id
    WHERE attempt.organization_id=p_organization_id
      AND attempt.status='queued' AND attempt.next_attempt_at<=clock_timestamp()
      AND campaign.status IN ('queued','sending')
      AND recipient.channel='email'
    ORDER BY attempt.next_attempt_at,attempt.id
    FOR UPDATE OF attempt SKIP LOCKED
    LIMIT 1;

  IF NOT FOUND THEN RETURN; END IF;

  UPDATE eogp.event_notification_delivery_attempts
     SET status='sending',attempted_at=clock_timestamp(),
         lease_expires_at=clock_timestamp()+interval '5 minutes'
   WHERE organization_id=p_organization_id AND id=v_attempt.attempt_id;

  UPDATE eogp.event_notification_campaigns
     SET status='sending',delivery_started_at=coalesce(delivery_started_at,clock_timestamp())
   WHERE organization_id=p_organization_id AND id=v_attempt.campaign_id
     AND status='queued';

  UPDATE eogp.email_delivery_tenant_queue queue
     SET available_at=coalesce((
       SELECT min(CASE WHEN attempt.status='queued' THEN attempt.next_attempt_at
                       ELSE attempt.lease_expires_at END)
         FROM eogp.event_notification_delivery_attempts attempt
         JOIN eogp.event_notification_campaigns campaign
           ON campaign.organization_id=attempt.organization_id AND campaign.id=attempt.campaign_id
        WHERE attempt.organization_id=p_organization_id
          AND campaign.status IN ('queued','sending')
          AND attempt.status IN ('queued','sending')
     ),clock_timestamp()+interval '5 minutes')
   WHERE queue.organization_id=p_organization_id;

  RETURN QUERY
  SELECT v_attempt.attempt_id,campaign.id,recipient.id,
         recipient.destination_ciphertext,config.credentials_ciphertext,
         config.settings,config.settings->>'senderEmail',
         config.settings->>'senderName',config.settings->>'replyTo',
         template.subject_template,template.body_template,event.title,event.event_code,event.status,
         decision.decision_kind,campaign.purpose,
         schedule.starts_at,schedule.ends_at,schedule.timezone_name
    FROM eogp.event_notification_campaigns campaign
    JOIN eogp.event_notification_recipients recipient
      ON recipient.organization_id=campaign.organization_id AND recipient.campaign_id=campaign.id
     AND recipient.id=v_attempt.recipient_id
    JOIN eogp.organization_delivery_config_revisions config
      ON config.organization_id=campaign.organization_id
     AND config.id=campaign.delivery_config_revision_id
    JOIN eogp.notification_template_revisions template
      ON template.organization_id=campaign.organization_id AND template.id=campaign.template_revision_id
    JOIN eogp.events event
      ON event.organization_id=campaign.organization_id AND event.id=campaign.event_id
    LEFT JOIN eogp.event_decisions decision
      ON decision.organization_id=campaign.organization_id AND decision.event_id=campaign.event_id
     AND decision.id=campaign.event_decision_id
    LEFT JOIN eogp.event_schedule_revisions schedule
      ON schedule.organization_id=decision.organization_id
     AND schedule.event_id=decision.event_id
     AND schedule.id=decision.replacement_schedule_revision_id
   WHERE campaign.organization_id=p_organization_id AND campaign.id=v_attempt.campaign_id;
END;
$function$;

CREATE FUNCTION eogp.complete_email_delivery_attempt(
  p_organization_id uuid,
  p_attempt_id uuid,
  p_outcome text,
  p_failure_code text DEFAULT NULL,
  p_provider_reference text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_attempt eogp.event_notification_delivery_attempts%ROWTYPE;
  v_campaign_id uuid;
  v_retry boolean := false;
  v_pending integer;
  v_sent integer;
  v_failed integer;
  v_uncertain integer;
  v_final_status text;
  v_next_available timestamptz;
BEGIN
  IF session_user<>'eventor_worker'
     OR eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'delivery completion requires worker role and matching tenant context'
      USING ERRCODE='42501';
  END IF;
  IF p_outcome NOT IN ('sent','failed','uncertain') THEN
    RAISE EXCEPTION 'unsupported delivery outcome' USING ERRCODE='22023';
  END IF;
  IF p_outcome='failed' AND (p_failure_code IS NULL OR p_failure_code NOT IN (
    'SMTP_CONNECTION','SMTP_TIMEOUT','SMTP_4XX','SMTP_5XX','SMTP_TLS',
    'SMTP_TEMPLATE_INVALID','CONTACT_CIPHERTEXT_INVALID',
    'DELIVERY_CREDENTIALS_INVALID','SMTP_UNKNOWN'
  )) THEN
    RAISE EXCEPTION 'unsupported SMTP failure classification' USING ERRCODE='22023';
  END IF;

  SELECT * INTO v_attempt FROM eogp.event_notification_delivery_attempts
   WHERE organization_id=p_organization_id AND id=p_attempt_id FOR UPDATE;
  IF NOT FOUND OR v_attempt.status<>'sending' THEN
    RAISE EXCEPTION 'delivery attempt is not actively claimed' USING ERRCODE='55000';
  END IF;
  v_campaign_id:=v_attempt.campaign_id;

  UPDATE eogp.event_notification_delivery_attempts
     SET status=p_outcome,
         provider_name='smtp',
         provider_message_reference=left(p_provider_reference,500),
         failure_code=CASE WHEN p_outcome='sent' THEN NULL ELSE coalesce(p_failure_code,'SMTP_UNKNOWN') END,
         lease_expires_at=NULL
   WHERE organization_id=p_organization_id AND id=p_attempt_id;

  v_retry := p_outcome='failed'
    AND p_failure_code IN ('SMTP_CONNECTION','SMTP_TIMEOUT','SMTP_4XX')
    AND v_attempt.attempt_number<5;

  IF v_retry THEN
    INSERT INTO eogp.event_notification_delivery_attempts(
      organization_id,campaign_id,recipient_id,attempt_number,status,next_attempt_at
    ) VALUES (
      p_organization_id,v_attempt.campaign_id,v_attempt.recipient_id,
      v_attempt.attempt_number+1,'queued',
      clock_timestamp()+make_interval(secs=>least(3600,60*(2^least(v_attempt.attempt_number,5))::integer))
    );
  END IF;

  SELECT count(*) FILTER (WHERE latest.status IN ('queued','sending')),
         count(*) FILTER (WHERE latest.status IN ('sent','delivered')),
         count(*) FILTER (WHERE latest.status IN ('failed','bounced')),
         count(*) FILTER (WHERE latest.status='uncertain')
    INTO v_pending,v_sent,v_failed,v_uncertain
    FROM (
      SELECT DISTINCT ON (attempt.recipient_id) attempt.status
        FROM eogp.event_notification_delivery_attempts attempt
       WHERE attempt.organization_id=p_organization_id AND attempt.campaign_id=v_campaign_id
       ORDER BY attempt.recipient_id,attempt.attempt_number DESC
    ) latest;

  SELECT min(CASE WHEN status='queued' THEN next_attempt_at ELSE lease_expires_at END)
    INTO v_next_available
    FROM eogp.event_notification_delivery_attempts
   WHERE organization_id=p_organization_id AND campaign_id=v_campaign_id
     AND status IN ('queued','sending');

  IF v_pending=0 THEN
    v_final_status:=CASE
      WHEN v_failed=0 AND v_uncertain=0 THEN 'completed'
      WHEN v_sent>0 THEN 'partial'
      WHEN v_uncertain>0 THEN 'partial'
      ELSE 'failed'
    END;
    UPDATE eogp.event_notification_campaigns
       SET status=v_final_status,delivery_completed_at=clock_timestamp()
     WHERE organization_id=p_organization_id AND id=v_campaign_id
       AND status IN ('queued','sending');
  END IF;

  IF v_next_available IS NULL THEN
    DELETE FROM eogp.email_delivery_tenant_queue
     WHERE organization_id=p_organization_id;
  ELSE
    INSERT INTO eogp.email_delivery_tenant_queue(organization_id,available_at)
    VALUES (p_organization_id,v_next_available)
    ON CONFLICT (organization_id) DO UPDATE
      SET available_at=EXCLUDED.available_at;
  END IF;

  RETURN jsonb_build_object(
    'attemptId',p_attempt_id,'outcome',p_outcome,'retryScheduled',v_retry,
    'campaignStatus',coalesce(v_final_status,'sending')
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.begin_organization_email_delivery_test(uuid,uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.complete_organization_email_delivery_test(uuid,uuid,uuid,boolean,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.queue_event_notification_campaign(uuid,uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.discover_pending_email_delivery_tenants() FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.claim_next_email_delivery(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.complete_email_delivery_attempt(uuid,uuid,text,text,text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION eogp.begin_organization_email_delivery_test(uuid,uuid,text,text),
  eogp.complete_organization_email_delivery_test(uuid,uuid,uuid,boolean,text),
  eogp.queue_event_notification_campaign(uuid,uuid,uuid)
TO eventor_runtime;
GRANT EXECUTE ON FUNCTION eogp.discover_pending_email_delivery_tenants(),
  eogp.claim_next_email_delivery(uuid),
  eogp.complete_email_delivery_attempt(uuid,uuid,text,text,text)
TO eventor_worker;
