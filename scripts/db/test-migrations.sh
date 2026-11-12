#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${DATABASE_URL:?Set DATABASE_URL to the eventor_migrator connection string}"
: "${DATABASE_URL_RUNTIME:?Set DATABASE_URL_RUNTIME to the eventor_runtime connection string}"

# Privileged fixture creation and schema-constraint checks run as eventor_owner.
echo "Running owner-level database fixtures and constraint checks..."
psql "$DATABASE_URL" -X -v ON_ERROR_STOP=1 -f "$ROOT_DIR/database/tests/constraints_and_booking_fixtures.sql"

# Tenant isolation and cross-organization access checks must run as eventor_runtime.
echo "Running tenant RLS and cross-organization checks as eventor_runtime..."
psql "$DATABASE_URL_RUNTIME" -X -v ON_ERROR_STOP=1 -f "$ROOT_DIR/database/tests/rls_and_constraints.sql"

bash "$ROOT_DIR/scripts/db/test-concurrency.sh"
bash "$ROOT_DIR/scripts/db/test_revision_publication_concurrency.sh"
