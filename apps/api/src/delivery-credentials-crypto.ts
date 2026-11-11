import {
  createCipheriv,
  createDecipheriv,
  createHmac,
  randomBytes,
} from "node:crypto";

export interface SmtpCredentials {
  readonly username: string;
  readonly password: string;
}

export type DeliveryCredentialBundle = Readonly<Record<string, string>>;

export interface DeliveryCredentialContext {
  readonly organizationId: string;
  readonly channel: "email" | "sms";
}

const MAGIC = Buffer.from("EDC1", "ascii");
const NONCE_BYTES = 12;
const TAG_BYTES = 16;

function validateKey(key: Buffer): void {
  if (!Buffer.isBuffer(key) || key.length !== 32) {
    throw new TypeError("Delivery credential encryption key must be exactly 32 bytes.");
  }
}

function aad(context: DeliveryCredentialContext): Buffer {
  const organizationId = context.organizationId.trim().toLowerCase();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(organizationId)) {
    throw new TypeError("A valid organization UUID is required for delivery credential encryption.");
  }
  if (context.channel !== "email" && context.channel !== "sms") {
    throw new TypeError("Unsupported delivery credential channel.");
  }
  return Buffer.from(
    `eventor:delivery-credentials:v1\0${organizationId}\0${context.channel}`,
    "utf8",
  );
}

function deriveKey(masterKey: Buffer): Buffer {
  validateKey(masterKey);
  return createHmac("sha256", masterKey)
    .update("eventor:delivery-credentials-encryption:v1", "utf8")
    .digest();
}

function validateCredentialBundle(credentials: DeliveryCredentialBundle): void {
  if (!credentials || typeof credentials !== "object" || Array.isArray(credentials)) {
    throw new TypeError("Delivery credentials must be a named string bundle.");
  }
  const entries = Object.entries(credentials);
  if (entries.length < 1 || entries.length > 32) {
    throw new TypeError("Delivery credential bundle must contain between 1 and 32 entries.");
  }
  let totalBytes = 0;
  for (const [name, value] of entries) {
    if (!/^[a-zA-Z][a-zA-Z0-9_.-]{0,63}$/.test(name) ||
        typeof value !== "string" || value.length === 0 || value.length > 4096) {
      throw new TypeError("Delivery credential bundle contains an invalid key or value.");
    }
    totalBytes += Buffer.byteLength(value, "utf8");
  }
  if (totalBytes > 8192) {
    throw new TypeError("Delivery credential bundle exceeds the supported size.");
  }
}

function validateSmtpCredentials(credentials: SmtpCredentials): void {
  if (!credentials || typeof credentials.username !== "string" ||
      typeof credentials.password !== "string" ||
      credentials.username.trim().length === 0 ||
      credentials.password.length === 0 ||
      credentials.username.length > 320 ||
      credentials.password.length > 4096) {
    throw new TypeError("SMTP username and password are required and must be within supported limits.");
  }
}

export function encryptDeliveryCredentialBundle(
  credentials: DeliveryCredentialBundle,
  masterKey: Buffer,
  context: DeliveryCredentialContext,
): Buffer {
  validateCredentialBundle(credentials);
  const key = deriveKey(masterKey);
  const nonce = randomBytes(NONCE_BYTES);
  const cipher = createCipheriv("aes-256-gcm", key, nonce);
  cipher.setAAD(aad(context));
  const plaintext = Buffer.from(JSON.stringify(credentials), "utf8");
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return Buffer.concat([MAGIC, nonce, cipher.getAuthTag(), ciphertext]);
}

export function decryptDeliveryCredentialBundle(
  envelope: Buffer,
  masterKey: Buffer,
  context: DeliveryCredentialContext,
): DeliveryCredentialBundle {
  if (!Buffer.isBuffer(envelope) || envelope.length <= MAGIC.length + NONCE_BYTES + TAG_BYTES) {
    throw new TypeError("Invalid delivery credential envelope.");
  }
  if (!envelope.subarray(0, MAGIC.length).equals(MAGIC)) {
    throw new TypeError("Unsupported delivery credential envelope version.");
  }

  const key = deriveKey(masterKey);
  const nonceStart = MAGIC.length;
  const tagStart = nonceStart + NONCE_BYTES;
  const ciphertextStart = tagStart + TAG_BYTES;
  const decipher = createDecipheriv("aes-256-gcm", key, envelope.subarray(nonceStart, tagStart));
  decipher.setAAD(aad(context));
  decipher.setAuthTag(envelope.subarray(tagStart, ciphertextStart));
  const plaintext = Buffer.concat([
    decipher.update(envelope.subarray(ciphertextStart)),
    decipher.final(),
  ]).toString("utf8");

  let parsed: unknown;
  try {
    parsed = JSON.parse(plaintext);
  } catch {
    throw new TypeError("Invalid delivery credential payload.");
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new TypeError("Invalid delivery credential payload.");
  }
  const bundle = parsed as DeliveryCredentialBundle;
  validateCredentialBundle(bundle);
  return bundle;
}

export function encryptDeliveryCredentials(
  credentials: SmtpCredentials,
  masterKey: Buffer,
  context: DeliveryCredentialContext,
): Buffer {
  if (context.channel !== "email") {
    throw new TypeError("SMTP credentials must be bound to the email channel.");
  }
  validateSmtpCredentials(credentials);
  return encryptDeliveryCredentialBundle(credentials, masterKey, context);
}

export function decryptDeliveryCredentials(
  envelope: Buffer,
  masterKey: Buffer,
  context: DeliveryCredentialContext,
): SmtpCredentials {
  if (context.channel !== "email") {
    throw new TypeError("SMTP credentials must be bound to the email channel.");
  }
  const bundle = decryptDeliveryCredentialBundle(envelope, masterKey, context);
  if (typeof bundle.username !== "string" || typeof bundle.password !== "string") {
    throw new TypeError("Invalid SMTP credential payload.");
  }
  const credentials = { username: bundle.username, password: bundle.password };
  validateSmtpCredentials(credentials);
  return credentials;
}
