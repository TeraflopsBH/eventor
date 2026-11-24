-- Host-provisioned platform administrators are explicit; existing users remain ordinary members.
ALTER TABLE eogp.users ADD COLUMN is_platform_admin boolean NOT NULL DEFAULT false;
GRANT SELECT(is_platform_admin) ON eogp.users TO eventor_auth;
-- Private global identifier index. Tenant organizations retain forced RLS.
CREATE TABLE eogp.platform_admin_organizations(organization_id uuid PRIMARY KEY REFERENCES eogp.organizations(id) ON DELETE CASCADE);
REVOKE ALL ON eogp.platform_admin_organizations FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
LOCK TABLE eogp.organizations IN ACCESS EXCLUSIVE MODE;
ALTER TABLE eogp.organizations NO FORCE ROW LEVEL SECURITY;
INSERT INTO eogp.platform_admin_organizations SELECT id FROM eogp.organizations;
ALTER TABLE eogp.organizations FORCE ROW LEVEL SECURITY;
CREATE FUNCTION eogp.index_platform_organization() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
BEGIN INSERT INTO eogp.platform_admin_organizations VALUES(NEW.id);RETURN NEW;END;
$function$;
REVOKE ALL ON FUNCTION eogp.index_platform_organization() FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
CREATE TRIGGER platform_organization_index AFTER INSERT ON eogp.organizations FOR EACH ROW EXECUTE FUNCTION eogp.index_platform_organization();

CREATE TABLE eogp.platform_admin_access (
 user_id uuid NOT NULL REFERENCES eogp.users(id),organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
 membership_id uuid NOT NULL,role_id uuid NOT NULL,grant_id uuid NOT NULL,previous_membership_status text,
 PRIMARY KEY(user_id,organization_id),
 FOREIGN KEY(organization_id,membership_id) REFERENCES eogp.organization_memberships(organization_id,id),
 FOREIGN KEY(organization_id,role_id) REFERENCES eogp.roles(organization_id,id),
 FOREIGN KEY(organization_id,grant_id) REFERENCES eogp.user_role_grants(organization_id,id)
);
CREATE TABLE eogp.platform_admin_audit (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),user_id uuid NOT NULL REFERENCES eogp.users(id),
 action text NOT NULL,organization_id uuid REFERENCES eogp.organizations(id),
 database_principal text NOT NULL DEFAULT session_user,reason text NOT NULL DEFAULT 'host provisioning',
 occurred_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
-- Global control-plane records, deliberately unavailable to tenant/runtime/auth table queries.
REVOKE ALL ON eogp.platform_admin_access,eogp.platform_admin_audit FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
CREATE TRIGGER platform_admin_audit_append_only BEFORE UPDATE OR DELETE ON eogp.platform_admin_audit FOR EACH ROW EXECUTE FUNCTION eogp.reject_append_only_mutation();

CREATE FUNCTION eogp.refresh_platform_admin_access(p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_org record;v_access eogp.platform_admin_access%ROWTYPE;v_member eogp.organization_memberships%ROWTYPE;
 v_role uuid;v_grant uuid;v_previous text;v_changes integer;
BEGIN
 PERFORM 1 FROM eogp.users WHERE id=p_user AND status='active' AND is_platform_admin FOR SHARE;
 IF NOT FOUND THEN RETURN;END IF;
 FOR v_org IN SELECT organization_id AS id FROM eogp.platform_admin_organizations ORDER BY organization_id LOOP
  PERFORM set_config('app.organization_id',v_org.id::text,true);
  PERFORM 1 FROM eogp.organizations WHERE id=v_org.id AND status='active' FOR SHARE;
  IF NOT FOUND THEN CONTINUE;END IF;
  PERFORM pg_advisory_xact_lock(hashtextextended('eventor:organization-access:'||v_org.id::text,0));
  SELECT * INTO v_access FROM eogp.platform_admin_access WHERE user_id=p_user AND organization_id=v_org.id;
  SELECT * INTO v_member FROM eogp.organization_memberships WHERE organization_id=v_org.id AND user_id=p_user FOR UPDATE;
  v_previous:=v_member.status;
  IF v_member.id IS NULL THEN
   INSERT INTO eogp.organization_memberships(organization_id,user_id,status,joined_at) VALUES(v_org.id,p_user,'active',clock_timestamp()) RETURNING * INTO v_member;
  ELSIF v_member.status<>'active' THEN
   UPDATE eogp.organization_memberships SET status='active',revoked_at=NULL,joined_at=coalesce(joined_at,clock_timestamp()) WHERE organization_id=v_org.id AND id=v_member.id RETURNING * INTO v_member;
  END IF;
  IF v_access.role_id IS NULL THEN
   v_role:=gen_random_uuid();
   INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind,is_system_preset) VALUES(v_role,v_org.id,'PA_'||replace(v_role::text,'-',''),'Platform administrator','organization',true);
  ELSE v_role:=v_access.role_id;END IF;
  INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
   SELECT v_org.id,v_role,code FROM eogp.permissions WHERE scope_kind<>'platform' ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_changes=ROW_COUNT;
  IF v_access.grant_id IS NULL OR NOT EXISTS(SELECT 1 FROM eogp.user_role_grants WHERE organization_id=v_org.id AND id=v_access.grant_id AND revoked_at IS NULL AND (expires_at IS NULL OR expires_at>clock_timestamp())) THEN
   INSERT INTO eogp.user_role_grants(organization_id,membership_id,role_id,scope_kind,granted_by_membership_id)
    VALUES(v_org.id,v_member.id,v_role,'organization',v_member.id) RETURNING id INTO v_grant;
   INSERT INTO eogp.platform_admin_access(user_id,organization_id,membership_id,role_id,grant_id,previous_membership_status)
    VALUES(p_user,v_org.id,v_member.id,v_role,v_grant,v_previous)
    ON CONFLICT(user_id,organization_id) DO UPDATE SET membership_id=EXCLUDED.membership_id,grant_id=EXCLUDED.grant_id,previous_membership_status=EXCLUDED.previous_membership_status;
   INSERT INTO eogp.platform_admin_audit(user_id,action,organization_id) VALUES(p_user,'workspace_access_provisioned',v_org.id);
  ELSIF v_changes>0 THEN
   INSERT INTO eogp.platform_admin_audit(user_id,action,organization_id) VALUES(p_user,'workspace_permissions_refreshed',v_org.id);
  END IF;
 END LOOP;
END;
$function$;
REVOKE ALL ON FUNCTION eogp.refresh_platform_admin_access(uuid) FROM PUBLIC,eventor_runtime,eventor_worker;
GRANT EXECUTE ON FUNCTION eogp.refresh_platform_admin_access(uuid) TO eventor_auth;

CREATE FUNCTION eogp.guard_platform_admin_membership()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
BEGIN
 IF NEW.status<>'active' AND EXISTS(SELECT 1 FROM eogp.users WHERE id=NEW.user_id AND is_platform_admin) THEN
  RAISE EXCEPTION 'platform administrator access is managed by the host administrator' USING ERRCODE='42501';END IF;
 RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION eogp.guard_platform_admin_membership() FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
CREATE TRIGGER platform_admin_membership_guard BEFORE UPDATE OF status ON eogp.organization_memberships FOR EACH ROW EXECUTE FUNCTION eogp.guard_platform_admin_membership();

CREATE FUNCTION eogp.platform_admin_flag_changed()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
DECLARE v_access record;
BEGIN
 INSERT INTO eogp.platform_admin_audit(user_id,action,reason) VALUES(NEW.id,CASE WHEN NEW.is_platform_admin THEN 'platform_admin_granted' ELSE 'platform_admin_revoked' END,coalesce(nullif(current_setting('app.platform_admin_reason',true),''),'host provisioning'));
 IF NEW.is_platform_admin THEN PERFORM eogp.refresh_platform_admin_access(NEW.id);
 ELSE
  FOR v_access IN SELECT * FROM eogp.platform_admin_access WHERE user_id=NEW.id ORDER BY organization_id LOOP
   PERFORM set_config('app.organization_id',v_access.organization_id::text,true);
   PERFORM pg_advisory_xact_lock(hashtextextended('eventor:organization-access:'||v_access.organization_id::text,0));
   UPDATE eogp.user_role_grants SET revoked_at=coalesce(revoked_at,clock_timestamp()) WHERE organization_id=v_access.organization_id AND id=v_access.grant_id;
   UPDATE eogp.user_sessions SET revoked_at=coalesce(revoked_at,clock_timestamp()) WHERE user_id=NEW.id AND organization_id=v_access.organization_id AND membership_id=v_access.membership_id;
   IF v_access.previous_membership_status IS DISTINCT FROM 'active' THEN
    UPDATE eogp.organization_memberships SET status=coalesce(v_access.previous_membership_status,'revoked'),revoked_at=CASE WHEN coalesce(v_access.previous_membership_status,'revoked')='revoked' THEN clock_timestamp() ELSE NULL END
     WHERE organization_id=v_access.organization_id AND id=v_access.membership_id;
   END IF;
  END LOOP;
 END IF;
 RETURN NEW;
END;
$function$;
REVOKE ALL ON FUNCTION eogp.platform_admin_flag_changed() FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
CREATE TRIGGER platform_admin_flag_guard AFTER UPDATE OF is_platform_admin ON eogp.users FOR EACH ROW WHEN(OLD.is_platform_admin IS DISTINCT FROM NEW.is_platform_admin) EXECUTE FUNCTION eogp.platform_admin_flag_changed();

CREATE FUNCTION eogp.record_staff_workspace_switch(p_user uuid,p_org uuid,p_member uuid,p_previous_org uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
BEGIN
 PERFORM set_config('app.organization_id',p_org::text,true);
 IF NOT EXISTS(SELECT 1 FROM eogp.organization_memberships WHERE organization_id=p_org AND id=p_member AND user_id=p_user AND status='active') THEN
  RAISE EXCEPTION 'workspace membership is unavailable' USING ERRCODE='42501';END IF;
 INSERT INTO eogp.audit_events(organization_id,actor_organization_id,actor_membership_id,actor_kind,action,aggregate_type,aggregate_id,safe_metadata)
  VALUES(p_org,p_org,p_member,'membership','staff.workspace_switched','organization',p_org,jsonb_build_object('previousOrganizationId',p_previous_org));
END;
$function$;
REVOKE ALL ON FUNCTION eogp.record_staff_workspace_switch(uuid,uuid,uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker;
GRANT EXECUTE ON FUNCTION eogp.record_staff_workspace_switch(uuid,uuid,uuid,uuid) TO eventor_auth;

-- Lock/revalidate only the selected user's target membership without granting auth tenant-table UPDATE.
CREATE FUNCTION eogp.lock_staff_workspace_membership(p_user uuid,p_org uuid)
RETURNS TABLE(user_id uuid,membership_id uuid,organization_id uuid)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,eogp AS $function$
BEGIN
 PERFORM set_config('app.organization_id',p_org::text,true);
 RETURN QUERY SELECT account.id,membership.id,organization.id
 FROM eogp.users account JOIN eogp.organization_memberships membership ON membership.user_id=account.id
 JOIN eogp.organizations organization ON organization.id=membership.organization_id
 WHERE account.id=p_user AND organization.id=p_org AND account.status='active' AND membership.status='active' AND organization.status='active'
 FOR SHARE OF account,membership,organization;
END;
$function$;
REVOKE ALL ON FUNCTION eogp.lock_staff_workspace_membership(uuid,uuid) FROM PUBLIC,eventor_runtime,eventor_worker;
GRANT EXECUTE ON FUNCTION eogp.lock_staff_workspace_membership(uuid,uuid) TO eventor_auth;
