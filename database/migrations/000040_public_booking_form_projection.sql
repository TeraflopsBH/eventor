-- Safely expose published booking forms to unauthenticated visitors.
-- The route directory is private to the database owner; public clients can only
-- call the narrowly scoped projection function below.
CREATE TABLE eogp.public_organization_routes (
    organization_id uuid PRIMARY KEY
      REFERENCES eogp.organizations(id) ON DELETE CASCADE,
    organization_slug text NOT NULL UNIQUE,
    is_active boolean NOT NULL,
    synced_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

REVOKE ALL ON TABLE eogp.public_organization_routes
  FROM PUBLIC, eventor_runtime, eventor_worker, eventor_auth;

INSERT INTO eogp.public_organization_routes (
  organization_id, organization_slug, is_active
)
SELECT id, slug, status = 'active'
  FROM eogp.organizations
ON CONFLICT (organization_id) DO UPDATE
  SET organization_slug = EXCLUDED.organization_slug,
      is_active = EXCLUDED.is_active,
      synced_at = clock_timestamp();

CREATE FUNCTION eogp.sync_public_organization_route()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM eogp.public_organization_routes
     WHERE organization_id = OLD.id;
    RETURN OLD;
  END IF;

  INSERT INTO eogp.public_organization_routes (
    organization_id, organization_slug, is_active
  ) VALUES (
    NEW.id, NEW.slug, NEW.status = 'active'
  )
  ON CONFLICT (organization_id) DO UPDATE
    SET organization_slug = EXCLUDED.organization_slug,
        is_active = EXCLUDED.is_active,
        synced_at = clock_timestamp();
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION eogp.sync_public_organization_route() FROM PUBLIC;

CREATE TRIGGER organizations_public_route_sync
AFTER INSERT OR UPDATE OF slug, status ON eogp.organizations
FOR EACH ROW EXECUTE FUNCTION eogp.sync_public_organization_route();

CREATE FUNCTION eogp.get_published_public_booking_form(
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
   WHERE organization_slug = lower(trim(p_organization_slug))
     AND is_active = true;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- RLS is enabled and forced on tenant data. Establish this tenant only after
  -- resolving an active public route; callers cannot supply an organization ID.
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
  'Unauthenticated, read-only projection of one active organization’s latest published booking form. Does not expose inquiry, requester, draft, offer or booking data.';
