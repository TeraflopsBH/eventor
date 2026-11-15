#!/usr/bin/env bash
set -euo pipefail

: "${AUTH_URL:?AUTH_URL must point to the dedicated eventor_auth database role}"
: "${MIGRATOR_URL:?MIGRATOR_URL must point to the migration/owner database role}"

work_dir="$(mktemp -d)"
email_fingerprint="$(openssl rand -hex 32)"
source_fingerprint="$(openssl rand -hex 32)"
cleanup() {
  psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 -v email="$email_fingerprint" -v source="$source_fingerprint" \
    -c "DELETE FROM eogp.auth_login_attempts WHERE email_fingerprint=:'email' AND source_fingerprint=:'source'" \
    >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

reserve_attempt_sql=$(cat <<'SQL'
INSERT INTO eogp.auth_login_attempts (
  email_fingerprint, source_fingerprint,
  window_started_at, failed_attempts, updated_at
) VALUES (:'email',:'source',clock_timestamp(),1,clock_timestamp())
ON CONFLICT (email_fingerprint, source_fingerprint)
DO UPDATE SET
  failed_attempts = CASE
    WHEN eogp.auth_login_attempts.window_started_at
         < clock_timestamp() - make_interval(secs => 900)
      THEN 1
    WHEN eogp.auth_login_attempts.blocked_until > clock_timestamp()
      THEN eogp.auth_login_attempts.failed_attempts
    ELSE eogp.auth_login_attempts.failed_attempts + 1
  END,
  window_started_at = CASE
    WHEN eogp.auth_login_attempts.window_started_at
         < clock_timestamp() - make_interval(secs => 900)
      THEN clock_timestamp()
    ELSE eogp.auth_login_attempts.window_started_at
  END,
  blocked_until = CASE
    WHEN eogp.auth_login_attempts.window_started_at
         < clock_timestamp() - make_interval(secs => 900)
      THEN NULL
    WHEN eogp.auth_login_attempts.blocked_until > clock_timestamp()
      THEN eogp.auth_login_attempts.blocked_until
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
  psql "$AUTH_URL" -X -A -t -v ON_ERROR_STOP=1 \
    -v email="$email_fingerprint" -v source="$source_fingerprint" \
    -c "$reserve_attempt_sql" >"$work_dir/$i" &
done
wait

allowed=0
blocked=0
for result_file in "$work_dir"/*; do
  case "$(tr -d '[:space:]' <"$result_file")" in
    f) allowed=$((allowed + 1)) ;;
    t) blocked=$((blocked + 1)) ;;
    *) echo "Unexpected login reservation result in $result_file" >&2; exit 1 ;;
  esac
done

if [[ "$allowed" -ne 5 || "$blocked" -ne 5 ]]; then
  echo "Expected exactly five allowed and five blocked concurrent reservations; got allowed=$allowed blocked=$blocked" >&2
  exit 1
fi

extra="$(psql "$AUTH_URL" -X -A -t -v ON_ERROR_STOP=1 \
  -v email="$email_fingerprint" -v source="$source_fingerprint" \
  -c "$reserve_attempt_sql" | tr -d '[:space:]')"
if [[ "$extra" != "t" ]]; then
  echo "A further login reservation was not blocked after the concurrent threshold" >&2
  exit 1
fi

echo "Concurrent authentication login rate-limit regression passed (5 allowed, 5 blocked, subsequent attempt blocked)."
