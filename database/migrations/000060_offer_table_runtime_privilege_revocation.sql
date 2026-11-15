-- The commercial workflow tables were created while the legacy schema-wide
-- runtime grants were still active. Revoke direct access in a forward-only
-- migration; application code must use the permission-checked command API.

REVOKE ALL ON eogp.booking_offers,
  eogp.booking_offer_revisions,
  eogp.external_action_capabilities
  FROM PUBLIC, eventor_runtime, eventor_worker, eventor_auth;
