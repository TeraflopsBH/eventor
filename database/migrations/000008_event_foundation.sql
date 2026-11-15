-- Organizer-owned event aggregate, immutable schedules, sessions and capability revisions.
CREATE TABLE eogp.events (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    event_code text NOT NULL,
    title text NOT NULL,
    description_internal text,
    status text NOT NULL DEFAULT 'draft'
      CHECK (status IN ('draft','planned','scheduled','active','completed','cancelled','postponed','archived')),
    timezone_name text NOT NULL DEFAULT 'Europe/Sarajevo',
    current_revision integer NOT NULL DEFAULT 1 CHECK (current_revision > 0),
    created_by_membership_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_code),
    FOREIGN KEY (organization_id, created_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);

CREATE TABLE eogp.event_schedule_revisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    revision_number integer NOT NULL CHECK (revision_number > 0),
    schedule_kind text NOT NULL DEFAULT 'original'
      CHECK (schedule_kind IN ('original','reschedule','correction')),
    starts_at timestamptz NOT NULL,
    ends_at timestamptz NOT NULL,
    timezone_name text NOT NULL,
    venue_summary jsonb NOT NULL DEFAULT '{}'::jsonb,
    schedule_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
    material_change boolean NOT NULL DEFAULT false,
    reconfirmation_policy text NOT NULL DEFAULT 'none'
      CHECK (reconfirmation_policy IN ('none','accepted_tentative','all_active_invitees','all_invited')),
    created_by_membership_id uuid NOT NULL,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_id, id),
    UNIQUE (organization_id, event_id, revision_number),
    FOREIGN KEY (organization_id, event_id) REFERENCES eogp.events(organization_id, id),
    FOREIGN KEY (organization_id, created_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    CHECK (ends_at > starts_at)
);

CREATE TABLE eogp.event_sessions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    code text NOT NULL,
    title text NOT NULL,
    starts_at timestamptz,
    ends_at timestamptz,
    timezone_name text NOT NULL DEFAULT 'Europe/Sarajevo',
    status text NOT NULL DEFAULT 'planned'
      CHECK (status IN ('planned','scheduled','active','completed','cancelled')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_id, id),
    UNIQUE (organization_id, event_id, code),
    FOREIGN KEY (organization_id, event_id) REFERENCES eogp.events(organization_id, id),
    CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at)
);

CREATE TABLE eogp.event_capability_sets (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    current_revision_number integer NOT NULL DEFAULT 0 CHECK (current_revision_number >= 0),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_id),
    FOREIGN KEY (organization_id, event_id) REFERENCES eogp.events(organization_id, id)
);

CREATE TABLE eogp.event_capability_revisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    capability_set_id uuid NOT NULL,
    revision_number integer NOT NULL CHECK (revision_number > 0),
    capabilities jsonb NOT NULL DEFAULT '{}'::jsonb,
    state text NOT NULL DEFAULT 'draft' CHECK (state IN ('draft','published','retired')),
    published_at timestamptz,
    published_by_membership_id uuid,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, capability_set_id, id),
    UNIQUE (organization_id, capability_set_id, revision_number),
    FOREIGN KEY (organization_id, capability_set_id)
      REFERENCES eogp.event_capability_sets(organization_id, id),
    FOREIGN KEY (organization_id, published_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    CHECK (jsonb_typeof(capabilities) = 'object')
);

CREATE TABLE eogp.event_capability_overrides (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    event_id uuid NOT NULL,
    capability_code text NOT NULL
      CHECK (capability_code IN ('guest_registry','invitations_rsvp','seating','guest_portal','checkin','prerequisites','operations_cockpit')),
    enabled boolean NOT NULL DEFAULT false,
    reason text,
    changed_by_membership_id uuid NOT NULL,
    changed_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, event_id, capability_code),
    FOREIGN KEY (organization_id, event_id) REFERENCES eogp.events(organization_id, id),
    FOREIGN KEY (organization_id, changed_by_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id)
);

ALTER TABLE eogp.config_catalogues
  ADD CONSTRAINT config_catalogues_event_scope_fk
  FOREIGN KEY (organization_id, scope_event_id)
  REFERENCES eogp.events(organization_id, id);
