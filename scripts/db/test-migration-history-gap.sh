#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${ADMIN_URL:?ADMIN_URL must connect as PostgreSQL administrator}"
: "${MIGRATOR_URL:?MIGRATOR_URL must connect as eventor_migrator}"

guard_db="eventor_migration_gap_guard"
admin_guard_url="${ADMIN_URL%/postgres}/${guard_db}"
migrator_guard_url="${MIGRATOR_URL%/eventor}/${guard_db}"

psql "$ADMIN_URL" -X -v ON_ERROR_STOP=1 \
  -c "CREATE DATABASE ${guard_db} OWNER eventor_owner"

psql "$admin_guard_url" -X -v ON_ERROR_STOP=1 <<'SQL'
CREATE SCHEMA eogp AUTHORIZATION eventor_owner;
SET ROLE eventor_owner;
CREATE TABLE eogp.schema_migrations (
  version text PRIMARY KEY,
  filename text NOT NULL UNIQUE,
  checksum_sha256 text NOT NULL CHECK (checksum_sha256 ~ '^[0-9a-f]{64}$'),
  execution_ms bigint NOT NULL CHECK (execution_ms >= 0),
  applied_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  applied_by text NOT NULL
);
SQL

for version in 000075 000076; do
  file="$(find "$ROOT_DIR/database/migrations" -maxdepth 1 -name "${version}_*.sql" -print -quit)"
  [[ -n "$file" ]] || { echo "Missing fixture migration $version" >&2; exit 1; }
  filename="$(basename "$file")"
  checksum="$(sha256sum "$file" | awk '{print $1}')"
  psql "$admin_guard_url" -X -v ON_ERROR_STOP=1 \
    -v version="$version" -v filename="$filename" -v checksum="$checksum" <<'SQL'
SET ROLE eventor_owner;
INSERT INTO eogp.schema_migrations(version,filename,checksum_sha256,execution_ms,applied_by)
VALUES (:'version',:'filename',:'checksum',0,'migration-gap-fixture');
SQL
done

output="$(mktemp)"
trap 'rm -f "$output"' EXIT
if DATABASE_URL="$migrator_guard_url" bash "$ROOT_DIR/scripts/db/migrate.sh" >"$output" 2>&1; then
  cat "$output"
  echo "Migration runner unexpectedly accepted a ledger with 000075-000076 but no earlier migrations." >&2
  exit 1
fi
if ! grep -Fq "Migration history gap: 000001_" "$output"; then
  cat "$output"
  echo "Migration runner failed for an unexpected reason; expected the history-gap guard." >&2
  exit 1
fi
echo "Migration runner correctly rejected an incomplete historical ledger."
