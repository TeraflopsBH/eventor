-- Eventor migration 000017: 000017_integrity_hardening.sql
-- Apply only through scripts/db/apply-migrations.sh so the checksum ledger is updated.
BEGIN;
SET LOCAL search_path TO eogp, public;

SET LOCAL search_path TO eogp, public;

CREATE FUNCTION eogp.reject_immutable_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = eogp, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'Table %.% is append-only; % is not permitted', TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_OP
    USING ERRCODE = '55000';
END;
$$;

DO $immutable$
DECLARE
  t text;
  tables text[] := ARRAY[
    'audit_events',
    'booking_confirmed_snapshots',
    'booking_inquiries',
    'booking_draft_revisions',
    'booking_status_history',
    'booking_cancellation_decisions',
    'booking_cancellation_effects',
    'booking_disruption_notices',
    'event_status_history',
    'event_schedule_revisions',
    'event_change_approval_decisions',
    'event_decisions',
    'event_decision_sessions',
    'event_venue_snapshots',
    'event_venue_snapshot_layers',
    'collaboration_grant_revisions',
    'venue_space_revisions',
    'invitation_revisions',
    'invitation_deliveries',
    'rsvp_responses',
    'event_notification_delivery_attempts',
    'attendance_records',
    'checkin_scan_records'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE OR DELETE ON eogp.%I FOR EACH ROW EXECUTE FUNCTION eogp.reject_immutable_mutation()', t || '_immutable_trg', t);
  END LOOP;
END
$immutable$;

CREATE INDEX booking_inquiries_inbox_idx
  ON eogp.booking_inquiries(organization_id, status, submitted_at DESC);
CREATE INDEX booking_records_calendar_idx
  ON eogp.booking_records(organization_id, venue_id, status, confirmed_at DESC);
CREATE INDEX booking_cancellation_requests_queue_idx
  ON eogp.booking_cancellation_requests(organization_id, status, submitted_at);
CREATE INDEX booking_disruption_notices_booking_idx
  ON eogp.booking_disruption_notices(organization_id, booking_id, issued_at DESC);
CREATE INDEX event_participations_event_status_idx
  ON eogp.event_participations(organization_id, event_id, status);
CREATE INDEX invitations_event_status_idx
  ON eogp.invitations(organization_id, event_id, status);
CREATE INDEX event_change_requests_queue_idx
  ON eogp.event_change_requests(organization_id, status, requested_at);
CREATE INDEX event_notification_campaigns_status_idx
  ON eogp.event_notification_campaigns(organization_id, status, created_at DESC);
CREATE INDEX outbox_events_pending_idx
  ON eogp.outbox_events(available_at, occurred_at)
  WHERE published_at IS NULL;
CREATE INDEX background_jobs_pending_idx
  ON eogp.background_jobs(available_at, created_at)
  WHERE status='queued';
CREATE INDEX audit_events_entity_history_idx
  ON eogp.audit_events(organization_id, entity_type, entity_id, occurred_at DESC);
CREATE INDEX collaboration_grants_grantee_idx
  ON eogp.collaboration_grants(grantee_organization_id, status, valid_until);
CREATE INDEX booking_event_links_booking_idx
  ON eogp.booking_event_links(booking_owner_organization_id, booking_id, link_status);
CREATE INDEX event_notification_recipients_status_idx
  ON eogp.event_notification_recipients(organization_id, campaign_id, status);
CREATE INDEX event_notification_delivery_attempts_pending_idx
  ON eogp.event_notification_delivery_attempts(organization_id, created_at)
  WHERE status IN ('queued','failed');

CREATE FUNCTION eogp.enforce_discrete_resource_line()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = eogp, pg_temp
AS $$
DECLARE
  v_unit_pool uuid;
  v_mode text;
  v_line_pool uuid;
  v_unit_status text;
BEGIN
  IF NEW.resource_unit_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT pool_id, status INTO v_unit_pool, v_unit_status
    FROM eogp.resource_units
   WHERE organization_id = NEW.organization_id AND id = NEW.resource_unit_id;

  SELECT reservation_mode INTO v_mode
    FROM eogp.resource_pools
   WHERE organization_id = NEW.organization_id AND id = v_unit_pool;

  SELECT resource_pool_id INTO v_line_pool
    FROM eogp.booking_resource_lines
   WHERE organization_id = NEW.organization_id AND id = NEW.booking_resource_line_id;

  IF v_unit_status <> 'active' OR v_mode <> 'discrete' OR v_line_pool IS DISTINCT FROM v_unit_pool THEN
    RAISE EXCEPTION 'Discrete unit must be active, belong to a discrete pool and match the booking line'
      USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER resource_reservations_unit_validation_trg
BEFORE INSERT OR UPDATE OF resource_unit_id, booking_resource_line_id
ON eogp.resource_reservations
FOR EACH ROW
EXECUTE FUNCTION eogp.enforce_discrete_resource_line();

COMMENT ON TABLE eogp.booking_records IS
  'Venue-provider-owned confirmed booking. Does not create or imply an operational event.';
COMMENT ON TABLE eogp.event_participations IS
  'Organizer-owned event participation. RSVP responses and physical attendance are separate relations.';
COMMENT ON TABLE eogp.booking_event_links IS
  'Explicit cross-organization booking/event association; never grants access by itself.';
COMMENT ON TABLE eogp.event_venue_snapshots IS
  'Immutable event-owned copy of a provider-approved venue revision with grant provenance.';
COMMENT ON TABLE eogp.event_notification_recipients IS
  'Fixed recipient snapshot with encrypted contact point; never place plaintext contact details in audit/outbox payloads.';

INSERT INTO eogp.schema_migrations(version, filename, checksum_sha256)
VALUES ('000017', '000017_integrity_hardening.sql', :'migration_checksum');
COMMIT;

CREATE FUNCTION eogp.guard_notification_recipient_snapshot()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = eogp, pg_temp
AS $$
BEGIN
  IF ROW(NEW.organization_id, NEW.campaign_id, NEW.event_id, NEW.participation_id,
         NEW.channel, NEW.qualification_code, NEW.contact_snapshot_ciphertext,
         NEW.contact_snapshot_key_id, NEW.locale, NEW.created_at)
     IS DISTINCT FROM
     ROW(OLD.organization_id, OLD.campaign_id, OLD.event_id, OLD.participation_id,
         OLD.channel, OLD.qualification_code, OLD.contact_snapshot_ciphertext,
         OLD.contact_snapshot_key_id, OLD.locale, OLD.created_at) THEN
    RAISE EXCEPTION 'Notification recipient snapshot fields are immutable'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER event_notification_recipient_snapshot_immutable_trg
BEFORE UPDATE ON eogp.event_notification_recipients
FOR EACH ROW EXECUTE FUNCTION eogp.guard_notification_recipient_snapshot();

CREATE FUNCTION eogp.guard_booking_offer_terms()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = eogp, pg_temp
AS $$
BEGIN
  IF ROW(NEW.organization_id, NEW.draft_revision_id, NEW.revision_no, NEW.currency,
         NEW.tax_basis, NEW.total_amount, NEW.terms_snapshot, NEW.valid_until, NEW.created_at)
     IS DISTINCT FROM
     ROW(OLD.organization_id, OLD.draft_revision_id, OLD.revision_no, OLD.currency,
         OLD.tax_basis, OLD.total_amount, OLD.terms_snapshot, OLD.valid_until, OLD.created_at) THEN
    RAISE EXCEPTION 'Issued booking offer terms are immutable; issue a replacement offer revision'
      USING ERRCODE = '55000';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER booking_offer_terms_immutable_trg
BEFORE UPDATE ON eogp.booking_offers
FOR EACH ROW EXECUTE FUNCTION eogp.guard_booking_offer_terms();
