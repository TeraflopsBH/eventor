import assert from "node:assert/strict";
import { createCipheriv, createHash, createHmac, randomBytes } from "node:crypto";
import test from "node:test";
import type { Pool } from "pg";
import { buildApi } from "../src/server.js";

const organizationId = "22222222-2222-4222-8222-222222222222";
const invitationId = "33333333-3333-4333-8333-333333333333";
const token = Buffer.alloc(32, 21).toString("base64url");

const privateFieldEncryptionKey = Buffer.alloc(32, 7);
function encryptPresentation(value: unknown): Buffer {
  const iv = randomBytes(12);
  const key = createHmac("sha256", privateFieldEncryptionKey)
    .update("eventor:private-reason-encryption:v1")
    .digest();
  const cipher = createCipheriv("aes-256-gcm", key, iv);
  const encrypted = Buffer.concat([cipher.update(JSON.stringify(value), "utf8"), cipher.final()]);
  return Buffer.concat([Buffer.from("EV1", "ascii"), iv, cipher.getAuthTag(), encrypted]);
}


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
    presentationSnapshotCiphertext: encryptPresentation({ greeting: "Welcome to the gathering" }).toString("base64"),
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
    privateFieldEncryptionKey,
  });
  return { app, calls, invitation };
}

const staffPrincipal = {
  userId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
  organizationId,
  membershipId: "bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb",
};

function makeStaffInvitationApi() {
  const calls: Array<{ sql: string; values: unknown[] }> = [];
  const client = {
    async query(sql: string, values: unknown[] = []) {
      const normalized = sql.replace(/\\s+/g, " ").trim();
      calls.push({ sql: normalized, values });
      if (["BEGIN", "COMMIT", "ROLLBACK"].includes(normalized)
          || normalized.startsWith("SELECT set_config")
          || normalized.startsWith("DELETE FROM eogp.idempotency_records")
          || normalized.startsWith("UPDATE eogp.idempotency_records")) {
        return { rows: [], rowCount: 1 };
      }
      if (normalized.startsWith("SELECT request_sha256,response_status,response_body FROM eogp.idempotency_records")) {
        return { rows: [], rowCount: 0 };
      }
      if (normalized.startsWith("INSERT INTO eogp.idempotency_records")) {
        return { rows: [{ id: "77777777-7777-4777-8777-777777777777" }], rowCount: 1 };
      }
      if (normalized.includes("eogp.issue_guest_invitation(")) {
        return {
          rows: [{
            result: {
              invitationId,
              invitationRevisionId: "44444444-4444-4444-8444-444444444444",
              linkId: "88888888-8888-4888-8888-888888888888",
              deliveryId: "99999999-9999-4999-8999-999999999999",
              status: "queued",
              created: true,
            },
          }],
          rowCount: 1,
        };
      }
      if (normalized.includes("eogp.revoke_guest_invitation(")) {
        return {
          rows: [{ result: { invitationId, status: "revoked", revokedLinks: 1 } }],
          rowCount: 1,
        };
      }
      throw new Error("Unexpected staff invitation SQL: " + normalized);
    },
    release() {},
  };
  const pool = { async connect() { return client; } } as unknown as Pool;
  const app = buildApi({
    pool,
    authenticateStaff: async () => staffPrincipal,
    verifyMutationOrigin: async () => true,
    privateFieldEncryptionKey: Buffer.alloc(32, 7),
    contactEncryptionKey: Buffer.alloc(32, 10),
  });
  return { app, calls };
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
  assert.deepEqual(data.presentationSnapshot, { greeting: "Welcome to the gathering" });
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
    headers: { "x-guest-invitation-token": "A".repeat(42) + "B" },
  });
  assert.equal(response.statusCode, 401);
  assert.equal(mock.calls.length, 0);
});


test("staff invitation issuance encrypts the bearer capability and queues delivery without returning it", async (t) => {
  const mock = makeStaffInvitationApi();
  t.after(async () => mock.app.close());

  const response = await mock.app.inject({
    method: "POST",
    url: "/events/55555555-5555-4555-8555-555555555555/participations/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa/invitation",
    headers: { "idempotency-key": "guest-issue-0001" },
    payload: {
      scheduleRevisionId: "11111111-1111-4111-8111-111111111112",
      rsvpPolicyRevisionId: "11111111-1111-4111-8111-111111111113",
      locale: "bs-BA",
      expiresAt: new Date(Date.now() + 7 * 86400000).toISOString(),
      presentationSnapshot: { greeting: "Dobro došli", venueName: "Main hall" },
    },
  });
  assert.equal(response.statusCode, 201);
  const data = response.json<{ data: Record<string, unknown> }>().data;
  assert.equal(data.status, "queued");
  assert.equal(data.deliveryId, "99999999-9999-4999-8999-999999999999");
  assert.equal("token" in data, false);
  const issue = mock.calls.find((call) => call.sql.includes("eogp.issue_guest_invitation("));
  assert.ok(issue);
  assert.match(String(issue.values[9]), /^[0-9a-f]{64}$/);
  assert.equal((issue.values[10] as Buffer).subarray(0, 4).toString("ascii"), "ECP1");
  assert.equal((issue.values[8] as Buffer).subarray(0, 3).toString("ascii"), "EV1");
  assert.equal(JSON.stringify(data).includes(token), false);
});

test("staff invitation revocation calls the audited tenant-scoped database command", async (t) => {
  const mock = makeStaffInvitationApi();
  t.after(async () => mock.app.close());

  const response = await mock.app.inject({
    method: "POST",
    url: "/invitations/33333333-3333-4333-8333-333333333333/revoke",
    headers: { "idempotency-key": "guest-revoke-0001" },
    payload: { reasonCode: "guest_request" },
  });
  assert.equal(response.statusCode, 201);
  assert.equal(response.json<{ data: { status: string; revokedLinks: number } }>().data.status, "revoked");
  const call = mock.calls.find((item) => item.sql.includes("eogp.revoke_guest_invitation("));
  assert.ok(call);
  assert.deepEqual(call.values, [organizationId, invitationId, staffPrincipal.membershipId, "guest_request"]);
});
