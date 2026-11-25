#!/usr/bin/env bash
# Isolated synthetic acceptance; never select the default development project.
set -Eeuo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
umask 077
mkdir -p "$repo/.eventor-dev"
export EVENTOR_DEV_STATE_DIR="$(mktemp -d "$repo/.eventor-dev/database-lifecycle.XXXXXX")"
export EVENTOR_DEV_PROJECT_NAME="eventor-lifecycle-$(basename "$EVENTOR_DEV_STATE_DIR" | tr '[:upper:]' '[:lower:]' | tr '.' '-')"
export EVENTOR_DEV_POSTGRES_PORT="$(python3 - <<'PY'
import socket
with socket.socket() as sock:
    sock.bind(('127.0.0.1',0));print(sock.getsockname()[1])
PY
)"
[[ "$EVENTOR_DEV_PROJECT_NAME" == eventor-lifecycle-* ]] || exit 2
compose() { docker compose --project-name "$EVENTOR_DEV_PROJECT_NAME" --env-file "$EVENTOR_DEV_STATE_DIR/dev.env" --file "$repo/compose.dev.yaml" "$@"; }
cleanup() { if [[ -f "$EVENTOR_DEV_STATE_DIR/dev.env" ]]; then compose down --volumes > "$EVENTOR_DEV_STATE_DIR/cleanup.log" 2>&1 || true;fi; }
trap cleanup EXIT
if EVENTOR_DEV_STATE_DIR="$EVENTOR_DEV_STATE_DIR/invalid-port" EVENTOR_DEV_POSTGRES_PORT=65536 bash "$repo/scripts/dev/db.sh" env > "$EVENTOR_DEV_STATE_DIR/invalid-port.log" 2>&1;then printf 'Invalid port accepted.\n' >&2;exit 1;fi
if EVENTOR_DEV_PROJECT_NAME=Invalid bash "$repo/scripts/dev/db.sh" status > "$EVENTOR_DEV_STATE_DIR/invalid-project.log" 2>&1;then printf 'Invalid project accepted.\n' >&2;exit 1;fi
bash "$repo/scripts/dev/db.sh" up > "$EVENTOR_DEV_STATE_DIR/up.log" 2>&1
[[ "$(grep -c ":$EVENTOR_DEV_POSTGRES_PORT/eventor" "$EVENTOR_DEV_STATE_DIR/dev.env")" -eq 4 ]]
compose exec -T postgres psql -U postgres -d eventor -v ON_ERROR_STOP=1 <<'SQL'
CREATE TABLE public.eventor_development_retention_probe(value text NOT NULL);
INSERT INTO public.eventor_development_retention_probe VALUES('synthetic-retention-proof');
SQL
bash "$repo/scripts/dev/db.sh" down > "$EVENTOR_DEV_STATE_DIR/down.log" 2>&1
container="$(compose ps --all -q postgres)"
[[ -n "$container" && "$(docker inspect --format '{{.State.Running}}' "$container")" == false ]]
docker volume inspect "${EVENTOR_DEV_PROJECT_NAME}_eventor-dev-postgres" >/dev/null
backups=("$EVENTOR_DEV_STATE_DIR"/backups/*.dump)
[[ ${#backups[@]} -eq 1 && -s "${backups[0]}" && "$(stat -c '%a' "${backups[0]}")" == 600 && "$(stat -c '%a' "$EVENTOR_DEV_STATE_DIR/backups")" == 700 ]]
bash "$repo/scripts/dev/db.sh" down >> "$EVENTOR_DEV_STATE_DIR/down.log" 2>&1
bash "$repo/scripts/dev/db.sh" up > "$EVENTOR_DEV_STATE_DIR/restart.log" 2>&1
[[ "$(compose exec -T postgres psql -U postgres -d eventor -Atqc 'SELECT value FROM public.eventor_development_retention_probe')" == synthetic-retention-proof ]]
compose exec -T postgres createdb -U postgres eventor_lifecycle_restore
compose exec -T postgres pg_restore -U postgres --exit-on-error -d eventor_lifecycle_restore < "${backups[0]}" > "$EVENTOR_DEV_STATE_DIR/restore.log" 2>&1
[[ "$(compose exec -T postgres psql -U postgres -d eventor_lifecycle_restore -Atqc 'SELECT value FROM public.eventor_development_retention_probe')" == synthetic-retention-proof ]]
# A failed backup must leave the database running.
mv "$EVENTOR_DEV_STATE_DIR/backups" "$EVENTOR_DEV_STATE_DIR/backups-saved"
touch "$EVENTOR_DEV_STATE_DIR/backups"
if bash "$repo/scripts/dev/db.sh" down > "$EVENTOR_DEV_STATE_DIR/failed-backup.log" 2>&1;then printf 'Shutdown unexpectedly ignored failed backup.\n' >&2;exit 1;fi
[[ "$(docker inspect --format '{{.State.Running}}' "$container")" == true ]]
rm "$EVENTOR_DEV_STATE_DIR/backups"
mv "$EVENTOR_DEV_STATE_DIR/backups-saved" "$EVENTOR_DEV_STATE_DIR/backups"
printf 'PASS isolated database shutdown/restart, persistent volume, protected backup, actual restore and failed-backup refusal. Receipts: %s\n' "$EVENTOR_DEV_STATE_DIR"
