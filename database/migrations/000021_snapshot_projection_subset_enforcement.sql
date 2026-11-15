-- Source rows remain provider-owned. RLS grants a recipient visibility
-- only over the exact source revision while the corresponding use grant and
-- share remain live.
CREATE FUNCTION eogp.has_active_venue_snapshot_share(
  p_source_organization_id uuid,
  p_source_revision_id uuid
) RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
  SELECT EXISTS (
    SELECT 1
      FROM eogp.venue_snapshot_shares AS share
      JOIN eogp.collaboration_grants AS collab
        ON collab.organization_id = share.organization_id
       AND collab.grantee_organization_id = share.event_owner_organization_id
       AND collab.id = share.collaboration_grant_id
     WHERE share.organization_id = p_source_organization_id
       AND share.venue_space_revision_id = p_source_revision_id
       AND share.event_owner_organization_id = eogp.current_organization_id()
       AND share.status = 'active'
       AND (share.expires_at IS NULL OR share.expires_at > statement_timestamp())
       AND collab.status = 'active'
       AND collab.valid_from <= statement_timestamp()
       AND (collab.valid_until IS NULL OR collab.valid_until > statement_timestamp())
       AND collab.allowed_actions @> ARRAY['venue.snapshot.use']::text[]
  );
$function$;

REVOKE ALL ON FUNCTION eogp.has_active_venue_snapshot_share(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.has_active_venue_snapshot_share(uuid,uuid)
  TO eventor_owner, eventor_runtime;

-- The policies are additive to tenant_isolation and expose only the exact
-- shared source rows. The copied event-owned snapshot remains independently
-- available after revocation; source master rows do not.
CREATE POLICY venue_space_revisions_active_share_read
  ON eogp.venue_space_revisions
  FOR SELECT TO eventor_owner, eventor_runtime
  USING (
    organization_id <> eogp.current_organization_id()
    AND eogp.has_active_venue_snapshot_share(organization_id, id)
  );

CREATE POLICY venue_spaces_active_share_read
  ON eogp.venue_spaces
  FOR SELECT TO eventor_owner, eventor_runtime
  USING (
    organization_id <> eogp.current_organization_id()
    AND EXISTS (
      SELECT 1
        FROM eogp.venue_space_revisions AS revision
       WHERE revision.organization_id = venue_spaces.organization_id
         AND revision.venue_space_id = venue_spaces.id
         AND eogp.has_active_venue_snapshot_share(
               revision.organization_id, revision.id
             )
    )
  );

CREATE POLICY spatial_layers_active_share_read
  ON eogp.spatial_layers
  FOR SELECT TO eventor_owner, eventor_runtime
  USING (
    organization_id <> eogp.current_organization_id()
    AND EXISTS (
      SELECT 1
        FROM eogp.venue_snapshot_shares AS share
       WHERE share.organization_id = spatial_layers.organization_id
         AND share.venue_space_revision_id = spatial_layers.venue_space_revision_id
         AND share.event_owner_organization_id = eogp.current_organization_id()
         AND share.status = 'active'
         AND (share.expires_at IS NULL OR share.expires_at > statement_timestamp())
         AND share.approved_layers @> jsonb_build_array(spatial_layers.id::text)
         AND eogp.has_active_venue_snapshot_share(
               share.organization_id, share.venue_space_revision_id
             )
    )
  );

CREATE POLICY spatial_objects_active_share_read
  ON eogp.spatial_objects
  FOR SELECT TO eventor_owner, eventor_runtime
  USING (
    organization_id <> eogp.current_organization_id()
    AND EXISTS (
      SELECT 1
        FROM eogp.spatial_layers AS layer
       WHERE layer.organization_id = spatial_objects.organization_id
         AND layer.id = spatial_objects.layer_id
         AND eogp.has_active_venue_snapshot_share(
               layer.organization_id, layer.venue_space_revision_id
             )
    )
  );

CREATE POLICY resource_pools_active_share_read
  ON eogp.resource_pools
  FOR SELECT TO eventor_owner, eventor_runtime
  USING (
    organization_id <> eogp.current_organization_id()
    AND EXISTS (
      SELECT 1
        FROM eogp.venue_snapshot_shares AS share
       WHERE share.organization_id = resource_pools.organization_id
         AND share.event_owner_organization_id = eogp.current_organization_id()
         AND share.status = 'active'
         AND (share.expires_at IS NULL OR share.expires_at > statement_timestamp())
         AND share.approved_resources @> jsonb_build_array(resource_pools.id::text)
         AND eogp.has_active_venue_snapshot_share(
               share.organization_id, share.venue_space_revision_id
             )
    )
  );

CREATE POLICY resource_units_active_share_read
  ON eogp.resource_units
  FOR SELECT TO eventor_owner, eventor_runtime
  USING (
    organization_id <> eogp.current_organization_id()
    AND EXISTS (
      SELECT 1
        FROM eogp.venue_snapshot_shares AS share
       WHERE share.organization_id = resource_units.organization_id
         AND share.event_owner_organization_id = eogp.current_organization_id()
         AND share.status = 'active'
         AND (share.expires_at IS NULL OR share.expires_at > statement_timestamp())
         AND share.approved_resources @> jsonb_build_array(resource_units.id::text)
         AND eogp.has_active_venue_snapshot_share(
               share.organization_id, share.venue_space_revision_id
             )
    )
  );

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
      UNION ALL
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
  v_source_organization_id uuid;
  v_revision_id uuid;
  v_approved_layers jsonb;
BEGIN
  SELECT snapshot.source_organization_id, snapshot.source_space_revision_id, share.approved_layers
    INTO v_source_organization_id, v_revision_id, v_approved_layers
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
        WHERE source_layer.organization_id = v_source_organization_id
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
  v_source_organization_id uuid;
  v_revision_id uuid;
  v_approved_layers jsonb;
BEGIN
  SELECT snapshot.source_organization_id, snapshot.source_space_revision_id, share.approved_layers
    INTO v_source_organization_id, v_revision_id, v_approved_layers
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
        WHERE source_object.organization_id = v_source_organization_id
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
  v_source_organization_id uuid;
  v_venue_id uuid;
  v_approved_resources jsonb;
  v_source_resource_id uuid;
BEGIN
  SELECT snapshot.source_organization_id, share.approved_resources, space.venue_id
    INTO v_source_organization_id, v_approved_resources, v_venue_id
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
          WHERE pool.organization_id = v_source_organization_id
            AND pool.id = v_source_resource_id
            AND pool.venue_id = v_venue_id
       )
       OR EXISTS (
         SELECT 1
           FROM eogp.resource_units AS unit
           JOIN eogp.resource_pools AS pool
             ON pool.organization_id = unit.organization_id
            AND pool.id = unit.resource_pool_id
          WHERE unit.organization_id = v_source_organization_id
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
