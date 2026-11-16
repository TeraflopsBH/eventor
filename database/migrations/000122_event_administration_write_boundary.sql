-- Event writes must use the permissioned commands introduced in 000121.
-- SECURITY DEFINER commands retain owner privileges; ordinary tenant sessions
-- must not bypass event.manage, audit attribution or revision checks.
REVOKE INSERT, UPDATE, DELETE ON eogp.events FROM eventor_runtime;
