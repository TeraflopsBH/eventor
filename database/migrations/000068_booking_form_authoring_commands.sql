-- Tenant-scoped booking-form authoring commands.
-- Drafts are editable; publication seals an immutable snapshot under migration 000020.
-- The API performs the full schema-v1 validation before invoking the save command;
-- these database commands enforce tenant, permission, revision and publication boundaries.

CREATE FUNCTION eogp.get_booking_forms(
  p_organization_id uuid,
  p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE v_result jsonb;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'formId',definition.id,'formCode',definition.form_code,'name',definition.name,
    'scopeKind',definition.scope_kind,'scopeVenueId',definition.scope_venue_id,
    'scopeSpaceId',definition.scope_space_id,'status',definition.status,
    'revisions',(SELECT coalesce(jsonb_agg(jsonb_build_object(
      'revisionId',revision.id,'revisionNumber',revision.revision_number,
      'locale',revision.locale,'fieldSchema',revision.field_schema,
      'state',revision.state,'publishedAt',revision.published_at,
      'createdAt',revision.created_at
    ) ORDER BY revision.revision_number DESC),'[]'::jsonb)
    FROM eogp.booking_form_revisions revision
    WHERE revision.organization_id=definition.organization_id
      AND revision.form_definition_id=definition.id)
  ) ORDER BY definition.form_code),'[]'::jsonb)
  INTO v_result
  FROM eogp.booking_form_definitions definition
  WHERE definition.organization_id=p_organization_id;
  RETURN v_result;
END;
$function$;

CREATE FUNCTION eogp.create_booking_form(
  p_organization_id uuid,p_actor_membership_id uuid,
  p_form_code text,p_name text,p_locale text,p_field_schema jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE v_form_id uuid:=gen_random_uuid(); v_revision_id uuid:=gen_random_uuid();
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  IF p_form_code IS NULL OR length(btrim(p_form_code)) NOT BETWEEN 2 AND 80
     OR p_form_code !~ '^[A-Za-z0-9][A-Za-z0-9_-]*
     OR p_name IS NULL OR length(btrim(p_name)) NOT BETWEEN 1 AND 250
     OR p_locale NOT IN ('bs-BA','en')
     OR p_field_schema IS NULL OR jsonb_typeof(p_field_schema)<>'object'
     OR jsonb_typeof(p_field_schema->'fields') IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_field_schema->'fields')>100 THEN
    RAISE EXCEPTION 'booking form details are invalid' USING ERRCODE='22023';
  END IF;
  INSERT INTO eogp.booking_form_definitions(
    id,organization_id,scope_kind,form_code,name,status
  ) VALUES(v_form_id,p_organization_id,'organization',btrim(p_form_code),btrim(p_name),'active');
  INSERT INTO eogp.booking_form_revisions(
    id,organization_id,form_definition_id,revision_number,locale,field_schema,state
  ) VALUES(v_revision_id,p_organization_id,v_form_id,1,p_locale,p_field_schema,'draft');
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.form.created','booking_form',v_form_id,'booking_form_created',
    jsonb_build_object('formCode',btrim(p_form_code),'revisionId',v_revision_id));
  RETURN jsonb_build_object('formId',v_form_id,'revisionId',v_revision_id,'revisionNumber',1,'state','draft');
END;
$function$;

CREATE FUNCTION eogp.create_booking_form_revision(
  p_organization_id uuid,p_form_id uuid,p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_form eogp.booking_form_definitions%ROWTYPE;
  v_latest eogp.booking_form_revisions%ROWTYPE;
  v_revision_id uuid:=gen_random_uuid(); v_number integer;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  SELECT * INTO v_form FROM eogp.booking_form_definitions
   WHERE organization_id=p_organization_id AND id=p_form_id FOR UPDATE;
  IF NOT FOUND OR v_form.status<>'active' THEN
    RAISE EXCEPTION 'active booking form not found' USING ERRCODE='P0002';
  END IF;
  SELECT * INTO v_latest FROM eogp.booking_form_revisions
   WHERE organization_id=p_organization_id AND form_definition_id=p_form_id
   ORDER BY revision_number DESC LIMIT 1 FOR UPDATE;
  IF NOT FOUND OR v_latest.state='draft' THEN
    RAISE EXCEPTION 'publish or retire the latest draft before creating another revision' USING ERRCODE='55000';
  END IF;
  v_number:=v_latest.revision_number+1;
  INSERT INTO eogp.booking_form_revisions(
    id,organization_id,form_definition_id,revision_number,locale,field_schema,state
  ) VALUES(v_revision_id,p_organization_id,p_form_id,v_number,v_latest.locale,v_latest.field_schema,'draft');
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.form.revision_created','booking_form',p_form_id,'booking_form_revision_created',
    jsonb_build_object('revisionId',v_revision_id,'revisionNumber',v_number));
  RETURN jsonb_build_object('formId',p_form_id,'revisionId',v_revision_id,'revisionNumber',v_number,'state','draft');
END;
$function$;

CREATE FUNCTION eogp.save_booking_form_draft(
  p_organization_id uuid,p_form_id uuid,p_revision_id uuid,p_actor_membership_id uuid,
  p_locale text,p_field_schema jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE v_revision eogp.booking_form_revisions%ROWTYPE;
  v_form eogp.booking_form_definitions%ROWTYPE; v_latest_id uuid;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  IF p_locale NOT IN ('bs-BA','en') OR p_field_schema IS NULL
     OR jsonb_typeof(p_field_schema)<>'object'
     OR jsonb_typeof(p_field_schema->'fields') IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_field_schema->'fields')>100 THEN
    RAISE EXCEPTION 'booking form draft schema is invalid' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_form FROM eogp.booking_form_definitions
   WHERE organization_id=p_organization_id AND id=p_form_id FOR UPDATE;
  IF NOT FOUND OR v_form.status<>'active' THEN
    RAISE EXCEPTION 'active booking form not found' USING ERRCODE='P0002';
  END IF;
  SELECT id INTO v_latest_id FROM eogp.booking_form_revisions
   WHERE organization_id=p_organization_id AND form_definition_id=p_form_id
   ORDER BY revision_number DESC LIMIT 1;
  IF v_latest_id IS DISTINCT FROM p_revision_id THEN
    RAISE EXCEPTION 'only the latest booking form revision may be edited' USING ERRCODE='40001';
  END IF;
  SELECT * INTO v_revision FROM eogp.booking_form_revisions
   WHERE organization_id=p_organization_id AND form_definition_id=p_form_id AND id=p_revision_id
   FOR UPDATE;
  IF NOT FOUND OR v_revision.state<>'draft' THEN
    RAISE EXCEPTION 'latest draft booking form revision is required' USING ERRCODE='55000';
  END IF;
  UPDATE eogp.booking_form_revisions
   SET locale=p_locale,field_schema=p_field_schema
   WHERE organization_id=p_organization_id AND id=p_revision_id;
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.form.draft_saved','booking_form',p_form_id,'booking_form_draft_saved',
    jsonb_build_object('revisionId',p_revision_id,'revisionNumber',v_revision.revision_number));
  RETURN jsonb_build_object('formId',p_form_id,'revisionId',p_revision_id,
    'revisionNumber',v_revision.revision_number,'state','draft');
END;
$function$;

CREATE FUNCTION eogp.publish_booking_form_revision(
  p_organization_id uuid,p_form_id uuid,p_revision_id uuid,p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_form eogp.booking_form_definitions%ROWTYPE;
  v_revision eogp.booking_form_revisions%ROWTYPE;
  v_latest_id uuid; v_field_count integer; v_published_at timestamptz:=clock_timestamp();
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  SELECT * INTO v_form FROM eogp.booking_form_definitions
   WHERE organization_id=p_organization_id AND id=p_form_id FOR UPDATE;
  IF NOT FOUND OR v_form.status<>'active' THEN
    RAISE EXCEPTION 'active booking form not found' USING ERRCODE='P0002';
  END IF;
  SELECT id INTO v_latest_id FROM eogp.booking_form_revisions
   WHERE organization_id=p_organization_id AND form_definition_id=p_form_id
   ORDER BY revision_number DESC LIMIT 1;
  IF v_latest_id IS DISTINCT FROM p_revision_id THEN
    RAISE EXCEPTION 'only the latest booking form revision may be published' USING ERRCODE='40001';
  END IF;
  SELECT * INTO v_revision FROM eogp.booking_form_revisions
   WHERE organization_id=p_organization_id AND form_definition_id=p_form_id AND id=p_revision_id
   FOR UPDATE;
  IF NOT FOUND OR v_revision.state<>'draft' THEN
    RAISE EXCEPTION 'draft booking form revision is required' USING ERRCODE='55000';
  END IF;
  SELECT jsonb_array_length(v_revision.field_schema->'fields') INTO v_field_count;
  IF v_field_count IS NULL OR v_field_count=0 THEN
    RAISE EXCEPTION 'a booking form must contain at least one field before publication' USING ERRCODE='22023';
  END IF;
  UPDATE eogp.booking_form_revisions
   SET state='published',published_at=v_published_at
   WHERE organization_id=p_organization_id AND id=p_revision_id;
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.form.published','booking_form',p_form_id,'booking_form_published',
    jsonb_build_object('revisionId',p_revision_id,'revisionNumber',v_revision.revision_number,
      'locale',v_revision.locale,'fieldCount',v_field_count));
  RETURN jsonb_build_object('formId',p_form_id,'revisionId',p_revision_id,
    'revisionNumber',v_revision.revision_number,'state','published','publishedAt',v_published_at);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.get_booking_forms(uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.create_booking_form(uuid,uuid,text,text,text,jsonb) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.create_booking_form_revision(uuid,uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.save_booking_form_draft(uuid,uuid,uuid,uuid,text,jsonb) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.publish_booking_form_revision(uuid,uuid,uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON TABLE eogp.booking_form_definitions,eogp.booking_form_revisions,eogp.booking_form_catalogue_bindings
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.get_booking_forms(uuid,uuid),
  eogp.create_booking_form(uuid,uuid,text,text,text,jsonb),
  eogp.create_booking_form_revision(uuid,uuid,uuid),
  eogp.save_booking_form_draft(uuid,uuid,uuid,uuid,text,jsonb),
  eogp.publish_booking_form_revision(uuid,uuid,uuid,uuid)
  TO eventor_runtime;

     OR p_name IS NULL OR length(btrim(p_name)) NOT BETWEEN 1 AND 250
     OR p_locale NOT IN ('bs-BA','en')
     OR p_field_schema IS NULL OR jsonb_typeof(p_field_schema)<>'object'
     OR jsonb_typeof(p_field_schema->'fields') IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_field_schema->'fields')>100 THEN
    RAISE EXCEPTION 'booking form details are invalid' USING ERRCODE='22023';
  END IF;
  INSERT INTO eogp.booking_form_definitions(
    id,organization_id,scope_kind,form_code,name,status
  ) VALUES(v_form_id,p_organization_id,'organization',btrim(p_form_code),btrim(p_name),'active');
  INSERT INTO eogp.booking_form_revisions(
    id,organization_id,form_definition_id,revision_number,locale,field_schema,state
  ) VALUES(v_revision_id,p_organization_id,v_form_id,1,p_locale,p_field_schema,'draft');
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.form.created','booking_form',v_form_id,'booking_form_created',
    jsonb_build_object('formCode',btrim(p_form_code),'revisionId',v_revision_id));
  RETURN jsonb_build_object('formId',v_form_id,'revisionId',v_revision_id,'revisionNumber',1,'state','draft');
END;
$function$;

CREATE FUNCTION eogp.create_booking_form_revision(
  p_organization_id uuid,p_form_id uuid,p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_form eogp.booking_form_definitions%ROWTYPE;
  v_latest eogp.booking_form_revisions%ROWTYPE;
  v_revision_id uuid:=gen_random_uuid(); v_number integer;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  SELECT * INTO v_form FROM eogp.booking_form_definitions
   WHERE organization_id=p_organization_id AND id=p_form_id FOR UPDATE;
  IF NOT FOUND OR v_form.status<>'active' THEN
    RAISE EXCEPTION 'active booking form not found' USING ERRCODE='P0002';
  END IF;
  SELECT * INTO v_latest FROM eogp.booking_form_revisions
   WHERE organization_id=p_organization_id AND form_definition_id=p_form_id
   ORDER BY revision_number DESC LIMIT 1 FOR UPDATE;
  IF NOT FOUND OR v_latest.state='draft' THEN
    RAISE EXCEPTION 'publish or retire the latest draft before creating another revision' USING ERRCODE='55000';
  END IF;
  v_number:=v_latest.revision_number+1;
  INSERT INTO eogp.booking_form_revisions(
    id,organization_id,form_definition_id,revision_number,locale,field_schema,state
  ) VALUES(v_revision_id,p_organization_id,p_form_id,v_number,v_latest.locale,v_latest.field_schema,'draft');
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.form.revision_created','booking_form',p_form_id,'booking_form_revision_created',
    jsonb_build_object('revisionId',v_revision_id,'revisionNumber',v_number));
  RETURN jsonb_build_object('formId',p_form_id,'revisionId',v_revision_id,'revisionNumber',v_number,'state','draft');
END;
$function$;

CREATE FUNCTION eogp.save_booking_form_draft(
  p_organization_id uuid,p_form_id uuid,p_revision_id uuid,p_actor_membership_id uuid,
  p_locale text,p_field_schema jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE v_revision eogp.booking_form_revisions%ROWTYPE;
  v_form eogp.booking_form_definitions%ROWTYPE; v_latest_id uuid;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  IF p_locale NOT IN ('bs-BA','en') OR p_field_schema IS NULL
     OR jsonb_typeof(p_field_schema)<>'object'
     OR jsonb_typeof(p_field_schema->'fields') IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_field_schema->'fields')>100 THEN
    RAISE EXCEPTION 'booking form draft schema is invalid' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_form FROM eogp.booking_form_definitions
   WHERE organization_id=p_organization_id AND id=p_form_id FOR UPDATE;
  IF NOT FOUND OR v_form.status<>'active' THEN
    RAISE EXCEPTION 'active booking form not found' USING ERRCODE='P0002';
  END IF;
  SELECT id INTO v_latest_id FROM eogp.booking_form_revisions
   WHERE organization_id=p_organization_id AND form_definition_id=p_form_id
   ORDER BY revision_number DESC LIMIT 1;
  IF v_latest_id IS DISTINCT FROM p_revision_id THEN
    RAISE EXCEPTION 'only the latest booking form revision may be edited' USING ERRCODE='40001';
  END IF;
  SELECT * INTO v_revision FROM eogp.booking_form_revisions
   WHERE organization_id=p_organization_id AND form_definition_id=p_form_id AND id=p_revision_id
   FOR UPDATE;
  IF NOT FOUND OR v_revision.state<>'draft' THEN
    RAISE EXCEPTION 'latest draft booking form revision is required' USING ERRCODE='55000';
  END IF;
  UPDATE eogp.booking_form_revisions
   SET locale=p_locale,field_schema=p_field_schema
   WHERE organization_id=p_organization_id AND id=p_revision_id;
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.form.draft_saved','booking_form',p_form_id,'booking_form_draft_saved',
    jsonb_build_object('revisionId',p_revision_id,'revisionNumber',v_revision.revision_number));
  RETURN jsonb_build_object('formId',p_form_id,'revisionId',p_revision_id,
    'revisionNumber',v_revision.revision_number,'state','draft');
END;
$function$;

CREATE FUNCTION eogp.publish_booking_form_revision(
  p_organization_id uuid,p_form_id uuid,p_revision_id uuid,p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_form eogp.booking_form_definitions%ROWTYPE;
  v_revision eogp.booking_form_revisions%ROWTYPE;
  v_latest_id uuid; v_field_count integer; v_published_at timestamptz:=clock_timestamp();
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  SELECT * INTO v_form FROM eogp.booking_form_definitions
   WHERE organization_id=p_organization_id AND id=p_form_id FOR UPDATE;
  IF NOT FOUND OR v_form.status<>'active' THEN
    RAISE EXCEPTION 'active booking form not found' USING ERRCODE='P0002';
  END IF;
  SELECT id INTO v_latest_id FROM eogp.booking_form_revisions
   WHERE organization_id=p_organization_id AND form_definition_id=p_form_id
   ORDER BY revision_number DESC LIMIT 1;
  IF v_latest_id IS DISTINCT FROM p_revision_id THEN
    RAISE EXCEPTION 'only the latest booking form revision may be published' USING ERRCODE='40001';
  END IF;
  SELECT * INTO v_revision FROM eogp.booking_form_revisions
   WHERE organization_id=p_organization_id AND form_definition_id=p_form_id AND id=p_revision_id
   FOR UPDATE;
  IF NOT FOUND OR v_revision.state<>'draft' THEN
    RAISE EXCEPTION 'draft booking form revision is required' USING ERRCODE='55000';
  END IF;
  SELECT jsonb_array_length(v_revision.field_schema->'fields') INTO v_field_count;
  IF v_field_count IS NULL OR v_field_count=0 THEN
    RAISE EXCEPTION 'a booking form must contain at least one field before publication' USING ERRCODE='22023';
  END IF;
  UPDATE eogp.booking_form_revisions
   SET state='published',published_at=v_published_at
   WHERE organization_id=p_organization_id AND id=p_revision_id;
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.form.published','booking_form',p_form_id,'booking_form_published',
    jsonb_build_object('revisionId',p_revision_id,'revisionNumber',v_revision.revision_number,
      'locale',v_revision.locale,'fieldCount',v_field_count));
  RETURN jsonb_build_object('formId',p_form_id,'revisionId',p_revision_id,
    'revisionNumber',v_revision.revision_number,'state','published','publishedAt',v_published_at);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.get_booking_forms(uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.create_booking_form(uuid,uuid,text,text,text,jsonb) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.create_booking_form_revision(uuid,uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.save_booking_form_draft(uuid,uuid,uuid,uuid,text,jsonb) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.publish_booking_form_revision(uuid,uuid,uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON TABLE eogp.booking_form_definitions,eogp.booking_form_revisions,eogp.booking_form_catalogue_bindings
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.get_booking_forms(uuid,uuid),
  eogp.create_booking_form(uuid,uuid,text,text,text,jsonb),
  eogp.create_booking_form_revision(uuid,uuid,uuid),
  eogp.save_booking_form_draft(uuid,uuid,uuid,uuid,text,jsonb),
  eogp.publish_booking_form_revision(uuid,uuid,uuid,uuid)
  TO eventor_runtime;

     OR p_name IS NULL OR length(btrim(p_name)) NOT BETWEEN 1 AND 250
     OR p_locale NOT IN ('bs-BA','en')
     OR p_field_schema IS NULL OR jsonb_typeof(p_field_schema)<>'object'
     OR jsonb_typeof(p_field_schema->'fields') IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_field_schema->'fields')>100 THEN
    RAISE EXCEPTION 'booking form details are invalid' USING ERRCODE='22023';
  END IF;
  INSERT INTO eogp.booking_form_definitions(
    id,organization_id,scope_kind,form_code,name,status
  ) VALUES(v_form_id,p_organization_id,'organization',btrim(p_form_code),btrim(p_name),'active');
  INSERT INTO eogp.booking_form_revisions(
    id,organization_id,form_definition_id,revision_number,locale,field_schema,state
  ) VALUES(v_revision_id,p_organization_id,v_form_id,1,p_locale,p_field_schema,'draft');
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.form.created','booking_form',v_form_id,'booking_form_created',
    jsonb_build_object('formCode',btrim(p_form_code),'revisionId',v_revision_id));
  RETURN jsonb_build_object('formId',v_form_id,'revisionId',v_revision_id,'revisionNumber',1,'state','draft');
END;
$function$;

CREATE FUNCTION eogp.create_booking_form_revision(
  p_organization_id uuid,p_form_id uuid,p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_form eogp.booking_form_definitions%ROWTYPE;
  v_latest eogp.booking_form_revisions%ROWTYPE;
  v_revision_id uuid:=gen_random_uuid(); v_number integer;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  SELECT * INTO v_form FROM eogp.booking_form_definitions
   WHERE organization_id=p_organization_id AND id=p_form_id FOR UPDATE;
  IF NOT FOUND OR v_form.status<>'active' THEN
    RAISE EXCEPTION 'active booking form not found' USING ERRCODE='P0002';
  END IF;
  SELECT * INTO v_latest FROM eogp.booking_form_revisions
   WHERE organization_id=p_organization_id AND form_definition_id=p_form_id
   ORDER BY revision_number DESC LIMIT 1 FOR UPDATE;
  IF NOT FOUND OR v_latest.state='draft' THEN
    RAISE EXCEPTION 'publish or retire the latest draft before creating another revision' USING ERRCODE='55000';
  END IF;
  v_number:=v_latest.revision_number+1;
  INSERT INTO eogp.booking_form_revisions(
    id,organization_id,form_definition_id,revision_number,locale,field_schema,state
  ) VALUES(v_revision_id,p_organization_id,p_form_id,v_number,v_latest.locale,v_latest.field_schema,'draft');
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.form.revision_created','booking_form',p_form_id,'booking_form_revision_created',
    jsonb_build_object('revisionId',v_revision_id,'revisionNumber',v_number));
  RETURN jsonb_build_object('formId',p_form_id,'revisionId',v_revision_id,'revisionNumber',v_number,'state','draft');
END;
$function$;

CREATE FUNCTION eogp.save_booking_form_draft(
  p_organization_id uuid,p_form_id uuid,p_revision_id uuid,p_actor_membership_id uuid,
  p_locale text,p_field_schema jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE v_revision eogp.booking_form_revisions%ROWTYPE;
  v_form eogp.booking_form_definitions%ROWTYPE; v_latest_id uuid;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  IF p_locale NOT IN ('bs-BA','en') OR p_field_schema IS NULL
     OR jsonb_typeof(p_field_schema)<>'object'
     OR jsonb_typeof(p_field_schema->'fields') IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_field_schema->'fields')>100 THEN
    RAISE EXCEPTION 'booking form draft schema is invalid' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_form FROM eogp.booking_form_definitions
   WHERE organization_id=p_organization_id AND id=p_form_id FOR UPDATE;
  IF NOT FOUND OR v_form.status<>'active' THEN
    RAISE EXCEPTION 'active booking form not found' USING ERRCODE='P0002';
  END IF;
  SELECT id INTO v_latest_id FROM eogp.booking_form_revisions
   WHERE organization_id=p_organization_id AND form_definition_id=p_form_id
   ORDER BY revision_number DESC LIMIT 1;
  IF v_latest_id IS DISTINCT FROM p_revision_id THEN
    RAISE EXCEPTION 'only the latest booking form revision may be edited' USING ERRCODE='40001';
  END IF;
  SELECT * INTO v_revision FROM eogp.booking_form_revisions
   WHERE organization_id=p_organization_id AND form_definition_id=p_form_id AND id=p_revision_id
   FOR UPDATE;
  IF NOT FOUND OR v_revision.state<>'draft' THEN
    RAISE EXCEPTION 'latest draft booking form revision is required' USING ERRCODE='55000';
  END IF;
  UPDATE eogp.booking_form_revisions
   SET locale=p_locale,field_schema=p_field_schema
   WHERE organization_id=p_organization_id AND id=p_revision_id;
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.form.draft_saved','booking_form',p_form_id,'booking_form_draft_saved',
    jsonb_build_object('revisionId',p_revision_id,'revisionNumber',v_revision.revision_number));
  RETURN jsonb_build_object('formId',p_form_id,'revisionId',p_revision_id,
    'revisionNumber',v_revision.revision_number,'state','draft');
END;
$function$;

CREATE FUNCTION eogp.publish_booking_form_revision(
  p_organization_id uuid,p_form_id uuid,p_revision_id uuid,p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_form eogp.booking_form_definitions%ROWTYPE;
  v_revision eogp.booking_form_revisions%ROWTYPE;
  v_latest_id uuid; v_field_count integer; v_published_at timestamptz:=clock_timestamp();
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  SELECT * INTO v_form FROM eogp.booking_form_definitions
   WHERE organization_id=p_organization_id AND id=p_form_id FOR UPDATE;
  IF NOT FOUND OR v_form.status<>'active' THEN
    RAISE EXCEPTION 'active booking form not found' USING ERRCODE='P0002';
  END IF;
  SELECT id INTO v_latest_id FROM eogp.booking_form_revisions
   WHERE organization_id=p_organization_id AND form_definition_id=p_form_id
   ORDER BY revision_number DESC LIMIT 1;
  IF v_latest_id IS DISTINCT FROM p_revision_id THEN
    RAISE EXCEPTION 'only the latest booking form revision may be published' USING ERRCODE='40001';
  END IF;
  SELECT * INTO v_revision FROM eogp.booking_form_revisions
   WHERE organization_id=p_organization_id AND form_definition_id=p_form_id AND id=p_revision_id
   FOR UPDATE;
  IF NOT FOUND OR v_revision.state<>'draft' THEN
    RAISE EXCEPTION 'draft booking form revision is required' USING ERRCODE='55000';
  END IF;
  SELECT jsonb_array_length(v_revision.field_schema->'fields') INTO v_field_count;
  IF v_field_count IS NULL OR v_field_count=0 THEN
    RAISE EXCEPTION 'a booking form must contain at least one field before publication' USING ERRCODE='22023';
  END IF;
  UPDATE eogp.booking_form_revisions
   SET state='published',published_at=v_published_at
   WHERE organization_id=p_organization_id AND id=p_revision_id;
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.form.published','booking_form',p_form_id,'booking_form_published',
    jsonb_build_object('revisionId',p_revision_id,'revisionNumber',v_revision.revision_number,
      'locale',v_revision.locale,'fieldCount',v_field_count));
  RETURN jsonb_build_object('formId',p_form_id,'revisionId',p_revision_id,
    'revisionNumber',v_revision.revision_number,'state','published','publishedAt',v_published_at);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.get_booking_forms(uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.create_booking_form(uuid,uuid,text,text,text,jsonb) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.create_booking_form_revision(uuid,uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.save_booking_form_draft(uuid,uuid,uuid,uuid,text,jsonb) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.publish_booking_form_revision(uuid,uuid,uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON TABLE eogp.booking_form_definitions,eogp.booking_form_revisions,eogp.booking_form_catalogue_bindings
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.get_booking_forms(uuid,uuid),
  eogp.create_booking_form(uuid,uuid,text,text,text,jsonb),
  eogp.create_booking_form_revision(uuid,uuid,uuid),
  eogp.save_booking_form_draft(uuid,uuid,uuid,uuid,text,jsonb),
  eogp.publish_booking_form_revision(uuid,uuid,uuid,uuid)
  TO eventor_runtime;

     OR p_name IS NULL OR length(btrim(p_name)) NOT BETWEEN 1 AND 250
     OR p_locale NOT IN ('bs-BA','en')
     OR p_field_schema IS NULL OR jsonb_typeof(p_field_schema)<>'object'
     OR jsonb_typeof(p_field_schema->'fields') IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_field_schema->'fields')>100 THEN
    RAISE EXCEPTION 'booking form details are invalid' USING ERRCODE='22023';
  END IF;
  INSERT INTO eogp.booking_form_definitions(
    id,organization_id,scope_kind,form_code,name,status
  ) VALUES(v_form_id,p_organization_id,'organization',btrim(p_form_code),btrim(p_name),'active');
  INSERT INTO eogp.booking_form_revisions(
    id,organization_id,form_definition_id,revision_number,locale,field_schema,state
  ) VALUES(v_revision_id,p_organization_id,v_form_id,1,p_locale,p_field_schema,'draft');
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.form.created','booking_form',v_form_id,'booking_form_created',
    jsonb_build_object('formCode',btrim(p_form_code),'revisionId',v_revision_id));
  RETURN jsonb_build_object('formId',v_form_id,'revisionId',v_revision_id,'revisionNumber',1,'state','draft');
END;
$function$;

CREATE FUNCTION eogp.create_booking_form_revision(
  p_organization_id uuid,p_form_id uuid,p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_form eogp.booking_form_definitions%ROWTYPE;
  v_latest eogp.booking_form_revisions%ROWTYPE;
  v_revision_id uuid:=gen_random_uuid(); v_number integer;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  SELECT * INTO v_form FROM eogp.booking_form_definitions
   WHERE organization_id=p_organization_id AND id=p_form_id FOR UPDATE;
  IF NOT FOUND OR v_form.status<>'active' THEN
    RAISE EXCEPTION 'active booking form not found' USING ERRCODE='P0002';
  END IF;
  SELECT * INTO v_latest FROM eogp.booking_form_revisions
   WHERE organization_id=p_organization_id AND form_definition_id=p_form_id
   ORDER BY revision_number DESC LIMIT 1 FOR UPDATE;
  IF NOT FOUND OR v_latest.state='draft' THEN
    RAISE EXCEPTION 'publish or retire the latest draft before creating another revision' USING ERRCODE='55000';
  END IF;
  v_number:=v_latest.revision_number+1;
  INSERT INTO eogp.booking_form_revisions(
    id,organization_id,form_definition_id,revision_number,locale,field_schema,state
  ) VALUES(v_revision_id,p_organization_id,p_form_id,v_number,v_latest.locale,v_latest.field_schema,'draft');
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.form.revision_created','booking_form',p_form_id,'booking_form_revision_created',
    jsonb_build_object('revisionId',v_revision_id,'revisionNumber',v_number));
  RETURN jsonb_build_object('formId',p_form_id,'revisionId',v_revision_id,'revisionNumber',v_number,'state','draft');
END;
$function$;

CREATE FUNCTION eogp.save_booking_form_draft(
  p_organization_id uuid,p_form_id uuid,p_revision_id uuid,p_actor_membership_id uuid,
  p_locale text,p_field_schema jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE v_revision eogp.booking_form_revisions%ROWTYPE;
  v_form eogp.booking_form_definitions%ROWTYPE; v_latest_id uuid;
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  IF p_locale NOT IN ('bs-BA','en') OR p_field_schema IS NULL
     OR jsonb_typeof(p_field_schema)<>'object'
     OR jsonb_typeof(p_field_schema->'fields') IS DISTINCT FROM 'array'
     OR jsonb_array_length(p_field_schema->'fields')>100 THEN
    RAISE EXCEPTION 'booking form draft schema is invalid' USING ERRCODE='22023';
  END IF;
  SELECT * INTO v_form FROM eogp.booking_form_definitions
   WHERE organization_id=p_organization_id AND id=p_form_id FOR UPDATE;
  IF NOT FOUND OR v_form.status<>'active' THEN
    RAISE EXCEPTION 'active booking form not found' USING ERRCODE='P0002';
  END IF;
  SELECT id INTO v_latest_id FROM eogp.booking_form_revisions
   WHERE organization_id=p_organization_id AND form_definition_id=p_form_id
   ORDER BY revision_number DESC LIMIT 1;
  IF v_latest_id IS DISTINCT FROM p_revision_id THEN
    RAISE EXCEPTION 'only the latest booking form revision may be edited' USING ERRCODE='40001';
  END IF;
  SELECT * INTO v_revision FROM eogp.booking_form_revisions
   WHERE organization_id=p_organization_id AND form_definition_id=p_form_id AND id=p_revision_id
   FOR UPDATE;
  IF NOT FOUND OR v_revision.state<>'draft' THEN
    RAISE EXCEPTION 'latest draft booking form revision is required' USING ERRCODE='55000';
  END IF;
  UPDATE eogp.booking_form_revisions
   SET locale=p_locale,field_schema=p_field_schema
   WHERE organization_id=p_organization_id AND id=p_revision_id;
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.form.draft_saved','booking_form',p_form_id,'booking_form_draft_saved',
    jsonb_build_object('revisionId',p_revision_id,'revisionNumber',v_revision.revision_number));
  RETURN jsonb_build_object('formId',p_form_id,'revisionId',p_revision_id,
    'revisionNumber',v_revision.revision_number,'state','draft');
END;
$function$;

CREATE FUNCTION eogp.publish_booking_form_revision(
  p_organization_id uuid,p_form_id uuid,p_revision_id uuid,p_actor_membership_id uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,eogp
AS $function$
DECLARE
  v_form eogp.booking_form_definitions%ROWTYPE;
  v_revision eogp.booking_form_revisions%ROWTYPE;
  v_latest_id uuid; v_field_count integer; v_published_at timestamptz:=clock_timestamp();
BEGIN
  IF eogp.current_organization_id() IS DISTINCT FROM p_organization_id THEN
    RAISE EXCEPTION 'organization context mismatch' USING ERRCODE='42501';
  END IF;
  PERFORM eogp.assert_booking_commercial_permission(
    p_organization_id,p_actor_membership_id,ARRAY['booking.manage']::text[]
  );
  SELECT * INTO v_form FROM eogp.booking_form_definitions
   WHERE organization_id=p_organization_id AND id=p_form_id FOR UPDATE;
  IF NOT FOUND OR v_form.status<>'active' THEN
    RAISE EXCEPTION 'active booking form not found' USING ERRCODE='P0002';
  END IF;
  SELECT id INTO v_latest_id FROM eogp.booking_form_revisions
   WHERE organization_id=p_organization_id AND form_definition_id=p_form_id
   ORDER BY revision_number DESC LIMIT 1;
  IF v_latest_id IS DISTINCT FROM p_revision_id THEN
    RAISE EXCEPTION 'only the latest booking form revision may be published' USING ERRCODE='40001';
  END IF;
  SELECT * INTO v_revision FROM eogp.booking_form_revisions
   WHERE organization_id=p_organization_id AND form_definition_id=p_form_id AND id=p_revision_id
   FOR UPDATE;
  IF NOT FOUND OR v_revision.state<>'draft' THEN
    RAISE EXCEPTION 'draft booking form revision is required' USING ERRCODE='55000';
  END IF;
  SELECT jsonb_array_length(v_revision.field_schema->'fields') INTO v_field_count;
  IF v_field_count IS NULL OR v_field_count=0 THEN
    RAISE EXCEPTION 'a booking form must contain at least one field before publication' USING ERRCODE='22023';
  END IF;
  UPDATE eogp.booking_form_revisions
   SET state='published',published_at=v_published_at
   WHERE organization_id=p_organization_id AND id=p_revision_id;
  INSERT INTO eogp.audit_events(
    organization_id,actor_organization_id,actor_membership_id,actor_kind,
    action,aggregate_type,aggregate_id,reason_code,safe_metadata
  ) VALUES(p_organization_id,p_organization_id,p_actor_membership_id,'membership',
    'booking.form.published','booking_form',p_form_id,'booking_form_published',
    jsonb_build_object('revisionId',p_revision_id,'revisionNumber',v_revision.revision_number,
      'locale',v_revision.locale,'fieldCount',v_field_count));
  RETURN jsonb_build_object('formId',p_form_id,'revisionId',p_revision_id,
    'revisionNumber',v_revision.revision_number,'state','published','publishedAt',v_published_at);
END;
$function$;

REVOKE ALL ON FUNCTION eogp.get_booking_forms(uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.create_booking_form(uuid,uuid,text,text,text,jsonb) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.create_booking_form_revision(uuid,uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.save_booking_form_draft(uuid,uuid,uuid,uuid,text,jsonb) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.publish_booking_form_revision(uuid,uuid,uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON TABLE eogp.booking_form_definitions,eogp.booking_form_revisions,eogp.booking_form_catalogue_bindings
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
GRANT EXECUTE ON FUNCTION eogp.get_booking_forms(uuid,uuid),
  eogp.create_booking_form(uuid,uuid,text,text,text,jsonb),
  eogp.create_booking_form_revision(uuid,uuid,uuid),
  eogp.save_booking_form_draft(uuid,uuid,uuid,uuid,text,jsonb),
  eogp.publish_booking_form_revision(uuid,uuid,uuid,uuid)
  TO eventor_runtime;
