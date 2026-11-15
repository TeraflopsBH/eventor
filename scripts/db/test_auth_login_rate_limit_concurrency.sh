#!/usr/bin/env bash
set -euo pipefail

: "$AUTH_URL"
: "$ADMIN_URL"

work_dir="$(mktemp -d)"
email_fingerprint="$(openssl rand -hex 32)"
source_fingerprint="$(openssl rand -hex 32)"
admin_eventor_url="${ADMIN_URL%/postgres}/eventor"
cleanup() {
  psql "$admin_eventor_url" -X -v ON_ERROR_STOP=1 \
    -c "DELETE FROM eogp.auth_login_attempts WHERE email_fingerprint='$email_fingerprint' AND source_fingerprint='$source_fingerprint'" \
    >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

reserve_attempt_sql=$(cat <<SQL
INSERT INTO eogp.auth_login_attempts (
  email_fingerprint, source_fingerprint,
  window_started_at, failed_attempts, updated_at
) VALUES ('$email_fingerprint','$source_fingerprint',clock_timestamp(),1,clock_timestamp())
ON CONFLICT (email_fingerprint, source_fingerprint)
DO UPDATE SET
  failed_attempts = CASE
    WHEN eogp.auth_login_attempts.blocked_until > clock_timestamp()
      THEN eogp.auth_login_attempts.failed_attempts
    WHEN eogp.auth_login_attempts.window_started_at
         < clock_timestamp() - make_interval(secs => 900)
      THEN 1
    ELSE eogp.auth_login_attempts.failed_attempts + 1
  END,
  window_started_at = CASE
    WHEN eogp.auth_login_attempts.blocked_until > clock_timestamp()
      THEN eogp.auth_login_attempts.window_started_at
    WHEN eogp.auth_login_attempts.window_started_at
         < clock_timestamp() - make_interval(secs => 900)
      THEN clock_timestamp()
    ELSE eogp.auth_login_attempts.window_started_at
  END,
  blocked_until = CASE
    WHEN eogp.auth_login_attempts.blocked_until > clock_timestamp()
      THEN eogp.auth_login_attempts.blocked_until
    WHEN eogp.auth_login_attempts.window_started_at
         < clock_timestamp() - make_interval(secs => 900)
      THEN NULL
    WHEN eogp.auth_login_attempts.failed_attempts + 1 > 5
      THEN clock_timestamp() + make_interval(secs => 900)
    ELSE NULL
  END,
  updated_at = clock_timestamp()
RETURNING coalesce(blocked_until > clock_timestamp(), false);
SQL
)

# Ten independent database sessions race on the same unique key. The UPSERT
# must serialize them: exactly five reservations pass and all remaining ones
# observe the block, regardless of statement arrival order.
for i in {1..10}; do
  psql "$AUTH_URL" -X -q -A -t -v ON_ERROR_STOP=1 \
    -c "$reserve_attempt_sql" >"$work_dir/$i.out" 2>"$work_dir/$i.err" &
done
wait

allowed=0
blocked=0
for result_file in "$work_dir"/*.out; do
  result="$(tr -d '[:space:]' <"$result_file")"
  case "$result" in
    f|false) allowed=$((allowed + 1)) ;;
    t|true) blocked=$((blocked + 1)) ;;
    *) echo "Unexpected login reservation result in $result_file: '$result'" >&2; cat "${result_file%.out}.err" >&2; exit 1 ;;
  esac
done

if [[ "$allowed" -ne 5 || "$blocked" -ne 5 ]]; then
  echo "Expected exactly five allowed and five blocked concurrent reservations; got allowed=$allowed blocked=$blocked" >&2
  exit 1
fi

extra="$(psql "$AUTH_URL" -X -q -A -t -v ON_ERROR_STOP=1 \
  -c "$reserve_attempt_sql" | tr -d '[:space:]')"
if [[ "$extra" != "t" ]]; then
  echo "A further login reservation was not blocked after the concurrent threshold" >&2
  exit 1
fi

# An active block must outlive an expired attempt window when the configured
# block duration is longer than the login window.
psql "$AUTH_URL" -X -v ON_ERROR_STOP=1 \
  -c "UPDATE eogp.auth_login_attempts
         SET window_started_at=clock_timestamp()-interval '1 hour',
             failed_attempts=6,
             blocked_until=clock_timestamp()+interval '5 minutes'
       WHERE email_fingerprint='$email_fingerprint' AND source_fingerprint='$source_fingerprint'" >/dev/null
active_block="$(psql "$AUTH_URL" -X -q -A -t -v ON_ERROR_STOP=1 \
  -c "$reserve_attempt_sql" | tr -d '[:space:]')"
if [[ "$active_block" != "t" ]]; then
  echo "An active login block was cleared when its attempt window expired" >&2
  exit 1
fi

echo "Concurrent authentication login rate-limit regression passed (5 allowed, 5 blocked, subsequent attempt blocked, active block preserved)."
