-- Keep bearer-token capability records inaccessible to application and worker roles.
-- Runtime and worker code must use the narrowly scoped SECURITY DEFINER commands.
REVOKE ALL ON TABLE eogp.external_action_capabilities
  FROM eventor_runtime, eventor_worker;

-- This trigger helper is internal implementation detail, not an application command.
-- Explicitly revoke role grants as well as PUBLIC execution.
REVOKE ALL ON FUNCTION eogp.assert_revision_parent_mutable(text,jsonb)
  FROM PUBLIC, eventor_runtime, eventor_worker, eventor_auth;
