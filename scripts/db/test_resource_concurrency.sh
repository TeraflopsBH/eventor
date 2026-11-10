#!/usr/bin/env bash
set -Eeuo pipefail

: "\${DATABASE_URL:?Set DATABASE_URL to the migrated PostgreSQL 18 database}"
org="11111111-1111-4111-8111-111111111111"
pool="41000000-0000-4000-8000-000000000002"
draft_revision="51000000-0000-4000-8000-000000000001"
resource_line="52000000-0000-4000-8000-000000000002"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

run_reservation() {
  local key="$1"
  psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -qAt >"$tmp/$key.log" 2>&1 <<SQL
BEGIN;
SET LOCAL ROLE eventor_owner;
SET LOCAL search_path TO eogp, public;
SELECT set_config('app.organization_id', '$org', true);
SELECT eogp.reserve_pooled_resource(
  '$org','$pool','$draft_revision',NULL,'$resource_line',
  '2027-02-01 10:00+00','2027-02-01 11:00+00',2,
  '2027-01-31 15:00+00','$key'
);
COMMIT;
SQL
}

run_reservation ci-concurrent-a-0001 &
pid_a=$!
run_reservation ci-concurrent-b-0001 &
pid_b=$!

if wait "$pid_a"; then status_a=0; else status_a=1; fi
if wait "$pid_b"; then status_b=0; else status_b=1; fi

successes=$(( (status_a == 0) + (status_b == 0) ))
failures=$(( (status_a != 0) + (status_b != 0) ))
if [[ "$successes" -ne 1 || "$failures" -ne 1 ]]; then
  echo "Expected exactly one successful reservation and one capacity rejection."
  cat "$tmp"/*.log
  exit 1
fi

if ! grep -q "resource pool capacity exceeded" "$tmp/ci-concurrent-a-0001.log" \
   && ! grep -q "resource pool capacity exceeded" "$tmp/ci-concurrent-b-0001.log"; then
  echo "The losing transaction did not fail for the expected capacity reason."
  cat "$tmp"/*.log
  exit 1
fi

echo "Concurrent pooled capacity test passed: exactly one of two conflicting transactions committed."
