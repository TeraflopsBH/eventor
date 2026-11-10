-- Eventor migration 000012: 000012_event_responsibility_disruption.sql
-- Apply only through scripts/db/apply-migrations.sh so the checksum ledger is updated.
BEGIN;
SET LOCAL search_path TO eogp, public;

SET LOCAL search_path TO eogp, public;

CREATE TABLE eogp.external_parties (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES eogp.organizations(id) ON DELETE RESTRICT,
  party_name      text NOT NULL,
  contact_json    jsonb NOT NULL DEFAULT '{}'::jsonb,
  notes           text,
  UNIQUE (organization_id, id)
);

CREATE TABLE eogp.event_responsibility_assignments (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  task_code       text NOT NULL,
  task_instance_id uuid,
  accountable_party_kind text NOT NULL CHECK (accountable_party_kind IN ('event_organization','external_party')),
  accountable_external_party_id uuid,
  performing_party_kind text NOT NULL CHECK (performing_party_kind IN ('event_organization','collaborating_organization','external_party')),
  performing_organization_id uuid,
  performing_external_party_id uuid,
  collaboration_grant_id uuid,
  approver_membership_id uuid,
  due_at          timestamptz,
  status          text NOT NULL DEFAULT 'not_started' CHECK (status IN ('not_applicable','not_started','in_progress','blocked','completed','cancelled')),
  data_scope_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at      timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (organization_id, id),
  UNIQUE (organization_id, event_id, id),
  FOREIGN KEY (organization_id, event_id)
    REFERENCES eogp.events(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, accountable_external_party_id)
    REFERENCES eogp.external_parties(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, performing_external_party_id)
    REFERENCES eogp.external_parties(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, approver_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, performing_organization_id, collaboration_grant_id)
    REFERENCES eogp.collaboration_grants(organization_id, grantee_organization_id, id) ON DELETE RESTRICT,
  CHECK (
    (accountable_party_kind='event_organization' AND accountable_external_party_id IS NULL)
    OR (accountable_party_kind='external_party' AND accountable_external_party_id IS NOT NULL)
  ),
  CHECK (
    (performing_party_kind='event_organization' AND performing_organization_id IS NULL AND performing_external_party_id IS NULL AND collaboration_grant_id IS NULL)
    OR (performing_party_kind='collaborating_organization' AND performing_organization_id IS NOT NULL AND performing_external_party_id IS NULL AND collaboration_grant_id IS NOT NULL)
    OR (performing_party_kind='external_party' AND performing_organization_id IS NULL AND performing_external_party_id IS NOT NULL AND collaboration_grant_id IS NULL)
  )
);

CREATE TABLE eogp.event_disruption_receipts (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  booking_event_link_id uuid NOT NULL,
  source_booking_notice_id uuid NOT NULL,
  source_organization_id uuid NOT NULL,
  received_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  acknowledged_by_membership_id uuid,
  acknowledged_at timestamptz,
  status          text NOT NULL DEFAULT 'received' CHECK (status IN ('received','acknowledged','resolved','dismissed')),
  UNIQUE (organization_id, id),
  FOREIGN KEY (organization_id, event_id)
    REFERENCES eogp.events(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, event_id, booking_event_link_id)
    REFERENCES eogp.booking_event_links(organization_id, event_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, acknowledged_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT
);

CREATE TABLE eogp.event_disruption_resolutions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  disruption_receipt_id uuid NOT NULL,
  outcome         text NOT NULL CHECK (outcome IN ('relocate','booking_amendment_requested','postpone','cancel_event','unresolved')),
  resolution_note text,
  resolved_by_membership_id uuid NOT NULL,
  resolved_at     timestamptz NOT NULL DEFAULT clock_timestamp(),
  FOREIGN KEY (organization_id, event_id)
    REFERENCES eogp.events(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, disruption_receipt_id)
    REFERENCES eogp.event_disruption_receipts(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, resolved_by_membership_id)
    REFERENCES eogp.organization_memberships(organization_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, id)
);

CREATE TABLE eogp.event_prerequisites (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  event_id        uuid NOT NULL,
  responsibility_assignment_id uuid NOT NULL,
  requirement_code text NOT NULL,
  due_at          timestamptz,
  status          text NOT NULL DEFAULT 'pending' CHECK (status IN ('not_applicable','pending','submitted','scheduled','completed','blocked')),
  evidence_reference text,
  restricted_metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  FOREIGN KEY (organization_id, event_id)
    REFERENCES eogp.events(organization_id, id) ON DELETE RESTRICT,
  FOREIGN KEY (organization_id, event_id, responsibility_assignment_id)
    REFERENCES eogp.event_responsibility_assignments(organization_id, event_id, id) ON DELETE RESTRICT,
  UNIQUE (organization_id, id)
);

INSERT INTO eogp.schema_migrations(version, filename, checksum_sha256)
VALUES ('000012', '000012_event_responsibility_disruption.sql', :'migration_checksum');
COMMIT;
