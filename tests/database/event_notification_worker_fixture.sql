\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);

INSERT INTO eogp.roles (id, organization_id, code, name, scope_kind)
VALUES ('93900000-0000-4000-8000-000000000001',
        '22222222-2222-4222-8222-222222222222',
        'CI_NOTIFICATION_REVIEWER','CI notification reviewer','event');
INSERT INTO eogp.role_permissions (organization_id, role_id, permission_code)
VALUES
 ('22222222-2222-4222-8222-222222222222','93900000-0000-4000-8000-000000000001','event.notifications.preview'),
 ('22222222-2222-4222-8222-222222222222','93900000-0000-4000-8000-000000000001','event.notifications.send');
INSERT INTO eogp.events
  (id, organization_id, event_code, title, status, current_revision, created_by_membership_id)
VALUES
 ('94000000-0000-4000-8000-000000000001',
  '22222222-2222-4222-8222-222222222222',
  'CI-NOTIFICATION-WORKER',
  'Notification worker integration event',
  'scheduled',1,'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');

INSERT INTO eogp.user_role_grants (
  id, organization_id, membership_id, role_id, scope_kind, scope_event_id,
  granted_by_membership_id
) VALUES (
 '93900000-0000-4000-8000-000000000002',
 '22222222-2222-4222-8222-222222222222',
 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
 '93900000-0000-4000-8000-000000000001',
 'event','94000000-0000-4000-8000-000000000001',
 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
);

INSERT INTO eogp.event_schedule_revisions
  (id, organization_id, event_id, revision_number, schedule_kind,
   starts_at, ends_at, timezone_name, venue_summary, schedule_snapshot,
   material_change, reconfirmation_policy, created_by_membership_id)
VALUES
 ('94100000-0000-4000-8000-000000000001',
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  1,'original','2099-03-10 08:00+00','2099-03-10 17:00+00',
  'Europe/Sarajevo','{"venue":"CI"}'::jsonb,'{"revision":1}'::jsonb,
  false,'none','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');

INSERT INTO eogp.persons
  (id, organization_id, first_name, last_name, display_name, created_by_membership_id)
VALUES
 ('94200000-0000-4000-8000-000000000001',
  '22222222-2222-4222-8222-222222222222','Worker','Eligible','Worker Eligible',
  'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
 ('94200000-0000-4000-8000-000000000002',
  '22222222-2222-4222-8222-222222222222','Worker','NoConsent','Worker NoConsent',
  'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
 ('94200000-0000-4000-8000-000000000003',
  '22222222-2222-4222-8222-222222222222','Worker','PreviouslyInvited','Worker Previously Invited',
  'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');

INSERT INTO eogp.event_participations
  (id, organization_id, event_id, person_id, status, added_by_membership_id)
VALUES
 ('94300000-0000-4000-8000-000000000001',
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  '94200000-0000-4000-8000-000000000001','eligible',
  'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
 ('94300000-0000-4000-8000-000000000002',
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  '94200000-0000-4000-8000-000000000002','eligible',
  'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
 ('94300000-0000-4000-8000-000000000003',
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  '94200000-0000-4000-8000-000000000003','eligible',
  'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');

INSERT INTO eogp.person_contact_points
  (id, organization_id, person_id, contact_kind, normalized_value_hash,
   encrypted_value, is_primary, is_verified, contact_consent)
VALUES
 ('94400000-0000-4000-8000-000000000001',
  '22222222-2222-4222-8222-222222222222',
  '94200000-0000-4000-8000-000000000001',
  'email',repeat('a',64),decode('01020304','hex'),true,true,'permitted'),
 ('94400000-0000-4000-8000-000000000002',
  '22222222-2222-4222-8222-222222222222',
  '94200000-0000-4000-8000-000000000002',
  'email',repeat('b',64),decode('05060708','hex'),true,true,'restricted'),
 ('94400000-0000-4000-8000-000000000003',
  '22222222-2222-4222-8222-222222222222',
  '94200000-0000-4000-8000-000000000003',
  'email',repeat('c',64),decode('090a0b0c','hex'),true,true,'permitted');

INSERT INTO eogp.invitations
  (id, organization_id, event_id, participation_id, status,
   current_revision_number, issued_at, created_by_membership_id)
VALUES
 ('94500000-0000-4000-8000-000000000001',
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  '94300000-0000-4000-8000-000000000001',
  'active',1,clock_timestamp(),'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
 ('94500000-0000-4000-8000-000000000002',
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  '94300000-0000-4000-8000-000000000002',
  'active',1,clock_timestamp(),'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
 ('94500000-0000-4000-8000-000000000003',
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  '94300000-0000-4000-8000-000000000003',
  'replaced',1,clock_timestamp() - interval '1 day','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
 ('94500000-0000-4000-8000-000000000004',
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  '94300000-0000-4000-8000-000000000003',
  'draft',0,NULL,'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');

INSERT INTO eogp.notification_templates
  (id, organization_id, code, purpose, status)
VALUES
 ('94600000-0000-4000-8000-000000000001',
  '22222222-2222-4222-8222-222222222222',
  'CI_EVENT_CANCELLATION','event_cancellation','active');

INSERT INTO eogp.notification_template_revisions
  (id, organization_id, template_id, revision_number, locale,
   subject_template, body_template, state, published_at)
VALUES
 ('94700000-0000-4000-8000-000000000001',
  '22222222-2222-4222-8222-222222222222',
  '94600000-0000-4000-8000-000000000001',
  1,'bs-BA','Otkazivanje događaja','Događaj je otkazan.','published',clock_timestamp());

INSERT INTO eogp.event_change_requests
  (id, organization_id, event_id, change_kind, expected_event_revision,
   reason_code, public_message, status, initiated_by_organization_id,
   initiated_by_membership_id, submitted_at, resolved_at)
VALUES
 ('94800000-0000-4000-8000-000000000001',
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  'cancel',1,'venue_unavailable','Događaj je otkazan.','executed',
  '22222222-2222-4222-8222-222222222222',
  'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
  clock_timestamp(),clock_timestamp());

UPDATE eogp.events
   SET status = 'cancelled',
       current_revision = 2,
       updated_at = clock_timestamp()
 WHERE organization_id = '22222222-2222-4222-8222-222222222222'
   AND id = '94000000-0000-4000-8000-000000000001';

INSERT INTO eogp.event_decisions
  (id, organization_id, event_id, source_change_request_id, decision_kind,
   original_schedule_revision_id, reason_code, public_message,
   executed_by_organization_id, executed_by_membership_id)
VALUES
 ('94900000-0000-4000-8000-000000000001',
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  '94800000-0000-4000-8000-000000000001',
  'cancelled','94100000-0000-4000-8000-000000000001',
  'venue_unavailable','Događaj je otkazan.',
  '22222222-2222-4222-8222-222222222222',
  'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');

INSERT INTO eogp.outbox_events
  (id, organization_id, topic, aggregate_type, aggregate_id, payload, idempotency_key)
VALUES
 ('95000000-0000-4000-8000-000000000001',
  '22222222-2222-4222-8222-222222222222',
  'event.change.notification_requested','event',
  '94000000-0000-4000-8000-000000000001',
  jsonb_build_object(
    'eventDecisionId','94900000-0000-4000-8000-000000000001',
    'changeRequestId','94800000-0000-4000-8000-000000000001',
    'decisionKind','cancelled',
    'audienceKind','all_previously_invited',
    'customParticipationIds','[]'::jsonb
  ),
  'ci-event-notification-worker-001');

COMMIT;
