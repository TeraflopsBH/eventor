\set ON_ERROR_STOP on

BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','97000000-0000-4000-8000-000000000001',true);

-- Isolated pre-000077 tenant and invitation. The bearer envelope deliberately
-- exists only on invitation_links, matching the already-published 000076 schema.
INSERT INTO eogp.organizations (id,slug,name,operating_profile)
VALUES (
  '97000000-0000-4000-8000-000000000001',
  'ci-forward-migration',
  'CI Forward Migration',
  'event_organizer'
);

INSERT INTO eogp.organization_memberships (id,organization_id,user_id,status,joined_at)
VALUES (
  '97000000-0000-4000-8000-000000000002',
  '97000000-0000-4000-8000-000000000001',
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  'active',clock_timestamp()
);

INSERT INTO eogp.events (
  id,organization_id,event_code,title,status,current_revision,created_by_membership_id
) VALUES (
  '97000000-0000-4000-8000-000000000003',
  '97000000-0000-4000-8000-000000000001',
  'CI-FORWARD-MIGRATION',
  'Invitation capability forward migration',
  'scheduled',1,
  '97000000-0000-4000-8000-000000000002'
);

INSERT INTO eogp.event_schedule_revisions (
  id,organization_id,event_id,revision_number,schedule_kind,starts_at,ends_at,
  timezone_name,venue_summary,schedule_snapshot,material_change,
  reconfirmation_policy,created_by_membership_id
) VALUES (
  '97000000-0000-4000-8000-000000000006',
  '97000000-0000-4000-8000-000000000001',
  '97000000-0000-4000-8000-000000000003',
  1,'original','2099-03-10 08:00+00','2099-03-10 17:00+00',
  'Europe/Sarajevo','{}'::jsonb,'{"revision":1}'::jsonb,
  false,'none','97000000-0000-4000-8000-000000000002'
);

INSERT INTO eogp.persons (
  id,organization_id,first_name,last_name,display_name,created_by_membership_id
) VALUES (
  '97000000-0000-4000-8000-000000000004',
  '97000000-0000-4000-8000-000000000001',
  'Forward','Migration','Forward Migration',
  '97000000-0000-4000-8000-000000000002'
);

INSERT INTO eogp.event_participations (
  id,organization_id,event_id,person_id,status,added_by_membership_id
) VALUES (
  '97000000-0000-4000-8000-000000000005',
  '97000000-0000-4000-8000-000000000001',
  '97000000-0000-4000-8000-000000000003',
  '97000000-0000-4000-8000-000000000004',
  'eligible','97000000-0000-4000-8000-000000000002'
);

INSERT INTO eogp.rsvp_policies (id,organization_id,event_id,code,name)
VALUES (
  '97000000-0000-4000-8000-000000000007',
  '97000000-0000-4000-8000-000000000001',
  '97000000-0000-4000-8000-000000000003',
  'CI_FORWARD_MIGRATION','CI forward migration'
);

INSERT INTO eogp.rsvp_policy_revisions (
  id,organization_id,event_id,policy_id,revision_number,event_timezone,state,published_at
) VALUES (
  '97000000-0000-4000-8000-000000000008',
  '97000000-0000-4000-8000-000000000001',
  '97000000-0000-4000-8000-000000000003',
  '97000000-0000-4000-8000-000000000007',
  1,'Europe/Sarajevo','published',clock_timestamp()
);

INSERT INTO eogp.invitations (
  id,organization_id,event_id,participation_id,status,current_revision_number,
  issued_at,created_by_membership_id
) VALUES (
  '97000000-0000-4000-8000-000000000009',
  '97000000-0000-4000-8000-000000000001',
  '97000000-0000-4000-8000-000000000003',
  '97000000-0000-4000-8000-000000000005',
  'active',1,clock_timestamp(),
  '97000000-0000-4000-8000-000000000002'
);

INSERT INTO eogp.invitation_revisions (
  id,organization_id,event_id,invitation_id,revision_number,
  schedule_revision_id,rsvp_policy_revision_id,locale,
  presentation_snapshot_ciphertext,issued_at,created_by_membership_id
) VALUES (
  '97000000-0000-4000-8000-000000000010',
  '97000000-0000-4000-8000-000000000001',
  '97000000-0000-4000-8000-000000000003',
  '97000000-0000-4000-8000-000000000009',
  1,
  '97000000-0000-4000-8000-000000000006',
  '97000000-0000-4000-8000-000000000008',
  'en',decode('455631010203','hex'),clock_timestamp(),
  '97000000-0000-4000-8000-000000000002'
);

INSERT INTO eogp.invitation_deliveries (
  id,organization_id,event_id,invitation_id,invitation_revision_id,
  channel,destination_ciphertext,destination_hash,status,capability_ciphertext
) VALUES (
  '97000000-0000-4000-8000-000000000012',
  '97000000-0000-4000-8000-000000000001',
  '97000000-0000-4000-8000-000000000003',
  '97000000-0000-4000-8000-000000000009',
  '97000000-0000-4000-8000-000000000010',
  'email',decode('45435031010203','hex'),repeat('f',64),'queued',NULL
);

INSERT INTO eogp.invitation_links (
  id,organization_id,event_id,invitation_id,invitation_revision_id,
  token_sha256,expires_at,capability_ciphertext
) VALUES (
  '97000000-0000-4000-8000-000000000011',
  '97000000-0000-4000-8000-000000000001',
  '97000000-0000-4000-8000-000000000003',
  '97000000-0000-4000-8000-000000000009',
  '97000000-0000-4000-8000-000000000010',
  repeat('9',64),clock_timestamp()+interval '1 day',
  decode('45435031' || repeat('aa',32),'hex')
);

COMMIT;
