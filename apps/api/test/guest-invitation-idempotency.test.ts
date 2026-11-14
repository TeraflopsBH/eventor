import assert from "node:assert/strict";
import test from "node:test";
import { guestInvitationIssuanceIdempotencyDigest } from "../src/guest-invitation-idempotency.js";

test("guest invitation issuance idempotency is scoped to membership, event and participation", () => {
  const key = "same-client-key";
  const first = guestInvitationIssuanceIdempotencyDigest("membership-a", "event-a", "participation-a", null, key);
  const secondMember = guestInvitationIssuanceIdempotencyDigest("membership-b", "event-a", "participation-a", null, key);
  const secondEvent = guestInvitationIssuanceIdempotencyDigest("membership-a", "event-b", "participation-a", null, key);
  const secondParticipation = guestInvitationIssuanceIdempotencyDigest("membership-a", "event-a", "participation-b", null, key);
  assert.match(first, /^[0-9a-f]{64}$/);
  assert.notEqual(first, secondMember);
  assert.notEqual(first, secondEvent);
  assert.notEqual(first, secondParticipation);
  assert.equal(first, guestInvitationIssuanceIdempotencyDigest("membership-a", "event-a", "participation-a", null, key));
  assert.notEqual(
    first,
    guestInvitationIssuanceIdempotencyDigest("membership-a", "event-a", "participation-a", "invitation-1", key),
  );
});
