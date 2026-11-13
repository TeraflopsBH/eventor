import { Pool } from "pg";
import { runEventNotificationWorker } from "./notification-worker.js";

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

const contactEncryptionKey = requiredKey("EVENTOR_CONTACT_ENCRYPTION_KEY");
const deliveryCredentialsEncryptionKey = requiredKey("EVENTOR_DELIVERY_CREDENTIALS_KEY");
function optionalPublicAppBaseUrl(): string | undefined {
  const raw = process.env.EVENTOR_PUBLIC_APP_BASE_URL?.trim();
  if (!raw) return undefined;
  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    throw new Error("EVENTOR_PUBLIC_APP_BASE_URL must be a valid absolute HTTPS URL.");
  }
  if (parsed.protocol !== "https:" || parsed.username || parsed.password || parsed.search || parsed.hash) {
    throw new Error("EVENTOR_PUBLIC_APP_BASE_URL must use HTTPS and must not contain credentials, query parameters or a fragment.");
  }
  return parsed.toString().replace(/\\/+$/, "");
}
const publicAppBaseUrl = optionalPublicAppBaseUrl();

const pool = new Pool({
  connectionString: required("EVENTOR_WORKER_DATABASE_URL"),
  max: positiveInteger("EVENTOR_WORKER_POOL_MAX", 5, 30),
  application_name: "eventor-notification-worker",
});

pool.on("error", (error) => {
  process.stderr.write(JSON.stringify({
    level: "error",
    event: "worker_pool_error",
    message: error.message,
  }) + "\n");
});

async function shutdown(signal: string): Promise<void> {
  process.stdout.write(JSON.stringify({ level: "info", event: "worker_shutdown", signal }) + "\n");
  await pool.end();
  process.exit(0);
}
process.once("SIGINT", () => { void shutdown("SIGINT"); });
process.once("SIGTERM", () => { void shutdown("SIGTERM"); });

try {
  await runEventNotificationWorker(pool, {
    batchSize: positiveInteger("EVENTOR_WORKER_BATCH_SIZE", 20, 100),
    maxTenantsPerPoll: positiveInteger("EVENTOR_WORKER_TENANT_LIMIT", 100, 1000),
    idlePollMs: positiveInteger("EVENTOR_WORKER_IDLE_POLL_MS", 3000, 60000),
    errorPollMs: positiveInteger("EVENTOR_WORKER_ERROR_POLL_MS", 5000, 60000),
    contactEncryptionKey,
    deliveryCredentialsEncryptionKey,
    ...(publicAppBaseUrl ? { publicAppBaseUrl } : {}),
    onBatch: (totals) => {
      process.stdout.write(JSON.stringify({
        level: "info",
        event: "event_notification_outbox_batch",
        ...totals,
      }) + "\n");
    },
    onError: (error) => {
      process.stderr.write(JSON.stringify({
        level: "error",
        event: "event_notification_worker_poll_failed",
        message: error instanceof Error ? error.message : "unknown error",
      }) + "\n");
    },
  });
} catch (error) {
  process.stderr.write(JSON.stringify({
    level: "fatal",
    event: "event_notification_worker_failed",
    message: error instanceof Error ? error.message : "unknown error",
  }) + "\n");
  await pool.end();
  process.exitCode = 1;
}
