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
END;
$roles$;

GRANT eventor_owner TO eventor_migrator;
GRANT CONNECT, CREATE ON DATABASE :"database_name" TO eventor_owner;
GRANT CONNECT ON DATABASE :"database_name" TO eventor_migrator, eventor_runtime, eventor_worker;

-- No passwords are embedded in this repository. Set LOGIN-role passwords through
-- the deployment secret manager or an interactive \password command.
