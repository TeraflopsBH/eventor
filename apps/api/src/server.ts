import Fastify, { type FastifyInstance, type FastifyReply, type FastifyRequest } from "fastify";
import { createCipheriv, createHash, createHmac, randomBytes } from "node:crypto";
import type { Pool, PoolClient, QueryResultRow } from "pg";
import { decryptDeliveryCredentials, encryptDeliveryCredentials } from "./delivery-credentials-crypto.js";
import { classifySmtpFailure, sendSmtpTestMessage, type SmtpSettings, type SmtpTransportFactory } from "./smtp-transport.js";
import type { paths } from "./generated/openapi.js";
import {
  clearStaffSessionCookies,
  STAFF_CSRF_COOKIE,
  STAFF_SESSION_COOKIE,
  SessionAuthError,
  type CreatedStaffSession,
  type StaffPrincipal,
} from "./session-auth.js";
export type { StaffPrincipal } from "./session-auth.js";

type JsonRequestBody<Path extends keyof paths, Method extends keyof paths[Path]> =
  paths[Path][Method] extends { requestBody: { content: { "application/json": infer Body } } }
    ? Body : never;
type SessionCreateBody = JsonRequestBody<"/auth/session", "post">;
type ReservationReleaseBody = JsonRequestBody<"/bookings/{bookingId}/reservations/release", "post">;
type EventChangeBody = JsonRequestBody<"/events/{eventId}/change-requests", "post">;
type EventChangeDecisionBody = JsonRequestBody<"/event-change-requests/{requestId}/approve", "post">;
type EventChangeExecutionBody = JsonRequestBody<"/event-change-requests/{requestId}/execute", "post">;
type EmailDeliveryConfigBody = JsonRequestBody<"/organization/delivery/email/configuration", "post">;
type EmailDeliveryTestBody = JsonRequestBody<"/organization/delivery/email/test", "post">;

export type StaffAuthenticator = (request: FastifyRequest) => Promise<StaffPrincipal | null>;
export type MutationOriginVerifier = (request: FastifyRequest, principal: StaffPrincipal) => Promise<boolean>;
export interface ApiDependencies {
  readonly pool: Pool;
  readonly authenticateStaff: StaffAuthenticator;
  readonly verifyMutationOrigin: MutationOriginVerifier;
  readonly verifyLoginOrigin?: (request: FastifyRequest) => boolean;
  readonly createStaffSession?: (
    request: FastifyRequest,
    body: SessionCreateBody,
  ) => Promise<CreatedStaffSession>;
  readonly revokeStaffSession?: (principal: StaffPrincipal) => Promise<void>;
  readonly getCurrentPrincipal?: (principal: StaffPrincipal) => Promise<Record<string, unknown>>;
  readonly privateFieldEncryptionKey?: Buffer;
  readonly deliveryCredentialsEncryptionKey?: Buffer;\n  readonly smtpTransportFactory?: SmtpTransportFactory;
  readonly trustedProxyAddresses?: readonly string[];
}

declare module "fastify" {
  interface FastifyRequest { staffPrincipal: StaffPrincipal | null; }
}

interface ApiProblem {
  readonly type: "about:blank";
  readonly title: string;
  readonly status: number;
  readonly code: string;
  readonly requestId: string;
}
class ApiError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) {
    super(message);
    this.name = "ApiError";
  }
}
interface IdempotencyRow extends QueryResultRow {
  request_sha256: string;
  response_status: number | null;
  response_body: Record<string, unknown> | null;
}
interface IdRow extends QueryResultRow { id: string; }
interface ResultRow extends QueryResultRow {
  result: unknown;
  released_count?: string | number;
}
interface CommandResponse {
  readonly status: number;
  readonly body: Record<string, unknown>;
}
type Command = (client: PoolClient) => Promise<Record<string, unknown>>;

const uuidPattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$";
const idempotencyHeaders = {
  type: "object", required: ["idempotency-key"],
  properties: { "idempotency-key": { type: "string", minLength: 8, maxLength: 200 } },
  additionalProperties: true,
} as const;
const eventParams = {
  type: "object", required: ["eventId"],
  properties: { eventId: { type: "string", pattern: uuidPattern } },
  additionalProperties: false,
} as const;
const requestParams = {
  type: "object", required: ["requestId"],
  properties: { requestId: { type: "string", pattern: uuidPattern } },
  additionalProperties: false,
} as const;
const campaignParams = {
  type: "object", required: ["campaignId"],
  properties: { campaignId: { type: "string", pattern: uuidPattern } },
  additionalProperties: false,
} as const;
const bookingParams = {
  type: "object", required: ["bookingId"],
  properties: { bookingId: { type: "string", pattern: uuidPattern } },
  additionalProperties: false,
} as const;
const emailDeliveryTestBody = {
  type: "object",
  required: ["recipient"],
  properties: { recipient: { type: "string", format: "email", maxLength: 320 } },
  additionalProperties: false,
} as const;
const emailDeliveryConfigBody = {
  type: "object",
  required: ["host", "port", "transportSecurity", "authMode", "senderEmail"],
  properties: {
    host: { type: "string", minLength: 1, maxLength: 253 },
    port: { type: "integer", minimum: 1, maximum: 65535 },
    transportSecurity: { type: "string", enum: ["starttls", "implicit_tls"] },
    authMode: { type: "string", enum: ["none", "password"] },
    senderEmail: { type: "string", format: "email", maxLength: 320 },
    senderName: { type: "string", maxLength: 200 },
    replyTo: { type: "string", format: "email", maxLength: 320 },
    connectionTimeoutMs: { type: "integer", minimum: 1000, maximum: 60000 },
    credentials: {
      type: "object",
      required: ["username", "password"],
      properties: {
        username: { type: "string", minLength: 1, maxLength: 320 },
        password: { type: "string", minLength: 1, maxLength: 4096 },
      },
      additionalProperties: false,
    },
    clearCredentials: { type: "boolean" },
  },
  additionalProperties: false,
} as const;
const reasonBody = {
  type: "object", required: ["reason"],
  properties: { reason: { type: "string", minLength: 3, maxLength: 2000 } },
  additionalProperties: false,
} as const;
const eventChangeBody = {
  type: "object",
  required: ["changeKind", "expectedEventRevision", "reasonCode"],
  properties: {
    changeKind: { type: "string", enum: ["cancel", "postpone", "reschedule"] },
    expectedEventRevision: { type: "integer", minimum: 1 },
    reasonCode: { type: "string", minLength: 2, maxLength: 100 },
    reasonInternal: { type: "string", maxLength: 4000 },
    publicMessage: { type: "string", maxLength: 4000 },
    replacementSchedule: {
      type: "object", required: ["startsAt", "endsAt", "timezone"],
      properties: {
        startsAt: { type: "string", format: "date-time" },
        endsAt: { type: "string", format: "date-time" },
        timezone: { type: "string", minLength: 1, maxLength: 100 },
        venueSummary: { type: "object", additionalProperties: true },
        materialChange: { type: "boolean" },
        reconfirmationPolicy: { type: "string", enum: ["none", "accepted_tentative", "all_active_invitees", "all_invited"] },
      },
      additionalProperties: false,
    },
  },
  additionalProperties: false,
} as const;
const eventExecutionBody = {
  type: "object", required: ["expectedEventRevision"],
  properties: {
    expectedEventRevision: { type: "integer", minimum: 1 },
    campaignAudience: { type: "string", enum: ["accepted_tentative", "all_active_invitees", "all_previously_invited", "custom"] },
    customParticipationIds: {
      type: "array", minItems: 1, uniqueItems: true,
      items: { type: "string", pattern: uuidPattern },
    },
    sendNotifications: { type: "boolean", default: true },
  },
  additionalProperties: false,
} as const;

function safeProblem(requestId: string, status: number, code: string, title: string): ApiProblem {
  return { type: "about:blank", title, status, code, requestId };
}
function stableJson(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return "[" + value.map((item) => stableJson(item)).join(",") + "]";
  const record = value as Record<string, unknown>;
  return "{" + Object.keys(record).sort().map((key) =>
    JSON.stringify(key) + ":" + stableJson(record[key])).join(",") + "}";
}
function requestHash(value: unknown, key?: Buffer): string {
  const canonical = stableJson(value);
  // Keyed hashing avoids a dictionary attack on low-entropy private reason text
  // stored only indirectly in the idempotency row.
  if (!key || key.length !== 32) return createHash("sha256").update(canonical).digest("hex");
  const idempotencyKey = createHmac("sha256", key)
    .update("eventor:idempotency-fingerprint:v1")
    .digest();
  return createHmac("sha256", idempotencyKey).update(canonical).digest("hex");
}
function encryptPrivateText(value: string, key: Buffer | undefined): Buffer {
  if (!key || key.length !== 32) {
    throw new ApiError(503, "PRIVATE_FIELD_ENCRYPTION_UNAVAILABLE", "Private event-reason encryption is not configured.");
  }
  const iv = randomBytes(12);
  const encryptionKey = createHmac("sha256", key)
    .update("eventor:private-reason-encryption:v1")
    .digest();
  const cipher = createCipheriv("aes-256-gcm", encryptionKey, iv);
  const encrypted = Buffer.concat([cipher.update(value, "utf8"), cipher.final()]);
  // Binary envelope: ASCII "EV1" + 12-byte nonce + 16-byte tag + ciphertext.
  return Buffer.concat([Buffer.from("EV1", "ascii"), iv, cipher.getAuthTag(), encrypted]);
}
function databaseError(error: unknown): ApiError {
  if (error instanceof ApiError) return error;
  const code = typeof error === "object" && error !== null && "code" in error
    ? String((error as { code?: unknown }).code ?? "") : "";
  switch (code) {
    case "42501": return new ApiError(403, "FORBIDDEN", "You are not permitted to perform this operation.");
    case "P0002": return new ApiError(404, "NOT_FOUND", "The requested resource was not found.");
    case "40001": return new ApiError(412, "STALE_REVISION", "The resource changed. Refresh it and try again.");
    case "22023":
    case "23514":
    case "23503": return new ApiError(422, "DOMAIN_VALIDATION_FAILED", "The request conflicts with domain validation rules.");
    case "23505":
    case "55000":
    case "23P01": return new ApiError(409, "STATE_CONFLICT", "The operation is not valid in the resource's current state.");
    case "08000":
    case "08003":
    case "08006": return new ApiError(503, "DATABASE_UNAVAILABLE", "The service is temporarily unavailable.");
    default: return new ApiError(500, "INTERNAL_ERROR", "An unexpected error occurred.");
  }
}
function parseStoredBody(value: Record<string, unknown> | string): Record<string, unknown> {
  return typeof value === "string" ? JSON.parse(value) as Record<string, unknown> : value;
}

async function runIdempotentCommand(
  dependencies: ApiDependencies,
  principal: StaffPrincipal,
  operationId: string,
  idempotencyKey: string,
  requestBody: unknown,
  command: Command,
): Promise<CommandResponse> {
  const client = await dependencies.pool.connect();
  const hash = requestHash(requestBody, dependencies.privateFieldEncryptionKey);
  try {
    await client.query("BEGIN");
    // The tenant comes only from the trusted session principal, never request data.
    await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
    await client.query(
      "DELETE FROM eogp.idempotency_records WHERE organization_id=$1 AND principal_kind='membership' AND principal_id=$2 AND operation_id=$3 AND idempotency_key=$4 AND expires_at<=clock_timestamp()",
      [principal.organizationId, principal.membershipId, operationId, idempotencyKey],
    );
    const existing = await client.query<IdempotencyRow>(
      "SELECT request_sha256,response_status,response_body FROM eogp.idempotency_records WHERE organization_id=$1 AND principal_kind='membership' AND principal_id=$2 AND operation_id=$3 AND idempotency_key=$4 FOR UPDATE",
      [principal.organizationId, principal.membershipId, operationId, idempotencyKey],
    );
    if (existing.rows.length > 0) {
      const row = existing.rows[0]!;
      if (row.request_sha256 !== hash) {
        throw new ApiError(409, "IDEMPOTENCY_KEY_REUSED", "This idempotency key was already used with a different request.");
      }
      if (row.response_status === null || row.response_body === null) {
        throw new ApiError(409, "REQUEST_IN_PROGRESS", "A request with this idempotency key is still being processed.");
      }
      await client.query("COMMIT");
      return { status: row.response_status, body: parseStoredBody(row.response_body) };
    }

    const inserted = await client.query<IdRow>(
      "INSERT INTO eogp.idempotency_records (organization_id,principal_kind,principal_id,operation_id,idempotency_key,request_sha256,expires_at) VALUES ($1,'membership',$2,$3,$4,$5,clock_timestamp()+interval '24 hours') ON CONFLICT (organization_id,principal_kind,principal_id,operation_id,idempotency_key) DO NOTHING RETURNING id",
      [principal.organizationId, principal.membershipId, operationId, idempotencyKey, hash],
    );
    if (inserted.rows.length === 0) {
      const concurrent = await client.query<IdempotencyRow>(
        "SELECT request_sha256,response_status,response_body FROM eogp.idempotency_records WHERE organization_id=$1 AND principal_kind='membership' AND principal_id=$2 AND operation_id=$3 AND idempotency_key=$4 FOR UPDATE",
        [principal.organizationId, principal.membershipId, operationId, idempotencyKey],
      );
      const row = concurrent.rows[0];
      if (!row || row.request_sha256 !== hash) {
        throw new ApiError(409, "IDEMPOTENCY_KEY_REUSED", "The idempotency key is already in use.");
      }
      if (row.response_status === null || row.response_body === null) {
        throw new ApiError(409, "REQUEST_IN_PROGRESS", "The request is still being processed.");
      }
      await client.query("COMMIT");
      return { status: row.response_status, body: parseStoredBody(row.response_body) };
    }

    const data = await command(client);
    const responseBody = { data };
    await client.query(
      "UPDATE eogp.idempotency_records SET response_status=201,response_body=$6::jsonb WHERE organization_id=$1 AND principal_kind='membership' AND principal_id=$2 AND operation_id=$3 AND idempotency_key=$4 AND request_sha256=$5",
      [principal.organizationId, principal.membershipId, operationId, idempotencyKey, hash, JSON.stringify(responseBody)],
    );
    await client.query("COMMIT");
    return { status: 201, body: responseBody };
  } catch (error) {
    try { await client.query("ROLLBACK"); } catch { /* preserve the command error */ }
    throw databaseError(error);
  } finally {
    client.release();
  }
}

function principalIsValid(principal: StaffPrincipal | null): principal is StaffPrincipal {
  return Boolean(principal &&
    new RegExp(uuidPattern).test(principal.userId) &&
    new RegExp(uuidPattern).test(principal.organizationId) &&
    new RegExp(uuidPattern).test(principal.membershipId));
}

export function buildApi(dependencies: ApiDependencies): FastifyInstance {
  const server = Fastify({
    logger: true,
    bodyLimit: 64 * 1024,
    trustProxy: dependencies.trustedProxyAddresses?.length
      ? [...dependencies.trustedProxyAddresses]
      : false,
  });
  server.decorateRequest("staffPrincipal", null);

  // Login is the only unauthenticated staff route and still requires an exact
  // allow-listed Origin. All other routes derive identity from the opaque DB
  // session cookie; state-changing requests additionally require CSRF validation.
  server.addHook("onRequest", async (request, reply) => {
    const pathname = request.url.split("?", 1)[0];
    if (request.method === "POST" && pathname === "/auth/session") {
      if (!dependencies.verifyLoginOrigin || !dependencies.verifyLoginOrigin(request)) {
        return reply.code(403).send(safeProblem(request.id, 403, "ORIGIN_REJECTED", "The request origin could not be verified."));
      }
      request.staffPrincipal = null;
      return;
    }

    const principal = await dependencies.authenticateStaff(request);
    if (!principalIsValid(principal)) {
      return reply.code(401).send(safeProblem(request.id, 401, "UNAUTHENTICATED", "Authentication is required."));
    }
    request.staffPrincipal = principal;

    if (["POST", "PUT", "PATCH", "DELETE"].includes(request.method)) {
      const validOrigin = await dependencies.verifyMutationOrigin(request, principal);
      if (!validOrigin) {
        return reply.code(403).send(safeProblem(request.id, 403, "CSRF_ORIGIN_REJECTED", "The request origin or CSRF token could not be verified."));
      }
    }
  });

  server.setErrorHandler((error, request, reply) => {
    if (error instanceof ApiError || error instanceof SessionAuthError) {
      return reply.code(error.status).send(safeProblem(request.id, error.status, error.code, error.message));
    }
    if (typeof error === "object" && error !== null && "validation" in error && Boolean((error as { validation?: unknown }).validation)) {
      return reply.code(400).send(safeProblem(request.id, 400, "INVALID_REQUEST", "The request does not match the API contract."));
    }
    request.log.error({ err: error }, "Unhandled API error");
    return reply.code(500).send(safeProblem(request.id, 500, "INTERNAL_ERROR", "An unexpected error occurred."));
  });

  const withCommand = async (
    request: FastifyRequest,
    reply: FastifyReply,
    operationId: string,
    body: unknown,
    command: Command,
  ) => {
    const principal = request.staffPrincipal;
    if (!principal) throw new ApiError(401, "UNAUTHENTICATED", "Authentication is required.");
    const key = request.headers["idempotency-key"];
    if (typeof key !== "string" || key.length < 8 || key.length > 200) {
      throw new ApiError(400, "IDEMPOTENCY_KEY_REQUIRED", "A valid Idempotency-Key header is required.");
    }
    const response = await runIdempotentCommand(dependencies, principal, operationId, key, body, command);
    return reply.code(response.status).send(response.body);
  };

  server.post<{ Body: SessionCreateBody }>(
    "/auth/session",
    {
      schema: {
        body: {
          type: "object",
          required: ["email", "password", "organizationSlug"],
          properties: {
            email: { type: "string", format: "email", maxLength: 320 },
            password: { type: "string", minLength: 12, maxLength: 1024 },
            organizationSlug: { type: "string", minLength: 2, maxLength: 80 },
          },
          additionalProperties: false,
        },
      },
    },
    async (request, reply) => {
      if (!dependencies.createStaffSession) {
        throw new ApiError(503, "AUTHENTICATION_NOT_CONFIGURED", "Staff authentication is not configured.");
      }
      const created = await dependencies.createStaffSession(request, request.body);
      const maxAge = Math.max(1, Math.floor((created.expiresAt.getTime() - Date.now()) / 1000));
      reply.header("set-cookie", [
        `${STAFF_SESSION_COOKIE}=${encodeURIComponent(created.sessionToken)}; Path=/; Max-Age=${maxAge}; Secure; HttpOnly; SameSite=Strict`,
        `${STAFF_CSRF_COOKIE}=${encodeURIComponent(created.csrfToken)}; Path=/; Max-Age=${maxAge}; Secure; SameSite=Strict`,
      ]);
      return reply.code(200).send({
        data: {
          userId: created.principal.userId,
          organizationId: created.principal.organizationId,
          membershipId: created.principal.membershipId,
          csrfToken: created.csrfToken,
          expiresAt: created.expiresAt.toISOString(),
        },
      });
    },
  );

  server.delete("/auth/session", async (request, reply) => {
    const principal = request.staffPrincipal!;
    if (!dependencies.revokeStaffSession) {
      throw new ApiError(503, "AUTHENTICATION_NOT_CONFIGURED", "Staff session revocation is not configured.");
    }
    await dependencies.revokeStaffSession(principal);
    reply.header("set-cookie", clearStaffSessionCookies());
    return reply.code(204).send();
  });

  server.get("/me", async (request, reply) => {
    const principal = request.staffPrincipal!;
    const data = dependencies.getCurrentPrincipal
      ? await dependencies.getCurrentPrincipal(principal)
      : {
          userId: principal.userId,
          organizationId: principal.organizationId,
          membershipId: principal.membershipId,
        };
    return reply.code(200).send({ data });
  });


  server.get<{ Params: { campaignId: string } }>(
    "/event-notification-campaigns/:campaignId/review",
    { schema: { params: campaignParams } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
        const result = await client.query<ResultRow>(
          "SELECT eogp.get_event_notification_campaign_review($1::uuid,$2::uuid,$3::uuid) AS result",
          [principal.organizationId, request.params.campaignId, principal.membershipId],
        );
        await client.query("COMMIT");
        return reply.code(200).send({ data: result.rows[0]?.result ?? null });
      } catch (error) {
        try { await client.query("ROLLBACK"); } catch { /* preserve the read error */ }
        throw databaseError(error);
      } finally {
        client.release();
      }
    },
  );

  server.post<{ Params: { campaignId: string }; Body: Record<string, never> }>(
    "/event-notification-campaigns/:campaignId/confirm",
    {
      schema: {
        params: campaignParams,
        headers: idempotencyHeaders,
        body: { type: "object", properties: {}, additionalProperties: false },
      },
    },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(request, reply, "confirmEventNotificationCampaign",
        { campaignId: request.params.campaignId }, async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.confirm_event_notification_campaign($1::uuid,$2::uuid,$3::uuid) AS result",
            [principal.organizationId, request.params.campaignId, principal.membershipId],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        });
    },
  );

  server.post<{ Params: { bookingId: string }; Body: ReservationReleaseBody }>(
    "/bookings/:bookingId/reservations/release",
    {
      schema: {
        params: bookingParams, headers: idempotencyHeaders,
        body: {
          type: "object", required: ["reservationIds", "reason"],
          properties: {
            reservationIds: { type: "array", minItems: 1, uniqueItems: true, items: { type: "string", pattern: uuidPattern } },
            reason: { type: "string", minLength: 3, maxLength: 1000 },
          },
          additionalProperties: false,
        },
      },
    },
    async (request, reply) => {
      const body = request.body;
      const principal = request.staffPrincipal!;
      return withCommand(request, reply, "releaseBookingReservations", { bookingId: request.params.bookingId, body }, async (client) => {
        const result = await client.query<ResultRow>(
          "SELECT eogp.release_booking_reservations($1::uuid,$2::uuid,$3::uuid[],$4::uuid,$5::text) AS released_count",
          [principal.organizationId, request.params.bookingId, body.reservationIds, principal.membershipId, body.reason],
        );
        return {
          bookingId: request.params.bookingId,
          releasedCount: Number(result.rows[0]?.released_count ?? 0),
          reservationIds: body.reservationIds,
        };
      });
    },
  );

  server.post<{ Params: { eventId: string }; Body: EventChangeBody }>(
    "/events/:eventId/change-requests",
    { schema: { params: eventParams, headers: idempotencyHeaders, body: eventChangeBody } },
    async (request, reply) => {
      const body = request.body;
      if ((body.changeKind === "postpone" || body.changeKind === "reschedule") && !body.replacementSchedule) {
        throw new ApiError(422, "REPLACEMENT_SCHEDULE_REQUIRED", "A postponement or reschedule requires a replacement schedule.");
      }
      if (body.changeKind !== "postpone" && body.changeKind !== "reschedule" && body.replacementSchedule) {
        throw new ApiError(422, "UNEXPECTED_REPLACEMENT_SCHEDULE", "A replacement schedule is accepted only for postponement or rescheduling.");
      }
      const encryptedReason = body.reasonInternal
        ? encryptPrivateText(body.reasonInternal, dependencies.privateFieldEncryptionKey) : null;
      const principal = request.staffPrincipal!;
      return withCommand(request, reply, "createEventChangeRequest", { eventId: request.params.eventId, body }, async (client) => {
        const result = await client.query<ResultRow>(
          "SELECT eogp.submit_event_change_request($1::uuid,$2::uuid,$3::uuid,$4::text,$5::integer,$6::text,$7::bytea,$8::text,$9::jsonb) AS result",
          [
            principal.organizationId, request.params.eventId, principal.membershipId,
            body.changeKind, body.expectedEventRevision, body.reasonCode, encryptedReason,
            body.publicMessage ?? null, body.replacementSchedule ? JSON.stringify(body.replacementSchedule) : null,
          ],
        );
        return result.rows[0]?.result as Record<string, unknown>;
      });
    },
  );

  server.post<{ Params: { requestId: string }; Body: EventChangeDecisionBody }>(
    "/event-change-requests/:requestId/approve",
    { schema: { params: requestParams, headers: idempotencyHeaders, body: reasonBody } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(request, reply, "approveEventChangeRequest", { requestId: request.params.requestId, body: request.body }, async (client) => {
        const result = await client.query<ResultRow>(
          "SELECT eogp.decide_event_change_request($1::uuid,$2::uuid,$3::uuid,'approved',$4::text) AS result",
          [principal.organizationId, request.params.requestId, principal.membershipId, request.body.reason],
        );
        return result.rows[0]?.result as Record<string, unknown>;
      });
    },
  );

  server.post<{ Params: { requestId: string }; Body: EventChangeDecisionBody }>(
    "/event-change-requests/:requestId/reject",
    { schema: { params: requestParams, headers: idempotencyHeaders, body: reasonBody } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(request, reply, "rejectEventChangeRequest", { requestId: request.params.requestId, body: request.body }, async (client) => {
        const result = await client.query<ResultRow>(
          "SELECT eogp.decide_event_change_request($1::uuid,$2::uuid,$3::uuid,'rejected',$4::text) AS result",
          [principal.organizationId, request.params.requestId, principal.membershipId, request.body.reason],
        );
        return result.rows[0]?.result as Record<string, unknown>;
      });
    },
  );

  server.post<{ Params: { requestId: string }; Body: EventChangeExecutionBody }>(
    "/event-change-requests/:requestId/execute",
    { schema: { params: requestParams, headers: idempotencyHeaders, body: eventExecutionBody } },
    async (request, reply) => {
      const body = request.body;
      const audience = body.campaignAudience;
      const customIds = body.customParticipationIds ?? [];
      if (audience === "custom" && customIds.length === 0) {
        throw new ApiError(422, "CUSTOM_AUDIENCE_REQUIRED", "Select at least one participant for a custom audience.");
      }
      if (audience !== "custom" && customIds.length > 0) {
        throw new ApiError(422, "CUSTOM_AUDIENCE_NOT_ALLOWED", "Participant IDs require the custom audience kind.");
      }
      const principal = request.staffPrincipal!;
      return withCommand(request, reply, "executeEventChangeRequest", { requestId: request.params.requestId, body }, async (client) => {
        const result = await client.query<ResultRow>(
          "SELECT eogp.execute_event_change_request($1::uuid,$2::uuid,$3::uuid,$4::integer,$5::text,$6::boolean,$7::uuid[]) AS result",
          [
            principal.organizationId, request.params.requestId, principal.membershipId,
            body.expectedEventRevision, audience ?? null, body.sendNotifications ?? true, customIds,
          ],
        );
        return result.rows[0]?.result as Record<string, unknown>;
      });
    },
  );


  server.post<{ Body: EmailDeliveryTestBody }>(
    "/organization/delivery/email/test",
    { schema: { headers: idempotencyHeaders, body: emailDeliveryTestBody } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const key = request.headers["idempotency-key"];
      if (typeof key !== "string" || key.length < 8 || key.length > 200) {
        throw new ApiError(400, "IDEMPOTENCY_KEY_REQUIRED", "A valid Idempotency-Key header is required.");
      }
      const idempotencyHash = createHash("sha256").update(key, "utf8").digest("hex");
      const recipientHash = createHash("sha256")
        .update(request.body.recipient.trim().toLowerCase(), "utf8").digest("hex");

      const beginClient = await dependencies.pool.connect();
      let begin: Record<string, unknown>;
      try {
        await beginClient.query("BEGIN");
        await beginClient.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
        const result = await beginClient.query<ResultRow>(
          "SELECT eogp.begin_organization_email_delivery_test($1::uuid,$2::uuid,$3::text,$4::text) AS result",
          [principal.organizationId, principal.membershipId, idempotencyHash, recipientHash],
        );
        begin = result.rows[0]?.result as Record<string, unknown>;
        await beginClient.query("COMMIT");
      } catch (error) {
        try { await beginClient.query("ROLLBACK"); } catch { /* preserve original error */ }
        throw databaseError(error);
      } finally {
        beginClient.release();
      }

      if (begin.created !== true) {
        const status = begin.status === "succeeded" ? 200 : begin.status === "failed" ? 502 : 202;
        return reply.code(status).send({
          data: {
            requestId: begin.requestId,
            status: begin.status,
            deliveryEnabled: false,
            replayed: true,
          },
        });
      }

      const encryptionKey = dependencies.deliveryCredentialsEncryptionKey;
      if (!encryptionKey || encryptionKey.length !== 32) {
        throw new ApiError(503, "DELIVERY_CREDENTIAL_ENCRYPTION_UNAVAILABLE", "Delivery credential encryption is not configured.");
      }

      let succeeded = false;
      let failureCode = "SMTP_UNKNOWN";
      let messageId: string | null = null;
      try {
        const settings = begin.settings as SmtpSettings;
        const encoded = begin.credentialsCiphertextBase64;
        const credentials = typeof encoded === "string"
          ? decryptDeliveryCredentials(Buffer.from(encoded, "base64"), encryptionKey, {
              organizationId: principal.organizationId,
              channel: "email",
            })
          : null;
        const sent = await sendSmtpTestMessage(
          settings,
          credentials,
          request.body.recipient.trim(),
          dependencies.smtpTransportFactory,
        );
        succeeded = true;
        messageId = sent.messageId;
      } catch (error) {
        failureCode = classifySmtpFailure(error).code;
        request.log.warn({ failureCode }, "Organization SMTP test failed");
      }

      const finishClient = await dependencies.pool.connect();
      let finish: Record<string, unknown>;
      try {
        await finishClient.query("BEGIN");
        await finishClient.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
        const result = await finishClient.query<ResultRow>(
          "SELECT eogp.complete_organization_email_delivery_test($1::uuid,$2::uuid,$3::uuid,$4::boolean,$5::text) AS result",
          [principal.organizationId, principal.membershipId, begin.requestId, succeeded, succeeded ? null : failureCode],
        );
        finish = result.rows[0]?.result as Record<string, unknown>;
        await finishClient.query("COMMIT");
      } catch (error) {
        try { await finishClient.query("ROLLBACK"); } catch { /* preserve original error */ }
        throw databaseError(error);
      } finally {
        finishClient.release();
      }

      if (!succeeded) {
        return reply.code(502).send({
          data: { requestId: begin.requestId, status: "failed", failureCode, deliveryEnabled: false },
        });
      }
      return reply.code(200).send({
        data: { ...finish, messageId, testRecipient: request.body.recipient.trim() },
      });
    },
  );

  server.post<{ Params: { campaignId: string }; Body: Record<string, never> }>(
    "/event-notification-campaigns/:campaignId/queue",
    {
      schema: {
        params: campaignParams,
        headers: idempotencyHeaders,
        body: { type: "object", properties: {}, additionalProperties: false },
      },
    },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(request, reply, "queueEventNotificationCampaign",
        { campaignId: request.params.campaignId }, async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.queue_event_notification_campaign($1::uuid,$2::uuid,$3::uuid) AS result",
            [principal.organizationId, request.params.campaignId, principal.membershipId],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        });
    },
  );

  server.get("/organization/delivery/email/configuration", async (request, reply) => {
    const principal = request.staffPrincipal!;
    const client = await dependencies.pool.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
      const result = await client.query<ResultRow>(
        "SELECT eogp.get_organization_email_delivery_config($1::uuid,$2::uuid) AS result",
        [principal.organizationId, principal.membershipId],
      );
      await client.query("COMMIT");
      return reply.code(200).send({ data: result.rows[0]?.result ?? null });
    } catch (error) {
      try { await client.query("ROLLBACK"); } catch { /* preserve the query error */ }
      throw databaseError(error);
    } finally {
      client.release();
    }
  });

  server.post<{ Body: EmailDeliveryConfigBody }>(
    "/organization/delivery/email/configuration",
    { schema: { headers: idempotencyHeaders, body: emailDeliveryConfigBody } },
    async (request, reply) => {
      const body = request.body;
      if (body.credentials && body.authMode !== "password") {
        throw new ApiError(422, "SMTP_CREDENTIALS_NOT_ALLOWED", "Credentials can be supplied only with password authentication.");
      }
      if (body.clearCredentials && body.credentials) {
        throw new ApiError(422, "SMTP_CREDENTIALS_CONFLICT", "Credentials cannot be replaced and cleared together.");
      }
      let encryptedCredentials: Buffer | null = null;
      if (body.credentials) {
        const key = dependencies.deliveryCredentialsEncryptionKey;
        if (!key || key.length !== 32) {
          throw new ApiError(503, "DELIVERY_CREDENTIAL_ENCRYPTION_UNAVAILABLE", "Delivery credential encryption is not configured.");
        }
        encryptedCredentials = encryptDeliveryCredentials(
          body.credentials,
          key,
          { organizationId: request.staffPrincipal!.organizationId, channel: "email" },
        );
      }
      const clearCredentials = body.clearCredentials ?? body.authMode === "none";
      const principal = request.staffPrincipal!;
      return withCommand(
        request,
        reply,
        "configureOrganizationEmailDelivery",
        body,
        async (client) => {
          const settings = {
            host: body.host,
            port: body.port,
            transportSecurity: body.transportSecurity,
            authMode: body.authMode,
            senderEmail: body.senderEmail,
            senderName: body.senderName ?? "",
            replyTo: body.replyTo ?? "",
            connectionTimeoutMs: body.connectionTimeoutMs ?? 15000,
          };
          const result = await client.query<ResultRow>(
            "SELECT eogp.set_organization_email_delivery_config($1::uuid,$2::uuid,$3::jsonb,$4::bytea,$5::boolean,$6::boolean) AS result",
            [
              principal.organizationId,
              principal.membershipId,
              JSON.stringify(settings),
              encryptedCredentials,
              Boolean(body.credentials),
              clearCredentials,
            ],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        },
      );
    },
  );

  return server;
}
