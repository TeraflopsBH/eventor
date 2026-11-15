#!/usr/bin/env bash
set -Eeuo pipefail

: "${ADMIN_URL:?ADMIN_URL is required}"
: "${UPGRADE_MIGRATOR_URL:?UPGRADE_MIGRATOR_URL is required}"

psql "$ADMIN_URL" -X -v ON_ERROR_STOP=1 -c "CREATE DATABASE eventor_upgrade OWNER eventor_owner;"
mkdir -p /tmp/eventor-migrations-v72
find database/migrations -maxdepth 1 -type f -name '*.sql' ! -name '000073_*' ! -name '000074_*' -print0 \
  | sort -z | xargs -0 -r cp -t /tmp/eventor-migrations-v72
test "$(find /tmp/eventor-migrations-v72 -maxdepth 1 -type f -name '*.sql' | wc -l)" -eq 72

DATABASE_URL="$UPGRADE_MIGRATOR_URL" MIGRATIONS_DIR=/tmp/eventor-migrations-v72 bash scripts/db/migrate.sh
psql "$UPGRADE_MIGRATOR_URL" -X -v ON_ERROR_STOP=1 -f tests/database/migration_smoke.sql

pre_migration_count="$(psql "$UPGRADE_MIGRATOR_URL" -X -qAt -v ON_ERROR_STOP=1 \
  -c "SET ROLE eventor_owner; SELECT count(*) FROM eogp.schema_migrations;")"
test "$pre_migration_count" = "72"

pre_data_counts="$(psql "$UPGRADE_MIGRATOR_URL" -X -qAt -v ON_ERROR_STOP=1 \
  -c "SET ROLE eventor_owner; SELECT (SELECT count(*) FROM eogp.organizations)||':'||(SELECT count(*) FROM eogp.venues)||':'||(SELECT count(*) FROM eogp.booking_resource_lines);")"
test -n "$pre_data_counts"

DATABASE_URL="$UPGRADE_MIGRATOR_URL" bash scripts/db/migrate.sh
post_data_counts="$(psql "$UPGRADE_MIGRATOR_URL" -X -qAt -v ON_ERROR_STOP=1 \
  -c "SET ROLE eventor_owner; SELECT (SELECT count(*) FROM eogp.organizations)||':'||(SELECT count(*) FROM eogp.venues)||':'||(SELECT count(*) FROM eogp.booking_resource_lines);")"
test "$pre_data_counts" = "$post_data_counts"

psql "$UPGRADE_MIGRATOR_URL" -X -v ON_ERROR_STOP=1 -c "SET ROLE eventor_owner; DO \$verify\$ BEGIN IF (SELECT count(*) FROM eogp.schema_migrations) <> 74 THEN RAISE EXCEPTION 'expected 74 migrations after upgrade'; END IF; IF to_regprocedure('eogp.confirm_booking_from_offer(uuid,uuid,uuid,text)') IS NULL THEN RAISE EXCEPTION 'migration 73 booking confirmation function is missing'; END IF; IF to_regprocedure('eogp.claim_booking_offer_email_delivery(uuid)') IS NULL THEN RAISE EXCEPTION 'migration 74 booking offer email worker claim function is missing'; END IF; END \$verify\$;"

echo "Migration 72 -> 74 preserved existing data counts: $post_data_counts"
