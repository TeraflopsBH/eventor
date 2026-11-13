import assert from "node:assert/strict";
import test from "node:test";
import type { Pool } from "pg";
import { runEventNotificationWorker } from "../src/notification-worker.js";

test("notification worker wakes from a long idle poll on SIGTERM and removes its listeners", async () => {
  const pool = {
    async query() {
      return { rows: [], rowCount: 0 };
    },
    async connect() {
      throw new Error("No tenant work should require a database connection.");
    },
  } as unknown as Pool;
  const sigintListenersBefore = process.listenerCount("SIGINT");
  const sigtermListenersBefore = process.listenerCount("SIGTERM");

  const worker = runEventNotificationWorker(pool, {
    contactEncryptionKey: Buffer.alloc(32, 1),
    deliveryCredentialsEncryptionKey: Buffer.alloc(32, 2),
    idlePollMs: 60_000,
    errorPollMs: 60_000,
  });

  await new Promise((resolve) => setTimeout(resolve, 10));
  process.emit("SIGTERM");
  await worker;

  assert.equal(process.listenerCount("SIGINT"), sigintListenersBefore);
  assert.equal(process.listenerCount("SIGTERM"), sigtermListenersBefore);
});
