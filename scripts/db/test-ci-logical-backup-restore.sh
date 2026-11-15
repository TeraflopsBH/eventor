#!/usr/bin/env bash
set -Eeuo pipefail

: "${EVENTOR_CI_BACKUP_RESTORE:?Set EVENTOR_CI_BACKUP_RESTORE=true to confirm this is an ephemeral CI database}"
: "${ADMIN_URL:?Set ADMIN_URL to the ephemeral PostgreSQL admin database}"
: "${ADMIN_EVENTOR_URL:?Set ADMIN_EVENTOR_URL to the ephemeral Eventor source database}"

if [[ "$EVENTOR_CI_BACKUP_RESTORE" != "true" ]]; then
  echo "Refusing backup/restore rehearsal outside explicitly enabled CI." >&2
  exit 2
fi

recovery_db="eventor_recovery"
recovery_url="${ADMIN_URL%/postgres}/${recovery_db}"
dump_file="$(mktemp -t eventor-ci-backup.XXXXXX.dump)"
cleanup() {
  rm -f "$dump_file"
  psql "$ADMIN_URL" -X -v ON_ERROR_STOP=1 \
    -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$recovery_db' AND pid <> pg_backend_pid();" \
    >/dev/null 2>&1 || true
  psql "$ADMIN_URL" -X -v ON_ERROR_STOP=1 \
    -c "DROP DATABASE IF EXISTS $recovery_db;" >/dev/null 2>&1 || true
}
trap cleanup EXIT

psql "$ADMIN_URL" -X -v ON_ERROR_STOP=1 \
  -c "DROP DATABASE IF EXISTS $recovery_db;"
psql "$ADMIN_URL" -X -v ON_ERROR_STOP=1 \
  -c "CREATE DATABASE $recovery_db OWNER eventor_owner;"

pg_dump --format=custom --no-password --file="$dump_file" "$ADMIN_EVENTOR_URL"
pg_restore --exit-on-error --no-password --dbname="$recovery_url" "$dump_file"

source_counts="$(psql "$ADMIN_EVENTOR_URL" -X -qAt -v ON_ERROR_STOP=1 -c \
  "SELECT (SELECT count(*) FROM eogp.schema_migrations)||':'||
          (SELECT count(*) FROM eogp.organizations)||':'||
          (SELECT count(*) FROM eogp.booking_drafts)||':'||
          (SELECT count(*) FROM eogp.booking_records)||':'||
          (SELECT count(*) FROM eogp.audit_events);")"
restored_counts="$(psql "$recovery_url" -X -qAt -v ON_ERROR_STOP=1 -c \
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

function_present="$(psql "$recovery_url" -X -qAt -v ON_ERROR_STOP=1 -c \
  "SELECT to_regprocedure('eogp.release_booking_draft_reservations(uuid,uuid,uuid[],uuid,text)') IS NOT NULL;")"
if [[ "$function_present" != "t" ]]; then
  echo "Restored database is missing the migration 000114 draft reservation release function." >&2
  exit 1
fi

printf 'Logical backup/restore passed. migration:organizations:drafts:bookings:audit=%s\n' "$restored_counts"
