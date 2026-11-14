\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SET LOCAL app.organization_id='22222222-2222-4222-8222-222222222222';

-- Reuse the committed event-notification fixture's event, schedule,
-- participations, memberships and invitations. Everything added here rolls back.
-- The notification worker fixture intentionally cancels its event. Temporarily
-- restore its lifecycle state inside this transaction so invitation revision
-- guards permit the fixture rows; the event change is rolled back at the end.
UPDATE eogp.events
   SET status='scheduled',updated_at=clock_timestamp()
 WHERE organization_id='22222222-2222-4222-8222-222222222222'
   AND id='94000000-0000-4000-8000-000000000001';

INSERT INTO eogp.rsvp_policies (
  id, organization_id, event_id, code, name
) VALUES (
  '95100000-0000-4000-8000-000000000001',
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  'CI_GUEST_ATTEMPT_HISTORY','CI guest attempt history'
);

INSERT INTO eogp.rsvp_policy_revisions (
  id, organization_id, event_id, policy_id, revision_number,
  event_timezone, state, published_at
) VALUES (
  '95200000-0000-4000-8000-000000000001',
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  '95100000-0000-4000-8000-000000000001',
  1,'Europe/Sarajevo','published',clock_timestamp()
);

INSERT INTO eogp.invitation_revisions (
  id, organization_id, event_id, invitation_id, revision_number,
  schedule_revision_id, rsvp_policy_revision_id, locale,
  presentation_snapshot_ciphertext, issued_at, created_by_membership_id
)
SELECT
  ('95300000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  ('94500000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
  1,
  '94100000-0000-4000-8000-000000000001',
  '95200000-0000-4000-8000-000000000001',
  'en',decode('455631010203','hex'),clock_timestamp(),
  'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
FROM generate_series(1,4) AS n;

INSERT INTO eogp.invitation_deliveries (
  id, organization_id, event_id, invitation_id, invitation_revision_id,
  channel, destination_ciphertext, destination_hash, status
)
SELECT
  ('95400000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  ('94500000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
  ('95300000-0000-4000-8000-' || lpad(n::text,12,'0'))::uuid,
  'email',decode('45435031010203','hex'),repeat(n::text,64),'queued'
FROM generate_series(1,4) AS n;

DO $attempt_history_regression$
DECLARE
  v_org uuid := '22222222-2222-4222-8222-222222222222';
  v_retry_delivery uuid := '95400000-0000-4000-8000-000000000001';
  v_uncertain_delivery uuid := '95400000-0000-4000-8000-000000000002';
  v_expired_delivery uuid := '95400000-0000-4000-8000-000000000003';
  v_suppressed_delivery uuid := '95400000-0000-4000-8000-000000000004';
  v_attempt record;
  v_count integer;
  v_denied boolean;
BEGIN
  -- A queued delivery has no SMTP attempt until it enters sending.
  SELECT count(*) INTO v_count
    FROM eogp.invitation_delivery_attempts
   WHERE organization_id=v_org AND delivery_id=v_retry_delivery;
  IF v_count<>0 THEN
    RAISE EXCEPTION 'queued delivery unexpectedly created an attempt';
  END IF;

  -- First SMTP claim, transient failure, and retry scheduling.
  UPDATE eogp.invitation_deliveries
     SET status='sending',attempt_count=1,
         lease_expires_at=clock_timestamp()+interval '5 minutes'
   WHERE organization_id=v_org AND id=v_retry_delivery;

  UPDATE eogp.invitation_deliveries
     SET status='queued',lease_expires_at=NULL,
         failure_code='SMTP_CONNECTION'
   WHERE organization_id=v_org AND id=v_retry_delivery;

  SELECT * INTO v_attempt
    FROM eogp.invitation_delivery_attempts
   WHERE organization_id=v_org AND delivery_id=v_retry_delivery
     AND attempt_number=1;
  IF NOT FOUND OR v_attempt.status<>'failed'
     OR v_attempt.failure_code<>'SMTP_CONNECTION'
     OR NOT v_attempt.retry_scheduled OR v_attempt.completed_at IS NULL THEN
    RAISE EXCEPTION 'transient failure did not finalize attempt 1 as retryable';
  END IF;

  -- Second claim succeeds and preserves the provider reference.
  UPDATE eogp.invitation_deliveries
     SET status='sending',attempt_count=2,
         lease_expires_at=clock_timestamp()+interval '5 minutes',
         failure_code=NULL
   WHERE organization_id=v_org AND id=v_retry_delivery;

  UPDATE eogp.invitation_deliveries
     SET status='sent',lease_expires_at=NULL,failure_code=NULL,
         provider_message_reference='<ci-guest-attempt-2@example.test>'
   WHERE organization_id=v_org AND id=v_retry_delivery;

  SELECT * INTO v_attempt
    FROM eogp.invitation_delivery_attempts
   WHERE organization_id=v_org AND delivery_id=v_retry_delivery
     AND attempt_number=2;
  IF NOT FOUND OR v_attempt.status<>'sent'
     OR v_attempt.provider_message_reference IS DISTINCT FROM '<ci-guest-attempt-2@example.test>'
     OR v_attempt.retry_scheduled OR v_attempt.completed_at IS NULL THEN
    RAISE EXCEPTION 'successful attempt 2 did not preserve sent/provider details';
  END IF;

  SELECT count(*) INTO v_count
    FROM eogp.invitation_delivery_attempts
   WHERE organization_id=v_org AND delivery_id=v_retry_delivery;
  IF v_count<>2 THEN
    RAISE EXCEPTION 'retry delivery should have exactly two attempt rows, got %',v_count;
  END IF;

  -- Completed attempt history is immutable even to a direct owner-level DML
  -- statement. Only the nested delivery-status trigger may finalize sending.
  v_denied := false;
  BEGIN
    UPDATE eogp.invitation_delivery_attempts
       SET failure_code='OWNER_TAMPER'
     WHERE organization_id=v_org AND delivery_id=v_retry_delivery
       AND attempt_number=1;
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'owner-level UPDATE rewrote completed invitation attempt history';
  END IF;

  v_denied := false;
  BEGIN
    DELETE FROM eogp.invitation_delivery_attempts
     WHERE organization_id=v_org AND delivery_id=v_retry_delivery
       AND attempt_number=1;
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'owner-level DELETE removed invitation attempt history';
  END IF;

  -- An ambiguous SMTP outcome is terminal and is never marked retryable.
  UPDATE eogp.invitation_deliveries
     SET status='sending',attempt_count=1,
         lease_expires_at=clock_timestamp()+interval '5 minutes'
   WHERE organization_id=v_org AND id=v_uncertain_delivery;

  UPDATE eogp.invitation_deliveries
     SET status='uncertain',lease_expires_at=NULL,
         failure_code='SMTP_UNKNOWN'
   WHERE organization_id=v_org AND id=v_uncertain_delivery;

  SELECT * INTO v_attempt
    FROM eogp.invitation_delivery_attempts
   WHERE organization_id=v_org AND delivery_id=v_uncertain_delivery
     AND attempt_number=1;
  IF NOT FOUND OR v_attempt.status<>'uncertain'
     OR v_attempt.failure_code<>'SMTP_UNKNOWN'
     OR v_attempt.retry_scheduled OR v_attempt.completed_at IS NULL THEN
    RAISE EXCEPTION 'uncertain SMTP outcome was not recorded as non-retryable';
  END IF;

  -- Expired lease recovery uses the same sending -> uncertain transition
  -- performed by claim_invitation_email_delivery().
  UPDATE eogp.invitation_deliveries
     SET status='sending',attempt_count=1,
         lease_expires_at=clock_timestamp()-interval '1 second'
   WHERE organization_id=v_org AND id=v_expired_delivery;

  UPDATE eogp.invitation_deliveries
     SET status='uncertain',lease_expires_at=NULL,
         failure_code='SMTP_UNKNOWN'
   WHERE organization_id=v_org AND id=v_expired_delivery
     AND status='sending' AND lease_expires_at<=clock_timestamp();

  SELECT * INTO v_attempt
    FROM eogp.invitation_delivery_attempts
   WHERE organization_id=v_org AND delivery_id=v_expired_delivery
     AND attempt_number=1;
  IF NOT FOUND OR v_attempt.status<>'uncertain'
     OR v_attempt.failure_code<>'SMTP_UNKNOWN'
     OR v_attempt.retry_scheduled OR v_attempt.completed_at IS NULL THEN
    RAISE EXCEPTION 'expired lease did not finalize its attempt as uncertain';
  END IF;

  -- Suppression before a worker claim must not create an SMTP attempt.
  UPDATE eogp.invitation_deliveries
     SET status='suppressed',failure_code='INVITATION_REVOKED'
   WHERE organization_id=v_org AND id=v_suppressed_delivery;

  SELECT count(*) INTO v_count
    FROM eogp.invitation_delivery_attempts
   WHERE organization_id=v_org AND delivery_id=v_suppressed_delivery;
  IF v_count<>0 THEN
    RAISE EXCEPTION 'pre-send suppression unexpectedly created an attempt';
  END IF;
END;
$attempt_history_regression$;

-- Add the precise event-scoped permission for the fixture organizer.
INSERT INTO eogp.role_permissions (organization_id,role_id,permission_code)
VALUES (
  '22222222-2222-4222-8222-222222222222',
  '93900000-0000-4000-8000-000000000001',
  'invitation.manage'
)
ON CONFLICT DO NOTHING;

INSERT INTO eogp.role_permissions (organization_id,role_id,permission_code)
VALUES
 ('22222222-2222-4222-8222-222222222222','93900000-0000-4000-8000-000000000001','rsvp.record'),
 ('22222222-2222-4222-8222-222222222222','93900000-0000-4000-8000-000000000001','rsvp.correct')
ON CONFLICT DO NOTHING;

-- A separate active member with no invitation.manage grant proves that
-- membership alone is insufficient. All identities are transaction-local.
INSERT INTO eogp.users (id,email,display_name,status)
VALUES (
  '95500000-0000-4000-8000-000000000001',
  'ci-guest-history-unauthorized@example.invalid',
  'CI Guest History Unauthorized','active'
);
INSERT INTO eogp.organization_memberships (
  id,organization_id,user_id,status,joined_at
) VALUES (
  '95600000-0000-4000-8000-000000000001',
  '22222222-2222-4222-8222-222222222222',
  '95500000-0000-4000-8000-000000000001',
  'active',clock_timestamp()
);

-- Exercise the SECURITY DEFINER projection through the actual runtime role.
SET LOCAL ROLE eventor_runtime;
SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);
SELECT set_config('app.actor_membership_id','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',true);

DO $attempt_history_authorization$
DECLARE
  v_result jsonb;
  v_denied boolean;
BEGIN
  -- Correct tenant, active event-scoped manager and actor context.
  v_result := eogp.list_guest_invitation_delivery_attempts(
    '22222222-2222-4222-8222-222222222222',
    '94500000-0000-4000-8000-000000000001',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
  );
  IF jsonb_typeof(v_result)<>'array' OR jsonb_array_length(v_result)<>2
     OR NOT (v_result @> '[{"attemptNumber":1,"status":"failed","retryScheduled":true}]'::jsonb)
     OR NOT (v_result @> '[{"attemptNumber":2,"status":"sent","retryScheduled":false}]'::jsonb) THEN
    RAISE EXCEPTION 'authorized event manager received an incomplete attempt history: %',v_result;
  END IF;

  -- Supplied actor must match the actor bound to the DB session.
  v_denied := false;
  BEGIN
    PERFORM eogp.list_guest_invitation_delivery_attempts(
      '22222222-2222-4222-8222-222222222222',
      '94500000-0000-4000-8000-000000000001',
      '95600000-0000-4000-8000-000000000001'
    );
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'history projection accepted an actor/context mismatch';
  END IF;

  -- A different tenant context cannot request the original tenant's history.
  PERFORM set_config('app.organization_id','33333333-3333-4333-8333-333333333333',true);
  v_denied := false;
  BEGIN
    PERFORM eogp.list_guest_invitation_delivery_attempts(
      '22222222-2222-4222-8222-222222222222',
      '94500000-0000-4000-8000-000000000001',
      'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
    );
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'history projection accepted a cross-tenant request';
  END IF;
  PERFORM set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);

  -- An active member without the event-scoped permission is not authorized.
  PERFORM set_config('app.actor_membership_id','95600000-0000-4000-8000-000000000001',true);
  v_denied := false;
  BEGIN
    PERFORM eogp.list_guest_invitation_delivery_attempts(
      '22222222-2222-4222-8222-222222222222',
      '94500000-0000-4000-8000-000000000001',
      '95600000-0000-4000-8000-000000000001'
    );
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'history projection accepted an active member without invitation.manage';
  END IF;
END;
$attempt_history_authorization$;

-- A successor published policy with an expired deadline exercises the
-- separate late-recording permission without changing the invitation's pinned
-- policy revision used by the first participant.
INSERT INTO eogp.rsvp_policy_revisions (
  id,organization_id,event_id,policy_id,revision_number,
  response_deadline,event_timezone,state,published_at,late_change_requires_staff
) VALUES (
  '95200000-0000-4000-8000-000000000002',
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  '95100000-0000-4000-8000-000000000001',
  2,clock_timestamp()-interval '1 minute','Europe/Sarajevo',
  'published',clock_timestamp(),true
);

-- Staff-recorded RSVP appends an attributed response; corrections append a
-- successor row and require the dedicated correction permission.
SET LOCAL ROLE eventor_runtime;
SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);
SELECT set_config('app.actor_membership_id','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',true);

DO $staff_rsvp_regression$
DECLARE
  v_org uuid := '22222222-2222-4222-8222-222222222222';
  v_event uuid := '94000000-0000-4000-8000-000000000001';
  v_participation uuid := '94300000-0000-4000-8000-000000000001';
  v_invitation uuid := '94500000-0000-4000-8000-000000000001';
  v_first uuid;
  v_second uuid;
  v_result jsonb;
  v_count integer;
  v_denied boolean;
BEGIN
  v_result := eogp.record_staff_guest_rsvp(
    v_org,v_event,v_participation,
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    'accepted','phone','guest',clock_timestamp()-interval '5 minutes',
    v_invitation,decode('45435031'||repeat('01',40),'hex'),NULL,NULL
  );
  v_first := (v_result->>'responseId')::uuid;
  IF v_result->>'response'<>'accepted' OR (v_result->>'sequenceNumber')::integer<>1 THEN
    RAISE EXCEPTION 'staff RSVP did not create the first response: %',v_result;
  END IF;

  v_result := eogp.record_staff_guest_rsvp(
    v_org,v_event,v_participation,
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    'declined','email','guest',clock_timestamp()-interval '4 minutes',
    v_invitation,decode('45435031'||repeat('02',40),'hex'),v_first,
    'Guest confirmed the earlier answer was recorded incorrectly'
  );
  v_second := (v_result->>'responseId')::uuid;
  IF v_result->>'response'<>'declined'
     OR (v_result->>'sequenceNumber')::integer<>2
     OR (v_result->>'correctionOfResponseId')::uuid<>v_first THEN
    RAISE EXCEPTION 'staff RSVP correction was not appended correctly: %',v_result;
  END IF;

  SELECT count(*) INTO v_count
    FROM eogp.rsvp_responses
   WHERE organization_id=v_org AND event_id=v_event
     AND participation_id=v_participation;
  IF v_count<>2 THEN
    RAISE EXCEPTION 'expected both original and corrected RSVP rows, found %',v_count;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM eogp.rsvp_responses
     WHERE organization_id=v_org AND id=v_first
       AND response='accepted' AND correction_of_response_id IS NULL
       AND actor_membership_id='bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
       AND notes_restricted_ciphertext=decode('45435031'||repeat('01',40),'hex')
  ) OR NOT EXISTS (
    SELECT 1 FROM eogp.rsvp_responses
     WHERE organization_id=v_org AND id=v_second
       AND response='declined' AND correction_of_response_id=v_first
       AND correction_reason='Guest confirmed the earlier answer was recorded incorrectly'
       AND notes_restricted_ciphertext=decode('45435031'||repeat('02',40),'hex')
  ) THEN
    RAISE EXCEPTION 'staff RSVP actor, source or correction evidence was not preserved';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM eogp.audit_events
     WHERE organization_id=v_org
       AND actor_membership_id='bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
       AND action='guest.rsvp.recorded'
       AND aggregate_id=v_participation
       AND safe_metadata->>'responseId'=v_first::text
  ) OR NOT EXISTS (
    SELECT 1 FROM eogp.audit_events
     WHERE organization_id=v_org
       AND actor_membership_id='bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
       AND action='guest.rsvp.corrected'
       AND aggregate_id=v_participation
       AND safe_metadata->>'correctionOfResponseId'=v_first::text
  ) THEN
    RAISE EXCEPTION 'staff RSVP record/correction audit events were not written';
  END IF;

  -- A stale correction cannot branch from a response that is no longer current.
  v_denied := false;
  BEGIN
    PERFORM eogp.record_staff_guest_rsvp(
      v_org,v_event,v_participation,
      'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
      'tentative','phone','guest',clock_timestamp()-interval '3 minutes',
      v_invitation,NULL,v_first,'Attempt to correct a superseded response'
    );
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'staff RSVP accepted a correction against a superseded response';
  END IF;

  -- An active membership without rsvp.record cannot record a response.
  PERFORM set_config('app.actor_membership_id','95600000-0000-4000-8000-000000000001',true);
  v_denied := false;
  BEGIN
    PERFORM eogp.record_staff_guest_rsvp(
      v_org,v_event,'94300000-0000-4000-8000-000000000002',
      '95600000-0000-4000-8000-000000000001',
      'accepted','phone','guest',clock_timestamp()-interval '1 minute',
      NULL,NULL,NULL,NULL
    );
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'staff RSVP accepted a member without rsvp.record';
  END IF;

  -- The supplied actor argument cannot override the transaction-bound actor.
  PERFORM set_config('app.actor_membership_id','95600000-0000-4000-8000-000000000001',true);
  v_denied := false;
  BEGIN
    PERFORM eogp.record_staff_guest_rsvp(
      v_org,v_event,'94300000-0000-4000-8000-000000000002',
      'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
      'accepted','phone','guest',clock_timestamp()-interval '1 minute',
      NULL,NULL,NULL,NULL
    );
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'staff RSVP accepted an actor/context mismatch';
  END IF;
  PERFORM set_config('app.actor_membership_id','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',true);

  -- A late staff record is denied without the separate override permission.
  v_denied := false;
  BEGIN
    PERFORM eogp.record_staff_guest_rsvp(
      v_org,v_event,'94300000-0000-4000-8000-000000000002',
      'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
      'accepted','phone','guest',clock_timestamp()-interval '1 minute',
      NULL,NULL,NULL,NULL
    );
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'late staff RSVP bypassed rsvp.override_deadline';
  END IF;
END;
$staff_rsvp_regression$;

-- Grant the explicit late-response override, then verify the same late record
-- succeeds for the authorized organizer.
SET LOCAL ROLE eventor_owner;
INSERT INTO eogp.role_permissions (organization_id,role_id,permission_code)
VALUES (
  '22222222-2222-4222-8222-222222222222',
  '93900000-0000-4000-8000-000000000001',
  'rsvp.override_deadline'
)
ON CONFLICT DO NOTHING;
SET LOCAL ROLE eventor_runtime;
SELECT set_config('app.actor_membership_id','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',true);
DO $staff_rsvp_late_override$
DECLARE
  v_result jsonb;
  v_projection jsonb;
BEGIN
  v_result := eogp.record_staff_guest_rsvp(
    '22222222-2222-4222-8222-222222222222',
    '94000000-0000-4000-8000-000000000001',
    '94300000-0000-4000-8000-000000000002',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    'accepted','phone','guest',clock_timestamp()-interval '1 minute',
    NULL,NULL,NULL,NULL
  );
  IF v_result->>'response'<>'accepted' THEN
    RAISE EXCEPTION 'authorized late RSVP was not recorded: %',v_result;
  END IF;
  v_projection := eogp.list_guest_invitation_participations(
    '22222222-2222-4222-8222-222222222222',
    '94000000-0000-4000-8000-000000000001',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
  );
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(v_projection) participant
     WHERE participant->>'participationId'='94300000-0000-4000-8000-000000000002'
       AND participant->>'currentResponseId'=v_result->>'responseId'
       AND participant->>'currentResponse'='accepted'
  ) THEN
    RAISE EXCEPTION 'staff participation projection did not expose the current RSVP response ID: %',v_projection;
  END IF;
END;
$staff_rsvp_late_override$;

-- The append-only guard also applies to staff-entered RSVP history.
-- Use the table owner so the trigger, rather than missing table privileges, is tested.
SET LOCAL ROLE eventor_owner;
DO $staff_rsvp_immutability$
DECLARE
  v_response_id uuid;
  v_denied boolean := false;
BEGIN
  SELECT id INTO v_response_id
    FROM eogp.rsvp_responses
   WHERE organization_id='22222222-2222-4222-8222-222222222222'
     AND participation_id='94300000-0000-4000-8000-000000000001'
   ORDER BY sequence_number LIMIT 1;
  BEGIN
    UPDATE eogp.rsvp_responses SET response='tentative' WHERE id=v_response_id;
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'staff RSVP history was mutable';
  END IF;
  v_denied := false;
  BEGIN
    DELETE FROM eogp.rsvp_responses WHERE id=v_response_id;
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'staff RSVP history was deletable';
  END IF;
END;
$staff_rsvp_immutability$;

SET LOCAL ROLE eventor_owner;


-- Staff RSVP history is permission- and actor-bound and never returns restricted note ciphertext.
SET LOCAL ROLE eventor_runtime;
SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);
SELECT set_config('app.actor_membership_id','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',true);
DO $staff_rsvp_history_read$
DECLARE v_history jsonb; v_denied boolean := false;
BEGIN
  v_history := eogp.list_staff_guest_rsvp_history(
    '22222222-2222-4222-8222-222222222222','94000000-0000-4000-8000-000000000001',
    '94300000-0000-4000-8000-000000000001','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');
  IF jsonb_array_length(v_history)<>2
     OR NOT (v_history @> '[{"sequenceNumber":2,"sourceChannel":"email","respondentKind":"guest","correctionReason":"Guest confirmed the earlier answer was recorded incorrectly"}]'::jsonb)
     OR (v_history->0) ? 'notesRestrictedCiphertext'
     OR NOT (v_history->0 ? 'actorMembershipId') OR NOT (v_history->0 ? 'recordedAt') THEN
    RAISE EXCEPTION 'staff RSVP history projection omitted evidence or exposed restricted fields: %',v_history;
  END IF;
  v_denied := false;
  BEGIN
    PERFORM eogp.list_staff_guest_rsvp_history(
      '22222222-2222-4222-8222-222222222222','94000000-0000-4000-8000-000000000001',
      '94300000-0000-4000-8000-000000000001','95600000-0000-4000-8000-000000000001');
  EXCEPTION WHEN SQLSTATE '42501' THEN v_denied := true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'RSVP history accepted mismatched actor context'; END IF;
END;
$staff_rsvp_history_read$;


-- Guard the production recovery path itself: the worker claim function must
-- atomically convert expired sending leases to terminal uncertain attempts.
-- The transition fixture above checks the attempt-history trigger semantics;
-- this assertion prevents the real claim path from silently losing recovery.
DO $expired_lease_claim_path$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef(
    'eogp.claim_invitation_email_delivery(uuid)'::regprocedure
  ) INTO v_definition;
  IF strpos(v_definition, 'status=''uncertain''')=0
     OR strpos(v_definition, 'status=''sending''')=0
     OR strpos(v_definition, 'lease_expires_at<=clock_timestamp()')=0
     OR strpos(v_definition, 'failure_code=''SMTP_UNKNOWN''')=0 THEN
    RAISE EXCEPTION 'real invitation delivery claim function no longer recovers expired leases as uncertain';
  END IF;
END;
$expired_lease_claim_path$;

ROLLBACK;

\echo 'Guest invitation delivery attempt-history transition regressions passed.'
