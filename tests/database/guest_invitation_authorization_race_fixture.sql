\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);

-- The notification worker fixture deliberately leaves its event cancelled.
-- This isolated race fixture temporarily restores it so SMTP authorization
-- can validate the live event capability; the test script restores cancelled.
UPDATE eogp.events
   SET status='scheduled',updated_at=clock_timestamp()
 WHERE organization_id='22222222-2222-4222-8222-222222222222'
   AND id='94000000-0000-4000-8000-000000000001';

INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
VALUES (
 '22222222-2222-4222-8222-222222222222',
 '93900000-0000-4000-8000-000000000001',
 'invitation.manage'
)
ON CONFLICT DO NOTHING;

INSERT INTO eogp.rsvp_policies(id,organization_id,event_id,code,name)
VALUES (
 '96300000-0000-4000-8000-000000000001',
 '22222222-2222-4222-8222-222222222222',
 '94000000-0000-4000-8000-000000000001',
 'CI_INVITATION_AUTH_RACE','CI invitation authorization race'
);

INSERT INTO eogp.rsvp_policy_revisions(
 id,organization_id,event_id,policy_id,revision_number,event_timezone,state,published_at,
 allowed_responses,response_change_allowed,response_deadline,late_change_requires_staff
) VALUES (
 '96400000-0000-4000-8000-000000000001',
 '22222222-2222-4222-8222-222222222222',
 '94000000-0000-4000-8000-000000000001',
 '96300000-0000-4000-8000-000000000001',
 1,'Europe/Sarajevo','published',clock_timestamp(),
 '["accepted"]'::jsonb,true,NULL,false
);

INSERT INTO eogp.invitation_revisions(
 id,organization_id,event_id,invitation_id,revision_number,
 schedule_revision_id,rsvp_policy_revision_id,locale,
 presentation_snapshot_ciphertext,issued_at,created_by_membership_id
) VALUES (
 '96500000-0000-4000-8000-000000000001',
 '22222222-2222-4222-8222-222222222222',
 '94000000-0000-4000-8000-000000000001',
 '94500000-0000-4000-8000-000000000005',
 1,'94100000-0000-4000-8000-000000000001',
 '96400000-0000-4000-8000-000000000001',
 'en',decode('455631010203','hex'),clock_timestamp(),
 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
);

INSERT INTO eogp.invitation_links(
 id,organization_id,event_id,invitation_id,invitation_revision_id,
 token_sha256,expires_at
) VALUES (
 '96600000-0000-4000-8000-000000000001',
 '22222222-2222-4222-8222-222222222222',
 '94000000-0000-4000-8000-000000000001',
 '94500000-0000-4000-8000-000000000005',
 '96500000-0000-4000-8000-000000000001',
 repeat('f',64),clock_timestamp()+interval '2 hours'
);

INSERT INTO eogp.invitation_deliveries(
 id,organization_id,event_id,invitation_id,invitation_revision_id,
 channel,destination_ciphertext,destination_hash,status
) VALUES (
 '96700000-0000-4000-8000-000000000001',
 '22222222-2222-4222-8222-222222222222',
 '94000000-0000-4000-8000-000000000001',
 '94500000-0000-4000-8000-000000000005',
 '96500000-0000-4000-8000-000000000001',
 'email',decode('45435031010203','hex'),repeat('d',64),'queued'
);

UPDATE eogp.invitation_deliveries
   SET status='sending',attempt_count=1,
       lease_expires_at=clock_timestamp()+interval '5 minutes'
 WHERE organization_id='22222222-2222-4222-8222-222222222222'
   AND id='96700000-0000-4000-8000-000000000001';

COMMIT;
