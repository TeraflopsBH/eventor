-- Revoke any outstanding customer capability when an issued offer revision
-- becomes terminal (accepted/rejected/expired/withdrawn). This also covers the
-- explicit supersede transition performed while creating a successor revision.
CREATE FUNCTION eogp.revoke_terminal_booking_offer_capability()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog,eogp
AS $function$
BEGIN
  IF OLD.state='issued'
     AND NEW.state IN ('accepted','rejected','expired','withdrawn') THEN
    UPDATE eogp.external_action_capabilities capability
       SET revoked_at=coalesce(capability.revoked_at,clock_timestamp())
     WHERE capability.organization_id=NEW.organization_id
       AND capability.offer_revision_id=NEW.id
       AND capability.action_code='offer_accept'
       AND capability.revoked_at IS NULL;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER booking_offer_revision_terminal_capability_revoke
  AFTER UPDATE OF state ON eogp.booking_offer_revisions
  FOR EACH ROW EXECUTE FUNCTION eogp.revoke_terminal_booking_offer_capability();

REVOKE ALL ON FUNCTION eogp.revoke_terminal_booking_offer_capability()
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
