import type { Pool, PoolClient, QueryResultRow } from "pg";
import { decryptContactValue } from "./contact-crypto.js";
import { decryptDeliveryCredentials } from "./delivery-credentials-crypto.js";
import {
  classifySmtpFailure,
  createSmtpTransport,
  renderNotificationTemplate,
  type SmtpSettings,
  type SmtpTransportFactory,
} from "./smtp-transport.js";

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
interface DeliveryJobRow extends QueryResultRow {
  attempt_id: string;
  campaign_id: string;
  recipient_id: string;
  destination_ciphertext: Buffer;
  credentials_ciphertext: Buffer | null;
  smtp_settings: SmtpSettings;
  sender_email: string;
  sender_name: string;
  reply_to: string | null;
  subject_template: string;
  body_template: string;
  event_title: string;
  event_code: string;
  event_status: string;
  decision_kind: string;
  campaign_purpose: string;
  starts_at: Date | string | null;
  ends_at: Date | string | null;
  timezone_name: string | null;
}
interface DeliveryClaimRow extends QueryResultRow {
  job: DeliveryJobRow | null;
}
interface DeliveryCompletionRow extends QueryResultRow {
  result: {
    outcome: string;
    retryScheduled: boolean;
    campaignStatus: string;
  };
}
interface ResendMessageReferenceRow extends QueryResultRow {
  reference: string;
}
interface BookingOfferEmailJobRow extends QueryResultRow {
  delivery_id: string;
  offer_id: string;
  offer_revision_id: string;
  capability_ciphertext: Buffer;
  recipient_ciphertext: Buffer;
  credentials_ciphertext: Buffer | null;
  smtp_settings: SmtpSettings;
  sender_email: string;
  sender_name: string;
  reply_to: string | null;
  valid_until: Date | string;
  currency: string;
  total_amount: string | number;
}

export interface NotificationWorkerTotals {
  readonly tenantsVisited: number;
  readonly processed: number;
  readonly campaignPreviewsPrepared: number;
  readonly deferred: number;
  readonly deadLettered: number;
  readonly emailAttempts: number;
  readonly emailSent: number;
  readonly emailFailed: number;
  readonly emailUncertain: number;
  readonly emailRetriesScheduled: number;
  readonly bookingOffersExpired: number;
  readonly bookingOfferEmailAttempts: number;
  readonly bookingOfferEmailSent: number;
  readonly bookingOfferEmailFailed: number;
  readonly bookingOfferEmailUncertain: number;
  readonly bookingOfferEmailRetriesScheduled: number;
}
export interface NotificationWorkerOptions {
  readonly batchSize?: number;
  readonly maxTenantsPerPoll?: number;
  readonly idlePollMs?: number;
  readonly errorPollMs?: number;
  readonly contactEncryptionKey?: Buffer;
  readonly deliveryCredentialsEncryptionKey?: Buffer;
  readonly publicAppBaseUrl?: string;
  readonly smtpTransportFactory?: SmtpTransportFactory;
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
    emailAttempts: 0,
    emailSent: 0,
    emailFailed: 0,
    emailUncertain: 0,
    emailRetriesScheduled: 0,
    bookingOffersExpired: 0,
    bookingOfferEmailAttempts: 0,
    bookingOfferEmailSent: 0,
    bookingOfferEmailFailed: 0,
    bookingOfferEmailUncertain: 0,
    bookingOfferEmailRetriesScheduled: 0,
  };
}

async function inTenantTransaction<T>(
  pool: Pool,
  organizationId: string,
  operation: (client: PoolClient) => Promise<T>,
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.organization_id',$1,true)", [organizationId]);
    const result = await operation(client);
    await client.query("COMMIT");
    return result;
  } catch (error) {
    try { await client.query("ROLLBACK"); } catch { /* preserve original worker error */ }
    throw error;
  } finally {
    client.release();
  }
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

  const tenants = await pool.query<PendingTenantRow>(
    `SELECT DISTINCT organization_id
       FROM eogp.outbox_events
      WHERE topic = 'event.change.notification_requested'
        AND published_at IS NULL
        AND dead_lettered_at IS NULL
        AND available_at <= clock_timestamp()
      ORDER BY organization_id
      LIMIT $1`,
    [maxTenantsPerPoll],
  );

  const totals = { ...emptyTotals() };
  for (const tenant of tenants.rows) {
    const result = await inTenantTransaction(pool, tenant.organization_id, async (client) => {
      const processed = await client.query<WorkerResultRow>(
        "SELECT eogp.process_event_notification_outbox($1) AS result",
        [batchSize],
      );
      return processed.rows[0]?.result;
    });
    totals.tenantsVisited += 1;
    totals.processed += Number(result?.processed ?? 0);
    totals.campaignPreviewsPrepared += Number(result?.campaignPreviewsPrepared ?? 0);
    totals.deferred += Number(result?.deferred ?? 0);
    totals.deadLettered += Number(result?.deadLettered ?? 0);
  }
  return totals;
}

function formatDate(value: Date | string | null): string {
  if (value === null) return "Not specified";
  const date = value instanceof Date ? value : new Date(value);
  return Number.isNaN(date.getTime()) ? "Not specified" : date.toISOString();
}

async function sendClaimedEmail(
  job: DeliveryJobRow,
  organizationId: string,
  contactKey: Buffer,
  deliveryKey: Buffer,
  factory: SmtpTransportFactory,
  providerMessageReference: string | null,
): Promise<{ outcome: "sent" | "failed" | "uncertain"; failureCode: string | null; messageReference: string | null }> {
  try {
    const credentials = job.credentials_ciphertext
      ? decryptDeliveryCredentials(job.credentials_ciphertext, deliveryKey, {
          organizationId,
          channel: "email",
        })
      : null;
    const destination = decryptContactValue(job.destination_ciphertext, contactKey, {
      organizationId,
      contactKind: "email",
    });
    const values: Record<string, string> = {
      "event.title": job.event_title,
      "event.code": job.event_code,
      "event.status": job.event_status,
      "event.startsAt": formatDate(job.starts_at),
      "event.endsAt": formatDate(job.ends_at),
      "event.timezone": job.timezone_name ?? "Not specified",
      "decision.kind": job.decision_kind,
      "campaign.purpose": job.campaign_purpose,
    };
    const subject = renderNotificationTemplate(job.subject_template, values);
    const text = renderNotificationTemplate(job.body_template, values);
    const transport = factory(job.smtp_settings, credentials);
    try {
      const result = await transport.sendMail({
        to: destination,
        subject,
        text,
        ...(providerMessageReference ? { messageId: providerMessageReference } : {}),
      });
      if (!result.accepted.some((address) => address.toLowerCase() === destination.toLowerCase())) {
        const error = new Error("SMTP server did not accept the recipient.") as Error & { responseCode: number };
        error.responseCode = 550;
        throw error;
      }
      return {
        outcome: "sent",
        failureCode: null,
        messageReference: providerMessageReference ?? result.messageId,
      };
    } finally {
      transport.close();
    }
  } catch (error) {
    const classification = classifySmtpFailure(error);
    return {
      outcome: classification.outcome,
      failureCode: classification.code,
      // Keep the prepared provider reference on failures too. In particular,
      // a DATA-stage timeout can be uncertain even though Resend accepted it.
      messageReference: providerMessageReference,
    };
  }
}

export async function processPendingEmailDeliveries(
  pool: Pool,
  contactEncryptionKey: Buffer,
  deliveryCredentialsEncryptionKey: Buffer,
  batchSize = 20,
  maxTenantsPerPoll = 100,
  factory: SmtpTransportFactory = createSmtpTransport,
): Promise<NotificationWorkerTotals> {
  if (!Buffer.isBuffer(contactEncryptionKey) || contactEncryptionKey.length !== 32) {
    throw new TypeError("Contact encryption key must be exactly 32 bytes.");
  }
  if (!Buffer.isBuffer(deliveryCredentialsEncryptionKey) || deliveryCredentialsEncryptionKey.length !== 32) {
    throw new TypeError("Delivery credential encryption key must be exactly 32 bytes.");
  }
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 100) {
    throw new RangeError("batchSize must be an integer between 1 and 100.");
  }
  if (!Number.isInteger(maxTenantsPerPoll) || maxTenantsPerPoll < 1 || maxTenantsPerPoll > 1000) {
    throw new RangeError("maxTenantsPerPoll must be an integer between 1 and 1000.");
  }

  const tenants = await pool.query<PendingTenantRow>(
    "SELECT organization_id FROM eogp.discover_pending_email_delivery_tenants()",
  );
  const totals = { ...emptyTotals() };
  for (const tenant of tenants.rows.slice(0, maxTenantsPerPoll)) {
    let tenantAttempts = 0;
    while (tenantAttempts < batchSize) {
      const job = await inTenantTransaction(pool, tenant.organization_id, async (client) => {
        const claimed = await client.query<DeliveryJobRow>(
          "SELECT * FROM eogp.claim_next_email_delivery($1::uuid)",
          [tenant.organization_id],
        );
        return claimed.rows[0] ?? null;
      });
      if (!job) break;

      let result: {
        outcome: "sent" | "failed" | "uncertain";
        failureCode: string | null;
        messageReference: string | null;
      };

      if (job.smtp_settings.host.trim().toLowerCase() === "smtp.resend.com") {
        // Prepare and commit the stable Message-ID before any SMTP bytes are
        // submitted. If Resend accepts the mail but the DATA response is lost,
        // its signed callback can still resolve the resulting uncertain attempt.
        try {
          const prepared = await inTenantTransaction(
            pool,
            tenant.organization_id,
            async (client) => client.query<ResendMessageReferenceRow>(
              "SELECT eogp.prepare_resend_delivery_submission($1::uuid,$2::uuid) AS reference",
              [tenant.organization_id, job.attempt_id],
            ),
          );
          const providerReference = prepared.rows[0]?.reference;
          if (typeof providerReference !== "string" || providerReference.length < 3) {
            throw new Error("Resend Message-ID preparation returned no reference.");
          }
          result = await sendClaimedEmail(
            job,
            tenant.organization_id,
            contactEncryptionKey,
            deliveryCredentialsEncryptionKey,
            factory,
            providerReference,
          );
        } catch {
          // The message has not been submitted yet. Record a safe, permanent
          // preparation failure instead of creating a false uncertain send.
          result = { outcome: "failed", failureCode: "SMTP_UNKNOWN", messageReference: null };
        }
      } else {
        result = await sendClaimedEmail(
          job,
          tenant.organization_id,
          contactEncryptionKey,
          deliveryCredentialsEncryptionKey,
          factory,
          null,
        );
      }
      await inTenantTransaction(pool, tenant.organization_id, async (client) => {
        const completed = await client.query<DeliveryCompletionRow>(
          "SELECT eogp.complete_email_delivery_attempt($1::uuid,$2::uuid,$3::text,$4::text,$5::text) AS result",
          [
            tenant.organization_id,
            job.attempt_id,
            result.outcome,
            result.failureCode,
            result.messageReference,
          ],
        );
        const completion = completed.rows[0]?.result;
        if (completion?.retryScheduled) totals.emailRetriesScheduled += 1;
      });
      totals.emailAttempts += 1;
      if (result.outcome === "sent") totals.emailSent += 1;
      else if (result.outcome === "uncertain") totals.emailUncertain += 1;
      else totals.emailFailed += 1;
      tenantAttempts += 1;
    }
    if (tenantAttempts > 0) totals.tenantsVisited += 1;
  }
  return totals;
}

export async function processPendingBookingOfferEmailDeliveries(
  pool: Pool,
  contactEncryptionKey: Buffer,
  deliveryCredentialsEncryptionKey: Buffer,
  publicAppBaseUrl: string,
  batchSize = 20,
  maxTenantsPerPoll = 100,
  factory: SmtpTransportFactory = createSmtpTransport,
): Promise<NotificationWorkerTotals> {
  if (!Buffer.isBuffer(contactEncryptionKey) || contactEncryptionKey.length !== 32
      || !Buffer.isBuffer(deliveryCredentialsEncryptionKey) || deliveryCredentialsEncryptionKey.length !== 32) {
    throw new TypeError("Offer email delivery requires separate 32-byte contact and delivery-credential keys.");
  }
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 100) {
    throw new RangeError("batchSize must be an integer between 1 and 100.");
  }
  if (!Number.isInteger(maxTenantsPerPoll) || maxTenantsPerPoll < 1 || maxTenantsPerPoll > 1000) {
    throw new RangeError("maxTenantsPerPoll must be an integer between 1 and 1000.");
  }
  const appUrl = new URL(publicAppBaseUrl);
  if (appUrl.protocol !== "https:" || appUrl.username || appUrl.password || appUrl.search || appUrl.hash) {
    throw new TypeError("The public application base URL must be HTTPS and contain no credentials, query or fragment.");
  }
  const baseUrl = appUrl.toString().replace(/\/+$/, "");
  const tenants = await pool.query<PendingTenantRow>(
    "SELECT organization_id FROM eogp.discover_pending_booking_offer_email_tenants()",
  );
  const totals = { ...emptyTotals() };
  for (const tenant of tenants.rows.slice(0, maxTenantsPerPoll)) {
    let tenantAttempts = 0;
    while (tenantAttempts < batchSize) {
      const job = await inTenantTransaction(pool, tenant.organization_id, async (client) => {
        const claimed = await client.query<BookingOfferEmailJobRow>(
          "SELECT * FROM eogp.claim_booking_offer_email_delivery($1::uuid)",
          [tenant.organization_id],
        );
        return claimed.rows[0] ?? null;
      });
      if (!job) break;

      let outcome: "sent" | "failed" | "uncertain" = "failed";
      let failureCode: string | null = null;
      let messageReference: string | null = null;
      let transport: ReturnType<SmtpTransportFactory> | null = null;
      try {
        const credentials = job.credentials_ciphertext
          ? decryptDeliveryCredentials(job.credentials_ciphertext, deliveryCredentialsEncryptionKey, {
              organizationId: tenant.organization_id,
              channel: "email",
            })
          : null;
        const destination = decryptContactValue(job.recipient_ciphertext, contactEncryptionKey, {
          organizationId: tenant.organization_id,
          contactKind: "email",
        });
        const capability = decryptContactValue(job.capability_ciphertext, contactEncryptionKey, {
          organizationId: tenant.organization_id,
          contactKind: "other",
        });
        if (!/^[A-Za-z0-9_-]{43}$/.test(capability)) {
          throw new TypeError("Contact ciphertext contains an invalid booking offer capability.");
        }
        const reviewUrl = `${baseUrl}/offers/${job.offer_id}#token=${encodeURIComponent(capability)}`;
        const validUntil = job.valid_until instanceof Date ? job.valid_until : new Date(job.valid_until);
        const validity = Number.isNaN(validUntil.getTime()) ? "the stated validity deadline" : validUntil.toISOString();
        const sender = job.sender_name.trim() || job.sender_email;
        const total = new Intl.NumberFormat("en", {
          style: "currency", currency: job.currency, maximumFractionDigits: 4,
        }).format(Number(job.total_amount));
        const subject = "Booking offer";
        const text = [
          "You have received a booking offer.",
          `Offer from: ${sender}`,
          "",
          `Offer total: ${total}`,
          `Valid until: ${validity}`,
          "",
          "Review the offer and accept or reject it using this secure link:",
          reviewUrl,
          "",
          "This link is personal. Do not forward it to anyone else.",
        ].join("\n");
        transport = factory(job.smtp_settings, credentials);
        const sent = await transport.sendMail({ to: destination, subject, text });
        if (!sent.accepted.some((address) => address.toLowerCase() === destination.toLowerCase())) {
          const error = new Error("SMTP server did not accept the offer recipient.") as Error & { responseCode: number };
          error.responseCode = 550;
          throw error;
        }
        outcome = "sent";
        messageReference = sent.messageId || null;
      } catch (error) {
        const classification = classifySmtpFailure(error);
        outcome = classification.outcome;
        failureCode = classification.code;
      } finally {
        try { transport?.close(); } catch { /* preserve the SMTP submission outcome */ }
      }

      const completed = await inTenantTransaction(pool, tenant.organization_id, async (client) => {
        const result = await client.query<DeliveryCompletionRow>(
          "SELECT eogp.complete_booking_offer_email_delivery($1::uuid,$2::uuid,$3::text,$4::text,$5::text) AS result",
          [tenant.organization_id, job.delivery_id, outcome, failureCode, messageReference],
        );
        return result.rows[0]?.result;
      });
      totals.bookingOfferEmailAttempts += 1;
      if (outcome === "sent") totals.bookingOfferEmailSent += 1;
      else if (outcome === "uncertain") totals.bookingOfferEmailUncertain += 1;
      else totals.bookingOfferEmailFailed += 1;
      if (completed?.retryScheduled) totals.bookingOfferEmailRetriesScheduled += 1;
      tenantAttempts += 1;
    }
    if (tenantAttempts > 0) totals.tenantsVisited += 1;
  }
  return totals;
}

export async function processExpiredBookingOffers(
  pool: Pool,
  batchSize = 100,
  maxTenantsPerPoll = 100,
): Promise<{ tenantsVisited: number; expired: number }> {
  if (!Number.isInteger(batchSize) || batchSize < 1 || batchSize > 500) {
    throw new RangeError("batchSize must be an integer between 1 and 500.");
  }
  if (!Number.isInteger(maxTenantsPerPoll) || maxTenantsPerPoll < 1 || maxTenantsPerPoll > 1000) {
    throw new RangeError("maxTenantsPerPoll must be an integer between 1 and 1000.");
  }

  const tenants = await pool.query<PendingTenantRow>(
    "SELECT organization_id FROM eogp.discover_due_booking_offer_expiry_tenants()",
  );
  let tenantsVisited = 0;
  let expired = 0;
  for (const tenant of tenants.rows.slice(0, maxTenantsPerPoll)) {
    const count = await inTenantTransaction(pool, tenant.organization_id, async (client) => {
      const result = await client.query<{ expired_count: number } & QueryResultRow>(
        "SELECT eogp.expire_due_booking_offers($1::uuid,$2::integer) AS expired_count",
        [tenant.organization_id, batchSize],
      );
      return Number(result.rows[0]?.expired_count ?? 0);
    });
    tenantsVisited += 1;
    expired += count;
  }
  return { tenantsVisited, expired };
}

/**
 * The worker prepares previews, then sends only explicitly queued email
 * campaigns. SMS recipients remain suppressed until an SMS adapter is enabled.
 * SMTP acceptance is recorded as "sent", never as proof of final delivery.
 */
export async function runEventNotificationWorker(
  pool: Pool,
  options: NotificationWorkerOptions = {},
): Promise<void> {
  const batchSize = options.batchSize ?? 20;
  const maxTenantsPerPoll = options.maxTenantsPerPoll ?? 100;
  const idlePollMs = options.idlePollMs ?? 3000;
  const errorPollMs = options.errorPollMs ?? 5000;
  const contactKey = options.contactEncryptionKey;
  const deliveryKey = options.deliveryCredentialsEncryptionKey;

  if (!contactKey || contactKey.length !== 32 || !deliveryKey || deliveryKey.length !== 32) {
    throw new TypeError("The worker requires separate 32-byte contact and delivery-credential encryption keys.");
  }
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
        const previews = await processPendingEventChangeNotifications(
          pool, batchSize, maxTenantsPerPoll,
        );
        const deliveries = await processPendingEmailDeliveries(
          pool, contactKey, deliveryKey, batchSize, maxTenantsPerPoll,
          options.smtpTransportFactory,
        );
        const offerEmails = options.publicAppBaseUrl
          ? await processPendingBookingOfferEmailDeliveries(
              pool, contactKey, deliveryKey, options.publicAppBaseUrl,
              batchSize, maxTenantsPerPoll, options.smtpTransportFactory,
            )
          : { ...emptyTotals() };
        const expiries = await processExpiredBookingOffers(pool, 100, maxTenantsPerPoll);
        const totals: NotificationWorkerTotals = {
          tenantsVisited: previews.tenantsVisited + deliveries.tenantsVisited + expiries.tenantsVisited,
          processed: previews.processed,
          campaignPreviewsPrepared: previews.campaignPreviewsPrepared,
          deferred: previews.deferred,
          deadLettered: previews.deadLettered,
          emailAttempts: deliveries.emailAttempts,
          emailSent: deliveries.emailSent,
          emailFailed: deliveries.emailFailed,
          emailUncertain: deliveries.emailUncertain,
          emailRetriesScheduled: deliveries.emailRetriesScheduled,
          bookingOffersExpired: expiries.expired,
          bookingOfferEmailAttempts: offerEmails.bookingOfferEmailAttempts,
          bookingOfferEmailSent: offerEmails.bookingOfferEmailSent,
          bookingOfferEmailFailed: offerEmails.bookingOfferEmailFailed,
          bookingOfferEmailUncertain: offerEmails.bookingOfferEmailUncertain,
          bookingOfferEmailRetriesScheduled: offerEmails.bookingOfferEmailRetriesScheduled,
        };
        if (totals.processed > 0 || totals.emailAttempts > 0 || totals.bookingOffersExpired > 0 || totals.bookingOfferEmailAttempts > 0) options.onBatch?.(totals);
        if (totals.processed === 0 && totals.emailAttempts === 0 && totals.bookingOffersExpired === 0 && totals.bookingOfferEmailAttempts === 0) await sleep(idlePollMs);
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
