\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SET LOCAL app.organization_id='22222222-2222-4222-8222-222222222222';

-- The SMTP authorization fixture provides an active invitation. Create a
-- successor policy, invitation revision and link rather than mutating the
-- append-only revision records. All changes roll back at the end of this test.
UPDATE eogp.events
   SET status='scheduled',updated_at=clock_timestamp()
 WHERE organization_id='22222222-2222-4222-8222-222222222222'
   AND id='94000000-0000-4000-8000-000000000001';
UPDATE eogp.invitations
   SET status='active',revoked_at=NULL
 WHERE organization_id='22222222-2222-4222-8222-222222222222'
   AND id='94500000-0000-4000-8000-000000000005';

INSERT INTO eogp.rsvp_policies(id,organization_id,event_id,code,name)
VALUES (
  '96800000-0000-4000-8000-000000000001',
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  'CI_GUEST_RSVP_WRITE_LIMIT','CI guest RSVP write limit'
);
INSERT INTO eogp.rsvp_policy_revisions(
  id,organization_id,event_id,policy_id,revision_number,event_timezone,
  state,published_at,allowed_responses,response_change_allowed,
  response_deadline,late_change_requires_staff
) VALUES (
  '96900000-0000-4000-8000-000000000001',
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  '96800000-0000-4000-8000-000000000001',
  1,'Europe/Sarajevo','published',clock_timestamp(),
  '["accepted"]'::jsonb,true,NULL,false
);
INSERT INTO eogp.invitation_revisions(
  id,organization_id,event_id,invitation_id,revision_number,
  schedule_revision_id,rsvp_policy_revision_id,locale,
  presentation_snapshot_ciphertext,issued_at,created_by_membership_id
) VALUES (
  '97000000-0000-4000-8000-000000000001',
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  '94500000-0000-4000-8000-000000000005',
  2,'94100000-0000-4000-8000-000000000001',
  '96900000-0000-4000-8000-000000000001',
  'en',decode('455631'||repeat('01',40),'hex'),clock_timestamp(),
  'bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
);
INSERT INTO eogp.invitation_links(
  id,organization_id,event_id,invitation_id,invitation_revision_id,
  token_sha256,expires_at
) VALUES (
  '97100000-0000-4000-8000-000000000001',
  '22222222-2222-4222-8222-222222222222',
  '94000000-0000-4000-8000-000000000001',
  '94500000-0000-4000-8000-000000000005',
  '97000000-0000-4000-8000-000000000001',
  repeat('e',64),clock_timestamp()+interval '1 hour'
);
UPDATE eogp.invitations
   SET current_revision_number=2,issued_at=COALESCE(issued_at,clock_timestamp())
 WHERE organization_id='22222222-2222-4222-8222-222222222222'
   AND id='94500000-0000-4000-8000-000000000005';

SET LOCAL ROLE eventor_runtime;
DO $guest_rsvp_capability_write_limit$
DECLARE
  v_token_sha256 text := repeat('e',64);
  i integer;
BEGIN
  FOR i IN 1..20 LOOP
    PERFORM eogp.submit_guest_invitation_rsvp(
      v_token_sha256,
      lpad(to_hex(i),64,'0'),
      lpad(to_hex(i+100),64,'0'),
      'accepted',
      NULL
    );
  END LOOP;
END;
$guest_rsvp_capability_write_limit$;

SET LOCAL ROLE eventor_owner;
DO $guest_rsvp_capability_write_limit_before$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count
    FROM eogp.rsvp_responses
   WHERE organization_id='22222222-2222-4222-8222-222222222222'
     AND invitation_link_id='97100000-0000-4000-8000-000000000001';
  IF v_count<>20 THEN
    RAISE EXCEPTION 'expected 20 guest responses before the cap, found %',v_count;
  END IF;
END;
$guest_rsvp_capability_write_limit_before$;

SET LOCAL ROLE eventor_runtime;
DO $guest_rsvp_capability_write_limit_reject$
DECLARE v_denied boolean := false;
BEGIN
  BEGIN
    PERFORM eogp.submit_guest_invitation_rsvp(
      repeat('e',64),
      lpad(to_hex(21),64,'0'),
      lpad(to_hex(121),64,'0'),
      'accepted',
      NULL
    );
  EXCEPTION WHEN SQLSTATE '54000' THEN
    v_denied := true;
  END;
  IF NOT v_denied THEN
    RAISE EXCEPTION 'guest invitation accepted a 21st distinct RSVP submission';
  END IF;
END;
$guest_rsvp_capability_write_limit_reject$;

SET LOCAL ROLE eventor_owner;
DO $guest_rsvp_capability_write_limit_after$
DECLARE v_count integer;
BEGIN
  SELECT count(*) INTO v_count
    FROM eogp.rsvp_responses
   WHERE organization_id='22222222-2222-4222-8222-222222222222'
     AND invitation_link_id='97100000-0000-4000-8000-000000000001';
  IF v_count<>20 THEN
    RAISE EXCEPTION 'rejected 21st RSVP appended a response row; count is %',v_count;
  END IF;
  SELECT count(*) INTO v_count
    FROM eogp.guest_invitation_rsvp_idempotency
   WHERE organization_id='22222222-2222-4222-8222-222222222222'
     AND invitation_link_id='97100000-0000-4000-8000-000000000001';
  IF v_count<>20 THEN
    RAISE EXCEPTION 'rejected 21st RSVP appended an idempotency row; count is %',v_count;
  END IF;
  SELECT count(*) INTO v_count
    FROM eogp.audit_events
   WHERE organization_id='22222222-2222-4222-8222-222222222222'
     AND actor_external_capability_id='97100000-0000-4000-8000-000000000001'
     AND action='guest.rsvp.submitted';
  IF v_count<>20 THEN
    RAISE EXCEPTION 'rejected 21st RSVP appended an audit event; count is %',v_count;
  END IF;
END;
$guest_rsvp_capability_write_limit_after$;
ROLLBACK;
\echo 'Guest invitation RSVP per-link write limit regression passed.'
