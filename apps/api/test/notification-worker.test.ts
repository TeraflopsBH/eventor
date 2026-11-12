import assert from "node:assert/strict";
import test from "node:test";
import type { Pool, PoolClient, QueryResultRow } from "pg";
import { processExpiredBookingOffers, processPendingBookingOfferEmailDeliveries, processPendingEmailDeliveries, processPendingEventChangeNotifications } from "../src/notification-worker.js";
import { encryptContactValue } from "../src/contact-crypto.js";
import { encryptDeliveryCredentials } from "../src/delivery-credentials-crypto.js";
import type { SmtpTransportFactory } from "../src/smtp-transport.js";

function fakePool(tenants: string[]) {
  const transactions: string[] = [];
  const released: string[] = [];
  const calls: Array<{ sql: string; values: unknown[] }> = [];

  const pool = {
    async query(sql: string, values: unknown[] = []) {
      calls.push({ sql: sql.replace(/\s+/g, " ").trim(), values });
      return {
        rows: tenants.map((organization_id) => ({ organization_id })) as QueryResultRow[],
        rowCount: tenants.length,
      };
    },
    async connect() {
      const client = {
        async query(sql: string, values: unknown[] = []) {
          const normalized = sql.replace(/\s+/g, " ").trim();
          calls.push({ sql: normalized, values });
          transactions.push(normalized);
          if (normalized.startsWith("SELECT eogp.expire_due_booking_offers")) {
            return { rows: [{ expired_count: 3 }], rowCount: 1 };
          }
          if (normalized.startsWith("SELECT eogp.process_event_notification_outbox")) {
            return {
              rows: [{
                result: {
                  processed: 2,
                  campaignPreviewsPrepared: 1,
                  deferred: 1,
                  deadLettered: 0,
                },
              }],
              rowCount: 1,
            };
          }
          return { rows: [], rowCount: 1 };
        },
        release() { released.push("released"); },
      };
      return client as unknown as PoolClient;
    },
  };
  return {
    pool: pool as unknown as Pool,
    calls,
    transactions,
    released,
  };
}

test("notification worker sets tenant context and commits one batch per tenant", async () => {
  const tenantA = "11111111-1111-4111-8111-111111111111";
  const tenantB = "22222222-2222-4222-8222-222222222222";
  const mock = fakePool([tenantA, tenantB]);

  const result = await processPendingEventChangeNotifications(mock.pool, 10, 50);

  assert.deepEqual(result, {
    tenantsVisited: 2,
    processed: 4,
    campaignPreviewsPrepared: 2,
    deferred: 2,
    deadLettered: 0,
    emailAttempts: 0,
    emailSent: 0,
    emailFailed: 0,
    emailUncertain: 0,
    emailRetriesScheduled: 0,
    bookingOffersExpired: 0,
    bookingOfferEmailAttempts: 0,
    bookingOfferEmailSent: 0,
    bookingOfferEmailFailed: 0,
    bookingOfferEmailUncertain: 0,
    bookingOfferEmailRetriesScheduled: 0,
  });
  assert.equal(mock.released.length, 2);
  assert.equal(
    mock.calls.filter((call) => call.sql.includes("set_config('app.organization_id'")).length,
    2,
  );
  assert.equal(
    mock.calls.filter((call) => call.sql.startsWith("SELECT eogp.process_event_notification_outbox")).length,
    2,
  );
  assert.equal(mock.transactions.filter((sql) => sql === "BEGIN").length, 2);
  assert.equal(mock.transactions.filter((sql) => sql === "COMMIT").length, 2);
});

test("booking offer expiry worker discovers due tenants and expires within tenant context", async () => {
  const tenantA = "11111111-1111-4111-8111-111111111111";
  const tenantB = "22222222-2222-4222-8222-222222222222";
  const mock = fakePool([tenantA, tenantB]);

  const result = await processExpiredBookingOffers(mock.pool, 25, 50);

  assert.deepEqual(result, { tenantsVisited: 2, expired: 6 });
  assert.equal(
    mock.calls.filter((call) => call.sql.includes("discover_due_booking_offer_expiry_tenants")).length,
    1,
  );
  const expiryCalls = mock.calls.filter((call) => call.sql.includes("expire_due_booking_offers"));
  assert.equal(expiryCalls.length, 2);
  assert.deepEqual(expiryCalls[0]?.values, [tenantA, 25]);
  assert.deepEqual(expiryCalls[1]?.values, [tenantB, 25]);
  assert.equal(mock.released.length, 2);
  assert.equal(mock.transactions.filter((sql) => sql === "BEGIN").length, 2);
  assert.equal(mock.transactions.filter((sql) => sql === "COMMIT").length, 2);
});

test("booking offer expiry worker rejects unsafe limits before discovery", async () => {
  const mock = fakePool([]);
  await assert.rejects(processExpiredBookingOffers(mock.pool, 501, 10), RangeError);
  assert.equal(mock.calls.length, 0);
});

test("booking offer email worker decrypts the queued capability and sends through the configured SMTP transport", async () => {
  const organizationId = "11111111-1111-4111-8111-111111111111";
  const offerId = "22222222-2222-4222-8222-222222222222";
  const offerRevisionId = "33333333-3333-4333-8333-333333333333";
  const deliveryId = "44444444-4444-4444-8444-444444444444";
  const contactKey = Buffer.alloc(32, 21);
  const deliveryKey = Buffer.alloc(32, 22);
  const capability = "A".repeat(43);
  const recipientCiphertext = encryptContactValue(
    "customer@example.test", contactKey,
    { organizationId, contactKind: "email" },
  );
  const capabilityCiphertext = encryptContactValue(
    capability, contactKey,
    { organizationId, contactKind: "other" },
  );
  const calls: string[] = [];
  const sentMessages: Array<{ to: string; subject: string; text: string }> = [];
  let closed = false;
  const job = {
    delivery_id: deliveryId,
    offer_id: offerId,
    offer_revision_id: offerRevisionId,
    capability_ciphertext: capabilityCiphertext,
    recipient_ciphertext: recipientCiphertext,
    credentials_ciphertext: null,
    smtp_settings: {
      host: "smtp.example.test",
      port: 587,
      transportSecurity: "starttls" as const,
      authMode: "none" as const,
      senderEmail: "offers@example.test",
      senderName: "Example Venue",
      replyTo: null,
      connectionTimeoutMs: 15000,
    },
    sender_email: "offers@example.test",
    sender_name: "Example Venue",
    reply_to: null,
    valid_until: new Date("2027-01-01T12:00:00.000Z"),
    currency: "BAM",
    total_amount: "125.00",
  };
  const client = {
    async query(sql: string, values: unknown[] = []) {
      const normalized = sql.replace(/\\s+/g, " ").trim();
      calls.push(normalized);
      if (normalized.startsWith("SELECT * FROM eogp.claim_booking_offer_email_delivery")) {
        return { rows: [job], rowCount: 1 };
      }
      if (normalized.startsWith("SELECT eogp.complete_booking_offer_email_delivery")) {
        assert.deepEqual(values, [organizationId, deliveryId, "sent", null, "smtp-message-id"]);
        return { rows: [{ result: { retryScheduled: false } }], rowCount: 1 };
      }
      return { rows: [], rowCount: 1 };
    },
    release() {},
  };
  const pool = {
    async query(sql: string) {
      calls.push(sql);
      return { rows: [{ organization_id: organizationId }], rowCount: 1 };
    },
    async connect() { return client; },
  } as unknown as Pool;
  const factory: SmtpTransportFactory = () => ({
    async verify() { return true; },
    async sendMail(message) {
      sentMessages.push(message);
      return { messageId: "smtp-message-id", accepted: [message.to] };
    },
    close() { closed = true; },
  });

  const result = await processPendingBookingOfferEmailDeliveries(
    pool, contactKey, deliveryKey, "https://eventor.example.test", 10, 10, factory,
  );
  assert.equal(result.bookingOfferEmailAttempts, 1);
  assert.equal(result.bookingOfferEmailSent, 1);
  assert.equal(result.bookingOfferEmailFailed, 0);
  assert.equal(result.bookingOfferEmailUncertain, 0);
  assert.equal(closed, true);
  assert.equal(sentMessages.length, 1);
  const sentMessage = sentMessages[0]!;
  assert.equal(sentMessage.to, "customer@example.test");
  assert.match(sentMessage.text, new RegExp(
    `https://eventor\\.example\\.test/offers/${offerId}#token=${capability}`,
  ));
  assert.ok(calls.some((sql) => sql === "BEGIN"));
  assert.ok(calls.some((sql) => sql === "COMMIT"));
});

test("booking offer email worker rejects a non-HTTPS public application URL before discovery", async () => {
  const mock = fakePool([]);
  await assert.rejects(
    processPendingBookingOfferEmailDeliveries(
      mock.pool, Buffer.alloc(32), Buffer.alloc(32), "http://eventor.example.test",
    ),
    /must be HTTPS/,
  );
  assert.equal(mock.calls.length, 0);
});

test("notification worker rejects unsafe batch sizes before querying", async () => {
  const mock = fakePool([]);
  await assert.rejects(
    processPendingEventChangeNotifications(mock.pool, 101, 10),
    RangeError,
  );
  assert.equal(mock.calls.length, 0);
});

test("email delivery worker decrypts tenant-bound contact and SMTP secrets only for SMTP submission", async () => {
  const organizationId = "22222222-2222-4222-8222-222222222222";
  const contactKey = Buffer.alloc(32, 0x31);
  const deliveryKey = Buffer.alloc(32, 0x42);
  const destinationCiphertext = encryptContactValue("guest@example.test", contactKey, {
    organizationId, contactKind: "email",
  });
  const credentialsCiphertext = encryptDeliveryCredentials({
    username: "smtp-user",
    password: "smtp-secret-not-for-logs",
  }, deliveryKey, { organizationId, channel: "email" });
  let claimed = false;
  let completionCalls = 0;
  const sqlCalls: string[] = [];
  const job = {
    attempt_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    campaign_id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    recipient_id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
    destination_ciphertext: destinationCiphertext,
    credentials_ciphertext: credentialsCiphertext,
    smtp_settings: {
      host: "smtp.example.test", port: 587, transportSecurity: "starttls",
      authMode: "password", senderEmail: "events@example.test",
      senderName: "Eventor", connectionTimeoutMs: 15000,
    },
    sender_email: "events@example.test",
    sender_name: "Eventor",
    reply_to: null,
    subject_template: "Update: {{event.title}}",
    body_template: "{{event.title}} ({{event.code}}) is {{event.status}}.",
    event_title: "Annual meeting",
    event_code: "EV-2026",
    event_status: "cancelled",
    decision_kind: "cancelled",
    campaign_purpose: "event_cancellation",
    starts_at: null,
    ends_at: null,
    timezone_name: "Europe/Sarajevo",
  };
  const pool = {
    async query(sql: string) {
      sqlCalls.push(sql);
      return { rows: [{ organization_id: organizationId }], rowCount: 1 };
    },
    async connect() {
      const client = {
        async query(sql: string, values: unknown[] = []) {
          const normalized = sql.replace(/\\s+/g, " ").trim();
          sqlCalls.push(normalized);
          if (normalized.startsWith("SELECT * FROM eogp.claim_next_email_delivery")) {
            if (claimed) return { rows: [], rowCount: 0 };
            claimed = true;
            return { rows: [job], rowCount: 1 };
          }
          if (normalized.startsWith("SELECT eogp.complete_email_delivery_attempt")) {
            completionCalls += 1;
            assert.equal(values[2], "sent");
            return { rows: [{ result: {
              outcome: "sent", retryScheduled: false, campaignStatus: "completed",
            } }], rowCount: 1 };
          }
          return { rows: [], rowCount: 1 };
        },
        release() {},
      };
      return client as unknown as PoolClient;
    },
  } as unknown as Pool;

  let sentTo = "";
  let subject = "";
  let body = "";
  let usedCredentials = false;
  const factory: SmtpTransportFactory = (_settings, credentials) => {
    usedCredentials = credentials?.password === "smtp-secret-not-for-logs";
    return {
      async verify() { return true; },
      async sendMail(message) {
        sentTo = message.to;
        subject = message.subject;
        body = message.text;
        return { messageId: "smtp-message-ref", accepted: [message.to] };
      },
      close() {},
    };
  };

  const result = await processPendingEmailDeliveries(
    pool, contactKey, deliveryKey, 5, 10, factory,
  );
  assert.equal(result.emailAttempts, 1);
  assert.equal(result.emailSent, 1);
  assert.equal(result.emailFailed, 0);
  assert.equal(sentTo, "guest@example.test");
  assert.equal(subject, "Update: Annual meeting");
  assert.equal(body, "Annual meeting (EV-2026) is cancelled.");
  assert.equal(usedCredentials, true);
  assert.equal(completionCalls, 1);
  assert.equal(sqlCalls.some((sql) => sql.includes("guest@example.test")), false);
});

test("email delivery worker records retryable SMTP connection failures without logging recipient data", async () => {
  const organizationId = "22222222-2222-4222-8222-222222222222";
  const contactKey = Buffer.alloc(32, 0x51);
  const deliveryKey = Buffer.alloc(32, 0x62);
  let claimed = false;
  let completedWith: unknown[] = [];
  const job = {
    attempt_id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    campaign_id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    recipient_id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
    destination_ciphertext: encryptContactValue("guest@example.test", contactKey, {
      organizationId, contactKind: "email",
    }),
    credentials_ciphertext: null,
    smtp_settings: {
      host: "smtp.example.test", port: 465, transportSecurity: "implicit_tls",
      authMode: "none", senderEmail: "events@example.test",
      senderName: "Eventor", connectionTimeoutMs: 15000,
    },
    sender_email: "events@example.test", sender_name: "Eventor", reply_to: null,
    subject_template: "Hi", body_template: "Hello",
    event_title: "Event", event_code: "E-1", event_status: "cancelled",
    decision_kind: "cancelled", campaign_purpose: "event_cancellation",
    starts_at: null, ends_at: null, timezone_name: "Europe/Sarajevo",
  };
  const pool = {
    async query() { return { rows: [{ organization_id: organizationId }], rowCount: 1 }; },
    async connect() {
      return {
        async query(sql: string, values: unknown[] = []) {
          const normalized = sql.replace(/\\s+/g, " ").trim();
          if (normalized.startsWith("SELECT * FROM eogp.claim_next_email_delivery")) {
            if (claimed) return { rows: [], rowCount: 0 };
            claimed = true;
            return { rows: [job], rowCount: 1 };
          }
          if (normalized.startsWith("SELECT eogp.complete_email_delivery_attempt")) {
            completedWith = values;
            return { rows: [{ result: {
              outcome: "failed", retryScheduled: true, campaignStatus: "sending",
            } }], rowCount: 1 };
          }
          return { rows: [], rowCount: 1 };
        },
        release() {},
      } as unknown as PoolClient;
    },
  } as unknown as Pool;
  const factory: SmtpTransportFactory = () => ({
    async verify() { return true; },
    async sendMail() { throw Object.assign(new Error("connection reset"), { code: "ECONNRESET" }); },
    close() {},
  });
  const result = await processPendingEmailDeliveries(
    pool, contactKey, deliveryKey, 5, 10, factory,
  );
  assert.equal(result.emailAttempts, 1);
  assert.equal(result.emailFailed, 1);
  assert.equal(result.emailRetriesScheduled, 1);
  assert.equal(completedWith[2], "failed");
  assert.equal(completedWith[3], "SMTP_CONNECTION");
});

test("Resend delivery prepares a stable Message-ID before SMTP and keeps it when recording acceptance", async () => {
  const organizationId = "22222222-2222-4222-8222-222222222222";
  const contactKey = Buffer.alloc(32, 0x71);
  const deliveryKey = Buffer.alloc(32, 0x72);
  const attemptId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const stableReference = "<eventor-aaaaaaaaaaaa4aaa8aaaaaaaaaaaaaaa@delivery.eventor.invalid>";
  const job = {
    attempt_id: attemptId,
    campaign_id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    recipient_id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
    destination_ciphertext: encryptContactValue("guest@example.test", contactKey, {
      organizationId, contactKind: "email",
    }),
    credentials_ciphertext: encryptDeliveryCredentials({
      username: "resend",
      password: "resend-api-key-not-real",
    }, deliveryKey, { organizationId, channel: "email" }),
    smtp_settings: {
      host: "smtp.resend.com", port: 587, transportSecurity: "starttls",
      authMode: "password", senderEmail: "events@example.test",
      senderName: "Eventor", connectionTimeoutMs: 15000,
    },
    sender_email: "events@example.test", sender_name: "Eventor", reply_to: null,
    subject_template: "Update: {{event.title}}", body_template: "Hello",
    event_title: "Event", event_code: "EV-1", event_status: "cancelled",
    decision_kind: "cancelled", campaign_purpose: "event_cancellation",
    starts_at: null, ends_at: null, timezone_name: "Europe/Sarajevo",
  };
  let claimCount = 0;
  let preparedCount = 0;
  let completionValues: unknown[] = [];
  let messageIdSent: string | undefined;
  const statements: string[] = [];
  const pool = {
    async query(sql: string) {
      statements.push(sql.replace(/\\s+/g, " ").trim());
      return { rows: [{ organization_id: organizationId }], rowCount: 1 };
    },
    async connect() {
      return {
        async query(sql: string, values: unknown[] = []) {
          const normalized = sql.replace(/\\s+/g, " ").trim();
          statements.push(normalized);
          if (normalized === "BEGIN" || normalized === "COMMIT" || normalized === "ROLLBACK") {
            return { rows: [], rowCount: 0 };
          }
          if (normalized.startsWith("SELECT set_config(")) return { rows: [], rowCount: 1 };
          if (normalized.startsWith("SELECT * FROM eogp.claim_next_email_delivery")) {
            claimCount += 1;
            return claimCount === 1
              ? { rows: [job], rowCount: 1 }
              : { rows: [], rowCount: 0 };
          }
          if (normalized.includes("eogp.prepare_resend_delivery_submission(")) {
            preparedCount += 1;
            assert.equal(values[0], organizationId);
            assert.equal(values[1], attemptId);
            return { rows: [{ reference: stableReference }], rowCount: 1 };
          }
          if (normalized.includes("eogp.complete_email_delivery_attempt(")) {
            completionValues = values;
            return { rows: [{ result: {
              outcome: "sent", retryScheduled: false, campaignStatus: "completed",
            } }], rowCount: 1 };
          }
          throw new Error("Unexpected SQL: " + normalized);
        },
        release() {},
      } as unknown as PoolClient;
    },
  } as unknown as Pool;

  const factory: SmtpTransportFactory = (_settings, credentials) => {
    assert.equal(credentials?.username, "resend");
    return {
      async verify() { return true; },
      async sendMail(message) {
        messageIdSent = message.messageId;
        assert.equal(message.to, "guest@example.test");
        return { messageId: message.messageId ?? "", accepted: [message.to] };
      },
      close() {},
    };
  };

  const result = await processPendingEmailDeliveries(
    pool, contactKey, deliveryKey, 5, 10, factory,
  );
  assert.equal(result.emailAttempts, 1);
  assert.equal(result.emailSent, 1);
  assert.equal(preparedCount, 1);
  assert.equal(messageIdSent, stableReference);
  assert.equal(completionValues[2], "sent");
  assert.equal(completionValues[4], stableReference);
  assert.ok(statements.some((sql) => sql.includes("prepare_resend_delivery_submission")));
});


test("uncertain Resend DATA outcome retains the pre-submission Message-ID for callback reconciliation", async () => {
  const organizationId = "22222222-2222-4222-8222-222222222222";
  const contactKey = Buffer.alloc(32, 0x73);
  const deliveryKey = Buffer.alloc(32, 0x74);
  const attemptId = "dddddddd-dddd-4ddd-8ddd-dddddddddddd";
  const stableReference = "<eventor-dddddddddddd4ddd8dddddddddddddd@delivery.eventor.invalid>";
  const job = {
    attempt_id: attemptId,
    campaign_id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
    recipient_id: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
    destination_ciphertext: encryptContactValue("guest@example.test", contactKey, {
      organizationId, contactKind: "email",
    }),
    credentials_ciphertext: encryptDeliveryCredentials({
      username: "resend", password: "resend-api-key-not-real",
    }, deliveryKey, { organizationId, channel: "email" }),
    smtp_settings: {
      host: "smtp.resend.com", port: 587, transportSecurity: "starttls",
      authMode: "password", senderEmail: "events@example.test",
      senderName: "Eventor", connectionTimeoutMs: 15000,
    },
    sender_email: "events@example.test", sender_name: "Eventor", reply_to: null,
    subject_template: "Update: {{event.title}}", body_template: "Hello",
    event_title: "Event", event_code: "EV-1", event_status: "cancelled",
    decision_kind: "cancelled", campaign_purpose: "event_cancellation",
    starts_at: null, ends_at: null, timezone_name: "Europe/Sarajevo",
  };
  let claimCount = 0;
  let completionValues: unknown[] = [];
  let messageIdSent: string | undefined;
  let preparedCount = 0;
  const pool = {
    async query() {
      return { rows: [{ organization_id: organizationId }], rowCount: 1 };
    },
    async connect() {
      return {
        async query(sql: string, values: unknown[] = []) {
          const normalized = sql.replace(/\\s+/g, " ").trim();
          if (normalized === "BEGIN" || normalized === "COMMIT" || normalized === "ROLLBACK") {
            return { rows: [], rowCount: 0 };
          }
          if (normalized.startsWith("SELECT set_config(")) return { rows: [], rowCount: 1 };
          if (normalized.startsWith("SELECT * FROM eogp.claim_next_email_delivery")) {
            claimCount += 1;
            return claimCount === 1 ? { rows: [job], rowCount: 1 } : { rows: [], rowCount: 0 };
          }
          if (normalized.includes("eogp.prepare_resend_delivery_submission(")) {
            preparedCount += 1;
            return { rows: [{ reference: stableReference }], rowCount: 1 };
          }
          if (normalized.includes("eogp.complete_email_delivery_attempt(")) {
            completionValues = values;
            return { rows: [{ result: {
              outcome: "uncertain", retryScheduled: false, campaignStatus: "partial",
            } }], rowCount: 1 };
          }
          throw new Error("Unexpected SQL: " + normalized);
        },
        release() {},
      } as unknown as PoolClient;
    },
  } as unknown as Pool;

  const factory: SmtpTransportFactory = () => ({
    async verify() { return true; },
    async sendMail(message) {
      messageIdSent = message.messageId;
      throw Object.assign(new Error("connection lost during SMTP DATA"), { command: "DATA" });
    },
    close() {},
  });

  const result = await processPendingEmailDeliveries(
    pool, contactKey, deliveryKey, 5, 10, factory,
  );
  assert.equal(result.emailAttempts, 1);
  assert.equal(result.emailUncertain, 1);
  assert.equal(preparedCount, 1);
  assert.equal(messageIdSent, stableReference);
  assert.equal(completionValues[2], "uncertain");
  assert.equal(completionValues[4], stableReference);
});
