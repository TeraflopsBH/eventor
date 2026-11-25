#!/usr/bin/env bash
# Run the CI browser smoke tests using the pinned browsers and OS libraries.
set -Eeuo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
playwright_image='mcr.microsoft.com/playwright:v1.56.1-noble@sha256:f1e7e01021efd65dd1a2c56064be399f3e4de00fd021ac561325f2bfbb2b837a'

case "${1:-}" in
  collaboration-grants)
    script='collaboration-grant-browser-smoke.mjs'
    base_url_env='EVENTOR_COLLABORATION_BROWSER_BASE_URL'
    ;;
  event-disruption-inbox)
    script='event-disruption-inbox-browser-smoke.mjs'
    base_url_env='EVENTOR_EVENT_INBOX_BROWSER_BASE_URL'
    ;;
  event-booking-links)
    script='event-booking-links-browser-smoke.mjs'
    base_url_env='EVENTOR_BOOKING_LINK_BROWSER_BASE_URL'
    ;;
  registry-relationship-merge)
    script='registry-relationship-merge-browser-smoke.mjs'
    base_url_env='EVENTOR_RELATIONSHIP_MERGE_BROWSER_BASE_URL'
    ;;
  registry-label-filter)
    script='registry-label-filter-browser-smoke.mjs'
    base_url_env='EVENTOR_LABEL_FILTER_BROWSER_BASE_URL'
    ;;
  registry-label-merge)
    script='registry-label-merge-browser-smoke.mjs'
    base_url_env='EVENTOR_LABEL_MERGE_BROWSER_BASE_URL'
    ;;
  event-guest-bulk-name-reset)
    script='event-guest-bulk-name-reset-browser-smoke.mjs'
    base_url_env='EVENTOR_BULK_NAME_RESET_BROWSER_BASE_URL'
    ;;
  event-rsvp-settings)
    script='event-rsvp-settings-browser-smoke.mjs'
    base_url_env='EVENTOR_RSVP_SETTINGS_BROWSER_BASE_URL'
    ;;
  workspace-access)
    script='workspace-access-browser-smoke.mjs'
    base_url_env='EVENTOR_WORKSPACE_BROWSER_BASE_URL'
    ;;
  registry-labels)
    script='registry-labels-browser-smoke.mjs'
    base_url_env='EVENTOR_REGISTRY_LABELS_BROWSER_BASE_URL'
    ;;
  staff-shell)
    script='staff-shell-browser-smoke.mjs'
    base_url_env='EVENTOR_STAFF_SHELL_BROWSER_BASE_URL'
    ;;
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
  event-guest-bulk-groups)
    script='event-guest-bulk-groups-browser-smoke.mjs'
    base_url_env='EVENTOR_BULK_GROUPS_BROWSER_BASE_URL'
    ;;
  registry-restoration)
    script='registry-restoration-browser-smoke.mjs'
    base_url_env='EVENTOR_RESTORATION_BROWSER_BASE_URL'
    ;;
  *)
    printf 'Usage: bash scripts/dev/run-browser-smoke.sh {collaboration-grants|event-disruption-inbox|event-booking-links|registry-label-filter|registry-relationship-merge|registry-label-merge|event-guest-bulk-name-reset|event-rsvp-settings|workspace-access|registry-labels|staff-shell|session|guest-invitation|organization-access|booking-disruption|public-booking-cancellation|registry-contact-merge|registry-reference-merge|registry-restoration|event-guest-bulk-groups}\n' >&2
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
