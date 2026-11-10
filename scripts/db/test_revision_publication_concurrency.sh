#!/usr/bin/env bash
set -Eeuo pipefail

: "${DATABASE_URL_RUNTIME:?Set DATABASE_URL_RUNTIME to the eventor_runtime PostgreSQL connection string}"
command -v psql >/dev/null 2>&1 || { echo "psql is required" >&2; exit 127; }

ORG="10000000-0000-0000-0000-00000000000a"
REVISION="c1000000-0000-4000-8000-000000000001"
LAYER="c2000000-0000-4000-8000-000000000001"
READY_LOCK_CLASSID=18541
READY_LOCK_OBJID=26027
TMP_DIR="$(mktemp -d)"
PUBLISHER_PID=""
CHILD_PID=""
PUBLISHER_PIPE_OPEN=0

cleanup() {
  if [[ "$PUBLISHER_PIPE_OPEN" -eq 1 ]]; then
    exec 3>&-
    PUBLISHER_PIPE_OPEN=0
  fi
  if [[ -n "$CHILD_PID" ]] && kill -0 "$CHILD_PID" 2>/dev/null; then
    kill "$CHILD_PID" 2>/dev/null || true
    wait "$CHILD_PID" 2>/dev/null || true
  fi
  if [[ -n "$PUBLISHER_PID" ]] && kill -0 "$PUBLISHER_PID" 2>/dev/null; then
    kill "$PUBLISHER_PID" 2>/dev/null || true
    wait "$PUBLISHER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Use an existing space from the committed tenant-isolation fixture, but create
# a separate draft revision so this race test is isolated and repeatable.
psql "$DATABASE_URL_RUNTIME" -X -v ON_ERROR_STOP=1 -qAt <<SQL
BEGIN;
SET LOCAL app.organization_id TO '$ORG';
INSERT INTO eogp.venue_space_revisions
  (id, organization_id, venue_space_id, revision_number,
   geometry, semantic_snapshot, content_sha256)
VALUES
  ('$REVISION', '$ORG', '70000000-0000-4000-8000-00000000000a', 3,
   '{}'::jsonb, '{"label":"CI concurrent publication revision"}'::jsonb,
   repeat('a',64));
COMMIT;
SQL

# The publisher takes the parent-row UPDATE lock, then advertises readiness via
# a transaction advisory lock and waits for the test controller to send COMMIT.
# A named pipe lets the controller release it only after the child INSERT is
# observed waiting on the parent's row lock.
mkfifo "$TMP_DIR/publisher.fifo"
PGAPPNAME=ci_revision_publisher psql "$DATABASE_URL_RUNTIME" \
  -X -v ON_ERROR_STOP=1 -qAt \
  <"$TMP_DIR/publisher.fifo" >"$TMP_DIR/publisher.log" 2>&1 &
PUBLISHER_PID=$!
exec 3>"$TMP_DIR/publisher.fifo"
PUBLISHER_PIPE_OPEN=1

cat >&3 <<SQL
BEGIN;
SET LOCAL app.organization_id TO '$ORG';
UPDATE eogp.venue_space_revisions
   SET published_at = clock_timestamp()
 WHERE organization_id = '$ORG'
   AND id = '$REVISION'
   AND published_at IS NULL;
SELECT pg_advisory_xact_lock($READY_LOCK_CLASSID, $READY_LOCK_OBJID);
\! touch '$TMP_DIR/publisher_ready'
SQL

ready=0
for _ in $(seq 1 100); do
  if [[ -f "$TMP_DIR/publisher_ready" ]]; then
    ready=1
    break
  fi
  if ! kill -0 "$PUBLISHER_PID" 2>/dev/null; then
    break
  fi
  sleep 0.05
done
if [[ "$ready" -ne 1 ]]; then
  echo "Publisher did not acquire the revision row lock and signal readiness."
  cat "$TMP_DIR/publisher.log"
  exit 1
fi

PGAPPNAME=ci_revision_child_insert psql "$DATABASE_URL_RUNTIME" \
  -X -v ON_ERROR_STOP=1 -qAt >"$TMP_DIR/child.log" 2>&1 <<SQL &
BEGIN;
SET LOCAL app.organization_id TO '$ORG';
INSERT INTO eogp.spatial_layers
  (id, organization_id, venue_space_revision_id, code, label, layer_kind)
VALUES
  ('$LAYER', '$ORG', '$REVISION',
   'CI-PUBLISH-RACE','CI publication race layer','zones');
COMMIT;
SQL
CHILD_PID=$!

blocked=0
for _ in $(seq 1 100); do
  waiting="$(psql "$DATABASE_URL_RUNTIME" -X -qAt -v ON_ERROR_STOP=1 -c "
    SELECT EXISTS (
      SELECT 1
        FROM pg_stat_activity
       WHERE application_name = 'ci_revision_child_insert'
         AND state = 'active'
         AND wait_event_type = 'Lock'
    );
  ")"
  if [[ "$waiting" == "t" ]]; then
    blocked=1
    break
  fi
  if ! kill -0 "$CHILD_PID" 2>/dev/null; then
    break
  fi
  sleep 0.05
done

# Publish only after determining whether the child INSERT correctly waits.
printf '%s\n' 'COMMIT;' >&3
exec 3>&-
PUBLISHER_PIPE_OPEN=0

if wait "$PUBLISHER_PID"; then
  publisher_status=0
else
  publisher_status=$?
fi
PUBLISHER_PID=""

if wait "$CHILD_PID"; then
  child_status=0
else
  child_status=$?
fi
CHILD_PID=""

if [[ "$publisher_status" -ne 0 ]]; then
  echo "Revision publication transaction failed."
  cat "$TMP_DIR/publisher.log"
  exit 1
fi

if [[ "$blocked" -ne 1 ]]; then
  echo "Child INSERT did not wait for the in-flight publication row lock."
  cat "$TMP_DIR/child.log"
  exit 1
fi

if [[ "$child_status" -eq 0 ]]; then
  echo "Child INSERT succeeded after publication; the parent lock did not serialize the race."
  cat "$TMP_DIR/child.log"
  exit 1
fi

if ! grep -q "children of published revision" "$TMP_DIR/child.log"; then
  echo "Child INSERT failed for a reason other than the published-parent guard."
  cat "$TMP_DIR/child.log"
  exit 1
fi

published_count="$(psql "$DATABASE_URL_RUNTIME" -X -qAt -v ON_ERROR_STOP=1 -c "
  SELECT count(*)
    FROM eogp.venue_space_revisions
   WHERE organization_id = '$ORG'
     AND id = '$REVISION'
     AND published_at IS NOT NULL;
")"
child_count="$(psql "$DATABASE_URL_RUNTIME" -X -qAt -v ON_ERROR_STOP=1 -c "
  SELECT count(*)
    FROM eogp.spatial_layers
   WHERE organization_id = '$ORG'
     AND id = '$LAYER';
")"

if [[ "$published_count" != "1" || "$child_count" != "0" ]]; then
  echo "Unexpected final race state: published revisions=$published_count, child rows=$child_count."
  cat "$TMP_DIR/child.log"
  exit 1
fi

echo "Concurrent revision publication test passed: child INSERT waited, then was rejected after publication committed."
