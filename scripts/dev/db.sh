#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="$ROOT_DIR/.eventor-dev"
ENV_FILE="$STATE_DIR/dev.env"
COMPOSE_FILE="$ROOT_DIR/compose.dev.yaml"
PROJECT_NAME="eventor-dev"

generate_environment() {
  mkdir -p "$STATE_DIR"
  if [[ -f "$ENV_FILE" ]]; then
    return
  fi
  local password
  password="$(openssl rand -hex 24)"
  umask 077
  {
    printf 'EVENTOR_DEV_POSTGRES_PASSWORD=%s\n' "$password"
    printf 'EVENTOR_DEV_POSTGRES_PORT=55432\n'
    printf 'EVENTOR_RUNTIME_DATABASE_URL=postgresql://eventor_runtime:%s@127.0.0.1:55432/eventor\n' "$password"
    printf 'EVENTOR_AUTH_DATABASE_URL=postgresql://eventor_auth:%s@127.0.0.1:55432/eventor\n' "$password"
    printf 'EVENTOR_WORKER_DATABASE_URL=postgresql://eventor_worker:%s@127.0.0.1:55432/eventor\n' "$password"
    printf 'EVENTOR_MIGRATOR_DATABASE_URL=postgresql://eventor_migrator:%s@127.0.0.1:55432/eventor\n' "$password"
    printf 'EVENTOR_ALLOWED_ORIGINS=http://127.0.0.1:5173,http://localhost:5173\n'
    for key_name in AUTH_FINGERPRINT PUBLIC_INQUIRY_FINGERPRINT FIELD_ENCRYPTION CONTACT_ENCRYPTION DELIVERY_CREDENTIALS BOOKING_CAPABILITY; do
      printf 'EVENTOR_%s_KEY=%s\n' "$key_name" "$(openssl rand -base64 32 | tr -d '\n')"
    done
    printf 'HOST=127.0.0.1\nPORT=8080\n'
  } > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  printf 'Generated local-only credentials in %s.\n' "$ENV_FILE"
}

load_environment() {
  generate_environment
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
}

compose() {
  docker compose --project-name "$PROJECT_NAME" --env-file "$ENV_FILE" --file "$COMPOSE_FILE" "$@"
}

initialize_database() {
  if ! compose exec -T postgres psql -U postgres -d postgres -Atqc \
    "SELECT 1 FROM pg_database WHERE datname='eventor'" | grep -qx 1; then
    compose exec -T postgres createdb -U postgres eventor
  fi
  compose exec -T postgres psql -U postgres -d eventor -v ON_ERROR_STOP=1 \
    -v database_name=eventor -f /repo/scripts/db/bootstrap-roles.sql
  compose exec -T postgres psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
    -c "ALTER DATABASE eventor OWNER TO eventor_owner"
  compose exec -T -e EVENTOR_DEV_DB_PASSWORD="$EVENTOR_DEV_POSTGRES_PASSWORD" postgres \
    psql -U postgres -d postgres -v ON_ERROR_STOP=1 <<'SQL'
\getenv role_password EVENTOR_DEV_DB_PASSWORD
SELECT format('ALTER ROLE %I PASSWORD %L', role_name, :'role_password')
FROM unnest(ARRAY['eventor_migrator','eventor_runtime','eventor_worker','eventor_auth']) AS role_name
\gexec
SQL
  local_manifest=""
  while IFS= read -r migration_file; do
    migration_name="$(basename "$migration_file")"
    migration_version="${migration_name%%_*}"
    migration_checksum="$(sha256sum "$migration_file" | awk '{print $1}')"
    local_manifest+="${migration_version} ${migration_checksum}"$'\n'
  done < <(find "$ROOT_DIR/database/migrations" -maxdepth 1 -type f \
    -name '[0-9][0-9][0-9][0-9][0-9][0-9]_*.sql' | sort)
  local_manifest="${local_manifest%$'\n'}"
  database_manifest="$(compose exec -T postgres psql -U postgres -d eventor -AtF ' ' \
    -c 'SELECT version,checksum_sha256 FROM eogp.schema_migrations ORDER BY version' 2>/dev/null || true)"
  if [[ "$database_manifest" != "$local_manifest" ]]; then
    compose exec -T \
      -e DATABASE_URL="postgresql://eventor_migrator:${EVENTOR_DEV_POSTGRES_PASSWORD}@127.0.0.1:5432/eventor" \
      postgres bash /repo/scripts/db/migrate.sh
  fi
}

command_name="${1:-status}"
case "$command_name" in
  up)
    load_environment
    mkdir -p "$STATE_DIR/logs"
    database_log="$STATE_DIR/logs/db-up.log"
    if ! compose up --detach --wait postgres >"$database_log" 2>&1; then
      printf 'PostgreSQL startup failed (log: %s).\n' "$database_log" >&2
      tail -n 80 "$database_log" >&2
      exit 1
    fi
    if ! initialize_database >>"$database_log" 2>&1; then
      printf 'Database initialization failed (log: %s).\n' "$database_log" >&2
      tail -n 80 "$database_log" >&2
      exit 1
    fi
    printf 'PostgreSQL 18.6 is ready on 127.0.0.1:%s.\n' "$EVENTOR_DEV_POSTGRES_PORT"
    ;;
  status)
    if [[ ! -f "$ENV_FILE" ]]; then
      printf 'Development database has not been initialized.\n'
      exit 0
    fi
    load_environment
    compose ps
    if compose exec -T postgres pg_isready -U postgres -d eventor >/dev/null 2>&1; then
      migration="$(compose exec -T postgres psql -U postgres -d eventor -Atqc "SELECT coalesce(max(version),'none') FROM eogp.schema_migrations" 2>/dev/null || printf 'unavailable')"
      printf 'Latest migration: %s\n' "$migration"
    fi
    ;;
  down)
    [[ -f "$ENV_FILE" ]] || { printf 'Development database is already stopped.\n'; exit 0; }
    load_environment
    compose stop postgres
    ;;
  psql)
    load_environment
    role="${2:-eventor_migrator}"
    case "$role" in eventor_migrator|eventor_runtime|eventor_worker|eventor_auth|postgres) ;; *) printf 'Unsupported role: %s\n' "$role" >&2; exit 2 ;; esac
    compose exec postgres psql -U "$role" -d eventor
    ;;
  file)
    load_environment
    role="${2:-}"
    relative_file="${3:-}"
    case "$role" in eventor_migrator|eventor_runtime|eventor_worker|eventor_auth|postgres) ;; *) printf 'Usage: %s file ROLE REPOSITORY_RELATIVE_SQL\n' "$0" >&2; exit 2 ;; esac
    [[ -n "$relative_file" && "$relative_file" != /* && "$relative_file" != *..* && -f "$ROOT_DIR/$relative_file" ]] \
      || { printf 'SQL file must be a repository-relative path.\n' >&2; exit 2; }
    compose exec -T postgres psql -U "$role" -d eventor -v ON_ERROR_STOP=1 -f "/repo/$relative_file"
    ;;
  env)
    load_environment
    printf '%s\n' "$ENV_FILE"
    ;;
  reset)
    [[ "${2:-}" == "--yes" ]] || { printf 'Reset deletes only the eventor-dev PostgreSQL volume. Re-run with: %s reset --yes\n' "$0" >&2; exit 2; }
    load_environment
    compose down --volumes
    printf 'Removed the disposable eventor-dev PostgreSQL volume. Local credentials were retained.\n'
    ;;
  *)
    printf 'Usage: %s {up|status|down|psql [ROLE]|file ROLE SQL_FILE|env|reset --yes}\n' "$0" >&2
    exit 2
    ;;
esac
