#!/usr/bin/env bash
# Host-only provisioning. Do not put passwords in arguments or exported variables.
set -Eeuo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ $# -eq 0 ]]; then
  node "$repo/apps/api/scripts/bootstrap-staff-account.mjs" --help
  exit 2
fi
if [[ -t 0 && " ${*} " != *" --help "* ]]; then
  IFS= read -rs -p 'Initial password: ' bootstrap_password
  printf '\n' >&2
  IFS= read -rs -p 'Confirm password: ' bootstrap_confirmation
  printf '\n' >&2
  trap 'unset bootstrap_password bootstrap_confirmation' EXIT
  [[ "$bootstrap_password" == "$bootstrap_confirmation" ]] || { printf 'Passwords do not match.\n' >&2;exit 1; }
  printf '%s' "$bootstrap_password" | node "$repo/apps/api/scripts/bootstrap-staff-account.mjs" "$@"
else
  node "$repo/apps/api/scripts/bootstrap-staff-account.mjs" "$@"
fi
