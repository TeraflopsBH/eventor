-- Permission catalogue and organization-scoped roles.
CREATE TABLE eogp.permissions (
    code text PRIMARY KEY,
    description text NOT NULL,
    scope_kind text NOT NULL
      CHECK (scope_kind IN ('platform','organization','venue','space','booking','event','task')),
    is_sensitive boolean NOT NULL DEFAULT false
);

CREATE TABLE eogp.roles (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    code text NOT NULL,
    name text NOT NULL,
    description text,
    scope_kind text NOT NULL DEFAULT 'organization'
      CHECK (scope_kind IN ('organization','venue','space','booking','event','task')),
    is_system_preset boolean NOT NULL DEFAULT false,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, code)
);

CREATE TABLE eogp.role_permissions (
    organization_id uuid NOT NULL,
    role_id uuid NOT NULL,
    permission_code text NOT NULL REFERENCES eogp.permissions(code),
    granted_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    PRIMARY KEY (organization_id, role_id, permission_code),
    FOREIGN KEY (organization_id, role_id)
      REFERENCES eogp.roles(organization_id, id)
      ON DELETE CASCADE
);

INSERT INTO eogp.permissions (code, description, scope_kind, is_sensitive) VALUES
('organization.manage','Manage organization settings and memberships','organization',true),
('venue.read','Read venue inventory','venue',false),
('venue.manage','Manage venues and spaces','venue',true),
('booking.inquiry.read','Read booking inquiries','booking',true),
('booking.manage','Manage booking drafts and offers','booking',true),
('booking.approve','Approve booking offers and exceptions','booking',true),
('booking.confirm','Confirm bookings and reserve resources','booking',true),
('booking.cancellation.request','Request booking cancellation','booking',true),
('booking.cancellation.review','Review booking cancellation requests','booking',true),
('booking.cancellation.approve','Approve or reject booking cancellation','booking',true),
('booking.cancellation.execute','Execute effective booking cancellation','booking',true),
('booking.cancellation.override','Use emergency booking cancellation override','booking',true),
('event.manage','Manage organizer-owned event','event',true),
('event.cancellation.preview','Preview event cancellation impact','event',true),
('event.cancellation.initiate','Initiate event cancellation','event',true),
('event.cancellation.approve','Approve event cancellation','event',true),
('event.cancellation.execute','Execute event cancellation','event',true),
('event.postponement.manage','Postpone or reschedule event','event',true),
('event.cancellation.notifications.preview','Preview cancellation audience','event',true),
('event.cancellation.notifications.send','Send event cancellation notification','event',true),
('event.cancellation.notifications.manage','Manage event cancellation campaigns','event',true),
('guest.read','Read permitted guest records','event',true),
('guest.manage','Manage guest registry and participation','event',true),
('invitation.manage','Issue and manage invitations','event',true),
('rsvp.record','Record RSVP on behalf of guest','event',true),
('rsvp.correct','Correct RSVP history with reason','event',true),
('collaboration.manage','Manage scoped collaboration grants','organization',true),
('task.assign','Assign event responsibility','event',true),
('allocation.manage','Manage event seating/allocation','event',true),
('checkin.manage','Manage admission and attendance','event',true),
('audit.read','Read authorized audit history','organization',true)
ON CONFLICT (code) DO NOTHING;

