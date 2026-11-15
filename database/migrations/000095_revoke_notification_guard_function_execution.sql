-- Trigger-only guards do not need direct EXECUTE privileges.
-- Their triggers were created by eventor_owner; revoke the default PUBLIC
-- grant and every application-role grant without affecting trigger execution.
REVOKE ALL ON FUNCTION eogp.protect_queued_event_notification_recipients()
  FROM PUBLIC, eventor_runtime, eventor_worker, eventor_auth;
REVOKE ALL ON FUNCTION eogp.protect_confirmed_event_notification_exclusions()
  FROM PUBLIC, eventor_runtime, eventor_worker, eventor_auth;
