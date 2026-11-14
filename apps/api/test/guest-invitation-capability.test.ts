import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import test from "node:test";
import { createGuestInvitationCapability, hashGuestInvitationToken } from "../src/guest-invitation-capability.js";

test("hashes a 256-bit base64url invitation token without returning the secret", () => {
  const token = randomBytes(32).toString("base64url");
  const digest = hashGuestInvitationToken(token);

  assert.match(digest ?? "", /^[0-9a-f]{64}$/);
  assert.notEqual(digest, token);
  assert.equal(hashGuestInvitationToken(token), digest);
});

test("rejects malformed, non-canonical and wrong-length invitation tokens", () => {
  assert.equal(hashGuestInvitationToken(undefined), null);
  assert.equal(hashGuestInvitationToken(""), null);
  assert.equal(hashGuestInvitationToken("short"), null);
  assert.equal(hashGuestInvitationToken("A".repeat(42) + "B"), null);
  assert.equal(hashGuestInvitationToken("A".repeat(42) + "!"), null);
  assert.equal(hashGuestInvitationToken("A".repeat(44)), null);
});

test("issues independent 256-bit capabilities and exposes only a digest for persistence", () => {
  const first = createGuestInvitationCapability();
  const second = createGuestInvitationCapability();

  assert.match(first.token, /^[A-Za-z0-9_-]{43}$/);
  assert.match(first.tokenSha256, /^[0-9a-f]{64}$/);
  assert.equal(hashGuestInvitationToken(first.token), first.tokenSha256);
  assert.notEqual(first.token, second.token);
  assert.notEqual(first.tokenSha256, second.tokenSha256);
});
