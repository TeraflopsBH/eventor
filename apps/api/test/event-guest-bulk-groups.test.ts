import assert from "node:assert/strict";
import test from "node:test";
import type { Pool } from "pg";
import { buildApi } from "../src/server.js";

const organizationId = "10000000-0000-0000-0000-00000000000a";
const membershipId = "30000000-0000-0000-0000-00000000000a";
const eventId = "79000000-0000-4000-8000-000000000001";
const groupId = "79000000-0000-4000-8000-00000000000a";
const guests = [
  { participationId: "79000000-0000-4000-8000-00000000000b", expectedRevision: 3 },
  { participationId: "79000000-0000-4000-8000-00000000000c", expectedRevision: 4 },
];

for (const action of ["add", "remove"] as const) {
  test(`bulk group ${action} canonicalizes retries and rechecks current event authority`, async () => {
    let revoked = false;
    let commandCalls = 0;
    let stored: Record<string, unknown> | null = null;
    const client = {
      async query(sql: string, values: readonly unknown[] = []) {
        if (sql.startsWith("SELECT request_sha256")) return { rows: stored ? [stored] : [] };
        if (sql.startsWith("INSERT INTO eogp.idempotency_records")) {
          stored = { request_sha256: values[4], response_status: null, response_body: null };
          return { rows: [{ id: groupId }] };
        }
        if (sql.startsWith("UPDATE eogp.idempotency_records")) {
          stored = { request_sha256: values[4], response_status: values[5], response_body: values[6] };
        }
        if (sql.includes("assert_staff_event_replay_permission")) {
          assert.deepEqual(values, [organizationId, eventId, membershipId]);
          if (revoked) throw Object.assign(new Error("permission revoked"), { code: "42501" });
        }
        if (sql.includes("SELECT eogp.set_event_guest_bulk_group(")) {
          commandCalls++;
          assert.deepEqual(values, [organizationId, eventId, membershipId, groupId, action, JSON.stringify(guests)]);
          return { rows: [{ result: { processedCount: 2, updatedCount: 1 } }] };
        }
        return { rows: [] };
      },
      release() {},
    };
    const app = buildApi({
      pool: { connect: async () => client } as unknown as Pool,
      authenticateStaff: async () => ({ organizationId, membershipId, userId: "20000000-0000-0000-0000-00000000000a" }),
      verifyMutationOrigin: async () => true,
    });
    const request = {
      method: "PATCH" as const, url: `/events/${eventId}/participations/bulk/groups`,
      headers: { "idempotency-key": `bulk-group-${action}-fixture` }, payload: { groupId, action, guests },
    };
    try {
      const first = await app.inject(request);
      assert.equal(first.statusCode, 200, first.body);
      assert.equal(first.headers["cache-control"], "no-store, private");
      const replay = await app.inject({ ...request, payload: { groupId: groupId.toUpperCase(), action,
        guests: [...guests].reverse().map(row => ({ ...row, participationId: row.participationId.toUpperCase() })) } });
      assert.equal(replay.statusCode, 200, replay.body);
      assert.equal(commandCalls, 1);
      const conflict = await app.inject({ ...request, payload: { ...request.payload, action: action === "add" ? "remove" : "add" } });
      assert.equal(conflict.statusCode, 409, conflict.body);
      revoked = true;
      const denied = await app.inject(request);
      assert.equal(denied.statusCode, 403, denied.body);
      assert.equal(commandCalls, 1);
      for (const payload of [
        { groupId, action, guests: [] },
        { groupId: "invalid", action, guests },
        { groupId, action: "replace", guests },
        { groupId, action, guests: [{ ...guests[0], expectedRevision: 0 }] },
        { groupId, action, guests: Array.from({ length: 51 }, () => guests[0]) },
      ]) {
        const invalid = await app.inject({ ...request, payload });
        assert.equal(invalid.statusCode, 400, invalid.body);
      }
    } finally { await app.close(); }
  });
}
