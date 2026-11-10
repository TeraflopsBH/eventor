-- Eventor migration 000002: 000002_authorization.sql
-- Apply only through scripts/db/apply-migrations.sh so the checksum ledger is updated.
BEGIN;
SET LOCAL search_path TO eogp, public;

SET LOCAL search_path TO eogp, public;

CREATE TABLE eogp.permissions (
  code        text PRIMARY KEY,
  description text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE eogp.roles (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id) ON DELETE RESTRICT,
  code            text NOT NULL,
  name            text NOT NULL,
  description     text,
  scope_type      text NOT NULL DEFAULT 'organization'
                  CHECK (scope_type IN ('organization','venue','space','event','station')),
  is_system       boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, code)
);

CREATE TABLE eogp.role_permissions (
  organization_id uuid NOT NULL,
  role_id         uuid NOT NULL,
  permission_code text NOT NULL REFERENCES eogp.permissions(code) ON DELETE RESTRICT,
  PRIMARY KEY (organization_id, role_id, permission_code),
  FOREIGN KEY (organization_id, role_id)
    REFERENCES eogp.roles(organization_id, id) ON DELETE CASCADE
);

CREATE TABLE eogp.user_role_grants (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  membership_id   uuid NOT NULL,
  role_id         uuid NOT NULL,
  scope_type      text NOT NULL DEFAULT 'organization'
                  CHECK (scope_type IN ('organization','venue','space','event','station')),
  scope_venue_id  uuid,
  scope_space_id  uuid,
  scope_event_id  uuid,
  scope_station_id uuid,
  granted_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at      timestamptz,
  revoked_at      timestamptz,
  FOREIGN KEY (organization_id, membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, role_id)
    REFERENCES eogp.roles(organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, id),
  CHECK (expires_at IS NULL OR expires_at > granted_at),
  CHECK (
    (scope_type = 'organization' AND num_nonnulls(scope_venue_id,scope_space_id,scope_event_id,scope_station_id)=0)
    OR (scope_type = 'venue' AND num_nonnulls(scope_venue_id,scope_space_id,scope_event_id,scope_station_id)=1 AND scope_venue_id IS NOT NULL)
    OR (scope_type = 'space' AND num_nonnulls(scope_venue_id,scope_space_id,scope_event_id,scope_station_id)=1 AND scope_space_id IS NOT NULL)
    OR (scope_type = 'event' AND num_nonnulls(scope_venue_id,scope_space_id,scope_event_id,scope_station_id)=1 AND scope_event_id IS NOT NULL)
    OR (scope_type = 'station' AND num_nonnulls(scope_venue_id,scope_space_id,scope_event_id,scope_station_id)=1 AND scope_station_id IS NOT NULL)
  )
);

INSERT INTO eogp.permissions(code,description) VALUES
('booking.inquiry.read','Read booking inquiries'),
('booking.inquiry.manage','Annotate and convert booking inquiries'),
('booking.draft.manage','Create and revise booking drafts'),
('booking.offer.issue','Issue booking offers'),
('booking.offer.approve','Approve offers and commercial exceptions'),
('booking.confirm','Confirm bookings and reserve resources'),
('booking.cancellation.request','Request booking cancellation'),
('booking.cancellation.review','Review booking cancellation requests'),
('booking.cancellation.approve','Approve or reject booking cancellation requests'),
('booking.cancellation.execute','Execute an effective booking cancellation'),
('booking.cancellation.override','Use emergency booking cancellation override'),
('booking.cancellation.commercial.read','Read cancellation financial consequences'),
('venue.manage','Manage venue and space inventory'),
('resource.manage','Manage resource inventory and reservations'),
('event.manage','Manage organizer-owned events'),
('event.capability.manage','Activate optional event capabilities'),
('event.responsibility.manage','Assign event task responsibility'),
('collaboration.grant.manage','Create, accept and revoke collaboration grants'),
('guest.read','Read organizer-owned guest information'),
('guest.manage','Manage guest registry and participation'),
('invitation.manage','Issue, revoke and reissue guest invitations'),
('rsvp.record','Record a staff-received RSVP'),
('rsvp.correct','Append an RSVP correction or late override'),
('event.cancellation.preview','Preview event cancellation effects'),
('event.cancellation.initiate','Initiate event cancellation or postponement'),
('event.cancellation.approve','Approve event change requests'),
('event.cancellation.execute','Execute approved event change requests'),
('event.cancellation.notifications.preview','Preview event notification audiences'),
('event.cancellation.notifications.send','Create/send event notification campaigns'),
('audit.read','Read permitted audit history')
ON CONFLICT (code) DO NOTHING;

INSERT INTO eogp.schema_migrations(version, filename, checksum_sha256)
VALUES ('000002', '000002_authorization.sql', :'migration_checksum');
COMMIT;
