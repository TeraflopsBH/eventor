import assert from "node:assert/strict";
import test from "node:test";
import {
  classifySmtpFailure,
  renderNotificationTemplate,
  sendSmtpTestMessage,
  type SmtpSettings,
  type SmtpTransport,
} from "../src/smtp-transport.js";
import type { SmtpCredentials } from "../src/delivery-credentials-crypto.js";

const settings: SmtpSettings = {
  host: "smtp.example.test",
  port: 587,
  transportSecurity: "starttls",
  authMode: "password",
  senderEmail: "events@example.test",
  senderName: "Eventor",
  connectionTimeoutMs: 15000,
};
const credentials: SmtpCredentials = {
  username: "mailer@example.test",
  password: "not-a-real-password",
};

test("SMTP test message verifies the connection, sends only to the explicit recipient and closes transport", async () => {
  const calls: string[] = [];
  const result = await sendSmtpTestMessage(
    settings,
    credentials,
    "operator@example.test",
    () => ({
      async verify() { calls.push("verify"); return true; },
      async sendMail(message) {
        calls.push("send");
        assert.equal(message.to, "operator@example.test");
        assert.equal(message.subject, "[Eventor] SMTP configuration test");
        assert.match(message.text, /No event notification was sent/);
        return { messageId: "test-message-id", accepted: ["operator@example.test"] };
      },
      close() { calls.push("close"); },
    }),
  );
  assert.deepEqual(calls, ["verify", "send", "close"]);
  assert.equal(result.messageId, "test-message-id");
});

test("SMTP test never sends if connection verification fails and still closes transport", async () => {
  const calls: string[] = [];
  await assert.rejects(sendSmtpTestMessage(
    settings,
    credentials,
    "operator@example.test",
    () => ({
      async verify() { calls.push("verify"); return false; },
      async sendMail() { calls.push("send"); return { messageId: "", accepted: [] }; },
      close() { calls.push("close"); },
    }),
  ));
  assert.deepEqual(calls, ["verify", "close"]);
});

test("notification template renderer supports only known placeholders", () => {
  assert.equal(
    renderNotificationTemplate("Event: {{event.title}} ({{event.code}})", {
      "event.title": "Annual meeting",
      "event.code": "EV-2026",
    }),
    "Event: Annual meeting (EV-2026)",
  );
  assert.throws(() => renderNotificationTemplate("{{person.password}}", {}), /Unsupported notification template placeholder/);
});

test("SMTP failure classifier distinguishes retryable, permanent and ambiguous outcomes", () => {
  assert.deepEqual(classifySmtpFailure({ code: "ECONNRESET" }), {
    outcome: "failed", code: "SMTP_CONNECTION",
  });
  assert.deepEqual(classifySmtpFailure({ responseCode: 451 }), {
    outcome: "failed", code: "SMTP_4XX",
  });
  assert.deepEqual(classifySmtpFailure({ responseCode: 550 }), {
    outcome: "failed", code: "SMTP_5XX",
  });
  assert.deepEqual(classifySmtpFailure({ command: "DATA" }), {
    outcome: "uncertain", code: "SMTP_UNKNOWN",
  });
});
