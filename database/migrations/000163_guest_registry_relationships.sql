INSERT INTO eogp.permissions (code, description, scope_kind, is_sensitive) VALUES
  ('guest.registry.relationships.read','Read organization guest relationships','organization',true),
  ('guest.registry.relationships.manage','Record and end organization guest relationships','organization',true);

CREATE TABLE eogp.person_relationships (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  from_person_id uuid NOT NULL,
  to_person_id uuid NOT NULL,
  relationship_kind text NOT NULL CHECK (relationship_kind IN ('household','family','assistant','delegate','colleague','partner','other')),
  directionality text NOT NULL CHECK (directionality IN ('mutual','directed')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  created_by_membership_id uuid NOT NULL,
  ended_at timestamptz,
  ended_by_membership_id uuid,
  FOREIGN KEY (organization_id, from_person_id) REFERENCES eogp.persons(organization_id, id),
  FOREIGN KEY (organization_id, to_person_id) REFERENCES eogp.persons(organization_id, id),
  FOREIGN KEY (organization_id, created_by_membership_id) REFERENCES eogp.organization_memberships(organization_id, id),
  FOREIGN KEY (organization_id, ended_by_membership_id) REFERENCES eogp.organization_memberships(organization_id, id),
  CHECK (from_person_id <> to_person_id),
  CHECK (directionality <> 'mutual' OR from_person_id < to_person_id),
  CHECK ((ended_at IS NULL) = (ended_by_membership_id IS NULL))
);
CREATE UNIQUE INDEX person_relationships_active_pair
  ON eogp.person_relationships(organization_id,from_person_id,to_person_id,relationship_kind,directionality) WHERE ended_at IS NULL;
CREATE INDEX person_relationships_from ON eogp.person_relationships(organization_id,from_person_id);
CREATE INDEX person_relationships_to ON eogp.person_relationships(organization_id,to_person_id);

ALTER TABLE eogp.person_relationships ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.person_relationships FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON eogp.person_relationships
  USING (organization_id = eogp.current_organization_id()) WITH CHECK (organization_id = eogp.current_organization_id());
REVOKE ALL ON eogp.person_relationships FROM PUBLIC, eventor_runtime;

CREATE FUNCTION eogp.assert_guest_registry_relationship_permission(p_org uuid, p_actor uuid, p_write boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
BEGIN
  PERFORM eogp.assert_guest_registry_permission(p_org, p_actor, p_write);
  IF NOT p_write THEN
    BEGIN
      PERFORM eogp.assert_event_command_permission(p_org,NULL,p_actor,'guest.registry.relationships.read');
      RETURN;
    EXCEPTION WHEN insufficient_privilege THEN NULL;
    END;
  END IF;
  PERFORM eogp.assert_event_command_permission(p_org,NULL,p_actor,'guest.registry.relationships.manage');
END;
$function$;

CREATE FUNCTION eogp.read_guest_registry_relationships(p_org uuid, p_actor uuid, p_person uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_relationships jsonb;
  v_status text;
  v_can_manage boolean := true;
BEGIN
  PERFORM eogp.assert_guest_registry_relationship_permission(p_org,p_actor,false);
  SELECT status INTO v_status FROM eogp.persons WHERE organization_id=p_org AND id=p_person;
  IF NOT FOUND THEN RAISE EXCEPTION 'person not found' USING ERRCODE='P0002'; END IF;
  BEGIN
    PERFORM eogp.assert_guest_registry_relationship_permission(p_org,p_actor,true);
  EXCEPTION WHEN insufficient_privilege THEN v_can_manage := false;
  END;
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'relationshipId',link.id,'kind',link.relationship_kind,'endedAt',link.ended_at,
    'relatedPersonId',person.id,'relatedStatus',person.status,
    'relatedDisplayName',coalesce(nullif(person.display_name,''),nullif(person.preferred_name,''),concat_ws(' ',person.first_name,person.last_name)),
    'direction',CASE WHEN link.directionality='mutual' THEN 'mutual'
      WHEN link.from_person_id=p_person THEN 'outgoing' ELSE 'incoming' END
  ) ORDER BY link.ended_at IS NOT NULL, lower(person.last_name), lower(person.first_name), link.id),'[]'::jsonb)
  INTO v_relationships FROM eogp.person_relationships link
  JOIN eogp.persons person ON person.organization_id=link.organization_id
    AND person.id=CASE WHEN link.from_person_id=p_person THEN link.to_person_id ELSE link.from_person_id END
  WHERE link.organization_id=p_org AND (link.from_person_id=p_person OR link.to_person_id=p_person);

  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,action,aggregate_type,aggregate_id)
  VALUES(p_org,p_org,p_actor,'membership','guest.registry.relationships_viewed','person',p_person);
  RETURN jsonb_build_object('relationships',v_relationships,'canManage',v_can_manage AND v_status <> 'merged');
END;
$function$;

CREATE FUNCTION eogp.write_guest_registry_relationship(
  p_org uuid, p_actor uuid, p_person uuid, p_relationship uuid, p_related uuid, p_kind text, p_directionality text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_link eogp.person_relationships%ROWTYPE;
  v_from uuid;
  v_to uuid;
  v_action text;
  v_profiles integer;
BEGIN
  PERFORM eogp.assert_guest_registry_relationship_permission(p_org,p_actor,true);
  IF p_relationship IS NULL THEN
    IF p_person IS NULL OR p_related IS NULL OR p_person=p_related OR p_kind IS NULL
      OR p_kind NOT IN ('household','family','assistant','delegate','colleague','partner','other')
      OR p_directionality IS NULL OR p_directionality NOT IN ('mutual','directed') THEN
      RAISE EXCEPTION 'invalid Registry relationship' USING ERRCODE='22023';
    END IF;

    -- Lock both profiles in the same order as supervised merges.
    PERFORM 1 FROM eogp.persons WHERE organization_id=p_org AND id IN (p_person,p_related) AND status='active'
    ORDER BY id FOR UPDATE;
    GET DIAGNOSTICS v_profiles=ROW_COUNT;
    IF v_profiles <> 2 THEN RAISE EXCEPTION 'one or both active profiles are unavailable' USING ERRCODE='P0002'; END IF;

    v_from := CASE WHEN p_directionality='mutual' THEN least(p_person,p_related) ELSE p_person END;
    v_to := CASE WHEN p_directionality='mutual' THEN greatest(p_person,p_related) ELSE p_related END;
    INSERT INTO eogp.person_relationships(organization_id,from_person_id,to_person_id,relationship_kind,directionality,created_by_membership_id)
    VALUES(p_org,v_from,v_to,p_kind,p_directionality,p_actor) RETURNING * INTO v_link;
    v_action := 'guest.registry.relationship.created';
  ELSE
    SELECT * INTO v_link FROM eogp.person_relationships
    WHERE organization_id=p_org AND id=p_relationship AND (from_person_id=p_person OR to_person_id=p_person) FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Registry relationship not found' USING ERRCODE='P0002'; END IF;
    IF v_link.ended_at IS NOT NULL THEN
      RETURN jsonb_build_object('relationshipId',v_link.id,'endedAt',v_link.ended_at);
    END IF;
    UPDATE eogp.person_relationships SET ended_at=clock_timestamp(), ended_by_membership_id=p_actor
    WHERE organization_id=p_org AND id=p_relationship RETURNING * INTO v_link;
    v_action := 'guest.registry.relationship.ended';
  END IF;

  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,safe_metadata)
  VALUES(p_org,p_org,p_actor,'membership',v_action,'person_relationship',v_link.id,
    jsonb_build_object('fromPersonId',v_link.from_person_id,'toPersonId',v_link.to_person_id));
  RETURN jsonb_build_object('relationshipId',v_link.id,'endedAt',v_link.ended_at);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.assert_guest_registry_relationship_permission(uuid,uuid,boolean),
  eogp.read_guest_registry_relationships(uuid,uuid,uuid),
  eogp.write_guest_registry_relationship(uuid,uuid,uuid,uuid,uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.assert_guest_registry_relationship_permission(uuid,uuid,boolean),
  eogp.read_guest_registry_relationships(uuid,uuid,uuid),
  eogp.write_guest_registry_relationship(uuid,uuid,uuid,uuid,uuid,text,text) TO eventor_runtime;

CREATE OR REPLACE FUNCTION eogp.guest_registry_merge_impact(
  p_org uuid, p_actor uuid, p_source eogp.persons, p_destination eogp.persons
) RETURNS jsonb LANGUAGE plpgsql SET search_path = pg_catalog, eogp
AS $function$
DECLARE
  v_link record;
  v_events jsonb := '[]'::jsonb;
  v_count integer := 0;
  v_reference text;
BEGIN
  IF p_source.status <> 'active' OR p_destination.status <> 'active' THEN
    RETURN jsonb_build_object('blocker', 'inactive_profile');
  END IF;
  IF EXISTS (SELECT 1 FROM eogp.person_contact_points WHERE organization_id = p_org AND person_id = p_source.id)
    OR EXISTS (SELECT 1 FROM eogp.person_identifiers WHERE organization_id = p_org AND person_id = p_source.id)
    OR EXISTS (SELECT 1 FROM eogp.persons WHERE organization_id = p_org AND merged_into_person_id = p_source.id)
    OR EXISTS (SELECT 1 FROM eogp.person_relationships WHERE organization_id = p_org AND ended_at IS NULL
      AND (from_person_id = p_source.id OR to_person_id = p_source.id)) THEN
    RETURN jsonb_build_object('blocker', 'source_has_linked_records');
  END IF;

  FOR v_link IN
    SELECT participation.id, event.id AS event_id, event.event_code, event.title, event.status,
      participation.status AS participation_status
    FROM eogp.event_participations participation
    JOIN eogp.events event ON event.organization_id = participation.organization_id AND event.id = participation.event_id
    WHERE participation.organization_id = p_org AND participation.person_id = p_source.id
    ORDER BY participation.id
  LOOP
    BEGIN
      PERFORM eogp.assert_event_guest_list_access(p_org, v_link.event_id, p_actor);
    EXCEPTION WHEN insufficient_privilege THEN
      RETURN jsonb_build_object('blocker', 'event_history_access_required');
    END;
    IF v_link.status NOT IN ('completed', 'cancelled', 'archived') THEN
      RETURN jsonb_build_object('blocker', 'source_has_linked_records');
    END IF;
    IF EXISTS (
      SELECT 1 FROM eogp.event_participations other
      JOIN eogp.persons person ON person.organization_id = other.organization_id AND person.id = other.person_id
      WHERE other.organization_id = p_org AND other.event_id = v_link.event_id
        AND (other.person_id = p_destination.id OR person.merged_into_person_id = p_destination.id)
    ) THEN
      RETURN jsonb_build_object('blocker', 'event_history_overlap');
    END IF;
    v_count := v_count + 1;
    -- Bind the review to the exact preserved participation references without storing them in audit metadata.
    v_reference := encode(sha256(convert_to(coalesce(v_reference, '') || v_link.id::text, 'UTF8')), 'hex');
    IF v_count <= 50 THEN
      v_events := v_events || jsonb_build_array(jsonb_build_object(
        'eventId', v_link.event_id, 'eventCode', v_link.event_code, 'eventTitle', v_link.title,
        'eventStatus', v_link.status, 'status', v_link.participation_status
      ));
    END IF;
  END LOOP;
  RETURN jsonb_build_object('historicalEvents', v_events, 'historicalCount', v_count, 'historicalReference', v_reference);
END;
$function$;
