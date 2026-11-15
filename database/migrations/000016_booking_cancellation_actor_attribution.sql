-- Complete actor attribution for externally executed booking cancellation and booking history.
-- No production schema has been released; this forward migration makes actor identity explicit.

ALTER TABLE eogp.external_action_capabilities
  ADD CONSTRAINT external_action_capabilities_booking_actor_key
  UNIQUE (organization_id, booking_id, id);

-- Effective cancellation may be executed by an authorized venue member,
-- a scoped external booking action capability under self-service policy,
-- or a narrowly-scoped service principal acting under the policy engine.
ALTER TABLE eogp.booking_cancellation_effects
  ALTER COLUMN executed_by_membership_id DROP NOT NULL,
  ADD COLUMN executed_by_external_capability_id uuid,
  ADD COLUMN executed_by_service_principal_id uuid,
  ADD COLUMN executed_by_kind text NOT NULL DEFAULT 'membership'
    CHECK (executed_by_kind IN ('membership','external_capability','service_principal'));

ALTER TABLE eogp.booking_cancellation_effects
  ADD CONSTRAINT booking_cancellation_effects_actor_check
  CHECK (
    (executed_by_kind = 'membership'
      AND executed_by_membership_id IS NOT NULL
      AND executed_by_external_capability_id IS NULL
      AND executed_by_service_principal_id IS NULL)
    OR
    (executed_by_kind = 'external_capability'
      AND executed_by_membership_id IS NULL
      AND executed_by_external_capability_id IS NOT NULL
      AND executed_by_service_principal_id IS NULL)
    OR
    (executed_by_kind = 'service_principal'
      AND executed_by_membership_id IS NULL
      AND executed_by_external_capability_id IS NULL
      AND executed_by_service_principal_id IS NOT NULL)
  ),
  ADD CONSTRAINT booking_cancellation_effects_external_actor_fk
    FOREIGN KEY (organization_id, booking_id, executed_by_external_capability_id)
    REFERENCES eogp.external_action_capabilities(organization_id, booking_id, id),
  ADD CONSTRAINT booking_cancellation_effects_service_actor_fk
    FOREIGN KEY (organization_id, executed_by_service_principal_id)
    REFERENCES eogp.service_principals(organization_id, id);

-- Status history retains the real principal for a customer-initiated
-- self-service cancellation; it must not manufacture an internal actor.
ALTER TABLE eogp.booking_status_history
  ADD COLUMN actor_external_capability_id uuid,
  ADD COLUMN actor_service_principal_id uuid,
  ADD COLUMN actor_kind text;

UPDATE eogp.booking_status_history
   SET actor_kind = 'membership'
 WHERE actor_membership_id IS NOT NULL;

DO $migration_guard$
BEGIN
  IF EXISTS (
    SELECT 1 FROM eogp.booking_status_history WHERE actor_kind IS NULL
  ) THEN
    RAISE EXCEPTION
      'booking_status_history contains rows without actor membership; explicitly backfill their authentic service/external actor before applying migration 000016';
  END IF;
END;
$migration_guard$;

ALTER TABLE eogp.booking_status_history
  ALTER COLUMN actor_kind SET NOT NULL,
  ALTER COLUMN actor_kind SET DEFAULT 'membership',
  ADD CONSTRAINT booking_status_history_actor_check
  CHECK (
    (actor_kind = 'membership'
      AND actor_membership_id IS NOT NULL
      AND actor_external_capability_id IS NULL
      AND actor_service_principal_id IS NULL)
    OR
    (actor_kind = 'external_capability'
      AND actor_membership_id IS NULL
      AND actor_external_capability_id IS NOT NULL
      AND actor_service_principal_id IS NULL)
    OR
    (actor_kind = 'service_principal'
      AND actor_membership_id IS NULL
      AND actor_external_capability_id IS NULL
      AND actor_service_principal_id IS NOT NULL)
  ),
  ADD CONSTRAINT booking_status_history_external_actor_fk
    FOREIGN KEY (organization_id, booking_id, actor_external_capability_id)
    REFERENCES eogp.external_action_capabilities(organization_id, booking_id, id),
  ADD CONSTRAINT booking_status_history_service_actor_fk
    FOREIGN KEY (organization_id, actor_service_principal_id)
    REFERENCES eogp.service_principals(organization_id, id);

-- The authoritative effect is immutable once committed. A venue disruption
-- notice is also a factual, append-only notice; acknowledgement/resolution is
-- recorded separately in the event owner's tenant.
CREATE TRIGGER booking_cancellation_effects_append_only_guard
  BEFORE UPDATE OR DELETE ON eogp.booking_cancellation_effects
  FOR EACH ROW EXECUTE FUNCTION eogp.reject_append_only_mutation();

CREATE TRIGGER booking_disruption_notices_append_only_guard
  BEFORE UPDATE OR DELETE ON eogp.booking_disruption_notices
  FOR EACH ROW EXECUTE FUNCTION eogp.reject_append_only_mutation();

REVOKE UPDATE, DELETE ON
  eogp.booking_cancellation_effects,
  eogp.booking_disruption_notices
FROM eventor_runtime, eventor_worker;

