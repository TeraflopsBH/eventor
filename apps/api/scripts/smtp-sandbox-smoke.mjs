import assert from "node:assert/strict";
import { sendSmtpTestMessage } from "../dist/src/smtp-transport.js";

function required(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing required SMTP sandbox setting: ${name}`);
  return value;
}
const port = Number(required("EVENTOR_SMTP_PORT"));
assert.ok(Number.isInteger(port) && port >= 1 && port <= 65535, "SMTP port must be valid");
const transportSecurity = required("EVENTOR_SMTP_TRANSPORT_SECURITY");
assert.ok(["starttls", "implicit_tls"].includes(transportSecurity), "SMTP transport security must be starttls or implicit_tls");
const authMode = required("EVENTOR_SMTP_AUTH_MODE");
assert.ok(["none", "password"].includes(authMode), "SMTP auth mode must be none or password");
const credentials = authMode === "password"
  ? { username: required("EVENTOR_SMTP_USERNAME"), password: required("EVENTOR_SMTP_PASSWORD") }
  : null;
const settings = {
  host: required("EVENTOR_SMTP_HOST"),
  port,
  transportSecurity,
  authMode,
  senderEmail: required("EVENTOR_SMTP_SENDER_EMAIL"),
  senderName: process.env.EVENTOR_SMTP_SENDER_NAME?.trim() || "Eventor CI",
  replyTo: process.env.EVENTOR_SMTP_REPLY_TO?.trim() || null,
  connectionTimeoutMs: 15000,
};
const result = await sendSmtpTestMessage(
  settings,
  credentials,
  required("EVENTOR_SMTP_TO"),
);
assert.ok(result.accepted.length > 0, "SMTP sandbox did not accept the configured recipient");
process.stdout.write(JSON.stringify({
  status: "passed",
  providerHost: settings.host,
  transportSecurity: settings.transportSecurity,
  acceptedRecipientCount: result.accepted.length,
}) + "\n");
