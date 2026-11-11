import assert from "node:assert/strict";
import test from "node:test";
import {
  decryptDeliveryCredentials,
  encryptDeliveryCredentials,
} from "../src/delivery-credentials-crypto.js";

const key = Buffer.alloc(32, 0x5a);
const context = {
  organizationId: "22222222-2222-4222-8222-222222222222",
  channel: "email" as const,
};
const credentials = {
  username: "mailer@example.test",
  password: "never-store-this-in-plaintext",
};

test("EDC1 encrypts SMTP credentials and round-trips only in the same tenant context", () => {
  const encrypted = encryptDeliveryCredentials(credentials, key, context);
  assert.equal(encrypted.subarray(0, 4).toString("ascii"), "EDC1");
  assert.equal(encrypted.includes(Buffer.from(credentials.password)), false);
  assert.deepEqual(decryptDeliveryCredentials(encrypted, key, context), credentials);
});

test("delivery credentials cannot be moved to another organization", () => {
  const encrypted = encryptDeliveryCredentials(credentials, key, context);
  assert.throws(() => decryptDeliveryCredentials(encrypted, key, {
    ...context,
    organizationId: "33333333-3333-4333-8333-333333333333",
  }));
});

test("delivery credentials cannot be moved between email and SMS channels", () => {
  const encrypted = encryptDeliveryCredentials(credentials, key, context);
  assert.throws(() => decryptDeliveryCredentials(encrypted, key, {
    ...context,
    channel: "sms",
  }));
});

test("delivery credentials cannot be decrypted with another key", () => {
  const encrypted = encryptDeliveryCredentials(credentials, key, context);
  assert.throws(() => decryptDeliveryCredentials(encrypted, Buffer.alloc(32, 0x2a), context));
});

test("EDC1 rejects malformed, unknown-version and tampered envelopes", () => {
  assert.throws(() => decryptDeliveryCredentials(Buffer.from("bad"), key, context));
  const encrypted = encryptDeliveryCredentials(credentials, key, context);
  const unknown = Buffer.from(encrypted);
  unknown.write("EDC2", 0, "ascii");
  assert.throws(() => decryptDeliveryCredentials(unknown, key, context));
  const tampered = Buffer.from(encrypted);
  const index = tampered.length - 1;
  tampered.writeUInt8(tampered.readUInt8(index) ^ 1, index);
  assert.throws(() => decryptDeliveryCredentials(tampered, key, context));
});

test("credential encryption rejects weak keys and empty credentials", () => {
  assert.throws(() => encryptDeliveryCredentials(credentials, Buffer.alloc(16), context));
  assert.throws(() => encryptDeliveryCredentials({ username: "", password: "x" }, key, context));
  assert.throws(() => encryptDeliveryCredentials({ username: "user", password: "" }, key, context));
});
