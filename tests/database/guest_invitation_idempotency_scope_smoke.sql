\set ON_ERROR_STOP on
BEGIN;
SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);
SELECT set_config('app.actor_membership_id','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',true);

DO $invitation_idempotency_scope$
DECLARE
  v_result jsonb;
  v_denied boolean := false;
  v_participation_id uuid;
  v_projection jsonb;
BEGIN
  v_projection := eogp.list_guest_invitation_participations(
    '22222222-2222-4222-8222-222222222222',
    '94000000-0000-4000-8000-000000000001',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
  );
  SELECT (participant->>'participationId')::uuid INTO v_participation_id
    FROM jsonb_array_elements(v_projection) participant
   WHERE participant->>'invitationId'='94500000-0000-4000-8000-000000000005';
  IF v_participation_id IS NULL THEN
    RAISE EXCEPTION 'idempotency fixture invitation is absent from the authorized projection';
  END IF;

  -- Replaying the original request is harmless and returns only its own result.
  v_result := eogp.issue_guest_invitation(
    '22222222-2222-4222-8222-222222222222',
    '94000000-0000-4000-8000-000000000001',
    v_participation_id,
    NULL,
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    '94100000-0000-4000-8000-000000000001',
    '96400000-0000-4000-8000-000000000001',
    'en',
    decode('455631'||repeat('01',40),'hex'),
    repeat('a',64),
    decode('45435031'||repeat('01',40),'hex'),
    clock_timestamp()+interval '2 hours',
    repeat('e',64)
  );
  IF v_result->>'created'<>'false'
     OR v_result->>'invitationId'<>'94500000-0000-4000-8000-000000000005'
     OR v_result->>'deliveryId'<>'96700000-0000-4000-8000-000000000001' THEN
    RAISE EXCEPTION 'same-request invitation replay returned an unexpected result: %',v_result;
  END IF;

  -- A caller authorized for this event cannot reuse that key to retrieve a
  -- different participant's invitation/delivery identifiers.
  BEGIN
    PERFORM eogp.issue_guest_invitation(
      '22222222-2222-4222-8222-222222222222',
      '94000000-0000-4000-8000-000000000001',
      '94300000-0000-4000-8000-000000000001',
      NULL,
      'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
      '94100000-0000-4000-8000-000000000001',
      '96400000-0000-4000-8000-000000000001',
      'en',
      decode('455631'||repeat('02',40),'hex'),
      repeat('b',64),
      decode('45435031'||repeat('02',40),'hex'),
      clock_timestamp()+interval '2 hours',
      repeat('e',64)
    );
  EXCEPTION WHEN SQLSTATE '22023' THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'invitation idempotency replay crossed participation boundaries';
  END IF;
END;
$invitation_idempotency_scope$;
ROLLBACK;
