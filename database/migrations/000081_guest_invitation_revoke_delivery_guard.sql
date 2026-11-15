-- Suppress queued email as soon as its bearer link is revoked or superseded.
-- This covers both explicit revocation and reissue, in the same transaction.
CREATE FUNCTION eogp.suppress_revoked_guest_invitation_delivery()
RETURNS trigger
LANGUAGE plpgsql
SET search_path=pg_catalog,eogp
AS $function$
BEGIN
  IF OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL THEN
    UPDATE eogp.invitation_deliveries delivery
       SET status='suppressed',
           lease_expires_at=NULL,
           failure_code=CASE
             WHEN NEW.replaced_by_link_id IS NOT NULL THEN 'INVITATION_SUPERSEDED'
             ELSE 'INVITATION_REVOKED'
           END
     WHERE delivery.organization_id=NEW.organization_id
       AND delivery.invitation_id=NEW.invitation_id
       AND delivery.invitation_revision_id=NEW.invitation_revision_id
       AND delivery.status='queued';
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.suppress_revoked_guest_invitation_delivery()
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

CREATE TRIGGER invitation_link_suppress_queued_delivery
AFTER UPDATE OF revoked_at ON eogp.invitation_links
FOR EACH ROW
WHEN (OLD.revoked_at IS NULL AND NEW.revoked_at IS NOT NULL)
EXECUTE FUNCTION eogp.suppress_revoked_guest_invitation_delivery();
