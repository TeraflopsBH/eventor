import type { Pool } from "pg";

export class StaffMembershipError extends Error {
  constructor(readonly code: "INVALID_INPUT" | "ACCOUNT_UNAVAILABLE" | "ORGANIZATION_UNAVAILABLE" | "MEMBERSHIP_EXISTS" | "OWNER_REQUIRED" | "PROVISIONING_FAILED", message: string) {
    super(message); this.name = "StaffMembershipError";
  }
}
export interface StaffMembershipInput { email: string; organizationId: string; reason: string }

/** Host-only operation. Existing memberships and account credentials must never be overwritten here. */
export async function provisionStaffMembership(pool: Pick<Pool, "connect">, input: StaffMembershipInput): Promise<{ userId: string; membershipId: string }> {
  const email = input.email.trim().toLowerCase(); const reason = input.reason.trim();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254 || /[\p{Cc}\p{Cs}]/u.test(email)
      || !/^[a-f\d]{8}(?:-[a-f\d]{4}){3}-[a-f\d]{12}$/i.test(input.organizationId)
      || !reason || reason.length > 250 || /[\p{Cc}\p{Cs}]/u.test(reason)) {
    throw new StaffMembershipError("INVALID_INPUT", "Specify a valid existing-account email, organization UUID and a nonblank reason of at most 250 characters.");
  }
  const client = await pool.connect().catch(() => { throw new StaffMembershipError("PROVISIONING_FAILED", "The privileged database connection is unavailable."); });
  try {
    await client.query("BEGIN");
    await client.query("SET LOCAL ROLE eventor_owner");
    await client.query("SELECT set_config('app.organization_id',$1,true)", [input.organizationId]);
    const organization = await client.query("SELECT id FROM eogp.organizations WHERE id=$1::uuid AND status='active' FOR SHARE", [input.organizationId]);
    if (!organization.rows.length) throw new StaffMembershipError("ORGANIZATION_UNAVAILABLE", "The selected organization is not active or available.");
    const account = await client.query<{ id: string }>("SELECT id FROM eogp.users WHERE lower(email)=$1 AND status='active' FOR UPDATE", [email]);
    if (!account.rows.length) throw new StaffMembershipError("ACCOUNT_UNAVAILABLE", "The selected account is not active or available.");
    const userId = account.rows[0]!.id;
    const existing = await client.query("SELECT id FROM eogp.organization_memberships WHERE organization_id=$1::uuid AND user_id=$2::uuid FOR UPDATE", [input.organizationId,userId]);
    if (existing.rows.length) throw new StaffMembershipError("MEMBERSHIP_EXISTS", "This account already has a membership in the selected organization. Review its current access separately.");
    const membership = await client.query<{ id: string }>(
      "INSERT INTO eogp.organization_memberships(organization_id,user_id,status,joined_at) VALUES($1::uuid,$2::uuid,'active',clock_timestamp()) RETURNING id", [input.organizationId,userId]);
    await client.query("INSERT INTO eogp.platform_admin_audit(user_id,action,organization_id,reason) VALUES($1::uuid,'staff_membership_provisioned',$2::uuid,$3)", [userId,input.organizationId,reason]);
    await client.query("COMMIT");
    return { userId,membershipId:membership.rows[0]!.id };
  } catch (failure) {
    try { await client.query("ROLLBACK"); } catch { /* Preserve the original failure. */ }
    if (failure instanceof StaffMembershipError) throw failure;
    const code = (failure as {code?: string}).code;
    if (code === "42501") throw new StaffMembershipError("OWNER_REQUIRED", "Use a privileged migration connection that can select eventor_owner.");
    if (code === "23505") throw new StaffMembershipError("MEMBERSHIP_EXISTS", "A membership already exists; review its current access separately.");
    throw new StaffMembershipError("PROVISIONING_FAILED", "Provisioning failed; no membership was committed.");
  } finally { client.release(); }
}
