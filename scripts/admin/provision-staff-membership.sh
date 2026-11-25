#!/usr/bin/env bash
# Host-only provisioning of an existing account's new organization membership.
set -Eeuo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if [[ $# -eq 0 ]]; then
  node "$repo/apps/api/scripts/provision-staff-membership.mjs" --help
  exit 2
fi
exec node "$repo/apps/api/scripts/provision-staff-membership.mjs" "$@"
