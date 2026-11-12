\set ON_ERROR_STOP on

BEGIN;
SET LOCAL ROLE eventor_owner;

SELECT set_config('app.organization_id','a1000000-0000-4000-8000-000000000001',true);
INSERT INTO eogp.organizations (id,slug,name,status,default_timezone)
VALUES (
  'a1000000-0000-4000-8000-000000000001',
  'ci-public-form',
  'CI Public Form Organization',
  'active',
  'Europe/Sarajevo'
);

INSERT INTO eogp.booking_form_definitions (
  id,organization_id,scope_kind,form_code,name,status
) VALUES (
  'a2000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'organization',
  'venue-rental',
  'Public venue rental inquiry',
  'active'
);

INSERT INTO eogp.booking_form_revisions (
  id,organization_id,form_definition_id,revision_number,locale,
  field_schema,state,published_at
) VALUES (
  'a3000000-0000-4000-8000-000000000001',
  'a1000000-0000-4000-8000-000000000001',
  'a2000000-0000-4000-8000-000000000001',
  1,
  'bs-BA',
  '{"fields":[{"code":"event_date","type":"date","required":true}]}'::jsonb,
  'published',
  clock_timestamp()
);

INSERT INTO eogp.booking_form_definitions (
  id,organization_id,scope_kind,form_code,name,status
) VALUES (
  'a2000000-0000-4000-8000-000000000002',
  'a1000000-0000-4000-8000-000000000001',
  'organization',
  'draft-only',
  'Unpublished inquiry',
  'active'
);

INSERT INTO eogp.booking_form_revisions (
  id,organization_id,form_definition_id,revision_number,locale,
  field_schema,state,published_at
) VALUES (
  'a3000000-0000-4000-8000-000000000002',
  'a1000000-0000-4000-8000-000000000001',
  'a2000000-0000-4000-8000-000000000002',
  1,
  'bs-BA',
  '{"fields":[]}'::jsonb,
  'draft',
  NULL
);

SELECT set_config('app.organization_id','a1000000-0000-4000-8000-000000000002',true);
INSERT INTO eogp.organizations (id,slug,name,status,default_timezone)
VALUES (
  'a1000000-0000-4000-8000-000000000002',
  'ci-public-form-suspended',
  'CI Suspended Public Form Organization',
  'suspended',
  'Europe/Sarajevo'
);

DO $test$
DECLARE
  v_form jsonb;
BEGIN
  v_form := eogp.get_published_public_booking_form('ci-public-form','venue-rental');
  IF v_form IS NULL
     OR v_form->>'organizationId' <> 'a1000000-0000-4000-8000-000000000001'
     OR v_form->>'formRevisionId' <> 'a3000000-0000-4000-8000-000000000001'
     OR v_form->>'locale' <> 'bs-BA'
     OR v_form->>'defaultLocale' <> 'en'
     OR v_form->'fieldSchema'->'fields'->0->>'code' <> 'event_date' THEN
    RAISE EXCEPTION 'published public form projection did not return the expected safe revision';
  END IF;

  IF eogp.get_published_public_booking_form('ci-public-form','draft-only') IS NOT NULL THEN
    RAISE EXCEPTION 'unpublished form revision was exposed publicly';
  END IF;
  IF eogp.get_published_public_booking_form('ci-public-form-suspended','venue-rental') IS NOT NULL THEN
    RAISE EXCEPTION 'suspended organization route was exposed publicly';
  END IF;
  IF eogp.get_published_public_booking_form('missing-public-organization','venue-rental') IS NOT NULL THEN
    RAISE EXCEPTION 'unknown organization route did not return not-found';
  END IF;

  IF has_table_privilege('eventor_runtime','eogp.public_organization_routes','SELECT') THEN
    RAISE EXCEPTION 'runtime role can read the private public-organization route directory';
  END IF;
  IF NOT has_function_privilege(
    'eventor_runtime',
    'eogp.get_published_public_booking_form(text,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'runtime role cannot execute the safe public-form projection';
  END IF;
END;
$test$;

-- The public projection reflects a later organization-default change
-- without changing the immutable authored form revision locale.
UPDATE eogp.organizations SET default_locale='bs-BA'
 WHERE id='a1000000-0000-4000-8000-000000000001';

DO $test$
DECLARE
  v_form jsonb;
BEGIN
  v_form := eogp.get_published_public_booking_form('ci-public-form','venue-rental');
  IF v_form->>'defaultLocale' <> 'bs-BA' OR v_form->>'locale' <> 'bs-BA' THEN
    RAISE EXCEPTION 'public form projection did not expose the configured organization locale separately from authored revision locale';
  END IF;
END;
$test$;

-- A tenant suspension is reflected in the private public-route directory.
SELECT set_config('app.organization_id','a1000000-0000-4000-8000-000000000001',true);
UPDATE eogp.organizations SET status='suspended'
 WHERE id='a1000000-0000-4000-8000-000000000001';

DO $test$
BEGIN
  IF eogp.get_published_public_booking_form('ci-public-form','venue-rental') IS NOT NULL THEN
    RAISE EXCEPTION 'organization suspension did not disable its public form route';
  END IF;
END;
$test$;

ROLLBACK;
