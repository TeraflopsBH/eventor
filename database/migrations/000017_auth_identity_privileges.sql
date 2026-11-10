-- Separate global authentication from tenant-scoped application queries.
-- The general runtime role must never be able to read password hashes.

CREATE POLICY organization_membership_auth_lookup
  ON eogp.organization_memberships
  FOR SELECT TO eventor_auth
  USING (true);

CREATE POLICY organization_auth_lookup
  ON eogp.organizations
  FOR SELECT TO eventor_auth
  USING (true);

-- Normal tenant-scoped application code gets only the profile projection of
-- members visible under the current tenant RLS context. The view owner is
-- eventor_owner; FORCE ROW LEVEL SECURITY remains enabled on memberships.
CREATE VIEW eogp.organization_member_profiles
WITH (security_barrier = true)
AS
SELECT
  membership.organization_id,
  membership.id AS membership_id,
  membership.user_id,
  membership.status AS membership_status,
  users.display_name,
  users.status AS user_status
FROM eogp.organization_memberships AS membership
JOIN eogp.users AS users
  ON users.id = membership.user_id;

REVOKE ALL ON eogp.organization_member_profiles FROM PUBLIC;
GRANT SELECT ON eogp.organization_member_profiles TO eventor_runtime;

-- Identity records are global and RLS is intentionally disabled on users.
-- Restrict direct table access to the dedicated authentication credential.
REVOKE ALL ON eogp.users FROM PUBLIC, eventor_runtime, eventor_worker;

GRANT SELECT (
  id, email, display_name, password_hash, status,
  email_verified_at, last_authenticated_at
) ON eogp.users TO eventor_auth;
GRANT INSERT (email, display_name, password_hash, status)
  ON eogp.users TO eventor_auth;
GRANT UPDATE (
  email, display_name, password_hash, status,
  email_verified_at, last_authenticated_at, updated_at
) ON eogp.users TO eventor_auth;

GRANT SELECT (
  organization_id, id, user_id, status, joined_at, revoked_at, created_at
) ON eogp.organization_memberships TO eventor_auth;
GRANT SELECT (
  id, slug, name, operating_profile, status, default_timezone, created_at, updated_at
) ON eogp.organizations TO eventor_auth;

COMMENT ON ROLE eventor_auth IS
  'Dedicated credential-verification and global membership-discovery role; no venue, booking, guest or event business-table access.';
COMMENT ON VIEW eogp.organization_member_profiles IS
  'Tenant-filtered member profile projection. Uses forced RLS on organization_memberships; does not expose email or password hash.';
