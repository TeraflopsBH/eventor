import assert from "node:assert/strict";
import test from "node:test";
import { setImmediate } from "node:timers/promises";
import type { Pool } from "pg";
import { runEventNotificationWorker } from "../src/notification-worker.js";

test("notification worker wakes from a long idle poll on SIGTERM and removes its listeners", async () => {
  let queryCount = 0;
  let markPollCycleReady!: () => void;
  const pollCycleReady = new Promise<void>((resolve) => {
    markPollCycleReady = resolve;
  });
  const pool = {
    async query() {
      queryCount += 1;
      if (queryCount === 3) markPollCycleReady();
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

  await pollCycleReady;
  await setImmediate();
  process.emit("SIGTERM");

  let shutdownTimeout: ReturnType<typeof setTimeout> | undefined;
  try {
    await Promise.race([
      worker,
      new Promise<never>((_, reject) => {
        shutdownTimeout = setTimeout(
          () => reject(new Error("Worker did not wake promptly after SIGTERM.")),
          1_000,
        );
      }),
    ]);
  } finally {
    if (shutdownTimeout) clearTimeout(shutdownTimeout);
  }

  assert.equal(process.listenerCount("SIGINT"), sigintListenersBefore);
  assert.equal(process.listenerCount("SIGTERM"), sigtermListenersBefore);
});
