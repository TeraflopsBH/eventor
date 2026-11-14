-- Persistent fixture for the worker-role expired-lease recovery regression.
BEGIN;
SET LOCAL ROLE eventor_owner;
SET LOCAL app.organization_id='22222222-2222-4222-8222-222222222222';

-- The shared worker fixture marks this event cancelled. Temporarily restore
-- its lifecycle state so the invitation revision guard accepts this test row.
UPDATE eogp.events
   SET status='scheduled',updated_at=clock_timestamp()
 WHERE organization_id='22222222-2222-4222-8222-222222222222'
   AND id='94000000-0000-4000-8000-000000000001';

INSERT INTO eogp.rsvp_policies (id,organization_id,event_id,code,name)
VALUES (
 '95700000-0000-4000-8000-000000000001',
 '22222222-2222-4222-8222-222222222222',
 '94000000-0000-4000-8000-000000000001',
 'CI_EXPIRED_GUEST_LEASE','CI expired guest lease'
);

INSERT INTO eogp.rsvp_policy_revisions (
 id,organization_id,event_id,policy_id,revision_number,event_timezone,state,published_at
) VALUES (
 '95800000-0000-4000-8000-000000000001',
 '22222222-2222-4222-8222-222222222222',
 '94000000-0000-4000-8000-000000000001',
 '95700000-0000-4000-8000-000000000001',
 1,'Europe/Sarajevo','published',clock_timestamp()
);

INSERT INTO eogp.invitation_revisions (
 id,organization_id,event_id,invitation_id,revision_number,
 schedule_revision_id,rsvp_policy_revision_id,locale,
 presentation_snapshot_ciphertext,issued_at,created_by_membership_id
) VALUES (
 '95900000-0000-4000-8000-000000000001',
 '22222222-2222-4222-8222-222222222222',
 '94000000-0000-4000-8000-000000000001',
 '94500000-0000-4000-8000-000000000001',
 1,'94100000-0000-4000-8000-000000000001',
 '95800000-0000-4000-8000-000000000001',
 'en',decode('455631010203','hex'),clock_timestamp(),
 'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
);

INSERT INTO eogp.invitation_deliveries (
 id,organization_id,event_id,invitation_id,invitation_revision_id,
 channel,destination_ciphertext,destination_hash,status
) VALUES (
 '96000000-0000-4000-8000-000000000001',
 '22222222-2222-4222-8222-222222222222',
 '94000000-0000-4000-8000-000000000001',
 '94500000-0000-4000-8000-000000000001',
 '95900000-0000-4000-8000-000000000001',
 'email',decode('45435031010203','hex'),repeat('e',64),'queued'
);

-- Create a real attempt with an already-expired lease. The worker's claim
-- function, not the fixture, must perform the sending -> uncertain recovery.
UPDATE eogp.invitation_deliveries
   SET status='sending',attempt_count=1,
       lease_expires_at=clock_timestamp()-interval '1 second'
 WHERE organization_id='22222222-2222-4222-8222-222222222222'
   AND id='96000000-0000-4000-8000-000000000001';
UPDATE eogp.events
   SET status='cancelled',updated_at=clock_timestamp()
 WHERE organization_id='22222222-2222-4222-8222-222222222222'
   AND id='94000000-0000-4000-8000-000000000001';
COMMIT;
