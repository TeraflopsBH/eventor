\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;

SELECT set_config('app.organization_id','10000000-0000-0000-0000-00000000000b',true);
UPDATE eogp.booking_event_links
   SET status = 'revoked',
       status_changed_by_membership_id = '30000000-0000-0000-0000-00000000000b',
       status_change_reason_code = 'ci_review_revoked'
 WHERE organization_id = '10000000-0000-0000-0000-00000000000b'
   AND id = '66000000-0000-4000-8000-00000000000a';

SELECT set_config('app.organization_id','10000000-0000-0000-0000-00000000000a',true);
UPDATE eogp.venue_snapshot_shares
   SET status = 'revoked',
       status_changed_by_membership_id = '30000000-0000-0000-0000-00000000000a',
       status_change_reason_code = 'ci_review_revoked'
 WHERE organization_id = '10000000-0000-0000-0000-00000000000a'
   AND id = '63000000-0000-4000-8000-00000000000a';

DO $test$
DECLARE
  v_link_audit_count integer;
  v_share_audit_count integer;
BEGIN
  PERFORM set_config('app.organization_id','10000000-0000-0000-0000-00000000000b',true);
  SELECT count(*) INTO v_link_audit_count
    FROM eogp.audit_events
   WHERE organization_id = '10000000-0000-0000-0000-00000000000b'
     AND action = 'booking.event.link.revoked'
     AND aggregate_type = 'booking_event_link'
     AND aggregate_id = '66000000-0000-4000-8000-00000000000a'
     AND actor_organization_id = '10000000-0000-0000-0000-00000000000b'
     AND actor_membership_id = '30000000-0000-0000-0000-00000000000b'
     AND authorization_grant_owner_organization_id = '10000000-0000-0000-0000-00000000000a'
     AND authorization_grant_id = '61000000-0000-4000-8000-00000000000b'
     AND reason_code = 'ci_review_revoked';

  PERFORM set_config('app.organization_id','10000000-0000-0000-0000-00000000000a',true);
  SELECT count(*) INTO v_share_audit_count
    FROM eogp.audit_events
   WHERE organization_id = '10000000-0000-0000-0000-00000000000a'
     AND action = 'venue.snapshot.share.revoked'
     AND aggregate_type = 'venue_snapshot_share'
     AND aggregate_id = '63000000-0000-4000-8000-00000000000a'
     AND actor_organization_id = '10000000-0000-0000-0000-00000000000a'
     AND actor_membership_id = '30000000-0000-0000-0000-00000000000a'
     AND reason_code = 'ci_review_revoked';

  IF v_link_audit_count <> 1 OR v_share_audit_count <> 1 THEN
    RAISE EXCEPTION 'expected exactly one attributable lifecycle audit per link/share; got link %, share %',
      v_link_audit_count, v_share_audit_count;
  END IF;
END;
$test$;

COMMIT;
