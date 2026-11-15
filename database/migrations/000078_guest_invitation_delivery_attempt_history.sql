-- Immutable operational history for guest invitation SMTP submissions.
-- One row is created for each worker claim; completion updates only that attempt.

CREATE TABLE eogp.invitation_delivery_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id uuid NOT NULL,
  invitation_id uuid NOT NULL,
  delivery_id uuid NOT NULL,
  attempt_number integer NOT NULL CHECK (attempt_number BETWEEN 1 AND 5),
  status text NOT NULL CHECK (status IN ('sending','sent','failed','uncertain')),
  failure_code text,
  provider_message_reference text,
  started_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  completed_at timestamptz,
  retry_scheduled boolean NOT NULL DEFAULT false,
  UNIQUE (organization_id,id),
  UNIQUE (organization_id,delivery_id,attempt_number),
  FOREIGN KEY (organization_id,delivery_id)
    REFERENCES eogp.invitation_deliveries(organization_id,id),
  FOREIGN KEY (organization_id,event_id,invitation_id)
    REFERENCES eogp.invitations(organization_id,event_id,id),
  CHECK ((status='sending') = (completed_at IS NULL)),
  CHECK (status<>'sending' OR (failure_code IS NULL AND provider_message_reference IS NULL)),
  CHECK (status<>'sent' OR failure_code IS NULL)
);

CREATE INDEX invitation_delivery_attempts_history_idx
  ON eogp.invitation_delivery_attempts(organization_id,invitation_id,started_at DESC,id DESC);

ALTER TABLE eogp.invitation_delivery_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.invitation_delivery_attempts FORCE ROW LEVEL SECURITY;
CREATE POLICY invitation_delivery_attempts_tenant
  ON eogp.invitation_delivery_attempts
  USING (organization_id=eogp.current_organization_id())
  WITH CHECK (organization_id=eogp.current_organization_id());
REVOKE ALL ON eogp.invitation_delivery_attempts FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

CREATE FUNCTION eogp.record_invitation_delivery_attempt_transition()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status AND NEW.status='sending' THEN
    INSERT INTO eogp.invitation_delivery_attempts(
      organization_id,event_id,invitation_id,delivery_id,attempt_number,status
    ) VALUES (
      NEW.organization_id,NEW.event_id,NEW.invitation_id,NEW.id,NEW.attempt_count,'sending'
    );
  ELSIF OLD.status='sending' AND NEW.status IS DISTINCT FROM OLD.status THEN
    UPDATE eogp.invitation_delivery_attempts attempt
       SET status=CASE WHEN NEW.status='sent' THEN 'sent'
                       WHEN NEW.status='uncertain' THEN 'uncertain'
                       ELSE 'failed' END,
           failure_code=left(NEW.failure_code,80),
           provider_message_reference=CASE WHEN NEW.status='sent' THEN left(NEW.provider_message_reference,998) ELSE NULL END,
           completed_at=clock_timestamp(),
           retry_scheduled=(NEW.status='queued')
     WHERE attempt.organization_id=OLD.organization_id
       AND attempt.delivery_id=OLD.id
       AND attempt.attempt_number=OLD.attempt_count
       AND attempt.status='sending';
    IF NOT FOUND THEN
      RAISE EXCEPTION 'guest invitation delivery attempt history is inconsistent';
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION eogp.record_invitation_delivery_attempt_transition() FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

CREATE TRIGGER invitation_delivery_attempt_transition
AFTER UPDATE OF status ON eogp.invitation_deliveries
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION eogp.record_invitation_delivery_attempt_transition();

CREATE FUNCTION eogp.list_guest_invitation_delivery_attempts(
  p_organization_id uuid,
  p_invitation_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_event_id uuid;
  v_result jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id
     OR nullif(current_setting('app.actor_membership_id',true),'')::uuid IS DISTINCT FROM p_actor_membership_id THEN
    RAISE EXCEPTION 'organization or staff actor context mismatch' USING ERRCODE='42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM eogp.organization_memberships membership
     WHERE membership.organization_id=p_organization_id
       AND membership.id=p_actor_membership_id AND membership.status='active'
  ) THEN
    RAISE EXCEPTION 'active staff membership is required' USING ERRCODE='42501';
  END IF;

  SELECT invitation.event_id INTO v_event_id
    FROM eogp.invitations invitation
   WHERE invitation.organization_id=p_organization_id AND invitation.id=p_invitation_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'guest invitation not found' USING ERRCODE='P0002';
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
       AND (user_grant.scope_kind='organization'
         OR (user_grant.scope_kind='event' AND user_grant.scope_event_id=v_event_id))
  ) THEN
    RAISE EXCEPTION 'invitation.manage permission is required for this event' USING ERRCODE='42501';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'attemptId',attempt.id,
    'deliveryId',attempt.delivery_id,
    'attemptNumber',attempt.attempt_number,
    'status',attempt.status,
    'failureCode',attempt.failure_code,
    'providerMessageReference',attempt.provider_message_reference,
    'startedAt',attempt.started_at,
    'completedAt',attempt.completed_at,
    'retryScheduled',attempt.retry_scheduled
  ) ORDER BY attempt.started_at DESC,attempt.id DESC),'[]'::jsonb)
    INTO v_result
    FROM eogp.invitation_delivery_attempts attempt
   WHERE attempt.organization_id=p_organization_id
     AND attempt.invitation_id=p_invitation_id;
  RETURN v_result;
END;
$function$;
REVOKE ALL ON FUNCTION eogp.list_guest_invitation_delivery_attempts(uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.list_guest_invitation_delivery_attempts(uuid,uuid,uuid) TO eventor_runtime;
