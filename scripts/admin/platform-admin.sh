#!/usr/bin/env bash
# Host-owner operation. Never run through an application request.
set -Eeuo pipefail
: "${MIGRATOR_URL:?Set MIGRATOR_URL to the privileged migration connection}"
case "${1:-}" in grant) enabled=true;; revoke) enabled=false;; *) printf 'Usage: %s {grant|revoke} EMAIL [REASON]\n' "$0" >&2;exit 2;;esac
[[ -n "${2:-}" ]] || { printf 'Specify an existing staff account email.\n' >&2;exit 2; }
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 -v target_email="$2" -v enabled="$enabled" -v reason="${3:-host administrator provisioning}" <<'SQL'
BEGIN;
SET LOCAL ROLE eventor_owner;
SELECT set_config('app.platform_admin_reason',:'reason',true);
UPDATE eogp.users SET is_platform_admin=:'enabled'::boolean,updated_at=clock_timestamp()
 WHERE lower(email)=lower(:'target_email') RETURNING id AS platform_admin_user_id \gset
SELECT eogp.refresh_platform_admin_access(:'platform_admin_user_id'::uuid);
SELECT :'platform_admin_user_id'::uuid AS user_id,:'enabled'::boolean AS platform_admin;
COMMIT;
SQL
