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



DO $collaboration_actor_binding$
DECLARE
  v_definition text;
BEGIN
  SELECT pg_get_functiondef('eogp.propose_collaboration_grant(uuid,uuid,text,uuid,uuid,uuid,text,jsonb,text[],timestamptz,timestamptz,uuid)'::regprocedure)
    INTO v_definition;
  IF strpos(v_definition,'app.actor_membership_id')=0 THEN
    RAISE EXCEPTION 'collaboration grant proposal must bind its supplied membership to the authenticated actor context';
  END IF;
END;
$collaboration_actor_binding$;



-- Collaboration grant lifecycle requires collaboration.manage in both organizations.
DO $collaboration_authorization$
DECLARE
  v_org_a uuid := '10000000-0000-0000-0000-00000000000a';
  v_org_b uuid := '10000000-0000-0000-0000-00000000000b';
  v_admin_a uuid := '30000000-0000-0000-0000-00000000000a';
  v_admin_b uuid := '30000000-0000-0000-0000-00000000000b';
  v_member_a uuid := '30000000-0000-0000-0000-00000000000c';
  v_member_b uuid := '30000000-0000-0000-0000-00000000000d';
  v_user_a uuid := '40000000-0000-4000-8000-00000000000c';
  v_user_b uuid := '40000000-0000-4000-8000-00000000000d';
  v_role_a uuid := '50000000-0000-4000-8000-00000000000c';
  v_role_b uuid := '50000000-0000-4000-8000-00000000000d';
  v_scope_kind text;
  v_venue_id uuid;
  v_space_id uuid;
  v_booking_id uuid;
  v_grant_id uuid;
  v_allowed_actions text[];
  v_projection jsonb;
  v_denied boolean;
BEGIN
  INSERT INTO eogp.users(id,email,display_name,status)
  VALUES
    (v_user_a,'ci-collaboration-unprivileged-a@example.invalid','CI Collaboration Member A','active'),
    (v_user_b,'ci-collaboration-unprivileged-b@example.invalid','CI Collaboration Member B','active')
  ON CONFLICT (id) DO NOTHING;
  PERFORM set_config('app.organization_id',v_org_a::text,true);
  INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status,joined_at)
  VALUES (v_member_a,v_org_a,v_user_a,'active',clock_timestamp())
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind)
  VALUES (v_role_a,v_org_a,'CI_COLLAB_MANAGE_A','CI collaboration manager A','organization')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
  VALUES (v_org_a,v_role_a,'collaboration.manage')
  ON CONFLICT DO NOTHING;
  INSERT INTO eogp.user_role_grants(
    organization_id,membership_id,role_id,scope_kind,granted_by_membership_id
  ) VALUES (v_org_a,v_admin_a,v_role_a,'organization',v_admin_a)
  ON CONFLICT DO NOTHING;

  PERFORM set_config('app.organization_id',v_org_b::text,true);
  INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status,joined_at)
  VALUES (v_member_b,v_org_b,v_user_b,'active',clock_timestamp())
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind)
  VALUES (v_role_b,v_org_b,'CI_COLLAB_MANAGE_B','CI collaboration manager B','organization')
  ON CONFLICT (id) DO NOTHING;
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
  VALUES (v_org_b,v_role_b,'collaboration.manage')
  ON CONFLICT DO NOTHING;
  INSERT INTO eogp.user_role_grants(
    organization_id,membership_id,role_id,scope_kind,granted_by_membership_id
  ) VALUES (v_org_b,v_admin_b,v_role_b,'organization',v_admin_b)
  ON CONFLICT DO NOTHING;

  PERFORM set_config('app.organization_id',v_org_a::text,true);
  SELECT scope_kind,scope_venue_id,scope_space_id,scope_booking_id,allowed_actions,projection
    INTO v_scope_kind,v_venue_id,v_space_id,v_booking_id,v_allowed_actions,v_projection
    FROM eogp.collaboration_grants
   WHERE organization_id=v_org_a AND grantee_organization_id=v_org_b
     AND id='61000000-0000-4000-8000-00000000000b';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'collaboration fixture grant is missing';
  END IF;

  PERFORM set_config('app.organization_id',v_org_a::text,true);
  PERFORM set_config('app.actor_membership_id',v_member_a::text,true);
  v_denied := false;
  BEGIN
    PERFORM eogp.propose_collaboration_grant(
      NULL,v_org_b,v_scope_kind,v_venue_id,v_space_id,v_booking_id,
      'CI unauthorized proposal',v_projection,v_allowed_actions,
      clock_timestamp()-interval '1 minute',clock_timestamp()+interval '30 days',v_member_a
    );
  EXCEPTION WHEN SQLSTATE '42501' THEN v_denied := true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'unprivileged grantor proposed a collaboration grant'; END IF;

  PERFORM set_config('app.actor_membership_id',v_admin_a::text,true);
  v_denied := false;
  BEGIN
    PERFORM eogp.propose_collaboration_grant(
      NULL,v_org_b,v_scope_kind,v_venue_id,v_space_id,v_booking_id,
      'CI mismatched actor proposal',v_projection,v_allowed_actions,
      clock_timestamp()-interval '1 minute',clock_timestamp()+interval '30 days',v_member_a
    );
  EXCEPTION WHEN SQLSTATE '42501' THEN v_denied := true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'collaboration proposal accepted an actor/context mismatch'; END IF;

  v_grant_id := eogp.propose_collaboration_grant(
    NULL,v_org_b,v_scope_kind,v_venue_id,v_space_id,v_booking_id,
    'CI authorized collaboration',v_projection,v_allowed_actions,
    clock_timestamp()-interval '1 minute',clock_timestamp()+interval '30 days',v_admin_a
  );

  PERFORM set_config('app.organization_id',v_org_b::text,true);
  PERFORM set_config('app.actor_membership_id',v_member_b::text,true);
  v_denied := false;
  BEGIN
    PERFORM eogp.accept_collaboration_grant(v_grant_id,v_member_b);
  EXCEPTION WHEN SQLSTATE '42501' THEN v_denied := true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'unprivileged grantee accepted a collaboration grant'; END IF;

  PERFORM set_config('app.actor_membership_id',v_admin_b::text,true);
  PERFORM eogp.accept_collaboration_grant(v_grant_id,v_admin_b);
  PERFORM set_config('app.organization_id',v_org_a::text,true);
  IF (SELECT status FROM eogp.collaboration_grants WHERE organization_id=v_org_a AND id=v_grant_id)<>'active' THEN
    RAISE EXCEPTION 'authorized grantee did not activate collaboration grant';
  END IF;

  PERFORM set_config('app.organization_id',v_org_a::text,true);
  PERFORM set_config('app.actor_membership_id',v_member_a::text,true);
  v_denied := false;
  BEGIN
    PERFORM eogp.revoke_collaboration_grant(v_grant_id,v_member_a,'CI unauthorized revocation');
  EXCEPTION WHEN SQLSTATE '42501' THEN v_denied := true;
  END;
  IF NOT v_denied THEN RAISE EXCEPTION 'unprivileged grantor revoked a collaboration grant'; END IF;

  PERFORM set_config('app.actor_membership_id',v_admin_a::text,true);
  PERFORM eogp.revoke_collaboration_grant(v_grant_id,v_admin_a,'CI authorized revocation');
  IF (SELECT status FROM eogp.collaboration_grants WHERE organization_id=v_org_a AND id=v_grant_id)<>'revoked' THEN
    RAISE EXCEPTION 'authorized grantor did not revoke collaboration grant';
  END IF;
END;
$collaboration_authorization$;

COMMIT;
