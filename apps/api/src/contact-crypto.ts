import {
  createCipheriv,
  createDecipheriv,
  createHmac,
  randomBytes,
} from "node:crypto";

export type ContactKind = "email" | "phone" | "postal" | "other";

export interface ContactEncryptionContext {
  readonly organizationId: string;
  readonly contactKind: ContactKind;
}

const ENVELOPE_MAGIC = Buffer.from("ECP1", "ascii");
const NONCE_BYTES = 12;
const TAG_BYTES = 16;

function validateKey(key: Buffer): void {
  if (!Buffer.isBuffer(key) || key.length !== 32) {
    throw new TypeError("Contact encryption key must be exactly 32 bytes.");
  }
}

function contextAad(context: ContactEncryptionContext): Buffer {
  const organizationId = context.organizationId.trim().toLowerCase();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(organizationId)) {
    throw new TypeError("A valid organization UUID is required for contact encryption.");
  }
  if (!["email", "phone", "postal", "other"].includes(context.contactKind)) {
    throw new TypeError("Unsupported contact kind.");
  }
  return Buffer.from(
    `eventor:contact-point:v1\0${organizationId}\0${context.contactKind}`,
    "utf8",
  );
}

function deriveContactKey(masterKey: Buffer): Buffer {
  validateKey(masterKey);
  return createHmac("sha256", masterKey)
    .update("eventor:contact-point-encryption:v1", "utf8")
    .digest();
}

/**
 * ECP1 envelope: 4-byte magic, 12-byte nonce, 16-byte GCM tag, ciphertext.
 * Tenant and contact kind are authenticated as AAD, preventing ciphertext
 * from being moved between organizations or contact types.
 */
export function encryptContactValue(
  plaintext: string,
  masterKey: Buffer,
  context: ContactEncryptionContext,
): Buffer {
  if (typeof plaintext !== "string" || plaintext.length === 0) {
    throw new TypeError("Contact value must be a non-empty string.");
  }
  const key = deriveContactKey(masterKey);
  const nonce = randomBytes(NONCE_BYTES);
  const cipher = createCipheriv("aes-256-gcm", key, nonce);
  cipher.setAAD(contextAad(context));
  const ciphertext = Buffer.concat([
    cipher.update(plaintext, "utf8"),
    cipher.final(),
  ]);
  return Buffer.concat([
    ENVELOPE_MAGIC,
    nonce,
    cipher.getAuthTag(),
    ciphertext,
  ]);
}

export function decryptContactValue(
  envelope: Buffer,
  masterKey: Buffer,
  context: ContactEncryptionContext,
): string {
  if (!Buffer.isBuffer(envelope) || envelope.length <= ENVELOPE_MAGIC.length + NONCE_BYTES + TAG_BYTES) {
    throw new TypeError("Invalid contact ciphertext envelope.");
  }
  if (!envelope.subarray(0, ENVELOPE_MAGIC.length).equals(ENVELOPE_MAGIC)) {
    throw new TypeError("Unsupported contact ciphertext version.");
  }
  const key = deriveContactKey(masterKey);
  const nonceStart = ENVELOPE_MAGIC.length;
  const tagStart = nonceStart + NONCE_BYTES;
  const ciphertextStart = tagStart + TAG_BYTES;
  const nonce = envelope.subarray(nonceStart, tagStart);
  const tag = envelope.subarray(tagStart, ciphertextStart);
  const ciphertext = envelope.subarray(ciphertextStart);
  const decipher = createDecipheriv("aes-256-gcm", key, nonce);
  decipher.setAAD(contextAad(context));
  decipher.setAuthTag(tag);
  return Buffer.concat([
    decipher.update(ciphertext),
    decipher.final(),
  ]).toString("utf8");
}
