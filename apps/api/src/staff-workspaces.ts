// Navigation hints only. Every read/write keeps its own scoped authorization.
export const staffWorkspaces = ["events", "event-guests", "guest-registry", "guest-invitations", "inquiries", "delivery", "campaign", "approvals", "forms", "prices", "cancellations", "taxes", "settings"] as const;
export type StaffWorkspace = typeof staffWorkspaces[number];
export interface WorkspaceGrant { permission_code: string; scope_kind: string }
export function availableStaffWorkspaces(grants: readonly WorkspaceGrant[]): StaffWorkspace[] {
  const has = (codes: readonly string[], scopes = ["organization", "event"]) =>
    grants.some(grant => scopes.includes(grant.scope_kind) && codes.includes(grant.permission_code));
  const organization = (codes: readonly string[]) => has(codes, ["organization"]);
  const booking = organization(["booking.manage"]);
  const allowed: Record<StaffWorkspace, boolean> = {
    events: has(["event.manage"]),
    "event-guests": has(["guest.read", "guest.manage"]),
    "guest-registry": organization(["guest.registry.read", "guest.registry.manage"]),
    "guest-invitations": has(["invitation.manage"]),
    inquiries: has(["booking.inquiry.read"], ["organization", "venue", "space", "booking"]),
    delivery: organization(["organization.delivery.manage"]),
    campaign: has(["event.notifications.send"]),
    approvals: booking, forms: booking, prices: booking, cancellations: booking, taxes: booking,
    settings: true,
  };
  return staffWorkspaces.filter(workspace => allowed[workspace]);
}
