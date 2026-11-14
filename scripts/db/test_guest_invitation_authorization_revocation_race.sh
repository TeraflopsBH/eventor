#!/usr/bin/env bash
set -Eeuo pipefail
: "${WORKER_URL:?Set WORKER_URL to the eventor_worker PostgreSQL login}"
: "${RUNTIME_URL:?Set RUNTIME_URL to the eventor_runtime PostgreSQL login}"
: "${MIGRATOR_URL:?Set MIGRATOR_URL to the eventor_migrator PostgreSQL login}"
org="22222222-2222-4222-8222-222222222222"
invitation="94500000-0000-4000-8000-000000000001"
delivery="96700000-0000-4000-8000-000000000001"
actor="bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb"
tmp="$(mktemp -d)"
worker_pid=""
runtime_pid=""
restore_event() {
  psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 -qAt <<SQL >/dev/null 2>&1 || true
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','$org',true);
UPDATE eogp.events SET status='cancelled',updated_at=clock_timestamp()
 WHERE organization_id='$org' AND id='94000000-0000-4000-8000-000000000001';
COMMIT;
SQL
}
cleanup() {
  [[ -z "$worker_pid" ]] || { kill "$worker_pid" 2>/dev/null || true; wait "$worker_pid" 2>/dev/null || true; }
  [[ -z "$runtime_pid" ]] || { kill "$runtime_pid" 2>/dev/null || true; wait "$runtime_pid" 2>/dev/null || true; }
  restore_event
  rm -rf "$tmp"
}
trap cleanup EXIT

wait_for_file() {
  local file="$1" pid="$2" log="$3"
  for _ in $(seq 1 200); do
    [[ -e "$file" ]] && return 0
    if ! kill -0 "$pid" 2>/dev/null; then cat "$log"; return 1; fi
    sleep 0.05
  done
  cat "$log"
  echo "Timed out waiting for synchronization marker $file." >&2
  return 1
}

# Race A: SMTP authorization obtains invitation/link locks first. Revocation
# must block until the worker's authorization transaction commits.
psql "$WORKER_URL" -X -v ON_ERROR_STOP=1 -qAt >"$tmp/worker-first.log" 2>&1 <<SQL &
BEGIN;
SELECT set_config('app.organization_id','$org',true);
DO \$authorize_first\$
BEGIN
  IF session_user<>'eventor_worker' THEN
    RAISE EXCEPTION 'authorization race must use eventor_worker, got %',session_user;
  END IF;
  IF NOT eogp.authorize_invitation_email_submission('$org','$delivery') THEN
    RAISE EXCEPTION 'worker authorization should win the first race';
  END IF;
END;
\$authorize_first\$;
\\! touch "$tmp/worker-authorized"
SELECT pg_sleep(2);
COMMIT;
SQL
worker_pid=$!
wait_for_file "$tmp/worker-authorized" "$worker_pid" "$tmp/worker-first.log"
started_ns="$(date +%s%N)"
psql "$RUNTIME_URL" -X -v ON_ERROR_STOP=1 -qAt >"$tmp/revoke-after-worker.log" 2>&1 <<SQL &
BEGIN;
SELECT set_config('app.organization_id','$org',true);
SELECT set_config('app.actor_membership_id','$actor',true);
SELECT eogp.revoke_guest_invitation('$org','$invitation','$actor','ci_worker_auth_won');
COMMIT;
SQL
runtime_pid=$!
wait "$runtime_pid"
runtime_pid=""
finished_ns="$(date +%s%N)"
worker_first_wait_ms="$(( (finished_ns-started_ns)/1000000 ))"
wait "$worker_pid"
worker_pid=""
if (( worker_first_wait_ms < 1500 )); then
  cat "$tmp/revoke-after-worker.log"
  echo "Revocation did not wait for the worker authorization transaction (${worker_first_wait_ms} ms)." >&2
  exit 1
fi
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 -qAt <<SQL
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','$org',true);
DO \$assert_worker_first\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM eogp.invitations WHERE organization_id='$org' AND id='$invitation' AND status='revoked')
     OR NOT EXISTS (SELECT 1 FROM eogp.invitation_links WHERE organization_id='$org' AND id='96600000-0000-4000-8000-000000000001' AND revoked_at IS NOT NULL) THEN
    RAISE EXCEPTION 'revocation did not commit after the winning worker authorization';
  END IF;
END;
\$assert_worker_first\$;
COMMIT;
SQL

# Reset only the invitation capability state. The same live sending lease is
# used to force authorization to contend on the invitation row in race B.
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 -qAt <<SQL
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','$org',true);
UPDATE eogp.events SET status='scheduled',updated_at=clock_timestamp()
 WHERE organization_id='$org' AND id='94000000-0000-4000-8000-000000000001';
UPDATE eogp.invitation_links SET revoked_at=NULL
 WHERE organization_id='$org' AND id='96600000-0000-4000-8000-000000000001';
UPDATE eogp.invitations SET status='active',revoked_at=NULL
 WHERE organization_id='$org' AND id='$invitation';
COMMIT;
SQL

# Race B: revocation obtains the invitation lock first. The worker must wait
# for commit, re-read the revoked capability, and refuse SMTP authorization.
psql "$RUNTIME_URL" -X -v ON_ERROR_STOP=1 -qAt >"$tmp/revoke-first.log" 2>&1 <<SQL &
BEGIN;
SELECT set_config('app.organization_id','$org',true);
SELECT set_config('app.actor_membership_id','$actor',true);
DO \$revoke_first\$
BEGIN
  IF session_user<>'eventor_runtime' THEN
    RAISE EXCEPTION 'revocation race must use eventor_runtime, got %',session_user;
  END IF;
  PERFORM eogp.revoke_guest_invitation('$org','$invitation','$actor','ci_revocation_won');
END;
\$revoke_first\$;
\\! touch "$tmp/revocation-committed"
SELECT pg_sleep(2);
COMMIT;
SQL
runtime_pid=$!
wait_for_file "$tmp/revocation-committed" "$runtime_pid" "$tmp/revoke-first.log"
started_ns="$(date +%s%N)"
psql "$WORKER_URL" -X -v ON_ERROR_STOP=1 -qAt >"$tmp/authorize-after-revoke.log" 2>&1 <<SQL &
BEGIN;
SELECT set_config('app.organization_id','$org',true);
DO \$authorize_after_revoke\$
DECLARE v_authorized boolean;
BEGIN
  IF session_user<>'eventor_worker' THEN
    RAISE EXCEPTION 'authorization race must use eventor_worker, got %',session_user;
  END IF;
  v_authorized := eogp.authorize_invitation_email_submission('$org','$delivery');
  IF v_authorized THEN
    RAISE EXCEPTION 'worker authorized SMTP after revocation committed first';
  END IF;
END;
\$authorize_after_revoke\$;
COMMIT;
SQL
worker_pid=$!
wait "$worker_pid"
worker_pid=""
finished_ns="$(date +%s%N)"
revoke_first_wait_ms="$(( (finished_ns-started_ns)/1000000 ))"
wait "$runtime_pid"
runtime_pid=""
if (( revoke_first_wait_ms < 1500 )); then
  cat "$tmp/authorize-after-revoke.log"
  echo "Worker authorization did not wait for the revocation transaction (${revoke_first_wait_ms} ms)." >&2
  exit 1
fi

echo "Guest invitation SMTP authorization/revocation races passed: worker-first revocation waited ${worker_first_wait_ms} ms; revocation-first worker authorization waited ${revoke_first_wait_ms} ms and returned false."
