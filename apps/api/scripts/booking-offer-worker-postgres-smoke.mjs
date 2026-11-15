import assert from "node:assert/strict";
import { Pool } from "pg";
import { processPendingBookingOfferEmailDeliveries } from "../dist/src/notification-worker.js";
import { encryptContactValue } from "../dist/src/contact-crypto.js";

const organizationId = "22222222-2222-4222-8222-222222222222";
const capability = "A".repeat(43);
const contactKey = Buffer.from(process.env.EVENTOR_CONTACT_ENCRYPTION_KEY ?? "", "base64");
const deliveryKey = Buffer.from(process.env.EVENTOR_DELIVERY_CREDENTIALS_KEY ?? "", "base64");

assert.equal(contactKey.length, 32, "contact encryption key must be 32 bytes");
assert.equal(deliveryKey.length, 32, "delivery credential key must be 32 bytes");

const migrator = new Pool({ connectionString: process.env.MIGRATOR_URL });
const worker = new Pool({ connectionString: process.env.WORKER_URL });
const submitted = [];
const transportCreations = [];

const smtpFactory = (settings, credentials) => {
  transportCreations.push({
    host: settings.host,
    username: credentials?.username ?? null,
    hasPassword: Boolean(credentials?.password),
  });
  assert.equal(settings.host, "smtp.resend.com");
  assert.equal(credentials?.username, "resend");
  assert.equal(credentials?.password, "ci-only-synthetic-provider-token");
  return {
    async verify() { return true; },
    async sendMail(message) {
      submitted.push(message);
      return {
        messageId: "<ci-booking-offer-worker@delivery.eventor.invalid>",
        accepted: [message.to],
      };
    },
    close() {},
  };
};

const transientFailureFactory = () => ({
  async verify() { return true; },
  async sendMail() {
    throw Object.assign(new Error("synthetic connection reset"), { code: "ECONNRESET" });
  },
  close() {},
});

try {
  const session = await worker.query("SELECT session_user");
  assert.equal(session.rows[0]?.session_user, "eventor_worker", "worker test must use the real eventor_worker login");

  const emailCiphertext = encryptContactValue("booking-offer-worker@example.invalid", contactKey, {
    organizationId,
    contactKind: "email",
  });
  const capabilityCiphertext = encryptContactValue(capability, contactKey, {
    organizationId,
    contactKind: "other",
  });

  const owner = await migrator.connect();
  let inquiryId;
  let deliveryId;
  try {
    await owner.query("BEGIN");
    await owner.query("SET LOCAL ROLE eventor_owner");
    await owner.query("SELECT set_config('app.organization_id',$1,true)", [organizationId]);
    const fixture = await owner.query(
      "SELECT delivery.id AS delivery_id,draft.source_inquiry_id AS inquiry_id " +
      "FROM eogp.booking_offer_email_deliveries delivery " +
      "JOIN eogp.booking_offers offer ON offer.organization_id=delivery.organization_id AND offer.id=delivery.offer_id " +
      "JOIN eogp.booking_drafts draft ON draft.organization_id=offer.organization_id AND draft.id=offer.draft_id " +
      "WHERE delivery.organization_id=$1 AND delivery.idempotency_key_sha256=$2",
      [organizationId, "4".repeat(64)],
    );
    assert.equal(fixture.rowCount, 1, "persistent booking-offer fixture was not found");
    inquiryId = fixture.rows[0].inquiry_id;
    deliveryId = fixture.rows[0].delivery_id;
    assert.match(inquiryId, /^[0-9a-f-]{36}$/i);
    assert.match(deliveryId, /^[0-9a-f-]{36}$/i);

    const inquiryUpdate = await owner.query(
      "UPDATE eogp.booking_inquiries SET requester_email_ciphertext=$3 WHERE organization_id=$1 AND id=$2::uuid",
      [organizationId, inquiryId, emailCiphertext],
    );
    assert.equal(inquiryUpdate.rowCount, 1, "synthetic inquiry email was not updated");
    const deliveryUpdate = await owner.query(
      "UPDATE eogp.booking_offer_email_deliveries SET recipient_ciphertext=$3, capability_ciphertext=$4 WHERE organization_id=$1 AND id=$2::uuid AND status='queued'",
      [organizationId, deliveryId, emailCiphertext, capabilityCiphertext],
    );
    assert.equal(deliveryUpdate.rowCount, 1, "synthetic queued offer delivery was not updated");
    await owner.query("COMMIT");
  } catch (error) {
    await owner.query("ROLLBACK");
    throw error;
  } finally {
    owner.release();
  }

  // First submission fails transiently. The database must schedule a bounded
  // retry rather than losing the delivery or marking it permanently failed.
  const failed = await processPendingBookingOfferEmailDeliveries(
    worker, contactKey, deliveryKey, "https://app.example.invalid", 1, 10, transientFailureFactory,
  );
  assert.equal(failed.bookingOfferEmailAttempts, 1);
  assert.equal(failed.bookingOfferEmailFailed, 1);
  assert.equal(failed.bookingOfferEmailRetriesScheduled, 1);

  const retryPreparation = await migrator.connect();
  try {
    await retryPreparation.query("BEGIN");
    await retryPreparation.query("SET LOCAL ROLE eventor_owner");
    await retryPreparation.query("SELECT set_config('app.organization_id',$1,true)", [organizationId]);
    const queued = await retryPreparation.query(
      "SELECT status,attempt_count,last_failure_code FROM eogp.booking_offer_email_deliveries WHERE organization_id=$1 AND id=$2::uuid",
      [organizationId, deliveryId],
    );
    assert.equal(queued.rows[0]?.status, "queued");
    assert.equal(Number(queued.rows[0]?.attempt_count), 1);
    assert.equal(queued.rows[0]?.last_failure_code, "SMTP_CONNECTION");
    await retryPreparation.query(
      "UPDATE eogp.booking_offer_email_deliveries SET next_attempt_at=clock_timestamp()-interval '1 second' WHERE organization_id=$1 AND id=$2::uuid",
      [organizationId, deliveryId],
    );
    await retryPreparation.query(
      "UPDATE eogp.booking_offer_email_delivery_tenant_queue SET available_at=clock_timestamp()-interval '1 second' WHERE organization_id=$1",
      [organizationId],
    );
    await retryPreparation.query("COMMIT");
  } catch (error) {
    await retryPreparation.query("ROLLBACK");
    throw error;
  } finally {
    retryPreparation.release();
  }

  // Two independent worker invocations contend for the retry. The database
  // claim must allow exactly one SMTP submission.
  const [first, second] = await Promise.all([
    processPendingBookingOfferEmailDeliveries(
      worker, contactKey, deliveryKey, "https://app.example.invalid", 1, 10, smtpFactory,
    ),
    processPendingBookingOfferEmailDeliveries(
      worker, contactKey, deliveryKey, "https://app.example.invalid", 1, 10, smtpFactory,
    ),
  ]);

  assert.equal(first.bookingOfferEmailAttempts + second.bookingOfferEmailAttempts, 1);
  assert.equal(first.bookingOfferEmailSent + second.bookingOfferEmailSent, 1);
  assert.equal(first.bookingOfferEmailFailed + second.bookingOfferEmailFailed, 0);
  assert.equal(first.bookingOfferEmailUncertain + second.bookingOfferEmailUncertain, 0);
  assert.equal(submitted.length, 1, "concurrent workers submitted the same offer more than once");
  assert.equal(submitted[0].to, "booking-offer-worker@example.invalid");
  assert.equal(submitted[0].subject, "Ponuda za rezervaciju");
  assert.match(submitted[0].text, /Primili ste ponudu za rezervaciju/);
  assert.match(submitted[0].text, /Ukupan iznos ponude/);
  assert.match(submitted[0].text, new RegExp("/offers/[0-9a-f-]{36}#token=" + capability));
  assert.equal(transportCreations.length, 1);

  const diagnostic = await migrator.connect();
  let stored;
  try {
    await diagnostic.query("BEGIN");
    await diagnostic.query("SET LOCAL ROLE eventor_owner");
    await diagnostic.query("SELECT set_config('app.organization_id',$1,true)", [organizationId]);
    const result = await diagnostic.query(
      "SELECT status,attempt_count,lease_expires_at,last_failure_code,provider_message_reference,sent_at," +
      "encode(capability_ciphertext,'base64') AS capability_envelope," +
      "encode(recipient_ciphertext,'base64') AS recipient_envelope " +
      "FROM eogp.booking_offer_email_deliveries WHERE organization_id=$1 AND id=$2::uuid",
      [organizationId, deliveryId],
    );
    stored = result.rows[0];
    await diagnostic.query("COMMIT");
  } catch (error) {
    await diagnostic.query("ROLLBACK");
    throw error;
  } finally {
    diagnostic.release();
  }

  assert.equal(stored?.status, "sent");
  assert.equal(Number(stored?.attempt_count), 2);
  assert.equal(stored?.lease_expires_at, null);
  assert.equal(stored?.last_failure_code, null);
  assert.equal(stored?.provider_message_reference, "<ci-booking-offer-worker@delivery.eventor.invalid>");
  assert.ok(stored?.sent_at);
  assert.ok(stored?.capability_envelope?.startsWith("RUNQMQ"));
  assert.ok(stored?.recipient_envelope?.startsWith("RUNQMQ"));
  assert.equal(stored.capability_envelope.includes(capability), false);
  assert.equal(stored.recipient_envelope.includes("booking-offer-worker@example.invalid"), false);

  process.stdout.write(JSON.stringify({
    status: "passed",
    concurrentWorkers: 2,
    smtpSubmissions: submitted.length,
    transientRetries: 1,
    offerDeliveryStatus: stored.status,
    attemptCount: Number(stored.attempt_count),
    providerReference: stored.provider_message_reference,
  }) + "\n");
} finally {
  await Promise.all([migrator.end(), worker.end()]);
}
