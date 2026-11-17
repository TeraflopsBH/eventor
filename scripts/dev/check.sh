#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_DIR="$ROOT_DIR/.eventor-dev/logs"
PYTHON="$ROOT_DIR/.eventor-dev/venv/bin/python"
mkdir -p "$LOG_DIR"
[[ -x "$PYTHON" ]] || PYTHON="$(command -v python3 || true)"

run_logged() {
  local label="$1" log_name="$2"
  shift 2
  local log_file="$LOG_DIR/$log_name.log"
  if "$@" >"$log_file" 2>&1; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s (log: %s)\n' "$label" "$log_file" >&2
    tail -n 80 "$log_file" >&2
    return 1
  fi
}

contract_checks() {
  [[ -n "$PYTHON" ]] || { printf 'Python is required for contract checks.\n' >&2; return 1; }
  run_logged "OpenAPI repository validator" openapi-repository \
    "$PYTHON" "$ROOT_DIR/scripts/validate_openapi.py" "$ROOT_DIR/docs/api/openapi.v0.3.yaml"
  if "$PYTHON" -c 'import openapi_spec_validator' >/dev/null 2>&1; then
    run_logged "OpenAPI semantic validator" openapi-semantic \
      "$PYTHON" -m openapi_spec_validator "$ROOT_DIR/docs/api/openapi.v0.3.yaml"
  else
    printf 'WARN OpenAPI semantic validator unavailable; run scripts/dev/setup.sh\n'
  fi
}

mode="${1:-quick}"
case "$mode" in
  quick)
    contract_checks
    run_logged "API type check" api-typecheck npm --prefix "$ROOT_DIR/apps/api" run typecheck
    run_logged "Staff tests" staff-tests npm --prefix "$ROOT_DIR/apps/staff-web" test
    run_logged "Staff type check" staff-typecheck npm --prefix "$ROOT_DIR/apps/staff-web" run typecheck
    ;;
  api)
    pattern="${2:-}"
    run_logged "API build" api-build npm --prefix "$ROOT_DIR/apps/api" run build
    if [[ -n "$pattern" ]]; then
      run_logged "API tests matching: $pattern" api-tests \
        node --test --test-name-pattern="$pattern" "$ROOT_DIR"/apps/api/dist/test/*.test.js
    else
      run_logged "API tests" api-tests node --test "$ROOT_DIR"/apps/api/dist/test/*.test.js
    fi
    ;;
  web)
    run_logged "Staff tests" staff-tests npm --prefix "$ROOT_DIR/apps/staff-web" test
    run_logged "Staff production build" staff-build npm --prefix "$ROOT_DIR/apps/staff-web" run build
    ;;
  db)
    role="${2:-}"
    sql_file="${3:-}"
    [[ -n "$role" && -n "$sql_file" ]] || { printf 'Usage: %s db ROLE REPOSITORY_RELATIVE_SQL\n' "$0" >&2; exit 2; }
    "$ROOT_DIR/scripts/dev/db.sh" up >/dev/null 2>&1
    run_logged "Database fixture $sql_file as $role" database-fixture \
      "$ROOT_DIR/scripts/dev/db.sh" file "$role" "$sql_file"
    ;;
  full)
    printf 'NOTE Full application checks; exact-head CI additionally runs audits, PostgreSQL integration/concurrency, browser, systemd and secret scans.\n'
    contract_checks
    run_logged "API tests" api-tests npm --prefix "$ROOT_DIR/apps/api" test
    run_logged "Staff tests/build" staff-build npm --prefix "$ROOT_DIR/apps/staff-web" run build
    run_logged "Staff regression tests" staff-tests npm --prefix "$ROOT_DIR/apps/staff-web" test
    ;;
  *)
    printf 'Usage: %s {quick|api [PATTERN]|web|db ROLE SQL_FILE|full}\n' "$0" >&2
    exit 2
    ;;
esac

printf 'Logs: %s\n' "$LOG_DIR"
