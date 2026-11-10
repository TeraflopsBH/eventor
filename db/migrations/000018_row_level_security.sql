-- Eventor migration 000018: 000018_row_level_security.sql
-- Apply only through scripts/db/apply-migrations.sh so the checksum ledger is updated.
BEGIN;
SET LOCAL search_path TO eogp, public;

SET LOCAL search_path TO eogp, public;

DO $rls$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT c.relname
      FROM pg_class c
      JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='eogp'
       AND c.relkind='r'
       AND EXISTS (
         SELECT 1 FROM pg_attribute a
          WHERE a.attrelid=c.oid AND a.attname='organization_id' AND NOT a.attisdropped
       )
  LOOP
    EXECUTE format('ALTER TABLE eogp.%I ENABLE ROW LEVEL SECURITY', r.relname);
    EXECUTE format('ALTER TABLE eogp.%I FORCE ROW LEVEL SECURITY', r.relname);
    EXECUTE format(
      'CREATE POLICY tenant_scope ON eogp.%I USING (organization_id = NULLIF(current_setting(''eogp.organization_id'', true), '''')::uuid) WITH CHECK (organization_id = NULLIF(current_setting(''eogp.organization_id'', true), '''')::uuid)',
      r.relname
    );
  END LOOP;
END
$rls$;

CREATE POLICY collaboration_grants_grantee_read
  ON eogp.collaboration_grants
  FOR SELECT
  USING (grantee_organization_id = NULLIF(current_setting('eogp.organization_id', true), '')::uuid);

CREATE POLICY booking_event_links_booking_owner_read
  ON eogp.booking_event_links
  FOR SELECT
  USING (booking_owner_organization_id = NULLIF(current_setting('eogp.organization_id', true), '')::uuid);

CREATE POLICY venue_snapshot_shares_grantee_read
  ON eogp.venue_snapshot_shares
  FOR SELECT
  USING (grantee_organization_id = NULLIF(current_setting('eogp.organization_id', true), '')::uuid);

GRANT USAGE ON SCHEMA eogp TO eogp_runtime, eogp_worker, eogp_readonly;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA eogp TO eogp_runtime;
GRANT SELECT ON ALL TABLES IN SCHEMA eogp TO eogp_readonly;
GRANT SELECT, INSERT, UPDATE ON
  eogp.outbox_events,
  eogp.background_jobs,
  eogp.invitation_deliveries,
  eogp.event_notification_delivery_attempts
TO eogp_worker;

REVOKE DELETE ON ALL TABLES IN SCHEMA eogp FROM eogp_runtime, eogp_worker, eogp_readonly;
REVOKE ALL ON eogp.schema_migrations FROM eogp_runtime, eogp_worker, eogp_readonly;
REVOKE UPDATE ON
  eogp.audit_events,
  eogp.booking_confirmed_snapshots,
  eogp.booking_status_history,
  eogp.booking_cancellation_decisions,
  eogp.booking_cancellation_effects,
  eogp.event_status_history,
  eogp.event_schedule_revisions,
  eogp.event_change_approval_decisions,
  eogp.event_decisions,
  eogp.event_decision_sessions,
  eogp.venue_space_revisions,
  eogp.invitation_revisions,
  eogp.invitation_deliveries,
  eogp.rsvp_responses,
  eogp.event_notification_recipients,
  eogp.event_notification_delivery_attempts,
  eogp.attendance_records,
  eogp.checkin_scan_records
FROM eogp_runtime, eogp_worker;

INSERT INTO eogp.schema_migrations(version, filename, checksum_sha256)
VALUES ('000018', '000018_row_level_security.sql', :'migration_checksum');
COMMIT;
