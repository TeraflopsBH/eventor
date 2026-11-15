\set ON_ERROR_STOP on

SET ROLE eventor_owner;
SELECT set_config('app.organization_id','97000000-0000-4000-8000-000000000001',true);

DO $guest_invitation_forward_schema$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='eogp' AND table_name='invitation_links'
       AND column_name='capability_ciphertext'
  ) THEN
    RAISE EXCEPTION 'invitation bearer ciphertext remains on the lookup-link table';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
     WHERE table_schema='eogp' AND table_name='invitation_deliveries'
       AND column_name='capability_ciphertext'
  ) THEN
    RAISE EXCEPTION 'restricted invitation delivery queue is missing capability ciphertext';
  END IF;

END;
$guest_invitation_forward_schema$;
