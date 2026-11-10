-- Enforce collaboration scope at the point where a grant is used.
-- A valid grant for one booking/space must not authorize another aggregate.

ALTER TABLE eogp.booking_event_links
  ADD COLUMN created_by_membership_id uuid NOT NULL,
  ADD CONSTRAINT booking_event_links_creator_membership_fk
    FOREIGN KEY (organization_id, created_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id);

ALTER TABLE eogp.event_venue_snapshots
  ADD COLUMN created_by_membership_id uuid NOT NULL,
  ADD CONSTRAINT event_venue_snapshots_creator_membership_fk
    FOREIGN KEY (organization_id, created_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id);

-- The organizer may read the explicitly approved share record. The provider
-- remains its sole writer and the sole owner of source venue geometry.
DROP POLICY tenant_isolation ON eogp.venue_snapshot_shares;
CREATE POLICY venue_snapshot_share_parties ON eogp.venue_snapshot_shares
  USING (
    organization_id = eogp.current_organization_id()
    OR event_owner_organization_id = eogp.current_organization_id()
  )
  WITH CHECK (organization_id = eogp.current_organization_id());

CREATE FUNCTION eogp.enforce_booking_event_link_grant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_organization_id uuid := eogp.current_organization_id();
  v_member_status text;
  v_grant_status text;
  v_scope_kind text;
  v_scope_booking_id uuid;
  v_valid_from timestamptz;
  v_valid_until timestamptz;
  v_allowed_actions text[];
BEGIN
  IF v_organization_id IS NULL OR NEW.organization_id <> v_organization_id THEN
    RAISE EXCEPTION 'event-owner tenant context is required for a booking-event link'
      USING ERRCODE = '42501';
  END IF;

  IF TG_OP = 'INSERT' AND NEW.status <> 'active' THEN
    RAISE EXCEPTION 'new booking-event links must start active'
      USING ERRCODE = '23514';
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF OLD.status <> 'active'
       OR NEW.status NOT IN ('ended','revoked')
       OR (to_jsonb(NEW) - 'status') IS DISTINCT FROM (to_jsonb(OLD) - 'status') THEN
      RAISE EXCEPTION 'booking-event links are immutable except for one-way ending/revocation'
        USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
  END IF;

  SELECT status INTO v_member_status
    FROM eogp.organization_memberships
   WHERE organization_id = v_organization_id
     AND id = NEW.created_by_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_member_status <> 'active' THEN
    RAISE EXCEPTION 'active event-owner membership is required to create a booking-event link'
      USING ERRCODE = '42501';
  END IF;

  IF NEW.organization_id = NEW.booking_owner_organization_id THEN
    IF NEW.collaboration_grant_id IS NOT NULL
       OR NEW.grant_owner_organization_id IS NOT NULL THEN
      RAISE EXCEPTION 'same-tenant booking-event links must not carry a collaboration grant'
        USING ERRCODE = '23514';
    END IF;
  ELSE
    SELECT status, scope_kind, scope_booking_id, valid_from, valid_until, allowed_actions
      INTO v_grant_status, v_scope_kind, v_scope_booking_id,
           v_valid_from, v_valid_until, v_allowed_actions
      FROM eogp.collaboration_grants
     WHERE organization_id = NEW.booking_owner_organization_id
       AND grantee_organization_id = NEW.organization_id
       AND id = NEW.collaboration_grant_id
     FOR UPDATE;

    IF NOT FOUND
       OR v_grant_status <> 'active'
       OR v_valid_from > clock_timestamp()
       OR (v_valid_until IS NOT NULL AND v_valid_until <= clock_timestamp())
       OR v_scope_kind <> 'booking'
       OR v_scope_booking_id IS DISTINCT FROM NEW.booking_id
       OR NOT (v_allowed_actions @> ARRAY['booking.event.link']::text[]) THEN
      RAISE EXCEPTION 'an active booking-scoped booking.event.link grant is required'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    authorization_grant_owner_organization_id, authorization_grant_id,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    NEW.organization_id, NEW.organization_id, NEW.created_by_membership_id, 'membership',
    NEW.grant_owner_organization_id, NEW.collaboration_grant_id,
    'booking.event.linked', 'booking_event_link', NEW.id,
    jsonb_build_object(
      'bookingOwnerOrganizationId', NEW.booking_owner_organization_id,
      'bookingId', NEW.booking_id,
      'eventId', NEW.event_id,
      'relationshipKind', NEW.relationship_kind
    )
  );

  RETURN NEW;
END;
$function$;

CREATE TRIGGER booking_event_links_grant_guard
  BEFORE INSERT OR UPDATE ON eogp.booking_event_links
  FOR EACH ROW EXECUTE FUNCTION eogp.enforce_booking_event_link_grant();

CREATE FUNCTION eogp.enforce_venue_snapshot_share_grant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_member_status text;
  v_grant_status text;
  v_scope_kind text;
  v_scope_venue_id uuid;
  v_scope_space_id uuid;
  v_valid_from timestamptz;
  v_valid_until timestamptz;
  v_revision_space_id uuid;
  v_revision_hash text;
  v_revision_published_at timestamptz;
  v_venue_id uuid;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF OLD.status <> 'active'
       OR NEW.status NOT IN ('revoked','expired')
       OR (to_jsonb(NEW) - 'status') IS DISTINCT FROM (to_jsonb(OLD) - 'status') THEN
      RAISE EXCEPTION 'venue snapshot shares are immutable except for one-way revocation/expiry'
        USING ERRCODE = '55000';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.status <> 'active'
     OR jsonb_typeof(NEW.approved_layers) IS DISTINCT FROM 'array'
     OR jsonb_typeof(NEW.approved_resources) IS DISTINCT FROM 'array'
     OR NEW.approved_at > clock_timestamp() THEN
    RAISE EXCEPTION 'new venue snapshot shares must be active with array projections'
      USING ERRCODE = '22023';
  END IF;

  SELECT status, scope_kind, scope_venue_id, scope_space_id,
         valid_from, valid_until
    INTO v_grant_status, v_scope_kind, v_scope_venue_id, v_scope_space_id,
         v_valid_from, v_valid_until
    FROM eogp.collaboration_grants
   WHERE organization_id = NEW.organization_id
     AND grantee_organization_id = NEW.event_owner_organization_id
     AND id = NEW.collaboration_grant_id
   FOR UPDATE;

  IF NOT FOUND
     OR v_grant_status <> 'active'
     OR NEW.approved_at < v_valid_from
     OR (v_valid_until IS NOT NULL AND NEW.approved_at >= v_valid_until) THEN
    RAISE EXCEPTION 'an active grant covering the venue-space revision is required'
      USING ERRCODE = '42501';
  END IF;

  SELECT status INTO v_member_status
    FROM eogp.organization_memberships
   WHERE organization_id = NEW.organization_id
     AND id = NEW.approved_by_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_member_status <> 'active' THEN
    RAISE EXCEPTION 'active venue-provider membership is required to approve a snapshot share'
      USING ERRCODE = '42501';
  END IF;

  SELECT revision.venue_space_id, revision.content_sha256,
         revision.published_at, space.venue_id
    INTO v_revision_space_id, v_revision_hash,
         v_revision_published_at, v_venue_id
    FROM eogp.venue_space_revisions AS revision
    JOIN eogp.venue_spaces AS space
      ON space.organization_id = revision.organization_id
     AND space.id = revision.venue_space_id
   WHERE revision.organization_id = NEW.organization_id
     AND revision.id = NEW.venue_space_revision_id
   FOR SHARE OF revision, space;

  IF NOT FOUND
     OR v_revision_published_at IS NULL
     OR v_revision_hash <> NEW.source_content_sha256 THEN
    RAISE EXCEPTION 'snapshot share must reference the exact published source revision and hash'
      USING ERRCODE = '23514';
  END IF;

  IF NOT (
    (v_scope_kind = 'venue' AND v_scope_venue_id = v_venue_id)
    OR
    (v_scope_kind = 'space' AND v_scope_space_id = v_revision_space_id)
  ) THEN
    RAISE EXCEPTION 'collaboration grant scope does not cover the requested venue-space revision'
      USING ERRCODE = '42501';
  END IF;

  IF v_valid_until IS NOT NULL
     AND (NEW.expires_at IS NULL OR NEW.expires_at > v_valid_until) THEN
    RAISE EXCEPTION 'snapshot share cannot outlive its collaboration grant'
      USING ERRCODE = '22023';
  END IF;

  IF NEW.expires_at IS NOT NULL AND NEW.expires_at <= NEW.approved_at THEN
    RAISE EXCEPTION 'snapshot share expiry must follow approval'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    authorization_grant_owner_organization_id, authorization_grant_id,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    NEW.organization_id, NEW.organization_id, NEW.approved_by_membership_id, 'membership',
    NEW.organization_id, NEW.collaboration_grant_id,
    'venue.snapshot.shared', 'venue_snapshot_share', NEW.id,
    jsonb_build_object(
      'eventOwnerOrganizationId', NEW.event_owner_organization_id,
      'eventId', NEW.event_id,
      'venueSpaceRevisionId', NEW.venue_space_revision_id,
      'sourceContentSha256', NEW.source_content_sha256
    )
  );

  RETURN NEW;
END;
$function$;

CREATE TRIGGER venue_snapshot_shares_grant_guard
  BEFORE INSERT OR UPDATE ON eogp.venue_snapshot_shares
  FOR EACH ROW EXECUTE FUNCTION eogp.enforce_venue_snapshot_share_grant();

CREATE FUNCTION eogp.enforce_event_venue_snapshot_grant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_share_status text;
  v_share_expires_at timestamptz;
  v_grant_status text;
  v_grant_valid_from timestamptz;
  v_grant_valid_until timestamptz;
  v_grant_actions text[];
  v_actor_status text;
  v_grant_owner_organization_id uuid;
  v_grant_id uuid;
BEGIN
  SELECT share.status, share.expires_at,
         collab.status, collab.valid_from, collab.valid_until, collab.allowed_actions,
         share.organization_id, share.collaboration_grant_id
    INTO v_share_status, v_share_expires_at,
         v_grant_status, v_grant_valid_from, v_grant_valid_until, v_grant_actions,
         v_grant_owner_organization_id, v_grant_id
    FROM eogp.venue_snapshot_shares AS share
    JOIN eogp.collaboration_grants AS collab
      ON collab.organization_id = share.organization_id
     AND collab.grantee_organization_id = share.event_owner_organization_id
     AND collab.id = share.collaboration_grant_id
   WHERE share.organization_id = NEW.share_owner_organization_id
     AND share.event_owner_organization_id = NEW.organization_id
     AND share.event_id = NEW.event_id
     AND share.id = NEW.snapshot_share_id
   FOR UPDATE OF share, collab;

  IF NOT FOUND
     OR v_share_status <> 'active'
     OR (v_share_expires_at IS NOT NULL AND v_share_expires_at <= clock_timestamp())
     OR v_grant_status <> 'active'
     OR v_grant_valid_from > clock_timestamp()
     OR (v_grant_valid_until IS NOT NULL AND v_grant_valid_until <= clock_timestamp())
     OR NOT (v_grant_actions @> ARRAY['venue.snapshot.use']::text[]) THEN
    RAISE EXCEPTION 'new event venue snapshots require an active, unexpired approved share and grant'
      USING ERRCODE = '42501';
  END IF;

  SELECT status INTO v_actor_status
    FROM eogp.organization_memberships
   WHERE organization_id = NEW.organization_id
     AND id = NEW.created_by_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_actor_status <> 'active' THEN
    RAISE EXCEPTION 'active event-owner membership is required to copy a venue snapshot'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO eogp.audit_events (
    organization_id, actor_organization_id, actor_membership_id, actor_kind,
    authorization_grant_owner_organization_id, authorization_grant_id,
    action, aggregate_type, aggregate_id, safe_metadata
  ) VALUES (
    NEW.organization_id, NEW.organization_id, NEW.created_by_membership_id, 'membership',
    v_grant_owner_organization_id, v_grant_id,
    'venue.snapshot.copied', 'event_venue_snapshot', NEW.id,
    jsonb_build_object(
      'shareId', NEW.snapshot_share_id,
      'sourceSpaceRevisionId', NEW.source_space_revision_id,
      'sourceContentSha256', NEW.source_content_sha256
    )
  );

  RETURN NEW;
END;
$function$;

CREATE TRIGGER event_venue_snapshots_grant_guard
  BEFORE INSERT ON eogp.event_venue_snapshots
  FOR EACH ROW EXECUTE FUNCTION eogp.enforce_event_venue_snapshot_grant();

-- A copied snapshot is historical data, but new operational bindings and
-- additions to its immutable child projection require a current use grant.
CREATE FUNCTION eogp.assert_event_venue_snapshot_usable(
  p_organization_id uuid,
  p_snapshot_id uuid
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_current_organization_id uuid := eogp.current_organization_id();
  v_share_status text;
  v_share_expires_at timestamptz;
  v_grant_status text;
  v_grant_valid_from timestamptz;
  v_grant_valid_until timestamptz;
  v_grant_actions text[];
BEGIN
  IF v_current_organization_id IS NULL
     OR v_current_organization_id <> p_organization_id THEN
    RAISE EXCEPTION 'event-owner tenant context is required to use a venue snapshot'
      USING ERRCODE = '42501';
  END IF;

  SELECT share.status, share.expires_at,
         collab.status, collab.valid_from, collab.valid_until, collab.allowed_actions
    INTO v_share_status, v_share_expires_at,
         v_grant_status, v_grant_valid_from, v_grant_valid_until, v_grant_actions
    FROM eogp.event_venue_snapshots AS snapshot
    JOIN eogp.venue_snapshot_shares AS share
      ON share.organization_id = snapshot.share_owner_organization_id
     AND share.event_owner_organization_id = snapshot.organization_id
     AND share.event_id = snapshot.event_id
     AND share.id = snapshot.snapshot_share_id
    JOIN eogp.collaboration_grants AS collab
      ON collab.organization_id = share.organization_id
     AND collab.grantee_organization_id = share.event_owner_organization_id
     AND collab.id = share.collaboration_grant_id
   WHERE snapshot.organization_id = p_organization_id
     AND snapshot.id = p_snapshot_id
   FOR UPDATE OF share, collab;

  IF NOT FOUND
     OR v_share_status <> 'active'
     OR (v_share_expires_at IS NOT NULL AND v_share_expires_at <= clock_timestamp())
     OR v_grant_status <> 'active'
     OR v_grant_valid_from > clock_timestamp()
     OR (v_grant_valid_until IS NOT NULL AND v_grant_valid_until <= clock_timestamp())
     OR NOT (v_grant_actions @> ARRAY['venue.snapshot.use']::text[]) THEN
    RAISE EXCEPTION 'new operational use requires a current active venue.snapshot.use grant and share'
      USING ERRCODE = '42501';
  END IF;
END;
$function$;

ALTER TABLE eogp.event_session_spaces
  ADD COLUMN created_by_membership_id uuid NOT NULL,
  ADD CONSTRAINT event_session_spaces_creator_membership_fk
    FOREIGN KEY (organization_id, created_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id);

CREATE FUNCTION eogp.enforce_event_session_space_snapshot_grant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_current_organization_id uuid := eogp.current_organization_id();
  v_actor_status text;
BEGIN
  IF v_current_organization_id IS NULL
     OR NEW.organization_id <> v_current_organization_id THEN
    RAISE EXCEPTION 'event-owner tenant context is required to bind a venue snapshot to a session'
      USING ERRCODE = '42501';
  END IF;

  SELECT status INTO v_actor_status
    FROM eogp.organization_memberships
   WHERE organization_id = v_current_organization_id
     AND id = NEW.created_by_membership_id
   FOR SHARE;
  IF NOT FOUND OR v_actor_status <> 'active' THEN
    RAISE EXCEPTION 'active event-owner membership is required to bind a venue snapshot'
      USING ERRCODE = '42501';
  END IF;

  PERFORM eogp.assert_event_venue_snapshot_usable(
    NEW.organization_id, NEW.event_venue_snapshot_id
  );
  RETURN NEW;
END;
$function$;

CREATE TRIGGER event_session_spaces_snapshot_use_guard
  BEFORE INSERT OR UPDATE ON eogp.event_session_spaces
  FOR EACH ROW EXECUTE FUNCTION eogp.enforce_event_session_space_snapshot_grant();

CREATE FUNCTION eogp.enforce_event_snapshot_child_use()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  PERFORM eogp.assert_event_venue_snapshot_usable(
    NEW.organization_id, NEW.snapshot_id
  );
  RETURN NEW;
END;
$function$;

CREATE TRIGGER event_venue_snapshot_layers_use_guard
  BEFORE INSERT ON eogp.event_venue_snapshot_layers
  FOR EACH ROW EXECUTE FUNCTION eogp.enforce_event_snapshot_child_use();

CREATE TRIGGER event_venue_snapshot_objects_use_guard
  BEFORE INSERT ON eogp.event_venue_snapshot_objects
  FOR EACH ROW EXECUTE FUNCTION eogp.enforce_event_snapshot_child_use();

CREATE TRIGGER event_venue_snapshot_resources_use_guard
  BEFORE INSERT ON eogp.event_venue_snapshot_resources
  FOR EACH ROW EXECUTE FUNCTION eogp.enforce_event_snapshot_child_use();

REVOKE ALL ON FUNCTION eogp.assert_event_venue_snapshot_usable(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.enforce_event_session_space_snapshot_grant() FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.enforce_event_snapshot_child_use() FROM PUBLIC;

REVOKE ALL ON FUNCTION eogp.enforce_booking_event_link_grant() FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.enforce_venue_snapshot_share_grant() FROM PUBLIC;
REVOKE ALL ON FUNCTION eogp.enforce_event_venue_snapshot_grant() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.enforce_booking_event_link_grant(),
  eogp.enforce_venue_snapshot_share_grant(),
  eogp.enforce_event_venue_snapshot_grant()
  TO eventor_runtime, eventor_worker;
