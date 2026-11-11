-- Tenant-owned, versioned delivery configuration.
-- This migration stores SMTP credentials only as an application-encrypted EDC1
-- envelope. No provider integration or message delivery is enabled here.

INSERT INTO eogp.permissions (code, description, scope_kind, is_sensitive)
VALUES (
  'organization.delivery.manage',
  'Manage organization email and notification delivery configuration',
  'organization',
  true
)
ON CONFLICT (code) DO NOTHING;

CREATE TABLE eogp.organization_delivery_config_revisions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
  channel text NOT NULL CHECK (channel IN ('email','sms')),
  revision integer NOT NULL CHECK (revision > 0),
  provider text NOT NULL,
  settings jsonb NOT NULL CHECK (jsonb_typeof(settings) = 'object'),
  credentials_ciphertext bytea,
  created_by_membership_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, channel, revision),
  FOREIGN KEY (organization_id, created_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id),
  CHECK (credentials_ciphertext IS NULL OR
    (octet_length(credentials_ciphertext) >= 33
     AND substring(credentials_ciphertext FROM 1 FOR 4) = convert_to('EDC1','UTF8')))
);

CREATE TABLE eogp.organization_delivery_config_heads (
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
  channel text NOT NULL CHECK (channel IN ('email','sms')),
  revision_id uuid NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (organization_id, channel),
  FOREIGN KEY (organization_id, revision_id)
    REFERENCES eogp.organization_delivery_config_revisions(organization_id, id)
);

ALTER TABLE eogp.organization_delivery_config_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.organization_delivery_config_revisions FORCE ROW LEVEL SECURITY;
CREATE POLICY organization_delivery_revisions_tenant
  ON eogp.organization_delivery_config_revisions
  USING (organization_id = eogp.current_organization_id())
  WITH CHECK (organization_id = eogp.current_organization_id());

ALTER TABLE eogp.organization_delivery_config_heads ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.organization_delivery_config_heads FORCE ROW LEVEL SECURITY;
CREATE POLICY organization_delivery_heads_tenant
  ON eogp.organization_delivery_config_heads
  USING (organization_id = eogp.current_organization_id())
  WITH CHECK (organization_id = eogp.current_organization_id());

REVOKE ALL ON
  eogp.organization_delivery_config_revisions,
  eogp.organization_delivery_config_heads
FROM PUBLIC, eventor_runtime, eventor_worker;
GRANT SELECT ON
  eogp.organization_delivery_config_revisions,
  eogp.organization_delivery_config_heads
TO eventor_runtime;

CREATE FUNCTION eogp.get_organization_email_delivery_config(
  p_organization_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE = '42501';
  END IF;

  PERFORM eogp.assert_event_command_permission(
    p_organization_id, NULL, p_actor_membership_id, 'organization.delivery.manage'
  );

  SELECT jsonb_build_object(
    'channel', revision.channel,
    'provider', revision.provider,
    'revision', revision.revision,
    'settings', revision.settings,
    'credentialsConfigured', revision.credentials_ciphertext IS NOT NULL,
    'updatedAt', revision.created_at
  )
  INTO v_result
  FROM eogp.organization_delivery_config_heads AS head
  JOIN eogp.organization_delivery_config_revisions AS revision
    ON revision.organization_id = head.organization_id
   AND revision.id = head.revision_id
  WHERE head.organization_id = p_organization_id
    AND head.channel = 'email';

  RETURN coalesce(v_result, jsonb_build_object(
    'channel','email','configured',false,'credentialsConfigured',false
  ));
END;
$function$;

CREATE FUNCTION eogp.set_organization_email_delivery_config(
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
  v_membership_status text;
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
  v_provider text := 'smtp';
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
     OR v_sender !~ '^[^[:space:]<>@]+@[^[:space:]<>@]+\.[^[:space:]<>@]+$'
     OR (v_reply_to <> '' AND v_reply_to !~ '^[^[:space:]<>@]+@[^[:space:]<>@]+\.[^[:space:]<>@]+$')
     OR coalesce((p_settings ->> 'connectionTimeoutMs')::integer,15000) NOT BETWEEN 1000 AND 60000
     OR length(coalesce(p_settings ->> 'senderName','')) > 200 THEN
    RAISE EXCEPTION 'SMTP settings failed validation' USING ERRCODE = '22023';
  END IF;

  IF p_replace_credentials AND p_clear_credentials THEN
    RAISE EXCEPTION 'credentials cannot be replaced and cleared together' USING ERRCODE = '22023';
  END IF;
  IF p_replace_credentials AND (
    p_credentials_ciphertext IS NULL
    OR octet_length(p_credentials_ciphertext) < 33
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

  IF p_clear_credentials THEN
    v_next_ciphertext := NULL;
  ELSIF p_replace_credentials THEN
    v_next_ciphertext := p_credentials_ciphertext;
  ELSE
    v_next_ciphertext := v_previous_ciphertext;
  END IF;

  IF v_auth_mode = 'password' AND v_next_ciphertext IS NULL THEN
    RAISE EXCEPTION 'SMTP password authentication requires configured credentials' USING ERRCODE = '22023';
  END IF;
  IF v_auth_mode = 'none' AND v_next_ciphertext IS NOT NULL THEN
    RAISE EXCEPTION 'SMTP credentials must be cleared when authentication is disabled' USING ERRCODE = '22023';
  END IF;

  SELECT coalesce(max(revision),0) + 1
    INTO v_revision
    FROM eogp.organization_delivery_config_revisions
   WHERE organization_id = p_organization_id
     AND channel = 'email';

  v_settings := jsonb_build_object(
    'host',v_host,
    'port',v_port,
    'transportSecurity',v_security,
    'authMode',v_auth_mode,
    'senderEmail',v_sender,
    'senderName',coalesce(p_settings ->> 'senderName',''),
    'replyTo',nullif(v_reply_to,''),
    'connectionTimeoutMs',coalesce((p_settings ->> 'connectionTimeoutMs')::integer,15000)
  );

  INSERT INTO eogp.organization_delivery_config_revisions (
    id, organization_id, channel, revision, provider, settings,
    credentials_ciphertext, created_by_membership_id
  ) VALUES (
    v_revision_id, p_organization_id, 'email', v_revision, v_provider,
    v_settings, v_next_ciphertext, p_actor_membership_id
  );

  INSERT INTO eogp.organization_delivery_config_heads (
    organization_id, channel, revision_id
  ) VALUES (p_organization_id,'email',v_revision_id)
  ON CONFLICT (organization_id,channel) DO UPDATE
    SET revision_id = EXCLUDED.revision_id,
        updated_at = clock_timestamp();

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    p_organization_id, p_organization_id, p_actor_membership_id, 'membership',
    'organization.delivery.email_configured',
    'organization_delivery_config', v_revision_id,
    jsonb_build_object(
      'channel','email','provider',v_provider,'revision',v_revision,
      'host',v_host,'port',v_port,'transportSecurity',v_security,
      'authMode',v_auth_mode,'credentialsConfigured',v_next_ciphertext IS NOT NULL
    )
  );

  RETURN jsonb_build_object(
    'channel','email','provider',v_provider,'revision',v_revision,
    'settings',v_settings,'credentialsConfigured',v_next_ciphertext IS NOT NULL,
    'updatedAt',clock_timestamp()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION eogp.reject_delivery_config_revision_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION 'delivery configuration revisions are immutable'
    USING ERRCODE = '55000';
END;
$function$;

CREATE TRIGGER organization_delivery_config_revision_immutable
  BEFORE UPDATE OR DELETE ON eogp.organization_delivery_config_revisions
  FOR EACH ROW EXECUTE FUNCTION eogp.reject_delivery_config_revision_mutation();

REVOKE ALL ON FUNCTION eogp.get_organization_email_delivery_config(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.set_organization_email_delivery_config(uuid,uuid,jsonb,bytea,boolean,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
  eogp.get_organization_email_delivery_config(uuid,uuid),
  eogp.set_organization_email_delivery_config(uuid,uuid,jsonb,bytea,boolean,boolean)
TO eventor_runtime;
