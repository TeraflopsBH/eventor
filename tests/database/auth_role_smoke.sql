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

  IF NOT has_table_privilege(current_user, 'eogp.user_sessions', 'SELECT')
     OR NOT has_table_privilege(current_user, 'eogp.user_sessions', 'INSERT')
     OR NOT has_table_privilege(current_user, 'eogp.user_sessions', 'UPDATE')
     OR has_table_privilege(current_user, 'eogp.user_sessions', 'DELETE')
     OR has_table_privilege('eventor_runtime', 'eogp.user_sessions', 'SELECT')
     OR has_table_privilege('eventor_worker', 'eogp.user_sessions', 'SELECT') THEN
    RAISE EXCEPTION 'session table privileges are not restricted to the authentication service';
  END IF;

  IF NOT has_table_privilege(current_user, 'eogp.auth_login_attempts', 'SELECT')
     OR NOT has_table_privilege(current_user, 'eogp.auth_login_attempts', 'INSERT')
     OR NOT has_table_privilege(current_user, 'eogp.auth_login_attempts', 'UPDATE')
     OR has_table_privilege(current_user, 'eogp.auth_login_attempts', 'DELETE') THEN
    RAISE EXCEPTION 'authentication rate-limit table privileges are incorrect';
  END IF;

  IF current_setting('app.organization_id', true) IS NOT NULL
     AND current_setting('app.organization_id', true) <> '' THEN
    RAISE EXCEPTION 'authentication smoke test must not rely on tenant GUC context';
  END IF;
END;
$test$;

\echo 'Authentication role privilege smoke tests passed.'
