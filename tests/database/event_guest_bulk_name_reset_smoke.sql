\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
DO $test$
DECLARE
  v_org CONSTANT uuid := '10000000-0000-0000-0000-00000000000a';
  v_user uuid := gen_random_uuid(); v_actor uuid := gen_random_uuid(); v_role uuid := gen_random_uuid();
  v_event uuid := gen_random_uuid(); v_other uuid := gen_random_uuid();
  v_person uuid; v_first uuid; v_second uuid; v_foreign uuid;
  v_selection jsonb; v_result jsonb; v_revisions jsonb; v_audits integer;
BEGIN
  PERFORM set_config('app.organization_id',v_org::text,true);
  PERFORM set_config('app.actor_membership_id',v_actor::text,true);
  INSERT INTO eogp.users(id,email,display_name,status)
    VALUES(v_user,'bulk-name-reset-'||v_user::text||'@example.invalid','Bulk name reset fixture','active');
  INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status,joined_at)
    VALUES(v_actor,v_org,v_user,'active',clock_timestamp());
  INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind)
    VALUES(v_role,v_org,'CI-BULK-NAME-RESET','Bulk name reset fixture','organization');
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
    SELECT v_org,v_role,code FROM unnest(ARRAY['guest.manage','guest.registry.manage']) code;
  INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id)
    VALUES(v_org,v_actor,v_role,'organization',v_actor);
  INSERT INTO eogp.events(id,organization_id,event_code,title,created_by_membership_id)
    VALUES(v_event,v_org,'CI-BULK-NAME-RESET','Bulk name reset fixture',v_actor),
      (v_other,v_org,'CI-BULK-NAME-RESET-OTHER','Other event fixture',v_actor);
  INSERT INTO eogp.event_capability_overrides(organization_id,event_id,capability_code,enabled,changed_by_membership_id)
    VALUES(v_org,v_event,'guest_registry',true,v_actor),(v_org,v_other,'guest_registry',true,v_actor);
  v_person := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Bulk","lastName":"Group First"}')->>'personId')::uuid;
  v_first := (eogp.link_registry_person_to_event(v_org,v_event,v_actor,v_person,'eligible')->>'participationId')::uuid;
  v_person := (eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create','{"firstName":"Bulk","lastName":"Group Second"}')->>'personId')::uuid;
  v_second := (eogp.link_registry_person_to_event(v_org,v_event,v_actor,v_person,'waitlisted')->>'participationId')::uuid;
  v_foreign := (eogp.link_registry_person_to_event(v_org,v_other,v_actor,v_person,'eligible')->>'participationId')::uuid;
  PERFORM eogp.set_event_guest_roster_name(v_org,v_event,v_actor,v_first,1,'Temporary first name');
  PERFORM eogp.set_event_guest_roster_name(v_org,v_event,v_actor,v_second,1,'Temporary second name');
  SELECT jsonb_agg(jsonb_build_object('participationId',id,'expectedRevision',revision) ORDER BY id) INTO v_selection
    FROM eogp.event_participations WHERE organization_id=v_org AND id IN(v_first,v_second);
  SELECT jsonb_agg(jsonb_build_object('id',id,'snapshot',person_identity_snapshot) ORDER BY id) INTO v_revisions
    FROM eogp.event_participations WHERE organization_id=v_org AND id IN(v_first,v_second);
  BEGIN
    PERFORM eogp.reset_event_guest_bulk_roster_names(v_org,v_event,v_actor,jsonb_set(v_selection,'{1,expectedRevision}','1'));
    RAISE EXCEPTION 'stale selection accepted';
  EXCEPTION WHEN serialization_failure THEN NULL;END;
  IF (SELECT count(*) FROM eogp.event_participations WHERE organization_id=v_org AND id IN(v_first,v_second) AND revision=2 AND roster_display_name_override IS NOT NULL)<>2 THEN RAISE EXCEPTION 'stale batch partially reset names';END IF;
  v_result:=eogp.reset_event_guest_bulk_roster_names(v_org,v_event,v_actor,v_selection);
  IF v_result<>'{"processedCount":2,"updatedCount":2}'::jsonb OR EXISTS(SELECT 1 FROM eogp.event_participations WHERE organization_id=v_org AND id IN(v_first,v_second) AND roster_display_name_override IS NOT NULL) THEN RAISE EXCEPTION 'bulk names not reset';END IF;
  IF (SELECT jsonb_agg(jsonb_build_object('id',id,'snapshot',person_identity_snapshot) ORDER BY id) FROM eogp.event_participations WHERE organization_id=v_org AND id IN(v_first,v_second)) IS DISTINCT FROM v_revisions THEN RAISE EXCEPTION 'recorded identities changed';END IF;
  SELECT jsonb_agg(jsonb_build_object('participationId',id,'expectedRevision',revision) ORDER BY id) INTO v_selection FROM eogp.event_participations WHERE organization_id=v_org AND id IN(v_first,v_second);
  v_result:=eogp.reset_event_guest_bulk_roster_names(v_org,v_event,v_actor,v_selection);
  IF v_result<>'{"processedCount":2,"updatedCount":0}'::jsonb THEN RAISE EXCEPTION 'reset of unchanged names mutated rows';END IF;
  BEGIN PERFORM eogp.reset_event_guest_bulk_roster_names(v_org,v_other,v_actor,v_selection);RAISE EXCEPTION 'cross-event selection accepted';EXCEPTION WHEN no_data_found THEN NULL;END;
  BEGIN PERFORM eogp.reset_event_guest_bulk_roster_names(v_org,v_event,v_actor,v_selection||v_selection);RAISE EXCEPTION 'duplicate selection accepted';EXCEPTION WHEN invalid_parameter_value THEN NULL;END;
  DELETE FROM eogp.role_permissions WHERE organization_id=v_org AND role_id=v_role AND permission_code='guest.manage';
  BEGIN PERFORM eogp.reset_event_guest_bulk_roster_names(v_org,v_event,v_actor,v_selection);RAISE EXCEPTION 'reset allowed after permission removal';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
END;
$test$;
ROLLBACK;
\echo 'Bulk roster display-name reset smoke passed.'
