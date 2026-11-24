# ADR 0015 — Email-first sign-in, workspace switching and platform administration

- Status: accepted.
- Date: 2026-11-24.
- Related: owner preview feedback and #104. Organizations and venues retain their separate domain meanings.

## Authentication and workspace selection

Ordinary users enter email and password. Password verification and the existing atomic login throttling precede disclosure of workspace names. One active membership opens directly. Multiple memberships return named choices without issuing session cookies; the selected organization ID is submitted with the credentials held only in the current form's memory. Slug selectors remain optional API compatibility inputs. No password, session token or selection credential is stored in browser storage.

Signed-in users can switch among their active memberships through a workspace menu. The command revalidates and locks the target account/membership and current session, issues new opaque session/CSRF credentials, revokes the old session and records the actual user's switch audit in one transaction. It preserves the original expiry. Target locks are acquired before the session lock; switching does not rewrite password-authentication timestamps. The browser replaces the page to clear prior workspace state. Every data command still checks the selected tenant and its scoped permissions.

## Explicit platform administrator

Existing users default to `is_platform_admin=false`. Only a privileged host-owner operation can change this flag; application authentication and runtime roles cannot update it. `scripts/admin/platform-admin.sh` grants/revokes it for an existing account and records the database principal, reason and time. An organization manager is not automatically a platform administrator.

An active platform administrator receives tracked, managed memberships and immutable-identity system role/grant references for active organizations. The managed organization role includes current non-platform permissions. Access is reconciled at login/session-profile refresh, including newly created organizations and permissions. The normal selected-tenant runtime remains in use; the flag never bypasses tenant RLS on application data.

Global provisioning uses private organization-ID, managed-access and append-only audit tables, following the existing private global routing-index boundary. Ordinary runtime, authentication and worker roles have no direct table access. A locked, transactional migration seeds the organization-ID index and restores FORCE RLS before commit; organizations themselves retain forced tenant RLS. Auth receives only narrow SECURITY DEFINER provisioning, target-membership lock and switch-audit routines with pinned search paths. This avoids granting auth UPDATE on tenant memberships just to lock them.

Tenant membership commands cannot suspend a platform-managed administrator while the global role is active. Host revocation removes its managed grants, revokes affected sessions and restores prior membership status where it was not active. Independently held ordinary memberships and grants remain. Provisioning audit identifies the host database principal, rather than falsely attributing it to the affected staff user. Workspace switching separately records the authenticated user's target membership as actor.

Inactive-organization recovery and global account provisioning remain host operations; this does not claim a complete global account-management console. All normal memberships, organization/venue boundaries, guest privacy and existing command authorization continue to apply.

## Tenant directory controls — 2026-11-25

The authorized member directory exposes a `hostManaged` boolean for each membership in the selected organization. It does not expose global account lists, emails or other memberships. Both searched and unfiltered directory paths use the same projection. The staff UI identifies host-managed access and omits tenant suspension/restoration controls for those members. The existing database membership guard remains authoritative; hiding a control grants no authority and does not replace server checks. Independent event-role assignments remain ordinary tenant-managed facts.
