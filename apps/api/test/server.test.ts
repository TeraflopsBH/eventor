import assert from "node:assert/strict";
import test from "node:test";
import type { Pool, PoolClient } from "pg";
import { buildApi, type StaffPrincipal } from "../src/server.js";

const principal: StaffPrincipal = {
  userId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
  organizationId: "22222222-2222-4222-8222-222222222222",
  membershipId: "bbbbbbbb-2222-4222-8222-bbbbbbbbbbbb",
};

interface StoredIdempotency {
  requestHash: string;
  responseStatus: number | null;
  responseBody: Record<string, unknown> | null;
}

function makePool() {
  const idempotency = new Map<string, StoredIdempotency>();
  const commandCalls: Array<{ sql: string; values: unknown[] }> = [];
  let reservationCalls = 0;
  let changeCalls = 0;

  const client = {
    async query(sql: string, values: unknown[] = []) {
      const normalized = sql.replace(/\s+/g, " ").trim();
      if (normalized === "BEGIN" || normalized === "COMMIT" || normalized === "ROLLBACK") {
        return { rows: [], rowCount: 0 };
      }
      if (normalized.startsWith("SELECT set_config(")) return { rows: [], rowCount: 1 };
      if (normalized.startsWith("DELETE FROM eogp.idempotency_records")) {
        return { rows: [], rowCount: 0 };
      }
      if (normalized.startsWith("SELECT request_sha256")) {
        const key = [values[0], values[1], values[2], values[3]].join("|");
        const found = idempotency.get(key);
        return {
          rows: found ? [{
            request_sha256: found.requestHash,
            response_status: found.responseStatus,
            response_body: found.responseBody,
          }] : [],
          rowCount: found ? 1 : 0,
        };
      }
      if (normalized.startsWith("INSERT INTO eogp.idempotency_records")) {
        const key = [values[0], values[1], values[2], values[3]].join("|");
        if (idempotency.has(key)) return { rows: [], rowCount: 0 };
        idempotency.set(key, {
          requestHash: String(values[4]),
          responseStatus: null,
          responseBody: null,
        });
        return { rows: [{ id: "idempotency-row" }], rowCount: 1 };
      }
      if (normalized.startsWith("UPDATE eogp.idempotency_records")) {
        const key = [values[0], values[1], values[2], values[3]].join("|");
        const found = idempotency.get(key);
        if (found) {
          found.responseStatus = 201;
          found.responseBody = JSON.parse(String(values[5])) as Record<string, unknown>;
        }
        return { rows: [], rowCount: found ? 1 : 0 };
      }
      if (normalized.includes("eogp.release_booking_reservations(")) {
        reservationCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ released_count: "2" }], rowCount: 1 };
      }
      if (normalized.includes("eogp.submit_event_change_request(")) {
        changeCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return {
          rows: [{
            result: {
              changeRequestId: "91500000-0000-4000-8000-000000000001",
              eventId: values[1],
              status: "submitted",
            },
          }],
          rowCount: 1,
        };
      }
      if (normalized.includes("eogp.decide_event_change_request(")) {
        changeCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { status: values[3] } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.execute_event_change_request(")) {
        changeCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { status: "cancelled", notificationState: "queued_for_dispatch" } }], rowCount: 1 };
      }
      throw new Error("Unexpected SQL in route test: " + normalized);
    },
    release() { /* no-op for the test pool */ },
  };

  const pool = {
    async connect() {
      return client as unknown as PoolClient;
    },
  } as unknown as Pool;

  return {
    pool,
    commandCalls,
    get reservationCalls() { return reservationCalls; },
    get changeCalls() { return changeCalls; },
  };
}

function makeApi(
  pool: Pool,
  options: {
    authenticated?: boolean;
    originValid?: boolean;
    encryptionKey?: Buffer;
  } = {},
) {
  return buildApi({
    pool,
    authenticateStaff: async () => options.authenticated === false ? null : principal,
    verifyMutationOrigin: async () => options.originValid !== false,
    privateFieldEncryptionKey: options.encryptionKey ?? Buffer.alloc(32, 7),
  });
}

test("reservation release delegates exact selected IDs to the permission-gated database command and replays idempotently", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const payload = {
    reservationIds: [
      "10000000-0000-4000-8000-000000000001",
      "10000000-0000-4000-8000-000000000002",
    ],
    reason: "booking_cancelled",
  };
  const headers = { "idempotency-key": "release-reservation-0001" };
  const first = await app.inject({
    method: "POST",
    url: "/bookings/73000000-0000-4000-8000-000000000001/reservations/release",
    headers,
    payload,
  });
  assert.equal(first.statusCode, 201);
  assert.equal(first.json<{ data: { releasedCount: number } }>().data.releasedCount, 2);
  assert.equal(mock.reservationCalls, 1);
  assert.equal(mock.commandCalls[0]?.values[0], principal.organizationId);
  assert.equal(mock.commandCalls[0]?.values[3], principal.membershipId);

  const replay = await app.inject({
    method: "POST",
    url: "/bookings/73000000-0000-4000-8000-000000000001/reservations/release",
    headers,
    payload,
  });
  assert.equal(replay.statusCode, 201);
  assert.deepEqual(replay.json<Record<string, unknown>>(), first.json<Record<string, unknown>>());
  assert.equal(mock.reservationCalls, 1);

  const conflictingReuse = await app.inject({
    method: "POST",
    url: "/bookings/73000000-0000-4000-8000-000000000001/reservations/release",
    headers,
    payload: { ...payload, reason: "different_reason" },
  });
  assert.equal(conflictingReuse.statusCode, 409);
  assert.equal(conflictingReuse.json().code, "IDEMPOTENCY_KEY_REUSED");
  assert.equal(mock.reservationCalls, 1);
});

test("event change submission encrypts private reason text before database persistence", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool, { encryptionKey: Buffer.alloc(32, 3) });
  t.after(async () => app.close());
  const response = await app.inject({
    method: "POST",
    url: "/events/90000000-0000-4000-8000-000000000001/change-requests",
    headers: { "idempotency-key": "event-cancel-request-01" },
    payload: {
      changeKind: "cancel",
      expectedEventRevision: 1,
      reasonCode: "venue_unavailable",
      reasonInternal: "Confidential internal note",
      publicMessage: "The event has been cancelled.",
    },
  });
  assert.equal(response.statusCode, 201);
  assert.equal(response.json<{ data: { status: string } }>().data.status, "submitted");
  const ciphertext = mock.commandCalls[0]?.values[6];
  assert.ok(Buffer.isBuffer(ciphertext));
  assert.equal((ciphertext as Buffer).subarray(0, 3).toString("ascii"), "EV1");
  assert.notEqual((ciphertext as Buffer).toString("utf8"), "Confidential internal note");
});

test("event reschedule without a replacement schedule is rejected before database access", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const response = await app.inject({
    method: "POST",
    url: "/events/90000000-0000-4000-8000-000000000001/change-requests",
    headers: { "idempotency-key": "event-reschedule-0001" },
    payload: {
      changeKind: "reschedule",
      expectedEventRevision: 1,
      reasonCode: "schedule_change",
    },
  });
  assert.equal(response.statusCode, 422);
  assert.equal(mock.changeCalls, 0);
});

test("postponement without a replacement schedule is rejected before database access", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const response = await app.inject({
    method: "POST",
    url: "/events/90000000-0000-4000-8000-000000000001/change-requests",
    headers: { "idempotency-key": "event-postpone-0001" },
    payload: {
      changeKind: "postpone",
      expectedEventRevision: 1,
      reasonCode: "venue_disruption",
    },
  });
  assert.equal(response.statusCode, 422);
  assert.equal(mock.changeCalls, 0);
});

test("custom notification audience requires explicit participation IDs", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const response = await app.inject({
    method: "POST",
    url: "/event-change-requests/91500000-0000-4000-8000-000000000001/execute",
    headers: { "idempotency-key": "event-execute-custom-01" },
    payload: { expectedEventRevision: 1, campaignAudience: "custom" },
  });
  assert.equal(response.statusCode, 422);
  assert.equal(response.json<{ code: string }>().code, "CUSTOM_AUDIENCE_REQUIRED");
  assert.equal(mock.changeCalls, 0);
});

test("staff mutations fail closed without a verified session or accepted origin", async (t) => {
  const unauthenticated = makePool();
  const noSessionApi = makeApi(unauthenticated.pool, { authenticated: false });
  t.after(async () => noSessionApi.close());
  const unauthenticatedResponse = await noSessionApi.inject({
    method: "POST",
    url: "/events/90000000-0000-4000-8000-000000000001/change-requests",
    headers: { "idempotency-key": "event-auth-check-01" },
    payload: { changeKind: "cancel", expectedEventRevision: 1, reasonCode: "test" },
  });
  assert.equal(unauthenticatedResponse.statusCode, 401);
  assert.equal(unauthenticated.commandCalls.length, 0);

  const originPool = makePool();
  const noOriginApi = makeApi(originPool.pool, { originValid: false });
  t.after(async () => noOriginApi.close());
  const originResponse = await noOriginApi.inject({
    method: "POST",
    url: "/events/90000000-0000-4000-8000-000000000001/change-requests",
    headers: { "idempotency-key": "event-origin-check-01" },
    payload: { changeKind: "cancel", expectedEventRevision: 1, reasonCode: "test" },
  });
  assert.equal(originResponse.statusCode, 403);
  assert.equal(originPool.commandCalls.length, 0);
});
