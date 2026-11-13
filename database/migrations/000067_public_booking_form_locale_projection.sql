-- Expose the organization's configured customer-facing locale with the
-- published form. The form revision locale remains separate: it describes the
-- language of vendor-authored labels and options, not the customer's UI choice.

CREATE OR REPLACE FUNCTION eogp.get_published_public_booking_form(
  p_organization_slug text,
  p_form_code text
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
     OR length(p_form_code) > 80 THEN
    RETURN NULL;
  END IF;

  SELECT organization_id INTO v_organization_id
    FROM eogp.public_organization_routes
   WHERE organization_slug = trim(p_organization_slug)
     AND is_active = true;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  PERFORM set_config('app.organization_id', v_organization_id::text, true);

  SELECT jsonb_build_object(
    'organizationId', organization.id,
    'organizationSlug', organization.slug,
    'organizationName', organization.name,
    'defaultLocale', organization.default_locale,
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
    JOIN LATERAL (
      SELECT candidate.id, candidate.revision_number, candidate.locale,
             candidate.field_schema, candidate.published_at
        FROM eogp.booking_form_revisions candidate
       WHERE candidate.organization_id = definition.organization_id
         AND candidate.form_definition_id = definition.id
         AND candidate.state = 'published'
         AND candidate.published_at IS NOT NULL
       ORDER BY candidate.published_at DESC,
                candidate.revision_number DESC,
                candidate.created_at DESC
       LIMIT 1
    ) revision ON true
   WHERE organization.id = v_organization_id
     AND definition.form_code = p_form_code
     AND definition.status = 'active'
   LIMIT 1;

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.get_published_public_booking_form(text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.get_published_public_booking_form(text,text)
  TO eventor_runtime;

COMMENT ON FUNCTION eogp.get_published_public_booking_form(text,text) IS
  'Unauthenticated read-only projection of one active organization’s latest published booking form, including its customer-facing default locale. Does not expose inquiry, requester, draft, offer or booking data.';
