\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_user uuid := gen_random_uuid(); v_actor uuid := gen_random_uuid(); v_role uuid := gen_random_uuid();
  v_event uuid := gen_random_uuid(); v_other uuid := gen_random_uuid();
  v_person uuid; v_first uuid; v_second uuid; v_foreign uuid;
  v_group uuid; v_keep uuid; v_foreign_group uuid;
  v_selection jsonb; v_result jsonb; v_invalid jsonb; v_revisions jsonb; v_audits integer;
BEGIN
  PERFORM set_config('app.organization_id',v_org::text,true);
  PERFORM set_config('app.actor_membership_id',v_actor::text,true);
  INSERT INTO eogp.users(id,email,display_name,status)
    VALUES(v_user,'bulk-groups-'||v_user::text||'@example.invalid','Bulk groups fixture','active');
  INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status,joined_at)
    VALUES(v_actor,v_org,v_user,'active',clock_timestamp());
  INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind)
    VALUES(v_role,v_org,'CI-BULK-GROUPS','Bulk groups fixture','organization');
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
    SELECT v_org,v_role,code FROM unnest(ARRAY['guest.manage','guest.registry.manage']) code;
  INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id)
    VALUES(v_org,v_actor,v_role,'organization',v_actor);
  INSERT INTO eogp.events(id,organization_id,event_code,title,created_by_membership_id)
    VALUES(v_event,v_org,'CI-BULK-GROUPS','Bulk groups fixture',v_actor),
      (v_other,v_org,'CI-BULK-GROUPS-OTHER','Other event fixture',v_actor);
  INSERT INTO eogp.event_capability_overrides(organization_id,event_id,capability_code,enabled,changed_by_membership_id)
    VALUES(v_org,v_event,'guest_registry',true,v_actor),(v_org,v_other,'guest_registry',true,v_actor);
  v_person := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Bulk","lastName":"Group First"}')->>'personId')::uuid;
  v_first := (eogp.link_registry_person_to_event(v_org,v_event,v_actor,v_person,'eligible')->>'participationId')::uuid;
  v_person := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Bulk","lastName":"Group Second"}')->>'personId')::uuid;
  v_second := (eogp.link_registry_person_to_event(v_org,v_event,v_actor,v_person,'waitlisted')->>'participationId')::uuid;
  v_foreign := (eogp.link_registry_person_to_event(v_org,v_other,v_actor,v_person,'eligible')->>'participationId')::uuid;
  v_group := (eogp.write_event_guest_group(v_org,v_event,v_actor,NULL,'BULK-GROUP','Bulk group fixture')->>'groupId')::uuid;
  v_keep := (eogp.write_event_guest_group(v_org,v_event,v_actor,NULL,'KEEP-GROUP','Keep group fixture')->>'groupId')::uuid;
  v_foreign_group := (eogp.write_event_guest_group(v_org,v_other,v_actor,NULL,'OTHER-GROUP','Other group fixture')->>'groupId')::uuid;
  PERFORM eogp.set_event_guest_groups(v_org,v_event,v_actor,v_first,1,ARRAY[v_keep],jsonb_build_object(v_keep::text,'lead'));

  -- A later stale selection must roll back earlier membership/revision/audit changes.
  SELECT jsonb_object_agg(id::text,revision) INTO v_revisions FROM eogp.event_participations WHERE organization_id=v_org AND event_id=v_event;
  SELECT count(*) INTO v_audits FROM eogp.audit_events WHERE organization_id=v_org AND action='guest.participation.groups_changed';
  SELECT jsonb_agg(jsonb_build_object('participationId',id,'expectedRevision',
    CASE WHEN id=greatest(v_first,v_second) THEN revision+1 ELSE revision END)) INTO v_selection
    FROM eogp.event_participations WHERE organization_id=v_org AND event_id=v_event;
  BEGIN
    PERFORM eogp.set_event_guest_bulk_group(v_org,v_event,v_actor,v_group,'add',v_selection);
    RAISE EXCEPTION 'stale selection accepted';
  EXCEPTION WHEN serialization_failure THEN NULL; END;
  IF EXISTS(SELECT 1 FROM eogp.guest_group_memberships WHERE organization_id=v_org AND group_id=v_group)
    OR v_revisions IS DISTINCT FROM (SELECT jsonb_object_agg(id::text,revision) FROM eogp.event_participations WHERE organization_id=v_org AND event_id=v_event)
    OR v_audits<>(SELECT count(*) FROM eogp.audit_events WHERE organization_id=v_org AND action='guest.participation.groups_changed') THEN
    RAISE EXCEPTION 'failed batch left partial writes'; END IF;

  v_selection := jsonb_build_array(jsonb_build_object('participationId',v_first,'expectedRevision',2),jsonb_build_object('participationId',v_second,'expectedRevision',1));
  FOREACH v_invalid IN ARRAY ARRAY['[]'::jsonb,'null'::jsonb,'{}'::jsonb,
    jsonb_build_array(v_selection->0,v_selection->0),jsonb_build_array(jsonb_build_object('participationId',v_first)),
    (SELECT jsonb_agg(jsonb_build_object('participationId',gen_random_uuid(),'expectedRevision',1)) FROM generate_series(1,51))]
  LOOP
    BEGIN
      PERFORM eogp.set_event_guest_bulk_group(v_org,v_event,v_actor,v_group,'add',v_invalid);
      RAISE EXCEPTION 'invalid selection accepted';
    EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  END LOOP;
  BEGIN
    PERFORM eogp.set_event_guest_bulk_group(v_org,v_event,v_actor,v_group,'replace',v_selection);
    RAISE EXCEPTION 'unknown action accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM eogp.set_event_guest_bulk_group(v_org,v_event,v_actor,v_foreign_group,'add',v_selection);
    RAISE EXCEPTION 'other-event group accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  BEGIN
    PERFORM eogp.set_event_guest_bulk_group(v_org,v_event,v_actor,v_group,'add',jsonb_build_array(jsonb_build_object('participationId',v_foreign,'expectedRevision',1)));
    RAISE EXCEPTION 'other-event guest accepted';
  EXCEPTION WHEN no_data_found THEN NULL; END;

  DELETE FROM eogp.role_permissions WHERE organization_id=v_org AND role_id=v_role AND permission_code='guest.manage';
  BEGIN
    PERFORM eogp.set_event_guest_bulk_group(v_org,v_event,v_actor,v_group,'add',v_selection);
    RAISE EXCEPTION 'revoked authority accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  INSERT INTO eogp.role_permissions VALUES(v_org,v_role,'guest.manage');
  PERFORM set_config('app.actor_membership_id',gen_random_uuid()::text,true);
  BEGIN
    PERFORM eogp.set_event_guest_bulk_group(v_org,v_event,v_actor,v_group,'add',v_selection);
    RAISE EXCEPTION 'actor mismatch accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('app.actor_membership_id',v_actor::text,true);
  PERFORM set_config('app.organization_id','10000000-0000-0000-0000-00000000000b',true);
  BEGIN
    PERFORM eogp.set_event_guest_bulk_group(v_org,v_event,v_actor,v_group,'add',v_selection);
    RAISE EXCEPTION 'tenant mismatch accepted';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
  PERFORM set_config('app.organization_id',v_org::text,true);

  v_result := eogp.set_event_guest_bulk_group(v_org,v_event,v_actor,v_group,'add',v_selection);
  IF v_result <> '{"processedCount":2,"updatedCount":2}'::jsonb
    OR (SELECT count(*) FROM eogp.guest_group_memberships WHERE organization_id=v_org AND group_id=v_group AND membership_kind='member')<>2
    OR NOT EXISTS(SELECT 1 FROM eogp.guest_group_memberships WHERE organization_id=v_org AND participation_id=v_first AND group_id=v_keep AND membership_kind='lead') THEN
    RAISE EXCEPTION 'bulk add lost membership roles or unrelated groups'; END IF;
  -- Existing roles are never reset by an add, and an unchanged batch has no audit/revision churn.
  PERFORM eogp.set_event_guest_groups(v_org,v_event,v_actor,v_first,3,ARRAY[v_keep,v_group],jsonb_build_object(v_group::text,'assistant'));
  v_selection := jsonb_build_array(jsonb_build_object('participationId',v_first,'expectedRevision',4),jsonb_build_object('participationId',v_second,'expectedRevision',2));
  SELECT count(*) INTO v_audits FROM eogp.audit_events WHERE organization_id=v_org AND action='guest.participation.groups_changed';
  v_result := eogp.set_event_guest_bulk_group(v_org,v_event,v_actor,v_group,'add',v_selection);
  IF v_result <> '{"processedCount":2,"updatedCount":0}'::jsonb
    OR NOT EXISTS(SELECT 1 FROM eogp.guest_group_memberships WHERE organization_id=v_org AND participation_id=v_first AND group_id=v_group AND membership_kind='assistant')
    OR v_audits<>(SELECT count(*) FROM eogp.audit_events WHERE organization_id=v_org AND action='guest.participation.groups_changed') THEN
    RAISE EXCEPTION 'unchanged add reset roles or created audit churn'; END IF;

  UPDATE eogp.event_participations SET status='cancelled' WHERE organization_id=v_org AND id=v_second;
  BEGIN
    PERFORM eogp.set_event_guest_bulk_group(v_org,v_event,v_actor,v_group,'remove',v_selection);
    RAISE EXCEPTION 'cancelled selection accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  IF (SELECT count(*) FROM eogp.guest_group_memberships WHERE organization_id=v_org AND group_id=v_group)<>2 THEN
    RAISE EXCEPTION 'cancelled selection removed another membership'; END IF;
  UPDATE eogp.event_participations SET status='waitlisted' WHERE organization_id=v_org AND id=v_second;
  PERFORM eogp.write_event_guest_group(v_org,v_event,v_actor,v_group,NULL,NULL);
  BEGIN
    PERFORM eogp.set_event_guest_bulk_group(v_org,v_event,v_actor,v_group,'add',v_selection);
    RAISE EXCEPTION 'retired group add accepted';
  EXCEPTION WHEN object_not_in_prerequisite_state THEN NULL; END;
  v_result := eogp.set_event_guest_bulk_group(v_org,v_event,v_actor,v_group,'remove',v_selection);
  IF v_result <> '{"processedCount":2,"updatedCount":2}'::jsonb
    OR EXISTS(SELECT 1 FROM eogp.guest_group_memberships WHERE organization_id=v_org AND group_id=v_group)
    OR NOT EXISTS(SELECT 1 FROM eogp.guest_group_memberships WHERE organization_id=v_org AND participation_id=v_first AND group_id=v_keep AND membership_kind='lead') THEN
    RAISE EXCEPTION 'retired removal lost unrelated membership or failed'; END IF;
  IF has_function_privilege('eventor_worker','eogp.set_event_guest_bulk_group(uuid,uuid,uuid,uuid,text,jsonb)','EXECUTE')
    OR NOT has_function_privilege('eventor_runtime','eogp.set_event_guest_bulk_group(uuid,uuid,uuid,uuid,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'unexpected command grants'; END IF;
END;
$test$;
ROLLBACK;
\echo 'Event guest bulk groups smoke passed.'
