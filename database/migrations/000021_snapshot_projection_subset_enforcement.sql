-- Enforce provider-approved venue snapshot projections at the database boundary.
-- Approved layer/resource arrays contain UUID strings matching the OpenAPI
-- approvedLayerIds / approvedResourceIds request fields.

CREATE FUNCTION eogp.validate_venue_snapshot_approved_projection()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_venue_id uuid;
  v_requested_layers integer;
  v_matched_layers integer;
  v_requested_resources integer;
  v_matched_resources integer;
BEGIN
  IF jsonb_typeof(NEW.approved_layers) IS DISTINCT FROM 'array'
     OR jsonb_typeof(NEW.approved_resources) IS DISTINCT FROM 'array' THEN
    RAISE EXCEPTION 'approved layer/resource projections must be JSON arrays'
      USING ERRCODE = '22023';
  END IF;

  SELECT space.venue_id
    INTO v_venue_id
    FROM eogp.venue_space_revisions AS revision
    JOIN eogp.venue_spaces AS space
      ON space.organization_id = revision.organization_id
     AND space.id = revision.venue_space_id
   WHERE revision.organization_id = NEW.organization_id
     AND revision.id = NEW.venue_space_revision_id
   FOR SHARE OF revision, space;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'venue snapshot projection source revision was not found'
      USING ERRCODE = '23503';
  END IF;

  v_requested_layers := jsonb_array_length(NEW.approved_layers);
  SELECT count(*)
    INTO v_matched_layers
    FROM eogp.spatial_layers AS layer
   WHERE layer.organization_id = NEW.organization_id
     AND layer.venue_space_revision_id = NEW.venue_space_revision_id
     AND NEW.approved_layers @> jsonb_build_array(layer.id::text);

  IF v_requested_layers <> v_matched_layers THEN
    RAISE EXCEPTION 'approved layer projection contains duplicates or IDs outside the selected source revision'
      USING ERRCODE = '22023';
  END IF;

  v_requested_resources := jsonb_array_length(NEW.approved_resources);
  SELECT count(*)
    INTO v_matched_resources
    FROM (
      SELECT pool.id
        FROM eogp.resource_pools AS pool
       WHERE pool.organization_id = NEW.organization_id
         AND pool.venue_id = v_venue_id
      UNION
      SELECT unit.id
        FROM eogp.resource_units AS unit
        JOIN eogp.resource_pools AS pool
          ON pool.organization_id = unit.organization_id
         AND pool.id = unit.resource_pool_id
       WHERE unit.organization_id = NEW.organization_id
         AND pool.venue_id = v_venue_id
    ) AS venue_resources
   WHERE NEW.approved_resources @> jsonb_build_array(venue_resources.id::text);

  IF v_requested_resources <> v_matched_resources THEN
    RAISE EXCEPTION 'approved resource projection contains duplicates or IDs outside the source venue'
      USING ERRCODE = '22023';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER venue_snapshot_shares_approved_projection_guard
  BEFORE INSERT ON eogp.venue_snapshot_shares
  FOR EACH ROW EXECUTE FUNCTION eogp.validate_venue_snapshot_approved_projection();

CREATE FUNCTION eogp.enforce_snapshot_layer_projection()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_revision_id uuid;
  v_approved_layers jsonb;
BEGIN
  SELECT snapshot.source_space_revision_id, share.approved_layers
    INTO v_revision_id, v_approved_layers
    FROM eogp.event_venue_snapshots AS snapshot
    JOIN eogp.venue_snapshot_shares AS share
      ON share.organization_id = snapshot.share_owner_organization_id
     AND share.event_owner_organization_id = snapshot.organization_id
     AND share.event_id = snapshot.event_id
     AND share.id = snapshot.snapshot_share_id
   WHERE snapshot.organization_id = NEW.organization_id
     AND snapshot.id = NEW.snapshot_id
   FOR SHARE OF share;

  IF NOT FOUND
     OR NEW.source_layer_id IS NULL
     OR NOT (v_approved_layers @> jsonb_build_array(NEW.source_layer_id::text))
     OR NOT EXISTS (
       SELECT 1
         FROM eogp.spatial_layers AS source_layer
        WHERE source_layer.organization_id = NEW.organization_id
          AND source_layer.venue_space_revision_id = v_revision_id
          AND source_layer.id = NEW.source_layer_id
     ) THEN
    RAISE EXCEPTION 'snapshot layer must reference a provider-approved layer from the shared source revision'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER event_venue_snapshot_layers_projection_guard
  BEFORE INSERT ON eogp.event_venue_snapshot_layers
  FOR EACH ROW EXECUTE FUNCTION eogp.enforce_snapshot_layer_projection();

CREATE FUNCTION eogp.enforce_snapshot_object_projection()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_revision_id uuid;
  v_approved_layers jsonb;
BEGIN
  SELECT snapshot.source_space_revision_id, share.approved_layers
    INTO v_revision_id, v_approved_layers
    FROM eogp.event_venue_snapshots AS snapshot
    JOIN eogp.venue_snapshot_shares AS share
      ON share.organization_id = snapshot.share_owner_organization_id
     AND share.event_owner_organization_id = snapshot.organization_id
     AND share.event_id = snapshot.event_id
     AND share.id = snapshot.snapshot_share_id
   WHERE snapshot.organization_id = NEW.organization_id
     AND snapshot.id = NEW.snapshot_id
   FOR SHARE OF share;

  IF NOT FOUND
     OR NEW.source_object_id IS NULL
     OR NOT EXISTS (
       SELECT 1
         FROM eogp.spatial_objects AS source_object
         JOIN eogp.spatial_layers AS source_layer
           ON source_layer.organization_id = source_object.organization_id
          AND source_layer.id = source_object.layer_id
        WHERE source_object.organization_id = NEW.organization_id
          AND source_object.id = NEW.source_object_id
          AND source_layer.venue_space_revision_id = v_revision_id
          AND v_approved_layers @> jsonb_build_array(source_layer.id::text)
     ) THEN
    RAISE EXCEPTION 'snapshot object must reference a source object in a provider-approved layer'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER event_venue_snapshot_objects_projection_guard
  BEFORE INSERT ON eogp.event_venue_snapshot_objects
  FOR EACH ROW EXECUTE FUNCTION eogp.enforce_snapshot_object_projection();

CREATE FUNCTION eogp.enforce_snapshot_resource_projection()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_venue_id uuid;
  v_approved_resources jsonb;
  v_source_resource_id uuid;
BEGIN
  SELECT share.approved_resources, space.venue_id
    INTO v_approved_resources, v_venue_id
    FROM eogp.event_venue_snapshots AS snapshot
    JOIN eogp.venue_snapshot_shares AS share
      ON share.organization_id = snapshot.share_owner_organization_id
     AND share.event_owner_organization_id = snapshot.organization_id
     AND share.event_id = snapshot.event_id
     AND share.id = snapshot.snapshot_share_id
    JOIN eogp.venue_space_revisions AS revision
      ON revision.organization_id = snapshot.source_organization_id
     AND revision.id = snapshot.source_space_revision_id
    JOIN eogp.venue_spaces AS space
      ON space.organization_id = revision.organization_id
     AND space.id = revision.venue_space_id
   WHERE snapshot.organization_id = NEW.organization_id
     AND snapshot.id = NEW.snapshot_id
   FOR SHARE OF share;

  v_source_resource_id := coalesce(NEW.source_resource_unit_id, NEW.source_resource_pool_id);

  IF NOT FOUND
     OR v_source_resource_id IS NULL
     OR NOT (v_approved_resources @> jsonb_build_array(v_source_resource_id::text))
     OR NOT (
       EXISTS (
         SELECT 1
           FROM eogp.resource_pools AS pool
          WHERE pool.organization_id = NEW.organization_id
            AND pool.id = v_source_resource_id
            AND pool.venue_id = v_venue_id
       )
       OR EXISTS (
         SELECT 1
           FROM eogp.resource_units AS unit
           JOIN eogp.resource_pools AS pool
             ON pool.organization_id = unit.organization_id
            AND pool.id = unit.resource_pool_id
          WHERE unit.organization_id = NEW.organization_id
            AND unit.id = v_source_resource_id
            AND pool.venue_id = v_venue_id
       )
     ) THEN
    RAISE EXCEPTION 'snapshot resource must be in the provider-approved resource projection'
      USING ERRCODE = '42501';
  END IF;

  RETURN NEW;
END;
$function$;

CREATE TRIGGER event_venue_snapshot_resources_projection_guard
  BEFORE INSERT ON eogp.event_venue_snapshot_resources
  FOR EACH ROW EXECUTE FUNCTION eogp.enforce_snapshot_resource_projection();

REVOKE ALL ON FUNCTION eogp.validate_venue_snapshot_approved_projection() FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.enforce_snapshot_layer_projection() FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.enforce_snapshot_object_projection() FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.enforce_snapshot_resource_projection() FROM PUBLIC;
