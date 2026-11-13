import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import test from "node:test";
import { verifyResendWebhookSignature } from "../src/resend-webhook.js";

const key = Buffer.from("eventor-resend-webhook-signing-key-32-bytes", "utf8");
const signingSecret = `whsec_${key.toString("base64")}`;
const nowMs = 1_800_000_000_000;

function signature(id: string, timestamp: string, payload: string): string {
  const digest = createHmac("sha256", key)
    .update(`${id}.${timestamp}.${payload}`, "utf8")
    .digest("base64");
  return `v1,${digest}`;
}

test("Resend webhook verifier accepts a valid Svix v1 signature over the exact raw body", () => {
  const payload = '{ "type":"email.delivered", "data":{"message_id":"<m@example.test>"} }';
  const headers = {
    id: "msg_01JRESEND000000000000000000",
    timestamp: String(Math.floor(nowMs / 1000)),
    signature: signature("msg_01JRESEND000000000000000000", String(Math.floor(nowMs / 1000)), payload),
  };
  assert.equal(verifyResendWebhookSignature({ payload, headers, signingSecret, nowMs }), true);
});

test("Resend webhook verifier rejects modified raw bodies and invalid signatures", () => {
  const id = "msg_01JRESEND000000000000000000";
  const timestamp = String(Math.floor(nowMs / 1000));
  const payload = '{"type":"email.bounced"}';
  const headers = { id, timestamp, signature: signature(id, timestamp, payload) };
  assert.equal(verifyResendWebhookSignature({ payload: payload + " ", headers, signingSecret, nowMs }), false);
  assert.equal(verifyResendWebhookSignature({ payload, headers: { ...headers, signature: "v1,AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" }, signingSecret, nowMs }), false);
  assert.equal(verifyResendWebhookSignature({ payload, headers, signingSecret: "whsec_not-base64!", nowMs }), false);
});

test("Resend webhook verifier rejects stale timestamps and accepts a matching v1 among rotated signatures", () => {
  const id = "msg_01JRESEND000000000000000000";
  const timestamp = String(Math.floor(nowMs / 1000) - 301);
  const payload = '{"type":"email.delivered"}';
  const staleHeaders = { id, timestamp, signature: signature(id, timestamp, payload) };
  assert.equal(verifyResendWebhookSignature({ payload, headers: staleHeaders, signingSecret, nowMs }), false);

  const freshTimestamp = String(Math.floor(nowMs / 1000));
  const valid = signature(id, freshTimestamp, payload);
  const rotatedHeaders = {
    id,
    timestamp: freshTimestamp,
    signature: `v0,invalid v1,AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA= ${valid}`,
  };
  assert.equal(verifyResendWebhookSignature({ payload, headers: rotatedHeaders, signingSecret, nowMs }), true);
});
