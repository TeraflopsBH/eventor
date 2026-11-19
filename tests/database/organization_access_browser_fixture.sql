\set ON_ERROR_STOP on

-- Synthetic staff workspace data for organization-access-browser-smoke.mjs.
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','22222222-2222-4222-8222-222222222222',true);
INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
VALUES ('22222222-2222-4222-8222-222222222222','78000000-0000-4000-8000-000000000001','organization.manage')
ON CONFLICT DO NOTHING;
INSERT INTO eogp.events(id,organization_id,event_code,title,created_by_membership_id)
VALUES (
  '79000000-0000-4000-8000-000000000090','22222222-2222-4222-8222-222222222222',
  'CI-ACCESS-BROWSER','Synthetic access assignment event','bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb'
) ON CONFLICT (id) DO NOTHING;
COMMIT;
