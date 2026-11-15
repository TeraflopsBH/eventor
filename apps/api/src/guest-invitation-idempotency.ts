import { createHash } from "node:crypto";

/**
 * Database-level issuance idempotency is scoped to the authenticated staff
 * principal and the exact event/participation command. A reused client key
 * must never replay another guest's invitation delivery.
 */
export function guestInvitationIssuanceIdempotencyDigest(
  membershipId: string,
  eventId: string,
  participationId: string,
  invitationId: string | null,
  idempotencyKey: string,
): string {
  const operation = invitationId ? "reissue" : "issue";
  return createHash("sha256")
    .update(`eventor:guest-invitation:${membershipId}:${eventId}:${participationId}:${operation}:${idempotencyKey}`, "utf8")
    .digest("hex");
}
