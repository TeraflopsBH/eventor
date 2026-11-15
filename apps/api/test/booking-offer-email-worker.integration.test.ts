import { randomBytes, randomUUID, createHash } from "node:crypto";
import { test } from "node:test";
import assert from "node:assert/strict";
import { Pool } from "pg";
import { encryptContactValue } from "../src/contact-crypto.js";
import { processPendingBookingOfferEmailDeliveries } from "../src/notification-worker.js";
import type { SmtpTransportFactory } from "../src/smtp-transport.js";

const migratorUrl = process.env.MIGRATOR_URL;
const workerUrl = process.env.WORKER_URL;
const enabled = Boolean(migratorUrl && workerUrl);
const organizationId = "11111111-1111-4111-8111-111111111111";
const contactKey = Buffer.alloc(32, 0x11);
const credentialsKey = Buffer.alloc(32, 0x22);

test("booking-offer worker sends a queued PostgreSQL delivery through fake SMTP and audits sent", {
  skip: !enabled,
}, async () => {
  const owner = new Pool({ connectionString: migratorUrl, max: 2 });
  const worker = new Pool({ connectionString: workerUrl, max: 2 });
  const suffix = randomBytes(6).toString("hex");
  const actorUserId = randomUUID();
  const actorId = randomUUID();
  const roleId = randomUUID();
  const inquiryId = randomUUID();
  const draftId = randomUUID();
  const draftRevisionId = randomUUID();
  const priceListId = randomUUID();
  const priceRevisionId = randomUUID();
  const cancellationId = randomUUID();
  const cancellationRevisionId = randomUUID();
  const approvalId = randomUUID();
  const approvalRevisionId = randomUUID();
  const deliveryConfigId = randomUUID();
  const email = `booking-worker-${suffix}@example.invalid`;
  const token = randomBytes(32).toString("base64url");
  const tokenHash = createHash("sha256").update(token).digest("hex");
  const idempotencyHash = createHash("sha256").update(randomBytes(32)).digest("hex");
  const emailCiphertext = encryptContactValue(email, contactKey, {
    organizationId, contactKind: "email",
  });
  const nameCiphertext = encryptContactValue("CI Booking Customer", contactKey, {
    organizationId, contactKind: "other",
  });
  const submittedCiphertext = encryptContactValue("Synthetic booking inquiry", contactKey, {
    organizationId, contactKind: "other",
  });
  const capabilityCiphertext = encryptContactValue(token, contactKey, {
    organizationId, contactKind: "other",
  });
  let deliveryId: string | undefined;
  const smtpMessages: { to: string; subject: string; text: string }[] = [];
  let smtpCalls = 0;

  const fakeSmtp: SmtpTransportFactory = (settings, credentials) => {
    assert.match(settings.host, /\.invalid$/);
    assert.equal(credentials, null);
    return {
      async verify() { return true; },
      async sendMail(message) {
        smtpCalls += 1;
        smtpMessages.push(message);
        return { messageId: `<ci-${suffix}@example.invalid>`, accepted: [message.to] };
      },
      close() {},
    };
  };

  try {
    const client = await owner.connect();
    try {
      await client.query("BEGIN");
      await client.query("SET LOCAL ROLE eventor_owner");
      await client.query("SELECT set_config('app.organization_id',$1,true)", [organizationId]);

      await client.query(
        `INSERT INTO eogp.users(id,email,display_name,status)
         VALUES($1,$2,'CI Booking Email Worker','active')`,
        [actorUserId, `booking-worker-actor-${suffix}@example.invalid`],
      );
      await client.query(
        `INSERT INTO eogp.organization_memberships(id,organization_id,user_id,status,joined_at)
         VALUES($1,$2,$3,'active',clock_timestamp())`,
        [actorId, organizationId, actorUserId],
      );
      await client.query(
        `INSERT INTO eogp.roles(id,organization_id,code,name,scope_kind)
         VALUES($1,$2,$3,'CI Booking Worker','organization')`,
        [roleId, organizationId, `ci-booking-worker-${suffix}`],
      );
      await client.query(
        `INSERT INTO eogp.role_permissions(organization_id,role_id,permission_code)
         VALUES($1,$2,'booking.manage')`,
        [organizationId, roleId],
      );
      await client.query(
        `INSERT INTO eogp.user_role_grants(
           organization_id,membership_id,role_id,scope_kind,granted_by_membership_id
         ) VALUES($1,$2,$3,'organization',$2)`,
        [organizationId, actorId, roleId],
      );

      await client.query(
        `INSERT INTO eogp.booking_inquiries(
           id,organization_id,public_reference,submitted_values_ciphertext,
           requester_name_ciphertext,requester_email_hash,requester_email_ciphertext
         ) VALUES($1,$2,$3,$4,$5,$6,$7)`,
        [inquiryId, organizationId, `CI-WORKER-${suffix}`, submittedCiphertext,
          nameCiphertext, createHash("sha256").update(email.toLowerCase()).digest("hex"), emailCiphertext],
      );
      await client.query(
        `INSERT INTO eogp.booking_drafts(
           id,organization_id,source_inquiry_id,created_by_membership_id,current_revision_number
         ) VALUES($1,$2,$3,$4,1)`,
        [draftId, organizationId, inquiryId, actorId],
      );
      await client.query(
        `INSERT INTO eogp.booking_draft_revisions(
           id,organization_id,draft_id,revision_number,values_snapshot,
           requested_start,requested_end,timezone_name,created_by_membership_id
         ) VALUES($1,$2,$3,1,'{"fixture":"booking-offer-worker"}',
           clock_timestamp()+interval '10 days',clock_timestamp()+interval '10 days 2 hours',
           'Europe/Sarajevo',$4)`,
        [draftRevisionId, organizationId, draftId, actorId],
      );

      await client.query(
        `INSERT INTO eogp.booking_price_lists(id,organization_id,scope_kind,code,name)
         VALUES($1,$2,'organization',$3,'CI Worker Price List')`,
        [priceListId, organizationId, `CI-WORKER-${suffix}`],
      );
      await client.query(
        `INSERT INTO eogp.booking_price_list_revisions(
           id,organization_id,price_list_id,revision_number,currency,tax_basis,state,published_at
         ) VALUES($1,$2,$3,1,'USD','not_applicable','draft',NULL)`,
        [priceRevisionId, organizationId, priceListId],
      );
      await client.query(
        `INSERT INTO eogp.booking_price_items(
           organization_id,price_list_revision_id,item_code,label,unit,unit_amount
         ) VALUES($1,$2,'ROOM','Meeting room','hour',50)`,
        [organizationId, priceRevisionId],
      );
      await client.query(
        `UPDATE eogp.booking_price_list_revisions
            SET state='published',published_at=clock_timestamp()
          WHERE organization_id=$1 AND id=$2`,
        [organizationId, priceRevisionId],
      );

      await client.query(
        `INSERT INTO eogp.cancellation_policies(id,organization_id,code,name)
         VALUES($1,$2,$3,'CI Worker Cancellation Policy')`,
        [cancellationId, organizationId, `CI-WORKER-${suffix}`],
      );
      await client.query(
        `INSERT INTO eogp.cancellation_policy_revisions(
           id,organization_id,cancellation_policy_id,revision_number,customer_mode,
           public_terms,state,published_at
         ) VALUES($1,$2,$3,1,'request_only','Synthetic CI terms','published',clock_timestamp())`,
        [cancellationRevisionId, organizationId, cancellationId],
      );
      await client.query(
        `INSERT INTO eogp.booking_approval_policies(id,organization_id,code,name)
         VALUES($1,$2,$3,'CI Worker Approval Policy')`,
        [approvalId, organizationId, `CI-WORKER-${suffix}`],
      );
      await client.query(
        `INSERT INTO eogp.booking_approval_policy_revisions(
           id,organization_id,policy_id,revision_number,state,rules,published_at
         ) VALUES($1,$2,$3,1,'published','[]',clock_timestamp())`,
        [approvalRevisionId, organizationId, approvalId],
      );

      const smtpSettings = {
        host: `smtp-ci-${suffix}.invalid`, port: 587, transportSecurity: "starttls",
        authMode: "none", senderEmail: "events@example.invalid",
        senderName: "Eventor CI", connectionTimeoutMs: 1000,
      };
      await client.query(
        `INSERT INTO eogp.organization_delivery_config_revisions(
           id,organization_id,channel,revision,provider,settings,created_by_membership_id
         ) VALUES($1,$2,'email',1,'smtp',$3::jsonb,$4)`,
        [deliveryConfigId, organizationId, JSON.stringify(smtpSettings), actorId],
      );
      await client.query(
        `INSERT INTO eogp.organization_delivery_config_heads(
           organization_id,channel,revision_id,delivery_enabled
         ) VALUES($1,'email',$2,true)`,
        [organizationId, deliveryConfigId],
      );

      await client.query("SELECT set_config('app.actor_membership_id',$1,true)", [actorId]);
      const prepared = await client.query(
        `SELECT eogp.save_booking_offer_revision(
          $1::uuid,$2::uuid,$3::uuid,NULL,$4::uuid,$5::uuid,$6::uuid,
          'USD','not_applicable',clock_timestamp()+interval '2 days',
          '[{"itemCode":"ROOM","quantity":2}]'::jsonb,'[]'::jsonb,0,NULL,false
        ) AS result`,
        [organizationId, draftRevisionId, actorId, priceRevisionId,
          cancellationRevisionId, approvalRevisionId],
      );
      const offerId = prepared.rows[0].result.offerId as string;
      await client.query(
        "SELECT eogp.issue_booking_offer($1::uuid,$2::uuid,$3::uuid,$4::text)",
        [organizationId, offerId, actorId, tokenHash],
      );
      const queued = await client.query(
        `SELECT eogp.queue_booking_offer_email_delivery(
          $1::uuid,$2::uuid,$3::uuid,$4::text,$5::text,$6::bytea
        ) AS result`,
        [organizationId, offerId, actorId, idempotencyHash, tokenHash, capabilityCiphertext],
      );
      deliveryId = queued.rows[0].result.deliveryId as string;
      assert.ok(deliveryId);
      await client.query("COMMIT");
    } catch (error) {
      await client.query("ROLLBACK");
      throw error;
    } finally {
      client.release();
    }

    const totals = await processPendingBookingOfferEmailDeliveries(
      worker, contactKey, credentialsKey, "https://app.example.invalid",
      5, 100, fakeSmtp,
    );
    assert.equal(totals.bookingOfferEmailAttempts, 1);
    assert.equal(totals.bookingOfferEmailSent, 1);
    assert.equal(smtpCalls, 1);
    assert.equal(smtpMessages[0]?.to, email);
    assert.match(smtpMessages[0]?.text ?? "", new RegExp(`/offers/[^\\s]+#token=${token}`));

    const verification = await owner.connect();
    try {
      await verification.query("BEGIN");
      await verification.query("SET LOCAL ROLE eventor_owner");
      await verification.query("SELECT set_config('app.organization_id',$1,true)", [organizationId]);
      const row = await verification.query(
        `SELECT status,attempt_count,provider_message_reference,sent_at
           FROM eogp.booking_offer_email_deliveries
          WHERE organization_id=$1 AND id=$2`,
        [organizationId, deliveryId],
      );
      assert.equal(row.rowCount, 1);
      assert.equal(row.rows[0].status, "sent");
      assert.equal(row.rows[0].attempt_count, 1);
      assert.equal(row.rows[0].provider_message_reference, `<ci-${suffix}@example.invalid>`);
      assert.ok(row.rows[0].sent_at);
      const audit = await verification.query(
        `SELECT actor_kind,actor_service_principal_id,action FROM eogp.audit_events
          WHERE organization_id=$1 AND aggregate_id=$2
            AND action='booking.offer.email_sent'`,
        [organizationId, (await verification.query(
          "SELECT offer_id FROM eogp.booking_offer_email_deliveries WHERE id=$1", [deliveryId],
        )).rows[0].offer_id],
      );
      assert.ok(audit.rows.some((entry) =>
        entry.actor_kind === "service_principal" && entry.actor_service_principal_id !== null && entry.action === "booking.offer.email_sent"));
      await verification.query("COMMIT");
    } catch (error) {
      await verification.query("ROLLBACK");
      throw error;
    } finally {
      verification.release();
    }

    const resetDelivery = async (attemptCount: number) => {
      const reset = await owner.connect();
      try {
        await reset.query("BEGIN");
        await reset.query("SET LOCAL ROLE eventor_owner");
        await reset.query("SELECT set_config('app.organization_id',$1,true)", [organizationId]);
        await reset.query(
          `UPDATE eogp.booking_offer_email_deliveries
              SET status='queued',attempt_count=$3,next_attempt_at=clock_timestamp(),
                  lease_expires_at=NULL,last_failure_code=NULL,
                  provider_message_reference=NULL,sent_at=NULL,updated_at=clock_timestamp()
            WHERE organization_id=$1 AND id=$2`,
          [organizationId, deliveryId, attemptCount],
        );
        await reset.query(
          `INSERT INTO eogp.booking_offer_email_delivery_tenant_queue(organization_id,available_at)
           VALUES($1,clock_timestamp())
           ON CONFLICT (organization_id) DO UPDATE
             SET available_at=EXCLUDED.available_at,updated_at=clock_timestamp()`,
          [organizationId],
        );
        await reset.query("COMMIT");
      } catch (error) {
        await reset.query("ROLLBACK");
        throw error;
      } finally {
        reset.release();
      }
    };

    const connectionFailure: SmtpTransportFactory = () => ({
      async verify() { return true; },
      async sendMail() {
        throw Object.assign(new Error("synthetic SMTP connection reset"), { code: "ECONNRESET" });
      },
      close() {},
    });
    await resetDelivery(0);
    const retryTotals = await processPendingBookingOfferEmailDeliveries(
      worker, contactKey, credentialsKey, "https://app.example.invalid",
      5, 100, connectionFailure,
    );
    assert.equal(retryTotals.bookingOfferEmailAttempts, 1);
    assert.equal(retryTotals.bookingOfferEmailFailed, 1);
    assert.equal(retryTotals.bookingOfferEmailRetriesScheduled, 1);

    const retryCheck = await owner.connect();
    try {
      await retryCheck.query("BEGIN");
      await retryCheck.query("SET LOCAL ROLE eventor_owner");
      await retryCheck.query("SELECT set_config('app.organization_id',$1,true)", [organizationId]);
      const row = await retryCheck.query(
        `SELECT status,attempt_count,last_failure_code,next_attempt_at,lease_expires_at
           FROM eogp.booking_offer_email_deliveries WHERE organization_id=$1 AND id=$2`,
        [organizationId, deliveryId],
      );
      assert.equal(row.rows[0].status, "queued");
      assert.equal(row.rows[0].attempt_count, 1);
      assert.equal(row.rows[0].last_failure_code, "SMTP_CONNECTION");
      assert.ok(new Date(row.rows[0].next_attempt_at).getTime() > Date.now());
      assert.equal(row.rows[0].lease_expires_at, null);
      await retryCheck.query("COMMIT");
    } catch (error) {
      await retryCheck.query("ROLLBACK");
      throw error;
    } finally {
      retryCheck.release();
    }

    const ambiguousFailure: SmtpTransportFactory = () => ({
      async verify() { return true; },
      async sendMail() {
        throw Object.assign(new Error("synthetic disconnect during DATA"), { command: "DATA" });
      },
      close() {},
    });
    await resetDelivery(1);
    const uncertainTotals = await processPendingBookingOfferEmailDeliveries(
      worker, contactKey, credentialsKey, "https://app.example.invalid",
      5, 100, ambiguousFailure,
    );
    assert.equal(uncertainTotals.bookingOfferEmailAttempts, 1);
    assert.equal(uncertainTotals.bookingOfferEmailUncertain, 1);
    assert.equal(uncertainTotals.bookingOfferEmailRetriesScheduled, 0);

    const uncertainCheck = await owner.connect();
    try {
      await uncertainCheck.query("BEGIN");
      await uncertainCheck.query("SET LOCAL ROLE eventor_owner");
      await uncertainCheck.query("SELECT set_config('app.organization_id',$1,true)", [organizationId]);
      const row = await uncertainCheck.query(
        `SELECT status,attempt_count,last_failure_code,provider_message_reference,
                sent_at,lease_expires_at
           FROM eogp.booking_offer_email_deliveries WHERE organization_id=$1 AND id=$2`,
        [organizationId, deliveryId],
      );
      assert.equal(row.rows[0].status, "uncertain");
      assert.equal(row.rows[0].attempt_count, 2);
      assert.equal(row.rows[0].last_failure_code, "SMTP_UNKNOWN");
      assert.equal(row.rows[0].provider_message_reference, null);
      assert.equal(row.rows[0].sent_at, null);
      assert.equal(row.rows[0].lease_expires_at, null);
      const audit = await uncertainCheck.query(
        `SELECT actor_kind,actor_service_principal_id,action FROM eogp.audit_events
          WHERE organization_id=$1 AND aggregate_id=$2
            AND action IN ('booking.offer.email_failed','booking.offer.email_uncertain')`,
        [organizationId, (await uncertainCheck.query(
          "SELECT offer_id FROM eogp.booking_offer_email_deliveries WHERE id=$1", [deliveryId],
        )).rows[0].offer_id],
      );
      assert.ok(audit.rows.some((entry) =>
        entry.action === "booking.offer.email_failed" &&
        entry.actor_kind === "service_principal" && entry.actor_service_principal_id !== null));
      assert.ok(audit.rows.some((entry) =>
        entry.action === "booking.offer.email_uncertain" &&
        entry.actor_kind === "service_principal" && entry.actor_service_principal_id !== null));
      await uncertainCheck.query("COMMIT");
    } catch (error) {
      await uncertainCheck.query("ROLLBACK");
      throw error;
    } finally {
      uncertainCheck.release();
    }
  } finally {
    await owner.end();
    await worker.end();
  }
});
