import assert from "node:assert/strict";
import { appendFileSync } from "node:fs";
import { Pool } from "pg";
import { processPendingEmailDeliveries } from "../dist/src/notification-worker.js";
import { encryptContactValue } from "../dist/src/contact-crypto.js";

const organizationId = "22222222-2222-4222-8222-222222222222";
const contactKey = Buffer.from(process.env.EVENTOR_CONTACT_ENCRYPTION_KEY ?? "", "base64");
const deliveryKey = Buffer.from(process.env.EVENTOR_DELIVERY_CREDENTIALS_KEY ?? "", "base64");
assert.equal(contactKey.length, 32, "contact encryption key must be 32 bytes");
assert.equal(deliveryKey.length, 32, "delivery credential key must be 32 bytes");

const migrator = new Pool({ connectionString: process.env.MIGRATOR_URL });
const worker = new Pool({ connectionString: process.env.WORKER_URL });
const recipients = [
  ["94200000-0000-4000-8000-000000000001", "worker-eligible@example.invalid"],
  ["94200000-0000-4000-8000-000000000002", "worker-no-consent@example.invalid"],
  ["94200000-0000-4000-8000-000000000003", "worker-previously-invited@example.invalid"],
  ["94200000-0000-4000-8000-000000000004", "worker-resend-uncertain@example.invalid"],
];

try {
  const submitted = [];
  const factoryCalls = [];
  const smtpFactory = (settings, auth) => {
    factoryCalls.push({ host: settings.host, username: auth?.username ?? null, hasPassword: Boolean(auth?.password) });
    return {
      async verify() { return true; },
      async sendMail(message) {
        submitted.push(message);
        return { messageId: message.messageId ?? "<ci-fallback@delivery.eventor.invalid>", accepted: [message.to] };
      },
      close() {},
    };
  };

  // Process exactly one queued recipient. The existing SQL state-machine smoke
  // then exercises the remaining accepted/uncertain outcomes independently.
  const totals = await processPendingEmailDeliveries(
    worker, contactKey, deliveryKey, 1, 10, smtpFactory,
  );
  const diagnosticClient = await migrator.connect();
  let deliveryDiagnostic;
  try {
    await diagnosticClient.query("BEGIN");
    await diagnosticClient.query("SET LOCAL ROLE eventor_owner");
    await diagnosticClient.query("SELECT set_config('app.organization_id',$1,true)", [organizationId]);
    const diagnostic = await diagnosticClient.query(
      `SELECT attempt.id AS attempt_id, attempt.status AS attempt_status, attempt.failure_code AS attempt_failure_code,
              latest.status AS latest_event_status, latest.failure_code AS latest_event_failure_code,
              latest.provider_name, latest.source, latest.provider_message_reference
         FROM eogp.event_notification_delivery_attempts attempt
         LEFT JOIN LATERAL (
           SELECT status,failure_code,provider_name,source,created_at
             FROM eogp.event_notification_delivery_attempt_events
            WHERE organization_id=attempt.organization_id AND attempt_id=attempt.id
            ORDER BY created_at DESC,id DESC LIMIT 1
         ) latest ON true
        WHERE attempt.organization_id=$1
        ORDER BY latest.created_at DESC NULLS LAST, attempt.id DESC LIMIT 1`,
      [organizationId],
    );
    deliveryDiagnostic = diagnostic.rows[0] ?? null;
    await diagnosticClient.query("COMMIT");
  } catch (error) {
    await diagnosticClient.query("ROLLBACK");
    throw error;
  } finally {
    diagnosticClient.release();
  }

  assert.ok(deliveryDiagnostic?.attempt_id, "worker did not expose a completed attempt for provider reconciliation");
  assert.ok(deliveryDiagnostic?.provider_message_reference, "worker did not persist the stable provider Message-ID");
  if (process.env.GITHUB_ENV) {
    appendFileSync(
      process.env.GITHUB_ENV,
      `CI_WORKER_ATTEMPT_ID=${deliveryDiagnostic.attempt_id}\\nCI_WORKER_MESSAGE_REFERENCE=${deliveryDiagnostic.provider_message_reference}\\n`,
    );
  }
  const callbackClient = await worker.connect();
  try {
    await callbackClient.query("BEGIN");
    await callbackClient.query("SELECT set_config('app.organization_id',$1,true)", [organizationId]);
    const firstCallback = await callbackClient.query(
      "SELECT eogp.record_verified_notification_provider_event($1::uuid,$2::text,$3::text,$4::uuid,$5::text,$6::text,$7::text) AS result",
      [organizationId, "smtp", "ci-provider-event-1", deliveryDiagnostic.attempt_id,
        deliveryDiagnostic.provider_message_reference, "delivered", "a".repeat(64)],
    );
    const firstResult = firstCallback.rows[0]?.result;
    assert.equal(firstResult?.status, "delivered");
    assert.equal(firstResult?.duplicate, false);
    const duplicateCallback = await callbackClient.query(
      "SELECT eogp.record_verified_notification_provider_event($1::uuid,$2::text,$3::text,$4::uuid,$5::text,$6::text,$7::text) AS result",
      [organizationId, "smtp", "ci-provider-event-1", deliveryDiagnostic.attempt_id,
        deliveryDiagnostic.provider_message_reference, "delivered", "a".repeat(64)],
    );
    assert.equal(duplicateCallback.rows[0]?.result?.duplicate, true);
    await callbackClient.query("COMMIT");
  } catch (error) {
    await callbackClient.query("ROLLBACK");
    throw error;
  } finally {
    callbackClient.release();
  }

  console.log(JSON.stringify({ totals, factoryCalls, submittedCount: submitted.length, deliveryDiagnostic }));
  assert.equal(totals.emailAttempts, 1);
  assert.equal(totals.emailSent, 1);
  assert.equal(totals.emailFailed, 0);
  assert.equal(totals.emailUncertain, 0);
  assert.equal(submitted.length, 1);
  assert.match(submitted[0].to, /@example\.invalid$/);
  assert.match(submitted[0].text, /Događaj je otkazan./);
  console.log(JSON.stringify({
    status: "passed",
    attempts: totals.emailAttempts,
    sent: totals.emailSent,
    failed: totals.emailFailed,
    uncertain: totals.emailUncertain,
    smtpSubmissions: submitted.length,
  }));
} finally {
  await Promise.all([migrator.end(), worker.end()]);
}
