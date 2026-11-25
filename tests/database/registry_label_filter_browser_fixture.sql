\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','10000000-0000-0000-0000-00000000000a',true);
INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
VALUES('10000000-0000-0000-0000-00000000000a','79e00000-0000-4000-8000-000000000001','guest.registry.export')
ON CONFLICT DO NOTHING;
COMMIT;
