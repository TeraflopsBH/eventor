-- Bind revocation authorization and audit attribution to the authenticated staff actor context.
CREATE OR REPLACE FUNCTION eogp.revoke_guest_invitation(
  p_organization_id uuid,
  p_invitation_id uuid,
  p_actor_membership_id uuid,
  p_reason_code text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_invitation eogp.invitations%ROWTYPE;
  v_member_status text;
  v_revoked_links integer;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id
     OR nullif(current_setting('app.actor_membership_id',true),'')::uuid IS DISTINCT FROM p_actor_membership_id THEN
    RAISE EXCEPTION 'organization or staff actor context mismatch' USING ERRCODE='42501';
  END IF;
  IF p_reason_code IS NULL OR p_reason_code !~ '^[a-z][a-z0-9_.-]{2,79}$' THEN
    RAISE EXCEPTION 'a machine-readable revocation reason is required' USING ERRCODE='22023';
  END IF;
  SELECT status INTO v_member_status
    FROM eogp.organization_memberships
   WHERE organization_id=p_organization_id AND id=p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_member_status<>'active' THEN
    RAISE EXCEPTION 'active staff membership is required' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1
      FROM eogp.user_role_grants user_grant
      JOIN eogp.role_permissions role_permission
        ON role_permission.organization_id=user_grant.organization_id
       AND role_permission.role_id=user_grant.role_id
     WHERE user_grant.organization_id=p_organization_id
       AND user_grant.membership_id=p_actor_membership_id
       AND user_grant.revoked_at IS NULL
       AND (user_grant.expires_at IS NULL OR user_grant.expires_at>clock_timestamp())
       AND role_permission.permission_code='invitation.manage'
       AND (
         user_grant.scope_kind='organization'
         OR (user_grant.scope_kind='event' AND user_grant.scope_event_id=(
           SELECT invitation.event_id FROM eogp.invitations invitation
            WHERE invitation.organization_id=p_organization_id AND invitation.id=p_invitation_id
         ))
       )
  ) THEN
    RAISE EXCEPTION 'invitation.manage permission is required for this invitation' USING ERRCODE='42501';
  END IF;
  SELECT * INTO v_invitation
    FROM eogp.invitations
   WHERE organization_id=p_organization_id AND id=p_invitation_id
   FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'invitation not found' USING ERRCODE='P0002';
  END IF;
  IF v_invitation.status='revoked' THEN
    RETURN jsonb_build_object('invitationId',p_invitation_id,'status','revoked','revokedLinks',0);
  END IF;
  IF v_invitation.status NOT IN ('active','draft') THEN
    RAISE EXCEPTION 'invitation cannot be revoked from its current state' USING ERRCODE='55000';
  END IF;

  UPDATE eogp.invitation_links
     SET revoked_at=clock_timestamp()
   WHERE organization_id=p_organization_id
     AND invitation_id=p_invitation_id AND revoked_at IS NULL;
  GET DIAGNOSTICS v_revoked_links=ROW_COUNT;

  UPDATE eogp.invitations
     SET status='revoked',revoked_at=clock_timestamp()
   WHERE organization_id=p_organization_id AND id=p_invitation_id;

  UPDATE eogp.invitation_deliveries
     SET status='suppressed',lease_expires_at=NULL,
         failure_code='INVITATION_REVOKED'
   WHERE organization_id=p_organization_id
     AND invitation_id=p_invitation_id
     AND status='queued';

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'guest.invitation.revoked','invitation',p_invitation_id,p_reason_code,
    jsonb_build_object('revokedLinks',v_revoked_links)
  );
  RETURN jsonb_build_object(
    'invitationId',p_invitation_id,'status','revoked','revokedLinks',v_revoked_links
  );
END;
$function$;
