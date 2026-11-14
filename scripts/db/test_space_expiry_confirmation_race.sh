#!/usr/bin/env bash
set -Eeuo pipefail
: "${WORKER_URL:?Set WORKER_URL to the eventor_worker PostgreSQL login}"
: "${RUNTIME_URL:?Set RUNTIME_URL to the eventor_runtime PostgreSQL login}"
org="11111111-1111-4111-8111-111111111111"
draft_revision="51000000-0000-4000-8000-000000000002"
booking="73000000-0000-4000-8000-000000000001"
actor="aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa"
hold="8a000000-0000-4000-8000-000000000001"
tmp="$(mktemp -d)"
worker_pid=""
cleanup() {
  if [[ -n "$worker_pid" ]]; then
    kill "$worker_pid" 2>/dev/null || true
    wait "$worker_pid" 2>/dev/null || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT
sleep 3.2
psql "$WORKER_URL" -X -v ON_ERROR_STOP=1 -qAt >"$tmp/worker.log" 2>&1 <<SQL &
BEGIN;
SELECT set_config('app.organization_id','$org',true);
SELECT 'WORKER_EXPIRED_COUNT=' || eogp.expire_space_holds('$org');
\! touch "$tmp/worker-ready"
SELECT pg_sleep(2);
COMMIT;
SQL
worker_pid=$!
for _ in $(seq 1 100); do
  [[ -e "$tmp/worker-ready" ]] && break
  if ! kill -0 "$worker_pid" 2>/dev/null; then
    cat "$tmp/worker.log"
    echo "Expiry worker exited before holding the expired-row transition." >&2
    exit 1
  fi
  sleep 0.05
done
if [[ ! -e "$tmp/worker-ready" ]]; then
  cat "$tmp/worker.log"
  echo "Timed out waiting for the worker to expire the hold." >&2
  exit 1
fi
runtime_started_ns="$(date +%s%N)"
psql "$RUNTIME_URL" -X -v ON_ERROR_STOP=1 -qAt <<SQL
BEGIN;
SELECT set_config('app.organization_id','$org',true);
DO \$race\$
DECLARE
  v_result jsonb;
  v_status text;
BEGIN
  IF session_user <> 'eventor_runtime' THEN
    RAISE EXCEPTION 'race conversion must use the eventor_runtime login, got %',session_user;
  END IF;
  v_result := eogp.confirm_booking_reservations(
    '$org','$draft_revision','$booking','$actor',
    'ci_expiry_worker_won_independent_connection_race'
  );
  IF (v_result->>'spaceReservationsConfirmed')::bigint <> 0 THEN
    RAISE EXCEPTION 'confirmation converted a hold already expired by the worker: %',v_result;
  END IF;
  SELECT status INTO v_status
    FROM eogp.venue_space_time_blocks
   WHERE organization_id='$org' AND id='$hold';
  IF v_status IS DISTINCT FROM 'expired' THEN
    RAISE EXCEPTION 'worker-won race ended in unexpected hold state: %',v_status;
  END IF;
END;
\$race\$;
COMMIT;
SQL
runtime_finished_ns="$(date +%s%N)"
runtime_wait_ms="$(( (runtime_finished_ns - runtime_started_ns) / 1000000 ))"
if (( runtime_wait_ms < 1500 )); then
  echo "Runtime conversion did not wait for the worker transaction as expected (${runtime_wait_ms} ms)." >&2
  cat "$tmp/worker.log"
  exit 1
fi
wait "$worker_pid"
worker_pid=""
if ! grep -Eq '^WORKER_EXPIRED_COUNT=[1-9][0-9]*$' "$tmp/worker.log"; then
  cat "$tmp/worker.log"
  echo "Worker output did not report an expiry transition." >&2
  exit 1
fi
echo "Independent-connection expiry/confirmation race passed: eventor_worker expired the hold; eventor_runtime waited ${runtime_wait_ms} ms, converted zero holds, and observed the committed expired state."
