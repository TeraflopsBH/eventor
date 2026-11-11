\set ON_ERROR_STOP on
BEGIN;
SET LOCAL app.organization_id='22222222-2222-4222-8222-222222222222';

DO $resend$
DECLARE
  v_endpoint_id uuid := '95400000-0000-4000-8000-000000000001';
  v_campaign_id uuid;
  v_attempt_id uuid;
  v_message_reference text;
  v_deliveries jsonb;
  v_prepared jsonb;
  v_activated jsonb;
  v_config jsonb;
  v_resolved jsonb;
  v_recorded jsonb;
  v_duplicate jsonb;
  v_conflict_rejected boolean := false;
  v_terminal_rejected boolean := false;
BEGIN
  IF session_user<>'eventor_runtime' THEN
    RAISE EXCEPTION 'Resend webhook smoke test must run as eventor_runtime';
  END IF;

  v_prepared:=eogp.prepare_organization_resend_webhook_endpoint(
    '22222222-2222-4222-8222-222222222222',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    v_endpoint_id
  );
  IF v_prepared->>'endpointId'<>v_endpoint_id::text
     OR (v_prepared->>'enabled')::boolean THEN
    RAISE EXCEPTION 'Resend callback endpoint was not prepared disabled: %',v_prepared;
  END IF;

  v_activated:=eogp.activate_organization_resend_webhook_endpoint(
    '22222222-2222-4222-8222-222222222222',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    v_endpoint_id,
    decode('45444331' || repeat('00',29),'hex')
  );
  IF v_activated->>'endpointId'<>v_endpoint_id::text
     OR NOT (v_activated->>'enabled')::boolean THEN
    RAISE EXCEPTION 'Resend callback endpoint was not activated: %',v_activated;
  END IF;

  v_config:=eogp.get_organization_resend_webhook_configuration(
    '22222222-2222-4222-8222-222222222222',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
  );
  IF v_config->>'endpointId'<>v_endpoint_id::text
     OR NOT (v_config->>'configured')::boolean
     OR v_config ? 'signingSecret' THEN
    RAISE EXCEPTION 'Resend configuration projection is unsafe or incomplete: %',v_config;
  END IF;

  IF has_table_privilege(current_user,'eogp.organization_resend_webhook_endpoints','SELECT')
     OR has_table_privilege(current_user,'eogp.resend_webhook_endpoint_routes','SELECT') THEN
    RAISE EXCEPTION 'runtime must not directly read Resend endpoint or routing tables';
  END IF;
  -- Exercise the public lookup with no pre-established tenant context.
  PERFORM set_config('app.organization_id','',true);
  IF eogp.current_organization_id() IS NOT NULL THEN
    RAISE EXCEPTION 'test did not clear the prior tenant context';
  END IF;
  v_resolved:=eogp.resolve_organization_resend_webhook_endpoint(v_endpoint_id);
  IF eogp.current_organization_id() IS DISTINCT FROM '22222222-2222-4222-8222-222222222222'::uuid
     OR v_resolved->>'organizationId'<>'22222222-2222-4222-8222-222222222222'
     OR v_resolved->>'signingSecretCiphertextBase64' IS NULL THEN
    RAISE EXCEPTION 'public endpoint resolution did not return tenant-bound encrypted secret';
  END IF;

  -- Resolve one ambiguous SMTP submission using the stable Message-ID
  -- that was committed before SMTP DATA was submitted. The SMTP completion
  -- event is uncertain and therefore has no Message-ID of its own.
  SELECT id INTO v_campaign_id
    FROM eogp.event_notification_campaigns
   WHERE organization_id='22222222-2222-4222-8222-222222222222'
     AND event_decision_id='94900000-0000-4000-8000-000000000001';
  v_deliveries:=eogp.list_event_notification_campaign_deliveries(
    '22222222-2222-4222-8222-222222222222',
    v_campaign_id,
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    'uncertain',100,0
  );
  SELECT (item->>'attemptId')::uuid INTO v_attempt_id
    FROM jsonb_array_elements(v_deliveries->'items') item
   LIMIT 1;
  IF v_attempt_id IS NULL OR (v_deliveries->'page'->>'total')::integer<2 THEN
    RAISE EXCEPTION 'two uncertain Resend attempts were not prepared for callback correlation: %',v_deliveries;
  END IF;
  v_message_reference:='<eventor-' || replace(v_attempt_id::text,'-','')
    || '@delivery.eventor.invalid>';

  v_recorded:=eogp.record_verified_resend_delivery_webhook(
    '22222222-2222-4222-8222-222222222222',
    v_endpoint_id,
    'msg_ci_resend_delivery_0001',
    v_message_reference,
    'delivered',
    repeat('d',64)
  );
  IF NOT (v_recorded->>'accepted')::boolean
     OR (v_recorded->>'duplicate')::boolean
     OR v_recorded->>'status'<>'delivered' THEN
    RAISE EXCEPTION 'Resend delivery event was not accepted: %',v_recorded;
  END IF;

  v_duplicate:=eogp.record_verified_resend_delivery_webhook(
    '22222222-2222-4222-8222-222222222222',
    v_endpoint_id,
    'msg_ci_resend_delivery_0001',
    v_message_reference,
    'delivered',
    repeat('d',64)
  );
  IF NOT (v_duplicate->>'duplicate')::boolean THEN
    RAISE EXCEPTION 'Resend provider event replay was not idempotent: %',v_duplicate;
  END IF;

  BEGIN
    PERFORM eogp.record_verified_resend_delivery_webhook(
      '22222222-2222-4222-8222-222222222222',
      v_endpoint_id,
      'msg_ci_resend_delivery_0001',
      v_message_reference,
      'bounced',
      repeat('e',64)
    );
  EXCEPTION WHEN unique_violation THEN
    v_conflict_rejected:=true;
  END;
  IF NOT v_conflict_rejected THEN
    RAISE EXCEPTION 'replayed Resend event ID with different content was not rejected';
  END IF;

  BEGIN
    PERFORM eogp.record_verified_resend_delivery_webhook(
      '22222222-2222-4222-8222-222222222222',
      v_endpoint_id,
      'msg_ci_resend_delivery_0002',
      v_message_reference,
      'bounced',
      repeat('f',64)
    );
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_terminal_rejected:=true;
  END;
  IF NOT v_terminal_rejected THEN
    RAISE EXCEPTION 'conflicting delivered-to-bounced terminal event was not rejected';
  END IF;

  v_deliveries:=eogp.list_event_notification_campaign_deliveries(
    '22222222-2222-4222-8222-222222222222',
    v_campaign_id,
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    'uncertain',100,0
  );
  IF (v_deliveries->'page'->>'total')::integer<>1 THEN
    RAISE EXCEPTION 'Resend callback did not resolve exactly one uncertain SMTP attempt: %',v_deliveries;
  END IF;
END;
$resend$;
COMMIT;

\echo 'Resend webhook endpoint, encrypted secret, Message-ID correlation and idempotency smoke tests passed.'
