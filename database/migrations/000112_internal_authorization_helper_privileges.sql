-- Defense in depth for internal authorization predicates and delegated task rows.
-- These routines are called from owner-controlled SECURITY DEFINER commands;
-- application roles must not be able to probe permission state directly.

REVOKE ALL ON FUNCTION eogp.assert_event_command_permission(uuid,uuid,uuid,text)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.assert_booking_inquiry_permission(uuid,uuid,text)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.assert_booking_draft_permission(uuid,uuid,uuid,text)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.assert_booking_commercial_permission(uuid,uuid,text[])
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
REVOKE ALL ON FUNCTION eogp.assert_collaboration_manage_permission(uuid,uuid)
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;

-- Delegated-task data is exposed through a fixed projection and an audited
-- status command only; no application role needs direct table access.
REVOKE ALL ON TABLE eogp.event_responsibility_assignments
  FROM PUBLIC,eventor_runtime,eventor_worker,eventor_auth;
