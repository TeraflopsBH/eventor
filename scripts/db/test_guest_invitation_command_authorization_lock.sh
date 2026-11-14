#!/usr/bin/env bash
set -Eeuo pipefail
: "${RUNTIME_URL:?Set RUNTIME_URL to the eventor_runtime PostgreSQL login}"
: "${MIGRATOR_URL:?Set MIGRATOR_URL to the eventor_migrator PostgreSQL login}"
org="22222222-2222-4222-8222-222222222222"
event="94000000-0000-4000-8000-000000000001"
participation="94300000-0000-4000-8000-000000000002"
invitation="94500000-0000-4000-8000-000000000005"
delivery="96700000-0000-4000-8000-000000000001"
actor="bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb"
role="93900000-0000-4000-8000-000000000001"
idempotency="$(printf '%064d' 0 | tr '0' 'c')"
tmp="$(mktemp -d)"
runtime_pid=""
cleanup() {
  [[ -z "$runtime_pid" ]] || { kill "$runtime_pid" 2>/dev/null || true; wait "$runtime_pid" 2>/dev/null || true; }
  psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 -qAt <<SQL >/dev/null 2>&1 || true
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','$org',true);
INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
VALUES ('$org','$role','invitation.manage') ON CONFLICT DO NOTHING;
UPDATE eogp.invitations SET status='active'
 WHERE organization_id='$org' AND id='$invitation';
UPDATE eogp.invitation_deliveries SET idempotency_key_sha256=NULL
 WHERE organization_id='$org' AND id='$delivery';
COMMIT;
SQL
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

# Make the existing delivery an idempotent replay target and mark the
# invitation revoked so the second command exercises revoke's early-return path.
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 -qAt <<SQL
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','$org',true);
UPDATE eogp.invitation_deliveries
   SET idempotency_key_sha256='$idempotency'
 WHERE organization_id='$org' AND id='$delivery';
UPDATE eogp.invitations SET status='revoked'
 WHERE organization_id='$org' AND id='$invitation';
COMMIT;
SQL

# Case A: an idempotent issuance replay must hold invitation.manage grant
# locks until the caller's transaction completes.
psql "$RUNTIME_URL" -X -v ON_ERROR_STOP=1 -qAt >"$tmp/issue.log" 2>&1 <<SQL &
BEGIN;
SELECT set_config('app.organization_id','$org',true);
SELECT set_config('app.actor_membership_id','$actor',true);
DO \$issue_replay\$
DECLARE v_result jsonb;
BEGIN
  IF session_user<>'eventor_runtime' THEN
    RAISE EXCEPTION 'issue replay must use eventor_runtime, got %',session_user;
  END IF;
  v_result:=eogp.issue_guest_invitation(
    '$org','$event','$participation','$invitation','$actor',
    '94100000-0000-4000-8000-000000000001',
    '96400000-0000-4000-8000-000000000001','en',
    decode('455631'||repeat('01',40),'hex'),
    repeat('a',64),
    decode('45435031'||repeat('01',40),'hex'),
    clock_timestamp()+interval '1 hour',
    '$idempotency'
  );
  IF v_result->>'created'<>'false' OR v_result->>'deliveryId'<>'$delivery' THEN
    RAISE EXCEPTION 'expected idempotent delivery replay, got %',v_result;
  END IF;
END;
\$issue_replay\$;
\! touch "$tmp/issue-locked"
SELECT pg_sleep(2);
COMMIT;
SQL
runtime_pid=$!
wait_for_file "$tmp/issue-locked" "$runtime_pid" "$tmp/issue.log"
started_ns="$(date +%s%N)"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 -qAt >"$tmp/revoke-permission-after-issue.log" 2>&1 <<SQL &
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','$org',true);
DELETE FROM eogp.role_permissions
 WHERE organization_id='$org' AND role_id='$role' AND permission_code='invitation.manage';
COMMIT;
SQL
owner_pid=$!
wait "$owner_pid"
finished_ns="$(date +%s%N)"
issue_wait_ms="$(( (finished_ns-started_ns)/1000000 ))"
wait "$runtime_pid"
runtime_pid=""
if (( issue_wait_ms < 1500 )); then
  cat "$tmp/revoke-permission-after-issue.log"
  echo "Permission revocation did not wait for idempotent issuance (${issue_wait_ms} ms)." >&2
  exit 1
fi
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 -qAt <<SQL
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','$org',true);
INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
VALUES ('$org','$role','invitation.manage') ON CONFLICT DO NOTHING;
COMMIT;
SQL

# Case B: revoking an already-revoked invitation must still hold permission
# locks while returning its idempotent terminal result.
psql "$RUNTIME_URL" -X -v ON_ERROR_STOP=1 -qAt >"$tmp/revoke.log" 2>&1 <<SQL &
BEGIN;
SELECT set_config('app.organization_id','$org',true);
SELECT set_config('app.actor_membership_id','$actor',true);
DO \$revoke_replay\$
DECLARE v_result jsonb;
BEGIN
  IF session_user<>'eventor_runtime' THEN
    RAISE EXCEPTION 'revoke replay must use eventor_runtime, got %',session_user;
  END IF;
  v_result:=eogp.revoke_guest_invitation('$org','$invitation','$actor','ci_revoke_replay');
  IF v_result->>'status'<>'revoked' THEN
    RAISE EXCEPTION 'expected already-revoked result, got %',v_result;
  END IF;
END;
\$revoke_replay\$;
\! touch "$tmp/revoke-locked"
SELECT pg_sleep(2);
COMMIT;
SQL
runtime_pid=$!
wait_for_file "$tmp/revoke-locked" "$runtime_pid" "$tmp/revoke.log"
started_ns="$(date +%s%N)"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 -qAt >"$tmp/revoke-permission-after-revoke.log" 2>&1 <<SQL &
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.organization_id','$org',true);
DELETE FROM eogp.role_permissions
 WHERE organization_id='$org' AND role_id='$role' AND permission_code='invitation.manage';
COMMIT;
SQL
owner_pid=$!
wait "$owner_pid"
finished_ns="$(date +%s%N)"
revoke_wait_ms="$(( (finished_ns-started_ns)/1000000 ))"
wait "$runtime_pid"
runtime_pid=""
if (( revoke_wait_ms < 1500 )); then
  cat "$tmp/revoke-permission-after-revoke.log"
  echo "Permission revocation did not wait for already-revoked command (${revoke_wait_ms} ms)." >&2
  exit 1
fi

echo "Guest invitation issue/revoke authorization locks passed: permission revocation waited ${issue_wait_ms} ms for idempotent issuance and ${revoke_wait_ms} ms for already-revoked replay."
