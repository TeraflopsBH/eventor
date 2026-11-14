import { createHash } from "node:crypto";

/**
 * Validate and hash an opaque guest invitation bearer token.
 *
 * Invitation links carry 256 bits of entropy encoded as unpadded base64url.
 * Only the SHA-256 digest is suitable for persistence or lookup; callers must
 * never log or return the supplied token.
 */
export function hashGuestInvitationToken(token: unknown): string | null {
  if (typeof token !== "string" || !/^[A-Za-z0-9_-]{43}$/.test(token)) {
    return null;
  }

  const decoded = Buffer.from(token, "base64url");
  if (decoded.length !== 32 || decoded.toString("base64url") !== token) {
    return null;
  }

  return createHash("sha256").update(decoded).digest("hex");
}
