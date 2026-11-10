import assert from "node:assert/strict";
import test from "node:test";
import type { Pool, PoolClient, QueryResultRow } from "pg";
import { processPendingEventChangeNotifications } from "../src/notification-worker.js";

function fakePool(tenants: string[]) {
  const transactions: string[] = [];
  const released: string[] = [];
  const calls: Array<{ sql: string; values: unknown[] }> = [];

  const pool = {
    async query(sql: string, values: unknown[] = []) {
      calls.push({ sql: sql.replace(/\s+/g, " ").trim(), values });
      return {
        rows: tenants.map((organization_id) => ({ organization_id })) as QueryResultRow[],
        rowCount: tenants.length,
      };
    },
    async connect() {
      const client = {
        async query(sql: string, values: unknown[] = []) {
          const normalized = sql.replace(/\s+/g, " ").trim();
          calls.push({ sql: normalized, values });
          transactions.push(normalized);
          if (normalized.startsWith("SELECT eogp.process_event_notification_outbox")) {
            return {
              rows: [{
                result: {
                  processed: 2,
                  campaignPreviewsPrepared: 1,
                  deferred: 1,
                  deadLettered: 0,
                },
              }],
              rowCount: 1,
            };
          }
          return { rows: [], rowCount: 1 };
        },
        release() { released.push("released"); },
      };
      return client as unknown as PoolClient;
    },
  };
  return {
    pool: pool as unknown as Pool,
    calls,
    transactions,
    released,
  };
}

test("notification worker sets tenant context and commits one batch per tenant", async () => {
  const tenantA = "11111111-1111-4111-8111-111111111111";
  const tenantB = "22222222-2222-4222-8222-222222222222";
  const mock = fakePool([tenantA, tenantB]);

  const result = await processPendingEventChangeNotifications(mock.pool, 10, 50);

  assert.deepEqual(result, {
    tenantsVisited: 2,
    processed: 4,
    campaignPreviewsPrepared: 2,
    deferred: 2,
    deadLettered: 0,
  });
  assert.equal(mock.released.length, 2);
  assert.equal(
    mock.calls.filter((call) => call.sql.includes("set_config('app.organization_id'")).length,
    2,
  );
  assert.equal(
    mock.calls.filter((call) => call.sql.startsWith("SELECT eogp.process_event_notification_outbox")).length,
    2,
  );
  assert.equal(mock.transactions.filter((sql) => sql === "BEGIN").length, 2);
  assert.equal(mock.transactions.filter((sql) => sql === "COMMIT").length, 2);
});

test("notification worker rejects unsafe batch sizes before querying", async () => {
  const mock = fakePool([]);
  await assert.rejects(
    processPendingEventChangeNotifications(mock.pool, 101, 10),
    RangeError,
  );
  assert.equal(mock.calls.length, 0);
});
