#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
: "${DATABASE_URL_RUNTIME:?Set DATABASE_URL_RUNTIME to the eventor_runtime connection string}"

psql "$DATABASE_URL_RUNTIME" -X -v ON_ERROR_STOP=1 -f "$ROOT_DIR/database/tests/rls_and_constraints.sql"
bash "$ROOT_DIR/scripts/db/test-concurrency.sh"
bash "$ROOT_DIR/scripts/db/test_revision_publication_concurrency.sh"
