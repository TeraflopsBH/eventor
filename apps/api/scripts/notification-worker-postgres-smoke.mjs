import assert from "node:assert/strict";
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
  const client = await migrator.connect();
  try {
    await client.query("BEGIN");
    await client.query("SET LOCAL ROLE eventor_owner");
    await client.query("SELECT set_config('app.organization_id',$1,true)", [organizationId]);

    for (const [personId, address] of recipients) {
      const encrypted = encryptContactValue(address, contactKey, {
        organizationId,
        contactKind: "email",
      });
      const updated = await client.query(
        `UPDATE eogp.person_contact_points
            SET encrypted_value=$3
          WHERE organization_id=$1 AND person_id=$2::uuid AND contact_kind='email'`,
        [organizationId, personId, encrypted],
      );
      assert.equal(updated.rowCount, 1, `expected one email contact for fixture person ${personId}`);
    }

    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }

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
      `SELECT attempt.status AS attempt_status, attempt.failure_code AS attempt_failure_code,
              latest.status AS latest_event_status, latest.failure_code AS latest_event_failure_code,
              latest.provider_name, latest.source
         FROM eogp.event_notification_delivery_attempts attempt
         LEFT JOIN LATERAL (
           SELECT status,failure_code,provider_name,source
             FROM eogp.event_notification_delivery_attempt_events
            WHERE organization_id=attempt.organization_id AND attempt_id=attempt.id
            ORDER BY created_at DESC,id DESC LIMIT 1
         ) latest ON true
        WHERE attempt.organization_id=$1
        ORDER BY attempt.created_at DESC LIMIT 1`,
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
