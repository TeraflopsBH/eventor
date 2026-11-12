-- Keep bearer-token capability records inaccessible to application and worker roles.
-- Runtime and worker code must use the narrowly scoped SECURITY DEFINER commands.
REVOKE ALL ON TABLE eogp.external_action_capabilities
  FROM eventor_runtime, eventor_worker;
