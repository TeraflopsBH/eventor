\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);

-- This integration fixture grants the actor only the event-scoped permissions
-- required for these three test events. Event four deliberately has no grant.
INSERT INTO eogp.roles (id, organization_id, code, name, scope_kind, is_system_preset)
VALUES
 ('93900000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','CI_EVENT_CHANGE_COMMANDS','CI event change command role','event',false);

INSERT INTO eogp.role_permissions (organization_id, role_id, permission_code)
VALUES
 ('22222222-2222-4222-8222-222222222222','93900000-0000-4000-8000-000000000001','event.cancellation.initiate'),
 ('22222222-2222-4222-8222-222222222222','93900000-0000-4000-8000-000000000001','event.cancellation.approve'),
 ('22222222-2222-4222-8222-222222222222','93900000-0000-4000-8000-000000000001','event.cancellation.execute'),
 ('22222222-2222-4222-8222-222222222222','93900000-0000-4000-8000-000000000001','event.postponement.manage');

INSERT INTO eogp.events
  (id, organization_id, event_code, title, status, current_revision, created_by_membership_id)
VALUES
 ('93000000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','CI-COMMAND-CANCEL','Command API cancellation','scheduled',1,'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
 ('93000000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','CI-COMMAND-POSTPONE','Command API postponement','scheduled',1,'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
 ('93000000-0000-4000-8000-000000000003','22222222-2222-4222-8222-222222222222','CI-COMMAND-RESCHEDULE','Command API reschedule','scheduled',1,'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
 ('93000000-0000-4000-8000-222222222222','22222222-2222-4222-8222-222222222222','CI-COMMAND-NO-GRANT','Command API no grant','scheduled',1,'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');

INSERT INTO eogp.event_schedule_revisions
  (id, organization_id, event_id, revision_number, schedule_kind, starts_at, ends_at,
   timezone_name, schedule_snapshot, created_by_membership_id)
VALUES
 ('93100000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','93000000-0000-4000-8000-000000000001',1,'original','2099-01-10 08:00+00','2099-01-10 17:00+00','Europe/Sarajevo','{"revision":1}'::jsonb,'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
 ('93100000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','93000000-0000-4000-8000-000000000002',1,'original','2099-01-11 08:00+00','2099-01-11 17:00+00','Europe/Sarajevo','{"revision":1}'::jsonb,'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
 ('93100000-0000-4000-8000-000000000003','22222222-2222-4222-8222-222222222222','93000000-0000-4000-8000-000000000003',1,'original','2099-01-12 08:00+00','2099-01-12 17:00+00','Europe/Sarajevo','{"revision":1}'::jsonb,'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
 ('93100000-0000-4000-8000-000000000004','22222222-2222-4222-8222-222222222222','93000000-0000-4000-8000-222222222222',1,'original','2099-01-13 08:00+00','2099-01-13 17:00+00','Europe/Sarajevo','{"revision":1}'::jsonb,'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');

INSERT INTO eogp.event_sessions
  (id, organization_id, event_id, code, title, starts_at, ends_at, status)
VALUES
 ('93200000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','93000000-0000-4000-8000-000000000001','PAST','Past completed session','2099-01-10 08:00+00','2099-01-10 09:00+00','completed'),
 ('93200000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','93000000-0000-4000-8000-000000000001','FUTURE','Future session','2099-01-10 10:00+00','2099-01-10 11:00+00','scheduled'),
 ('93200000-0000-4000-8000-000000000003','22222222-2222-4222-8222-222222222222','93000000-0000-4000-8000-000000000002','POSTPONE','Postponed session','2099-01-11 08:00+00','2099-01-11 09:00+00','scheduled'),
 ('93200000-0000-4000-8000-000000000004','22222222-2222-4222-8222-222222222222','93000000-0000-4000-8000-000000000003','RESCHEDULE','Rescheduled session','2099-01-12 08:00+00','2099-01-12 09:00+00','scheduled');

INSERT INTO eogp.user_role_grants (
 organization_id,membership_id,role_id,scope_kind,scope_event_id,granted_by_membership_id
) VALUES
 ('22222222-2222-4222-8222-222222222222','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb','93900000-0000-4000-8000-000000000001','event','93000000-0000-4000-8000-000000000001','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
 ('22222222-2222-4222-8222-222222222222','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb','93900000-0000-4000-8000-000000000001','event','93000000-0000-4000-8000-000000000002','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
 ('22222222-2222-4222-8222-222222222222','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb','93900000-0000-4000-8000-000000000001','event','93000000-0000-4000-8000-000000000003','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');

-- Execute commands as the same database role used by the API. The functions
-- perform their own active-membership and scoped-permission checks.
SET LOCAL ROLE eventor_runtime;

DO $commands$
DECLARE
  v_cancel_request uuid;
  v_postpone_request uuid;
  v_reschedule_request uuid;
  v_result jsonb;
  v_replacement uuid;
  v_denied boolean := false;
  v_stale boolean := false;
BEGIN
  v_cancel_request := (eogp.submit_event_change_request(
    '22222222-2222-4222-8222-222222222222',
    '93000000-0000-4000-8000-000000000001',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    'cancel',1,'venue_unavailable',
    decode('455631010203','hex'),
    'The event has been cancelled.',
    NULL
  ) ->> 'changeRequestId')::uuid;

  PERFORM eogp.decide_event_change_request(
    '22222222-2222-4222-8222-222222222222',
    v_cancel_request,
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    'approved',
    'Approved by the event owner.'
  );

  v_result := eogp.execute_event_change_request(
    '22222222-2222-4222-8222-222222222222',
    v_cancel_request,
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    1,
    'all_active_invitees',
    true,
    ARRAY[]::uuid[]
  );
  IF v_result ->> 'status' <> 'cancelled'
     OR v_result ->> 'notificationState' <> 'queued_for_dispatch' THEN
    RAISE EXCEPTION 'cancellation command returned unexpected result: %',v_result;
  END IF;

  -- Replaying the same request is handled by the HTTP idempotency layer; the
  -- database command itself still refuses to execute an already-executed row.
  BEGIN
    PERFORM eogp.execute_event_change_request(
      '22222222-2222-4222-8222-222222222222',
      v_cancel_request,
      'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
      1,
      'all_active_invitees',
      true,
      ARRAY[]::uuid[]
    );
    RAISE EXCEPTION 'already executed change request was executed twice';
  EXCEPTION WHEN SQLSTATE '55000' OR SQLSTATE '40001' THEN
    NULL;
  END;

  BEGIN
    PERFORM eogp.submit_event_change_request(
      '22222222-2222-4222-8222-222222222222',
      '93000000-0000-4000-8000-000000000001',
      'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
      'cancel',1,'stale_request',NULL,NULL,NULL
    );
    RAISE EXCEPTION 'stale event revision was accepted';
  EXCEPTION WHEN SQLSTATE '40001' THEN
    v_stale := true;
  END;
  IF NOT v_stale THEN RAISE EXCEPTION 'stale revision did not return serialization conflict'; END IF;

  v_postpone_request := (eogp.submit_event_change_request(
    '22222222-2222-4222-8222-222222222222',
    '93000000-0000-4000-8000-000000000002',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    'postpone',1,'provider_disruption',
    NULL,'The event will be postponed.',NULL
  ) ->> 'changeRequestId')::uuid;
  PERFORM eogp.decide_event_change_request(
    '22222222-2222-4222-8222-222222222222',
    v_postpone_request,
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    'approved',
    'Approved after reviewing the venue notice.'
  );
  v_result := eogp.execute_event_change_request(
    '22222222-2222-4222-8222-222222222222',
    v_postpone_request,
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    1,
    'accepted_tentative',
    false,
    ARRAY[]::uuid[]
  );
  IF v_result ->> 'status' <> 'postponed'
     OR v_result ->> 'notificationState' <> 'not_requested' THEN
    RAISE EXCEPTION 'postponement command returned unexpected result: %',v_result;
  END IF;

  v_reschedule_request := (eogp.submit_event_change_request(
    '22222222-2222-4222-8222-222222222222',
    '93000000-0000-4000-8000-000000000003',
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    'reschedule',1,'organizer_reschedule',
    NULL,'The event has a new date.',
    '{"startsAt":"2099-02-12T08:00:00Z","endsAt":"2099-02-12T17:00:00Z","timezone":"Europe/Sarajevo","materialChange":true,"reconfirmationPolicy":"accepted_tentative"}'::jsonb
  ) ->> 'changeRequestId')::uuid;
  SELECT replacement_schedule_revision_id INTO v_replacement
    FROM eogp.event_change_requests WHERE id = v_reschedule_request;
  IF v_replacement IS NULL THEN RAISE EXCEPTION 'reschedule request did not create a replacement schedule'; END IF;

  PERFORM eogp.decide_event_change_request(
    '22222222-2222-4222-8222-222222222222',
    v_reschedule_request,
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    'approved',
    'Approved after the new schedule was checked.'
  );
  v_result := eogp.execute_event_change_request(
    '22222222-2222-4222-8222-222222222222',
    v_reschedule_request,
    'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
    1,
    'accepted_tentative',
    true,
    ARRAY[]::uuid[]
  );
  IF v_result ->> 'decisionKind' <> 'rescheduled'
     OR v_result ->> 'status' <> 'scheduled' THEN
    RAISE EXCEPTION 'reschedule command returned unexpected result: %',v_result;
  END IF;

  BEGIN
    PERFORM eogp.submit_event_change_request(
      '22222222-2222-4222-8222-222222222222',
      '93000000-0000-4000-8000-222222222222',
      'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
      'cancel',1,'missing_scope',NULL,NULL,NULL
    );
    RAISE EXCEPTION 'event-scoped grant authorized an unrelated event';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'missing event permission did not deny request'; END IF;

  BEGIN
    PERFORM eogp.submit_event_change_request(
      '22222222-2222-4222-8222-222222222222',
      '93000000-0000-4000-8000-000000000003',
      'aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa',
      'reschedule',1,'wrong_tenant',NULL,NULL,
      '{"startsAt":"2099-02-12T08:00:00Z","endsAt":"2099-02-12T17:00:00Z","timezone":"Europe/Sarajevo"}'::jsonb
    );
    RAISE EXCEPTION 'cross-tenant membership was accepted';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;
END;
$commands$;

RESET ROLE;
SET LOCAL ROLE eventor_owner;

DO $assertions$
DECLARE
  v_count integer;
BEGIN
  IF (SELECT status FROM eogp.events WHERE id='93000000-0000-4000-8000-000000000001') <> 'cancelled'
     OR (SELECT current_revision FROM eogp.events WHERE id='93000000-0000-4000-8000-000000000001') <> 2 THEN
    RAISE EXCEPTION 'cancellation command did not update event state and revision';
  END IF;
  IF (SELECT status FROM eogp.event_sessions WHERE id='93200000-0000-4000-8000-000000000001') <> 'completed'
     OR (SELECT status FROM eogp.event_sessions WHERE id='93200000-0000-4000-8000-000000000002') <> 'cancelled' THEN
    RAISE EXCEPTION 'cancellation command changed completed history or left a future session active';
  END IF;
  SELECT count(*) INTO v_count FROM eogp.outbox_events
   WHERE organization_id='22222222-2222-4222-8222-222222222222'
     AND topic='event.change.notification_requested'
     AND aggregate_id='93000000-0000-4000-8000-000000000001';
  IF v_count <> 1 THEN RAISE EXCEPTION 'cancellation must enqueue exactly one notification dispatch request'; END IF;
  IF EXISTS (SELECT 1 FROM eogp.event_notification_campaigns
              WHERE organization_id='22222222-2222-4222-8222-222222222222'
                AND event_id='93000000-0000-4000-8000-000000000001') THEN
    RAISE EXCEPTION 'event command fabricated a notification campaign before the dispatcher prepared its audience';
  END IF;
  IF (SELECT status FROM eogp.events WHERE id='93000000-0000-4000-8000-000000000002') <> 'postponed' THEN
    RAISE EXCEPTION 'postponement command did not set event status';
  END IF;
  IF (SELECT status FROM eogp.events WHERE id='93000000-0000-4000-8000-000000000003') <> 'scheduled' THEN
    RAISE EXCEPTION 'reschedule command did not return event to scheduled status';
  END IF;
  SELECT count(*) INTO v_count FROM eogp.event_decisions
   WHERE organization_id='22222222-2222-4222-8222-222222222222'
     AND decision_kind IN ('cancelled','postponed','rescheduled')
     AND event_id IN (
       '93000000-0000-4000-8000-000000000001',
       '93000000-0000-4000-8000-000000000002',
       '93000000-0000-4000-8000-000000000003'
     );
  IF v_count <> 3 THEN RAISE EXCEPTION 'expected one committed decision per event change'; END IF;
END;
$assertions$;

ROLLBACK;
