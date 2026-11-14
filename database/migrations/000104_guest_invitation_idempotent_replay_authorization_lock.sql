-- Hold invitation.manage grant and permission rows through issuance,
-- including idempotency replays that return before invitation mutation triggers.

CREATE OR REPLACE FUNCTION eogp.issue_guest_invitation(
  p_organization_id uuid,
  p_event_id uuid,
  p_participation_id uuid,
  p_invitation_id uuid,
  p_actor_membership_id uuid,
  p_schedule_revision_id uuid,
  p_rsvp_policy_revision_id uuid,
  p_locale text,
  p_presentation_snapshot_ciphertext bytea,
  p_token_sha256 text,
  p_capability_ciphertext bytea,
  p_expires_at timestamptz,
  p_idempotency_key_sha256 text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_invitation eogp.invitations%ROWTYPE;
  v_revision_id uuid;
  v_link_id uuid;
  v_delivery_id uuid;
  v_revision_number integer;
  v_person_id uuid;
  v_destination bytea;
  v_destination_hash text;
  v_config_id uuid;
  v_member_status text;
  v_existing eogp.invitation_deliveries%ROWTYPE;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id
     OR nullif(current_setting('app.actor_membership_id',true),'')::uuid IS DISTINCT FROM p_actor_membership_id THEN
    RAISE EXCEPTION 'organization or staff actor context mismatch' USING ERRCODE='42501';
  END IF;
  IF p_token_sha256 IS NULL OR p_token_sha256 !~ '^[0-9a-f]{64}$'
     OR p_idempotency_key_sha256 IS NULL OR p_idempotency_key_sha256 !~ '^[0-9a-f]{64}$'
     OR p_capability_ciphertext IS NULL OR octet_length(p_capability_ciphertext)<=32
     OR substring(p_capability_ciphertext FROM 1 FOR 4)<>convert_to('ECP1','UTF8')
     OR p_presentation_snapshot_ciphertext IS NULL OR octet_length(p_presentation_snapshot_ciphertext)<=31
     OR substring(p_presentation_snapshot_ciphertext FROM 1 FOR 3)<>convert_to('EV1','UTF8')
     OR p_locale IS NULL OR p_locale NOT IN ('bs-BA','en')
     OR p_expires_at IS NULL OR p_expires_at<=clock_timestamp()
     OR p_expires_at>clock_timestamp()+interval '180 days' THEN
    RAISE EXCEPTION 'invalid guest invitation issuance request' USING ERRCODE='22023';
  END IF;

  SELECT status INTO v_member_status
    FROM eogp.organization_memberships
   WHERE organization_id=p_organization_id AND id=p_actor_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_member_status<>'active' THEN
    RAISE EXCEPTION 'active staff membership is required' USING ERRCODE='42501';
  END IF;

  PERFORM 1
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
       OR (user_grant.scope_kind='event' AND user_grant.scope_event_id=p_event_id)
     )
   FOR SHARE OF user_grant,role_permission;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'invitation.manage permission is required for this event' USING ERRCODE='42501';
  END IF;

  -- Serialize retries of the same idempotency key without taking a delivery
  -- row lock before the participation -> invitation -> link lock order. A
  -- worker authorizing SMTP takes invitation -> link -> delivery; locking
  -- the delivery here first would create a reissue/authorization deadlock.
  PERFORM pg_advisory_xact_lock(hashtextextended(
    p_organization_id::text || ':' || p_idempotency_key_sha256,0
  ));

  SELECT * INTO v_existing
    FROM eogp.invitation_deliveries
   WHERE organization_id=p_organization_id
     AND idempotency_key_sha256=p_idempotency_key_sha256;
  IF FOUND THEN
    RETURN jsonb_build_object(
      'invitationId',v_existing.invitation_id,
      'deliveryId',v_existing.id,
      'status',v_existing.status,
      'created',false
    );
  END IF;

  SELECT participation.person_id INTO v_person_id
    FROM eogp.event_participations participation
    JOIN eogp.events event
      ON event.organization_id=participation.organization_id
     AND event.id=participation.event_id
   WHERE participation.organization_id=p_organization_id
     AND participation.event_id=p_event_id
     AND participation.id=p_participation_id
     AND participation.status='eligible'
     AND event.status IN ('planned','scheduled','active')
   FOR UPDATE OF participation;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'eligible event participation not found' USING ERRCODE='P0002';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM eogp.event_schedule_revisions schedule
     WHERE schedule.organization_id=p_organization_id
       AND schedule.event_id=p_event_id
       AND schedule.id=p_schedule_revision_id
       AND schedule.id=eogp.current_event_schedule_revision_id(p_organization_id,p_event_id)
  ) THEN
    RAISE EXCEPTION 'the current event schedule revision is required' USING ERRCODE='55000';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM eogp.rsvp_policy_revisions policy
     WHERE policy.organization_id=p_organization_id
       AND policy.event_id=p_event_id
       AND policy.id=p_rsvp_policy_revision_id
       AND policy.state='published'
  ) THEN
    RAISE EXCEPTION 'a published RSVP policy revision is required' USING ERRCODE='55000';
  END IF;

  SELECT contact.encrypted_value,contact.normalized_value_hash
    INTO v_destination,v_destination_hash
    FROM eogp.person_contact_points contact
   WHERE contact.organization_id=p_organization_id
     AND contact.person_id=v_person_id
     AND contact.contact_kind='email'
     AND contact.is_primary=true
     AND contact.is_verified=true
     AND contact.contact_consent='permitted'
   ORDER BY contact.updated_at DESC,contact.id
   LIMIT 1;
  IF v_destination IS NULL THEN
    RAISE EXCEPTION 'guest has no verified primary email with permitted contact consent'
      USING ERRCODE='55000';
  END IF;

  SELECT head.revision_id INTO v_config_id
    FROM eogp.organization_delivery_config_heads head
    JOIN eogp.organization_delivery_config_revisions config
      ON config.organization_id=head.organization_id AND config.id=head.revision_id
   WHERE head.organization_id=p_organization_id
     AND head.channel='email' AND head.delivery_enabled=true
     AND config.provider='smtp'
     AND (config.settings->>'authMode'<>'password' OR config.credentials_ciphertext IS NOT NULL);
  IF v_config_id IS NULL THEN
    RAISE EXCEPTION 'email delivery is not enabled or configured' USING ERRCODE='55000';
  END IF;

  IF p_invitation_id IS NULL AND EXISTS (
    SELECT 1 FROM eogp.invitations existing
     WHERE existing.organization_id=p_organization_id
       AND existing.event_id=p_event_id
       AND existing.participation_id=p_participation_id
       AND existing.status='active'
  ) THEN
    RAISE EXCEPTION 'an active invitation already exists; reissue that invitation instead'
      USING ERRCODE='23505';
  END IF;

  IF p_invitation_id IS NULL THEN
    INSERT INTO eogp.invitations(
      organization_id,event_id,participation_id,status,current_revision_number,
      issued_at,created_by_membership_id
    ) VALUES (
      p_organization_id,p_event_id,p_participation_id,'draft',0,
      NULL,p_actor_membership_id
    ) RETURNING * INTO v_invitation;
  ELSE
    SELECT * INTO v_invitation
      FROM eogp.invitations invitation
     WHERE invitation.organization_id=p_organization_id
       AND invitation.event_id=p_event_id
       AND invitation.id=p_invitation_id
       AND invitation.participation_id=p_participation_id
       AND invitation.status IN ('active','draft')
     FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'active invitation to reissue was not found' USING ERRCODE='P0002';
    END IF;
  END IF;

  SELECT COALESCE(max(revision_number),0)+1 INTO v_revision_number
    FROM eogp.invitation_revisions
   WHERE organization_id=p_organization_id AND invitation_id=v_invitation.id;

  INSERT INTO eogp.invitation_revisions(
    organization_id,event_id,invitation_id,revision_number,schedule_revision_id,
    rsvp_policy_revision_id,locale,presentation_snapshot_ciphertext,
    issued_at,created_by_membership_id
  ) VALUES (
    p_organization_id,p_event_id,v_invitation.id,v_revision_number,p_schedule_revision_id,
    p_rsvp_policy_revision_id,p_locale,p_presentation_snapshot_ciphertext,
    clock_timestamp(),p_actor_membership_id
  ) RETURNING id INTO v_revision_id;

  INSERT INTO eogp.invitation_links(
    organization_id,event_id,invitation_id,invitation_revision_id,
    token_sha256,expires_at
  ) VALUES (
    p_organization_id,p_event_id,v_invitation.id,v_revision_id,
    p_token_sha256,p_expires_at
  ) RETURNING id INTO v_link_id;

  IF p_invitation_id IS NOT NULL THEN
    UPDATE eogp.invitation_links
       SET revoked_at=clock_timestamp(),replaced_by_link_id=v_link_id
     WHERE organization_id=p_organization_id
       AND event_id=p_event_id AND invitation_id=v_invitation.id
       AND id<>v_link_id AND revoked_at IS NULL;
  END IF;

  UPDATE eogp.invitations
     SET status='active',current_revision_number=v_revision_number,
         issued_at=COALESCE(issued_at,clock_timestamp()),revoked_at=NULL
   WHERE organization_id=p_organization_id AND id=v_invitation.id;

  INSERT INTO eogp.invitation_deliveries(
    organization_id,event_id,invitation_id,invitation_revision_id,
    channel,destination_ciphertext,destination_hash,status,
    idempotency_key_sha256,capability_ciphertext,delivery_config_revision_id
  ) VALUES (
    p_organization_id,p_event_id,v_invitation.id,v_revision_id,
    'email',v_destination,v_destination_hash,'queued',
    p_idempotency_key_sha256,p_capability_ciphertext,v_config_id
  ) RETURNING id INTO v_delivery_id;

  INSERT INTO eogp.invitation_delivery_tenant_queue(organization_id,available_at)
  VALUES (p_organization_id,clock_timestamp())
  ON CONFLICT (organization_id) DO UPDATE
    SET available_at=least(eogp.invitation_delivery_tenant_queue.available_at,EXCLUDED.available_at),
        updated_at=clock_timestamp();

  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,safe_metadata
  ) VALUES (
    p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    CASE WHEN p_invitation_id IS NULL THEN 'guest.invitation.issued' ELSE 'guest.invitation.reissued' END,
    'invitation',v_invitation.id,
    jsonb_build_object('eventId',p_event_id,'participationId',p_participation_id,
      'revisionId',v_revision_id,'linkId',v_link_id,'deliveryId',v_delivery_id)
  );

  RETURN jsonb_build_object(
    'invitationId',v_invitation.id,'invitationRevisionId',v_revision_id,
    'linkId',v_link_id,'deliveryId',v_delivery_id,'status','queued','created',true
  );
END;
$function$;

REVOKE ALL ON FUNCTION eogp.issue_guest_invitation(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,bytea,text,bytea,timestamptz,text)
  FROM PUBLIC,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.issue_guest_invitation(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,bytea,text,bytea,timestamptz,text)
  TO eventor_runtime;


-- Revoke can also return early for an already-revoked invitation. Hold the
-- permission rows through that idempotent result, not just through mutations.
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
  PERFORM 1
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
   FOR SHARE OF user_grant,role_permission;
  IF NOT FOUND THEN
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

REVOKE ALL ON FUNCTION eogp.revoke_guest_invitation(uuid,uuid,uuid,text)
  FROM PUBLIC,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.revoke_guest_invitation(uuid,uuid,uuid,text)
  TO eventor_runtime;
