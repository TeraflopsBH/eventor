\set ON_ERROR_STOP on

-- Run as eventor_auth with no tenant GUC set.
DO $test$
DECLARE
  organization_count integer;
  membership_count integer;
  user_count integer;
  can_bypass boolean;
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
  IF EXISTS (
    SELECT 1
      FROM pg_proc routine
      JOIN pg_namespace namespace ON namespace.oid = routine.pronamespace
      CROSS JOIN LATERAL aclexplode(
        coalesce(routine.proacl, acldefault('f', routine.proowner))
      ) privilege
     WHERE namespace.nspname = 'eogp'
       AND routine.prosecdef
       AND privilege.grantee = 0
       AND privilege.privilege_type = 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'an eogp SECURITY DEFINER function is executable by PUBLIC';
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

  IF current_setting('app.organization_id', true) IS NOT NULL
     AND current_setting('app.organization_id', true) <> '' THEN
    RAISE EXCEPTION 'authentication smoke test must not rely on tenant GUC context';
  END IF;
END;
$test$;

\echo 'Authentication role privilege smoke tests passed.'
