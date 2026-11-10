import Fastify, { type FastifyInstance, type FastifyReply, type FastifyRequest } from "fastify";
import { createCipheriv, createHash, createHmac, randomBytes } from "node:crypto";
import type { Pool, PoolClient, QueryResultRow } from "pg";
import type { paths } from "./generated/openapi.js";

type JsonRequestBody<Path extends keyof paths, Method extends keyof paths[Path]> =
  paths[Path][Method] extends { requestBody: { content: { "application/json": infer Body } } }
    ? Body : never;
type ReservationReleaseBody = JsonRequestBody<"/bookings/{bookingId}/reservations/release", "post">;
type EventChangeBody = JsonRequestBody<"/events/{eventId}/change-requests", "post">;
type EventChangeDecisionBody = JsonRequestBody<"/event-change-requests/{requestId}/approve", "post">;
type EventChangeExecutionBody = JsonRequestBody<"/event-change-requests/{requestId}/execute", "post">;

export interface StaffPrincipal {
  readonly userId: string;
  readonly organizationId: string;
  readonly membershipId: string;
}
export type StaffAuthenticator = (request: FastifyRequest) => Promise<StaffPrincipal | null>;
export type MutationOriginVerifier = (request: FastifyRequest, principal: StaffPrincipal) => Promise<boolean>;
export interface ApiDependencies {
  readonly pool: Pool;
  readonly authenticateStaff: StaffAuthenticator;
  readonly verifyMutationOrigin: MutationOriginVerifier;
  readonly privateFieldEncryptionKey?: Buffer;
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
const bookingParams = {
  type: "object", required: ["bookingId"],
  properties: { bookingId: { type: "string", pattern: uuidPattern } },
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
  const server = Fastify({ logger: false, bodyLimit: 64 * 1024 });
  server.decorateRequest("staffPrincipal", null);

  // The host must provide verification of its signed staff session and CSRF/
  // origin policy. This module intentionally does not trust identity headers.
  server.addHook("onRequest", async (request, reply) => {
    const principal = await dependencies.authenticateStaff(request);
    if (!principalIsValid(principal)) {
      return reply.code(401).send(safeProblem(request.id, 401, "UNAUTHENTICATED", "Authentication is required."));
    }
    request.staffPrincipal = principal;
    const validOrigin = await dependencies.verifyMutationOrigin(request, principal);
    if (!validOrigin) {
      return reply.code(403).send(safeProblem(request.id, 403, "CSRF_ORIGIN_REJECTED", "The request origin could not be verified."));
    }
  });

  server.setErrorHandler((error, request, reply) => {
    if (error instanceof ApiError) {
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

  return server;
}
