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
winner_pid=""
cleanup() {
  if [[ -n "$winner_pid" ]]; then
    kill "$winner_pid" 2>/dev/null || true
    wait "$winner_pid" 2>/dev/null || true
  fi
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
    -c "SELECT set_config('app.organization_id','$org',false)" \
    -c "SELECT venue_space_id
          FROM eogp.venue_space_time_blocks
         WHERE organization_id='$org'
           AND id='15000000-0000-4000-8000-000000000002'" | tail -n1
)"
if [[ ! "$space_id" =~ ^[0-9a-fA-F-]{36}$ ]]; then
  echo "Could not resolve the venue space from the committed booking fixture." >&2
  exit 1
fi

# Transaction A inserts the active hold but deliberately keeps it uncommitted.
# The marker is created only after PostgreSQL has accepted the insert.
psql "$RUNTIME_URL" -X -v ON_ERROR_STOP=1 -qAt >"$tmp/winner.log" 2>&1 <<SQL &
BEGIN;
SELECT set_config('app.organization_id','$org',true);
DO \$login\$
BEGIN
  IF session_user <> 'eventor_runtime' THEN
    RAISE EXCEPTION 'space overlap winner must use eventor_runtime, got %',session_user;
  END IF;
END;
\$login\$;
INSERT INTO eogp.venue_space_time_blocks(
  organization_id,venue_space_id,booking_draft_revision_id,
  reservation_kind,status,starts_at,ends_at,expires_at,
  idempotency_key,actor_membership_id
) VALUES(
  '$org','$space_id','$draft_revision',
  'draft_hold','held',
  '2038-01-01 10:00:00+00','2038-01-01 11:00:00+00',
  clock_timestamp()+interval '1 day',
  '$key_a','$actor'
);
\! touch "$tmp/winner-ready"
SELECT pg_sleep(2);
COMMIT;
SQL
winner_pid=$!

for _ in $(seq 1 100); do
  [[ -e "$tmp/winner-ready" ]] && break
  if ! kill -0 "$winner_pid" 2>/dev/null; then
    cat "$tmp/winner.log"
    echo "First runtime transaction failed before inserting its hold." >&2
    exit 1
  fi
  sleep 0.05
done
if [[ ! -e "$tmp/winner-ready" ]]; then
  cat "$tmp/winner.log"
  echo "Timed out waiting for the first runtime transaction to hold its inserted row." >&2
  exit 1
fi

runtime_started_ns="$(date +%s%N)"
if psql "$RUNTIME_URL" -X -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -qAt \
  >"$tmp/loser.log" 2>&1 <<SQL
BEGIN;
SELECT set_config('app.organization_id','$org',true);
DO \$login\$
BEGIN
  IF session_user <> 'eventor_runtime' THEN
    RAISE EXCEPTION 'space overlap contender must use eventor_runtime, got %',session_user;
  END IF;
END;
\$login\$;
INSERT INTO eogp.venue_space_time_blocks(
  organization_id,venue_space_id,booking_draft_revision_id,
  reservation_kind,status,starts_at,ends_at,expires_at,
  idempotency_key,actor_membership_id
) VALUES(
  '$org','$space_id','$draft_revision',
  'draft_hold','held',
  '2038-01-01 10:00:00+00','2038-01-01 11:00:00+00',
  clock_timestamp()+interval '1 day',
  '$key_b','$actor'
);
COMMIT;
SQL
then
  loser_status=0
else
  loser_status=1
fi
runtime_finished_ns="$(date +%s%N)"
runtime_wait_ms="$(( (runtime_finished_ns - runtime_started_ns) / 1000000 ))"

wait "$winner_pid"
winner_pid=""

if [[ "$loser_status" -ne 1 ]] || ! grep -q '23P01' "$tmp/loser.log"; then
  echo "The overlapping runtime transaction did not fail with exclusion SQLSTATE 23P01."
  cat "$tmp/winner.log" "$tmp/loser.log"
  exit 1
fi
if (( runtime_wait_ms < 1500 )); then
  echo "The second transaction did not wait for the first transaction to commit (${runtime_wait_ms} ms)." >&2
  cat "$tmp/winner.log" "$tmp/loser.log"
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

echo "Independent-connection space overlap test passed: the second runtime transaction waited ${runtime_wait_ms} ms, then received exclusion SQLSTATE 23P01; exactly one active hold remained."
