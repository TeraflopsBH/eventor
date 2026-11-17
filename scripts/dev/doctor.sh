#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DETAILS=false
REMOTE=false
for argument in "$@"; do
  case "$argument" in
    --details) DETAILS=true ;;
    --remote) REMOTE=true ;;
    *) printf 'Usage: %s [--details] [--remote]\n' "$0" >&2; exit 2 ;;
  esac
done

pass_count=0
warn_count=0
fail_count=0

report() {
  local level="$1" name="$2" value="$3"
  printf '%-4s %-18s %s\n' "$level" "$name" "$value"
  case "$level" in
    PASS) ((pass_count += 1)) ;;
    WARN) ((warn_count += 1)) ;;
    FAIL) ((fail_count += 1)) ;;
  esac
}

version_or_missing() {
  local command_name="$1"
  if command -v "$command_name" >/dev/null 2>&1; then
    "$command_name" --version 2>&1 | head -n 1
  else
    printf 'missing'
  fi
}

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  case "${ID:-}:${ID_LIKE:-}" in
    zorin:*|ubuntu:*|debian:*|*:ubuntu*|*:debian*) report PASS os "${PRETTY_NAME:-Linux}" ;;
    *) report WARN os "${PRETTY_NAME:-Linux}; Zorin/Ubuntu is the supported local target" ;;
  esac
else
  report WARN os "unable to read /etc/os-release"
fi

architecture="$(uname -m)"
[[ "$architecture" == "x86_64" || "$architecture" == "aarch64" ]] \
  && report PASS architecture "$architecture" \
  || report WARN architecture "$architecture; verify Node/PostgreSQL image support"

cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || printf '0')"
((cpu_count >= 2)) && report PASS cpu "${cpu_count} logical CPUs" || report WARN cpu "${cpu_count} logical CPU; 2+ recommended"

memory_kib="$(awk '/MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || printf '0')"
memory_gib=$((memory_kib / 1024 / 1024))
((memory_gib >= 4)) && report PASS memory "${memory_gib} GiB" || report WARN memory "${memory_gib} GiB; 4+ recommended"

free_kib="$(df -Pk "$ROOT_DIR" | awk 'NR==2 {print $4}')"
free_gib=$((free_kib / 1024 / 1024))
((free_gib >= 10)) && report PASS disk "${free_gib} GiB free" || report WARN disk "${free_gib} GiB free; 10+ recommended"

for required_command in bash git curl openssl sha256sum node npm docker; do
  if command -v "$required_command" >/dev/null 2>&1; then
    report PASS "$required_command" "$(version_or_missing "$required_command")"
  else
    report FAIL "$required_command" missing
  fi
done

node_version="$(node --version 2>/dev/null || true)"
[[ "$node_version" == "v22.16.0" ]] \
  && report PASS node-parity "matches CI v22.16.0" \
  || report WARN node-parity "${node_version:-missing}; CI uses v22.16.0"

if command -v python3 >/dev/null 2>&1; then
  python_version="$(python3 --version 2>&1)"
  [[ "$python_version" == Python\ 3.12.* ]] \
    && report PASS python "$python_version" \
    || report WARN python "$python_version; CI uses Python 3.12"
  if python3 -c 'import venv' >/dev/null 2>&1; then
    report PASS python-venv available
  else
    report WARN python-venv "missing; scripts/dev/setup.sh cannot create its isolated environment"
  fi
else
  report WARN python "missing; needed for full OpenAPI parity"
fi

if docker compose version >/dev/null 2>&1; then
  report PASS compose "$(docker compose version --short)"
else
  report FAIL compose "Docker Compose v2 is unavailable"
fi

if docker info >/dev/null 2>&1; then
  report PASS docker-daemon running
else
  report FAIL docker-daemon "unavailable to the current user"
fi

if [[ -d "$ROOT_DIR/.git" ]]; then
  branch="$(git -C "$ROOT_DIR" branch --show-current)"
  remote="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)"
  [[ "$remote" == *"TeraflopsBH/eventor"* ]] \
    && report PASS repository "${branch:-detached}; official origin" \
    || report WARN repository "${branch:-detached}; check origin ${remote:-missing}"
  if [[ -n "$(git -C "$ROOT_DIR" status --short)" ]]; then
    report WARN worktree "local changes present; preserve them before switching/resetting"
  else
    report PASS worktree clean
  fi
  if $REMOTE; then
    remote_main="$(git -C "$ROOT_DIR" ls-remote origin refs/heads/main 2>/dev/null | awk 'NR==1 {print $1}')"
    local_main="$(git -C "$ROOT_DIR" show-ref --verify --hash refs/heads/main 2>/dev/null || true)"
    if [[ -n "$remote_main" && "$local_main" == "$remote_main" ]]; then
      report PASS main-sync "local main matches origin at ${local_main:0:12}"
    elif [[ -z "$remote_main" ]]; then
      report WARN main-sync "unable to read origin/main"
    elif [[ -z "$local_main" ]]; then
      report WARN main-sync "local main branch is absent; remote main is ${remote_main:0:12}"
    else
      report WARN main-sync "local ${local_main:0:12} differs from remote ${remote_main:0:12}; inspect before updating"
    fi
  fi
else
  report FAIL repository "$ROOT_DIR is not a Git checkout"
fi

if command -v ss >/dev/null 2>&1; then
  for port in 5173 8080 55432; do
    if ss -H -ltn "sport = :$port" 2>/dev/null | grep -q .; then
      report WARN "port-$port" "already in use"
    else
      report PASS "port-$port" available
    fi
  done
fi

if $DETAILS; then
  printf '\nRepository: %s\nNode pin:  %s\n' "$ROOT_DIR" "$(cat "$ROOT_DIR/.node-version")"
fi

printf '\nSummary: %d pass, %d warning, %d failure\n' "$pass_count" "$warn_count" "$fail_count"
((fail_count == 0))
