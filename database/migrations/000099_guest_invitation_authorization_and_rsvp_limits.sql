-- Close two boundedness/authorization gaps found during guest-invitation review.
-- This is additive: historical migrations remain immutable.

CREATE FUNCTION eogp.guard_guest_invitation_manage_permission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_actor uuid;
BEGIN
  -- Migrations and tightly controlled owner maintenance run without a staff
  -- actor context. Application commands always bind this context before
  -- invoking invitation mutations.
  v_actor := nullif(current_setting('app.actor_membership_id',true),'')::uuid;
  IF v_actor IS NULL THEN
    RETURN NEW;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM eogp.organization_memberships membership
     WHERE membership.organization_id=NEW.organization_id
       AND membership.id=v_actor
       AND membership.status='active'
     FOR SHARE
  ) THEN
    RAISE EXCEPTION 'active staff membership is required'
      USING ERRCODE='42501';
  END IF;

  PERFORM 1
    FROM eogp.user_role_grants user_grant
    JOIN eogp.role_permissions role_permission
      ON role_permission.organization_id=user_grant.organization_id
     AND role_permission.role_id=user_grant.role_id
   WHERE user_grant.organization_id=NEW.organization_id
     AND user_grant.membership_id=v_actor
     AND user_grant.revoked_at IS NULL
     AND (user_grant.expires_at IS NULL OR user_grant.expires_at>clock_timestamp())
     AND role_permission.permission_code='invitation.manage'
     AND (
       user_grant.scope_kind='organization'
       OR (user_grant.scope_kind='event' AND user_grant.scope_event_id=NEW.event_id)
     )
   FOR SHARE OF user_grant,role_permission;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'invitation.manage permission is required for this event'
      USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.guard_guest_invitation_manage_permission()
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

CREATE TRIGGER invitations_manage_permission_guard
BEFORE INSERT OR UPDATE ON eogp.invitations
FOR EACH ROW EXECUTE FUNCTION eogp.guard_guest_invitation_manage_permission();

-- Public RSVP links are bearer capabilities and the response history is
-- append-only. Bound the number of guest-originated writes per link. The RSVP
-- command already locks the invitation-link row FOR UPDATE before inserting,
-- so concurrent submissions through the supported command serialize here.
CREATE FUNCTION eogp.enforce_guest_invitation_rsvp_write_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_existing_count integer;
  v_max_guest_responses constant integer := 20;
BEGIN
  IF NEW.invitation_link_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT count(*) INTO v_existing_count
    FROM eogp.rsvp_responses response
   WHERE response.organization_id=NEW.organization_id
     AND response.invitation_link_id=NEW.invitation_link_id;

  IF v_existing_count >= v_max_guest_responses THEN
    RAISE EXCEPTION 'guest invitation response limit reached'
      USING ERRCODE='54000';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.enforce_guest_invitation_rsvp_write_limit()
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

CREATE TRIGGER guest_invitation_rsvp_write_limit
BEFORE INSERT ON eogp.rsvp_responses
FOR EACH ROW EXECUTE FUNCTION eogp.enforce_guest_invitation_rsvp_write_limit();
