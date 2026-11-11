-- Resend webhook endpoint management and authenticated per-attempt outcome ingestion.
-- The endpoint UUID is a routing identifier, not an authentication secret.
-- The Svix signature over the raw request body is the authentication boundary.

CREATE TABLE eogp.organization_resend_webhook_endpoints (
  id uuid PRIMARY KEY,
  organization_id uuid NOT NULL UNIQUE REFERENCES eogp.organizations(id),
  signing_secret_ciphertext bytea,
  enabled boolean NOT NULL DEFAULT false,
  created_by_membership_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (organization_id,created_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id,id),
  CHECK ((enabled) = (signing_secret_ciphertext IS NOT NULL)),
  CHECK (signing_secret_ciphertext IS NULL OR (
    octet_length(signing_secret_ciphertext)>=33
    AND substring(signing_secret_ciphertext FROM 1 FOR 4)=convert_to('EDC1','UTF8')
  ))
);
ALTER TABLE eogp.organization_resend_webhook_endpoints ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.organization_resend_webhook_endpoints FORCE ROW LEVEL SECURITY;
CREATE POLICY organization_resend_webhook_endpoints_tenant
  ON eogp.organization_resend_webhook_endpoints
  USING (organization_id=eogp.current_organization_id())
  WITH CHECK (organization_id=eogp.current_organization_id());
REVOKE ALL ON eogp.organization_resend_webhook_endpoints FROM PUBLIC,eventor_runtime,eventor_worker;

CREATE FUNCTION eogp.prepare_organization_resend_webhook_endpoint(
  p_organization_id uuid,
  p_actor_membership_id uuid,
  p_endpoint_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_settings jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_event_command_permission(
    p_organization_id,NULL,p_actor_membership_id,'organization.delivery.manage'
  );
  SELECT revision.settings INTO v_settings
    FROM eogp.organization_delivery_config_heads head
    JOIN eogp.organization_delivery_config_revisions revision
      ON revision.organization_id=head.organization_id AND revision.id=head.revision_id
   WHERE head.organization_id=p_organization_id AND head.channel='email';
  IF NOT FOUND OR v_settings->>'host'<>'smtp.resend.com'
     OR v_settings->>'authMode'<>'password' THEN
    RAISE EXCEPTION 'Resend SMTP must be the current password-authenticated email provider before preparing its webhook'
      USING ERRCODE='55000';
  END IF;

  INSERT INTO eogp.organization_resend_webhook_endpoints(
    id,organization_id,signing_secret_ciphertext,enabled,created_by_membership_id
  ) VALUES (p_endpoint_id,p_organization_id,NULL,false,p_actor_membership_id)
  ON CONFLICT (organization_id) DO UPDATE
    SET id=EXCLUDED.id,
        signing_secret_ciphertext=NULL,
        enabled=false,
        created_by_membership_id=EXCLUDED.created_by_membership_id,
        updated_at=clock_timestamp();

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'organization.delivery.resend_webhook_prepared',
    'organization_resend_webhook_endpoint',p_endpoint_id,
    jsonb_build_object('provider','resend','enabled',false)
  );

  RETURN jsonb_build_object('endpointId',p_endpoint_id,'enabled',false);
END;
$function$;

CREATE FUNCTION eogp.activate_organization_resend_webhook_endpoint(
  p_organization_id uuid,
  p_actor_membership_id uuid,
  p_endpoint_id uuid,
  p_signing_secret_ciphertext bytea
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_endpoint eogp.organization_resend_webhook_endpoints%ROWTYPE;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_event_command_permission(
    p_organization_id,NULL,p_actor_membership_id,'organization.delivery.manage'
  );
  IF p_signing_secret_ciphertext IS NULL
     OR octet_length(p_signing_secret_ciphertext)<33
     OR substring(p_signing_secret_ciphertext FROM 1 FOR 4)<>convert_to('EDC1','UTF8') THEN
    RAISE EXCEPTION 'a valid EDC1-encrypted Resend signing secret is required' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_endpoint
    FROM eogp.organization_resend_webhook_endpoints
   WHERE organization_id=p_organization_id AND id=p_endpoint_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Resend webhook endpoint was not prepared for this organization'
      USING ERRCODE='P0002';
  END IF;

  UPDATE eogp.organization_resend_webhook_endpoints
     SET signing_secret_ciphertext=p_signing_secret_ciphertext,
         enabled=true,
         updated_at=clock_timestamp()
   WHERE organization_id=p_organization_id AND id=p_endpoint_id;

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'organization.delivery.resend_webhook_activated',
    'organization_resend_webhook_endpoint',p_endpoint_id,
    jsonb_build_object('provider','resend','enabled',true,'signingSecretStored',true)
  );

  RETURN jsonb_build_object('endpointId',p_endpoint_id,'enabled',true,'updatedAt',clock_timestamp());
END;
$function$;

CREATE FUNCTION eogp.get_organization_resend_webhook_configuration(
  p_organization_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_event_command_permission(
    p_organization_id,NULL,p_actor_membership_id,'organization.delivery.manage'
  );
  SELECT jsonb_build_object(
    'endpointId',id,
    'configured',enabled,
    'updatedAt',updated_at
  ) INTO v_result
    FROM eogp.organization_resend_webhook_endpoints
   WHERE organization_id=p_organization_id;
  RETURN coalesce(v_result,jsonb_build_object('endpointId',NULL,'configured',false));
END;
$function$;

-- Public webhook routing lookup returns only an authenticated-encrypted
-- signing-secret envelope and its tenant binding. The endpoint UUID is not
-- itself an authorization credential.
CREATE FUNCTION eogp.resolve_organization_resend_webhook_endpoint(
  p_endpoint_id uuid
) RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
  SELECT jsonb_build_object(
    'organizationId',organization_id,
    'signingSecretCiphertextBase64',encode(signing_secret_ciphertext,'base64')
  )
    FROM eogp.organization_resend_webhook_endpoints
   WHERE id=p_endpoint_id AND enabled=true
$function$;

-- Called by the API only after Svix signature and timestamp verification.
-- Recipient addresses and raw payloads are not stored. The exact RFC Message-ID
-- is matched against an immutable SMTP acceptance event for a Resend-configured
-- campaign; each Eventor attempt contains one recipient.
CREATE UNIQUE INDEX event_notification_smtp_message_reference_uidx
  ON eogp.event_notification_delivery_attempt_events(organization_id,provider_message_reference)
  WHERE provider_name='smtp' AND status='sent' AND provider_message_reference IS NOT NULL;

CREATE FUNCTION eogp.record_verified_resend_delivery_webhook(
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
  v_current_status text;
  v_existing eogp.event_notification_provider_events%ROWTYPE;
  v_inserted_id uuid;
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

  SELECT attempt.id,campaign.id
    INTO v_attempt_id,v_campaign_id
    FROM eogp.event_notification_delivery_attempt_events accepted
    JOIN eogp.event_notification_delivery_attempts attempt
      ON attempt.organization_id=accepted.organization_id AND attempt.id=accepted.attempt_id
    JOIN eogp.event_notification_campaigns campaign
      ON campaign.organization_id=attempt.organization_id AND campaign.id=attempt.campaign_id
    JOIN eogp.organization_delivery_config_revisions revision
      ON revision.organization_id=campaign.organization_id
     AND revision.id=campaign.delivery_config_revision_id
   WHERE accepted.organization_id=p_organization_id
     AND accepted.provider_name='smtp'
     AND accepted.status='sent'
     AND accepted.provider_message_reference=p_provider_message_reference
     AND revision.settings->>'host'='smtp.resend.com'
   LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Resend Message-ID does not match a known accepted attempt'
      USING ERRCODE='P0002';
  END IF;

  PERFORM 1 FROM eogp.event_notification_campaigns
   WHERE organization_id=p_organization_id AND id=v_campaign_id FOR UPDATE;
  PERFORM 1 FROM eogp.event_notification_delivery_attempts
   WHERE organization_id=p_organization_id AND id=v_attempt_id FOR UPDATE;

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

  SELECT coalesce(latest.status,attempt.status) INTO v_current_status
    FROM eogp.event_notification_delivery_attempts attempt
    LEFT JOIN LATERAL (
      SELECT status FROM eogp.event_notification_delivery_attempt_events
       WHERE organization_id=p_organization_id AND attempt_id=v_attempt_id
       ORDER BY created_at DESC,id DESC LIMIT 1
    ) latest ON true
   WHERE attempt.organization_id=p_organization_id AND attempt.id=v_attempt_id;

  IF v_current_status NOT IN ('sent','delivered','bounced') THEN
    RAISE EXCEPTION 'Resend event cannot override the current operator or delivery decision'
      USING ERRCODE='55000';
  END IF;
  IF v_current_status IN ('delivered','bounced') AND v_current_status<>p_outcome THEN
    RAISE EXCEPTION 'conflicting terminal Resend delivery outcome'
      USING ERRCODE='55000';
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

  RETURN jsonb_build_object(
    'accepted',true,'duplicate',false,'attemptId',v_attempt_id,'status',p_outcome
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.prepare_organization_resend_webhook_endpoint(uuid,uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.activate_organization_resend_webhook_endpoint(uuid,uuid,uuid,bytea) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.get_organization_resend_webhook_configuration(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.resolve_organization_resend_webhook_endpoint(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.record_verified_resend_delivery_webhook(uuid,uuid,text,text,text,text) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION eogp.prepare_organization_resend_webhook_endpoint(uuid,uuid,uuid),
  eogp.activate_organization_resend_webhook_endpoint(uuid,uuid,uuid,bytea),
  eogp.get_organization_resend_webhook_configuration(uuid,uuid)
TO eventor_runtime;
GRANT EXECUTE ON FUNCTION eogp.resolve_organization_resend_webhook_endpoint(uuid),
  eogp.record_verified_resend_delivery_webhook(uuid,uuid,text,text,text,text)
TO eventor_runtime;
