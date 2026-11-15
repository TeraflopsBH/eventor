import assert from "node:assert/strict";
import { Pool } from "pg";
import { processPendingBookingOfferEmailDeliveries } from "../dist/src/notification-worker.js";
import { encryptContactValue } from "../dist/src/contact-crypto.js";

const organizationId = "22222222-2222-4222-8222-222222222222";
const actorMembershipId = "bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb";
const otherOrganizationId = "11111111-1111-4111-8111-111111111111";
const capability = "A".repeat(43);
const contactKey = Buffer.from(process.env.EVENTOR_CONTACT_ENCRYPTION_KEY ?? "", "base64");
const deliveryKey = Buffer.from(process.env.EVENTOR_DELIVERY_CREDENTIALS_KEY ?? "", "base64");

assert.equal(contactKey.length, 32, "contact encryption key must be 32 bytes");
assert.equal(deliveryKey.length, 32, "delivery credential key must be 32 bytes");

const migrator = new Pool({ connectionString: process.env.MIGRATOR_URL });
const worker = new Pool({ connectionString: process.env.WORKER_URL });
const runtime = new Pool({ connectionString: process.env.RUNTIME_URL });
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
  let offerId;
  try {
    await owner.query("BEGIN");
    await owner.query("SET LOCAL ROLE eventor_owner");
    await owner.query("SELECT set_config('app.organization_id',$1,true)", [organizationId]);
    const fixture = await owner.query(
      "SELECT delivery.id AS delivery_id,draft.source_inquiry_id AS inquiry_id,offer.id AS offer_id " +
      "FROM eogp.booking_offer_email_deliveries delivery " +
      "JOIN eogp.booking_offers offer ON offer.organization_id=delivery.organization_id AND offer.id=delivery.offer_id " +
      "JOIN eogp.booking_drafts draft ON draft.organization_id=offer.organization_id AND draft.id=offer.draft_id " +
      "WHERE delivery.organization_id=$1 AND delivery.idempotency_key_sha256=$2",
      [organizationId, "4".repeat(64)],
    );
    assert.equal(fixture.rowCount, 1, "persistent booking-offer fixture was not found");
    inquiryId = fixture.rows[0].inquiry_id;
    deliveryId = fixture.rows[0].delivery_id;
    offerId = fixture.rows[0].offer_id;
    assert.match(inquiryId, /^[0-9a-f-]{36}$/i);
    assert.match(deliveryId, /^[0-9a-f-]{36}$/i);
    assert.match(offerId, /^[0-9a-f-]{36}$/i);

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

  const afterSend = await migrator.connect();
  let sent;
  try {
    await afterSend.query("BEGIN");
    await afterSend.query("SET LOCAL ROLE eventor_owner");
    await afterSend.query("SELECT set_config('app.organization_id',$1,true)", [organizationId]);
    const result = await afterSend.query(
      "SELECT status,attempt_count,manual_retry_count,lease_expires_at,last_failure_code," +
      "provider_message_reference,sent_at,encode(capability_ciphertext,'base64') AS capability_envelope," +
      "encode(recipient_ciphertext,'base64') AS recipient_envelope " +
      "FROM eogp.booking_offer_email_deliveries WHERE organization_id=$1 AND id=$2::uuid",
      [organizationId, deliveryId],
    );
    sent = result.rows[0];
    await afterSend.query("COMMIT");
  } catch (error) {
    await afterSend.query("ROLLBACK");
    throw error;
  } finally {
    afterSend.release();
  }

  assert.equal(sent?.status, "sent");
  assert.equal(Number(sent?.attempt_count), 2);
  assert.equal(Number(sent?.manual_retry_count), 0);
  assert.equal(sent?.lease_expires_at, null);
  assert.equal(sent?.last_failure_code, null);
  assert.equal(sent?.provider_message_reference, "<ci-booking-offer-worker@delivery.eventor.invalid>");
  assert.ok(sent?.sent_at);
  assert.ok(sent?.capability_envelope?.startsWith("RUNQMQ"));
  assert.ok(sent?.recipient_envelope?.startsWith("RUNQMQ"));
  assert.equal(sent.capability_envelope.includes(capability), false);
  assert.equal(sent.recipient_envelope.includes("booking-offer-worker@example.invalid"), false);

  // Simulate a worker crash after claim: an expired sending lease must become
  // uncertain and must never be silently sent again.
  const expiredLease = await migrator.connect();
  try {
    await expiredLease.query("BEGIN");
    await expiredLease.query("SET LOCAL ROLE eventor_owner");
    await expiredLease.query("SELECT set_config('app.organization_id',$1,true)", [organizationId]);
    const changed = await expiredLease.query(
      "UPDATE eogp.booking_offer_email_deliveries " +
      "SET status='sending',lease_expires_at=clock_timestamp()-interval '1 second'," +
      "sent_at=NULL,provider_message_reference=NULL,last_failure_code=NULL,updated_at=clock_timestamp() " +
      "WHERE organization_id=$1 AND id=$2::uuid AND status='sent'",
      [organizationId, deliveryId],
    );
    assert.equal(changed.rowCount, 1);
    await expiredLease.query(
      "INSERT INTO eogp.booking_offer_email_delivery_tenant_queue(organization_id,available_at,updated_at) " +
      "VALUES ($1,clock_timestamp()-interval '1 second',clock_timestamp()) " +
      "ON CONFLICT (organization_id) DO UPDATE SET available_at=EXCLUDED.available_at,updated_at=EXCLUDED.updated_at",
      [organizationId],
    );
    await expiredLease.query("COMMIT");
  } catch (error) {
    await expiredLease.query("ROLLBACK");
    throw error;
  } finally {
    expiredLease.release();
  }

  const expiredPoll = await processPendingBookingOfferEmailDeliveries(
    worker, contactKey, deliveryKey, "https://app.example.invalid", 1, 10, smtpFactory,
  );
  assert.equal(expiredPoll.bookingOfferEmailAttempts, 0);
  assert.equal(submitted.length, 1, "an expired lease must not trigger an automatic duplicate SMTP submission");

  const uncertainCheck = await migrator.connect();
  try {
    await uncertainCheck.query("BEGIN");
    await uncertainCheck.query("SET LOCAL ROLE eventor_owner");
    await uncertainCheck.query("SELECT set_config('app.organization_id',$1,true)", [organizationId]);
    const result = await uncertainCheck.query(
      "SELECT status,last_failure_code,lease_expires_at FROM eogp.booking_offer_email_deliveries WHERE organization_id=$1 AND id=$2::uuid",
      [organizationId, deliveryId],
    );
    assert.equal(result.rows[0]?.status, "uncertain");
    assert.equal(result.rows[0]?.last_failure_code, "SMTP_UNKNOWN");
    assert.equal(result.rows[0]?.lease_expires_at, null);
    await uncertainCheck.query("COMMIT");
  } catch (error) {
    await uncertainCheck.query("ROLLBACK");
    throw error;
  } finally {
    uncertainCheck.release();
  }

  // A staff operator must explicitly resolve the uncertain result before the
  // single permitted manual retry.
  const staff = await runtime.connect();
  try {
    await staff.query("BEGIN");
    await staff.query("SELECT set_config('app.organization_id',$1,true)", [organizationId]);
    await staff.query("SELECT set_config('app.actor_membership_id',$1,true)", [actorMembershipId]);
    const reconciled = await staff.query(
      "SELECT eogp.reconcile_booking_offer_email_delivery($1::uuid,$2::uuid,$3::uuid,$4::text,$5::text,$6::text) AS result",
      [organizationId, deliveryId, actorMembershipId, "confirmed_not_sent", "CI verified no provider acceptance after expired lease", null],
    );
    assert.equal(reconciled.rows[0]?.result?.status, "failed");
    const retried = await staff.query(
      "SELECT eogp.retry_booking_offer_email_delivery($1::uuid,$2::uuid,$3::uuid,$4::text) AS result",
      [organizationId, deliveryId, actorMembershipId, "CI one-time retry after confirmed non-acceptance"],
    );
    assert.equal(retried.rows[0]?.result?.status, "queued");
    assert.equal(Number(retried.rows[0]?.result?.manualRetryCount), 1);

    await staff.query("SAVEPOINT second_manual_retry");
    let secondRetryBlocked = false;
    try {
      const secondRetry = await staff.query(
        "SELECT eogp.retry_booking_offer_email_delivery($1::uuid,$2::uuid,$3::uuid,$4::text) AS result",
        [organizationId, deliveryId, actorMembershipId, "CI must reject a second manual retry"],
      );
      secondRetryBlocked = secondRetry.rows[0]?.result?.status !== "queued" ||
        Number(secondRetry.rows[0]?.result?.manualRetryCount) !== 2;
    } catch {
      secondRetryBlocked = true;
      await staff.query("ROLLBACK TO SAVEPOINT second_manual_retry");
    }
    assert.equal(secondRetryBlocked, true, "a second manual retry must be rejected");
    await staff.query("COMMIT");
  } catch (error) {
    await staff.query("ROLLBACK");
    throw error;
  } finally {
    staff.release();
  }

  const manualRetry = await migrator.connect();
  try {
    await manualRetry.query("BEGIN");
    await manualRetry.query("SET LOCAL ROLE eventor_owner");
    await manualRetry.query("SELECT set_config('app.organization_id',$1,true)", [organizationId]);
    await manualRetry.query(
      "UPDATE eogp.booking_offer_email_deliveries SET next_attempt_at=clock_timestamp()-interval '1 second' WHERE organization_id=$1 AND id=$2::uuid",
      [organizationId, deliveryId],
    );
    await manualRetry.query(
      "UPDATE eogp.booking_offer_email_delivery_tenant_queue SET available_at=clock_timestamp()-interval '1 second' WHERE organization_id=$1",
      [organizationId],
    );
    await manualRetry.query("COMMIT");
  } catch (error) {
    await manualRetry.query("ROLLBACK");
    throw error;
  } finally {
    manualRetry.release();
  }

  const manualSend = await processPendingBookingOfferEmailDeliveries(
    worker, contactKey, deliveryKey, "https://app.example.invalid", 1, 10, smtpFactory,
  );
  assert.equal(manualSend.bookingOfferEmailAttempts, 1);
  assert.equal(manualSend.bookingOfferEmailSent, 1);
  assert.equal(submitted.length, 2);

  const finalCheck = await migrator.connect();
  let finalState;
  try {
    await finalCheck.query("BEGIN");
    await finalCheck.query("SET LOCAL ROLE eventor_owner");
    await finalCheck.query("SELECT set_config('app.organization_id',$1,true)", [organizationId]);
    const result = await finalCheck.query(
      "SELECT delivery.status,delivery.attempt_count,delivery.manual_retry_count,delivery.last_failure_code," +
      "delivery.lease_expires_at,delivery.sent_at," +
      "(SELECT count(*) FROM eogp.audit_events audit WHERE audit.organization_id=delivery.organization_id " +
      "AND audit.aggregate_id=delivery.offer_id AND audit.action='booking.offer.email_sent') AS sent_audit_count," +
      "(SELECT count(*) FROM eogp.audit_events audit WHERE audit.organization_id=delivery.organization_id " +
      "AND audit.aggregate_id=delivery.offer_id AND audit.action='booking.offer.email_uncertain' " +
      "AND audit.safe_metadata->>'source'='expired_worker_lease') AS expired_lease_audit_count," +
      "NOT EXISTS (SELECT 1 FROM eogp.audit_events audit WHERE audit.organization_id=delivery.organization_id " +
      "AND audit.aggregate_id=delivery.offer_id AND (audit.safe_metadata::text LIKE '%'||$3||'%' " +
      "OR audit.safe_metadata::text LIKE '%'||$4||'%')) AS audit_redacted " +
      "FROM eogp.booking_offer_email_deliveries delivery " +
      "WHERE delivery.organization_id=$1 AND delivery.id=$2::uuid",
      [organizationId, deliveryId, "booking-offer-worker@example.invalid", capability],
    );
    finalState = result.rows[0];
    await finalCheck.query("COMMIT");
  } catch (error) {
    await finalCheck.query("ROLLBACK");
    throw error;
  } finally {
    finalCheck.release();
  }

  assert.equal(finalState?.status, "sent");
  // Manual retry resets the per-cycle attempt counter before redelivery.
  assert.equal(Number(finalState?.attempt_count), 1);
  assert.equal(Number(finalState?.manual_retry_count), 1);
  assert.equal(Number(finalState?.sent_audit_count), 2);
  assert.equal(Number(finalState?.expired_lease_audit_count), 1);
  assert.equal(finalState?.audit_redacted, true);
  assert.equal(finalState?.last_failure_code, null);
  assert.equal(finalState?.lease_expires_at, null);
  assert.ok(finalState?.sent_at);

  // A real worker login cannot claim another tenant's delivery.
  const crossTenantWorker = await worker.connect();
  try {
    await crossTenantWorker.query("BEGIN");
    await crossTenantWorker.query("SELECT set_config('app.organization_id',$1,true)", [otherOrganizationId]);
    let denied = false;
    try {
      await crossTenantWorker.query(
        "SELECT * FROM eogp.claim_booking_offer_email_delivery($1::uuid)",
        [organizationId],
      );
    } catch (error) {
      denied = error.code === "42501";
      await crossTenantWorker.query("ROLLBACK");
    }
    assert.equal(denied, true, "worker must not claim another tenant's delivery");
  } finally {
    crossTenantWorker.release();
  }

  process.stdout.write(JSON.stringify({
    status: "passed",
    realWorkerLogin: session.rows[0].session_user,
    transientRetries: 1,
    concurrentWorkers: 2,
    expiredLeaseReconciled: true,
    manualRetries: Number(finalState.manual_retry_count),
    duplicateManualRetryRejected: true,
    finalDeliveryStatus: finalState.status,
    attemptCount: Number(finalState.attempt_count),
    smtpSubmissions: submitted.length,
  }) + "\n");
} finally {
  await Promise.all([migrator.end(), worker.end(), runtime.end()]);
}
