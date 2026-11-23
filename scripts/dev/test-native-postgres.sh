#!/usr/bin/env bash
# Run isolated database regressions with installed PostgreSQL 18 binaries.
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for program in postgres initdb pg_ctl psql createdb; do
  command -v "$program" >/dev/null || {
    printf 'PostgreSQL 18 binaries must be on PATH. Missing %s.\n' "$program" >&2
    exit 1
  }
done
version="$(postgres --version)"
[[ "$version" == *" 18."* ]] || {
  printf 'PostgreSQL 18 is required. Found %s.\n' "$version" >&2
  exit 1
}

umask 077
mkdir -p "$ROOT_DIR/.eventor-dev/logs"
log_dir="$(mktemp -d "$ROOT_DIR/.eventor-dev/logs/native-postgres.XXXXXX")"
cluster_dir="$(mktemp -d /tmp/eventor-postgres.XXXXXX)"

cleanup() {
  if [[ -f "$cluster_dir/data/postmaster.pid" ]]; then
    pg_ctl -D "$cluster_dir/data" -m fast -w stop >>"$log_dir/server.log" 2>&1 || {
      printf 'Could not stop temporary cluster %s. Logs: %s\n' "$cluster_dir" "$log_dir" >&2
      return 1
    }
  fi
  rm -rf -- "$cluster_dir"
}
trap cleanup EXIT

run_check() {
  local label="$1" filename="$2"
  shift 2
  if "$@" >"$log_dir/$filename" 2>&1; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s. Logs: %s\n' "$label" "$log_dir/$filename" >&2
    tail -n 40 "$log_dir/$filename" >&2
    return 1
  fi
}

run_check "Initialize temporary PostgreSQL" init.log \
  initdb -D "$cluster_dir/data" -U postgres --encoding=UTF8 --auth-local=trust --auth-host=scram-sha-256
mkdir "$cluster_dir/socket"
run_check "Start socket-only PostgreSQL" start.log \
  pg_ctl -D "$cluster_dir/data" -l "$log_dir/server.log" \
    -o "-h '' -p 5432 -k $cluster_dir/socket" -w start

export PGHOST="$cluster_dir/socket" PGPORT=5432
unset PGHOSTADDR PGPASSWORD PGSERVICE PGSERVICEFILE PGOPTIONS
export ADMIN_URL=postgresql://postgres@/postgres
export MIGRATOR_URL=postgresql://eventor_migrator@/eventor
export AUTH_URL=postgresql://eventor_auth@/eventor
export DATABASE_URL_RUNTIME=postgresql://eventor_runtime@/eventor
export WORKER_URL=postgresql://eventor_worker@/eventor

cd "$ROOT_DIR"
run_check "Create isolated test database" create-db.log createdb -U postgres eventor
run_check "Bootstrap least-privilege database roles" roles.log \
  psql "$ADMIN_URL" -X -v ON_ERROR_STOP=1 -v database_name=eventor -f scripts/db/bootstrap-roles.sql
psql "$ADMIN_URL" -X -v ON_ERROR_STOP=1 -q -c 'ALTER DATABASE eventor OWNER TO eventor_owner'
run_check "Rehearse populated schema upgrades" upgrades.log \
  bash scripts/db/test-upgrade-000073-to-000074.sh
run_check "Verify database constraints, RLS and concurrency" database.log \
  bash scripts/db/test-migrations.sh
run_check "Verify authentication-role privileges" auth-role.log \
  psql "$AUTH_URL" -X -v ON_ERROR_STOP=1 -f tests/database/auth_role_smoke.sql
printf 'Logs: %s\n' "$log_dir"
