#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STATE_DIR="$ROOT_DIR/.eventor-dev"
CACHE_DIR="$STATE_DIR/npm-cache"
VENV_DIR="$STATE_DIR/venv"

mkdir -p "$CACHE_DIR"

run_logged() {
  local label="$1" log_name="$2"
  shift 2
  local log_file="$STATE_DIR/logs/$log_name.log"
  mkdir -p "$STATE_DIR/logs"
  if "$@" >"$log_file" 2>&1; then
    printf 'PASS %s\n' "$label"
  else
    printf 'FAIL %s (log: %s)\n' "$label" "$log_file" >&2
    tail -n 80 "$log_file" >&2
    return 1
  fi
}

expected_node="v$(cat "$ROOT_DIR/.node-version")"
actual_node="$(node --version 2>/dev/null || true)"
if [[ "$actual_node" != "$expected_node" ]]; then
  printf 'Expected Node %s; found %s. Activate .nvmrc/.node-version first.\n' "$expected_node" "${actual_node:-missing}" >&2
  exit 1
fi

run_logged "API dependencies" setup-api \
  npm --prefix "$ROOT_DIR/apps/api" ci --cache "$CACHE_DIR" --no-audit --no-fund
run_logged "Staff-web dependencies" setup-staff \
  npm --prefix "$ROOT_DIR/apps/staff-web" ci --cache "$CACHE_DIR" --no-audit --no-fund

if command -v python3 >/dev/null 2>&1; then
  python3 -m venv "$VENV_DIR"
  run_logged "Python contract tools" setup-python \
    "$VENV_DIR/bin/python" -m pip install --disable-pip-version-check -r "$ROOT_DIR/requirements-dev.txt"
else
  printf 'Python is missing; JavaScript development works, but full OpenAPI parity is unavailable.\n' >&2
fi

printf 'Setup complete. Next: scripts/dev/db.sh up && scripts/dev/check.sh quick\nLogs: %s\n' "$STATE_DIR/logs"
