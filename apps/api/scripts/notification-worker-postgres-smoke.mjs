import assert from "node:assert/strict";
import { Pool } from "pg";
import { processPendingEmailDeliveries } from "../dist/src/notification-worker.js";
import { encryptContactValue } from "../dist/src/contact-crypto.js";
import { encryptDeliveryCredentials } from "../dist/src/delivery-credentials-crypto.js";

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

    const credentials = encryptDeliveryCredentials(
      { username: "resend", password: "ci-only-synthetic-provider-token" },
      deliveryKey,
      { organizationId, channel: "email" },
    );
    const config = await client.query(
      `UPDATE eogp.organization_delivery_config_revisions revision
          SET credentials_ciphertext=$2
         FROM eogp.organization_delivery_config_heads head
        WHERE head.organization_id=$1
          AND head.channel='email'
          AND head.revision_id=revision.id
          AND revision.organization_id=$1`,
      [organizationId, credentials],
    );
    assert.equal(config.rowCount, 1, "expected one current email-delivery configuration revision");
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }

  const submitted = [];
  const smtpFactory = (settings, auth) => {
    assert.equal(settings.host, "smtp.resend.com");
    assert.equal(auth?.username, "resend");
    assert.equal(auth?.password, "ci-only-synthetic-provider-token");
    return {
      async verify() { return true; },
      async sendMail(message) {
        submitted.push(message);
        assert.ok(message.messageId, "Resend delivery must use the precommitted stable Message-ID");
        return { messageId: message.messageId, accepted: [message.to] };
      },
      close() {},
    };
  };

  // Process exactly one queued recipient. The existing SQL state-machine smoke
  // then exercises the remaining accepted/uncertain outcomes independently.
  const totals = await processPendingEmailDeliveries(
    worker, contactKey, deliveryKey, 1, 10, smtpFactory,
  );
  assert.equal(totals.emailAttempts, 1);
  assert.equal(totals.emailSent, 1);
  assert.equal(totals.emailFailed, 0);
  assert.equal(totals.emailUncertain, 0);
  assert.equal(submitted.length, 1);
  assert.match(submitted[0].to, /@example\.invalid$/);
  assert.match(submitted[0].text, /Notification worker integration event/);
  process.stdout.write(JSON.stringify({
    status: "passed",
    attempts: totals.emailAttempts,
    sent: totals.emailSent,
    failed: totals.emailFailed,
    uncertain: totals.emailUncertain,
    smtpSubmissions: submitted.length,
  }) + "\\n");
} finally {
  await Promise.all([migrator.end(), worker.end()]);
}
