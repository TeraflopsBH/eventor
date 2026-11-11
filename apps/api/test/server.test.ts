import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import test from "node:test";
import type { Pool, PoolClient } from "pg";
import { buildApi, type StaffPrincipal } from "../src/server.js";
import { encryptDeliveryCredentialBundle } from "../src/delivery-credentials-crypto.js";
import type { SmtpTransportFactory } from "../src/smtp-transport.js";

const resendWebhookSigningSecret = `whsec_${Buffer.from("eventor-resend-webhook-test-secret-32-bytes").toString("base64")}`;

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
  let campaignReviewCalls = 0;
  let campaignListCalls = 0;
  let campaignProgressCalls = 0;
  let campaignDeliveryListCalls = 0;
  let campaignConfirmCalls = 0;
  let deliveryConfigCalls = 0;
  let deliveryTestBegins = 0;
  let deliveryTestCompletions = 0;
  let campaignQueueCalls = 0;
  let campaignCancelCalls = 0;
  let deliveryReconcileCalls = 0;
  let deliveryRetryCalls = 0;
  let resendWebhookPrepareCalls = 0;
  let resendWebhookActivateCalls = 0;
  let resendWebhookResolveCalls = 0;
  let resendWebhookRecordCalls = 0;
  const deliveryTests = new Map<string, string>();

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
      if (normalized.includes("eogp.list_event_notification_campaigns(")) {
        campaignListCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          items: [{
            campaignId: "94900000-0000-4000-8000-000000000001",
            eventId: "94000000-0000-4000-8000-000000000001",
            purpose: "event_cancellation", audienceKind: "all_previously_invited",
            status: "queued", recipientCount: 2, actualRecipientCount: 2,
            createdAt: "2026-11-11T09:00:00.000Z", confirmedAt: null,
            queuedAt: "2026-11-11T09:01:00.000Z", deliveryStartedAt: null,
            deliveryCompletedAt: null,
          }],
          page: { limit: values[3], offset: values[4], total: 1 },
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.get_event_notification_campaign_progress(")) {
        campaignProgressCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          campaignId: values[1], eventId: "94000000-0000-4000-8000-000000000001",
          status: "sending", purpose: "event_cancellation", recipientCount: 2,
          attemptCount: 3,
          deliveryCounts: { queued: 1, sending: 0, sent: 1, failed: 0, uncertain: 0, suppressed: 0 },
          createdAt: "2026-11-11T09:00:00.000Z", confirmedAt: null,
          queuedAt: "2026-11-11T09:01:00.000Z", deliveryStartedAt: "2026-11-11T09:02:00.000Z",
          deliveryCompletedAt: null,
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.list_event_notification_campaign_deliveries(")) {
        campaignDeliveryListCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          items: [{
            attemptId: "95000000-0000-4000-8000-000000000001",
            recipientReference: "95100000-0000-4000-8000-000000000001",
            channel: "email", attemptNumber: 1, status: "failed",
            failureCode: "SMTP_4XX", provider: "smtp",
            queuedForAt: "2026-11-11T09:01:00.000Z", sendingAt: "2026-11-11T09:02:00.000Z",
            completedAt: "2026-11-11T09:03:00.000Z", retryScheduled: true,
          }],
          page: { limit: values[4], offset: values[5], total: 1 },
          counts: { failed: 1, queued: 1 },
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.get_event_notification_campaign_review(")) {
        campaignReviewCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          campaignId: values[1], status: "previewed", recipientCount: 2,
          actualRecipientCount: 2, recipients: [{ participationId: "p1", channel: "email" }],
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.confirm_event_notification_campaign(")) {
        campaignConfirmCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          campaignId: values[1], status: "confirmed", recipientCount: 2,
          deliveryQueued: false,
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.begin_organization_email_delivery_test(")) {
        deliveryTestBegins += 1;
        const idempotencyHash = String(values[2]);
        const existing = deliveryTests.get(idempotencyHash);
        if (existing) {
          return { rows: [{ result: {
            requestId: existing, status: "succeeded", created: false,
            configRevisionId: "dddddddd-4444-4444-8444-dddddddddddd",
          } }], rowCount: 1 };
        }
        const requestId = "eeeeeeee-5555-4555-8555-eeeeeeeeeeee";
        deliveryTests.set(idempotencyHash, requestId);
        return { rows: [{ result: {
          requestId, status: "pending", created: true,
          configRevisionId: "dddddddd-4444-4444-8444-dddddddddddd",
          settings: {
            host: "smtp.example.test", port: 587, transportSecurity: "starttls",
            authMode: "none", senderEmail: "events@example.test",
            senderName: "Eventor", connectionTimeoutMs: 15000,
          },
          credentialsCiphertextBase64: null,
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.complete_organization_email_delivery_test(")) {
        deliveryTestCompletions += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          requestId: values[2], status: values[3] ? "succeeded" : "failed",
          deliveryEnabled: Boolean(values[3]),
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.queue_event_notification_campaign(")) {
        campaignQueueCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          campaignId: values[1], status: "queued",
          emailRecipientCount: 2, smsSuppressedCount: 1,
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.cancel_queued_event_notification_campaign(")) {
        campaignCancelCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          campaignId: values[1], status: "cancelled", suppressedAttempts: 2,
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.reconcile_notification_delivery_attempt(")) {
        deliveryReconcileCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { attemptId: values[1], previousStatus: "uncertain", status: "sent", campaignStatus: "partial" } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.retry_failed_notification_delivery_attempt(")) {
        deliveryRetryCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { attemptId: "95200000-0000-4000-8000-000000000001", previousAttemptId: values[1], attemptNumber: 2, status: "queued" } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.get_organization_resend_webhook_configuration(")) {
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { endpointId: "95300000-0000-4000-8000-000000000001", configured: true, updatedAt: "2026-11-11T12:00:00.000Z" } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.prepare_organization_resend_webhook_endpoint(")) {
        resendWebhookPrepareCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { endpointId: values[2], enabled: false } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.activate_organization_resend_webhook_endpoint(")) {
        resendWebhookActivateCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { endpointId: values[2], enabled: true, updatedAt: "2026-11-11T12:00:00.000Z" } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.resolve_organization_resend_webhook_endpoint(")) {
        resendWebhookResolveCalls += 1;
        const ciphertext = encryptDeliveryCredentialBundle(
          { signingSecret: resendWebhookSigningSecret },
          Buffer.alloc(32, 9),
          { organizationId: principal.organizationId, channel: "email" },
        );
        return { rows: [{ result: {
          organizationId: principal.organizationId,
          signingSecretCiphertextBase64: ciphertext.toString("base64"),
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.record_verified_resend_delivery_webhook(")) {
        resendWebhookRecordCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: { accepted: true, duplicate: false, attemptId: "95000000-0000-4000-8000-000000000001", status: values[4] } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.get_organization_email_delivery_config(")) {
        return { rows: [{ result: {
          channel: "email", provider: "smtp", revision: 2,
          settings: { host: "smtp.example.test", port: 587, transportSecurity: "starttls", authMode: "password" },
          credentialsConfigured: true,
        } }], rowCount: 1 };
      }
      if (normalized.includes("eogp.set_organization_email_delivery_config(")) {
        deliveryConfigCalls += 1;
        commandCalls.push({ sql: normalized, values });
        return { rows: [{ result: {
          channel: "email", provider: "smtp", revision: 3,
          settings: JSON.parse(String(values[2])),
          credentialsConfigured: Boolean(values[4]) || Boolean(values[5]) === false,
        } }], rowCount: 1 };
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
    get campaignReviewCalls() { return campaignReviewCalls; },
    get campaignListCalls() { return campaignListCalls; },
    get campaignProgressCalls() { return campaignProgressCalls; },
    get campaignDeliveryListCalls() { return campaignDeliveryListCalls; },
    get campaignConfirmCalls() { return campaignConfirmCalls; },
    get deliveryConfigCalls() { return deliveryConfigCalls; },
    get deliveryTestBegins() { return deliveryTestBegins; },
    get deliveryTestCompletions() { return deliveryTestCompletions; },
    get campaignQueueCalls() { return campaignQueueCalls; },
    get campaignCancelCalls() { return campaignCancelCalls; },
    get deliveryReconcileCalls() { return deliveryReconcileCalls; },
    get deliveryRetryCalls() { return deliveryRetryCalls; },
    get resendWebhookPrepareCalls() { return resendWebhookPrepareCalls; },
    get resendWebhookActivateCalls() { return resendWebhookActivateCalls; },
    get resendWebhookResolveCalls() { return resendWebhookResolveCalls; },
    get resendWebhookRecordCalls() { return resendWebhookRecordCalls; },
  };
}

function makeApi(
  pool: Pool,
  options: {
    authenticated?: boolean;
    originValid?: boolean;
    encryptionKey?: Buffer;
    loginOriginValid?: boolean;
    withSessionCallbacks?: boolean;
    smtpTransportFactory?: SmtpTransportFactory;
    publicApiBaseUrl?: string;
  } = {},
) {
  return buildApi({
    pool,
    authenticateStaff: async () => options.authenticated === false ? null : principal,
    verifyMutationOrigin: async () => options.originValid !== false,
    verifyLoginOrigin: () => options.loginOriginValid !== false,
    ...(options.withSessionCallbacks ? {
      createStaffSession: async () => ({
        principal,
        sessionToken: "S".repeat(43),
        csrfToken: "C".repeat(43),
        expiresAt: new Date(Date.now() + 60 * 60 * 1000),
      }),
      revokeStaffSession: async () => undefined,
      getCurrentPrincipal: async () => ({ ...principal, memberships: [] }),
    } : {}),
    privateFieldEncryptionKey: options.encryptionKey ?? Buffer.alloc(32, 7),
    deliveryCredentialsEncryptionKey: Buffer.alloc(32, 9),
    publicApiBaseUrl: options.publicApiBaseUrl ?? "https://eventor.example.test/api",
    ...(options.smtpTransportFactory ? { smtpTransportFactory: options.smtpTransportFactory } : {}),
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

  const differentBooking = await app.inject({
    method: "POST",
    url: "/bookings/73000000-0000-4000-8000-000000000002/reservations/release",
    headers,
    payload,
  });
  assert.equal(differentBooking.statusCode, 409);
  assert.equal(differentBooking.json().code, "IDEMPOTENCY_KEY_REUSED");
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


test("staff login, current-principal and logout routes use cookie sessions and explicit CSRF/origin checks", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool, { withSessionCallbacks: true });
  t.after(async () => app.close());

  const login = await app.inject({
    method: "POST",
    url: "/auth/session",
    headers: { origin: "https://staff.example.test" },
    payload: {
      email: "staff@example.test",
      password: "correct horse battery staple",
      organizationSlug: "event-owner",
    },
  });
  assert.equal(login.statusCode, 200);
  assert.equal(login.json().data.userId, principal.userId);
  const setCookie = login.headers["set-cookie"];
  assert.ok(Array.isArray(setCookie));
  assert.ok(setCookie.some((value) => value.startsWith("__Host-eventor_session=")));
  assert.ok(setCookie.some((value) => value.startsWith("__Host-eventor_csrf=")));

  const current = await app.inject({
    method: "GET",
    url: "/me",
    headers: { cookie: "__Host-eventor_session=" + "S".repeat(43) },
  });
  assert.equal(current.statusCode, 200);
  assert.equal(current.json().data.userId, principal.userId);

  const logout = await app.inject({
    method: "DELETE",
    url: "/auth/session",
    headers: { cookie: "__Host-eventor_session=" + "S".repeat(43) },
  });
  assert.equal(logout.statusCode, 204);
  const clearCookie = logout.headers["set-cookie"];
  assert.ok(Array.isArray(clearCookie));
  assert.ok(clearCookie.every((value) => value.includes("Max-Age=0")));
});

test("staff login rejects requests without the configured browser origin", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool, { withSessionCallbacks: true, loginOriginValid: false });
  t.after(async () => app.close());
  const login = await app.inject({
    method: "POST",
    url: "/auth/session",
    payload: {
      email: "staff@example.test",
      password: "correct horse battery staple",
      organizationSlug: "event-owner",
    },
  });
  assert.equal(login.statusCode, 403);
  assert.equal(login.json().code, "ORIGIN_REJECTED");
});


test("Resend webhook endpoint configuration returns a callback URL and stores its signing secret encrypted", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());

  const current = await app.inject({
    method: "GET",
    url: "/organization/delivery/email/resend-webhook",
  });
  assert.equal(current.statusCode, 200);
  assert.equal(current.json<{ data: { configured: boolean; callbackUrl: string } }>().data.configured, true);
  assert.equal(current.json<{ data: { callbackUrl: string } }>().data.callbackUrl,
    "https://eventor.example.test/api/webhooks/resend/95300000-0000-4000-8000-000000000001");

  const prepared = await app.inject({
    method: "POST",
    url: "/organization/delivery/email/resend-webhook/prepare",
    headers: { "idempotency-key": "resend-webhook-prepare-01" },
    payload: {},
  });
  assert.equal(prepared.statusCode, 201);
  assert.equal(prepared.json<{ data: { callbackUrl: string; enabled: boolean } }>().data.enabled, false);
  assert.match(prepared.json<{ data: { callbackUrl: string } }>().data.callbackUrl, /^https:\/\/eventor\.example\.test\/api\/webhooks\/resend\//);
  assert.equal(mock.resendWebhookPrepareCalls, 1);

  const endpointId = "95300000-0000-4000-8000-000000000001";
  const activated = await app.inject({
    method: "POST",
    url: "/organization/delivery/email/resend-webhook/activate",
    headers: { "idempotency-key": "resend-webhook-activate-01" },
    payload: { endpointId, signingSecret: resendWebhookSigningSecret },
  });
  assert.equal(activated.statusCode, 201);
  assert.equal(activated.json<{ data: { enabled: boolean } }>().data.enabled, true);
  assert.equal(mock.resendWebhookActivateCalls, 1);
  const ciphertext = mock.commandCalls.find(call => call.sql.includes("activate_organization_resend_webhook_endpoint"))?.values[3] as Buffer;
  assert.ok(Buffer.isBuffer(ciphertext));
  assert.equal(ciphertext.subarray(0, 4).toString("ascii"), "EDC1");
  assert.notEqual(ciphertext.toString("utf8"), resendWebhookSigningSecret);
});

test("public Resend webhook accepts a valid signature without a staff session and records the normalized delivery event", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool, { authenticated: false });
  t.after(async () => app.close());
  const endpointId = "95300000-0000-4000-8000-000000000001";
  const svixId = "msg_01JRESEND000000000000000001";
  const timestamp = String(Math.floor(Date.now() / 1000));
  const raw = JSON.stringify({
    type: "email.delivered",
    created_at: "2026-11-11T12:00:00.000Z",
    data: {
      email_id: "f53e1234-1234-4234-8234-123456789012",
      message_id: "<eventor-attempt-1@example.test>",
      to: ["guest@example.test"],
    },
  });
  const signature = createHmac("sha256", Buffer.from(resendWebhookSigningSecret.slice(6), "base64"))
    .update(`${svixId}.${timestamp}.${raw}`, "utf8")
    .digest("base64");
  const response = await app.inject({
    method: "POST",
    url: `/webhooks/resend/${endpointId}`,
    headers: {
      "content-type": "application/json",
      "svix-id": svixId,
      "svix-timestamp": timestamp,
      "svix-signature": `v1,${signature}`,
    },
    payload: raw,
  });
  assert.equal(response.statusCode, 200);
  assert.equal(response.json<{ status: string; duplicate: boolean }>().status, "delivered");
  assert.equal(mock.resendWebhookResolveCalls, 1);
  assert.equal(mock.resendWebhookRecordCalls, 1);
  const call = mock.commandCalls.find(item => item.sql.includes("record_verified_resend_delivery_webhook"));
  assert.equal(call?.values[0], principal.organizationId);
  assert.equal(call?.values[1], endpointId);
  assert.equal(call?.values[2], svixId);
  assert.equal(call?.values[3], "<eventor-attempt-1@example.test>");
  assert.equal(call?.values[4], "delivered");
});

test("public Resend webhook rejects forged signatures before delivery-event ingestion", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool, { authenticated: false });
  t.after(async () => app.close());
  const timestamp = String(Math.floor(Date.now() / 1000));
  const raw = JSON.stringify({ type: "email.bounced", data: { message_id: "<eventor-attempt-2@example.test>", to: ["guest@example.test"] } });
  const response = await app.inject({
    method: "POST",
    url: "/webhooks/resend/95300000-0000-4000-8000-000000000001",
    headers: {
      "content-type": "application/json",
      "svix-id": "msg_01JRESEND000000000000000002",
      "svix-timestamp": timestamp,
      "svix-signature": "v1,AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
    },
    payload: raw,
  });
  assert.equal(response.statusCode, 401);
  assert.equal(mock.resendWebhookResolveCalls, 1);
  assert.equal(mock.resendWebhookRecordCalls, 0);
});

test("campaign list applies pagination and returns only the database permission projection", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const response = await app.inject({
    method: "GET",
    url: "/event-notification-campaigns?status=queued&limit=10&offset=20",
  });
  assert.equal(response.statusCode, 200);
  const payload = response.json<{ data: Array<{ campaignId: string }>; meta: { limit: number; offset: number; totalCount: number } }>();
  assert.equal(payload.data[0]?.campaignId, "94900000-0000-4000-8000-000000000001");
  assert.deepEqual(payload.meta, { limit: 10, offset: 20, totalCount: 1 });
  assert.equal(mock.campaignListCalls, 1);
  assert.equal(mock.commandCalls[0]?.values[0], principal.organizationId);
  assert.equal(mock.commandCalls[0]?.values[1], principal.membershipId);
  assert.equal(mock.commandCalls[0]?.values[2], "queued");
});

test("campaign progress and delivery report expose only operational attempt metadata", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const campaignId = "94900000-0000-4000-8000-000000000001";
  const progress = await app.inject({
    method: "GET",
    url: `/event-notification-campaigns/${campaignId}`,
  });
  assert.equal(progress.statusCode, 200);
  assert.equal(progress.json<{ data: { deliveryCounts: { sent: number } } }>().data.deliveryCounts.sent, 1);
  assert.equal(mock.campaignProgressCalls, 1);

  const deliveries = await app.inject({
    method: "GET",
    url: `/event-notification-campaigns/${campaignId}/deliveries?status=failed&limit=5&offset=0`,
  });
  assert.equal(deliveries.statusCode, 200);
  const payload = deliveries.json<{
    data: Array<{ status: string; failureCode: string; recipientReference: string }>;
    meta: { totalCount: number; counts: Record<string, number> };
  }>();
  assert.equal(payload.data[0]?.status, "failed");
  assert.equal(payload.data[0]?.failureCode, "SMTP_4XX");
  assert.equal(payload.meta.counts.failed, 1);
  assert.equal("email" in payload.data[0]!, false);
  assert.equal("phone" in payload.data[0]!, false);
  assert.equal("providerMessageReference" in payload.data[0]!, false);
  assert.equal(mock.campaignDeliveryListCalls, 1);
  assert.equal(mock.commandCalls[1]?.values[2], principal.membershipId);
  assert.equal(mock.commandCalls[1]?.values[3], "failed");
});

test("delivery reconciliation is an idempotent permission-gated operator command", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const attemptId = "95000000-0000-4000-8000-000000000001";
  const payload = { resolution: "confirmed_sent", reason: "Provider dashboard confirms SMTP acceptance." };
  const headers = { "idempotency-key": "delivery-reconcile-0001" };
  const first = await app.inject({
    method: "POST", url: `/notification-delivery-attempts/${attemptId}/reconcile`,
    headers, payload,
  });
  assert.equal(first.statusCode, 201);
  assert.equal(first.json<{ data: { status: string } }>().data.status, "sent");
  assert.equal(mock.deliveryReconcileCalls, 1);
  assert.equal(mock.commandCalls[0]?.values[0], principal.organizationId);
  assert.equal(mock.commandCalls[0]?.values[1], attemptId);
  assert.equal(mock.commandCalls[0]?.values[2], principal.membershipId);
  const replay = await app.inject({
    method: "POST", url: `/notification-delivery-attempts/${attemptId}/reconcile`,
    headers, payload,
  });
  assert.equal(replay.statusCode, 201);
  assert.equal(mock.deliveryReconcileCalls, 1);
});

test("operator delivery retry is a separate reasoned and idempotent command", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const attemptId = "95000000-0000-4000-8000-000000000001";
  const payload = { reason: "Operator verified the remote server did not accept the message." };
  const headers = { "idempotency-key": "delivery-retry-0001" };
  const response = await app.inject({
    method: "POST", url: `/notification-delivery-attempts/${attemptId}/retry`,
    headers, payload,
  });
  assert.equal(response.statusCode, 201);
  assert.equal(response.json<{ data: { status: string; attemptNumber: number } }>().data.status, "queued");
  assert.equal(mock.deliveryRetryCalls, 1);
  assert.equal(mock.commandCalls[0]?.values[0], principal.organizationId);
  assert.equal(mock.commandCalls[0]?.values[1], attemptId);
  assert.equal(mock.commandCalls[0]?.values[2], principal.membershipId);
});

test("campaign review returns a restricted snapshot projection through the permission-gated database function", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const response = await app.inject({
    method: "GET",
    url: "/event-notification-campaigns/94900000-0000-4000-8000-000000000001/review",
  });
  assert.equal(response.statusCode, 200);
  assert.equal(response.json<{ data: { status: string; actualRecipientCount: number } }>().data.status, "previewed");
  assert.equal(response.json<{ data: { actualRecipientCount: number } }>().data.actualRecipientCount, 2);
  assert.equal(mock.campaignReviewCalls, 1);
  assert.equal(mock.commandCalls[0]?.values[0], principal.organizationId);
  assert.equal(mock.commandCalls[0]?.values[2], principal.membershipId);
});

test("campaign confirmation is idempotent and explicitly does not queue delivery", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const headers = { "idempotency-key": "confirm-campaign-0001" };
  const payload = {};
  const first = await app.inject({
    method: "POST",
    url: "/event-notification-campaigns/94900000-0000-4000-8000-000000000001/confirm",
    headers,
    payload,
  });
  assert.equal(first.statusCode, 201);
  assert.equal(first.json<{ data: { status: string; deliveryQueued: boolean } }>().data.status, "confirmed");
  assert.equal(first.json<{ data: { deliveryQueued: boolean } }>().data.deliveryQueued, false);
  assert.equal(mock.campaignConfirmCalls, 1);
  assert.equal(mock.commandCalls[0]?.values[2], principal.membershipId);

  const replay = await app.inject({
    method: "POST",
    url: "/event-notification-campaigns/94900000-0000-4000-8000-000000000001/confirm",
    headers,
    payload,
  });
  assert.equal(replay.statusCode, 201);
  assert.deepEqual(replay.json<Record<string, unknown>>(), first.json<Record<string, unknown>>());
  assert.equal(mock.campaignConfirmCalls, 1);
});

test("campaign confirmation rejects an invalid browser origin before database access", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool, { originValid: false });
  t.after(async () => app.close());
  const response = await app.inject({
    method: "POST",
    url: "/event-notification-campaigns/94900000-0000-4000-8000-000000000001/confirm",
    headers: { "idempotency-key": "confirm-campaign-0002" },
    payload: {},
  });
  assert.equal(response.statusCode, 403);
  assert.equal(mock.campaignConfirmCalls, 0);
});

test("organization SMTP configuration encrypts credentials before database persistence and is idempotent", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const payload = {
    host: "smtp.example.test",
    port: 587,
    transportSecurity: "starttls",
    authMode: "password",
    senderEmail: "events@example.test",
    senderName: "Eventor",
    credentials: {
      username: "mailer@example.test",
      password: "super-secret-smtp-password",
    },
  };
  const headers = { "idempotency-key": "smtp-config-version-0001" };
  const first = await app.inject({
    method: "POST",
    url: "/organization/delivery/email/configuration",
    headers,
    payload,
  });
  assert.equal(first.statusCode, 201);
  assert.equal(mock.deliveryConfigCalls, 1);
  const storedCiphertext = mock.commandCalls[0]?.values[3];
  assert.ok(Buffer.isBuffer(storedCiphertext));
  assert.equal((storedCiphertext as Buffer).subarray(0, 4).toString("ascii"), "EDC1");
  assert.equal((storedCiphertext as Buffer).includes(Buffer.from(payload.credentials.password)), false);
  assert.equal(JSON.stringify(mock.commandCalls[0]?.values).includes(payload.credentials.password), false);

  const replay = await app.inject({
    method: "POST",
    url: "/organization/delivery/email/configuration",
    headers,
    payload,
  });
  assert.equal(replay.statusCode, 201);
  assert.deepEqual(replay.json<Record<string, unknown>>(), first.json<Record<string, unknown>>());
  assert.equal(mock.deliveryConfigCalls, 1);
});

test("organization SMTP configuration projection never returns credentials", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const response = await app.inject({
    method: "GET",
    url: "/organization/delivery/email/configuration",
  });
  assert.equal(response.statusCode, 200);
  const data = response.json<{ data: Record<string, unknown> }>().data;
  assert.equal(data.credentialsConfigured, true);
  assert.equal("credentials" in data, false);
  assert.equal("password" in data, false);
});

test("SMTP test sends only to the requested address and idempotent replay does not resend", async (t) => {
  const mock = makePool();
  let verifyCalls = 0;
  let sendCalls = 0;
  let closeCalls = 0;
  const app = makeApi(mock.pool, {
    smtpTransportFactory: () => ({
      async verify() { verifyCalls += 1; return true; },
      async sendMail(message) {
        sendCalls += 1;
        assert.equal(message.to, "operator@example.test");
        return { messageId: "smtp-test-message", accepted: [message.to] };
      },
      close() { closeCalls += 1; },
    }),
  });
  t.after(async () => app.close());
  const headers = { "idempotency-key": "smtp-test-request-0001" };
  const first = await app.inject({
    method: "POST",
    url: "/organization/delivery/email/test",
    headers,
    payload: { recipient: "operator@example.test" },
  });
  assert.equal(first.statusCode, 200);
  assert.equal(first.json<{ data: { status: string; deliveryEnabled: boolean } }>().data.status, "succeeded");
  assert.equal(first.json<{ data: { deliveryEnabled: boolean } }>().data.deliveryEnabled, true);
  assert.equal(verifyCalls, 1);
  assert.equal(sendCalls, 1);
  assert.equal(closeCalls, 1);
  assert.equal(mock.deliveryTestCompletions, 1);

  const replay = await app.inject({
    method: "POST",
    url: "/organization/delivery/email/test",
    headers,
    payload: { recipient: "operator@example.test" },
  });
  assert.equal(replay.statusCode, 200);
  assert.equal(replay.json<{ data: { replayed: boolean } }>().data.replayed, true);
  assert.equal(sendCalls, 1);
  assert.equal(mock.deliveryTestCompletions, 1);
});

test("campaign queueing is an explicit idempotent command", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const headers = { "idempotency-key": "queue-campaign-0001" };
  const first = await app.inject({
    method: "POST",
    url: "/event-notification-campaigns/94900000-0000-4000-8000-000000000001/queue",
    headers,
    payload: {},
  });
  assert.equal(first.statusCode, 201);
  assert.equal(first.json<{ data: { status: string; smsSuppressedCount: number } }>().data.status, "queued");
  assert.equal(first.json<{ data: { smsSuppressedCount: number } }>().data.smsSuppressedCount, 1);
  assert.equal(mock.campaignQueueCalls, 1);
  const replay = await app.inject({
    method: "POST",
    url: "/event-notification-campaigns/94900000-0000-4000-8000-000000000001/queue",
    headers,
    payload: {},
  });
  assert.equal(replay.statusCode, 201);
  assert.equal(mock.campaignQueueCalls, 1);
});

test("queued notification campaign can be cancelled before delivery starts", async (t) => {
  const mock = makePool();
  const app = makeApi(mock.pool);
  t.after(async () => app.close());
  const headers = { "idempotency-key": "cancel-campaign-0001" };
  const first = await app.inject({
    method: "POST",
    url: "/event-notification-campaigns/94900000-0000-4000-8000-000000000001/cancel",
    headers,
    payload: {},
  });
  assert.equal(first.statusCode, 201);
  assert.equal(first.json<{ data: { status: string; suppressedAttempts: number } }>().data.status, "cancelled");
  assert.equal(first.json<{ data: { suppressedAttempts: number } }>().data.suppressedAttempts, 2);
  assert.equal(mock.campaignCancelCalls, 1);
  const replay = await app.inject({
    method: "POST",
    url: "/event-notification-campaigns/94900000-0000-4000-8000-000000000001/cancel",
    headers,
    payload: {},
  });
  assert.equal(replay.statusCode, 201);
  assert.equal(mock.campaignCancelCalls, 1);
});
