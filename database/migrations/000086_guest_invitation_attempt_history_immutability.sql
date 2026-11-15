-- Prevent direct rewriting or deletion of completed guest invitation attempt history.
-- The only permitted UPDATE is the nested transition performed by the delivery
-- status trigger when a claimed attempt leaves sending.

CREATE FUNCTION eogp.guard_invitation_delivery_attempt_history()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
BEGIN
  IF TG_OP='DELETE' THEN
    RAISE EXCEPTION 'guest invitation delivery attempt history cannot be deleted'
      USING ERRCODE='55000';
  END IF;

  IF pg_trigger_depth()<2
     OR OLD.status<>'sending'
     OR NEW.status NOT IN ('sent','failed','uncertain')
     OR NEW.completed_at IS NULL
     OR ROW(
       NEW.id,NEW.organization_id,NEW.event_id,NEW.invitation_id,
       NEW.delivery_id,NEW.attempt_number,NEW.started_at
     ) IS DISTINCT FROM ROW(
       OLD.id,OLD.organization_id,OLD.event_id,OLD.invitation_id,
       OLD.delivery_id,OLD.attempt_number,OLD.started_at
     ) THEN
    RAISE EXCEPTION 'guest invitation delivery attempt history may only be finalized by its delivery transition'
      USING ERRCODE='55000';
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.guard_invitation_delivery_attempt_history()
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

CREATE TRIGGER invitation_delivery_attempt_history_guard
BEFORE UPDATE OR DELETE ON eogp.invitation_delivery_attempts
FOR EACH ROW
EXECUTE FUNCTION eogp.guard_invitation_delivery_attempt_history();
