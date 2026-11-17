#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT_DIR/.eventor-dev/dev.env"
mode="${1:-}"

case "$mode" in
  web)
    exec npm --prefix "$ROOT_DIR/apps/staff-web" run dev -- --host 127.0.0.1
    ;;
  api|api-debug|worker)
    "$ROOT_DIR/scripts/dev/db.sh" up >/dev/null 2>&1
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
    npm --prefix "$ROOT_DIR/apps/api" run build
    case "$mode" in
      api) exec npm --prefix "$ROOT_DIR/apps/api" run start ;;
      api-debug) exec node --enable-source-maps --inspect=127.0.0.1:9229 "$ROOT_DIR/apps/api/dist/src/main.js" ;;
      worker) exec npm --prefix "$ROOT_DIR/apps/api" run start:worker ;;
    esac
    ;;
  *)
    printf 'Usage: %s {web|api|api-debug|worker}\n' "$0" >&2
    exit 2
    ;;
esac
