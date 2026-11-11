-- Published configuration and venue revisions are immutable. Revisioned
-- children must be finalized before publication and cannot be changed after.
CREATE FUNCTION eogp.prevent_published_revision_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
DECLARE
  v_old jsonb := to_jsonb(OLD);
  v_state text := v_old ->> 'state';
  v_published_at text := v_old ->> 'published_at';
BEGIN
  IF v_state IN ('published','retired') OR v_published_at IS NOT NULL THEN
    RAISE EXCEPTION 'published revision %.% is immutable', TG_TABLE_SCHEMA, TG_TABLE_NAME
      USING ERRCODE = '55000';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$function$;

DO $block$
DECLARE
  table_name text;
  revision_tables text[] := ARRAY[
    'config_catalogue_revisions',
    'config_catalogue_option_revisions',
    'booking_form_revisions',
    'booking_price_list_revisions',
    'cancellation_policy_revisions',
    'rsvp_policy_revisions',
    'notification_template_revisions',
    'event_capability_revisions',
    'venue_space_revisions'
  ];
BEGIN
  FOREACH table_name IN ARRAY revision_tables LOOP
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON eogp.%I FOR EACH ROW EXECUTE FUNCTION eogp.prevent_published_revision_mutation()',
      table_name || '_published_immutable_guard', table_name
    );
  END LOOP;
END;
$block$;

-- Child records are mutable while the parent revision is a draft. Check both
-- OLD and NEW parents on updates so rows cannot be moved into a published version.
CREATE FUNCTION eogp.assert_revision_parent_mutable(
  p_table_name text,
  p_row jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_organization_id uuid := (p_row ->> 'organization_id')::uuid;
  v_state text;
  v_published_at timestamptz;
  v_parent_id uuid;
BEGIN
  IF v_organization_id IS NULL
     OR v_organization_id <> eogp.current_organization_id() THEN
    RAISE EXCEPTION 'tenant context is required to modify revision children'
      USING ERRCODE = '42501';
  END IF;

  CASE p_table_name
    WHEN 'config_catalogue_revision_options' THEN
      v_parent_id := (p_row ->> 'catalogue_revision_id')::uuid;
      SELECT state, published_at INTO v_state, v_published_at
        FROM eogp.config_catalogue_revisions
       WHERE organization_id = v_organization_id AND id = v_parent_id;
    WHEN 'booking_form_catalogue_bindings' THEN
      v_parent_id := (p_row ->> 'form_revision_id')::uuid;
      SELECT state, published_at INTO v_state, v_published_at
        FROM eogp.booking_form_revisions
       WHERE organization_id = v_organization_id AND id = v_parent_id;
    WHEN 'booking_price_items' THEN
      v_parent_id := (p_row ->> 'price_list_revision_id')::uuid;
      SELECT state, published_at INTO v_state, v_published_at
        FROM eogp.booking_price_list_revisions
       WHERE organization_id = v_organization_id AND id = v_parent_id;
    WHEN 'floor_plan_assets' THEN
      v_parent_id := (p_row ->> 'venue_space_revision_id')::uuid;
      SELECT NULL::text, published_at INTO v_state, v_published_at
        FROM eogp.venue_space_revisions
       WHERE organization_id = v_organization_id AND id = v_parent_id;
    WHEN 'spatial_layers' THEN
      v_parent_id := (p_row ->> 'venue_space_revision_id')::uuid;
      SELECT NULL::text, published_at INTO v_state, v_published_at
        FROM eogp.venue_space_revisions
       WHERE organization_id = v_organization_id AND id = v_parent_id;
    WHEN 'spatial_objects' THEN
      v_parent_id := (p_row ->> 'layer_id')::uuid;
      SELECT NULL::text, revision.published_at INTO v_state, v_published_at
        FROM eogp.spatial_layers AS layer
        JOIN eogp.venue_space_revisions AS revision
          ON revision.organization_id = layer.organization_id
         AND revision.id = layer.venue_space_revision_id
       WHERE layer.organization_id = v_organization_id
         AND layer.id = v_parent_id;
    ELSE
      RAISE EXCEPTION 'unsupported revision-child table: %', p_table_name
        USING ERRCODE = '22023';
  END CASE;

  IF FOUND AND (v_state IN ('published','retired') OR v_published_at IS NOT NULL) THEN
    RAISE EXCEPTION 'children of published revision %.% are immutable', 'eogp', p_table_name
      USING ERRCODE = '55000';
  END IF;
END;
$function$;

CREATE FUNCTION eogp.protect_published_revision_children()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  IF TG_OP <> 'INSERT' THEN
    PERFORM eogp.assert_revision_parent_mutable(TG_TABLE_NAME, to_jsonb(OLD));
  END IF;
  IF TG_OP <> 'DELETE' THEN
    PERFORM eogp.assert_revision_parent_mutable(TG_TABLE_NAME, to_jsonb(NEW));
    RETURN NEW;
  END IF;
  RETURN OLD;
END;
$function$;

DO $block$
DECLARE
  table_name text;
  child_tables text[] := ARRAY[
    'config_catalogue_revision_options',
    'booking_form_catalogue_bindings',
    'booking_price_items',
    'floor_plan_assets',
    'spatial_layers',
    'spatial_objects'
  ];
BEGIN
  FOREACH table_name IN ARRAY child_tables LOOP
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE INSERT OR UPDATE OR DELETE ON eogp.%I FOR EACH ROW EXECUTE FUNCTION eogp.protect_published_revision_children()',
      table_name || '_published_parent_guard', table_name
    );
  END LOOP;
END;
$block$;

-- Offer terms may be edited only before issue. After issue, the only mutable
-- fields are the terminal decision state and acceptance timestamp.
CREATE FUNCTION eogp.protect_issued_booking_offer_revision()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  IF OLD.issued_at IS NOT NULL THEN
    IF TG_OP = 'DELETE' THEN
      RAISE EXCEPTION 'issued booking offer revisions are immutable'
        USING ERRCODE = '55000';
    END IF;

    IF (to_jsonb(NEW) - 'state' - 'accepted_at')
       IS DISTINCT FROM (to_jsonb(OLD) - 'state' - 'accepted_at')
       OR OLD.state <> 'issued'
       OR NEW.state NOT IN ('accepted','rejected','expired','withdrawn')
       OR (NEW.state = 'accepted' AND NEW.accepted_at IS NULL)
       OR (NEW.state <> 'accepted' AND NEW.accepted_at IS NOT NULL) THEN
      RAISE EXCEPTION 'issued booking offer terms are immutable; only one terminal decision is allowed'
        USING ERRCODE = '55000';
    END IF;
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER booking_offer_revisions_issued_immutable_guard
  BEFORE UPDATE OR DELETE ON eogp.booking_offer_revisions
  FOR EACH ROW EXECUTE FUNCTION eogp.protect_issued_booking_offer_revision();

-- These records are revisions by definition; edits create a successor row.
CREATE TRIGGER booking_draft_revisions_append_only_guard
  BEFORE UPDATE OR DELETE ON eogp.booking_draft_revisions
  FOR EACH ROW EXECUTE FUNCTION eogp.reject_append_only_mutation();

CREATE TRIGGER invitation_revisions_append_only_guard
  BEFORE UPDATE OR DELETE ON eogp.invitation_revisions
  FOR EACH ROW EXECUTE FUNCTION eogp.reject_append_only_mutation();

REVOKE ALL ON FUNCTION eogp.prevent_published_revision_mutation() FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.assert_revision_parent_mutable(text,jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.protect_published_revision_children() FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.protect_issued_booking_offer_revision() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.assert_revision_parent_mutable(text,jsonb),
  eogp.protect_published_revision_children(),
  eogp.protect_issued_booking_offer_revision()
  TO eventor_runtime, eventor_worker;
