#!/usr/bin/env bash
set -Eeuo pipefail

: "${DATABASE_URL:?Set DATABASE_URL to a PostgreSQL 18 database connection string}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MIGRATIONS_DIR="${MIGRATIONS_DIR:-$ROOT_DIR/database/migrations}"

command -v psql >/dev/null 2>&1 || { echo "psql is required" >&2; exit 127; }
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required" >&2; exit 127; }

# The ledger is bootstrap metadata, not a normal numbered migration. All numbered
# migrations and their ledger entries are committed atomically in one transaction.
psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
BEGIN;
SET LOCAL ROLE eventor_owner;
CREATE SCHEMA IF NOT EXISTS eogp AUTHORIZATION eventor_owner;
CREATE TABLE IF NOT EXISTS eogp.schema_migrations (
    version text PRIMARY KEY,
    filename text NOT NULL UNIQUE,
    checksum_sha256 text NOT NULL CHECK (checksum_sha256 ~ '^[0-9a-f]{64}$'),
    execution_ms bigint NOT NULL CHECK (execution_ms >= 0),
    applied_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    applied_by text NOT NULL
);
COMMIT;
SQL

shopt -s nullglob
files=("$MIGRATIONS_DIR"/[0-9][0-9][0-9][0-9][0-9][0-9]_*.sql)
(("${#files[@]}" > 0)) || { echo "No migration files found in $MIGRATIONS_DIR" >&2; exit 1; }

for file in "${files[@]}"; do
  filename="$(basename "$file")"
  version="${filename%%_*}"
  [[ "$version" =~ ^[0-9]{6}$ ]] || { echo "Invalid migration filename: $filename" >&2; exit 1; }
  checksum="$(sha256sum "$file" | awk '{print $1}')"

  existing="$(psql "$DATABASE_URL" -X -At -v ON_ERROR_STOP=1 -v version="$version" \
    -c "SELECT checksum_sha256 FROM eogp.schema_migrations WHERE version = :'version'")"

  if [[ -n "$existing" ]]; then
    if [[ "$existing" != "$checksum" ]]; then
      echo "Checksum mismatch for already-applied migration $filename" >&2
      exit 1
    fi
    echo "SKIP $filename (already applied)"
    continue
  fi

  tmp="$(mktemp)"
  trap 'rm -f "$tmp"' EXIT
  {
    printf '%s\n' '\set ON_ERROR_STOP on'
    printf '%s\n' 'BEGIN;'
    printf '%s\n' 'SET LOCAL ROLE eventor_owner;'
    printf '%s\n' 'SET LOCAL search_path TO eogp, public;'
    printf '%s\n' 'SELECT pg_advisory_xact_lock(23104, 18001);'
    printf '%s\n' 'SELECT clock_timestamp()::text AS migration_started_at \gset'
    printf "\\\\i '%s'\\n" "$file"
    printf "INSERT INTO eogp.schema_migrations (version, filename, checksum_sha256, execution_ms, applied_by) VALUES ('%s','%s','%s', GREATEST(0, floor(extract(epoch FROM clock_timestamp() - :'migration_started_at'::timestamptz) * 1000)::bigint), session_user);\\n" "$version" "$filename" "$checksum"
    printf '%s\n' 'COMMIT;'
  } > "$tmp"

  echo "APPLY $filename"
  psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -f "$tmp"
  rm -f "$tmp"
  trap - EXIT
done

echo "Database migrations are up to date."
