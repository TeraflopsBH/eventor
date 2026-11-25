import argon2 from "argon2";
import type { Pool } from "pg";

export class StaffBootstrapError extends Error {
  constructor(readonly code: "INVALID_INPUT" | "ACCOUNT_EXISTS" | "ORGANIZATION_UNAVAILABLE" | "OWNER_REQUIRED" | "PROVISIONING_FAILED", message: string) {
    super(message); this.name = "StaffBootstrapError";
  }
}
export interface StaffBootstrapInput {
  email: string;
  displayName: string;
  password: string;
  organizationId?: string;
  reason: string;
}
const invalid = () => new StaffBootstrapError("INVALID_INPUT", "Specify a valid email, display name, reason and a password of 12–1024 UTF-8 bytes; an organization ID must be a UUID.");

/** Privileged host operation only. Never expose through an application route. */
export async function bootstrapStaffAccount(pool: Pick<Pool, "connect">, input: StaffBootstrapInput): Promise<{ userId: string; membershipId: string | null }> {
  const email = input.email.trim().toLowerCase();
  const displayName = input.displayName.trim(); const reason = input.reason.trim();
  const passwordBytes = Buffer.byteLength(input.password, "utf8");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.length > 254 || /[\p{Cc}\p{Cs}]/u.test(email)
    || !displayName || displayName.length > 250 || /[\p{Cc}\p{Cs}]/u.test(displayName)
    || !reason || reason.length > 250 || /[\p{Cc}\p{Cs}]/u.test(reason)
    || passwordBytes < 12 || passwordBytes > 1024 || !input.password.trim() || /[\r\n\0]/u.test(input.password)
    || (input.organizationId !== undefined && !/^[a-f\d]{8}(?:-[a-f\d]{4}){3}-[a-f\d]{12}$/i.test(input.organizationId))) throw invalid();
  const passwordHash = await argon2.hash(input.password, { type: argon2.argon2id });
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SET LOCAL ROLE eventor_owner");
    if (input.organizationId) {
      await client.query("SELECT set_config('app.organization_id',$1,true)", [input.organizationId]);
      const organization = await client.query("SELECT id FROM eogp.organizations WHERE id=$1::uuid AND status='active' FOR SHARE", [input.organizationId]);
      if (!organization.rows.length) throw new StaffBootstrapError("ORGANIZATION_UNAVAILABLE", "The selected organization is not active or available.");
    }
    const user = await client.query<{ id: string }>(
      "INSERT INTO eogp.users(email,display_name,password_hash,status,is_platform_admin,email_verified_at) VALUES($1,$2,$3,'active',false,NULL) RETURNING id", [email,displayName,passwordHash]);
    const userId = user.rows[0]!.id;
    let membershipId: string | null = null;
    if (input.organizationId) {
      const membership = await client.query<{ id: string }>(
        "INSERT INTO eogp.organization_memberships(organization_id,user_id,status,joined_at) VALUES($1::uuid,$2::uuid,'active',clock_timestamp()) RETURNING id", [input.organizationId,userId]);
      membershipId = membership.rows[0]!.id;
    }
    // Host attribution uses session_user, never the newly created member as a fictitious actor.
    await client.query(
      "INSERT INTO eogp.platform_admin_audit(user_id,action,organization_id,reason) VALUES($1::uuid,'staff_account_provisioned',$2::uuid,$3)", [userId,input.organizationId ?? null,reason]);
    await client.query("COMMIT");
    return { userId,membershipId };
  } catch (failure) {
    try { await client.query("ROLLBACK"); } catch { /* Preserve the original failure. */ }
    if (failure instanceof StaffBootstrapError) throw failure;
    const code = (failure as { code?: string }).code;
    if (code === "23505") throw new StaffBootstrapError("ACCOUNT_EXISTS", "An account with this email already exists; it was not changed.");
    if (code === "42501") throw new StaffBootstrapError("OWNER_REQUIRED", "Use a privileged migration connection that can select eventor_owner.");
    throw new StaffBootstrapError("PROVISIONING_FAILED", "Provisioning failed; no account was committed.");
  } finally { client.release(); }
}
