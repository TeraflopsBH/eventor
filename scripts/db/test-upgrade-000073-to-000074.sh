#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${MIGRATOR_URL:?MIGRATOR_URL must connect as eventor_migrator}"
: "${AUTH_URL:?AUTH_URL must connect as eventor_auth}"
MIGRATION_074="$ROOT_DIR/database/migrations/000074_booking_offer_email_worker_fixes.sql"

pre_dir="$(mktemp -d)"
post_dir="$(mktemp -d)"
trap 'rm -rf "$pre_dir" "$post_dir"' EXIT

# Rehearse the exact schema boundary immediately before the worker-fix
# migration. The migration chain through 000073 is applied first, then the
# same committed synthetic CI fixture used by the normal database suite.
cp "$ROOT_DIR"/database/migrations/[0-9][0-9][0-9][0-9][0-9][0-9]_*.sql "$pre_dir/"
rm "$pre_dir/000074_booking_offer_email_worker_fixes.sql"
rm "$pre_dir/000075_guest_invitation_runtime.sql"
rm "$pre_dir/000076_guest_invitation_issuance_delivery.sql"
rm "$pre_dir/000077_guest_invitation_staff_projections.sql"
rm "$pre_dir/000078_guest_invitation_delivery_attempt_history.sql"
rm "$pre_dir/000079_guest_invitation_rsvp_lock_order.sql"
rm "$pre_dir/000080_guest_invitation_history_capability_state.sql"
rm "$pre_dir/000081_guest_invitation_revoke_delivery_guard.sql"
rm "$pre_dir/000082_guest_invitation_send_authorization.sql"
rm "$pre_dir/000083_guest_invitation_send_authorization_current_capabilities.sql"
rm "$pre_dir/000084_guest_invitation_effective_schedule.sql"
rm "$pre_dir/000085_guest_invitation_idempotency_lock_order.sql"
rm "$pre_dir/000086_guest_invitation_attempt_history_immutability.sql"
rm "$pre_dir/000087_guest_invitation_revoke_actor_binding.sql"
rm "$pre_dir/000088_guest_invitation_capability_effective_schedule.sql"
rm "$pre_dir/000089_guest_invitation_effective_schedule_projection.sql"
rm "$pre_dir/000090_bind_staff_actor_context.sql"
rm "$pre_dir/000091_bind_remaining_staff_actor_context.sql"
rm "$pre_dir/000092_collaboration_grant_authorization.sql"
rm "$pre_dir/000093_booking_draft_actor_context.sql"
rm "$pre_dir/000094_auth_role_column_privileges.sql"
rm "$pre_dir/000095_revoke_notification_guard_function_execution.sql"
rm "$pre_dir/000096_staff_recorded_rsvp.sql"
rm "$pre_dir/000097_guest_rsvp_current_response_projection.sql"
rm "$pre_dir/000098_staff_guest_rsvp_history.sql"
rm "$pre_dir/000099_guest_invitation_authorization_and_rsvp_limits.sql"

echo "=== Apply schema through 000073 ==="
DATABASE_URL="$MIGRATOR_URL" MIGRATIONS_DIR="$pre_dir" \
  bash "$ROOT_DIR/scripts/db/migrate.sh"

echo "=== Seed synthetic authentication identities and prior-schema data ==="
psql "$AUTH_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/seed_auth_test_users.sql"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/migration_smoke.sql"

count_snapshot() {
  psql "$MIGRATOR_URL" -X -qAt -v ON_ERROR_STOP=1 <<'SQL'
SET ROLE eventor_owner;
SELECT
  (SELECT count(*) FROM eogp.organizations) || ',' ||
  (SELECT count(*) FROM eogp.organization_memberships) || ',' ||
  (SELECT count(*) FROM eogp.venues) || ',' ||
  (SELECT count(*) FROM eogp.booking_drafts) || ',' ||
  (SELECT count(*) FROM eogp.booking_offers) || ',' ||
  (SELECT count(*) FROM eogp.booking_offer_email_deliveries);
SQL
}

before="$(count_snapshot)"
echo "Pre-upgrade tenant/business row counts: $before"

echo "=== Apply migration 000074 on the populated 000073 schema ==="
cp "$MIGRATION_074" "$post_dir/"
DATABASE_URL="$MIGRATOR_URL" MIGRATIONS_DIR="$post_dir" \
  bash "$ROOT_DIR/scripts/db/migrate.sh"

after="$(count_snapshot)"
echo "Post-upgrade tenant/business row counts: $after"
if [[ "$before" != "$after" ]]; then
  echo "Migration 000074 unexpectedly changed existing tenant/business row counts" >&2
  exit 1
fi

echo "=== Verify migration ledger and upgraded worker function contract ==="
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
SET ROLE eventor_owner;
DO $upgrade_check$
DECLARE
  v_count integer;
  v_result text;
BEGIN
  SELECT count(*) INTO v_count FROM eogp.schema_migrations;
  IF v_count <> 74
     OR NOT EXISTS (SELECT 1 FROM eogp.schema_migrations WHERE version='000073')
     OR NOT EXISTS (SELECT 1 FROM eogp.schema_migrations WHERE version='000074') THEN
    RAISE EXCEPTION 'expected contiguous migration ledger through 000074; found % rows',v_count;
  END IF;

  v_result:=pg_get_function_result(
    'eogp.claim_booking_offer_email_delivery(uuid)'::regprocedure
  );
  IF position('currency text' IN v_result)=0 THEN
    RAISE EXCEPTION 'upgraded claim function has unexpected result contract: %',v_result;
  END IF;
END;
$upgrade_check$;
SQL

echo "=== Re-run the normal migration runner against the complete chain ==="
DATABASE_URL="$MIGRATOR_URL" bash "$ROOT_DIR/scripts/db/migrate.sh"

echo "Populated schema upgrade rehearsal 000073 -> 000074 passed."
