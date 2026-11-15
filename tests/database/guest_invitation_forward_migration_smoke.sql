\set ON_ERROR_STOP on

SET ROLE eventor_owner;
DO $guest_invitation_forward_migration$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='eogp'
       AND table_name='invitation_links'
       AND column_name='capability_ciphertext'
  ) THEN
    RAISE EXCEPTION 'invitation bearer ciphertext remains on the lookup-link table';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='eogp'
       AND table_name='invitation_deliveries'
       AND column_name='capability_ciphertext'
  ) THEN
    RAISE EXCEPTION 'restricted invitation delivery queue is missing capability ciphertext';
  END IF;

  IF position('v_delivery.capability_ciphertext' IN
      pg_get_functiondef('eogp.claim_invitation_email_delivery(uuid)'::regprocedure))=0 THEN
    RAISE EXCEPTION 'invitation delivery claim does not read the restricted delivery envelope';
  END IF;
END;
$guest_invitation_forward_migration$;
