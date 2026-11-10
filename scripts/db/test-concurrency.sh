#!/usr/bin/env bash
set -Eeuo pipefail

: "\${DATABASE_URL_RUNTIME:?Set DATABASE_URL_RUNTIME to the eventor_runtime PostgreSQL connection string}"
command -v psql >/dev/null 2>&1 || { echo "psql is required" >&2; exit 127; }

ORG="10000000-0000-0000-0000-00000000000a"
POOL="a0000000-0000-0000-0000-00000000000b"
REVISION="c0000000-0000-0000-0000-00000000000a"
START="2031-03-01 10:00:00+00"
END="2031-03-01 11:00:00+00"
EXPIRES="clock_timestamp() + interval '2 hours'"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

run_attempt() {
  local key="$1"
  psql "$DATABASE_URL_RUNTIME" -X -qAt -v ON_ERROR_STOP=1 <<SQL
BEGIN;
SELECT set_config('app.organization_id', '$ORG', true);
SELECT eogp.reserve_pooled_resource(
  '$ORG', '$POOL', '$REVISION', NULL, NULL,
  '$START'::timestamptz, '$END'::timestamptz, 1,
  $EXPIRES, '$key'
);
COMMIT;
SQL
}

set +e
run_attempt "ci-concurrent-a-0001" >"$TMP_DIR/a.out" 2>&1 &
pid_a=$!
run_attempt "ci-concurrent-b-0001" >"$TMP_DIR/b.out" 2>&1 &
pid_b=$!
wait "$pid_a"
status_a=$?
wait "$pid_b"
status_b=$?
set -e

successes=0
failures=0
for pair in "a:$status_a" "b:$status_b"; do
  status="\${pair#*:}"
  [[ "$status" -eq 0 ]] && ((successes+=1)) || ((failures+=1))
done

if [[ "$successes" -ne 1 || "$failures" -ne 1 ]]; then
  echo "Expected exactly one concurrent pooled reservation to succeed."
  echo "--- attempt A ---"; cat "$TMP_DIR/a.out"
  echo "--- attempt B ---"; cat "$TMP_DIR/b.out"
  exit 1
fi

failed_output="$TMP_DIR/a.out"
[[ "$status_a" -eq 0 ]] && failed_output="$TMP_DIR/b.out"
if ! grep -q "resource pool capacity exceeded" "$failed_output"; then
  echo "The losing transaction failed for an unexpected reason."
  cat "$failed_output"
  exit 1
fi

active_count="$(psql "$DATABASE_URL_RUNTIME" -X -qAt -v ON_ERROR_STOP=1 <<SQL
BEGIN;
SELECT set_config('app.organization_id', '$ORG', true);
SELECT count(*)
FROM eogp.resource_reservations
WHERE organization_id = '$ORG'
  AND resource_pool_id = '$POOL'
  AND status = 'held'
  AND starts_at = '$START'::timestamptz
  AND ends_at = '$END'::timestamptz;
COMMIT;
SQL
)"
if [[ "$active_count" != "1" ]]; then
  echo "Expected exactly one active reservation in the one-unit pool; found $active_count."
  exit 1
fi

echo "PostgreSQL concurrent pooled-capacity test passed (one commit, one capacity rejection)."
