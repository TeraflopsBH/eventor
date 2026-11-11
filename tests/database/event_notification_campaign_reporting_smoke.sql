\set ON_ERROR_STOP on
BEGIN;
SET LOCAL app.organization_id='22222222-2222-4222-8222-222222222222';

DO $reporting$
DECLARE
  v_campaign_id uuid;
  v_list jsonb;
  v_progress jsonb;
  v_deliveries jsonb;
  v_item jsonb;
  v_status text;
BEGIN
  SELECT id INTO v_campaign_id
    FROM eogp.event_notification_campaigns
   WHERE organization_id='22222222-2222-4222-8222-222222222222'
     AND event_decision_id='94900000-0000-4000-8000-000000000001';

  v_list:=eogp.list_event_notification_campaigns(
    '22222222-2222-4222-8222-222222222222',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',NULL,25,0
  );
  IF jsonb_array_length(v_list->'items')<1
     OR (v_list->'page'->>'total')::integer<1 THEN
    RAISE EXCEPTION 'authorized campaign list did not return the fixture campaign: %',v_list;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_list->'items') item
     WHERE item->>'campaignId'=v_campaign_id::text
  ) THEN
    RAISE EXCEPTION 'campaign list omitted the accessible fixture campaign';
  END IF;

  v_progress:=eogp.get_event_notification_campaign_progress(
    '22222222-2222-4222-8222-222222222222',
    v_campaign_id,
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
  );
  IF v_progress->>'campaignId'<>v_campaign_id::text
     OR NOT (v_progress ? 'deliveryCounts')
     OR NOT (v_progress ? 'attemptCount') THEN
    RAISE EXCEPTION 'campaign progress projection is incomplete: %',v_progress;
  END IF;

  v_deliveries:=eogp.list_event_notification_campaign_deliveries(
    '22222222-2222-4222-8222-222222222222',
    v_campaign_id,
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',NULL,100,0
  );
  IF jsonb_typeof(v_deliveries->'items')<>'array'
     OR (v_deliveries->'page'->>'total')::integer<1 THEN
    RAISE EXCEPTION 'delivery report did not return fixture attempts: %',v_deliveries;
  END IF;
  v_item:=v_deliveries->'items'->0;
  IF v_item ? 'destination'
     OR v_item ? 'destinationCiphertext'
     OR v_item ? 'email'
     OR v_item ? 'phone'
     OR v_item ? 'providerMessageReference' THEN
    RAISE EXCEPTION 'delivery report exposes recipient contact or provider message details: %',v_item;
  END IF;
  IF NOT (v_item ? 'recipientReference')
     OR NOT (v_item ? 'attemptNumber')
     OR NOT (v_item ? 'status') THEN
    RAISE EXCEPTION 'delivery report omitted operational attempt fields: %',v_item;
  END IF;

  BEGIN
    PERFORM eogp.list_event_notification_campaigns(
      '11111111-1111-4111-8111-111111111111',
      'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',NULL,25,0
    );
    RAISE EXCEPTION 'cross-tenant campaign list unexpectedly succeeded';
  EXCEPTION WHEN insufficient_privilege THEN NULL;
  END;
END;
$reporting$;
COMMIT;

\echo 'Campaign listing, progress and privacy-safe delivery reporting smoke tests passed.'
