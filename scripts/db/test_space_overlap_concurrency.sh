#!/usr/bin/env bash
set -Eeuo pipefail

: "${RUNTIME_URL:?Set RUNTIME_URL to the eventor_runtime PostgreSQL login}"
: "${MIGRATOR_URL:?Set MIGRATOR_URL to the eventor_migrator PostgreSQL login}"

org="11111111-1111-4111-8111-111111111111"
draft_revision="89000000-0000-4000-8000-000000000002"
actor="aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa"
key_a="ci-space-overlap-concurrent-a"
key_b="ci-space-overlap-concurrent-b"
tmp="$(mktemp -d)"

cleanup() {
  psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 -qAt >/dev/null 2>&1 <<SQL || true
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','$org',true);
DELETE FROM eogp.venue_space_time_blocks
 WHERE organization_id='$org'
   AND idempotency_key IN ('$key_a','$key_b');
COMMIT;
SQL
  rm -rf "$tmp"
}
trap cleanup EXIT

space_id="$(
  psql "$RUNTIME_URL" -X -v ON_ERROR_STOP=1 -qAt \
    -c "SELECT set_config('app.organization_id','$org',true)" \
    -c "SELECT venue_space_id
          FROM eogp.venue_space_time_blocks
         WHERE organization_id='$org'
           AND id='15000000-0000-4000-8000-000000000002'" | tail -n1
)"
if [[ ! "$space_id" =~ ^[0-9a-fA-F-]{36}$ ]]; then
  echo "Could not resolve the active venue space from the committed booking fixture." >&2
  exit 1
fi

run_attempt() {
  local key="$1"
  psql "$RUNTIME_URL" -X -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -qAt \
    >"$tmp/$key.log" 2>&1 <<SQL
BEGIN;
SELECT set_config('app.organization_id','$org',true);
DO \$login\$
BEGIN
  IF session_user <> 'eventor_runtime' THEN
    RAISE EXCEPTION 'space overlap attempt must use eventor_runtime, got %',session_user;
  END IF;
END;
\$login\$;
-- Keep both independent transactions open briefly before they contend.
SELECT pg_sleep(0.5);
INSERT INTO eogp.venue_space_time_blocks(
  organization_id,venue_space_id,booking_draft_revision_id,
  reservation_kind,status,starts_at,ends_at,expires_at,
  idempotency_key,actor_membership_id
) VALUES(
  '$org','$space_id','$draft_revision',
  'draft_hold','held',
  '2038-01-01 10:00:00+00','2038-01-01 11:00:00+00',
  clock_timestamp()+interval '1 day',
  '$key','$actor'
);
COMMIT;
SQL
}

run_attempt "$key_a" &
pid_a=$!
run_attempt "$key_b" &
pid_b=$!

if wait "$pid_a"; then status_a=0; else status_a=1; fi
if wait "$pid_b"; then status_b=0; else status_b=1; fi

successes=$(( (status_a == 0) + (status_b == 0) ))
failures=$(( (status_a != 0) + (status_b != 0) ))
if [[ "$successes" -ne 1 || "$failures" -ne 1 ]]; then
  echo "Expected exactly one concurrent space hold insert to commit and one to fail."
  cat "$tmp"/*.log
  exit 1
fi

if ! grep -q '23P01' "$tmp/$key_a.log" && ! grep -q '23P01' "$tmp/$key_b.log"; then
  echo "The losing transaction did not fail with the expected exclusion SQLSTATE 23P01."
  cat "$tmp"/*.log
  exit 1
fi

psql "$RUNTIME_URL" -X -v ON_ERROR_STOP=1 -qAt <<SQL
BEGIN;
SELECT set_config('app.organization_id','$org',true);
DO \$verify\$
DECLARE
  v_active_count bigint;
BEGIN
  SELECT count(*) INTO v_active_count
    FROM eogp.venue_space_time_blocks
   WHERE organization_id='$org'
     AND idempotency_key IN ('$key_a','$key_b')
     AND status='held';
  IF v_active_count <> 1 THEN
    RAISE EXCEPTION 'expected exactly one active overlapping space hold, found %',v_active_count;
  END IF;
END;
\$verify\$;
COMMIT;
SQL

echo "Independent-connection space overlap test passed: exactly one runtime transaction committed; the other received exclusion SQLSTATE 23P01."
