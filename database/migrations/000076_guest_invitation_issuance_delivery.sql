-- Staff-issued guest invitation capabilities and encrypted email delivery.
-- Raw bearer tokens exist only in process memory and an authenticated-encryption
-- envelope for the delivery worker; lookup and audit records contain only hashes.

ALTER TABLE eogp.invitation_links
  ADD COLUMN capability_ciphertext bytea,
  ADD CONSTRAINT invitation_links_capability_ciphertext_ck
    CHECK (capability_ciphertext IS NULL OR (
      octet_length(capability_ciphertext) > 32
      AND substring(capability_ciphertext FROM 1 FOR 4) = convert_to('ECP1','UTF8')
    ));

ALTER TABLE eogp.invitation_deliveries
  ADD COLUMN idempotency_key_sha256 text,
  ADD COLUMN capability_ciphertext bytea,
  ADD COLUMN delivery_config_revision_id uuid,
  ADD COLUMN attempt_count integer NOT NULL DEFAULT 0 CHECK (attempt_count BETWEEN 0 AND 5),
  ADD COLUMN next_attempt_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  ADD COLUMN lease_expires_at timestamptz,
  ADD COLUMN last_failure_code text,
  ADD CONSTRAINT invitation_deliveries_idempotency_ck
    CHECK (idempotency_key_sha256 IS NULL OR idempotency_key_sha256 ~ '^[0-9a-f]{64}$'),
  ADD CONSTRAINT invitation_deliveries_capability_ck
    CHECK (capability_ciphertext IS NULL OR (
      octet_length(capability_ciphertext) > 32
      AND substring(capability_ciphertext FROM 1 FOR 4) = convert_to('ECP1','UTF8')
    )),
  ADD CONSTRAINT invitation_deliveries_config_fk
    FOREIGN KEY (organization_id, delivery_config_revision_id)
    REFERENCES eogp.organization_delivery_config_revisions(organization_id,id),
  ADD CONSTRAINT invitation_deliveries_idempotency_uq
    UNIQUE (organization_id,idempotency_key_sha256);

-- Legacy "sending" rows predate leases; fail closed as uncertain rather than
-- silently resubmitting a message that may already have reached the provider.
UPDATE eogp.invitation_deliveries
   SET status='uncertain',failure_code='SMTP_UNKNOWN'
 WHERE status='sending';

ALTER TABLE eogp.invitation_deliveries
  DROP CONSTRAINT invitation_deliveries_status_check;
ALTER TABLE eogp.invitation_deliveries
  ADD CONSTRAINT invitation_deliveries_status_check
    CHECK (status IN ('queued','sending','sent','delivered','bounced','failed','suppressed','uncertain')),
  ADD CONSTRAINT invitation_deliveries_lease_ck
    CHECK ((status='sending') = (lease_expires_at IS NOT NULL));

CREATE INDEX invitation_deliveries_ready_idx
  ON eogp.invitation_deliveries(organization_id,next_attempt_at,queued_at)
  WHERE status='queued';

CREATE TABLE eogp.invitation_delivery_tenant_queue (
  organization_id uuid PRIMARY KEY REFERENCES eogp.organizations(id),
  available_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
REVOKE ALL ON eogp.invitation_delivery_tenant_queue
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
GRANT SELECT ON eogp.invitation_delivery_tenant_queue TO eventor_worker;
REVOKE ALL ON eogp.invitation_deliveries
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

CREATE FUNCTION eogp.issue_guest_invitation(
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
  v_config_id uuid;
  v_member_status text;
  v_existing eogp.invitation_deliveries%ROWTYPE;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
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

  SELECT * INTO v_existing
    FROM eogp.invitation_deliveries
   WHERE organization_id=p_organization_id
     AND idempotency_key_sha256=p_idempotency_key_sha256
   FOR UPDATE;
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
       AND schedule.revision_number=(
         SELECT max(latest.revision_number)
           FROM eogp.event_schedule_revisions latest
          WHERE latest.organization_id=p_organization_id AND latest.event_id=p_event_id
       )
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

  SELECT contact.encrypted_value INTO v_destination
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
    UPDATE eogp.invitation_links
       SET revoked_at=clock_timestamp()
     WHERE organization_id=p_organization_id
       AND event_id=p_event_id AND invitation_id=p_invitation_id
       AND revoked_at IS NULL;
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
    token_sha256,expires_at,capability_ciphertext
  ) VALUES (
    p_organization_id,p_event_id,v_invitation.id,v_revision_id,
    p_token_sha256,p_expires_at,p_capability_ciphertext
  ) RETURNING id INTO v_link_id;

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
    'email',v_destination,encode(digest(v_destination,'sha256'),'hex'),'queued',
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

CREATE FUNCTION eogp.revoke_guest_invitation(
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
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
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

CREATE FUNCTION eogp.discover_pending_invitation_delivery_tenants()
RETURNS TABLE(organization_id uuid)
LANGUAGE plpgsql
SET search_path=pg_catalog,eogp
AS $function$
BEGIN
  IF session_user<>'eventor_worker' THEN
    RAISE EXCEPTION 'invitation delivery discovery requires eventor_worker' USING ERRCODE='42501';
  END IF;
  RETURN QUERY
    SELECT queue.organization_id FROM eogp.invitation_delivery_tenant_queue queue
     WHERE queue.available_at<=clock_timestamp()
     ORDER BY queue.available_at,queue.organization_id LIMIT 1000;
END;
$function$;

CREATE FUNCTION eogp.claim_invitation_email_delivery(p_organization_id uuid)
RETURNS TABLE(
  delivery_id uuid,invitation_id uuid,invitation_revision_id uuid,
  capability_ciphertext bytea,recipient_ciphertext bytea,
  credentials_ciphertext bytea,smtp_settings jsonb,
  sender_email text,sender_name text,reply_to text,
  event_title text,starts_at timestamptz,timezone_name text,locale text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_delivery eogp.invitation_deliveries%ROWTYPE;
  v_next timestamptz;
BEGIN
  IF session_user<>'eventor_worker'
     OR eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'invitation email claim requires worker role and matching tenant context'
      USING ERRCODE='42501';
  END IF;
  UPDATE eogp.invitation_deliveries
     SET status='uncertain',lease_expires_at=NULL,failure_code='SMTP_UNKNOWN'
   WHERE organization_id=p_organization_id AND status='sending'
     AND lease_expires_at<=clock_timestamp();

  SELECT delivery.* INTO v_delivery
    FROM eogp.invitation_deliveries delivery
    JOIN eogp.invitations invitation
      ON invitation.organization_id=delivery.organization_id
     AND invitation.id=delivery.invitation_id
   WHERE delivery.organization_id=p_organization_id
     AND delivery.status='queued' AND delivery.next_attempt_at<=clock_timestamp()
     AND invitation.status='active'
   ORDER BY delivery.next_attempt_at,delivery.queued_at,delivery.id
   FOR UPDATE OF delivery SKIP LOCKED LIMIT 1;
  IF NOT FOUND THEN
    SELECT min(CASE WHEN status='queued' THEN next_attempt_at ELSE lease_expires_at END)
      INTO v_next FROM eogp.invitation_deliveries
     WHERE organization_id=p_organization_id AND status IN ('queued','sending');
    IF v_next IS NULL THEN
      DELETE FROM eogp.invitation_delivery_tenant_queue WHERE organization_id=p_organization_id;
    ELSE
      UPDATE eogp.invitation_delivery_tenant_queue SET available_at=v_next,updated_at=clock_timestamp()
       WHERE organization_id=p_organization_id;
    END IF;
    RETURN;
  END IF;
  UPDATE eogp.invitation_deliveries
     SET status='sending',attempt_count=attempt_count+1,
         lease_expires_at=clock_timestamp()+interval '5 minutes'
   WHERE organization_id=p_organization_id AND id=v_delivery.id;

  RETURN QUERY
  SELECT v_delivery.id,v_delivery.invitation_id,v_delivery.invitation_revision_id,
         v_delivery.capability_ciphertext,v_delivery.destination_ciphertext,
         config.credentials_ciphertext,config.settings,
         config.settings->>'senderEmail',config.settings->>'senderName',
         config.settings->>'replyTo',event.title,schedule.starts_at,schedule.timezone_name,
         revision.locale
    FROM eogp.organization_delivery_config_revisions config
    JOIN eogp.invitation_revisions revision
      ON revision.organization_id=v_delivery.organization_id AND revision.id=v_delivery.invitation_revision_id
    JOIN eogp.events event
      ON event.organization_id=v_delivery.organization_id AND event.id=v_delivery.event_id
    JOIN eogp.event_schedule_revisions schedule
      ON schedule.organization_id=revision.organization_id AND schedule.id=revision.schedule_revision_id
   WHERE config.organization_id=p_organization_id
     AND config.id=v_delivery.delivery_config_revision_id;
END;
$function$;

CREATE FUNCTION eogp.complete_invitation_email_delivery(
  p_organization_id uuid,p_delivery_id uuid,p_outcome text,
  p_failure_code text DEFAULT NULL,p_provider_message_reference text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_delivery eogp.invitation_deliveries%ROWTYPE;
  v_retry boolean:=false;
  v_next timestamptz;
BEGIN
  IF session_user<>'eventor_worker'
     OR eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'invitation email completion requires worker role and matching tenant context'
      USING ERRCODE='42501';
  END IF;
  IF p_outcome NOT IN ('sent','failed','uncertain') THEN
    RAISE EXCEPTION 'invalid invitation email outcome' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_delivery FROM eogp.invitation_deliveries
   WHERE organization_id=p_organization_id AND id=p_delivery_id FOR UPDATE;
  IF NOT FOUND OR v_delivery.status<>'sending' OR v_delivery.lease_expires_at<=clock_timestamp() THEN
    RAISE EXCEPTION 'invitation email delivery lease is missing or expired' USING ERRCODE='55000';
  END IF;

  IF p_outcome='sent' THEN
    UPDATE eogp.invitation_deliveries
       SET status='sent',lease_expires_at=NULL,failure_code=NULL,
           provider_message_reference=left(p_provider_message_reference,998),
           sent_at=clock_timestamp()
     WHERE organization_id=p_organization_id AND id=p_delivery_id;
  ELSIF p_outcome='uncertain' THEN
    UPDATE eogp.invitation_deliveries
       SET status='uncertain',lease_expires_at=NULL,
           failure_code=left(coalesce(p_failure_code,'SMTP_UNKNOWN'),80)
     WHERE organization_id=p_organization_id AND id=p_delivery_id;
  ELSE
    v_retry:=p_failure_code IN ('SMTP_CONNECTION','SMTP_TIMEOUT','SMTP_4XX')
      AND v_delivery.attempt_count<5;
    v_next:=clock_timestamp()+make_interval(secs=>
      least(3600,30*power(2,greatest(0,v_delivery.attempt_count-1))::integer));
    UPDATE eogp.invitation_deliveries
       SET status=CASE WHEN v_retry THEN 'queued' ELSE 'failed' END,
           next_attempt_at=CASE WHEN v_retry THEN v_next ELSE next_attempt_at END,
           lease_expires_at=NULL,failure_code=left(coalesce(p_failure_code,'SMTP_UNKNOWN'),80),
           failed_at=CASE WHEN v_retry THEN NULL ELSE clock_timestamp() END
     WHERE organization_id=p_organization_id AND id=p_delivery_id;
  END IF;

  IF p_outcome='failed' AND v_retry THEN
    UPDATE eogp.invitation_delivery_tenant_queue
       SET available_at=least(available_at,v_next),updated_at=clock_timestamp()
     WHERE organization_id=p_organization_id;
  ELSE
    SELECT min(CASE WHEN status='queued' THEN next_attempt_at ELSE lease_expires_at END)
      INTO v_next FROM eogp.invitation_deliveries
     WHERE organization_id=p_organization_id AND status IN ('queued','sending');
    IF v_next IS NULL THEN
      DELETE FROM eogp.invitation_delivery_tenant_queue WHERE organization_id=p_organization_id;
    ELSE
      INSERT INTO eogp.invitation_delivery_tenant_queue(organization_id,available_at)
      VALUES(p_organization_id,v_next)
      ON CONFLICT(organization_id) DO UPDATE
        SET available_at=EXCLUDED.available_at,updated_at=clock_timestamp();
    END IF;
  END IF;

  INSERT INTO eogp.audit_events(
    organization_id,actor_kind,action,aggregate_type,aggregate_id,reason_code,safe_metadata,occurred_at
  ) VALUES (
    p_organization_id,'system',
    CASE WHEN p_outcome='sent' THEN 'guest.invitation.email_sent'
         WHEN p_outcome='uncertain' THEN 'guest.invitation.email_uncertain'
         ELSE 'guest.invitation.email_failed' END,
    'invitation',v_delivery.invitation_id,
    CASE WHEN p_outcome='sent' THEN 'smtp_accepted' ELSE coalesce(p_failure_code,'SMTP_UNKNOWN') END,
    jsonb_build_object('deliveryId',p_delivery_id,'invitationRevisionId',v_delivery.invitation_revision_id,
      'status',CASE WHEN p_outcome='sent' THEN 'sent' WHEN p_outcome='uncertain' THEN 'uncertain'
                    WHEN v_retry THEN 'queued' ELSE 'failed' END,'retryScheduled',p_outcome='failed' AND v_retry),
    clock_timestamp()
  );
  RETURN jsonb_build_object('deliveryId',p_delivery_id,
    'status',CASE WHEN p_outcome='sent' THEN 'sent' WHEN p_outcome='uncertain' THEN 'uncertain'
                  WHEN v_retry THEN 'queued' ELSE 'failed' END,
    'retryScheduled',p_outcome='failed' AND v_retry);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.issue_guest_invitation(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,bytea,text,bytea,timestamptz,text),
  eogp.revoke_guest_invitation(uuid,uuid,uuid,text)
  FROM PUBLIC,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.discover_pending_invitation_delivery_tenants(),
  eogp.claim_invitation_email_delivery(uuid),
  eogp.complete_invitation_email_delivery(uuid,uuid,text,text,text)
  FROM PUBLIC,eventor_runtime,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.issue_guest_invitation(uuid,uuid,uuid,uuid,uuid,uuid,uuid,text,bytea,text,bytea,timestamptz,text),
  eogp.revoke_guest_invitation(uuid,uuid,uuid,text) TO eventor_runtime;
GRANT EXECUTE ON FUNCTION eogp.discover_pending_invitation_delivery_tenants(),
  eogp.claim_invitation_email_delivery(uuid),
  eogp.complete_invitation_email_delivery(uuid,uuid,text,text,text) TO eventor_worker;
