import { Pool } from "pg";
import { buildApi } from "./server.js";
import { PostgresStaffSessionAuth } from "./session-auth.js";

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required environment variable: ${name}`);
  return value;
}

function requiredKey(name: string): Buffer {
  const encoded = required(name);
  if (!/^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/.test(encoded)) {
    throw new Error(`${name} must be base64-encoded.`);
  }
  const key = Buffer.from(encoded, "base64");
  if (key.length !== 32) throw new Error(`${name} must decode to exactly 32 bytes.`);
  return key;
}

function positiveInteger(name: string, fallback: number, max: number): number {
  const raw = process.env[name];
  if (!raw) return fallback;
  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1 || value > max) {
    throw new Error(`${name} must be an integer between 1 and ${max}.`);
  }
  return value;
}

const runtimePool = new Pool({
  connectionString: required("EVENTOR_RUNTIME_DATABASE_URL"),
  max: positiveInteger("EVENTOR_API_POOL_MAX", 20, 100),
  application_name: "eventor-api-runtime",
});
const authPool = new Pool({
  connectionString: required("EVENTOR_AUTH_DATABASE_URL"),
  max: positiveInteger("EVENTOR_AUTH_POOL_MAX", 5, 30),
  application_name: "eventor-api-auth",
});

const allowedOrigins = required("EVENTOR_ALLOWED_ORIGINS")
  .split(",")
  .map((origin) => origin.trim())
  .filter(Boolean);
const fingerprintKey = requiredKey("EVENTOR_AUTH_FINGERPRINT_KEY");
const privateFieldEncryptionKey = requiredKey("EVENTOR_FIELD_ENCRYPTION_KEY");
const trustedProxyAddresses = (process.env.EVENTOR_TRUST_PROXY_CIDRS ?? "")
  .split(",")
  .map((value) => value.trim())
  .filter(Boolean);

const auth = new PostgresStaffSessionAuth(authPool, {
  allowedOrigins,
  fingerprintKey,
});
const app = buildApi({
  pool: runtimePool,
  authenticateStaff: (request) => auth.authenticateStaff(request),
  verifyMutationOrigin: (request, principal) => auth.verifyMutationOrigin(request, principal),
  verifyLoginOrigin: (request) => auth.verifyLoginOrigin(request),
  createStaffSession: (request, body) => auth.createStaffSession(request, body),
  revokeStaffSession: (principal) => auth.revokeStaffSession(principal),
  getCurrentPrincipal: (principal) => auth.getCurrentPrincipal(principal),
  privateFieldEncryptionKey,
  trustedProxyAddresses,
});

const host = process.env.HOST?.trim() || "0.0.0.0";
const port = positiveInteger("PORT", 8080, 65535);

let closing = false;
async function shutdown(signal: string): Promise<void> {
  if (closing) return;
  closing = true;
  app.log.info({ signal }, "Shutting down Eventor API");
  try {
    await app.close();
  } finally {
    await Promise.allSettled([runtimePool.end(), authPool.end()]);
  }
}

process.once("SIGINT", () => { void shutdown("SIGINT"); });
process.once("SIGTERM", () => { void shutdown("SIGTERM"); });

try {
  await app.listen({ host, port });
  app.log.info({ host, port }, "Eventor API listening");
} catch (error) {
  app.log.error({ err: error }, "Eventor API failed to start");
  await Promise.allSettled([runtimePool.end(), authPool.end()]);
  process.exitCode = 1;
}
