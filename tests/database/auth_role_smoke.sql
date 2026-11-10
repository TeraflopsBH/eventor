\set ON_ERROR_STOP on

-- Run as eventor_auth with no tenant GUC set.
DO $test$
DECLARE
  organization_count integer;
  membership_count integer;
  user_count integer;
  can_bypass boolean;
BEGIN
  SELECT count(*) INTO organization_count FROM eogp.organizations;
  SELECT count(*) INTO membership_count FROM eogp.organization_memberships;
  SELECT count(*) INTO user_count FROM eogp.users WHERE email = 'ci-extended-a@example.invalid';

  IF organization_count <> 3 OR membership_count <> 3 OR user_count <> 1 THEN
    RAISE EXCEPTION
      'auth role lookup failed: organizations %, memberships %, matching users %',
      organization_count, membership_count, user_count;
  END IF;

  SELECT rolbypassrls INTO can_bypass FROM pg_roles WHERE rolname = current_user;
  IF can_bypass IS DISTINCT FROM false THEN
    RAISE EXCEPTION 'authentication role must not have BYPASSRLS';
  END IF;

  IF has_table_privilege(current_user, 'eogp.venues', 'SELECT')
     OR has_table_privilege(current_user, 'eogp.organization_memberships', 'UPDATE')
     OR has_column_privilege(current_user, 'eogp.users', 'password_hash', 'UPDATE') THEN
    RAISE EXCEPTION 'authentication role has excessive business-table or identity-write privileges';
  END IF;

  IF NOT has_column_privilege(current_user, 'eogp.users', 'password_hash', 'SELECT')
     OR NOT has_column_privilege(current_user, 'eogp.users', 'email', 'SELECT') THEN
    RAISE EXCEPTION 'authentication role lacks required credential lookup privileges';
  END IF;
END;
$test$;

\echo 'Authentication role privilege smoke tests passed.'
