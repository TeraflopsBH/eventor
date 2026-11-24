\set ON_ERROR_STOP on

-- Run as eventor_auth with no tenant GUC set.
DO $test$
DECLARE
  organization_count integer;
  membership_count integer;
  user_count integer;
  can_bypass boolean;
  public_definer_functions text;
  tenant_tables_without_forced_rls text;
  v_role text;
  v_function text;
BEGIN
  SELECT count(id) INTO organization_count FROM eogp.organizations;
  SELECT count(id) INTO membership_count FROM eogp.organization_memberships;
  SELECT count(id) INTO user_count FROM eogp.users WHERE email = 'ci-extended-a@example.invalid';

  IF organization_count < 5 OR membership_count < 5 OR user_count <> 1 THEN
    RAISE EXCEPTION
      'auth role lookup failed: organizations %, memberships %, matching users %',
      organization_count, membership_count, user_count;
  END IF;

  SELECT rolbypassrls INTO can_bypass FROM pg_roles WHERE rolname = current_user;
  IF can_bypass IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'authentication role must not have BYPASSRLS';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM pg_roles
     WHERE rolname IN ('eventor_owner','eventor_migrator','eventor_runtime','eventor_worker','eventor_auth')
       AND (
         rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication OR rolbypassrls
         OR (rolname = 'eventor_owner' AND rolcanlogin)
         OR (rolname <> 'eventor_owner' AND (NOT rolcanlogin OR rolinherit))
       )
  ) THEN
    RAISE EXCEPTION 'Eventor database roles do not match the least-privilege bootstrap contract';
  END IF;

  IF EXISTS (
    SELECT 1
      FROM pg_auth_members AS role_membership
      JOIN pg_roles AS granted_role ON granted_role.oid = role_membership.roleid
      JOIN pg_roles AS member_role ON member_role.oid = role_membership.member
     WHERE member_role.rolname IN (
       'eventor_owner','eventor_migrator','eventor_runtime','eventor_worker','eventor_auth'
     )
       AND NOT (
         granted_role.rolname = 'eventor_owner'
         AND member_role.rolname = 'eventor_migrator'
       )
  ) OR NOT EXISTS (
    SELECT 1
      FROM pg_auth_members AS role_membership
      JOIN pg_roles AS granted_role ON granted_role.oid = role_membership.roleid
      JOIN pg_roles AS member_role ON member_role.oid = role_membership.member
     WHERE granted_role.rolname = 'eventor_owner'
       AND member_role.rolname = 'eventor_migrator'
  ) THEN
    RAISE EXCEPTION 'Eventor database roles have unexpected memberships or lack the migrator-to-owner membership';
  END IF;

  IF has_table_privilege(current_user, 'eogp.venues', 'SELECT')
     OR has_table_privilege(current_user, 'eogp.organization_memberships', 'UPDATE')
     OR has_table_privilege(current_user, 'eogp.users', 'DELETE') THEN
    RAISE EXCEPTION 'authentication role has excessive business-table or identity-delete privileges';
  END IF;

  -- Authentication access is intentionally column-scoped. A table-level
  -- grant would silently expand when new identity/session columns are added.
  IF has_table_privilege(current_user, 'eogp.users', 'SELECT')
     OR has_table_privilege(current_user, 'eogp.users', 'INSERT')
     OR has_table_privilege(current_user, 'eogp.users', 'UPDATE')
     OR has_table_privilege(current_user, 'eogp.user_sessions', 'SELECT')
     OR has_table_privilege(current_user, 'eogp.user_sessions', 'INSERT')
     OR has_table_privilege(current_user, 'eogp.user_sessions', 'UPDATE')
     OR has_table_privilege(current_user, 'eogp.organization_memberships', 'SELECT')
     OR has_table_privilege(current_user, 'eogp.organizations', 'SELECT')
     OR has_table_privilege('eventor_runtime', 'eogp.users', 'SELECT')
     OR has_table_privilege('eventor_runtime', 'eogp.user_sessions', 'SELECT')
     OR has_table_privilege('eventor_worker', 'eogp.users', 'SELECT')
     OR has_table_privilege('eventor_worker', 'eogp.user_sessions', 'SELECT') THEN
    RAISE EXCEPTION 'authentication/business roles have table-wide identity privileges; expected column-only auth access';
  END IF;

  -- Delegated task records contain owner-tenant operational data. Every
  -- application role must be denied both table-level and column-level access;
  -- checking only has_table_privilege would miss explicit column grants.
  FOREACH v_role IN ARRAY ARRAY['eventor_runtime','eventor_worker','eventor_auth'] LOOP
    IF has_table_privilege(v_role,'eogp.event_responsibility_assignments','SELECT')
       OR has_table_privilege(v_role,'eogp.event_responsibility_assignments','INSERT')
       OR has_table_privilege(v_role,'eogp.event_responsibility_assignments','UPDATE')
       OR has_table_privilege(v_role,'eogp.event_responsibility_assignments','DELETE')
       OR has_table_privilege(v_role,'eogp.event_responsibility_assignments','TRUNCATE')
       OR has_any_column_privilege(v_role,'eogp.event_responsibility_assignments','SELECT')
       OR has_any_column_privilege(v_role,'eogp.event_responsibility_assignments','INSERT')
       OR has_any_column_privilege(v_role,'eogp.event_responsibility_assignments','UPDATE') THEN
      RAISE EXCEPTION 'application role % has direct access to delegated task records',v_role;
    END IF;
  END LOOP;
  IF EXISTS (
    SELECT 1
      FROM pg_class relation
      JOIN pg_namespace namespace ON namespace.oid=relation.relnamespace
      CROSS JOIN LATERAL aclexplode(
        coalesce(relation.relacl,acldefault('r',relation.relowner))
      ) privilege
     WHERE namespace.nspname='eogp'
       AND relation.relname='event_responsibility_assignments'
       AND privilege.grantee=0
  ) THEN
    RAISE EXCEPTION 'PUBLIC has direct privileges on delegated task records';
  END IF;

  -- Permission predicates are implementation helpers, not public database
  -- APIs. None of the application roles or PUBLIC may execute them directly.
  FOREACH v_role IN ARRAY ARRAY['eventor_runtime','eventor_worker','eventor_auth'] LOOP
    FOREACH v_function IN ARRAY ARRAY[
      'eogp.assert_event_command_permission(uuid,uuid,uuid,text)',
      'eogp.assert_booking_inquiry_permission(uuid,uuid,text)',
      'eogp.assert_booking_draft_permission(uuid,uuid,uuid,text)',
      'eogp.assert_booking_commercial_permission(uuid,uuid,text[])',
      'eogp.assert_collaboration_manage_permission(uuid,uuid)'
    ] LOOP
      IF has_function_privilege(v_role,v_function,'EXECUTE') THEN
        RAISE EXCEPTION 'application role % can execute internal authorization helper % directly',
          v_role,v_function;
      END IF;
    END LOOP;
  END LOOP;
  IF EXISTS (
    SELECT 1
      FROM pg_proc routine
      JOIN pg_namespace namespace ON namespace.oid=routine.pronamespace
      CROSS JOIN LATERAL aclexplode(
        coalesce(routine.proacl,acldefault('f',routine.proowner))
      ) privilege
     WHERE namespace.nspname='eogp'
       AND routine.oid IN (
         'eogp.assert_event_command_permission(uuid,uuid,uuid,text)'::regprocedure,
         'eogp.assert_booking_inquiry_permission(uuid,uuid,text)'::regprocedure,
         'eogp.assert_booking_draft_permission(uuid,uuid,uuid,text)'::regprocedure,
         'eogp.assert_booking_commercial_permission(uuid,uuid,text[])'::regprocedure,
         'eogp.assert_collaboration_manage_permission(uuid,uuid)'::regprocedure
       )
       AND privilege.grantee=0
       AND privilege.privilege_type='EXECUTE'
  ) THEN
    RAISE EXCEPTION 'PUBLIC can execute an internal authorization helper directly';
  END IF;

  IF NOT has_column_privilege(current_user, 'eogp.users', 'password_hash', 'SELECT')
     OR NOT has_column_privilege(current_user, 'eogp.users', 'password_hash', 'UPDATE')
     OR NOT has_column_privilege(current_user, 'eogp.users', 'email', 'SELECT') THEN
    RAISE EXCEPTION 'authentication role lacks required credential lookup/password-update privileges';
  END IF;

  IF NOT has_column_privilege(current_user, 'eogp.user_sessions', 'session_token_sha256', 'SELECT')
     OR NOT has_column_privilege(current_user, 'eogp.user_sessions', 'csrf_token_sha256', 'SELECT')
     OR NOT has_column_privilege(current_user, 'eogp.user_sessions', 'last_seen_at', 'UPDATE')
     OR NOT has_column_privilege(current_user, 'eogp.user_sessions', 'revoked_at', 'UPDATE')
     OR NOT has_column_privilege(current_user, 'eogp.user_sessions', 'session_token_sha256', 'INSERT')
     OR has_column_privilege(current_user, 'eogp.user_sessions', 'session_token_sha256', 'UPDATE')
     OR has_column_privilege(current_user, 'eogp.user_sessions', 'csrf_token_sha256', 'UPDATE')
     OR has_column_privilege(current_user, 'eogp.user_sessions', 'user_id', 'UPDATE')
     OR has_column_privilege(current_user, 'eogp.user_sessions', 'revoked_at', 'INSERT')
     OR has_table_privilege(current_user, 'eogp.user_sessions', 'DELETE')
     OR has_table_privilege('eventor_runtime', 'eogp.user_sessions', 'SELECT')
     OR has_table_privilege('eventor_worker', 'eogp.user_sessions', 'SELECT') THEN
    RAISE EXCEPTION 'session column privileges are broader or narrower than the authentication service requires';
  END IF;

  IF NOT has_table_privilege(current_user, 'eogp.auth_login_attempts', 'SELECT')
     OR NOT has_table_privilege(current_user, 'eogp.auth_login_attempts', 'INSERT')
     OR NOT has_column_privilege(current_user, 'eogp.auth_login_attempts', 'failed_attempts', 'UPDATE')
     OR NOT has_column_privilege(current_user, 'eogp.auth_login_attempts', 'blocked_until', 'UPDATE')
     OR has_column_privilege(current_user, 'eogp.auth_login_attempts', 'email_fingerprint', 'UPDATE')
     OR has_table_privilege(current_user, 'eogp.auth_login_attempts', 'DELETE') THEN
    RAISE EXCEPTION 'authentication rate-limit column privileges are incorrect';
  END IF;

  IF has_column_privilege(current_user, 'eogp.users', 'email', 'UPDATE')
     OR has_column_privilege(current_user, 'eogp.users', 'status', 'UPDATE')
     OR has_column_privilege(current_user, 'eogp.users', 'email_verified_at', 'UPDATE')
     OR NOT has_column_privilege(current_user, 'eogp.users', 'locale_preference', 'UPDATE')
     OR NOT has_column_privilege(current_user, 'eogp.users', 'password_hash', 'UPDATE') THEN
    RAISE EXCEPTION 'authentication role can change account identity/state or lacks required password/locale updates';
  END IF;

  -- SECURITY DEFINER routines must never inherit PostgreSQL's default
  -- PUBLIC EXECUTE grant. Internal helpers are callable only through their
  -- explicitly granted application command functions.
  SELECT string_agg(routine.oid::regprocedure::text, ', ' ORDER BY routine.oid::regprocedure::text)
    INTO public_definer_functions
    FROM pg_proc routine
    JOIN pg_namespace namespace ON namespace.oid = routine.pronamespace
    CROSS JOIN LATERAL aclexplode(
      coalesce(routine.proacl, acldefault('f', routine.proowner))
    ) privilege
   WHERE namespace.nspname = 'eogp'
     AND routine.prosecdef
     AND privilege.grantee = 0
     AND privilege.privilege_type = 'EXECUTE';
  IF public_definer_functions IS NOT NULL THEN
    RAISE EXCEPTION 'eogp SECURITY DEFINER functions executable by PUBLIC: %', public_definer_functions;
  END IF;

  -- Every tenant-owned table with a mandatory organization_id must
  -- enforce RLS even when accessed by its owner or a SECURITY DEFINER routine.
  -- A missing policy fails closed; missing FORCE RLS does not.
  SELECT string_agg(format('%I.%I', namespace.nspname, relation.relname), ', ' ORDER BY relation.relname)
    INTO tenant_tables_without_forced_rls
    FROM pg_class relation
    JOIN pg_namespace namespace ON namespace.oid = relation.relnamespace
    JOIN pg_attribute attribute ON attribute.attrelid = relation.oid
   WHERE namespace.nspname = 'eogp'
     AND relation.relkind = 'r'
     AND attribute.attname = 'organization_id'
     AND attribute.attnum > 0
     AND NOT attribute.attisdropped
     AND attribute.attnotnull
     -- These are deliberately global routing/queue indexes: they expose only
     -- opaque token digests, tenant IDs, or public route identifiers. Their
     -- direct grants are checked separately below; tenant data stays behind
     -- tenant-scoped SECURITY DEFINER functions.
     AND relation.relname NOT IN (
       'booking_offer_capability_lookup',
       'booking_offer_email_delivery_tenant_queue',
       'booking_offer_expiry_tenant_queue',
       'guest_invitation_capability_lookup',
       'invitation_delivery_tenant_queue',
       'public_organization_routes',
       'resend_webhook_endpoint_routes',
       'platform_admin_organizations',
       'platform_admin_access',
       'platform_admin_audit'
     )
     AND (NOT relation.relrowsecurity OR NOT relation.relforcerowsecurity);
  IF tenant_tables_without_forced_rls IS NOT NULL THEN
    RAISE EXCEPTION 'tenant-owned eogp tables lack ENABLE and FORCE ROW LEVEL SECURITY: %', tenant_tables_without_forced_rls;
  END IF;

  -- Global routing, platform control-plane and worker-queue indexes intentionally bypass tenant RLS,
  -- so they must remain inaccessible except for the worker's tenant-key-only
  -- SELECT on the three queue directories.
  IF EXISTS (
    SELECT 1
      FROM pg_class relation
      JOIN pg_namespace namespace ON namespace.oid=relation.relnamespace
      CROSS JOIN LATERAL aclexplode(
        coalesce(relation.relacl,acldefault('r',relation.relowner))
      ) privilege
      LEFT JOIN pg_roles granted_role ON granted_role.oid=privilege.grantee
     WHERE namespace.nspname='eogp'
       AND relation.relname IN (
         'booking_offer_capability_lookup',
         'booking_offer_email_delivery_tenant_queue',
         'booking_offer_expiry_tenant_queue',
         'guest_invitation_capability_lookup',
         'invitation_delivery_tenant_queue',
         'public_organization_routes',
         'resend_webhook_endpoint_routes',
       'platform_admin_organizations',
       'platform_admin_access',
       'platform_admin_audit'
       )
       AND (
         privilege.grantee=0
         OR granted_role.rolname IN ('eventor_runtime','eventor_auth')
         OR (
           granted_role.rolname='eventor_worker'
           AND NOT (
             relation.relname IN (
               'booking_offer_email_delivery_tenant_queue',
               'booking_offer_expiry_tenant_queue',
               'invitation_delivery_tenant_queue'
             )
             AND privilege.privilege_type='SELECT'
           )
         )
       )
  )
  OR NOT has_table_privilege('eventor_worker','eogp.booking_offer_email_delivery_tenant_queue','SELECT')
  OR NOT has_table_privilege('eventor_worker','eogp.booking_offer_expiry_tenant_queue','SELECT')
  OR NOT has_table_privilege('eventor_worker','eogp.invitation_delivery_tenant_queue','SELECT') THEN
    RAISE EXCEPTION 'global routing/queue index privileges exceed their explicit least-privilege contract';
  END IF;

  -- A SECURITY DEFINER routine without a pinned pg_catalog-first search path
  -- is vulnerable to object-shadowing through caller-controlled schemas.
  IF EXISTS (
    SELECT 1
      FROM pg_proc routine
      JOIN pg_namespace namespace ON namespace.oid = routine.pronamespace
     WHERE namespace.nspname = 'eogp'
       AND routine.prosecdef
       AND NOT coalesce(routine.proconfig, ARRAY[]::text[])
                    @> ARRAY['search_path=pg_catalog, eogp']
       AND NOT EXISTS (
         SELECT 1
           FROM unnest(coalesce(routine.proconfig, ARRAY[]::text[])) setting
          WHERE setting = 'search_path=pg_catalog'
       )
  ) THEN
    RAISE EXCEPTION 'an eogp SECURITY DEFINER function lacks a pinned pg_catalog-first search_path';
  END IF;

  -- Actor-bearing SECURITY DEFINER permission helpers must bind their
  -- membership argument to the transaction's trusted staff actor context.
  -- Collaboration acceptance/revocation delegate this check to the shared
  -- collaboration manager helper; preserve that delegation explicitly.
  IF position('app.actor_membership_id' IN pg_get_functiondef(
       'eogp.assert_event_command_permission(uuid,uuid,uuid,text)'::regprocedure
     )) = 0
     OR position('app.actor_membership_id' IN pg_get_functiondef(
       'eogp.assert_booking_inquiry_permission(uuid,uuid,text)'::regprocedure
     )) = 0
     OR position('app.actor_membership_id' IN pg_get_functiondef(
       'eogp.assert_collaboration_manage_permission(uuid,uuid)'::regprocedure
     )) = 0
     OR position('app.actor_membership_id' IN pg_get_functiondef(
       'eogp.assert_booking_commercial_permission(uuid,uuid,text[])'::regprocedure
     )) = 0
     OR position('app.actor_membership_id' IN pg_get_functiondef(
       'eogp.assert_booking_draft_permission(uuid,uuid,uuid,text)'::regprocedure
     )) = 0
     OR position('assert_collaboration_manage_permission' IN pg_get_functiondef(
       'eogp.accept_collaboration_grant(uuid,uuid)'::regprocedure
     )) = 0
     OR position('assert_collaboration_manage_permission' IN pg_get_functiondef(
       'eogp.revoke_collaboration_grant(uuid,uuid,text)'::regprocedure
     )) = 0 THEN
    RAISE EXCEPTION 'staff SECURITY DEFINER permission routines do not bind actor membership to trusted transaction context';
  END IF;

  IF current_setting('app.organization_id', true) IS NOT NULL
     AND current_setting('app.organization_id', true) <> '' THEN
    RAISE EXCEPTION 'authentication smoke test must not rely on tenant GUC context';
  END IF;
END;
$test$;

\echo 'Authentication role privilege smoke tests passed.'
