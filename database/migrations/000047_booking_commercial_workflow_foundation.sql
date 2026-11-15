-- Booking commercial workflow foundation: pinned approval policy and immutable decision history.
-- Offer creation/issue/decision/confirmation commands are added in subsequent migrations.
CREATE TABLE eogp.booking_approval_policies (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL REFERENCES eogp.organizations(id),
    code text NOT NULL,
    name text NOT NULL,
    status text NOT NULL DEFAULT 'active'
      CHECK (status IN ('active','retired')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, code)
);

CREATE TABLE eogp.booking_approval_policy_revisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    policy_id uuid NOT NULL,
    revision_number integer NOT NULL CHECK (revision_number > 0),
    state text NOT NULL DEFAULT 'draft'
      CHECK (state IN ('draft','published','retired')),
    rules jsonb NOT NULL DEFAULT '[]'::jsonb,
    published_at timestamptz,
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    UNIQUE (organization_id, policy_id, id),
    UNIQUE (organization_id, policy_id, revision_number),
    FOREIGN KEY (organization_id, policy_id)
      REFERENCES eogp.booking_approval_policies(organization_id, id),
    CHECK (jsonb_typeof(rules) = 'array'),
    CHECK ((state IN ('published','retired')) = (published_at IS NOT NULL))
);

-- The offer revision pins both the policy revision and the exact evaluated
-- requirements. A later policy publication cannot silently change an offer.
ALTER TABLE eogp.booking_offer_revisions
  ADD COLUMN approval_policy_revision_id uuid,
  ADD COLUMN approval_requirements_snapshot jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD CONSTRAINT booking_offer_revision_approval_policy_fk
    FOREIGN KEY (organization_id, approval_policy_revision_id)
    REFERENCES eogp.booking_approval_policy_revisions(organization_id, id),
  ADD CONSTRAINT booking_offer_revision_approval_snapshot_array
    CHECK (jsonb_typeof(approval_requirements_snapshot) = 'array');

CREATE TABLE eogp.booking_offer_decision_history (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    offer_id uuid NOT NULL,
    offer_revision_id uuid NOT NULL,
    decision text NOT NULL
      CHECK (decision IN ('accepted','rejected','expired','withdrawn','superseded')),
    actor_kind text NOT NULL
      CHECK (actor_kind IN ('membership','external_capability','system')),
    actor_membership_id uuid,
    external_capability_id uuid,
    reason_code text,
    reason_ciphertext bytea,
    customer_name_ciphertext bytea,
    customer_note_ciphertext bytea,
    occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, offer_id)
      REFERENCES eogp.booking_offers(organization_id, id),
    FOREIGN KEY (organization_id, offer_id, offer_revision_id)
      REFERENCES eogp.booking_offer_revisions(organization_id, offer_id, id),
    FOREIGN KEY (organization_id, actor_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    FOREIGN KEY (organization_id, external_capability_id)
      REFERENCES eogp.external_action_capabilities(organization_id, id),
    CHECK (
      (actor_kind = 'membership' AND actor_membership_id IS NOT NULL AND external_capability_id IS NULL)
      OR (actor_kind = 'external_capability' AND actor_membership_id IS NULL AND external_capability_id IS NOT NULL)
      OR (actor_kind = 'system' AND actor_membership_id IS NULL AND external_capability_id IS NULL)
    )
);
CREATE INDEX booking_offer_decision_history_revision_idx
  ON eogp.booking_offer_decision_history (organization_id, offer_revision_id, occurred_at);

CREATE TABLE eogp.booking_offer_approval_decisions (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id uuid NOT NULL,
    offer_id uuid NOT NULL,
    offer_revision_id uuid NOT NULL,
    rule_code text NOT NULL,
    decision text NOT NULL
      CHECK (decision IN ('approved','rejected','returned_for_changes')),
    actor_membership_id uuid NOT NULL,
    reason text NOT NULL,
    decided_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, offer_id)
      REFERENCES eogp.booking_offers(organization_id, id),
    FOREIGN KEY (organization_id, offer_id, offer_revision_id)
      REFERENCES eogp.booking_offer_revisions(organization_id, offer_id, id),
    FOREIGN KEY (organization_id, actor_membership_id)
      REFERENCES eogp.organization_memberships(organization_id, id),
    CHECK (length(btrim(rule_code)) BETWEEN 1 AND 100),
    CHECK (length(btrim(reason)) BETWEEN 3 AND 2000)
);
CREATE INDEX booking_offer_approval_decisions_revision_idx
  ON eogp.booking_offer_approval_decisions (organization_id, offer_revision_id, rule_code, decided_at);

-- Decision and approval records are evidence, not mutable current-state rows.
CREATE TRIGGER booking_offer_decision_history_append_only_guard
  BEFORE UPDATE OR DELETE ON eogp.booking_offer_decision_history
  FOR EACH ROW EXECUTE FUNCTION eogp.reject_append_only_mutation();

CREATE TRIGGER booking_offer_approval_decisions_append_only_guard
  BEFORE UPDATE OR DELETE ON eogp.booking_offer_approval_decisions
  FOR EACH ROW EXECUTE FUNCTION eogp.reject_append_only_mutation();

CREATE FUNCTION eogp.prevent_published_booking_approval_policy_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog
AS $function$
BEGIN
  IF OLD.state IN ('published','retired') OR OLD.published_at IS NOT NULL THEN
    RAISE EXCEPTION 'published booking approval policy revisions are immutable'
      USING ERRCODE = '55000';
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER booking_approval_policy_revisions_immutable_guard
  BEFORE UPDATE OR DELETE ON eogp.booking_approval_policy_revisions
  FOR EACH ROW EXECUTE FUNCTION eogp.prevent_published_booking_approval_policy_mutation();

ALTER TABLE eogp.booking_approval_policies ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.booking_approval_policies FORCE ROW LEVEL SECURITY;
ALTER TABLE eogp.booking_approval_policy_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.booking_approval_policy_revisions FORCE ROW LEVEL SECURITY;
ALTER TABLE eogp.booking_offer_decision_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.booking_offer_decision_history FORCE ROW LEVEL SECURITY;
ALTER TABLE eogp.booking_offer_approval_decisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE eogp.booking_offer_approval_decisions FORCE ROW LEVEL SECURITY;

CREATE POLICY booking_approval_policies_tenant_isolation
  ON eogp.booking_approval_policies
  USING (organization_id = eogp.current_organization_id())
  WITH CHECK (organization_id = eogp.current_organization_id());
CREATE POLICY booking_approval_policy_revisions_tenant_isolation
  ON eogp.booking_approval_policy_revisions
  USING (organization_id = eogp.current_organization_id())
  WITH CHECK (organization_id = eogp.current_organization_id());
CREATE POLICY booking_offer_decision_history_tenant_isolation
  ON eogp.booking_offer_decision_history
  USING (organization_id = eogp.current_organization_id())
  WITH CHECK (organization_id = eogp.current_organization_id());
CREATE POLICY booking_offer_approval_decisions_tenant_isolation
  ON eogp.booking_offer_approval_decisions
  USING (organization_id = eogp.current_organization_id())
  WITH CHECK (organization_id = eogp.current_organization_id());

REVOKE ALL ON eogp.booking_approval_policies,
  eogp.booking_approval_policy_revisions,
  eogp.booking_offer_decision_history,
  eogp.booking_offer_approval_decisions
  FROM PUBLIC, eventor_runtime, eventor_worker, eventor_auth;

REVOKE ALL ON FUNCTION eogp.prevent_published_booking_approval_policy_mutation()
  FROM PUBLIC, eventor_runtime, eventor_worker, eventor_auth;
