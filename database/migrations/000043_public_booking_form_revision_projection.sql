-- Resolve an exact previously published booking-form revision for submission.
-- This preserves open public forms across a publication change without allowing
-- arbitrary organizations, inactive forms or unpublished revisions to be read.

CREATE FUNCTION eogp.get_public_booking_form_revision(
  p_organization_slug text,
  p_form_code text,
  p_form_revision_id uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_organization_id uuid;
  v_result jsonb;
BEGIN
  IF nullif(trim(p_organization_slug), '') IS NULL
     OR length(p_organization_slug) > 80
     OR nullif(trim(p_form_code), '') IS NULL
     OR length(p_form_code) > 80
     OR p_form_revision_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT organization_id INTO v_organization_id
    FROM eogp.public_organization_routes
   WHERE organization_slug = trim(p_organization_slug)
     AND is_active = true
   FOR SHARE;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  PERFORM set_config('app.organization_id', v_organization_id::text, true);

  SELECT jsonb_build_object(
    'organizationId', organization.id,
    'organizationSlug', organization.slug,
    'organizationName', organization.name,
    'defaultTimezone', organization.default_timezone,
    'formCode', definition.form_code,
    'formName', definition.name,
    'formRevisionId', revision.id,
    'revisionNumber', revision.revision_number,
    'locale', revision.locale,
    'fieldSchema', revision.field_schema,
    'publishedAt', revision.published_at
  )
    INTO v_result
    FROM eogp.organizations organization
    JOIN eogp.booking_form_definitions definition
      ON definition.organization_id = organization.id
    JOIN eogp.booking_form_revisions revision
      ON revision.organization_id = definition.organization_id
     AND revision.form_definition_id = definition.id
   WHERE organization.id = v_organization_id
     AND definition.form_code = trim(p_form_code)
     AND definition.status = 'active'
     AND revision.id = p_form_revision_id
     AND revision.state = 'published'
     AND revision.published_at IS NOT NULL
   LIMIT 1;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.get_public_booking_form_revision(text,text,uuid)
  FROM PUBLIC, eventor_worker, eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.get_public_booking_form_revision(text,text,uuid)
  TO eventor_runtime;

COMMENT ON FUNCTION eogp.get_public_booking_form_revision(text,text,uuid) IS
  'Returns the constrained public projection of one exact, previously published revision of an active booking form. Resolves tenant only from the private active public-route directory.';
