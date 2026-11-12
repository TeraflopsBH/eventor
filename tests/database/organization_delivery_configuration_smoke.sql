\set ON_ERROR_STOP on
BEGIN;
SET LOCAL app.organization_id = '22222222-2222-4222-8222-222222222222';

DO $delivery$
DECLARE
  v_first jsonb;
  v_second jsonb;
  v_third jsonb;
  v_invalid_rejected boolean := false;
  v_count integer;
  v_test jsonb;
  v_enabled jsonb;
  v_queue jsonb;
  v_campaign_id uuid;
  v_queued integer;
  v_locale_settings jsonb;
  v_locale_update jsonb;
  v_original_locale text;
  v_target_locale text;
BEGIN
  v_locale_settings := eogp.get_organization_locale_settings(
    '22222222-2222-4222-8222-222222222222',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
  );
  IF (v_locale_settings ->> 'canManage')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'organization locale projection did not honor organization.manage permission: %',v_locale_settings;
  END IF;
  v_original_locale := v_locale_settings ->> 'defaultLocale';
  v_target_locale := CASE WHEN v_original_locale='en' THEN 'bs-BA' ELSE 'en' END;
  v_locale_update := eogp.set_organization_default_locale(
    '22222222-2222-4222-8222-222222222222',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    v_target_locale
  );
  IF v_locale_update ->> 'defaultLocale' IS DISTINCT FROM v_target_locale THEN
    RAISE EXCEPTION 'organization default locale update failed: %',v_locale_update;
  END IF;
  PERFORM eogp.set_organization_default_locale(
    '22222222-2222-4222-8222-222222222222',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    v_original_locale
  );
  BEGIN
    PERFORM eogp.set_organization_default_locale(
      '22222222-2222-4222-8222-222222222222',
      'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
      'fr'
    );
    RAISE EXCEPTION 'unsupported organization locale should have been rejected';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;

  IF has_table_privilege(current_user, 'eogp.organization_delivery_config_revisions', 'SELECT')
     OR has_table_privilege(current_user, 'eogp.organization_delivery_config_revisions', 'INSERT')
     OR has_table_privilege(current_user, 'eogp.organization_delivery_config_heads', 'SELECT')
     OR has_table_privilege(current_user, 'eogp.organization_delivery_config_heads', 'UPDATE') THEN
    RAISE EXCEPTION 'runtime must access delivery configuration only through restricted functions';
  END IF;

  v_first := eogp.set_organization_email_delivery_config(
    '22222222-2222-4222-8222-222222222222',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    jsonb_build_object(
      'host','smtp.example.test',
      'port',587,
      'transportSecurity','starttls',
      'authMode','password',
      'senderEmail','events@example.test',
      'senderName','Eventor CI',
      'replyTo','reply@example.test',
      'connectionTimeoutMs',12000
    ),
    decode('45444331' || repeat('00',29),'hex'),
    true,
    false
  );

  IF v_first ->> 'channel' <> 'email'
     OR v_first ->> 'provider' <> 'smtp'
     OR (v_first ->> 'revision')::integer <> 1
     OR (v_first ->> 'credentialsConfigured')::boolean IS DISTINCT FROM true
     OR v_first::text LIKE '%45444331%' THEN
    RAISE EXCEPTION 'SMTP config creation returned an invalid or sensitive projection: %', v_first;
  END IF;

  v_second := eogp.set_organization_email_delivery_config(
    '22222222-2222-4222-8222-222222222222',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    jsonb_build_object(
      'host','smtp.example.test',
      'port',587,
      'transportSecurity','starttls',
      'authMode','password',
      'senderEmail','events@example.test',
      'senderName','Eventor CI updated',
      'replyTo','reply@example.test',
      'connectionTimeoutMs',12000
    ),
    NULL,
    false,
    false
  );

  IF (v_second ->> 'revision')::integer <> 2
     OR (v_second ->> 'credentialsConfigured')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'SMTP credential preservation on settings revision failed: %', v_second;
  END IF;

  v_third := eogp.set_organization_email_delivery_config(
    '22222222-2222-4222-8222-222222222222',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    jsonb_build_object(
      'host','smtp.resend.com',
      'port',587,
      'transportSecurity','starttls',
      'authMode','password',
      'senderEmail','events@example.test',
      'senderName','Eventor CI',
      'replyTo','',
      'connectionTimeoutMs',15000
    ),
    decode('45444331' || repeat('00',29),'hex'),
    true,
    false
  );

  IF (v_third ->> 'revision')::integer <> 3
     OR (v_third ->> 'credentialsConfigured')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'SMTP credential clearing failed: %', v_third;
  END IF;

  BEGIN
    PERFORM eogp.set_organization_email_delivery_config(
      '22222222-2222-4222-8222-222222222222',
      'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
      jsonb_build_object(
        'host','smtp.example.test',
        'port',25,
        'transportSecurity','none',
        'authMode','none',
        'senderEmail','events@example.test'
      ),
      NULL,false,false
    );
  EXCEPTION WHEN SQLSTATE '22023' THEN
    v_invalid_rejected := true;
  END;
  IF NOT v_invalid_rejected THEN
    RAISE EXCEPTION 'insecure SMTP transport configuration must be rejected';
  END IF;

  SELECT count(*) INTO v_count
    FROM eogp.audit_events
   WHERE organization_id = '22222222-2222-4222-8222-222222222222'
     AND aggregate_type = 'organization_delivery_config'
     AND action = 'organization.delivery.email_configured'
     AND actor_membership_id = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'expected one audit event per delivery configuration revision; got %', v_count;
  END IF;

  IF eogp.get_organization_email_delivery_config(
    '22222222-2222-4222-8222-222222222222',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
  ) ->> 'credentialsConfigured' <> 'true' THEN
    RAISE EXCEPTION 'delivery configuration projection did not return the current head';
  END IF;

    v_test := eogp.begin_organization_email_delivery_test(
      '22222222-2222-4222-8222-222222222222',
      'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
      repeat('1',64),
      repeat('2',64)
    );
    IF (v_test ->> 'created')::boolean IS DISTINCT FROM true
       OR v_test ->> 'status' <> 'pending'
       OR v_test ->> 'credentialsCiphertextBase64' IS NOT NULL THEN
      RAISE EXCEPTION 'SMTP test request did not create a safe pending request: %',v_test;
    END IF;

    v_enabled := eogp.complete_organization_email_delivery_test(
      '22222222-2222-4222-8222-222222222222',
      'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
      (v_test ->> 'requestId')::uuid,
      true,
      NULL
    );
    IF v_enabled ->> 'status' <> 'succeeded'
       OR (v_enabled ->> 'deliveryEnabled')::boolean IS DISTINCT FROM true THEN
      RAISE EXCEPTION 'successful SMTP test did not enable current configuration: %',v_enabled;
    END IF;

    SELECT id INTO v_campaign_id
      FROM eogp.event_notification_campaigns
     WHERE organization_id='22222222-2222-4222-8222-222222222222'
       AND event_decision_id='94900000-0000-4000-8000-000000000001';
    v_queue := eogp.queue_event_notification_campaign(
      '22222222-2222-4222-8222-222222222222',
      v_campaign_id,
      'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
    );
    IF v_queue ->> 'status' <> 'queued'
       OR (v_queue ->> 'emailRecipientCount')::integer <> 2 THEN
      RAISE EXCEPTION 'explicit campaign queue did not queue the expected email recipients: %',v_queue;
    END IF;

    SELECT count(*) INTO v_queued
      FROM eogp.event_notification_delivery_attempts
     WHERE organization_id='22222222-2222-4222-8222-222222222222'
       AND campaign_id=v_campaign_id AND status='queued';
    IF v_queued <> 2 THEN
      RAISE EXCEPTION 'expected two queued SMTP attempts, got %',v_queued;
    END IF;

END;
$delivery$;
COMMIT;

\echo 'Organization delivery configuration smoke tests passed.'
