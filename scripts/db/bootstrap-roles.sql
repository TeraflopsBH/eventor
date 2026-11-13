\set ON_ERROR_STOP on

-- Run as a database administrator while connected to the Eventor database.
-- The database name is supplied by the caller: psql -v database_name=eventor -f this_file.
DO $roles$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'eventor_owner') THEN
    EXECUTE 'CREATE ROLE eventor_owner NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'eventor_migrator') THEN
    EXECUTE 'CREATE ROLE eventor_migrator LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'eventor_runtime') THEN
    EXECUTE 'CREATE ROLE eventor_runtime LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'eventor_worker') THEN
    EXECUTE 'CREATE ROLE eventor_worker LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'eventor_auth') THEN
    EXECUTE 'CREATE ROLE eventor_auth LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS';
  END IF;
END;
$roles$;

-- Reconcile existing roles as well as newly created ones. Bootstrap is run by
-- an administrator, so it must not silently preserve unsafe attributes left by
-- an earlier manual or incomplete role setup.
ALTER ROLE eventor_owner
  NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
ALTER ROLE eventor_migrator
  LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
ALTER ROLE eventor_runtime
  LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
ALTER ROLE eventor_worker
  LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;
ALTER ROLE eventor_auth
  LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS;

-- Reconcile memberships too: NOINHERIT does not prevent SET ROLE through an
-- unexpected membership. Only the migrator may SET ROLE to the non-login owner.
DO $memberships$
DECLARE
  membership record;
BEGIN
  FOR membership IN
    SELECT granted_role.rolname AS granted_role_name,
           member_role.rolname AS member_role_name
      FROM pg_auth_members AS role_membership
      JOIN pg_roles AS granted_role ON granted_role.oid = role_membership.roleid
      JOIN pg_roles AS member_role ON member_role.oid = role_membership.member
     WHERE member_role.rolname IN (
       'eventor_owner','eventor_migrator','eventor_runtime','eventor_worker','eventor_auth'
     )
  LOOP
    EXECUTE format(
      'REVOKE %I FROM %I',
      membership.granted_role_name,
      membership.member_role_name
    );
  END LOOP;
END;
$memberships$;

GRANT eventor_owner TO eventor_migrator;
GRANT CONNECT, CREATE ON DATABASE :"database_name" TO eventor_owner;
GRANT CONNECT ON DATABASE :"database_name" TO eventor_migrator, eventor_runtime, eventor_worker, eventor_auth;

-- No passwords are embedded in this repository. Set LOGIN-role passwords through
-- the deployment secret manager or an interactive \password command.
