\set ON_ERROR_STOP on
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
COMMIT;
