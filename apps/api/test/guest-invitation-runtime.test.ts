import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import test from "node:test";
import type { Pool } from "pg";
import { buildApi } from "../src/server.js";

const organizationId = "22222222-2222-4222-8222-222222222222";
const invitationId = "33333333-3333-4333-8333-333333333333";
const token = Buffer.alloc(32, 21).toString("base64url");

function makeGuestApi() {
  const calls: Array<{ sql: string; values: unknown[] }> = [];
  const invitation = {
    organizationId,
    invitationId,
    invitationRevisionId: "44444444-4444-4444-8444-444444444444",
    eventId: "55555555-5555-4555-8555-555555555555",
    eventTitle: "Community gathering",
    eventStatus: "scheduled",
    startsAt: "2027-03-01T17:00:00.000Z",
    endsAt: "2027-03-01T21:00:00.000Z",
    timezone: "Europe/Sarajevo",
    venueSummary: { name: "Main hall" },
    locale: "bs-BA",
    allowedResponses: ["accepted", "declined", "tentative"],
    responseDeadline: null,
    responseChangeAllowed: true,
    currentResponse: null,
  };
  const client = {
    async query(sql: string, values: unknown[] = []) {
      const normalized = sql.replace(/\\s+/g, " ").trim();
      calls.push({ sql: normalized, values });
      if (["BEGIN", "COMMIT", "ROLLBACK"].includes(normalized)) {
        return { rows: [], rowCount: 0 };
      }
      if (normalized.includes("eogp.resolve_guest_invitation(")) {
        return { rows: [{ result: invitation }], rowCount: 1 };
      }
      if (normalized.includes("eogp.submit_guest_invitation_rsvp(")) {
        return {
          rows: [{
            result: {
              invitationId,
              responseId: "66666666-6666-4666-8666-666666666666",
              response: values[3],
              receivedAt: "2026-11-14T12:00:00.000Z",
              replayed: false,
            },
          }],
          rowCount: 1,
        };
      }
      if (normalized.includes("eogp.get_guest_invitation_rsvp_history(")) {
        return {
          rows: [{
            result: [{
              responseId: "66666666-6666-4666-8666-666666666666",
              response: "accepted",
              receivedAt: "2026-11-14T12:00:00.000Z",
              sequenceNumber: 1,
            }],
          }],
          rowCount: 1,
        };
      }
      throw new Error("Unexpected guest API SQL: " + normalized);
    },
    release() {},
  };
  const pool = {
    async connect() { return client; },
  } as unknown as Pool;
  const app = buildApi({
    pool,
    authenticateStaff: async () => null,
    verifyMutationOrigin: async () => false,
    contactEncryptionKey: Buffer.alloc(32, 10),
  });
  return { app, calls, invitation };
}

test("guest invitation resolution is capability-authenticated and returns no tenant identifier", async (t) => {
  const mock = makeGuestApi();
  t.after(async () => mock.app.close());

  const response = await mock.app.inject({
    method: "POST",
    url: "/guest/invitation/resolve",
    headers: {
      "x-guest-invitation-token": token,
      "idempotency-key": "guest-resolve-0001",
    },
    payload: { clientContext: "web" },
  });
  assert.equal(response.statusCode, 200);
  assert.equal(response.headers["cache-control"], "no-store, private");
  assert.equal(response.headers["referrer-policy"], "no-referrer");
  assert.equal(response.headers["x-robots-tag"], "noindex, nofollow, noarchive");
  const data = response.json<{ data: Record<string, unknown> }>().data;
  assert.equal(data.eventTitle, "Community gathering");
  assert.equal(data.organizationId, undefined);
  assert.equal(
    mock.calls.find((call) => call.sql.includes("eogp.resolve_guest_invitation("))?.values[0],
    createHash("sha256").update(Buffer.from(token, "base64url")).digest("hex"),
  );
});

test("guest RSVP submission encrypts optional notes and uses idempotency hashes", async (t) => {
  const mock = makeGuestApi();
  t.after(async () => mock.app.close());

  const response = await mock.app.inject({
    method: "POST",
    url: "/guest/invitation/me/rsvp",
    headers: {
      "x-guest-invitation-token": token,
      "idempotency-key": "guest-rsvp-0001",
    },
    payload: { response: "accepted", note: "Vegetarian meal, please." },
  });
  assert.equal(response.statusCode, 201);
  assert.equal(response.json<{ data: { response: string } }>().data.response, "accepted");
  const call = mock.calls.find((item) => item.sql.includes("eogp.submit_guest_invitation_rsvp("));
  assert.ok(call);
  assert.equal(call.values[0], createHash("sha256").update(Buffer.from(token, "base64url")).digest("hex"));
  assert.equal(call.values[1], createHash("sha256").update("guest-rsvp-0001").digest("hex"));
  const encryptedNote = call.values[4] as Buffer;
  assert.ok(Buffer.isBuffer(encryptedNote));
  assert.equal(encryptedNote.subarray(0, 4).toString("ascii"), "ECP1");
  assert.notEqual(encryptedNote.toString("utf8").includes("Vegetarian"), true);
});

test("guest invitation history is returned through its capability-scoped database function", async (t) => {
  const mock = makeGuestApi();
  t.after(async () => mock.app.close());

  const response = await mock.app.inject({
    method: "GET",
    url: "/guest/invitation/me/rsvp-history",
    headers: { "x-guest-invitation-token": token },
  });
  assert.equal(response.statusCode, 200);
  assert.equal(response.json<{ data: Array<{ response: string }> }>().data[0]?.response, "accepted");
  assert.ok(mock.calls.some((call) => call.sql.includes("eogp.get_guest_invitation_rsvp_history(")));
});

test("guest invitation routes reject malformed bearer tokens before database access", async (t) => {
  const mock = makeGuestApi();
  t.after(async () => mock.app.close());

  const response = await mock.app.inject({
    method: "GET",
    url: "/guest/invitation/me",
    headers: { "x-guest-invitation-token": "not-a-token" },
  });
  assert.equal(response.statusCode, 401);
  assert.equal(mock.calls.length, 0);
});
