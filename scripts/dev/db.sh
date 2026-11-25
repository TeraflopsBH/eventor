#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="${EVENTOR_DEV_STATE_DIR:-$ROOT_DIR/.eventor-dev}"
ENV_FILE="$STATE_DIR/dev.env"
COMPOSE_FILE="$ROOT_DIR/compose.dev.yaml"
PROJECT_NAME="${EVENTOR_DEV_PROJECT_NAME:-eventor-dev}"
[[ "$PROJECT_NAME" =~ ^[a-z0-9][a-z0-9_-]*$ ]] || { printf 'Use a lowercase Compose project name.\n' >&2; exit 2; }

generate_environment() {
  mkdir -p "$STATE_DIR"
  if [[ -f "$ENV_FILE" ]]; then
    return
  fi
  local password pg_port
  pg_port="${EVENTOR_DEV_POSTGRES_PORT:-55432}"
  if ! [[ "$pg_port" =~ ^[0-9]{1,5}$ ]] || (( 10#$pg_port < 1 || 10#$pg_port > 65535 )); then
    printf 'Choose a TCP port between 1 and 65535.\n' >&2; return 2
  fi
  pg_port="$((10#$pg_port))"
  password="$(openssl rand -hex 24)"
  umask 077
  {
    printf 'EVENTOR_DEV_POSTGRES_PASSWORD=%s\n' "$password"
    printf 'EVENTOR_DEV_POSTGRES_PORT=%s\n' "$pg_port"
    printf 'EVENTOR_RUNTIME_DATABASE_URL=postgresql://eventor_runtime:%s@127.0.0.1:%s/eventor\n' "$password" "$pg_port"
    printf 'EVENTOR_AUTH_DATABASE_URL=postgresql://eventor_auth:%s@127.0.0.1:%s/eventor\n' "$password" "$pg_port"
    printf 'EVENTOR_WORKER_DATABASE_URL=postgresql://eventor_worker:%s@127.0.0.1:%s/eventor\n' "$password" "$pg_port"
    printf 'EVENTOR_MIGRATOR_DATABASE_URL=postgresql://eventor_migrator:%s@127.0.0.1:%s/eventor\n' "$password" "$pg_port"
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

verify_persistent_container() {
  local container_id="$1" auto_remove storage
  auto_remove="$(docker inspect --format '{{.HostConfig.AutoRemove}}' "$container_id")"
  storage="$(docker inspect --format '{{range .Mounts}}{{if eq .Destination "/var/lib/postgresql"}}{{.Type}}:{{.Name}}{{end}}{{end}}' "$container_id")"
  if [[ "$auto_remove" != false || "$storage" != "volume:${PROJECT_NAME}_eventor-dev-postgres" ]]; then
    printf 'Refusing shutdown: PostgreSQL is not using the expected persistent named volume. Back up and investigate before stopping it.\n' >&2
    return 1
  fi
}

backup_database() {
  local backup_file
  umask 077
  if ! mkdir -p "$STATE_DIR/backups" || ! chmod 700 "$STATE_DIR/backups"; then
    printf 'Backup directory is unavailable; PostgreSQL has not been stopped.\n' >&2
    return 1
  fi
  backup_file="$(mktemp "$STATE_DIR/backups/${PROJECT_NAME}-$(date -u +%Y%m%dT%H%M%SZ).XXXXXX.dump")"
  if ! compose exec -T postgres pg_dump -U postgres -d eventor --format=custom > "$backup_file"; then
    rm -f "$backup_file"
    printf 'Database backup failed; PostgreSQL has not been stopped.\n' >&2
    return 1
  fi
  if ! compose exec -T postgres pg_restore --file=/dev/null < "$backup_file" >/dev/null; then
    rm -f "$backup_file"
    printf 'Backup verification failed; PostgreSQL has not been stopped.\n' >&2
    return 1
  fi
  printf 'Verified local backup: %s\n' "$backup_file"
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
    container_id="$(compose ps --status running -q postgres)"
    [[ -n "$container_id" ]] || { printf 'Development database is not running.\n'; exit 0; }
    verify_persistent_container "$container_id"
    backup_database
    compose stop postgres
    printf 'Stopped PostgreSQL; named volume %s_eventor-dev-postgres is retained.\n' "$PROJECT_NAME"
    ;;
  backup)
    [[ -f "$ENV_FILE" ]] || { printf 'Development database has not been initialized.\n' >&2; exit 2; }
    load_environment
    backup_database
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
    [[ "${2:-}" == "--yes" ]] || { printf 'Reset deletes only the %s PostgreSQL volume. Re-run with: %s reset --yes\n' "$PROJECT_NAME" "$0" >&2; exit 2; }
    load_environment
    compose down --volumes
    printf 'Removed the selected development PostgreSQL volume. Local credentials were retained.\n'
    ;;
  *)
    printf 'Usage: %s {up|status|backup|down|psql [ROLE]|file ROLE SQL_FILE|env|reset --yes}\n' "$0" >&2
    exit 2
    ;;
esac
