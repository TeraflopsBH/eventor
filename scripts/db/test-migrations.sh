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
bash "$ROOT_DIR/scripts/db/test-concurrency.sh"
bash "$ROOT_DIR/scripts/db/test_revision_publication_concurrency.sh"
