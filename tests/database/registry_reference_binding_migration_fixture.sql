-- Populate both tenants before 000183; ciphertext and original ownership must survive the backfill.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','11111111-1111-4111-8111-111111111111',true);
INSERT INTO eogp.persons(id,organization_id,first_name,last_name,created_by_membership_id)
VALUES('79f00000-0000-4000-8000-000000000001','11111111-1111-4111-8111-111111111111','Upgrade','Reference A','aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa');
INSERT INTO eogp.person_identifiers(id,organization_id,person_id,identifier_kind,identifier_hash,encrypted_value,created_at)
VALUES('79f00000-0000-4000-8000-000000000011','11111111-1111-4111-8111-111111111111','79f00000-0000-4000-8000-000000000001',
  'external-ref-v1:CI-UPGRADE-BINDING',repeat('1',64),convert_to('ECP1'||repeat('upgrade-reference-',3),'UTF8'),'2026-11-01T00:00:00Z');
SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);
INSERT INTO eogp.persons(id,organization_id,first_name,last_name,created_by_membership_id)
VALUES('79f00000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','Upgrade','Reference B','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb');
INSERT INTO eogp.person_identifiers(id,organization_id,person_id,identifier_kind,identifier_hash,encrypted_value,created_at)
VALUES('79f00000-0000-4000-8000-000000000012','22222222-2222-4222-8222-222222222222','79f00000-0000-4000-8000-000000000002',
  'external-ref-v1:CI-UPGRADE-BINDING',repeat('1',64),convert_to('ECP1'||repeat('upgrade-reference-',3),'UTF8'),'2026-11-01T00:00:00Z');
COMMIT;
