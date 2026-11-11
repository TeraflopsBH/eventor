import assert from "node:assert/strict";
import test from "node:test";
import type { Pool, PoolClient, QueryResultRow } from "pg";
import { processPendingEmailDeliveries, processPendingEventChangeNotifications } from "../src/notification-worker.js";
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
