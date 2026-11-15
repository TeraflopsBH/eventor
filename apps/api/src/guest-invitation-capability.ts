import { createHash, randomBytes } from "node:crypto";

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

/**
 * Create a new invitation bearer token and its persistence-safe digest.
 * Persist only tokenSha256; return token once to the caller for link delivery.
 */
export function createGuestInvitationCapability(): {
  readonly token: string;
  readonly tokenSha256: string;
} {
  const token = randomBytes(32).toString("base64url");
  const tokenSha256 = hashGuestInvitationToken(token);
  if (!tokenSha256) {
    throw new Error("Generated guest invitation capability was invalid.");
  }
  return { token, tokenSha256 };
}
