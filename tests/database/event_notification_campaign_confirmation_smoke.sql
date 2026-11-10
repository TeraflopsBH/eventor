\set ON_ERROR_STOP on
BEGIN;
SET LOCAL app.organization_id = '22222222-2222-4222-8222-222222222222';

DO $review$
DECLARE
  v_review jsonb;
BEGIN
  v_review := eogp.get_event_notification_campaign_review(
    '22222222-2222-4222-8222-222222222222',
    (SELECT id FROM eogp.event_notification_campaigns
      WHERE organization_id = '22222222-2222-4222-8222-222222222222'
        AND event_decision_id = '94900000-0000-4000-8000-000000000001'),
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
  );
  IF v_review ->> 'status' <> 'previewed'
     OR (v_review ->> 'recipientCount')::integer <> 2
     OR (v_review ->> 'actualRecipientCount')::integer <> 2
     OR (v_review ->> 'exclusionCount')::integer <> 1
     OR jsonb_array_length(v_review -> 'recipients') <> 2 THEN
    RAISE EXCEPTION 'campaign review projection is incomplete or inconsistent: %', v_review;
  END IF;
  IF v_review::text LIKE '%destination_ciphertext%'
     OR v_review::text LIKE '%encrypted_value%' THEN
    RAISE EXCEPTION 'campaign review must never expose encrypted contact values';
  END IF;
END;
$review$;

DO $confirm$
DECLARE
  v_campaign_id uuid;
  v_result jsonb;
  v_count integer;
  v_second_confirmation_rejected boolean := false;
BEGIN
  SELECT id INTO v_campaign_id
    FROM eogp.event_notification_campaigns
   WHERE organization_id = '22222222-2222-4222-8222-222222222222'
     AND event_decision_id = '94900000-0000-4000-8000-000000000001';

  v_result := eogp.confirm_event_notification_campaign(
    '22222222-2222-4222-8222-222222222222',
    v_campaign_id,
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
  );

  IF v_result ->> 'status' <> 'confirmed'
     OR (v_result ->> 'deliveryQueued')::boolean IS DISTINCT FROM false
     OR (v_result ->> 'recipientCount')::integer <> 2 THEN
    RAISE EXCEPTION 'campaign confirmation returned an unexpected result: %', v_result;
  END IF;

  IF (SELECT status FROM eogp.event_notification_campaigns
       WHERE organization_id = '22222222-2222-4222-8222-222222222222'
         AND id = v_campaign_id) <> 'confirmed' THEN
    RAISE EXCEPTION 'campaign status was not confirmed';
  END IF;

  SELECT count(*) INTO v_count
    FROM eogp.audit_events
   WHERE organization_id = '22222222-2222-4222-8222-222222222222'
     AND aggregate_type = 'event_notification_campaign'
     AND aggregate_id = v_campaign_id
     AND action = 'event.notification_campaign.confirmed'
     AND actor_membership_id = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'campaign confirmation audit attribution is missing';
  END IF;

  SELECT count(*) INTO v_count
    FROM eogp.event_notification_delivery_attempts
   WHERE organization_id = '22222222-2222-4222-8222-222222222222'
     AND campaign_id = v_campaign_id;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'confirmation must not create delivery attempts';
  END IF;

  IF has_table_privilege(current_user, 'eogp.event_notification_campaigns', 'UPDATE')
     OR has_table_privilege(current_user, 'eogp.event_notification_recipients', 'INSERT')
     OR has_table_privilege(current_user, 'eogp.event_notification_exclusions', 'INSERT') THEN
    RAISE EXCEPTION 'runtime role must not directly mutate campaign or fixed audience tables';
  END IF;

  BEGIN
    PERFORM eogp.confirm_event_notification_campaign(
      '22222222-2222-4222-8222-222222222222',
      v_campaign_id,
      'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
    );
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_second_confirmation_rejected := true;
  END;
  IF NOT v_second_confirmation_rejected THEN
    RAISE EXCEPTION 'a second confirmation must fail rather than silently mutate a confirmed campaign';
  END IF;
END;
$confirm$;
COMMIT;


-- Exercise database-level guards as the trusted owner, independently of the
-- runtime role's revoked table privileges.
BEGIN;
SET LOCAL ROLE eventor_owner;
SET LOCAL app.organization_id = '22222222-2222-4222-8222-222222222222';
DO $snapshot_guard$
DECLARE
  v_rejected boolean;
  v_campaign_id uuid;
BEGIN
  SELECT id INTO v_campaign_id
    FROM eogp.event_notification_campaigns
   WHERE organization_id = '22222222-2222-4222-8222-222222222222'
     AND event_decision_id = '94900000-0000-4000-8000-000000000001';

  v_rejected := false;
  BEGIN
    INSERT INTO eogp.event_notification_recipients (
      id, organization_id, event_id, campaign_id, participation_id,
      invitation_id, qualification_reason, channel, destination_ciphertext,
      destination_hash
    ) VALUES (
      '95100000-0000-4000-8000-000000000001',
      '22222222-2222-4222-8222-222222222222',
      '94000000-0000-4000-8000-000000000001',
      v_campaign_id,
      '94300000-0000-4000-8000-000000000001',
      '94500000-0000-4000-8000-000000000001',
      'late_insert_regression','email',decode('aa','hex'),repeat('a',64)
    );
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_rejected := true;
  END;
  IF NOT v_rejected THEN
    RAISE EXCEPTION 'recipient was appended after campaign confirmation';
  END IF;

  v_rejected := false;
  BEGIN
    INSERT INTO eogp.event_notification_exclusions (
      id, organization_id, event_id, campaign_id, participation_id,
      exclusion_reason, actor_organization_id, actor_membership_id
    ) VALUES (
      '95200000-0000-4000-8000-000000000001',
      '22222222-2222-4222-8222-222222222222',
      '94000000-0000-4000-8000-000000000001',
      v_campaign_id,
      '94300000-0000-4000-8000-000000000002',
      'late_exclusion_regression',
      '22222222-2222-4222-8222-222222222222',
      'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
    );
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_rejected := true;
  END;
  IF NOT v_rejected THEN
    RAISE EXCEPTION 'exclusion was appended after campaign confirmation';
  END IF;
END;
$snapshot_guard$;
ROLLBACK;
