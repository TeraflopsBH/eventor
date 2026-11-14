import assert from "node:assert/strict";
import test from "node:test";
import { guestInvitationIssuanceIdempotencyDigest } from "../src/guest-invitation-idempotency.js";

test("guest invitation issuance idempotency is scoped to the staff membership", () => {
  const key = "same-client-key";
  const first = guestInvitationIssuanceIdempotencyDigest("membership-a", null, key);
  const second = guestInvitationIssuanceIdempotencyDigest("membership-b", null, key);
  assert.match(first, /^[0-9a-f]{64}$/);
  assert.match(second, /^[0-9a-f]{64}$/);
  assert.notEqual(first, second);
  assert.equal(first, guestInvitationIssuanceIdempotencyDigest("membership-a", null, key));
  assert.notEqual(
    first,
    guestInvitationIssuanceIdempotencyDigest("membership-a", "invitation-1", key),
  );
});
