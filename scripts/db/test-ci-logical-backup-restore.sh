#!/usr/bin/env bash
set -Eeuo pipefail

: "${EVENTOR_CI_BACKUP_RESTORE:?Set EVENTOR_CI_BACKUP_RESTORE=true to confirm this is an ephemeral CI database}"
: "${ADMIN_URL:?Set ADMIN_URL to the ephemeral PostgreSQL admin database}"
: "${ADMIN_EVENTOR_URL:?Set ADMIN_EVENTOR_URL to the ephemeral Eventor source database}"

if [[ "$EVENTOR_CI_BACKUP_RESTORE" != "true" ]]; then
  echo "Refusing backup/restore rehearsal outside explicitly enabled CI." >&2
  exit 2
fi

# Use the PostgreSQL 18 client that matches the CI service, even when the
# runner image also ships an older distro-default client.
pg_bin_dir="${EVENTOR_PG_BIN_DIR:-/usr/lib/postgresql/18/bin}"
psql_bin="$pg_bin_dir/psql"
pg_dump_bin="$pg_bin_dir/pg_dump"
pg_restore_bin="$pg_bin_dir/pg_restore"
for binary in "$psql_bin" "$pg_dump_bin" "$pg_restore_bin"; do
  if [[ ! -x "$binary" ]]; then
    echo "Required PostgreSQL 18 client binary is missing: $binary" >&2
    exit 2
  fi
done
"$pg_dump_bin" --version
"$pg_restore_bin" --version

recovery_db="eventor_recovery"
recovery_url="${ADMIN_URL%/postgres}/${recovery_db}"
dump_file="$(mktemp -t eventor-ci-backup.XXXXXX.dump)"
cleanup() {
  rm -f "$dump_file"
  $psql_bin "$ADMIN_URL" -X -v ON_ERROR_STOP=1 \
    -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$recovery_db' AND pid <> pg_backend_pid();" \
    >/dev/null 2>&1 || true
  $psql_bin "$ADMIN_URL" -X -v ON_ERROR_STOP=1 \
    -c "DROP DATABASE IF EXISTS $recovery_db;" >/dev/null 2>&1 || true
}
trap cleanup EXIT

$psql_bin "$ADMIN_URL" -X -v ON_ERROR_STOP=1 \
  -c "DROP DATABASE IF EXISTS $recovery_db;"
$psql_bin "$ADMIN_URL" -X -v ON_ERROR_STOP=1 \
  -c "CREATE DATABASE $recovery_db OWNER eventor_owner;"

$pg_dump_bin --format=custom --no-password --file="$dump_file" "$ADMIN_EVENTOR_URL"
$pg_restore_bin --exit-on-error --no-password --dbname="$recovery_url" "$dump_file"

source_counts="$($psql_bin "$ADMIN_EVENTOR_URL" -X -qAt -v ON_ERROR_STOP=1 -c \
  "SELECT (SELECT count(*) FROM eogp.schema_migrations)||':'||
          (SELECT count(*) FROM eogp.organizations)||':'||
          (SELECT count(*) FROM eogp.booking_drafts)||':'||
          (SELECT count(*) FROM eogp.booking_records)||':'||
          (SELECT count(*) FROM eogp.audit_events);")"
restored_counts="$($psql_bin "$recovery_url" -X -qAt -v ON_ERROR_STOP=1 -c \
  "SELECT (SELECT count(*) FROM eogp.schema_migrations)||':'||
          (SELECT count(*) FROM eogp.organizations)||':'||
          (SELECT count(*) FROM eogp.booking_drafts)||':'||
          (SELECT count(*) FROM eogp.booking_records)||':'||
          (SELECT count(*) FROM eogp.audit_events);")"

if [[ "$source_counts" != "$restored_counts" ]]; then
  printf 'Backup/restore row-count mismatch. source=%s restored=%s\n' \
    "$source_counts" "$restored_counts" >&2
  exit 1
fi

function_present="$($psql_bin "$recovery_url" -X -qAt -v ON_ERROR_STOP=1 -c \
  "SELECT to_regprocedure('eogp.release_booking_draft_reservations(uuid,uuid,uuid[],uuid,text)') IS NOT NULL;")"
if [[ "$function_present" != "t" ]]; then
  echo "Restored database is missing the migration 000114 draft reservation release function." >&2
  exit 1
fi

printf 'Logical backup/restore passed. migration:organizations:drafts:bookings:audit=%s\n' "$restored_counts"
