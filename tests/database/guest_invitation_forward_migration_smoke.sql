\set ON_ERROR_STOP on

SET ROLE eventor_owner;
SELECT set_config('app.organization_id','97000000-0000-4000-8000-000000000001',true);
SELECT
  id,
  organization_id,
  event_id,
  invitation_id,
  invitation_revision_id,
  encode(capability_ciphertext,'hex') AS capability_ciphertext_hex
FROM eogp.invitation_deliveries
WHERE organization_id='97000000-0000-4000-8000-000000000001'
ORDER BY id;

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

  IF NOT EXISTS (
    SELECT 1
      FROM eogp.invitation_deliveries delivery
     WHERE delivery.organization_id='97000000-0000-4000-8000-000000000001'
       AND delivery.id='97000000-0000-4000-8000-000000000012'
       AND delivery.capability_ciphertext=decode('45435031' || repeat('aa',32),'hex')
  ) THEN
    RAISE EXCEPTION 'pre-existing link capability ciphertext was not preserved on its delivery row';
  END IF;
END;
$guest_invitation_forward_migration$;
