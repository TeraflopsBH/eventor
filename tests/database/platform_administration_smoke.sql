\set ON_ERROR_STOP on
BEGIN;
SET LOCAL ROLE eventor_owner;
DO $test$
DECLARE
 v_a CONSTANT uuid:='10000000-0000-0000-0000-00000000000a';v_b CONSTANT uuid:='10000000-0000-0000-0000-00000000000b';
 v_user uuid:=gen_random_uuid();v_member uuid:=gen_random_uuid();v_role uuid:=gen_random_uuid();v_access eogp.platform_admin_access%ROWTYPE;v_session uuid;v_other_session uuid;v_new_org uuid:=gen_random_uuid();
BEGIN
 PERFORM set_config('app.organization_id',v_a::text,true);
 INSERT INTO eogp.users(id,email,display_name,status) VALUES(v_user,'platform-'||v_user::text||'@example.invalid','Synthetic platform administrator','active');
 INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status) VALUES(v_member,v_a,v_user,'active');
 INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind) VALUES(v_role,v_a,'INDEPENDENT-PLATFORM-FIXTURE','Independent fixture grant','organization');
 INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code) VALUES(v_a,v_role,'guest.registry.read');
 INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id) VALUES(v_a,v_member,v_role,'organization',v_member);
 PERFORM eogp.refresh_platform_admin_access(v_user);
 IF EXISTS(SELECT 1 FROM eogp.platform_admin_access WHERE user_id=v_user) THEN RAISE EXCEPTION 'ordinary membership gained platform access';END IF;
 IF has_column_privilege('eventor_auth','eogp.users','is_platform_admin','UPDATE') OR has_column_privilege('eventor_runtime','eogp.users','is_platform_admin','UPDATE') OR has_table_privilege('eventor_runtime','eogp.platform_admin_access','SELECT') OR has_table_privilege('eventor_auth','eogp.platform_admin_audit','INSERT') THEN RAISE EXCEPTION 'platform controls exposed to application roles';END IF;
 UPDATE eogp.users SET is_platform_admin=true WHERE id=v_user;
 IF (SELECT count(*) FROM eogp.platform_admin_access WHERE user_id=v_user AND organization_id IN(v_a,v_b))<>2 THEN RAISE EXCEPTION 'platform workspaces missing';END IF;
 SELECT * INTO v_access FROM eogp.platform_admin_access WHERE user_id=v_user AND organization_id=v_a;
 IF v_access.membership_id<>v_member OR v_access.previous_membership_status<>'active' THEN RAISE EXCEPTION 'existing membership not preserved';END IF;
 PERFORM set_config('app.organization_id',v_a::text,true);
 IF (SELECT count(*) FROM eogp.role_permissions WHERE organization_id=v_a AND role_id=v_access.role_id)<>(SELECT count(*) FROM eogp.permissions WHERE scope_kind<>'platform') THEN RAISE EXCEPTION 'platform role lacks current organization operations';END IF;
 BEGIN UPDATE eogp.organization_memberships SET status='suspended' WHERE organization_id=v_a AND id=v_member;RAISE EXCEPTION 'tenant operation disabled platform administrator';EXCEPTION WHEN insufficient_privilege THEN NULL;END;
 INSERT INTO eogp.user_sessions(user_id,organization_id,membership_id,session_token_sha256,csrf_token_sha256,expires_at)
 VALUES(v_user,v_a,v_member,repeat('a',64),repeat('b',64),clock_timestamp()+interval '1 hour') RETURNING id INTO v_session;
 SELECT * INTO v_access FROM eogp.platform_admin_access WHERE user_id=v_user AND organization_id=v_b;
 PERFORM set_config('app.organization_id',v_b::text,true);
 INSERT INTO eogp.user_sessions(user_id,organization_id,membership_id,session_token_sha256,csrf_token_sha256,expires_at)
 VALUES(v_user,v_b,v_access.membership_id,repeat('c',64),repeat('d',64),clock_timestamp()+interval '1 hour') RETURNING id INTO v_other_session;
 PERFORM eogp.record_staff_workspace_switch(v_user,v_b,v_access.membership_id,v_a);
 IF NOT EXISTS(SELECT 1 FROM eogp.audit_events WHERE organization_id=v_b AND action='staff.workspace_switched' AND actor_membership_id=v_access.membership_id AND safe_metadata->>'previousOrganizationId'=v_a::text) THEN RAISE EXCEPTION 'workspace switch audit missing';END IF;
 PERFORM set_config('app.organization_id',v_new_org::text,true);
 INSERT INTO eogp.organizations(id,slug,name) VALUES(v_new_org,'platform-'||v_new_org::text,'Synthetic later workspace');
 PERFORM eogp.refresh_platform_admin_access(v_user);
 IF NOT EXISTS(SELECT 1 FROM eogp.platform_admin_access WHERE user_id=v_user AND organization_id=v_new_org) THEN RAISE EXCEPTION 'new workspace not discovered';END IF;
 IF has_function_privilege('eventor_runtime','eogp.lock_staff_workspace_membership(uuid,uuid)','EXECUTE') OR NOT has_function_privilege('eventor_auth','eogp.lock_staff_workspace_membership(uuid,uuid)','EXECUTE') THEN RAISE EXCEPTION 'workspace lock helper exposed';END IF;
 BEGIN UPDATE eogp.platform_admin_audit SET reason='mutated' WHERE user_id=v_user;RAISE EXCEPTION 'platform audit mutable';EXCEPTION WHEN object_not_in_prerequisite_state OR insufficient_privilege THEN NULL;END;
 UPDATE eogp.users SET is_platform_admin=false WHERE id=v_user;
 PERFORM set_config('app.organization_id',v_b::text,true);
 IF EXISTS(SELECT 1 FROM eogp.user_role_grants WHERE organization_id=v_b AND id=v_access.grant_id AND revoked_at IS NULL)
  OR EXISTS(SELECT 1 FROM eogp.user_sessions WHERE organization_id=v_b AND id=v_other_session AND revoked_at IS NULL)
  OR EXISTS(SELECT 1 FROM eogp.organization_memberships WHERE organization_id=v_b AND id=v_access.membership_id AND status='active') THEN RAISE EXCEPTION 'revocation retained platform-only access';END IF;
 PERFORM set_config('app.organization_id',v_a::text,true);
 IF EXISTS(SELECT 1 FROM eogp.user_sessions WHERE organization_id=v_a AND id=v_session AND revoked_at IS NULL)
  OR NOT EXISTS(SELECT 1 FROM eogp.organization_memberships WHERE organization_id=v_a AND id=v_member AND status='active')
  OR NOT EXISTS(SELECT 1 FROM eogp.user_role_grants WHERE organization_id=v_a AND membership_id=v_member AND role_id=v_role AND revoked_at IS NULL) THEN RAISE EXCEPTION 'revocation lost independent membership or kept its privileged session';END IF;
 IF NOT EXISTS(SELECT 1 FROM eogp.platform_admin_audit WHERE user_id=v_user AND action='platform_admin_granted') OR NOT EXISTS(SELECT 1 FROM eogp.platform_admin_audit WHERE user_id=v_user AND action='platform_admin_revoked') THEN RAISE EXCEPTION 'platform provisioning audit missing';END IF;
END;
$test$;
ROLLBACK;
\echo 'Platform administration and workspace audit smoke passed.'
