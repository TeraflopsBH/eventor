-- Narrow the dedicated authentication role to the session fields its service actually mutates.
-- It may not rewrite session identity or bearer-token hashes after creation.

REVOKE SELECT, INSERT, UPDATE ON eogp.user_sessions FROM eventor_auth;
GRANT SELECT (
  id, user_id, organization_id, membership_id,
  session_token_sha256, csrf_token_sha256,
  expires_at, last_seen_at, revoked_at
) ON eogp.user_sessions TO eventor_auth;
GRANT INSERT (
  user_id, organization_id, membership_id,
  session_token_sha256, csrf_token_sha256, expires_at,
  source_fingerprint, user_agent_fingerprint
) ON eogp.user_sessions TO eventor_auth;
GRANT UPDATE (last_seen_at, revoked_at)
  ON eogp.user_sessions TO eventor_auth;

-- Login throttling only changes counters and window timestamps; its lookup keys are immutable.
REVOKE UPDATE ON eogp.auth_login_attempts FROM eventor_auth;
GRANT UPDATE (failed_attempts, blocked_until, window_started_at, updated_at)
  ON eogp.auth_login_attempts TO eventor_auth;

-- The current authentication service rehashes passwords and records successful authentication.
-- It does not manage account identity, verification or activation state.
REVOKE UPDATE (email, display_name, status, email_verified_at)
  ON eogp.users FROM eventor_auth;
