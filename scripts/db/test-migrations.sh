#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${MIGRATOR_URL:?Set MIGRATOR_URL to the eventor_migrator connection string}"
: "${DATABASE_URL_RUNTIME:?Set DATABASE_URL_RUNTIME to the eventor_runtime connection string}"

# Run the broad fixture/constraint suite as eventor_owner so it can seed legacy
# draft/offer fixtures whose direct runtime DML is intentionally revoked by
# migration 000046. FORCE ROW LEVEL SECURITY remains enabled for eventor_owner;
# the suite separately asserts the effective eventor_runtime grants.
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -c "SET ROLE eventor_owner" \
  -f "$ROOT_DIR/database/tests/rls_and_constraints.sql"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/guest_registry_contact_merge_smoke.sql"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/guest_registry_reference_merge_smoke.sql"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/guest_registry_reviewed_restoration_smoke.sql"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/event_guest_bulk_groups_smoke.sql"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/registry_person_labels_smoke.sql"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/platform_administration_smoke.sql"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/event_rsvp_settings_smoke.sql"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/event_guest_bulk_name_reset_smoke.sql"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/guest_registry_label_merge_smoke.sql"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/guest_registry_relationship_merge_smoke.sql"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/registry_label_filter_smoke.sql"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/booking_event_link_commands_smoke.sql"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/event_booking_reference_projection_smoke.sql"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/event_disruption_inbox_smoke.sql"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/end_event_booking_link_smoke.sql"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/collaboration_proposal_revocation_smoke.sql"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/staff_collaboration_lifecycle_smoke.sql"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/collaboration_party_names_smoke.sql"
psql "$MIGRATOR_URL" -X -v ON_ERROR_STOP=1 \
  -f "$ROOT_DIR/tests/database/event_partner_booking_options_smoke.sql"
bash "$ROOT_DIR/scripts/db/test-concurrency.sh"
bash "$ROOT_DIR/scripts/db/test_revision_publication_concurrency.sh"
