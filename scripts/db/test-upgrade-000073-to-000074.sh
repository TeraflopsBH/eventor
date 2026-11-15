#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${MIGRATOR_URL:?MIGRATOR_URL must connect as eventor_migrator}"
: "${AUTH_URL:?AUTH_URL must connect as eventor_auth}"
MIGRATION_074="$ROOT_DIR/database/migrations/000074_booking_offer_email_worker_fixes.sql"

pre_dir="$(mktemp -d)"
post_dir="$(mktemp -d)"
middle_dir="$(mktemp -d)"
later_dir="$(mktemp -d)"
trap 'rm -rf "$pre_dir" "$post_dir" "$middle_dir" "$later_dir"' EXIT

# Rehearse the exact schema boundary immediately before the worker-fix
# migration. The migration chain through 000073 is applied first, then the
# same committed synthetic CI fixture used by the normal database suite.
for file in "$ROOT_DIR"/database/migrations/[0-9][0-9][0-9][0-9][0-9][0-9]_*.sql; do
  filename="$(basename "$file")"
  version="${filename%%_*}"
  if (( 10#${version} <= 73 )); then
    cp "$file" "$pre_dir/"
  fi
done

echo "=== Apply schema through 000073 ==="
DATABASE_URL="$MIGRATOR_URL" MIGRATIONS_DIR="$pre_dir" \
  bash "$ROOT_DIR/scripts/db/migrate.sh"

echo "=== Seed synthetic authentication identities and prior-schema data ==="
psql "$AUTH_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/seed_auth_test_users.sql"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/migration_smoke.sql"

count_snapshot() {
  psql "$MIGRATOR_URL" -X -qAt -v ON_ERROR_STOP=1 <<'SQL'
SET ROLE eventor_owner;
SELECT
  (SELECT count(*) FROM eogp.organizations) || ',' ||
  (SELECT count(*) FROM eogp.organization_memberships) || ',' ||
  (SELECT count(*) FROM eogp.venues) || ',' ||
  (SELECT count(*) FROM eogp.booking_drafts) || ',' ||
  (SELECT count(*) FROM eogp.booking_offers) || ',' ||
  (SELECT count(*) FROM eogp.booking_offer_email_deliveries);
SQL
}

before="$(count_snapshot)"
echo "Pre-upgrade tenant/business row counts: $before"

echo "=== Apply migration 000074 on the populated 000073 schema ==="
cp "$MIGRATION_074" "$post_dir/"
DATABASE_URL="$MIGRATOR_URL" MIGRATIONS_DIR="$post_dir" \
  bash "$ROOT_DIR/scripts/db/migrate.sh"

after="$(count_snapshot)"
echo "Post-upgrade tenant/business row counts: $after"
if [[ "$before" != "$after" ]]; then
  echo "Migration 000074 unexpectedly changed existing tenant/business row counts" >&2
  exit 1
fi

echo "=== Verify migration ledger and upgraded worker function contract ==="
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
SET ROLE eventor_owner;
DO $upgrade_check$
DECLARE
  v_count integer;
  v_result text;
BEGIN
  SELECT count(*) INTO v_count FROM eogp.schema_migrations;
  IF v_count <> 74
     OR NOT EXISTS (SELECT 1 FROM eogp.schema_migrations WHERE version='000073')
     OR NOT EXISTS (SELECT 1 FROM eogp.schema_migrations WHERE version='000074') THEN
    RAISE EXCEPTION 'expected contiguous migration ledger through 000074; found % rows',v_count;
  END IF;

  v_result:=pg_get_function_result(
    'eogp.claim_booking_offer_email_delivery(uuid)'::regprocedure
  );
  IF position('currency text' IN v_result)=0 THEN
    RAISE EXCEPTION 'upgraded claim function has unexpected result contract: %',v_result;
  END IF;
END;
$upgrade_check$;
SQL

echo "=== Apply the published 000075 and 000076 migrations unchanged ==="
cp "$ROOT_DIR"/database/migrations/000075_*.sql "$middle_dir/"
cp "$ROOT_DIR"/database/migrations/000076_*.sql "$middle_dir/"
DATABASE_URL="$MIGRATOR_URL" MIGRATIONS_DIR="$middle_dir" \
  bash "$ROOT_DIR/scripts/db/migrate.sh"

echo "=== Seed a pre-000077 invitation link with its legacy encrypted capability ==="
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/guest_invitation_capability_migration_fixture.sql"

echo "=== Apply forward migrations from 000077 onward ==="
for file in "$ROOT_DIR"/database/migrations/[0-9][0-9][0-9][0-9][0-9][0-9]_*.sql; do
  filename="$(basename "$file")"
  version="${filename%%_*}"
  if (( 10#${version} >= 77 )); then
    cp "$file" "$later_dir/"
  fi
done
DATABASE_URL="$MIGRATOR_URL" MIGRATIONS_DIR="$later_dir" \
  bash "$ROOT_DIR/scripts/db/migrate.sh"

echo "=== Verify the 000076 -> 000077 capability-envelope data migration ==="
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/guest_invitation_forward_migration_smoke.sql"

echo "Populated schema upgrade rehearsals 000073 -> 000074 and 000076 -> 000077 passed."
