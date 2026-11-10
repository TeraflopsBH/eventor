-- Tenant RLS, runtime privileges, append-only protection and worker grants.
-- app.organization_id must be set transaction-locally after the API authorizes the caller.

DO $block$
DECLARE
  item record;
BEGIN
  FOR item IN
    SELECT table_name
      FROM information_schema.columns
     WHERE table_schema = 'eogp'
       AND column_name = 'organization_id'
       AND is_nullable = 'NO'
     GROUP BY table_name
     ORDER BY table_name
  LOOP
    EXECUTE format('ALTER TABLE eogp.%I ENABLE ROW LEVEL SECURITY', item.table_name);
    EXECUTE format('ALTER TABLE eogp.%I FORCE ROW LEVEL SECURITY', item.table_name);
    EXECUTE format(
      'CREATE POLICY tenant_isolation ON eogp.%I USING (organization_id = eogp.current_organization_id()) WITH CHECK (organization_id = eogp.current_organization_id())',
      item.table_name
    );
  END LOOP;
END;
$block$;

ALTER TABLE eogp.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.organizations FORCE ROW LEVEL SECURITY;
CREATE POLICY organization_self_access ON eogp.organizations
  USING (id = eogp.current_organization_id())
  WITH CHECK (id = eogp.current_organization_id());

-- Users are global authentication identities, not tenant-owned rows. The API must
-- query them through the authentication service and scope profile projections separately.
ALTER TABLE eogp.users DISABLE ROW LEVEL SECURITY;

-- A grant is visible to both parties, but business authorization still decides who may accept/revoke it.
DROP POLICY tenant_isolation ON eogp.collaboration_grants;
CREATE POLICY collaboration_grant_parties ON eogp.collaboration_grants
  USING (
    organization_id = eogp.current_organization_id()
    OR grantee_organization_id = eogp.current_organization_id()
  )
  WITH CHECK (
    organization_id = eogp.current_organization_id()
    OR grantee_organization_id = eogp.current_organization_id()
  );

-- Event-owned association is visible to the event owner and booking owner; field projections remain service-controlled.
DROP POLICY tenant_isolation ON eogp.booking_event_links;
CREATE POLICY booking_event_link_parties ON eogp.booking_event_links
  USING (
    organization_id = eogp.current_organization_id()
    OR booking_owner_organization_id = eogp.current_organization_id()
  )
  WITH CHECK (organization_id = eogp.current_organization_id());

CREATE FUNCTION eogp.reject_append_only_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  RAISE EXCEPTION 'table %.% is append-only', TG_TABLE_SCHEMA, TG_TABLE_NAME
    USING ERRCODE = '55000';
END;
$function$;

DO $block$
DECLARE
  table_name text;
  append_only_tables text[] := ARRAY[
    'audit_events',
    'booking_confirmed_snapshots',
    'booking_approvals',
    'booking_status_history',
    'booking_cancellation_decisions',
    'event_schedule_revisions',
    'collaboration_grant_revisions',
    'event_venue_snapshots',
    'event_venue_snapshot_layers',
    'event_venue_snapshot_objects',
    'event_venue_snapshot_resources',
    'event_change_approval_decisions',
    'event_decisions',
    'event_status_history',
    'participation_status_history',
    'rsvp_responses',
    'attendance_records',
    'event_notification_delivery_attempts',
    'event_prerequisite_status_history'
  ];
BEGIN
  FOREACH table_name IN ARRAY append_only_tables LOOP
    EXECUTE format(
      'CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON eogp.%I FOR EACH ROW EXECUTE FUNCTION eogp.reject_append_only_mutation()',
      table_name || '_append_only_guard', table_name
    );
  END LOOP;
END;
$block$;

REVOKE ALL ON SCHEMA eogp FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA eogp FROM PUBLIC;
GRANT USAGE ON SCHEMA eogp TO eventor_runtime, eventor_worker;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA eogp TO eventor_runtime;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA eogp TO eventor_runtime;

GRANT SELECT ON eogp.permissions TO eventor_runtime, eventor_worker;
REVOKE INSERT, UPDATE, DELETE ON eogp.permissions, eogp.schema_migrations FROM eventor_runtime, eventor_worker;
GRANT SELECT, UPDATE ON eogp.outbox_events, eogp.background_jobs TO eventor_worker;
GRANT SELECT, INSERT, UPDATE ON eogp.invitation_deliveries TO eventor_worker;
GRANT SELECT, INSERT, UPDATE ON eogp.event_notification_recipients TO eventor_worker;
GRANT SELECT, INSERT ON eogp.event_notification_delivery_attempts TO eventor_worker;
GRANT SELECT ON eogp.invitation_revisions, eogp.notification_template_revisions TO eventor_worker;

REVOKE INSERT, UPDATE, DELETE ON eogp.resource_reservations FROM eventor_runtime, eventor_worker;
GRANT SELECT ON eogp.resource_reservations TO eventor_runtime, eventor_worker;
GRANT EXECUTE ON FUNCTION eogp.reserve_pooled_resource(uuid,uuid,uuid,uuid,uuid,timestamptz,timestamptz,integer,timestamptz,text)
  TO eventor_runtime;

REVOKE UPDATE, DELETE ON
  eogp.audit_events,
  eogp.booking_confirmed_snapshots,
  eogp.booking_approvals,
  eogp.booking_status_history,
  eogp.booking_cancellation_decisions,
  eogp.event_schedule_revisions,
  eogp.collaboration_grant_revisions,
  eogp.event_venue_snapshots,
  eogp.event_venue_snapshot_layers,
  eogp.event_venue_snapshot_objects,
  eogp.event_venue_snapshot_resources,
  eogp.event_change_approval_decisions,
  eogp.event_decisions,
  eogp.event_status_history,
  eogp.participation_status_history,
  eogp.rsvp_responses,
  eogp.attendance_records,
  eogp.event_notification_delivery_attempts,
  eogp.event_prerequisite_status_history
FROM eventor_runtime, eventor_worker;

ALTER DEFAULT PRIVILEGES FOR ROLE eventor_owner IN SCHEMA eogp
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO eventor_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE eventor_owner IN SCHEMA eogp
  GRANT USAGE, SELECT ON SEQUENCES TO eventor_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE eventor_owner IN SCHEMA eogp
  REVOKE ALL ON TABLES FROM PUBLIC;

