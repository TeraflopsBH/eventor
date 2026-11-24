\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
DO $test$
DECLARE v_org uuid; v_person uuid; v_reference uuid; v_count integer;
BEGIN
  IF NOT (SELECT relrowsecurity AND relforcerowsecurity FROM pg_class WHERE oid='eogp.person_identifiers'::regclass) THEN
    RAISE EXCEPTION 'reference encryption backfill did not restore forced RLS'; END IF;
  FOR v_org,v_person,v_reference IN VALUES
    ('11111111-1111-4111-8111-111111111111'::uuid,'79f00000-0000-4000-8000-000000000001'::uuid,'79f00000-0000-4000-8000-000000000011'::uuid),
    ('22222222-2222-4222-8222-222222222222'::uuid,'79f00000-0000-4000-8000-000000000002'::uuid,'79f00000-0000-4000-8000-000000000012'::uuid)
  LOOP
    PERFORM set_config('app.organization_id',v_org::text,true);
    IF NOT EXISTS(SELECT 1 FROM eogp.person_identifiers WHERE id=v_reference AND person_id=v_person AND encryption_person_id=v_person
      AND identifier_kind='external-ref-v1:CI-UPGRADE-BINDING' AND identifier_hash=repeat('1',64)
      AND encrypted_value=convert_to('ECP1'||repeat('upgrade-reference-',3),'UTF8') AND created_at='2026-11-01T00:00:00Z') THEN
      RAISE EXCEPTION 'populated reference encryption binding lost ownership or protected values'; END IF;
    SELECT count(*) INTO v_count FROM eogp.person_identifiers WHERE id IN('79f00000-0000-4000-8000-000000000011','79f00000-0000-4000-8000-000000000012');
    IF v_count<>1 THEN RAISE EXCEPTION 'forced owner RLS exposed the other tenant after backfill'; END IF;
    BEGIN
      UPDATE eogp.person_identifiers SET encryption_person_id=CASE WHEN v_person='79f00000-0000-4000-8000-000000000001'::uuid
        THEN '79f00000-0000-4000-8000-000000000002'::uuid ELSE '79f00000-0000-4000-8000-000000000001'::uuid END WHERE id=v_reference;
      RAISE EXCEPTION 'encryption identity could cross organizations';
    EXCEPTION WHEN foreign_key_violation THEN NULL; END;
  END LOOP;
  -- Remove only this rehearsal's two synthetic records after verifying both populated tenants.
  FOR v_org,v_person,v_reference IN VALUES
    ('11111111-1111-4111-8111-111111111111'::uuid,'79f00000-0000-4000-8000-000000000001'::uuid,'79f00000-0000-4000-8000-000000000011'::uuid),
    ('22222222-2222-4222-8222-222222222222'::uuid,'79f00000-0000-4000-8000-000000000002'::uuid,'79f00000-0000-4000-8000-000000000012'::uuid)
  LOOP
    PERFORM set_config('app.organization_id',v_org::text,true);
    DELETE FROM eogp.person_identifiers WHERE id=v_reference;
    DELETE FROM eogp.persons WHERE id=v_person;
  END LOOP;
END;
$test$;
COMMIT;
\echo 'Populated reference encryption binding upgrade and forced RLS checks passed.'
