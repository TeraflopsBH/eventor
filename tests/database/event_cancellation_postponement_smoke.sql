\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);

-- Shared guest identities used by both organizer-owned event fixtures.
INSERT INTO eogp.persons
  (id, organization_id, first_name, last_name, created_by_membership_id)
VALUES
  ('90300000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','Guest','One','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('90300000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','Guest','Two','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('90300000-0000-4000-8000-000000000003','22222222-2222-4222-8222-222222222222','Guest','Three','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('90300000-0000-4000-8000-000000000004','22222222-2222-4222-8222-222222222222','Guest','Four','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');

-- Event 1 will be cancelled after invitations have been delivered and RSVP
-- responses exist. Event 2 receives a provider disruption notice, then the
-- organizer independently decides to postpone it.
INSERT INTO eogp.events
  (id, organization_id, event_code, title, status, current_revision, created_by_membership_id)
VALUES
  ('90000000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','CI-CANCEL-AFTER-INVITES','CI Cancellation After Invitations','scheduled',1,'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('90000000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','CI-POSTPONE-AFTER-DISRUPTION','CI Postponement After Provider Notice','scheduled',1,'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');

INSERT INTO eogp.event_schedule_revisions
  (id, organization_id, event_id, revision_number, schedule_kind, starts_at, ends_at,
   timezone_name, venue_summary, schedule_snapshot, material_change, reconfirmation_policy,
   created_by_membership_id)
VALUES
  ('90100000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001',1,'original','2030-11-10 08:00+00','2030-11-10 17:00+00','Europe/Sarajevo','{"venue":"Main Hall"}','{"version":1}'::jsonb,false,'none','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('90100000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002',1,'original','2030-11-11 08:00+00','2030-11-11 17:00+00','Europe/Sarajevo','{"venue":"Main Hall"}','{"version":1}'::jsonb,false,'none','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('90100000-0000-4000-8000-000000000003','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002',2,'reschedule','2030-12-01 08:00+00','2030-12-01 17:00+00','Europe/Sarajevo','{"venue":"Main Hall"}','{"version":2,"reconfirmation":"accepted_tentative"}'::jsonb,true,'accepted_tentative','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');

INSERT INTO eogp.event_sessions
  (id, organization_id, event_id, code, title, starts_at, ends_at, status)
VALUES
  ('90200000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','PAST-SESSION','Completed morning session','2030-11-10 08:00+00','2030-11-10 10:00+00','completed'),
  ('90200000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','FUTURE-SESSION','Future afternoon session','2030-11-10 13:00+00','2030-11-10 17:00+00','scheduled'),
  ('90200000-0000-4000-8000-000000000003','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','POSTPONE-SESSION','Session to be postponed','2030-11-11 08:00+00','2030-11-11 17:00+00','scheduled');

INSERT INTO eogp.rsvp_policies (id, organization_id, event_id, code, name)
VALUES
  ('90500000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','CI-RSVP-CANCEL','Cancellation RSVP policy'),
  ('90500000-0000-4000-8000-222222222222','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','CI-RSVP-POSTPONE','Postponement RSVP policy');

INSERT INTO eogp.rsvp_policy_revisions
  (id, organization_id, event_id, policy_id, revision_number, allowed_responses,
   response_deadline, event_timezone, response_change_allowed, late_change_requires_staff,
   state, published_at)
VALUES
  ('90600000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','90500000-0000-4000-8000-000000000001',1,'["accepted","declined","tentative"]'::jsonb,'2030-11-01 12:00+00','Europe/Sarajevo',true,true,'published',clock_timestamp()),
  ('90600000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90500000-0000-4000-8000-000000000002',1,'["accepted","declined","tentative"]'::jsonb,'2030-11-02 12:00+00','Europe/Sarajevo',true,true,'published',clock_timestamp());

INSERT INTO eogp.event_participations
  (id, organization_id, event_id, person_id, participation_code, status, added_by_membership_id)
VALUES
  ('90400000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','90300000-0000-4000-8000-000000000001','CANCEL-G1','eligible','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('90400000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','90300000-0000-4000-8000-000000000002','CANCEL-G2','eligible','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('90400000-0000-4000-8000-000000000003','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','90300000-0000-4000-8000-000000000003','CANCEL-G3','eligible','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('90400000-0000-4000-8000-000000000004','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','90300000-0000-4000-8000-000000000004','CANCEL-G4','eligible','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('90400000-0000-4000-8000-000000000011','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90300000-0000-4000-8000-000000000001','POSTPONE-G1','eligible','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('90400000-0000-4000-8000-000000000012','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90300000-0000-4000-8000-000000000002','POSTPONE-G2','eligible','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('90400000-0000-4000-8000-000000000013','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90300000-0000-4000-8000-000000000003','POSTPONE-G3','eligible','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('90400000-0000-4000-8000-000000000014','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90300000-0000-4000-8000-000000000004','POSTPONE-G4','eligible','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');

INSERT INTO eogp.invitations
  (id, organization_id, event_id, participation_id, status, current_revision_number, issued_at, created_by_membership_id)
VALUES
  ('90700000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','90400000-0000-4000-8000-000000000001','active',1,clock_timestamp() - interval '2 days','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('90700000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','90400000-0000-4000-8000-000000000002','active',1,clock_timestamp() - interval '2 days','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('90700000-0000-4000-8000-000000000003','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','90400000-0000-4000-8000-000000000003','active',1,clock_timestamp() - interval '2 days','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('90700000-0000-4000-8000-000000000004','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','90400000-0000-4000-8000-000000000004','active',1,clock_timestamp() - interval '2 days','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('90700000-0000-4000-8000-000000000011','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90400000-0000-4000-8000-000000000011','active',1,clock_timestamp() - interval '2 days','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('90700000-0000-4000-8000-000000000012','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90400000-0000-4000-8000-000000000012','active',1,clock_timestamp() - interval '2 days','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('90700000-0000-4000-8000-000000000013','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90400000-0000-4000-8000-000000000013','active',1,clock_timestamp() - interval '2 days','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('90700000-0000-4000-8000-000000000014','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90400000-0000-4000-8000-000000000014','active',1,clock_timestamp() - interval '2 days','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');

INSERT INTO eogp.invitation_revisions
  (id, organization_id, event_id, invitation_id, revision_number, schedule_revision_id,
   rsvp_policy_revision_id, presentation_snapshot_ciphertext, issued_at, created_by_membership_id)
SELECT
  mapping.revision_id, '22222222-2222-4222-8222-222222222222', mapping.event_id,
  mapping.invitation_id, 1, mapping.schedule_id, mapping.policy_revision_id,
  decode('aabbcc','hex'), clock_timestamp() - interval '2 days',
  'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
FROM (VALUES
  ('90800000-0000-4000-8000-000000000001'::uuid,'90000000-0000-4000-8000-000000000001'::uuid,'90700000-0000-4000-8000-000000000001'::uuid,'90100000-0000-4000-8000-000000000001'::uuid,'90600000-0000-4000-8000-000000000001'::uuid),
  ('90800000-0000-4000-8000-000000000002'::uuid,'90000000-0000-4000-8000-000000000001'::uuid,'90700000-0000-4000-8000-000000000002'::uuid,'90100000-0000-4000-8000-000000000001'::uuid,'90600000-0000-4000-8000-000000000001'::uuid),
  ('90800000-0000-4000-8000-000000000003'::uuid,'90000000-0000-4000-8000-000000000001'::uuid,'90700000-0000-4000-8000-000000000003'::uuid,'90100000-0000-4000-8000-000000000001'::uuid,'90600000-0000-4000-8000-000000000001'::uuid),
  ('90800000-0000-4000-8000-000000000004'::uuid,'90000000-0000-4000-8000-000000000001'::uuid,'90700000-0000-4000-8000-000000000004'::uuid,'90100000-0000-4000-8000-000000000001'::uuid,'90600000-0000-4000-8000-000000000001'::uuid),
  ('90800000-0000-4000-8000-000000000011'::uuid,'90000000-0000-4000-8000-000000000002'::uuid,'90700000-0000-4000-8000-000000000011'::uuid,'90100000-0000-4000-8000-000000000002'::uuid,'90600000-0000-4000-8000-000000000002'::uuid),
  ('90800000-0000-4000-8000-000000000012'::uuid,'90000000-0000-4000-8000-000000000002'::uuid,'90700000-0000-4000-8000-000000000012'::uuid,'90100000-0000-4000-8000-000000000002'::uuid,'90600000-0000-4000-8000-000000000002'::uuid),
  ('90800000-0000-4000-8000-000000000013'::uuid,'90000000-0000-4000-8000-000000000002'::uuid,'90700000-0000-4000-8000-000000000013'::uuid,'90100000-0000-4000-8000-000000000002'::uuid,'90600000-0000-4000-8000-000000000002'::uuid),
  ('90800000-0000-4000-8000-000000000014'::uuid,'90000000-0000-4000-8000-000000000002'::uuid,'90700000-0000-4000-8000-000000000014'::uuid,'90100000-0000-4000-8000-000000000002'::uuid,'90600000-0000-4000-8000-000000000002'::uuid)
) AS mapping(revision_id,event_id,invitation_id,schedule_id,policy_revision_id);

INSERT INTO eogp.invitation_links
  (id, organization_id, event_id, invitation_id, invitation_revision_id,
   token_sha256, issued_at, expires_at)
SELECT
  mapping.link_id, '22222222-2222-4222-8222-222222222222', mapping.event_id,
  mapping.invitation_id, mapping.revision_id, mapping.token_hash,
  clock_timestamp() - interval '2 days', clock_timestamp() + interval '5 days'
FROM (VALUES
  ('90900000-0000-4000-8000-000000000001'::uuid,'90000000-0000-4000-8000-000000000001'::uuid,'90700000-0000-4000-8000-000000000001'::uuid,'90800000-0000-4000-8000-000000000001'::uuid,repeat('1',64)),
  ('90900000-0000-4000-8000-000000000002'::uuid,'90000000-0000-4000-8000-000000000001'::uuid,'90700000-0000-4000-8000-000000000002'::uuid,'90800000-0000-4000-8000-000000000002'::uuid,repeat('2',64)),
  ('90900000-0000-4000-8000-000000000003'::uuid,'90000000-0000-4000-8000-000000000001'::uuid,'90700000-0000-4000-8000-000000000003'::uuid,'90800000-0000-4000-8000-000000000003'::uuid,repeat('3',64)),
  ('90900000-0000-4000-8000-000000000004'::uuid,'90000000-0000-4000-8000-000000000001'::uuid,'90700000-0000-4000-8000-000000000004'::uuid,'90800000-0000-4000-8000-000000000004'::uuid,repeat('4',64)),
  ('90900000-0000-4000-8000-000000000011'::uuid,'90000000-0000-4000-8000-000000000002'::uuid,'90700000-0000-4000-8000-000000000011'::uuid,'90800000-0000-4000-8000-000000000011'::uuid,repeat('5',64)),
  ('90900000-0000-4000-8000-000000000012'::uuid,'90000000-0000-4000-8000-000000000002'::uuid,'90700000-0000-4000-8000-000000000012'::uuid,'90800000-0000-4000-8000-000000000012'::uuid,repeat('6',64)),
  ('90900000-0000-4000-8000-000000000013'::uuid,'90000000-0000-4000-8000-000000000002'::uuid,'90700000-0000-4000-8000-000000000013'::uuid,'90800000-0000-4000-8000-000000000013'::uuid,repeat('7',64)),
  ('90900000-0000-4000-8000-000000000014'::uuid,'90000000-0000-4000-8000-000000000002'::uuid,'90700000-0000-4000-8000-000000000014'::uuid,'90800000-0000-4000-8000-000000000014'::uuid,repeat('8',64))
) AS mapping(link_id,event_id,invitation_id,revision_id,token_hash);

INSERT INTO eogp.invitation_deliveries
  (id, organization_id, event_id, invitation_id, invitation_revision_id,
   channel, destination_ciphertext, destination_hash, status, sent_at, delivered_at, failed_at, failure_code)
VALUES
  ('91000000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','90700000-0000-4000-8000-000000000001','90800000-0000-4000-8000-000000000001','email',decode('01','hex'),repeat('a',64),'delivered',clock_timestamp() - interval '1 day',clock_timestamp() - interval '1 day',NULL,NULL),
  ('91000000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','90700000-0000-4000-8000-000000000002','90800000-0000-4000-8000-000000000002','email',decode('02','hex'),repeat('b',64),'queued',NULL,NULL,NULL,NULL),
  ('91000000-0000-4000-8000-000000000003','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','90700000-0000-4000-8000-000000000003','90800000-0000-4000-8000-000000000003','email',decode('03','hex'),repeat('c',64),'failed',NULL,NULL,clock_timestamp() - interval '1 hour','transient'),
  ('91000000-0000-4000-8000-000000000004','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','90700000-0000-4000-8000-000000000004','90800000-0000-4000-8000-000000000004','email',decode('04','hex'),repeat('d',64),'delivered',clock_timestamp() - interval '1 day',clock_timestamp() - interval '1 day',NULL,NULL),
  ('91000000-0000-4000-8000-000000000011','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90700000-0000-4000-8000-000000000011','90800000-0000-4000-8000-000000000011','email',decode('11','hex'),repeat('e',64),'delivered',clock_timestamp() - interval '1 day',clock_timestamp() - interval '1 day',NULL,NULL),
  ('91000000-0000-4000-8000-000000000012','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90700000-0000-4000-8000-000000000012','90800000-0000-4000-8000-000000000012','email',decode('12','hex'),repeat('f',64),'queued',NULL,NULL,NULL,NULL),
  ('91000000-0000-4000-8000-000000000013','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90700000-0000-4000-8000-000000000013','90800000-0000-4000-8000-000000000013','email',decode('13','hex'),repeat('0',64),'failed',NULL,NULL,clock_timestamp() - interval '1 hour','transient'),
  ('91000000-0000-4000-8000-000000000014','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90700000-0000-4000-8000-000000000014','90800000-0000-4000-8000-000000000014','email',decode('14','hex'),repeat('9',64),'delivered',clock_timestamp() - interval '1 day',clock_timestamp() - interval '1 day',NULL,NULL);

-- RSVP answers are independent history; one participation has no answer.
INSERT INTO eogp.rsvp_responses
  (id, organization_id, event_id, participation_id, invitation_id, invitation_revision_id,
   schedule_revision_id, sequence_number, response, source_channel, respondent_kind,
   received_at, actor_membership_id)
VALUES
  ('91100000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','90400000-0000-4000-8000-000000000001','90700000-0000-4000-8000-000000000001','90800000-0000-4000-8000-000000000001','90100000-0000-4000-8000-000000000001',1,'accepted','staff_entry','staff',clock_timestamp() - interval '1 day','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('91100000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','90400000-0000-4000-8000-000000000002','90700000-0000-4000-8000-000000000002','90800000-0000-4000-8000-000000000002','90100000-0000-4000-8000-000000000001',1,'tentative','staff_entry','staff',clock_timestamp() - interval '1 day','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('91100000-0000-4000-8000-000000000003','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','90400000-0000-4000-8000-000000000003','90700000-0000-4000-8000-000000000003','90800000-0000-4000-8000-000000000003','90100000-0000-4000-8000-000000000001',1,'declined','staff_entry','staff',clock_timestamp() - interval '1 day','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('91100000-0000-4000-8000-000000000011','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90400000-0000-4000-8000-000000000011','90700000-0000-4000-8000-000000000011','90800000-0000-4000-8000-000000000011','90100000-0000-4000-8000-000000000002',1,'accepted','staff_entry','staff',clock_timestamp() - interval '1 day','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('91100000-0000-4000-8000-000000000012','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90400000-0000-4000-8000-000000000012','90700000-0000-4000-8000-000000000012','90800000-0000-4000-8000-000000000012','90100000-0000-4000-8000-000000000002',1,'tentative','staff_entry','staff',clock_timestamp() - interval '1 day','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('91100000-0000-4000-8000-000000000013','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90400000-0000-4000-8000-000000000013','90700000-0000-4000-8000-000000000013','90800000-0000-4000-8000-000000000013','90100000-0000-4000-8000-000000000002',1,'declined','staff_entry','staff',clock_timestamp() - interval '1 day','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');

-- A completed first session has a real attendance record. Cancelling the
-- remaining session must not delete or rewrite it.
INSERT INTO eogp.attendance_records
  (id, organization_id, event_id, session_id, participation_id, attendance_action,
   attendance_state, actor_membership_id, reason)
VALUES
  ('91200000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','90200000-0000-4000-8000-000000000001','90400000-0000-4000-8000-000000000001','manual_arrival','present','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb','Historical attendance before later session cancellation');

INSERT INTO eogp.notification_templates (id, organization_id, code, purpose)
VALUES
  ('91300000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','CI-EVENT-CANCEL','event_cancellation'),
  ('91300000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','CI-EVENT-POSTPONE','event_postponement');

INSERT INTO eogp.notification_template_revisions
  (id, organization_id, template_id, revision_number, locale, subject_template,
   body_template, state, published_at)
VALUES
  ('91400000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','91300000-0000-4000-8000-000000000001',1,'en','Event cancelled','The event has been cancelled.','published',clock_timestamp()),
  ('91400000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','91300000-0000-4000-8000-000000000002',1,'en','Event postponed','The event has been postponed.','published',clock_timestamp());


-- CASE 1: organizer cancellation after invitations were broadcast and answers
-- were recorded. The organizer executes the change; the event trigger revokes
-- invitation links and suppresses only unsent invitation deliveries.
INSERT INTO eogp.event_change_requests
  (id, organization_id, event_id, change_kind, expected_event_revision, reason_code,
   public_message, status, initiated_by_organization_id, initiated_by_membership_id,
   submitted_at, resolved_at)
VALUES
  ('91500000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','cancel',1,'organizer_decision','The event will not take place.', 'executed','22222222-2222-4222-8222-222222222222','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',clock_timestamp(),clock_timestamp());

UPDATE eogp.events
   SET status = 'cancelled',
       current_revision = 2,
       updated_at = clock_timestamp()
 WHERE organization_id = '22222222-2222-4222-8222-222222222222'
   AND id = '90000000-0000-4000-8000-000000000001';

UPDATE eogp.event_sessions
   SET status = 'cancelled'
 WHERE organization_id = '22222222-2222-4222-8222-222222222222'
   AND event_id = '90000000-0000-4000-8000-000000000001'
   AND status IN ('planned','scheduled','active');

INSERT INTO eogp.event_decisions
  (id, organization_id, event_id, source_change_request_id, decision_kind,
   original_schedule_revision_id, reason_code, public_message,
   executed_by_organization_id, executed_by_membership_id)
VALUES
  ('91600000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','91500000-0000-4000-8000-000000000001','cancelled','90100000-0000-4000-8000-000000000001','organizer_decision','The event will not take place.','22222222-2222-4222-8222-222222222222','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');

INSERT INTO eogp.event_status_history
  (id, organization_id, event_id, previous_status, new_status, decision_id,
   actor_membership_id, reason_code)
VALUES
  ('91800000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','scheduled','cancelled','91600000-0000-4000-8000-000000000001','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb','organizer_decision');

INSERT INTO eogp.event_decision_sessions
  (organization_id, event_id, decision_id, session_id, outcome)
VALUES
  ('22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','91600000-0000-4000-8000-000000000001','90200000-0000-4000-8000-000000000001','unaffected'),
  ('22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','91600000-0000-4000-8000-000000000001','90200000-0000-4000-8000-000000000002','cancelled');

INSERT INTO eogp.event_notification_campaigns
  (id, organization_id, event_id, event_decision_id, purpose, audience_kind,
   status, template_revision_id, audience_rules_snapshot, created_by_organization_id,
   created_by_membership_id)
VALUES
  ('92000000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','91600000-0000-4000-8000-000000000001','event_cancellation','all_active_invitees','draft','91400000-0000-4000-8000-000000000001',
   '{"audience":"all_active_invitees","resolvedAt":"cancellation-confirmation","includes":["accepted","tentative","declined","no_response"],"invitationStatus":["active"]}'::jsonb,
   '22222222-2222-4222-8222-222222222222','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');

INSERT INTO eogp.event_notification_recipients
  (id, organization_id, event_id, campaign_id, participation_id, invitation_id,
   qualification_reason, channel, destination_ciphertext, destination_hash)
VALUES
  ('92100000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001','90400000-0000-4000-8000-000000000001','90700000-0000-4000-8000-000000000001','active_invitation_accepted','email',decode('21','hex'),repeat('a',64)),
  ('92100000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001','90400000-0000-4000-8000-000000000002','90700000-0000-4000-8000-000000000002','active_invitation_tentative','email',decode('22','hex'),repeat('b',64)),
  ('92100000-0000-4000-8000-000000000003','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001','90400000-0000-4000-8000-000000000003','90700000-0000-4000-8000-000000000003','active_invitation_declined','email',decode('23','hex'),repeat('c',64)),
  ('92100000-0000-4000-8000-000000000004','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001','90400000-0000-4000-8000-000000000004','90700000-0000-4000-8000-000000000004','active_invitation_no_response','email',decode('24','hex'),repeat('d',64));

UPDATE eogp.event_notification_campaigns
   SET status = 'queued',
       recipient_count = 4,
       confirmed_by_organization_id = '22222222-2222-4222-8222-222222222222',
       confirmed_by_membership_id = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
       confirmed_at = clock_timestamp()
 WHERE organization_id = '22222222-2222-4222-8222-222222222222'
   AND id = '92000000-0000-4000-8000-000000000001';

INSERT INTO eogp.event_notification_delivery_attempts
  (id, organization_id, campaign_id, recipient_id, attempt_number, status)
VALUES
  ('92200000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','92000000-0000-4000-8000-000000000001','92100000-0000-4000-8000-000000000001',1,'queued');

DO $cancel_assertions$
DECLARE
  v_count integer;
  v_rejected boolean;
  v_status text;
BEGIN
  SELECT status INTO v_status
    FROM eogp.events
   WHERE organization_id = '22222222-2222-4222-8222-222222222222'
     AND id = '90000000-0000-4000-8000-000000000001';
  IF v_status <> 'cancelled' THEN
    RAISE EXCEPTION 'organizer cancellation did not set the event lifecycle state';
  END IF;

  IF (SELECT status FROM eogp.event_sessions WHERE id = '90200000-0000-4000-8000-000000000001') <> 'completed'
     OR (SELECT status FROM eogp.event_sessions WHERE id = '90200000-0000-4000-8000-000000000002') <> 'cancelled' THEN
    RAISE EXCEPTION 'cancellation rewrote completed session history or failed to cancel the future session';
  END IF;

  SELECT count(*) INTO v_count
    FROM eogp.rsvp_responses
   WHERE organization_id = '22222222-2222-4222-8222-222222222222'
     AND event_id = '90000000-0000-4000-8000-000000000001';
  IF v_count <> 3
     OR (SELECT count(*) FROM eogp.rsvp_responses WHERE event_id = '90000000-0000-4000-8000-000000000001' AND response = 'accepted') <> 1
     OR (SELECT count(*) FROM eogp.rsvp_responses WHERE event_id = '90000000-0000-4000-8000-000000000001' AND response = 'tentative') <> 1
     OR (SELECT count(*) FROM eogp.rsvp_responses WHERE event_id = '90000000-0000-4000-8000-000000000001' AND response = 'declined') <> 1 THEN
    RAISE EXCEPTION 'cancellation erased or reinterpreted existing RSVP history';
  END IF;

  SELECT count(*) INTO v_count
    FROM eogp.attendance_records
   WHERE organization_id = '22222222-2222-4222-8222-222222222222'
     AND event_id = '90000000-0000-4000-8000-000000000001'
     AND id = '91200000-0000-4000-8000-000000000001';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'cancellation erased a historical attendance record';
  END IF;

  IF (SELECT status FROM eogp.invitation_deliveries WHERE id = '91000000-0000-4000-8000-000000000001') <> 'delivered'
     OR (SELECT status FROM eogp.invitation_deliveries WHERE id = '91000000-0000-4000-8000-000000000002') <> 'suppressed'
     OR (SELECT status FROM eogp.invitation_deliveries WHERE id = '91000000-0000-4000-8000-000000000003') <> 'suppressed'
     OR (SELECT status FROM eogp.invitation_deliveries WHERE id = '91000000-0000-4000-8000-000000000004') <> 'delivered' THEN
    RAISE EXCEPTION 'cancellation did not suppress only queued/failed invitation deliveries';
  END IF;

  SELECT count(*) INTO v_count
    FROM eogp.invitation_links
   WHERE organization_id = '22222222-2222-4222-8222-222222222222'
     AND event_id = '90000000-0000-4000-8000-000000000001'
     AND revoked_at IS NOT NULL;
  IF v_count <> 4 THEN
    RAISE EXCEPTION 'cancellation did not revoke all existing invitation links';
  END IF;

  SELECT count(*) INTO v_count
    FROM eogp.event_notification_recipients
   WHERE organization_id = '22222222-2222-4222-8222-222222222222'
     AND campaign_id = '92000000-0000-4000-8000-000000000001';
  IF v_count <> 4 THEN
    RAISE EXCEPTION 'all-active-invitees cancellation audience must include accepted, tentative, declined and unanswered invitees; got %',v_count;
  END IF;

  IF (SELECT status FROM eogp.event_notification_delivery_attempts WHERE id = '92200000-0000-4000-8000-000000000001') <> 'queued' THEN
    RAISE EXCEPTION 'cancellation workflow suppressed its own cancellation-notice delivery';
  END IF;

  -- Once the event is cancelled, no new invitation, invitation link,
  -- delivery/retry or RSVP response may be created.
  v_rejected := false;
  BEGIN
    INSERT INTO eogp.invitations
      (id, organization_id, event_id, participation_id, created_by_membership_id)
    VALUES
      ('90700000-0000-4000-8000-000000000099','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','90400000-0000-4000-8000-000000000004','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'new invitation was accepted after event cancellation'; END IF;

  v_rejected := false;
  BEGIN
    INSERT INTO eogp.invitation_links
      (id, organization_id, event_id, invitation_id, invitation_revision_id,
       token_sha256, issued_at, expires_at)
    VALUES
      ('90900000-0000-4000-8000-000000000099','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','90700000-0000-4000-8000-000000000001','90800000-0000-4000-8000-000000000001',repeat('f',64),clock_timestamp(),clock_timestamp()+interval '1 day');
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'new invitation link was accepted after event cancellation'; END IF;

  v_rejected := false;
  BEGIN
    INSERT INTO eogp.invitation_deliveries
      (id, organization_id, event_id, invitation_id, invitation_revision_id,
       channel, destination_ciphertext, destination_hash, status)
    VALUES
      ('91000000-0000-4000-8000-000000000099','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','90700000-0000-4000-8000-000000000001','90800000-0000-4000-8000-000000000001','email',decode('ff','hex'),repeat('f',64),'queued');
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'new invitation delivery was queued after event cancellation'; END IF;

  v_rejected := false;
  BEGIN
    INSERT INTO eogp.rsvp_responses
      (id, organization_id, event_id, participation_id, schedule_revision_id,
       sequence_number, response, source_channel, respondent_kind, received_at, actor_membership_id)
    VALUES
      ('91100000-0000-4000-8000-000000000099','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','90400000-0000-4000-8000-000000000004','90100000-0000-4000-8000-000000000001',1,'accepted','staff_entry','staff',clock_timestamp()-interval '1 second','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'new RSVP response was accepted after event cancellation'; END IF;

  v_rejected := false;
  BEGIN
    UPDATE eogp.invitation_deliveries
       SET status = 'queued'
     WHERE id = '91000000-0000-4000-8000-000000000002';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'suppressed invitation delivery was re-queued after event cancellation'; END IF;

  v_rejected := false;
  BEGIN
    UPDATE eogp.event_notification_campaigns
       SET audience_rules_snapshot = '{"changed":true}'::jsonb
     WHERE id = '92000000-0000-4000-8000-000000000001';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'queued cancellation audience snapshot was mutable'; END IF;

  v_rejected := false;
  BEGIN
    INSERT INTO eogp.event_notification_recipients
      (id, organization_id, event_id, campaign_id, participation_id, invitation_id,
       qualification_reason, channel, destination_ciphertext, destination_hash)
    VALUES
      ('92100000-0000-4000-8000-000000000099','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','92000000-0000-4000-8000-000000000001','90400000-0000-4000-8000-000000000004','90700000-0000-4000-8000-000000000004','late_added_recipient','email',decode('99','hex'),repeat('e',64));
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'recipient was added after the campaign audience was queued'; END IF;

  v_rejected := false;
  BEGIN
    INSERT INTO eogp.event_notification_campaigns
      (id, organization_id, event_id, event_decision_id, purpose, audience_kind,
       template_revision_id, audience_rules_snapshot, created_by_organization_id,
       created_by_membership_id)
    VALUES
      ('92000000-0000-4000-8000-000000000099','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','91600000-0000-4000-8000-000000000001','event_postponement','all_active_invitees','91400000-0000-4000-8000-000000000002','{}'::jsonb,'22222222-2222-4222-8222-222222222222','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');
  EXCEPTION WHEN SQLSTATE '23514' THEN
    v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'postponement notification was attached to an event-cancellation decision'; END IF;

  v_rejected := false;
  BEGIN
    INSERT INTO eogp.event_decisions
      (id, organization_id, event_id, source_change_request_id, decision_kind,
       original_schedule_revision_id, reason_code, executed_by_organization_id,
       executed_by_membership_id)
    VALUES
      ('91600000-0000-4000-8000-000000000099','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000001','91500000-0000-4000-8000-000000000001','postponed','90100000-0000-4000-8000-000000000001','wrong_decision','22222222-2222-4222-8222-222222222222','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');
  EXCEPTION WHEN SQLSTATE '23514' THEN
    v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'event decision kind was not checked against its request'; END IF;
END;
$cancel_assertions$;


-- CASE 2: a provider sends a booking-disruption notice. This is not an event
-- cancellation or postponement: the organizer event and guest audience remain
-- unchanged until the organizer separately executes an event change.
INSERT INTO eogp.event_disruption_resolutions
  (id, organization_id, event_id, source_provider_organization_id,
   source_booking_notice_id, source_notice_snapshot, resolution_kind, status,
   grant_owner_organization_id, collaboration_grant_id)
VALUES
  ('91900000-0000-4000-8000-000000000001','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','11111111-1111-4111-8111-111111111111','93000000-0000-4000-8000-000000000099','{"bookingReference":"CI-PROVIDER-NOTICE","affectedWindow":{"startsAt":"2030-11-11T08:00:00Z","endsAt":"2030-11-11T17:00:00Z"},"disruptionCategory":"venue_unavailability"}'::jsonb,'unresolved','received','11111111-1111-4111-8111-111111111111','60000000-0000-4000-8000-000000000001');

DO $provider_notice_assertions$
DECLARE
  v_status text;
  v_count integer;
BEGIN
  SELECT status INTO v_status
    FROM eogp.events
   WHERE organization_id = '22222222-2222-4222-8222-222222222222'
     AND id = '90000000-0000-4000-8000-000000000002';
  SELECT count(*) INTO v_count
    FROM eogp.event_decisions
   WHERE organization_id = '22222222-2222-4222-8222-222222222222'
     AND event_id = '90000000-0000-4000-8000-000000000002';
  IF v_status <> 'scheduled' OR v_count <> 0
     OR EXISTS (
       SELECT 1 FROM eogp.event_notification_campaigns
        WHERE organization_id = '22222222-2222-4222-8222-222222222222'
          AND event_id = '90000000-0000-4000-8000-000000000002'
     ) THEN
    RAISE EXCEPTION 'provider booking notice automatically changed/cancelled the organizer event or sent guest notifications';
  END IF;
END;
$provider_notice_assertions$;


-- The organizer separately decides to postpone, pins a replacement schedule,
-- notifies only accepted/tentative invitees, and preserves old RSVP responses.
INSERT INTO eogp.event_change_requests
  (id, organization_id, event_id, change_kind, expected_event_revision, reason_code,
   public_message, status, initiated_by_organization_id, initiated_by_membership_id,
   submitted_at, resolved_at)
VALUES
  ('91500000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','postpone',1,'venue_disruption_reviewed','The event is postponed; a new date is being arranged.','executed','22222222-2222-4222-8222-222222222222','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',clock_timestamp(),clock_timestamp());

UPDATE eogp.events
   SET status = 'postponed',
       current_revision = 2,
       updated_at = clock_timestamp()
 WHERE organization_id = '22222222-2222-4222-8222-222222222222'
   AND id = '90000000-0000-4000-8000-000000000002';

INSERT INTO eogp.event_decisions
  (id, organization_id, event_id, source_change_request_id, decision_kind,
   original_schedule_revision_id, replacement_schedule_revision_id, reason_code,
   public_message, executed_by_organization_id, executed_by_membership_id)
VALUES
  ('91600000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','91500000-0000-4000-8000-000000000002','postponed','90100000-0000-4000-8000-000000000002','90100000-0000-4000-8000-000000000003','venue_disruption_reviewed','The event is postponed; a new date is being arranged.','22222222-2222-4222-8222-222222222222','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');

INSERT INTO eogp.event_status_history
  (id, organization_id, event_id, previous_status, new_status, decision_id,
   actor_membership_id, reason_code)
VALUES
  ('91800000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','scheduled','postponed','91600000-0000-4000-8000-000000000002','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb','venue_disruption_reviewed');

INSERT INTO eogp.event_decision_sessions
  (organization_id, event_id, decision_id, session_id, outcome)
VALUES
  ('22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','91600000-0000-4000-8000-000000000002','90200000-0000-4000-8000-000000000003','postponed');

-- Reissue only the accepted/tentative invitees against the replacement schedule.
INSERT INTO eogp.invitation_revisions
  (id, organization_id, event_id, invitation_id, revision_number, schedule_revision_id,
   rsvp_policy_revision_id, presentation_snapshot_ciphertext, issued_at, created_by_membership_id)
VALUES
  ('90800000-0000-4000-8000-000000000021','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90700000-0000-4000-8000-000000000011',2,'90100000-0000-4000-8000-000000000003','90600000-0000-4000-8000-000000000002',decode('bbccdd','hex'),clock_timestamp(),'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'),
  ('90800000-0000-4000-8000-000000000022','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90700000-0000-4000-8000-000000000012',2,'90100000-0000-4000-8000-000000000003','90600000-0000-4000-8000-000000000002',decode('bbccde','hex'),clock_timestamp(),'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');

UPDATE eogp.invitations
   SET current_revision_number = 2
 WHERE organization_id = '22222222-2222-4222-8222-222222222222'
   AND id IN ('90700000-0000-4000-8000-000000000011','90700000-0000-4000-8000-000000000012');

INSERT INTO eogp.invitation_links
  (id, organization_id, event_id, invitation_id, invitation_revision_id,
   token_sha256, issued_at, expires_at)
VALUES
  ('90900000-0000-4000-8000-000000000021','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90700000-0000-4000-8000-000000000011','90800000-0000-4000-8000-000000000021',repeat('a',64),clock_timestamp(),clock_timestamp()+interval '5 days'),
  ('90900000-0000-4000-8000-000000000022','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90700000-0000-4000-8000-000000000012','90800000-0000-4000-8000-000000000022',repeat('b',64),clock_timestamp(),clock_timestamp()+interval '5 days');

INSERT INTO eogp.invitation_deliveries
  (id, organization_id, event_id, invitation_id, invitation_revision_id,
   channel, destination_ciphertext, destination_hash, status)
VALUES
  ('91000000-0000-4000-8000-000000000021','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90700000-0000-4000-8000-000000000011','90800000-0000-4000-8000-000000000021','email',decode('21','hex'),repeat('1',64),'queued'),
  ('91000000-0000-4000-8000-000000000022','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90700000-0000-4000-8000-000000000012','90800000-0000-4000-8000-000000000022','email',decode('22','hex'),repeat('2',64),'queued');

-- A guest can respond to the replacement schedule; old response rows remain
-- attached to the original schedule and are not rewritten.
INSERT INTO eogp.rsvp_responses
  (id, organization_id, event_id, participation_id, invitation_id, invitation_revision_id,
   schedule_revision_id, sequence_number, response, source_channel, respondent_kind,
   received_at, invitation_link_id)
VALUES
  ('91100000-0000-4000-8000-000000000021','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90400000-0000-4000-8000-000000000011','90700000-0000-4000-8000-000000000011','90800000-0000-4000-8000-000000000021','90100000-0000-4000-8000-000000000003',2,'tentative','invitation_link','guest',clock_timestamp()-interval '1 second','90900000-0000-4000-8000-000000000021');

INSERT INTO eogp.event_notification_campaigns
  (id, organization_id, event_id, event_decision_id, purpose, audience_kind,
   status, template_revision_id, audience_rules_snapshot, created_by_organization_id,
   created_by_membership_id)
VALUES
  ('92000000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','91600000-0000-4000-8000-000000000002','event_postponement','accepted_tentative','draft','91400000-0000-4000-8000-000000000002',
   '{"audience":"accepted_tentative","basedOnScheduleRevisionId":"90100000-0000-4000-8000-000000000002","snapshotSemantics":"fixed_at_confirmation"}'::jsonb,
   '22222222-2222-4222-8222-222222222222','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');

INSERT INTO eogp.event_notification_recipients
  (id, organization_id, event_id, campaign_id, participation_id, invitation_id,
   qualification_reason, channel, destination_ciphertext, destination_hash)
VALUES
  ('92100000-0000-4000-8000-000000000011','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','92000000-0000-4000-8000-000000000002','90400000-0000-4000-8000-000000000011','90700000-0000-4000-8000-000000000011','latest_response_accepted','email',decode('31','hex'),repeat('3',64)),
  ('92100000-0000-4000-8000-000000000012','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','92000000-0000-4000-8000-000000000002','90400000-0000-4000-8000-000000000012','90700000-0000-4000-8000-000000000012','latest_response_tentative','email',decode('32','hex'),repeat('4',64));

UPDATE eogp.event_notification_campaigns
   SET status = 'queued',
       recipient_count = 2,
       confirmed_by_organization_id = '22222222-2222-4222-8222-222222222222',
       confirmed_by_membership_id = 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb',
       confirmed_at = clock_timestamp()
 WHERE organization_id = '22222222-2222-4222-8222-222222222222'
   AND id = '92000000-0000-4000-8000-000000000002';

DO $postpone_assertions$
DECLARE
  v_count integer;
  v_rejected boolean;
BEGIN
  IF (SELECT status FROM eogp.events WHERE id = '90000000-0000-4000-8000-000000000002') <> 'postponed' THEN
    RAISE EXCEPTION 'organizer postponement did not update event status';
  END IF;
  IF (SELECT status FROM eogp.event_sessions WHERE id = '90200000-0000-4000-8000-000000000003') <> 'scheduled' THEN
    RAISE EXCEPTION 'postponement incorrectly cancelled the event session';
  END IF;
  IF (SELECT outcome FROM eogp.event_decision_sessions WHERE decision_id = '91600000-0000-4000-8000-000000000002' AND session_id = '90200000-0000-4000-8000-000000000003') <> 'postponed' THEN
    RAISE EXCEPTION 'postponed session decision outcome was not retained';
  END IF;

  SELECT count(*) INTO v_count
    FROM eogp.invitation_links
   WHERE event_id = '90000000-0000-4000-8000-000000000002'
     AND id IN ('90900000-0000-4000-8000-000000000011','90900000-0000-4000-8000-000000000012','90900000-0000-4000-8000-000000000013','90900000-0000-4000-8000-000000000014')
     AND revoked_at IS NOT NULL;
  IF v_count <> 4 THEN RAISE EXCEPTION 'old schedule invitation links were not revoked'; END IF;

  IF (SELECT status FROM eogp.invitation_deliveries WHERE id = '91000000-0000-4000-8000-000000000011') <> 'delivered'
     OR (SELECT status FROM eogp.invitation_deliveries WHERE id = '91000000-0000-4000-8000-000000000012') <> 'suppressed'
     OR (SELECT status FROM eogp.invitation_deliveries WHERE id = '91000000-0000-4000-8000-000000000013') <> 'suppressed'
     OR (SELECT status FROM eogp.invitation_deliveries WHERE id = '91000000-0000-4000-8000-000000000021') <> 'queued' THEN
    RAISE EXCEPTION 'postponement did not retire prior-schedule sends while retaining new-schedule sends';
  END IF;

  IF (SELECT count(*) FROM eogp.rsvp_responses WHERE event_id = '90000000-0000-4000-8000-000000000002' AND participation_id = '90400000-0000-4000-8000-000000000011') <> 2
     OR (SELECT response FROM eogp.rsvp_responses WHERE id = '91100000-0000-4000-8000-000000000011') <> 'accepted'
     OR (SELECT schedule_revision_id FROM eogp.rsvp_responses WHERE id = '91100000-0000-4000-8000-000000000011') <> '90100000-0000-4000-8000-000000000002'
     OR (SELECT response FROM eogp.rsvp_responses WHERE id = '91100000-0000-4000-8000-000000000021') <> 'tentative'
     OR (SELECT schedule_revision_id FROM eogp.rsvp_responses WHERE id = '91100000-0000-4000-8000-000000000021') <> '90100000-0000-4000-8000-000000000003' THEN
    RAISE EXCEPTION 'postponement rewrote an old RSVP or failed to append the replacement-schedule response';
  END IF;

  SELECT count(*) INTO v_count
    FROM eogp.event_notification_recipients
   WHERE campaign_id = '92000000-0000-4000-8000-000000000002';
  IF v_count <> 2
     OR EXISTS (
       SELECT 1 FROM eogp.event_notification_recipients
        WHERE campaign_id = '92000000-0000-4000-8000-000000000002'
          AND participation_id IN ('90400000-0000-4000-8000-000000000013','90400000-0000-4000-8000-000000000014')
     ) THEN
    RAISE EXCEPTION 'accepted/tentative postponement audience included declined or unanswered guests';
  END IF;

  v_rejected := false;
  BEGIN
    INSERT INTO eogp.rsvp_responses
      (id, organization_id, event_id, participation_id, schedule_revision_id,
       sequence_number, response, source_channel, respondent_kind, received_at,
       actor_membership_id)
    VALUES
      ('91100000-0000-4000-8000-000000000099','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90400000-0000-4000-8000-000000000014','90100000-0000-4000-8000-000000000002',1,'accepted','staff_entry','staff',clock_timestamp()-interval '1 second','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'RSVP was accepted against the superseded schedule after postponement'; END IF;

  v_rejected := false;
  BEGIN
    INSERT INTO eogp.rsvp_responses
      (id, organization_id, event_id, participation_id, invitation_id, invitation_revision_id,
       schedule_revision_id, sequence_number, response, source_channel, respondent_kind,
       received_at, invitation_link_id)
    VALUES
      ('91100000-0000-4000-8000-000000000098','22222222-2222-4222-8222-222222222222','90000000-0000-4000-8000-000000000002','90400000-0000-4000-8000-000000000011','90700000-0000-4000-8000-000000000011','90800000-0000-4000-8000-000000000011','90100000-0000-4000-8000-000000000002',2,'accepted','invitation_link','guest',clock_timestamp()-interval '1 second','90900000-0000-4000-8000-000000000011');
  EXCEPTION WHEN SQLSTATE '55000' THEN
    v_rejected := true;
  END;
  IF NOT v_rejected THEN RAISE EXCEPTION 'revoked old invitation link accepted an RSVP'; END IF;
END;
$postpone_assertions$;

ROLLBACK;
