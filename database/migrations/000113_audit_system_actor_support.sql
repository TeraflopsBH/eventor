-- Allow background workers to append audit events with an explicit system actor.
-- System events are organization-scoped records with no human/service identity;
-- the tenant remains in organization_id and the actor identity columns stay NULL.
DO $constraints$
DECLARE
  v_constraint record;
BEGIN
  FOR v_constraint IN
    SELECT conname
      FROM pg_constraint
     WHERE conrelid='eogp.audit_events'::regclass
       AND contype='c'
       AND pg_get_constraintdef(oid) ILIKE '%actor_kind%'
  LOOP
    EXECUTE format('ALTER TABLE eogp.audit_events DROP CONSTRAINT %I',v_constraint.conname);
  END LOOP;
END;
$constraints$;

ALTER TABLE eogp.audit_events
  ADD CONSTRAINT audit_events_actor_kind_check
    CHECK (actor_kind IN ('membership','service_principal','external_capability','system')),
  ADD CONSTRAINT audit_events_actor_identity_check
    CHECK (
      (actor_kind='membership'
        AND actor_organization_id IS NOT NULL
        AND actor_membership_id IS NOT NULL
        AND actor_service_principal_id IS NULL
        AND actor_external_capability_id IS NULL)
      OR
      (actor_kind='service_principal'
        AND actor_organization_id IS NOT NULL
        AND actor_membership_id IS NULL
        AND actor_service_principal_id IS NOT NULL
        AND actor_external_capability_id IS NULL)
      OR
      (actor_kind='external_capability'
        AND actor_organization_id IS NULL
        AND actor_membership_id IS NULL
        AND actor_service_principal_id IS NULL
        AND actor_external_capability_id IS NOT NULL)
      OR
      (actor_kind='system'
        AND actor_organization_id IS NULL
        AND actor_membership_id IS NULL
        AND actor_service_principal_id IS NULL
        AND actor_external_capability_id IS NULL)
    );
