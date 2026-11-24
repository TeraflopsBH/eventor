-- Internal, organization-configurable classifications on persistent Registry profiles.
CREATE TABLE eogp.registry_labels (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
  label text NOT NULL CHECK(length(btrim(label)) BETWEEN 1 AND 80 AND label !~ '[[:cntrl:]]'),
  retired_at timestamptz, created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE(organization_id,id)
);
CREATE UNIQUE INDEX registry_labels_name_uq ON eogp.registry_labels(organization_id,lower(label));
CREATE TABLE eogp.registry_person_label_assignments (
  organization_id uuid NOT NULL, person_id uuid NOT NULL, label_id uuid NOT NULL,
  added_by_membership_id uuid NOT NULL, added_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY(organization_id,person_id,label_id),
  FOREIGN KEY(organization_id,person_id) REFERENCES eogp.persons(organization_id,id),
  FOREIGN KEY(organization_id,label_id) REFERENCES eogp.registry_labels(organization_id,id),
  FOREIGN KEY(organization_id,added_by_membership_id) REFERENCES eogp.organization_memberships(organization_id,id)
);
ALTER TABLE eogp.registry_labels ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.registry_labels FORCE ROW LEVEL SECURITY;
ALTER TABLE eogp.registry_person_label_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.registry_person_label_assignments FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_isolation ON eogp.registry_labels USING(organization_id=eogp.current_organization_id()) WITH CHECK(organization_id=eogp.current_organization_id());
CREATE POLICY tenant_isolation ON eogp.registry_person_label_assignments USING(organization_id=eogp.current_organization_id()) WITH CHECK(organization_id=eogp.current_organization_id());
REVOKE ALL ON eogp.registry_labels,eogp.registry_person_label_assignments FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

CREATE FUNCTION eogp.assert_registry_label_access(p_org uuid,p_actor uuid,p_write boolean)
RETURNS void LANGUAGE plpgsql SET search_path=pg_catalog,eogp AS $function$
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_org OR nullif(current_setting('app.actor_membership_id',true),'')::uuid IS DISTINCT FROM p_actor THEN
    RAISE EXCEPTION 'organization or staff context mismatch' USING ERRCODE='42501'; END IF;
  PERFORM eogp.assert_guest_registry_permission(p_org,p_actor,p_write);
END;
$function$;
REVOKE ALL ON FUNCTION eogp.assert_registry_label_access(uuid,uuid,boolean) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

CREATE FUNCTION eogp.list_registry_person_labels(p_org uuid,p_actor uuid,p_person uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_person eogp.persons%ROWTYPE; v_labels jsonb; v_assigned jsonb; v_manage boolean:=false;
BEGIN
  PERFORM eogp.assert_registry_label_access(p_org,p_actor,false);
  SELECT * INTO v_person FROM eogp.persons WHERE organization_id=p_org AND id=p_person;
  IF NOT FOUND THEN RAISE EXCEPTION 'profile not found' USING ERRCODE='P0002'; END IF;
  BEGIN PERFORM eogp.assert_registry_label_access(p_org,p_actor,true); v_manage:=v_person.status='active';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  SELECT coalesce(jsonb_agg(jsonb_build_object('labelId',id,'label',label,'retired',retired_at IS NOT NULL) ORDER BY retired_at IS NOT NULL,lower(label),id),'[]'::jsonb)
    INTO v_labels FROM eogp.registry_labels WHERE organization_id=p_org;
  SELECT coalesce(jsonb_agg(label_id ORDER BY label_id),'[]'::jsonb) INTO v_assigned
    FROM eogp.registry_person_label_assignments WHERE organization_id=p_org AND person_id=p_person;
  RETURN jsonb_build_object('revision',v_person.revision,'canManage',v_manage,'labels',v_labels,'assignedLabelIds',v_assigned);
END;
$function$;
CREATE FUNCTION eogp.write_registry_label(p_org uuid,p_actor uuid,p_label uuid,p_name text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_label eogp.registry_labels%ROWTYPE;
BEGIN
  PERFORM eogp.assert_registry_label_access(p_org,p_actor,true);
  IF p_label IS NULL THEN
    IF coalesce(length(btrim(p_name)),0) NOT BETWEEN 1 AND 80 OR p_name ~ '[[:cntrl:]]' THEN
      RAISE EXCEPTION 'invalid label name' USING ERRCODE='22023'; END IF;
    INSERT INTO eogp.registry_labels(organization_id,label) VALUES(p_org,btrim(p_name)) RETURNING * INTO v_label;
  ELSE
    UPDATE eogp.registry_labels SET retired_at=coalesce(retired_at,clock_timestamp()) WHERE organization_id=p_org AND id=p_label RETURNING * INTO v_label;
    IF NOT FOUND THEN RAISE EXCEPTION 'label not found' USING ERRCODE='P0002'; END IF;
  END IF;
  INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,action,aggregate_type,aggregate_id,safe_metadata)
    VALUES(p_org,p_org,p_actor,'membership',CASE WHEN p_label IS NULL THEN 'guest.registry.label_created' ELSE 'guest.registry.label_retired' END,'registry_label',v_label.id,'{}');
  RETURN jsonb_build_object('labelId',v_label.id,'label',v_label.label,'retired',v_label.retired_at IS NOT NULL);
END;
$function$;
CREATE FUNCTION eogp.set_registry_person_labels(p_org uuid,p_actor uuid,p_person uuid,p_revision integer,p_labels uuid[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_person eogp.persons%ROWTYPE; v_before uuid[]; v_after uuid[]; v_revision integer;
BEGIN
  PERFORM eogp.assert_registry_label_access(p_org,p_actor,true);
  SELECT * INTO v_person FROM eogp.persons WHERE organization_id=p_org AND id=p_person FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'profile not found' USING ERRCODE='P0002'; END IF;
  IF v_person.revision IS DISTINCT FROM p_revision THEN RAISE EXCEPTION 'profile changed' USING ERRCODE='40001'; END IF;
  IF v_person.status<>'active' THEN RAISE EXCEPTION 'profile is not active' USING ERRCODE='55000'; END IF;
  SELECT coalesce(array_agg(DISTINCT id ORDER BY id),ARRAY[]::uuid[]) INTO v_after FROM unnest(p_labels) selected(id) WHERE id IS NOT NULL;
  IF cardinality(p_labels) IS DISTINCT FROM cardinality(v_after) OR cardinality(v_after)>100 THEN RAISE EXCEPTION 'invalid labels' USING ERRCODE='22023'; END IF;
  SELECT coalesce(array_agg(label_id ORDER BY label_id),ARRAY[]::uuid[]) INTO v_before FROM eogp.registry_person_label_assignments WHERE organization_id=p_org AND person_id=p_person;
  IF EXISTS(SELECT 1 FROM unnest(v_after) selected(id) WHERE NOT EXISTS(SELECT 1 FROM eogp.registry_labels WHERE organization_id=p_org AND id=selected.id AND (retired_at IS NULL OR id=ANY(v_before)))) THEN
    RAISE EXCEPTION 'label is unavailable' USING ERRCODE='55000'; END IF;
  v_revision:=v_person.revision;
  IF v_before<>v_after THEN
    DELETE FROM eogp.registry_person_label_assignments WHERE organization_id=p_org AND person_id=p_person AND NOT label_id=ANY(v_after);
    INSERT INTO eogp.registry_person_label_assignments(organization_id,person_id,label_id,added_by_membership_id)
      SELECT p_org,p_person,id,p_actor FROM unnest(v_after) selected(id) WHERE NOT id=ANY(v_before);
    UPDATE eogp.persons SET revision=revision+1,updated_at=clock_timestamp() WHERE organization_id=p_org AND id=p_person RETURNING revision INTO v_revision;
    INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,action,aggregate_type,aggregate_id,safe_metadata)
      VALUES(p_org,p_org,p_actor,'membership','guest.registry.labels_changed','person',p_person,jsonb_build_object('previousLabelIds',v_before,'labelIds',v_after,'revision',v_revision));
  END IF;
  RETURN jsonb_build_object('revision',v_revision,'assignedLabelIds',v_after);
END;
$function$;
REVOKE ALL ON FUNCTION eogp.list_registry_person_labels(uuid,uuid,uuid),eogp.write_registry_label(uuid,uuid,uuid,text),eogp.set_registry_person_labels(uuid,uuid,uuid,integer,uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION eogp.list_registry_person_labels(uuid,uuid,uuid),eogp.write_registry_label(uuid,uuid,uuid,text),eogp.set_registry_person_labels(uuid,uuid,uuid,integer,uuid[]) TO eventor_runtime;

-- Labelled duplicates need a separate reviewed resolution; never silently lose classifications.
ALTER FUNCTION eogp.guest_registry_merge_impact(uuid,uuid,eogp.persons,eogp.persons) RENAME TO guest_registry_merge_impact_without_labels;
CREATE FUNCTION eogp.guest_registry_merge_impact(p_org uuid,p_actor uuid,p_source eogp.persons,p_destination eogp.persons)
RETURNS jsonb LANGUAGE plpgsql SET search_path=pg_catalog,eogp AS $function$
BEGIN
  IF EXISTS(SELECT 1 FROM eogp.registry_person_label_assignments WHERE organization_id=p_org AND person_id=p_source.id) THEN
    RETURN jsonb_build_object('blocker','source_has_linked_records'); END IF;
  RETURN eogp.guest_registry_merge_impact_without_labels(p_org,p_actor,p_source,p_destination);
END;
$function$;
REVOKE ALL ON FUNCTION eogp.guest_registry_merge_impact(uuid,uuid,eogp.persons,eogp.persons),eogp.guest_registry_merge_impact_without_labels(uuid,uuid,eogp.persons,eogp.persons) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

-- Enrich only the authorized Registry directory/profile read. Public/event projections stay unchanged.
CREATE FUNCTION eogp.registry_person_label_projection(p_org uuid,p_person uuid)
RETURNS jsonb LANGUAGE sql STABLE SET search_path=pg_catalog,eogp AS $function$
 SELECT coalesce(jsonb_agg(jsonb_build_object('labelId',label.id,'label',label.label,'retired',label.retired_at IS NOT NULL) ORDER BY lower(label.label),label.id),'[]'::jsonb)
 FROM eogp.registry_person_label_assignments assignment JOIN eogp.registry_labels label ON label.organization_id=assignment.organization_id AND label.id=assignment.label_id
 WHERE assignment.organization_id=p_org AND assignment.person_id=p_person;
$function$;
ALTER FUNCTION eogp.read_guest_registry(uuid,uuid,uuid,text,boolean,integer) RENAME TO read_guest_registry_without_labels;
CREATE FUNCTION eogp.read_guest_registry(p_org uuid,p_actor uuid,p_person uuid,p_query text,p_archived boolean,p_offset integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_result jsonb;v_people jsonb;
BEGIN
 v_result:=eogp.read_guest_registry_without_labels(p_org,p_actor,p_person,p_query,p_archived,p_offset);
 IF p_person IS NOT NULL THEN RETURN v_result||jsonb_build_object('labels',eogp.registry_person_label_projection(p_org,p_person));END IF;
 SELECT coalesce(jsonb_agg(person||jsonb_build_object('labels',eogp.registry_person_label_projection(p_org,(person->>'personId')::uuid)) ORDER BY ordinal),'[]'::jsonb)
 INTO v_people FROM jsonb_array_elements(v_result->'people') WITH ORDINALITY people(person,ordinal);
 RETURN jsonb_set(v_result,'{people}',v_people);
END;
$function$;
REVOKE ALL ON FUNCTION eogp.registry_person_label_projection(uuid,uuid),eogp.read_guest_registry_without_labels(uuid,uuid,uuid,text,boolean,integer),eogp.read_guest_registry(uuid,uuid,uuid,text,boolean,integer) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.read_guest_registry(uuid,uuid,uuid,text,boolean,integer) TO eventor_runtime;
