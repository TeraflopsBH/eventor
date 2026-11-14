import { createHash } from "node:crypto";

/**
 * Database-level issuance idempotency must have the same principal boundary
 * as the API command ledger. Never let two staff memberships in one tenant
 * collide merely because they supplied the same Idempotency-Key.
 */
export function guestInvitationIssuanceIdempotencyDigest(
  membershipId: string,
  invitationId: string | null,
  idempotencyKey: string,
): string {
  const operation = invitationId ? "reissue" : "issue";
  return createHash("sha256")
    .update(`eventor:guest-invitation:${membershipId}:${operation}:${idempotencyKey}`, "utf8")
    .digest("hex");
}
