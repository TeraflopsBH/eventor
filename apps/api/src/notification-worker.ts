import type { Pool, PoolClient, QueryResultRow } from "pg";

interface PendingTenantRow extends QueryResultRow {
  organization_id: string;
}

interface WorkerResultRow extends QueryResultRow {
  result: {
    processed?: number;
    campaignPreviewsPrepared?: number;
    deferred?: number;
    deadLettered?: number;
  };
}

export interface NotificationWorkerTotals {
  readonly tenantsVisited: number;
  readonly processed: number;
  readonly campaignPreviewsPrepared: number;
  readonly deferred: number;
  readonly deadLettered: number;
}

export interface NotificationWorkerOptions {
  readonly batchSize?: number;
  readonly maxTenantsPerPoll?: number;
  readonly idlePollMs?: number;
  readonly errorPollMs?: number;
  readonly onBatch?: (totals: NotificationWorkerTotals) => void;
  readonly onError?: (error: unknown) => void;
}

const sleep = (milliseconds: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, milliseconds));

function emptyTotals(): NotificationWorkerTotals {
  return {
    tenantsVisited: 0,
    processed: 0,
    campaignPreviewsPrepared: 0,
    deferred: 0,
    deadLettered: 0,
  };
}

export async function processPendingEventChangeNotifications(
  pool: Pool,
  batchSize = 20,
  maxTenantsPerPoll = 100,
): Promise<NotificationWorkerTotals> {
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 100) {
    throw new RangeError("batchSize must be an integer between 1 and 100.");
  }
  if (!Number.isInteger(maxTenantsPerPoll) || maxTenantsPerPoll < 1 || maxTenantsPerPoll > 1000) {
    throw new RangeError("maxTenantsPerPoll must be an integer between 1 and 1000.");
  }

  // eventor_worker has a narrowly scoped RLS discovery policy for this topic.
  // It learns tenant IDs only; event payload and business data are read after
  // setting transaction-local tenant context for each tenant below.
  const tenants = await pool.query<PendingTenantRow>(
    \`SELECT DISTINCT organization_id
       FROM eogp.outbox_events
      WHERE topic = 'event.change.notification_requested'
        AND published_at IS NULL
        AND dead_lettered_at IS NULL
        AND available_at <= clock_timestamp()
      ORDER BY organization_id
      LIMIT $1\`,
    [maxTenantsPerPoll],
  );

  const totals = {
    tenantsVisited: 0,
    processed: 0,
    campaignPreviewsPrepared: 0,
    deferred: 0,
    deadLettered: 0,
  };

  for (const tenant of tenants.rows) {
    const client = await pool.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT set_config('app.organization_id',$1,true)", [
        tenant.organization_id,
      ]);
      const result = await client.query<WorkerResultRow>(
        "SELECT eogp.process_event_notification_outbox($1) AS result",
        [batchSize],
      );
      await client.query("COMMIT");
      const row = result.rows[0]?.result;
      totals.tenantsVisited += 1;
      totals.processed += Number(row?.processed ?? 0);
      totals.campaignPreviewsPrepared += Number(row?.campaignPreviewsPrepared ?? 0);
      totals.deferred += Number(row?.deferred ?? 0);
      totals.deadLettered += Number(row?.deadLettered ?? 0);
    } catch (error) {
      try {
        await client.query("ROLLBACK");
      } catch {
        // Preserve the original worker error.
      }
      throw error;
    } finally {
      client.release();
    }
  }

  return totals;
}

/**
 * Long-running tenant-aware outbox poller. This worker prepares draft/previewed
 * campaigns and immutable-per-campaign contact snapshots only. It intentionally
 * has no email/SMS provider adapter and never marks a recipient as sent.
 */
export async function runEventNotificationWorker(
  pool: Pool,
  options: NotificationWorkerOptions = {},
): Promise<void> {
  const batchSize = options.batchSize ?? 20;
  const maxTenantsPerPoll = options.maxTenantsPerPoll ?? 100;
  const idlePollMs = options.idlePollMs ?? 3000;
  const errorPollMs = options.errorPollMs ?? 5000;

  if (idlePollMs < 250 || errorPollMs < 250) {
    throw new RangeError("Worker poll intervals must be at least 250 milliseconds.");
  }

  let stopping = false;
  const stop = () => { stopping = true; };
  process.once("SIGINT", stop);
  process.once("SIGTERM", stop);

  try {
    while (!stopping) {
      try {
        const totals = await processPendingEventChangeNotifications(
          pool,
          batchSize,
          maxTenantsPerPoll,
        );
        if (totals.processed > 0) options.onBatch?.(totals);
        if (totals.processed === 0) await sleep(idlePollMs);
      } catch (error) {
        options.onError?.(error);
        await sleep(errorPollMs);
      }
    }
  } finally {
    process.removeListener("SIGINT", stop);
    process.removeListener("SIGTERM", stop);
  }
}
