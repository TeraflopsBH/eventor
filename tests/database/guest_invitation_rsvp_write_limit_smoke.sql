\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SET LOCAL app.organization_id='22222222-2222-4222-8222-222222222222';

-- The SMTP authorization fixture provides a real invitation/link/capability.
-- Make the pinned policy permissive for repeated responses only in this
-- rollback-only regression transaction.
UPDATE eogp.events
   SET status='scheduled',updated_at=clock_timestamp()
 WHERE organization_id='22222222-2222-4222-8222-222222222222'
   AND id='94000000-0000-4000-8000-000000000001';
UPDATE eogp.invitations
   SET status='active',current_revision_number=1,issued_at=clock_timestamp(),revoked_at=NULL
 WHERE organization_id='22222222-2222-4222-8222-222222222222'
   AND id='94500000-0000-4000-8000-000000000005';
UPDATE eogp.invitation_revisions
   SET issued_at=clock_timestamp()
 WHERE organization_id='22222222-2222-4222-8222-222222222222'
   AND id='96500000-0000-4000-8000-000000000001';
UPDATE eogp.invitation_links
   SET revoked_at=NULL,expires_at=clock_timestamp()+interval '1 hour'
 WHERE organization_id='22222222-2222-4222-8222-222222222222'
   AND id='96600000-0000-4000-8000-000000000001';
UPDATE eogp.rsvp_policy_revisions
   SET state='published',allowed_responses='["accepted"]'::jsonb,
       response_change_allowed=true,response_deadline=NULL,
       late_change_requires_staff=false
 WHERE organization_id='22222222-2222-4222-8222-222222222222'
   AND id='96400000-0000-4000-8000-000000000001';

SET LOCAL ROLE eventor_runtime;
DO $guest_rsvp_capability_write_limit$
DECLARE
  v_link_id uuid := '96600000-0000-4000-8000-000000000001';
  v_token_sha256 text := repeat('f',64);
  v_denied boolean := false;
  v_count integer;
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

  SET LOCAL ROLE eventor_owner;
  SELECT count(*) INTO v_count
    FROM eogp.rsvp_responses
   WHERE organization_id='22222222-2222-4222-8222-222222222222'
     AND invitation_link_id=v_link_id;
  IF v_count<>20 THEN
    RAISE EXCEPTION 'expected 20 guest responses before the cap, found %',v_count;
  END IF;
  SET LOCAL ROLE eventor_runtime;

  BEGIN
    PERFORM eogp.submit_guest_invitation_rsvp(
      v_token_sha256,
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

  SET LOCAL ROLE eventor_owner;
  SELECT count(*) INTO v_count
    FROM eogp.rsvp_responses
   WHERE organization_id='22222222-2222-4222-8222-222222222222'
     AND invitation_link_id=v_link_id;
  IF v_count<>20 THEN
    RAISE EXCEPTION 'rejected 21st RSVP appended a response row; count is %',v_count;
  END IF;
  SELECT count(*) INTO v_count
    FROM eogp.guest_invitation_rsvp_idempotency
   WHERE organization_id='22222222-2222-4222-8222-222222222222'
     AND invitation_link_id=v_link_id;
  IF v_count<>20 THEN
    RAISE EXCEPTION 'rejected 21st RSVP appended an idempotency row; count is %',v_count;
  END IF;
  SELECT count(*) INTO v_count
    FROM eogp.audit_events
   WHERE organization_id='22222222-2222-4222-8222-222222222222'
     AND actor_external_capability_id=v_link_id
     AND action='guest.rsvp.submitted';
  IF v_count<>20 THEN
    RAISE EXCEPTION 'rejected 21st RSVP appended an audit event; count is %',v_count;
  END IF;
END;
$guest_rsvp_capability_write_limit$;

ROLLBACK;
\echo 'Guest invitation RSVP per-link write limit regression passed.'
