#!/usr/bin/env bash
# Run the CI browser smoke tests using the pinned browsers and OS libraries.
set -Eeuo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
playwright_image='mcr.microsoft.com/playwright:v1.56.1-noble@sha256:f1e7e01021efd65dd1a2c56064be399f3e4de00fd021ac561325f2bfbb2b837a'

case "${1:-}" in
  session)
    script='session-browser-smoke.mjs'
    base_url_env='EVENTOR_BROWSER_BASE_URL'
    ;;
  guest-invitation)
    script='guest-invitation-browser-smoke.mjs'
    base_url_env='EVENTOR_GUEST_BROWSER_BASE_URL'
    ;;
  organization-access)
    script='organization-access-browser-smoke.mjs'
    base_url_env='EVENTOR_ACCESS_BROWSER_BASE_URL'
    ;;
  booking-disruption)
    script='booking-disruption-browser-smoke.mjs'
    base_url_env='EVENTOR_DISRUPTION_BROWSER_BASE_URL'
    ;;
  public-booking-cancellation)
    script='public-booking-cancellation-browser-smoke.mjs'
    base_url_env='EVENTOR_CANCELLATION_BROWSER_BASE_URL'
    ;;
  registry-contact-merge)
    script='registry-contact-merge-browser-smoke.mjs'
    base_url_env='EVENTOR_CONTACT_MERGE_BROWSER_BASE_URL'
    ;;
  registry-reference-merge)
    script='registry-reference-merge-browser-smoke.mjs'
    base_url_env='EVENTOR_REFERENCE_MERGE_BROWSER_BASE_URL'
    ;;
  *)
    printf 'Usage: bash scripts/dev/run-browser-smoke.sh {session|guest-invitation|organization-access|booking-disruption|public-booking-cancellation|registry-contact-merge|registry-reference-merge}\n' >&2
    exit 2
    ;;
esac

browser_env=()
if [[ -v "$base_url_env" ]]; then
  browser_env=(--env "$base_url_env=${!base_url_env}")
fi

docker run --rm --init --network host --shm-size=256m \
  --user pwuser --cap-drop ALL --security-opt no-new-privileges \
  --mount "type=bind,source=$repo/apps/api/scripts,target=/work/scripts,readonly" \
  --mount "type=bind,source=$repo/apps/api/node_modules,target=/work/node_modules,readonly" \
  --workdir /work --env HOME=/home/pwuser "${browser_env[@]}" \
  "$playwright_image" node "scripts/$script"
