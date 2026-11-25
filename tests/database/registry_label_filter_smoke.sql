\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
DO $test$
DECLARE
 v_org CONSTANT uuid:='10000000-0000-0000-0000-00000000000a';v_foreign CONSTANT uuid:='10000000-0000-0000-0000-00000000000b';
 v_actor uuid:=gen_random_uuid();v_user uuid:=gen_random_uuid();v_role uuid:=gen_random_uuid();v_label uuid;v_foreign_label uuid;
 v_person uuid;v_archived uuid;v_tag text:='LabelFilter-'||gen_random_uuid()::text;v_first jsonb;v_second jsonb;v_result jsonb;v_export jsonb;v_labels jsonb;
BEGIN
 PERFORM set_config('app.organization_id',v_org::text,true);PERFORM set_config('app.actor_membership_id',v_actor::text,true);
 INSERT INTO eogp.users(id,email,display_name,status) VALUES(v_user,v_tag||'@example.invalid','Synthetic classification filter operator','active');
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(v_actor,v_org,v_user,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(v_role,v_org,'CI-LABEL-FILTER','Synthetic classification filter role','organization');
 INSERT INTO eogp.role_permissions SELECT v_org,v_role,code FROM unnest(ARRAY['guest.registry.read','guest.registry.manage','guest.registry.export']) code;
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(v_org,v_actor,v_role,'organization',v_actor);
 v_label:=(eogp.write_registry_label(v_org,v_actor,NULL,'Synthetic filter VIP')->>'labelId')::uuid;
 FOR n IN 1..55 LOOP
  v_person:=(eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',jsonb_build_object('firstName','Synthetic','lastName',v_tag||'-'||lpad(n::text,3,'0')))->>'personId')::uuid;
  PERFORM eogp.set_registry_person_labels(v_org,v_actor,v_person,1,ARRAY[v_label]);
  IF n=55 THEN v_archived:=v_person;END IF;
 END LOOP;
 FOR n IN 1..60 LOOP
  PERFORM eogp.write_guest_registry_person(v_org,v_actor,NULL,NULL,'create',jsonb_build_object('firstName','Synthetic','lastName',v_tag||'-000-unclassified-'||n::text));
 END LOOP;
 v_first:=eogp.read_guest_registry(v_org,v_actor,NULL,v_tag,false,0,v_label);
 v_second:=eogp.read_guest_registry(v_org,v_actor,NULL,v_tag,false,50,v_label);
 IF jsonb_array_length(v_first->'people') IS DISTINCT FROM 50 OR v_first->>'nextOffset' IS DISTINCT FROM '50' OR jsonb_array_length(v_second->'people') IS DISTINCT FROM 5 OR v_second->'nextOffset' IS DISTINCT FROM 'null'::jsonb THEN RAISE EXCEPTION 'classification filter applied after pagination';END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(v_first->'people') a JOIN jsonb_array_elements(v_second->'people') b ON a->>'personId'=b->>'personId') OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_first->'people') item WHERE NOT(item->'labels' @> jsonb_build_array(jsonb_build_object('labelId',v_label)))) THEN RAISE EXCEPTION 'filtered page overlaps or lost label badges';END IF;
 v_export:=eogp.read_guest_registry_export(v_org,v_actor,v_tag,false,v_label);
 IF jsonb_array_length(v_export->'people') IS DISTINCT FROM 55 OR EXISTS(SELECT 1 FROM jsonb_array_elements(v_export->'people') item WHERE item->>'lastName' LIKE '%unclassified%') THEN RAISE EXCEPTION 'export ignored classification filter';END IF;
 IF jsonb_array_length(eogp.read_guest_registry(v_org,v_actor,NULL,v_tag||'-001',false,0,v_label)->'people') IS DISTINCT FROM 1 OR jsonb_array_length(eogp.read_guest_registry_export(v_org,v_actor,v_tag||'-001',false,v_label)->'people') IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'name/classification intersection ignored';END IF;
 -- Export limits apply after classification filtering, not to unrelated profiles.
 BEGIN
  INSERT INTO eogp.persons(organization_id,first_name,last_name,created_by_membership_id) SELECT v_org,'Synthetic',v_tag||'-bulk-unclassified-'||n::text,v_actor FROM generate_series(1,20001) n;
  IF jsonb_array_length(eogp.read_guest_registry_export(v_org,v_actor,v_tag,false,v_label)->'people') IS DISTINCT FROM 55 OR eogp.read_guest_registry_export(v_org,v_actor,v_tag,false)->>'limitExceeded' IS DISTINCT FROM 'true' THEN RAISE EXCEPTION 'export limit applied before classification filtering';END IF;
  RAISE EXCEPTION 'rollback synthetic export-limit case' USING ERRCODE='P9999';
 EXCEPTION WHEN SQLSTATE 'P9999' THEN NULL;
 END;
 PERFORM eogp.write_registry_label(v_org,v_actor,v_label,NULL);
 v_labels:=eogp.list_registry_labels(v_org,v_actor);
 IF NOT(v_labels @> jsonb_build_array(jsonb_build_object('labelId',v_label,'retired',true))) OR jsonb_array_length(eogp.read_guest_registry_export(v_org,v_actor,v_tag,false,v_label)->'people') IS DISTINCT FROM 55 THEN RAISE EXCEPTION 'retirement hid historical classifications';END IF;
 PERFORM eogp.write_guest_registry_person(v_org,v_actor,v_archived,2,'archive','{}');
 IF jsonb_array_length(eogp.read_guest_registry_export(v_org,v_actor,v_tag,false,v_label)->'people') IS DISTINCT FROM 54 OR jsonb_array_length(eogp.read_guest_registry_export(v_org,v_actor,v_tag,true,v_label)->'people') IS DISTINCT FROM 1 THEN RAISE EXCEPTION 'profile-state filter ignored';END IF;
 IF jsonb_array_length(eogp.read_guest_registry_export(v_org,v_actor,v_tag,false)->'people') IS DISTINCT FROM 114 THEN RAISE EXCEPTION 'legacy unfiltered export changed';END IF;
 PERFORM set_config('app.organization_id',v_foreign::text,true);
 INSERT INTO eogp.registry_labels(organization_id,label) VALUES(v_foreign,'Synthetic foreign filter label') RETURNING id INTO v_foreign_label;
 PERFORM set_config('app.organization_id',v_org::text,true);
 IF eogp.list_registry_labels(v_org,v_actor) @> jsonb_build_array(jsonb_build_object('labelId',v_foreign_label)) OR eogp.read_guest_registry(v_org,v_actor,NULL,v_tag,false,0,v_foreign_label)->'people' IS DISTINCT FROM '[]'::jsonb OR eogp.read_guest_registry_export(v_org,v_actor,v_tag,false,v_foreign_label)->'people' IS DISTINCT FROM '[]'::jsonb THEN RAISE EXCEPTION 'foreign classification leaked';END IF;
 IF eogp.read_guest_registry(v_org,v_actor,NULL,v_tag,false,0,gen_random_uuid())->'people' IS DISTINCT FROM '[]'::jsonb THEN RAISE EXCEPTION 'unknown classification ignored';END IF;
 DELETE FROM eogp.role_permissions WHERE organization_id=v_org AND role_id=v_role AND permission_code IN('guest.registry.manage','guest.registry.export');
 IF jsonb_array_length(eogp.read_guest_registry(v_org,v_actor,NULL,v_tag,false,0,v_label)->'people') IS DISTINCT FROM 50 OR NOT(eogp.list_registry_labels(v_org,v_actor) @> jsonb_build_array(jsonb_build_object('labelId',v_label))) THEN RAISE EXCEPTION 'read-only classification search unavailable';END IF;
 BEGIN PERFORM eogp.read_guest_registry_export(v_org,v_actor,v_tag,false,v_label);RAISE EXCEPTION 'classification filter bypassed export permission';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 DELETE FROM eogp.role_permissions WHERE organization_id=v_org AND role_id=v_role AND permission_code='guest.registry.read';
 BEGIN PERFORM eogp.list_registry_labels(v_org,v_actor);RAISE EXCEPTION 'revoked Registry authority exposed classifications';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 BEGIN PERFORM eogp.read_guest_registry(v_org,v_actor,NULL,v_tag,false,0,v_label);RAISE EXCEPTION 'revoked Registry authority searched classifications';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 IF has_table_privilege('eventor_runtime','eogp.registry_person_label_assignments','SELECT') THEN RAISE EXCEPTION 'classification table access granted';END IF;
END;
$test$;
ROLLBACK;
\echo 'Registry classification filter, pagination and export smoke passed.'
