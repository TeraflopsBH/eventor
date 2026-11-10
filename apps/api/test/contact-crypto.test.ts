import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import test from "node:test";
import {
  decryptContactValue,
  encryptContactValue,
} from "../src/contact-crypto.js";

const key = randomBytes(32);
const context = {
  organizationId: "22222222-2222-4222-8222-222222222222",
  contactKind: "email" as const,
};

test("contact ciphertext uses a versioned authenticated envelope and round-trips", () => {
  const value = "person@example.test";
  const encrypted = encryptContactValue(value, key, context);
  assert.equal(encrypted.subarray(0, 4).toString("ascii"), "ECP1");
  assert.equal(encrypted.includes(Buffer.from(value)), false);
  assert.equal(decryptContactValue(encrypted, key, context), value);
});

test("contact ciphertext cannot be moved to another tenant or contact kind", () => {
  const encrypted = encryptContactValue("person@example.test", key, context);
  assert.throws(() => decryptContactValue(encrypted, key, {
    ...context,
    organizationId: "33333333-3333-4333-8333-333333333333",
  }));
  assert.throws(() => decryptContactValue(encrypted, key, {
    ...context,
    contactKind: "phone",
  }));
});

test("contact ciphertext rejects malformed envelopes, wrong keys and tampering", () => {
  assert.throws(() => decryptContactValue(Buffer.from("legacy"), key, context));
  const encrypted = encryptContactValue("person@example.test", key, context);
  const altered = Buffer.from(encrypted);
  altered[altered.length - 1] ^= 1;
  assert.throws(() => decryptContactValue(altered, key, context));
  assert.throws(() => decryptContactValue(encrypted, randomBytes(32), context));
});

test("contact encryption rejects invalid keys and empty values", () => {
  assert.throws(() => encryptContactValue("x", Buffer.alloc(16), context));
  assert.throws(() => encryptContactValue("", key, context));
});
