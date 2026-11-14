import Fastify, { type FastifyInstance, type FastifyReply, type FastifyRequest } from "fastify";
import { createCipheriv, createHash, createHmac, randomBytes, randomUUID } from "node:crypto";
import type { Pool, PoolClient, QueryResultRow } from "pg";
import { decryptDeliveryCredentialBundle, decryptDeliveryCredentials, encryptDeliveryCredentialBundle, encryptDeliveryCredentials } from "./delivery-credentials-crypto.js";
import { decryptContactValue, encryptContactValue } from "./contact-crypto.js";
import { PublicFormAnswersError, PublicFormSchemaError, validatePublicFormAnswers, validatePublicFormSchema } from "./public-form-validation.js";
import { verifyResendWebhookSignature } from "./resend-webhook.js";
import { hashGuestInvitationToken } from "./guest-invitation-capability.js";
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
type LocalePreferenceBody = { locale: "bs-BA" | "en" | null };
type OrganizationLocaleBody = { defaultLocale: "bs-BA" | "en" };
type ReservationReleaseBody = JsonRequestBody<"/bookings/{bookingId}/reservations/release", "post">;
type EventChangeBody = JsonRequestBody<"/events/{eventId}/change-requests", "post">;
type EventChangeDecisionBody = JsonRequestBody<"/event-change-requests/{requestId}/approve", "post">;
type EventChangeExecutionBody = JsonRequestBody<"/event-change-requests/{requestId}/execute", "post">;
type EmailDeliveryConfigBody = JsonRequestBody<"/organization/delivery/email/configuration", "post">;
type EmailDeliveryTestBody = JsonRequestBody<"/organization/delivery/email/test", "post">;
type BookingOfferCreateBody = {
  priceListRevisionId: string;
  cancellationPolicyRevisionId: string;
  approvalPolicyRevisionId: string;
  currency: string;
  taxBasis: "inclusive" | "exclusive" | "not_applicable" | "to_be_confirmed";
  validUntil: string;
  lineItems: Array<{ itemCode: string; quantity: number }>;
  adjustments?: Array<{ code: string; label: string; kind: "fee" | "discount" | "credit"; amount: number }>;
  taxAmount: number;
  internalReason?: string;
};
type BookingOfferSuccessorBody = BookingOfferCreateBody & { draftRevisionId: string; supersedeCurrentOffer?: boolean };
type BookingOfferAcceptanceBody = {
  acceptanceName?: string;
  acceptanceNote?: string;
};
type BookingOfferEmailBody = { acceptanceToken: string };
type BookingOfferRejectionBody = {
  reasonCode: string;
  reason: string;
  note?: string;
};
type BookingConfirmationBody = {
  expectedDraftRevisionId: string;
  confirmationReason: string;
};

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
  readonly updateUserLocale?: (principal: StaffPrincipal, locale: "bs-BA" | "en" | null) => Promise<void>;
  readonly privateFieldEncryptionKey?: Buffer;
  readonly contactEncryptionKey?: Buffer;
  readonly bookingCapabilityKey?: Buffer;
  readonly publicInquiryFingerprintKey?: Buffer;
  readonly deliveryCredentialsEncryptionKey?: Buffer;
  readonly publicApiBaseUrl?: string;
  readonly smtpTransportFactory?: SmtpTransportFactory;
  readonly trustedProxyAddresses?: readonly string[];
}

declare module "fastify" {
  interface FastifyRequest { staffPrincipal: StaffPrincipal | null; rawJsonBody: string | null; }
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

interface PublicBookingInquiryBody {
  readonly formCode: string;
  readonly formRevisionId: string;
  readonly customerLocale?: "bs-BA" | "en";
  readonly requester: {
    readonly displayName: string;
    readonly email?: string;
    readonly phone?: string;
  };
  readonly requested: {
    readonly startAt?: string;
    readonly endAt?: string;
    readonly timezone?: string;
    readonly spaceCodes?: readonly string[];
  };
  readonly answers: Record<string, unknown>;
  readonly attachmentReferences?: readonly string[];
}

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
const publicBookingFormParams = {
  type: "object",
  required: ["organizationSlug", "formCode"],
  properties: {
    organizationSlug: { type: "string", minLength: 2, maxLength: 80, pattern: "^[A-Za-z0-9][A-Za-z0-9-]*$" },
    formCode: { type: "string", minLength: 2, maxLength: 80, pattern: "^[A-Za-z0-9][A-Za-z0-9_-]*$" },
  },
  additionalProperties: false,
} as const;
const publicBookingInquiryParams = {
  type: "object",
  required: ["organizationSlug"],
  properties: {
    organizationSlug: { type: "string", minLength: 2, maxLength: 80, pattern: "^[A-Za-z0-9][A-Za-z0-9-]*$" },
  },
  additionalProperties: false,
} as const;
const publicBookingInquiryHeaders = {
  type: "object",
  required: ["idempotency-key"],
  properties: {
    "idempotency-key": { type: "string", minLength: 8, maxLength: 200 },
  },
  additionalProperties: true,
} as const;
const localePreferenceBody = { type: "object", required: ["locale"], properties: { locale: { type: ["string","null"], enum: ["bs-BA","en",null] } }, additionalProperties: false } as const;
const organizationLocaleBody = { type: "object", required: ["defaultLocale"], properties: { defaultLocale: { type: "string", enum: ["bs-BA","en"] } }, additionalProperties: false } as const;
const publicBookingInquiryBody = {
  type: "object",
  required: ["formCode", "formRevisionId", "requester", "requested", "answers"],
  properties: {
    formCode: { type: "string", minLength: 2, maxLength: 80, pattern: "^[A-Za-z0-9][A-Za-z0-9_-]*$" },
    formRevisionId: { type: "string", pattern: uuidPattern },
    customerLocale: { type: "string", enum: ["bs-BA", "en"] },
    requester: {
      type: "object",
      required: ["displayName"],
      properties: {
        displayName: { type: "string", minLength: 1, maxLength: 250 },
        email: { type: "string", format: "email", maxLength: 320 },
        phone: { type: "string", maxLength: 50 },
      },
      additionalProperties: false,
    },
    requested: {
      type: "object",
      properties: {
        startAt: { type: "string", format: "date-time" },
        endAt: { type: "string", format: "date-time" },
        timezone: { type: "string", minLength: 1, maxLength: 80 },
        spaceCodes: {
          type: "array",
          maxItems: 50,
          items: { type: "string", minLength: 1, maxLength: 80 },
        },
      },
      additionalProperties: false,
    },
    answers: { type: "object", maxProperties: 100, additionalProperties: true },
    attachmentReferences: {
      type: "array",
      maxItems: 20,
      items: { type: "string", minLength: 1, maxLength: 200 },
    },
  },
  additionalProperties: false,
} as const;
const campaignListQuery = {
  type: "object",
  properties: {
    status: { type: "string", enum: ["draft", "previewed", "confirmed", "queued", "sending", "completed", "partial", "failed", "cancelled"] },
    limit: { type: "integer", minimum: 1, maximum: 100, default: 25 },
    offset: { type: "integer", minimum: 0, maximum: 10000, default: 0 },
  },
  additionalProperties: false,
} as const;
const inquiryParams = {
  type: "object",
  required: ["inquiryId"],
  properties: { inquiryId: { type: "string", pattern: uuidPattern } },
  additionalProperties: false,
} as const;
const bookingOfferParams = {
  type: "object", required: ["offerId"],
  properties: { offerId: { type: "string", pattern: uuidPattern } },
  additionalProperties: false,
} as const;
const bookingOfferRevisionParams = {
  type: "object", required: ["revisionId"],
  properties: { revisionId: { type: "string", pattern: uuidPattern } },
  additionalProperties: false,
} as const;
const bookingApprovalPolicyParams = {
  type: "object", required: ["policyId"],
  properties: { policyId: { type: "string", pattern: uuidPattern } },
  additionalProperties: false,
} as const;
const bookingApprovalPolicyRevisionParams = {
  type: "object", required: ["policyId", "revisionId"],
  properties: {
    policyId: { type: "string", pattern: uuidPattern },
    revisionId: { type: "string", pattern: uuidPattern },
  },
  additionalProperties: false,
} as const;
const bookingCancellationPolicyParams = {
  type: "object", required: ["policyId"],
  properties: { policyId: { type: "string", pattern: uuidPattern } },
  additionalProperties: false,
} as const;
const bookingCancellationPolicyRevisionParams = {
  type: "object", required: ["policyId", "revisionId"],
  properties: {
    policyId: { type: "string", pattern: uuidPattern },
    revisionId: { type: "string", pattern: uuidPattern },
  },
  additionalProperties: false,
} as const;
const bookingFormParams = {
  type: "object", required: ["formId"],
  properties: { formId: { type: "string", pattern: uuidPattern } },
  additionalProperties: false,
} as const;
const bookingFormRevisionParams = {
  type: "object", required: ["formId", "revisionId"],
  properties: {
    formId: { type: "string", pattern: uuidPattern },
    revisionId: { type: "string", pattern: uuidPattern },
  },
  additionalProperties: false,
} as const;
const bookingFormCreateBody = {
  type: "object", required: ["code", "name", "locale", "fieldSchema"],
  properties: {
    code: { type: "string", minLength: 2, maxLength: 80, pattern: "^[A-Za-z0-9][A-Za-z0-9_-]*$" },
    name: { type: "string", minLength: 1, maxLength: 250 },
    locale: { type: "string", enum: ["bs-BA", "en"] },
    fieldSchema: { type: "object", maxProperties: 10, additionalProperties: true },
  },
  additionalProperties: false,
} as const;
const bookingFormDraftBody = {
  type: "object", required: ["locale", "fieldSchema"],
  properties: {
    locale: { type: "string", enum: ["bs-BA", "en"] },
    fieldSchema: { type: "object", maxProperties: 10, additionalProperties: true },
  },
  additionalProperties: false,
} as const;
const bookingPriceListParams = {
  type: "object", required: ["priceListId"],
  properties: { priceListId: { type: "string", pattern: uuidPattern } },
  additionalProperties: false,
} as const;
const bookingPriceListRevisionParams = {
  type: "object", required: ["priceListId", "revisionId"],
  properties: {
    priceListId: { type: "string", pattern: uuidPattern },
    revisionId: { type: "string", pattern: uuidPattern },
  },
  additionalProperties: false,
} as const;
const bookingTaxProfileParams = {
  type: "object", required: ["taxProfileId"],
  properties: { taxProfileId: { type: "string", pattern: uuidPattern } },
  additionalProperties: false,
} as const;
const bookingTaxProfileRevisionParams = {
  type: "object", required: ["taxProfileId", "revisionId"],
  properties: {
    taxProfileId: { type: "string", pattern: uuidPattern },
    revisionId: { type: "string", pattern: uuidPattern },
  },
  additionalProperties: false,
} as const;
const bookingTaxProfileCreateBody = {
  type: "object", required: ["code", "name", "currency", "taxBasis"],
  properties: {
    code: { type: "string", minLength: 2, maxLength: 80, pattern: "^[A-Za-z0-9][A-Za-z0-9._-]*$" },
    name: { type: "string", minLength: 1, maxLength: 250 },
    jurisdictionCode: { type: ["string", "null"], maxLength: 100 },
    registrationIdentifier: { type: ["string", "null"], maxLength: 120 },
    currency: { type: "string", pattern: "^[A-Z]{3}$" },
    taxBasis: { type: "string", enum: ["inclusive", "exclusive", "not_applicable"] },
  },
  additionalProperties: false,
} as const;
const bookingTaxProfileRevisionBody = {
  type: "object",
  required: ["jurisdictionCode", "registrationIdentifier", "currency", "taxBasis", "roundingMethod", "roundingScale", "effectiveFrom", "effectiveUntil", "taxCodes"],
  properties: {
    jurisdictionCode: { type: ["string", "null"], maxLength: 100 },
    registrationIdentifier: { type: ["string", "null"], maxLength: 120 },
    currency: { type: "string", pattern: "^[A-Z]{3}$" },
    taxBasis: { type: "string", enum: ["inclusive", "exclusive", "not_applicable"] },
    roundingMethod: { type: "string", enum: ["per_line", "per_tax_code", "invoice_total"] },
    roundingScale: { type: "integer", minimum: 0, maximum: 4 },
    effectiveFrom: { type: ["string", "null"], format: "date-time" },
    effectiveUntil: { type: ["string", "null"], format: "date-time" },
    taxCodes: {
      type: "array", maxItems: 200,
      items: {
        type: "object", required: ["taxCode", "label", "treatment", "rate"],
        properties: {
          taxCode: { type: "string", minLength: 1, maxLength: 80, pattern: "^[A-Za-z0-9][A-Za-z0-9._-]*$" },
          label: { type: "string", minLength: 1, maxLength: 200 },
          treatment: { type: "string", enum: ["percentage", "zero_rated", "exempt", "out_of_scope", "manual"] },
          rate: { type: ["number", "null"], minimum: 0, maximum: 100 },
        },
        additionalProperties: false,
      },
    },
  },
  additionalProperties: false,
} as const;
const bookingTaxProfileRevisionCreateBody = {
  ...bookingTaxProfileRevisionBody,
  required: ["jurisdictionCode", "registrationIdentifier", "currency", "taxBasis", "roundingMethod", "roundingScale", "effectiveFrom", "effectiveUntil"],
} as const;
const bookingPriceListTaxProfileBody = {
  type: "object", required: ["taxProfileRevisionId"],
  properties: { taxProfileRevisionId: { type: ["string", "null"], pattern: uuidPattern } },
  additionalProperties: false,
} as const;
const bookingCancellationPolicyCreateBody = {
  type: "object", required: ["code", "name"],
  properties: {
    code: { type: "string", minLength: 2, maxLength: 80, pattern: "^[A-Za-z0-9][A-Za-z0-9._-]*$" },
    name: { type: "string", minLength: 1, maxLength: 250 },
  },
  additionalProperties: false,
} as const;
const bookingCancellationPolicyRevisionBody = {
  type: "object",
  required: ["customerMode", "publicTerms", "approvalRules", "commercialRules", "noticeRules"],
  properties: {
    customerMode: { type: "string", enum: ["request_only", "approval_required", "self_service"] },
    publicTerms: { type: "string", minLength: 1, maxLength: 10000 },
    approvalRules: { type: "object", maxProperties: 100, additionalProperties: true },
    commercialRules: { type: "object", maxProperties: 100, additionalProperties: true },
    noticeRules: { type: "object", maxProperties: 100, additionalProperties: true },
  },
  additionalProperties: false,
} as const;
const bookingPriceListCreateBody = {
  type: "object", required: ["code", "name", "currency", "taxBasis"],
  properties: {
    code: { type: "string", minLength: 2, maxLength: 80, pattern: "^[A-Za-z0-9][A-Za-z0-9._-]*$" },
    name: { type: "string", minLength: 1, maxLength: 250 },
    scopeKind: { type: "string", enum: ["organization", "venue", "space"], default: "organization" },
    scopeVenueId: { type: ["string", "null"], pattern: uuidPattern },
    scopeSpaceId: { type: ["string", "null"], pattern: uuidPattern },
    currency: { type: "string", pattern: "^[A-Z]{3}$" },
    taxBasis: { type: "string", enum: ["inclusive", "exclusive", "not_applicable", "to_be_confirmed"] },
  },
  additionalProperties: false,
} as const;
const bookingPriceListRevisionBody = {
  type: "object", required: ["currency", "taxBasis"],
  properties: {
    currency: { type: "string", pattern: "^[A-Z]{3}$" },
    taxBasis: { type: "string", enum: ["inclusive", "exclusive", "not_applicable", "to_be_confirmed"] },
    effectiveFrom: { type: ["string", "null"], format: "date-time" },
    effectiveUntil: { type: ["string", "null"], format: "date-time" },
  },
  additionalProperties: false,
} as const;
const bookingPriceListDraftBody = {
  type: "object", required: ["currency", "taxBasis", "items"],
  properties: {
    currency: { type: "string", pattern: "^[A-Z]{3}$" },
    taxBasis: { type: "string", enum: ["inclusive", "exclusive", "not_applicable", "to_be_confirmed"] },
    effectiveFrom: { type: ["string", "null"], format: "date-time" },
    effectiveUntil: { type: ["string", "null"], format: "date-time" },
    items: {
      type: "array", maxItems: 500,
      items: {
        type: "object", required: ["itemCode", "label", "unit", "unitAmount"],
        properties: {
          itemCode: { type: "string", minLength: 1, maxLength: 100, pattern: "^[A-Za-z0-9][A-Za-z0-9._-]*$" },
          label: { type: "string", minLength: 1, maxLength: 250 },
          unit: { type: "string", minLength: 1, maxLength: 40 },
          unitAmount: { type: "number", minimum: 0 },
          taxCode: { type: ["string", "null"], maxLength: 80 },
          quantityMin: { type: "number", minimum: 0, default: 1 },
          quantityMax: { type: ["number", "null"], minimum: 0 },
        },
        additionalProperties: false,
      },
    },
  },
  additionalProperties: false,
} as const;
const bookingApprovalPolicyCreateBody = {
  type: "object",
  required: ["code", "name"],
  properties: {
    code: { type: "string", minLength: 2, maxLength: 80 },
    name: { type: "string", minLength: 1, maxLength: 250 },
  },
  additionalProperties: false,
} as const;
const bookingApprovalPolicyRevisionBody = {
  type: "object",
  required: ["rules"],
  properties: {
    rules: {
      type: "array",
      maxItems: 50,
      items: {
        type: "object",
        required: ["code", "condition", "requiredApprovals", "permission", "separationOfDuties"],
        properties: {
          code: { type: "string", minLength: 1, maxLength: 100 },
          condition: {
            type: "object",
            required: ["kind"],
            properties: {
              kind: { type: "string", enum: ["always", "total_at_least", "discount_at_least", "adjustment_present"] },
              amount: { type: "number", exclusiveMinimum: 0 },
              currency: { type: "string", pattern: "^[A-Z]{3}$" },
              adjustmentKind: { type: "string", enum: ["fee", "discount", "credit"] },
            },
            additionalProperties: false,
          },
          requiredApprovals: { type: "integer", minimum: 1, maximum: 10 },
          permission: { type: "string", const: "booking.approve" },
          separationOfDuties: { type: "boolean" },
        },
        additionalProperties: false,
      },
    },
  },
  additionalProperties: false,
} as const;
const bookingOfferCreateBody = {
  type: "object",
  required: ["priceListRevisionId", "cancellationPolicyRevisionId", "approvalPolicyRevisionId", "currency", "taxBasis", "validUntil", "lineItems", "taxAmount"],
  properties: {
    priceListRevisionId: { type: "string", pattern: uuidPattern },
    cancellationPolicyRevisionId: { type: "string", pattern: uuidPattern },
    approvalPolicyRevisionId: { type: "string", pattern: uuidPattern },
    currency: { type: "string", pattern: "^[A-Z]{3}$" },
    taxBasis: { type: "string", enum: ["inclusive", "exclusive", "not_applicable", "to_be_confirmed"] },
    validUntil: { type: "string", format: "date-time" },
    lineItems: { type: "array", maxItems: 100, items: {
      type: "object", required: ["itemCode", "quantity"],
      properties: { itemCode: { type: "string", minLength: 1, maxLength: 100 }, quantity: { type: "number", exclusiveMinimum: 0, maximum: 999999999.999 } },
      additionalProperties: false,
    } },
    adjustments: { type: "array", maxItems: 50, items: {
      type: "object", required: ["code", "label", "kind", "amount"],
      properties: {
        code: { type: "string", minLength: 1, maxLength: 80 },
        label: { type: "string", minLength: 1, maxLength: 250 },
        kind: { type: "string", enum: ["fee", "discount", "credit"] },
        amount: { type: "number", exclusiveMinimum: 0, maximum: 999999999999.99 },
      },
      additionalProperties: false,
    } },
    taxAmount: { type: "number", minimum: 0, maximum: 999999999999.99 },
    internalReason: { type: "string", minLength: 3, maxLength: 2000 },
  },
  additionalProperties: false,
} as const;
const bookingOfferSuccessorBody = {
  type: "object",
  required: ["draftRevisionId", "priceListRevisionId", "cancellationPolicyRevisionId", "approvalPolicyRevisionId", "currency", "taxBasis", "validUntil", "lineItems", "taxAmount"],
  properties: {
    draftRevisionId: { type: "string", pattern: uuidPattern },
    priceListRevisionId: { type: "string", pattern: uuidPattern },
    cancellationPolicyRevisionId: { type: "string", pattern: uuidPattern },
    approvalPolicyRevisionId: { type: "string", pattern: uuidPattern },
    currency: { type: "string", pattern: "^[A-Z]{3}$" },
    taxBasis: { type: "string", enum: ["inclusive", "exclusive", "not_applicable", "to_be_confirmed"] },
    validUntil: { type: "string", format: "date-time" },
    lineItems: { type: "array", maxItems: 100, items: {
      type: "object", required: ["itemCode", "quantity"],
      properties: { itemCode: { type: "string", minLength: 1, maxLength: 100 }, quantity: { type: "number", exclusiveMinimum: 0, maximum: 999999999.999 } },
      additionalProperties: false,
    } },
    adjustments: { type: "array", maxItems: 50, items: {
      type: "object", required: ["code", "label", "kind", "amount"],
      properties: { code: { type: "string", minLength: 1, maxLength: 80 }, label: { type: "string", minLength: 1, maxLength: 250 }, kind: { type: "string", enum: ["fee", "discount", "credit"] }, amount: { type: "number", exclusiveMinimum: 0, maximum: 999999999999.99 } },
      additionalProperties: false,
    } },
    taxAmount: { type: "number", minimum: 0, maximum: 999999999999.99 },
    internalReason: { type: "string", minLength: 3, maxLength: 2000 },
    supersedeCurrentOffer: { type: "boolean", default: false },
  },
  additionalProperties: false,
} as const;
const bookingOfferIssueBody = { type: "object", properties: {}, additionalProperties: false } as const;
const bookingOfferEmailBody = {
  type: "object",
  required: ["acceptanceToken"],
  properties: { acceptanceToken: { type: "string", pattern: "^[A-Za-z0-9_-]{43}$" } },
  additionalProperties: false,
} as const;
const bookingOfferEmailDeliveryQuery = {
  type: "object",
  properties: {
    status: { type: "string", enum: ["queued","sending","sent","failed","uncertain"] },
    limit: { type: "integer", minimum: 1, maximum: 100, default: 25 },
    offset: { type: "integer", minimum: 0, maximum: 10000, default: 0 },
  },
  additionalProperties: false,
} as const;
const bookingOfferEmailReconciliationBody = {
  type: "object",
  required: ["resolution","reason"],
  properties: {
    resolution: { type: "string", enum: ["confirmed_sent","confirmed_not_sent"] },
    reason: { type: "string", minLength: 3, maxLength: 1000 },
    providerMessageReference: { type: "string", maxLength: 998 },
  },
  additionalProperties: false,
} as const;
const bookingOfferEmailRetryBody = {
  type: "object",
  required: ["reason"],
  properties: { reason: { type: "string", minLength: 3, maxLength: 1000 } },
  additionalProperties: false,
} as const;
const bookingConfirmationBody = {
  type: "object",
  required: ["expectedDraftRevisionId", "confirmationReason"],
  properties: {
    expectedDraftRevisionId: { type: "string", pattern: uuidPattern },
    confirmationReason: { type: "string", minLength: 3, maxLength: 2000 },
  },
  additionalProperties: false,
} as const;
const bookingOfferApprovalBody = {
  type: "object",
  required: ["offerRevisionId", "ruleCode", "decision", "reason"],
  properties: {
    offerRevisionId: { type: "string", pattern: uuidPattern },
    ruleCode: { type: "string", minLength: 1, maxLength: 100 },
    decision: { type: "string", enum: ["approved", "rejected", "returned_for_changes"] },
    reason: { type: "string", minLength: 3, maxLength: 2000 },
  },
  additionalProperties: false,
} as const;

const publicOfferViewParams = {
  type: "object", required: ["offerId"],
  properties: { offerId: { type: "string", pattern: uuidPattern } },
  additionalProperties: false,
} as const;
const publicOfferCapabilityHeaders = {
  type: "object",
  required: ["x-external-booking-token"],
  properties: {
    "x-external-booking-token": { type: "string", pattern: "^[A-Za-z0-9_-]{43}$" },
  },
  additionalProperties: true,
} as const;
const guestInvitationCapabilityHeaders = {
  type: "object",
  required: ["x-guest-invitation-token"],
  properties: {
    "x-guest-invitation-token": { type: "string", pattern: "^[A-Za-z0-9_-]{43}$" },
  },
  additionalProperties: true,
} as const;
const guestInvitationResolveHeaders = {
  type: "object",
  required: ["idempotency-key", "x-guest-invitation-token"],
  properties: {
    "idempotency-key": { type: "string", minLength: 8, maxLength: 200 },
    "x-guest-invitation-token": { type: "string", pattern: "^[A-Za-z0-9_-]{43}$" },
  },
  additionalProperties: true,
} as const;
const guestInvitationResolveBody = {
  type: "object",
  properties: { clientContext: { type: "string", maxLength: 200 } },
  additionalProperties: false,
} as const;
const guestRsvpBody = {
  type: "object",
  required: ["response"],
  properties: {
    response: { type: "string", enum: ["accepted", "declined", "tentative"] },
    note: { type: "string", maxLength: 1000 },
  },
  additionalProperties: false,
} as const;
const guestRsvpHeaders = {
  type: "object",
  required: ["idempotency-key", "x-guest-invitation-token"],
  properties: {
    "idempotency-key": { type: "string", minLength: 8, maxLength: 200 },
    "x-guest-invitation-token": { type: "string", pattern: "^[A-Za-z0-9_-]{43}$" },
  },
  additionalProperties: true,
} as const;

const publicOfferDecisionParams = {
  type: "object", required: ["offerId"],
  properties: { offerId: { type: "string", pattern: uuidPattern } },
  additionalProperties: false,
} as const;
const publicOfferDecisionHeaders = {
  type: "object", required: ["idempotency-key", "x-external-booking-token"],
  properties: {
    "idempotency-key": { type: "string", minLength: 8, maxLength: 200 },
    "x-external-booking-token": { type: "string", pattern: "^[A-Za-z0-9_-]{43}$" },
  },
  additionalProperties: true,
} as const;
const bookingOfferAcceptanceBody = {
  type: "object",
  properties: {
    acceptanceName: { type: "string", minLength: 1, maxLength: 250 },
    acceptanceNote: { type: "string", maxLength: 1000 },
  },
  additionalProperties: false,
} as const;
const bookingOfferRejectionBody = {
  type: "object",
  required: ["reasonCode", "reason"],
  properties: {
    reasonCode: { type: "string", minLength: 2, maxLength: 100 },
    reason: { type: "string", minLength: 3, maxLength: 2000 },
    note: { type: "string", maxLength: 1000 },
  },
  additionalProperties: false,
} as const;
const bookingDraftParams = {
  type: "object",
  required: ["draftId"],
  properties: { draftId: { type: "string", pattern: uuidPattern } },
  additionalProperties: false,
} as const;
const organizationInquiryParams = {
  type: "object",
  required: ["organizationId"],
  properties: { organizationId: { type: "string", pattern: uuidPattern } },
  additionalProperties: false,
} as const;
const inquiryListQuery = {
  type: "object",
  properties: {
    status: { type: "string", enum: ["received", "under_review", "converted", "declined", "withdrawn", "spam"] },
    assignedToMembershipId: { type: "string", pattern: uuidPattern },
    limit: { type: "integer", minimum: 1, maximum: 100, default: 25 },
    offset: { type: "integer", minimum: 0, maximum: 10000, default: 0 },
  },
  additionalProperties: false,
} as const;
const inquiryAssignmentBody = {
  type: "object",
  required: ["assignedToMembershipId"],
  properties: {
    assignedToMembershipId: { type: ["string", "null"], pattern: uuidPattern },
  },
  additionalProperties: false,
} as const;
const inquiryStatusBody = {
  type: "object",
  required: ["status", "reason"],
  properties: {
    status: { type: "string", enum: ["received", "under_review", "declined", "spam"] },
    reason: { type: "string", minLength: 3, maxLength: 1000 },
  },
  additionalProperties: false,
} as const;
const inquiryAnnotationBody = {
  type: "object",
  required: ["annotation"],
  properties: { annotation: { type: "string", minLength: 1, maxLength: 4000 } },
  additionalProperties: false,
} as const;
const bookingDraftAllocationAvailabilityPreviewBody = {
  type: "object",
  required: ["spaceLines", "resourceLines", "resourceStartsAt", "resourceEndsAt"],
  properties: {
    spaceLines: {
      type: "array", maxItems: 50,
      items: {
        type: "object",
        required: ["venueSpaceId", "startsAt", "endsAt", "blockKind"],
        properties: {
          venueSpaceId: { type: "string", pattern: uuidPattern },
          startsAt: { type: "string", format: "date-time" },
          endsAt: { type: "string", format: "date-time" },
          blockKind: { type: "string", enum: ["setup", "rehearsal", "event_use", "teardown", "buffer"] },
          requestedCapacity: { type: "integer", minimum: 1 },
        },
        additionalProperties: true,
      },
    },
    resourceLines: {
      type: "array", maxItems: 100,
      items: {
        type: "object",
        required: ["resourceTypeId", "requestedQuantity"],
        properties: {
          resourceTypeId: { type: "string", pattern: uuidPattern },
          requestedQuantity: { type: "number", exclusiveMinimum: 0, maximum: 999999999.999 },
        },
        additionalProperties: true,
      },
    },
    resourceStartsAt: { type: ["string", "null"], format: "date-time" },
    resourceEndsAt: { type: ["string", "null"], format: "date-time" },
  },
  additionalProperties: false,
} as const;

const bookingDraftRevisionBody = {
  type: "object",
  required: [
    "expectedRevisionNumber", "values", "requestedStart", "requestedEnd",
    "timezone", "spaceLines", "resourceLines", "changeReason",
  ],
  properties: {
    expectedRevisionNumber: { type: "integer", minimum: 0 },
    values: { type: "object", maxProperties: 100, additionalProperties: true },
    requestedStart: { type: ["string", "null"], format: "date-time" },
    requestedEnd: { type: ["string", "null"], format: "date-time" },
    timezone: { type: "string", minLength: 1, maxLength: 80 },
    spaceLines: {
      type: "array", maxItems: 50,
      items: {
        type: "object",
        required: ["venueSpaceId", "startsAt", "endsAt", "blockKind"],
        properties: {
          venueSpaceId: { type: "string", pattern: uuidPattern },
          startsAt: { type: "string", format: "date-time" },
          endsAt: { type: "string", format: "date-time" },
          blockKind: { type: "string", enum: ["setup", "rehearsal", "event_use", "teardown", "buffer"] },
          requestedCapacity: { type: "integer", minimum: 0 },
        },
        additionalProperties: false,
      },
    },
    resourceLines: {
      type: "array", maxItems: 100,
      items: {
        type: "object",
        required: ["resourceTypeId", "requestedQuantity"],
        properties: {
          resourceTypeId: { type: "string", pattern: uuidPattern },
          requestedQuantity: { type: "number", exclusiveMinimum: 0, maximum: 999999999.999 },
          values: { type: "object", maxProperties: 100, additionalProperties: true },
        },
        additionalProperties: false,
      },
    },
    changeReason: { type: "string", minLength: 3, maxLength: 2000 },
  },
  additionalProperties: false,
} as const;

const campaignDeliveryQuery = {
  type: "object",
  properties: {
    status: { type: "string", enum: ["queued", "sending", "sent", "delivered", "failed", "bounced", "uncertain", "suppressed"] },
    limit: { type: "integer", minimum: 1, maximum: 100, default: 50 },
    offset: { type: "integer", minimum: 0, maximum: 10000, default: 0 },
  },
  additionalProperties: false,
} as const;
const resendWebhookActivateBody = {
  type: "object",
  required: ["endpointId", "signingSecret"],
  properties: {
    endpointId: { type: "string", pattern: uuidPattern },
    signingSecret: { type: "string", minLength: 24, maxLength: 512, pattern: "^whsec_[A-Za-z0-9+/]+={0,2}$" },
  },
  additionalProperties: false,
} as const;
const resendWebhookParams = {
  type: "object",
  required: ["endpointId"],
  properties: { endpointId: { type: "string", pattern: uuidPattern } },
  additionalProperties: false,
} as const;
const deliveryReconciliationBody = {
  type: "object",
  required: ["resolution", "reason"],
  properties: {
    resolution: { type: "string", enum: ["confirmed_sent", "confirmed_not_sent", "confirmed_delivered", "confirmed_bounced"] },
    reason: { type: "string", minLength: 3, maxLength: 1000 },
  },
  additionalProperties: false,
} as const;
const deliveryRetryBody = {
  type: "object",
  required: ["reason"],
  properties: { reason: { type: "string", minLength: 3, maxLength: 1000 } },
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
function publicInquiryFingerprint(key: Buffer | undefined, purpose: string, value: string): string {
  if (!key || key.length !== 32) {
    throw new ApiError(503, "PUBLIC_INQUIRY_SECURITY_NOT_CONFIGURED", "Public inquiry protection is not configured.");
  }
  return createHmac("sha256", key)
    .update(`eventor:public-booking-inquiry:${purpose}:v1\x00`, "utf8")
    .update(value, "utf8")
    .digest("hex");
}

function assertBoundedAnswerValues(value: unknown): void {
  let nodes = 0;
  const visit = (current: unknown, depth: number): void => {
    nodes += 1;
    if (nodes > 3000 || depth > 8) {
      throw new ApiError(422, "PUBLIC_FORM_ANSWERS_TOO_COMPLEX", "The submitted form answers are too complex.");
    }
    if (typeof current === "string") {
      if (current.length > 5000) {
        throw new ApiError(422, "PUBLIC_FORM_ANSWER_TOO_LONG", "A submitted form answer is too long.");
      }
      return;
    }
    if (Array.isArray(current)) {
      if (current.length > 250) {
        throw new ApiError(422, "PUBLIC_FORM_ANSWER_TOO_LARGE", "A submitted form answer contains too many items.");
      }
      for (const item of current) visit(item, depth + 1);
      return;
    }
    if (current !== null && typeof current === "object") {
      const entries = Object.entries(current as Record<string, unknown>);
      if (entries.length > 100) {
        throw new ApiError(422, "PUBLIC_FORM_ANSWER_TOO_LARGE", "A submitted form answer contains too many properties.");
      }
      for (const [key, item] of entries) {
        if (key.length > 100 || ["__proto__", "prototype", "constructor"].includes(key)) {
          throw new ApiError(422, "PUBLIC_FORM_ANSWER_KEY_INVALID", "A submitted form answer contains an unsupported field name.");
        }
        visit(item, depth + 1);
      }
    }
  };
  visit(value, 0);
  if (Buffer.byteLength(JSON.stringify(value), "utf8") > 32 * 1024) {
    throw new ApiError(413, "PUBLIC_FORM_ANSWERS_TOO_LARGE", "The submitted form answers exceed the allowed size.");
  }
}
function decryptInquiryCiphertext(
  value: unknown,
  key: Buffer | undefined,
  organizationId: string,
  contactKind: "email" | "phone" | "other",
): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value !== "string" || !key || key.length !== 32) {
    throw new ApiError(503, "INQUIRY_CONTACT_DECRYPTION_UNAVAILABLE", "Inquiry contact decryption is not configured.");
  }
  try {
    return decryptContactValue(Buffer.from(value, "base64"), key, { organizationId, contactKind });
  } catch {
    throw new ApiError(500, "INQUIRY_CONTACT_DECRYPTION_FAILED", "Stored inquiry contact data could not be decrypted.");
  }
}
function decryptInquiryListItem(value: unknown, key: Buffer | undefined, organizationId: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(500, "INQUIRY_PROJECTION_INVALID", "The inquiry projection is invalid.");
  }
  const record = value as Record<string, unknown>;
  const { requesterNameCiphertextBase64, ...safe } = record;
  return {
    ...safe,
    requesterName: decryptInquiryCiphertext(requesterNameCiphertextBase64, key, organizationId, "other"),
  };
}
function decryptInquiryDetail(value: unknown, key: Buffer | undefined, organizationId: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(500, "INQUIRY_PROJECTION_INVALID", "The inquiry projection is invalid.");
  }
  const record = value as Record<string, unknown>;
  const {
    requesterNameCiphertextBase64,
    requesterEmailCiphertextBase64,
    requesterPhoneCiphertextBase64,
    submittedValuesCiphertextBase64,
    ...safe
  } = record;
  const encryptedSubmission = decryptInquiryCiphertext(submittedValuesCiphertextBase64, key, organizationId, "other");
  let submittedValues: unknown;
  try {
    submittedValues = encryptedSubmission === null ? null : JSON.parse(encryptedSubmission);
  } catch {
    throw new ApiError(500, "INQUIRY_SUBMISSION_DECRYPTION_FAILED", "Stored inquiry answers could not be decoded.");
  }
  return {
    ...safe,
    requesterName: decryptInquiryCiphertext(requesterNameCiphertextBase64, key, organizationId, "other"),
    requesterEmail: decryptInquiryCiphertext(requesterEmailCiphertextBase64, key, organizationId, "email"),
    requesterPhone: decryptInquiryCiphertext(requesterPhoneCiphertextBase64, key, organizationId, "phone"),
    submittedValues,
  };
}

function decryptBookingDraftProjection(
  value: unknown,
  key: Buffer | undefined,
  organizationId: string,
): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(500, "BOOKING_DRAFT_PROJECTION_INVALID", "The booking draft projection is invalid.");
  }
  const record = value as Record<string, unknown>;
  const currentRevision = record.currentRevision;
  if (currentRevision === null || currentRevision === undefined) {
    return { ...record, currentRevision: null };
  }
  if (typeof currentRevision !== "object" || Array.isArray(currentRevision)) {
    throw new ApiError(500, "BOOKING_DRAFT_PROJECTION_INVALID", "The current booking draft revision is invalid.");
  }
  const revision = currentRevision as Record<string, unknown>;
  const snapshot = revision.valuesSnapshot;
  if (!snapshot || typeof snapshot !== "object" || Array.isArray(snapshot)) {
    throw new ApiError(500, "BOOKING_DRAFT_SNAPSHOT_INVALID", "The booking draft snapshot is invalid.");
  }
  const envelope = snapshot as Record<string, unknown>;
  if (envelope.schemaVersion !== 1 || envelope.encryption !== "ECP1" ||
      envelope.contactKind !== "other" || typeof envelope.ciphertextBase64 !== "string") {
    throw new ApiError(500, "BOOKING_DRAFT_SNAPSHOT_UNSUPPORTED", "The booking draft snapshot format is unsupported.");
  }
  const encryptedValues = decryptInquiryCiphertext(
    envelope.ciphertextBase64, key, organizationId, "other",
  );
  let values: unknown;
  try {
    values = encryptedValues === null ? null : JSON.parse(encryptedValues);
  } catch {
    throw new ApiError(500, "BOOKING_DRAFT_SNAPSHOT_INVALID", "The encrypted booking draft values could not be decoded.");
  }
  if (!values || typeof values !== "object" || Array.isArray(values)) {
    throw new ApiError(500, "BOOKING_DRAFT_SNAPSHOT_INVALID", "The decrypted booking draft values are not an object.");
  }
  const { valuesSnapshot: _valuesSnapshot, ...safeRevision } = revision;
  return {
    ...record,
    currentRevision: {
      ...safeRevision,
      values,
    },
  };
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
  if (error instanceof PublicFormAnswersError) {
    return new ApiError(422, "PUBLIC_FORM_ANSWERS_INVALID", "Submitted answers do not match the published booking form.");
  }
  if (error instanceof PublicFormSchemaError) {
    return new ApiError(500, "PUBLIC_FORM_SCHEMA_INVALID", "The published booking form schema is invalid.");
  }
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
    await client.query("SELECT set_config('app.actor_membership_id',$1,true)", [principal.membershipId]);
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
    logger: { redact: ["req.headers.x-external-booking-token", "req.headers.x-guest-invitation-token"] },
    bodyLimit: 64 * 1024,
    trustProxy: dependencies.trustedProxyAddresses?.length
      ? [...dependencies.trustedProxyAddresses]
      : false,
  });
  server.decorateRequest("staffPrincipal", null);
  server.decorateRequest("rawJsonBody", null);
  server.removeContentTypeParser("application/json");
  server.addContentTypeParser("application/json", { parseAs: "string" }, (request, body, done) => {
    const rawBody = typeof body === "string" ? body : body.toString("utf8");
    request.rawJsonBody = rawBody;
    try {
      done(null, JSON.parse(rawBody) as unknown);
    } catch (error) {
      done(error as Error);
    }
  });

  // Login is the only unauthenticated staff route and still requires an exact
  // allow-listed Origin. All other routes derive identity from the opaque DB
  // session cookie; state-changing requests additionally require CSRF validation.
  server.addHook("onRequest", async (request, reply) => {
    const pathname = request.url.split("?", 1)[0] ?? request.url;
    const publicBookingFormRead = request.method === "GET" &&
      /^\/public\/organizations\/[^/]+\/booking-forms\/[^/]+$/.test(pathname);
    const publicBookingInquiryWrite = request.method === "POST" &&
      /^\/public\/organizations\/[^/]+\/booking-inquiries$/.test(pathname);
    const publicOfferDecision = request.method === "POST" &&
      /^\/booking-offers\/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}\/(accept|reject)$/.test(pathname);
    const publicOfferView = request.method === "GET" &&
      /^\/public\/booking-offers\/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-8][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$/.test(pathname);
    if (publicBookingFormRead || publicBookingInquiryWrite || publicOfferDecision || publicOfferView) {
      // Public intake and purpose-bound offer decisions authenticate through their own capability.
      request.staffPrincipal = null;
      return;
    }
    if (request.method === "POST" &&
        pathname.startsWith("/webhooks/resend/") &&
        /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89abAB][0-9a-f]{3}-[0-9a-f]{12}$/i.test(pathname.slice("/webhooks/resend/".length))) {
      // Provider callbacks authenticate with a signed Svix payload, not a staff session.
      return;
    }
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

  server.get<{
    Params: { organizationSlug: string; formCode: string };
  }>(
    "/public/organizations/:organizationSlug/booking-forms/:formCode",
    { schema: { params: publicBookingFormParams } },
    async (request, reply) => {
      const client = await dependencies.pool.connect();
      try {
        const result = await client.query<ResultRow>(
          "SELECT eogp.get_published_public_booking_form($1::text,$2::text) AS result",
          [request.params.organizationSlug, request.params.formCode],
        );
        const data = result.rows[0]?.result;
        if (!data || typeof data !== "object" || Array.isArray(data)) {
          return reply.code(404).send(
            safeProblem(request.id, 404, "PUBLIC_BOOKING_FORM_NOT_FOUND", "The requested booking form is not available."),
          );
        }
        return reply
          .header("cache-control", "public, max-age=60")
          .code(200)
          .send({ data });
      } catch (error) {
        throw databaseError(error);
      } finally {
        client.release();
      }
    },
  );

  server.post<{
    Params: { organizationSlug: string };
    Body: PublicBookingInquiryBody;
  }>(
    "/public/organizations/:organizationSlug/booking-inquiries",
    {
      bodyLimit: 64 * 1024,
      schema: {
        params: publicBookingInquiryParams,
        headers: publicBookingInquiryHeaders,
        body: publicBookingInquiryBody,
      },
    },
    async (request, reply) => {
      const idempotencyKey = request.headers["idempotency-key"];
      if (typeof idempotencyKey !== "string" || idempotencyKey.length < 8 || idempotencyKey.length > 200) {
        throw new ApiError(400, "IDEMPOTENCY_KEY_REQUIRED", "A valid Idempotency-Key header is required.");
      }
      const contactKey = dependencies.contactEncryptionKey;
      const fingerprintKey = dependencies.publicInquiryFingerprintKey;
      if (!contactKey || contactKey.length !== 32 || !fingerprintKey || fingerprintKey.length !== 32) {
        throw new ApiError(503, "PUBLIC_INQUIRY_SECURITY_NOT_CONFIGURED", "Public inquiry protection is not configured.");
      }

      const body = request.body;
      assertBoundedAnswerValues(body.answers);
      if (body.attachmentReferences && body.attachmentReferences.length > 0) {
        throw new ApiError(422, "PUBLIC_INQUIRY_ATTACHMENTS_UNAVAILABLE", "Attachments are not supported by this public form yet.");
      }

      const requesterName = body.requester.displayName.trim();
      if (!requesterName) {
        throw new ApiError(400, "REQUESTER_NAME_REQUIRED", "A requester name is required.");
      }
      const requesterEmail = body.requester.email?.trim() || null;
      const requesterPhone = body.requester.phone?.trim() || null;
      const requestedStart = body.requested.startAt ? new Date(body.requested.startAt) : null;
      const requestedEnd = body.requested.endAt ? new Date(body.requested.endAt) : null;
      if ((requestedStart && Number.isNaN(requestedStart.getTime())) ||
          (requestedEnd && Number.isNaN(requestedEnd.getTime())) ||
          (requestedStart && requestedEnd && requestedEnd <= requestedStart)) {
        throw new ApiError(422, "REQUESTED_TIME_INVALID", "The requested end must be later than the requested start.");
      }

      const client = await dependencies.pool.connect();
      try {
        const formResult = await client.query<ResultRow>(
          "SELECT eogp.get_public_booking_form_revision($1::text,$2::text,$3::uuid) AS result",
          [request.params.organizationSlug, body.formCode, body.formRevisionId],
        );
        const form = formResult.rows[0]?.result;
        if (!form || typeof form !== "object" || Array.isArray(form)) {
          const latestFormResult = await client.query<ResultRow>(
            "SELECT eogp.get_published_public_booking_form($1::text,$2::text) AS result",
            [request.params.organizationSlug, body.formCode],
          );
          const latestForm = latestFormResult.rows[0]?.result;
          if (latestForm && typeof latestForm === "object" && !Array.isArray(latestForm)) {
            return reply.code(409).send(
              safeProblem(request.id, 409, "PUBLIC_FORM_REVISION_UNAVAILABLE", "The published form changed or is no longer available. Reload it and try again."),
            );
          }
          return reply.code(404).send(
            safeProblem(request.id, 404, "PUBLIC_BOOKING_FORM_NOT_FOUND", "The requested booking form is not available."),
          );
        }
        const formProjection = form as Record<string, unknown>;
        const organizationId = formProjection.organizationId;
        const defaultTimezone = formProjection.defaultTimezone;
        if (typeof organizationId !== "string" || typeof defaultTimezone !== "string" ||
            typeof formProjection.formRevisionId !== "string" ||
            formProjection.formRevisionId.toLowerCase() !== body.formRevisionId.toLowerCase()) {
          throw new ApiError(500, "PUBLIC_BOOKING_FORM_INVALID", "The published booking form could not be loaded.");
        }
        validatePublicFormAnswers(formProjection.fieldSchema, body.answers);

        const submittedValues = {
          requested: {
            startAt: requestedStart?.toISOString() ?? null,
            endAt: requestedEnd?.toISOString() ?? null,
            timezone: body.requested.timezone?.trim() || defaultTimezone,
            spaceCodes: body.requested.spaceCodes ?? [],
          },
          answers: body.answers,
        };
        const submittedValuesCiphertext = encryptContactValue(
          JSON.stringify(submittedValues),
          contactKey,
          { organizationId, contactKind: "other" },
        );
        const requesterNameCiphertext = encryptContactValue(
          requesterName,
          contactKey,
          { organizationId, contactKind: "other" },
        );
        const emailHash = requesterEmail
          ? publicInquiryFingerprint(contactKey, "requester-email", requesterEmail.toLowerCase())
          : null;
        const emailCiphertext = requesterEmail
          ? encryptContactValue(requesterEmail, contactKey, { organizationId, contactKind: "email" })
          : null;
        const phoneHash = requesterPhone
          ? publicInquiryFingerprint(contactKey, "requester-phone", requesterPhone)
          : null;
        const phoneCiphertext = requesterPhone
          ? encryptContactValue(requesterPhone, contactKey, { organizationId, contactKind: "phone" })
          : null;
        const sourceFingerprint = publicInquiryFingerprint(
          fingerprintKey,
          "source",
          request.ip || request.socket.remoteAddress || "unknown",
        );
        const keyFingerprint = publicInquiryFingerprint(fingerprintKey, "idempotency-key", idempotencyKey);
        const payloadFingerprint = publicInquiryFingerprint(
          fingerprintKey,
          "request",
          stableJson({ organizationSlug: request.params.organizationSlug, body }),
        );
        const submitted = await client.query<ResultRow>(
          "SELECT eogp.submit_public_booking_inquiry_with_locale($1::text,$2::text,$3::uuid,$4::text,$5::text,$6::text,$7::bytea,$8::bytea,$9::text,$10::bytea,$11::text,$12::bytea,$13::timestamptz,$14::timestamptz,$15::text,$16::text) AS result",
          [
            request.params.organizationSlug,
            body.formCode,
            body.formRevisionId,
            sourceFingerprint,
            keyFingerprint,
            payloadFingerprint,
            submittedValuesCiphertext,
            requesterNameCiphertext,
            emailHash,
            emailCiphertext,
            phoneHash,
            phoneCiphertext,
            requestedStart,
            requestedEnd,
            submittedValues.requested.timezone,
            body.customerLocale ?? null,
          ],
        );
        const result = submitted.rows[0]?.result;
        if (!result || typeof result !== "object" || Array.isArray(result)) {
          throw new ApiError(500, "PUBLIC_INQUIRY_SUBMISSION_FAILED", "The inquiry could not be submitted.");
        }
        const outcome = result as Record<string, unknown>;
        if (outcome.rateLimited === true) {
          const retryAfter = Math.max(1, Math.min(3600, Number(outcome.retryAfterSeconds) || 3600));
          return reply
            .header("cache-control", "no-store")
            .header("retry-after", String(retryAfter))
            .code(429)
            .send(safeProblem(request.id, 429, "PUBLIC_INQUIRY_RATE_LIMITED", "Too many inquiries were submitted. Please try again later."));
        }
        if (outcome.idempotencyConflict === true) {
          return reply.code(409).send(
            safeProblem(request.id, 409, "IDEMPOTENCY_KEY_REUSED", "This idempotency key was already used with a different request."),
          );
        }
        if (outcome.formUnavailable === true) {
          return reply.code(409).send(
            safeProblem(request.id, 409, "PUBLIC_FORM_REVISION_UNAVAILABLE", "The published form changed or is no longer available. Reload it and try again."),
          );
        }
        if (typeof outcome.inquiryId !== "string" || typeof outcome.publicReference !== "string") {
          throw new ApiError(500, "PUBLIC_INQUIRY_SUBMISSION_FAILED", "The inquiry could not be submitted.");
        }
        return reply
          .header("cache-control", "no-store")
          .code(201)
          .send({
            data: {
              inquiryId: outcome.inquiryId,
              publicReference: outcome.publicReference,
              status: outcome.status,
              replayed: outcome.replayed === true,
            },
          });
      } catch (error) {
        throw databaseError(error);
      } finally {
        client.release();
      }
    },
  );

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



  server.patch<{ Body: LocalePreferenceBody }>("/me/preferences", { schema: { body: localePreferenceBody } }, async (request, reply) => {
    const principal = request.staffPrincipal!;
    if (!dependencies.updateUserLocale) throw new ApiError(503, "USER_PREFERENCES_NOT_CONFIGURED", "Staff preferences are not available.");
    await dependencies.updateUserLocale(principal, request.body.locale);
    return reply.code(200).send({ data: { userLocale: request.body.locale } });
  });

  server.get("/organization/locale", async (request, reply) => {
    const principal = request.staffPrincipal!;
    const client = await dependencies.pool.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
      const result = await client.query<ResultRow>(
        "SELECT eogp.get_organization_locale_settings($1::uuid,$2::uuid) AS result",
        [principal.organizationId,principal.membershipId],
      );
      await client.query("COMMIT");
      return reply.code(200).send({ data: result.rows[0]?.result ?? null });
    } catch (error) {
      try { await client.query("ROLLBACK"); } catch { /* preserve the query error */ }
      throw databaseError(error);
    } finally { client.release(); }
  });

  server.patch<{ Body: OrganizationLocaleBody }>("/organization/locale", { schema: { body: organizationLocaleBody } }, async (request, reply) => {
    const principal = request.staffPrincipal!;
    const client = await dependencies.pool.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
      await client.query("SELECT set_config('app.actor_membership_id',$1,true)", [principal.membershipId]);
      const result = await client.query<ResultRow>(
        "SELECT eogp.set_organization_default_locale($1::uuid,$2::uuid,$3::text) AS result",
        [principal.organizationId,principal.membershipId,request.body.defaultLocale],
      );
      await client.query("COMMIT");
      return reply.code(200).send({ data: result.rows[0]?.result ?? null });
    } catch (error) {
      try { await client.query("ROLLBACK"); } catch { /* preserve the command error */ }
      throw databaseError(error);
    } finally { client.release(); }
  });

  server.get<{ Params: { organizationId: string } }>(
    "/organizations/:organizationId/booking-inquiry-capabilities",
    { schema: { params: organizationInquiryParams } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      if (request.params.organizationId !== principal.organizationId) {
        throw new ApiError(403, "FORBIDDEN", "The requested organization is not the active membership organization.");
      }
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
        const result = await client.query<ResultRow>(
          "SELECT eogp.get_booking_inquiry_capabilities($1::uuid,$2::uuid) AS result",
          [principal.organizationId, principal.membershipId],
        );
        await client.query("COMMIT");
        return reply.code(200).send({ data: result.rows[0]?.result ?? {
          canAssign: false, canManage: false, canAnnotate: false, canConvert: false, canReadDraft: false, canManageDraft: false,
        } });
      } catch (error) {
        try { await client.query("ROLLBACK"); } catch { /* preserve the read error */ }
        throw databaseError(error);
      } finally {
        client.release();
      }
    },
  );

  server.get<{ Params: { organizationId: string } }>(
    "/organizations/:organizationId/booking-inquiry-assignees",
    { schema: { params: organizationInquiryParams } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      if (request.params.organizationId !== principal.organizationId) {
        throw new ApiError(403, "FORBIDDEN", "The requested organization is not the active membership organization.");
      }
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
        const result = await client.query<ResultRow>(
          "SELECT eogp.list_booking_inquiry_assignees($1::uuid,$2::uuid) AS result",
          [principal.organizationId, principal.membershipId],
        );
        await client.query("COMMIT");
        const projection = result.rows[0]?.result as { items?: unknown[] } | undefined;
        return reply.code(200).send({
          data: Array.isArray(projection?.items) ? projection.items : [],
        });
      } catch (error) {
        try { await client.query("ROLLBACK"); } catch { /* preserve the read error */ }
        throw databaseError(error);
      } finally {
        client.release();
      }
    },
  );

  server.get<{
    Params: { organizationId: string };
    Querystring: { status?: string; assignedToMembershipId?: string; limit?: number; offset?: number };
  }>(
    "/organizations/:organizationId/booking-inquiries",
    { schema: { params: organizationInquiryParams, querystring: inquiryListQuery } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      if (request.params.organizationId !== principal.organizationId) {
        throw new ApiError(403, "FORBIDDEN", "The requested organization is not the active membership organization.");
      }
      const limit = request.query.limit ?? 25;
      const offset = request.query.offset ?? 0;
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
        const result = await client.query<ResultRow>(
          "SELECT eogp.list_booking_inquiries($1::uuid,$2::uuid,$3::text,$4::uuid,$5::integer,$6::integer) AS result",
          [
            principal.organizationId,
            principal.membershipId,
            request.query.status ?? null,
            request.query.assignedToMembershipId ?? null,
            limit,
            offset,
          ],
        );
        await client.query("COMMIT");
        const projection = result.rows[0]?.result as {
          items?: unknown[];
          page?: { total?: number };
        } | undefined;
        const key = dependencies.contactEncryptionKey;
        const items = (projection?.items ?? []).map((item) =>
          decryptInquiryListItem(item, key, principal.organizationId)
        );
        return reply.code(200).send({
          data: items,
          meta: { limit, offset, totalCount: projection?.page?.total ?? 0 },
        });
      } catch (error) {
        try { await client.query("ROLLBACK"); } catch { /* preserve the read error */ }
        throw databaseError(error);
      } finally {
        client.release();
      }
    },
  );

  server.get<{ Params: { draftId: string } }>(
    "/booking-drafts/:draftId",
    { schema: { params: bookingDraftParams } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
        const result = await client.query<ResultRow>(
          "SELECT eogp.get_booking_draft($1::uuid,$2::uuid,$3::uuid) AS result",
          [principal.organizationId, request.params.draftId, principal.membershipId],
        );
        await client.query("COMMIT");
        return reply.code(200).send({
          data: decryptBookingDraftProjection(
            result.rows[0]?.result, dependencies.contactEncryptionKey, principal.organizationId,
          ),
        });
      } catch (error) {
        try { await client.query("ROLLBACK"); } catch { /* preserve the read error */ }
        throw databaseError(error);
      } finally {
        client.release();
      }
    },
  );

  server.get<{ Params: { draftId: string } }>(
    "/booking-drafts/:draftId/allocation-options",
    { schema: { params: bookingDraftParams } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
        const result = await client.query<ResultRow>(
          "SELECT eogp.get_booking_draft_allocation_options($1::uuid,$2::uuid,$3::uuid) AS result",
          [principal.organizationId, request.params.draftId, principal.membershipId],
        );
        await client.query("COMMIT");
        return reply.code(200).send({ data: result.rows[0]?.result ?? { spaces: [], resources: [] } });
      } catch (error) {
        try { await client.query("ROLLBACK"); } catch { /* preserve the original read error */ }
        throw databaseError(error);
      } finally {
        client.release();
      }
    },
  );

  server.post<{
    Params: { draftId: string };
    Body: {
      spaceLines: Array<Record<string, unknown>>;
      resourceLines: Array<Record<string, unknown>>;
      resourceStartsAt: string | null;
      resourceEndsAt: string | null;
    };
  }>(
    "/booking-drafts/:draftId/allocation-availability-preview",
    {
      schema: {
        params: bookingDraftParams,
        body: bookingDraftAllocationAvailabilityPreviewBody,
      },
    },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
        const result = await client.query<ResultRow>(
          "SELECT eogp.preview_booking_draft_allocation_availability($1::uuid,$2::uuid,$3::uuid,$4::jsonb,$5::jsonb,$6::timestamptz,$7::timestamptz) AS result",
          [
            principal.organizationId,
            request.params.draftId,
            principal.membershipId,
            JSON.stringify(request.body.spaceLines),
            JSON.stringify(request.body.resourceLines),
            request.body.resourceStartsAt,
            request.body.resourceEndsAt,
          ],
        );
        await client.query("COMMIT");
        return reply.code(200).send({
          data: result.rows[0]?.result ?? {
            spaces: [],
            resources: [],
            resourceIntervalChecked: false,
            spaceAlternatives: [],
            resourcePools: [],
            advisoryOnly: true,
          },
        });
      } catch (error) {
        try { await client.query("ROLLBACK"); } catch { /* preserve the original preview error */ }
        throw databaseError(error);
      } finally {
        client.release();
      }
    },
  );

  server.post<{
    Params: { draftId: string };
    Body: {
      expectedRevisionNumber: number;
      values: Record<string, unknown>;
      requestedStart: string | null;
      requestedEnd: string | null;
      timezone: string;
      spaceLines: Array<Record<string, unknown>>;
      resourceLines: Array<Record<string, unknown>>;
      changeReason: string;
    };
  }>(
    "/booking-drafts/:draftId/revisions",
    {
      schema: {
        params: bookingDraftParams,
        headers: idempotencyHeaders,
        body: bookingDraftRevisionBody,
      },
    },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const key = dependencies.contactEncryptionKey;
      if (!key || key.length !== 32) {
        throw new ApiError(503, "BOOKING_DRAFT_ENCRYPTION_UNAVAILABLE", "Booking draft value encryption is not configured.");
      }
      const existingRequested = request.body.values.requested;
      const requestedValues = existingRequested && typeof existingRequested === "object" &&
        !Array.isArray(existingRequested)
        ? existingRequested as Record<string, unknown>
        : {};
      const normalizedValues: Record<string, unknown> = {
        ...request.body.values,
        requested: {
          ...requestedValues,
          startAt: request.body.requestedStart,
          endAt: request.body.requestedEnd,
          timezone: request.body.timezone,
        },
      };
      assertBoundedAnswerValues(normalizedValues);
      assertBoundedAnswerValues(request.body.spaceLines);
      assertBoundedAnswerValues(request.body.resourceLines);
      const valuesCiphertext = encryptContactValue(
        JSON.stringify(normalizedValues),
        key,
        { organizationId: principal.organizationId, contactKind: "other" },
      );
      return withCommand(
        request,
        reply,
        "createBookingDraftRevision",
        { draftId: request.params.draftId, ...request.body },
        async (client) => {
          const current = await client.query<ResultRow>(
            "SELECT eogp.get_booking_draft($1::uuid,$2::uuid,$3::uuid) AS result",
            [principal.organizationId, request.params.draftId, principal.membershipId],
          );
          const projection = current.rows[0]?.result;
          if (!projection || typeof projection !== "object" || Array.isArray(projection)) {
            throw new ApiError(500, "BOOKING_DRAFT_PROJECTION_INVALID", "The booking draft projection is invalid.");
          }
          const currentRecord = projection as Record<string, unknown>;
          const currentRevision = currentRecord.currentRevision;
          if (currentRevision && typeof currentRevision === "object" && !Array.isArray(currentRevision)) {
            const fieldSchema = (currentRevision as Record<string, unknown>).fieldSchema;
            if (fieldSchema !== null && fieldSchema !== undefined) {
              const values = request.body.values;
              validatePublicFormAnswers(fieldSchema, normalizedValues.answers ?? {});
            }
          }

          const result = await client.query<ResultRow>(
            "SELECT eogp.create_booking_draft_revision($1::uuid,$2::uuid,$3::uuid,$4::integer,$5::bytea,$6::timestamptz,$7::timestamptz,$8::text,$9::jsonb,$10::jsonb,$11::text) AS result",
            [
              principal.organizationId,
              request.params.draftId,
              principal.membershipId,
              request.body.expectedRevisionNumber,
              valuesCiphertext,
              request.body.requestedStart,
              request.body.requestedEnd,
              request.body.timezone,
              JSON.stringify(request.body.spaceLines),
              JSON.stringify(request.body.resourceLines),
              request.body.changeReason,
            ],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        },
      );
    },
  );



  server.get(
    "/organization/booking-forms",
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
        const result = await client.query<ResultRow>(
          "SELECT eogp.get_booking_forms($1::uuid,$2::uuid) AS result",
          [principal.organizationId, principal.membershipId],
        );
        await client.query("COMMIT");
        return reply.code(200).send({ data: result.rows[0]?.result ?? [] });
      } catch (error) {
        try { await client.query("ROLLBACK"); } catch { /* preserve the read error */ }
        throw databaseError(error);
      } finally { client.release(); }
    },
  );

  server.post<{
    Body: { code: string; name: string; locale: "bs-BA" | "en"; fieldSchema: Record<string, unknown> };
  }>(
    "/organization/booking-forms",
    { schema: { headers: idempotencyHeaders, body: bookingFormCreateBody } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      try { validatePublicFormSchema(request.body.fieldSchema); }
      catch { throw new ApiError(422, "BOOKING_FORM_SCHEMA_INVALID", "The booking form schema is invalid."); }
      return withCommand(request, reply, "createBookingForm", request.body, async (client) => {
        const result = await client.query<ResultRow>(
          "SELECT eogp.create_booking_form($1::uuid,$2::uuid,$3::text,$4::text,$5::text,$6::jsonb) AS result",
          [principal.organizationId, principal.membershipId, request.body.code, request.body.name,
            request.body.locale, JSON.stringify(request.body.fieldSchema)],
        );
        return result.rows[0]?.result as Record<string, unknown>;
      });
    },
  );

  server.post<{ Params: { formId: string } }>(
    "/booking-forms/:formId/revisions",
    { schema: { params: bookingFormParams, headers: idempotencyHeaders } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(request, reply, "createBookingFormRevision",
        { formId: request.params.formId }, async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.create_booking_form_revision($1::uuid,$2::uuid,$3::uuid) AS result",
            [principal.organizationId, request.params.formId, principal.membershipId],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        });
    },
  );

  server.put<{
    Params: { formId: string; revisionId: string };
    Body: { locale: "bs-BA" | "en"; fieldSchema: Record<string, unknown> };
  }>(
    "/booking-forms/:formId/revisions/:revisionId",
    { schema: { params: bookingFormRevisionParams, headers: idempotencyHeaders, body: bookingFormDraftBody } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      try { validatePublicFormSchema(request.body.fieldSchema); }
      catch { throw new ApiError(422, "BOOKING_FORM_SCHEMA_INVALID", "The booking form schema is invalid."); }
      return withCommand(request, reply, "saveBookingFormDraft",
        { formId: request.params.formId, revisionId: request.params.revisionId, ...request.body },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.save_booking_form_draft($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::text,$6::jsonb) AS result",
            [principal.organizationId, request.params.formId, request.params.revisionId,
              principal.membershipId, request.body.locale, JSON.stringify(request.body.fieldSchema)],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        });
    },
  );

  server.post<{ Params: { formId: string; revisionId: string } }>(
    "/booking-forms/:formId/revisions/:revisionId/publish",
    { schema: { params: bookingFormRevisionParams, headers: idempotencyHeaders } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(request, reply, "publishBookingFormRevision",
        { formId: request.params.formId, revisionId: request.params.revisionId },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.publish_booking_form_revision($1::uuid,$2::uuid,$3::uuid,$4::uuid) AS result",
            [principal.organizationId, request.params.formId, request.params.revisionId, principal.membershipId],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        });
    },
  );

  server.get(
    "/organization/booking-price-lists",
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
        const result = await client.query<ResultRow>(
          "SELECT eogp.get_booking_price_lists($1::uuid,$2::uuid) AS result",
          [principal.organizationId, principal.membershipId],
        );
        await client.query("COMMIT");
        return reply.code(200).send({ data: result.rows[0]?.result ?? [] });
      } catch (error) {
        try { await client.query("ROLLBACK"); } catch { /* preserve the read error */ }
        throw databaseError(error);
      } finally {
        client.release();
      }
    },
  );

  server.post<{
    Body: {
      code: string; name: string; scopeKind?: "organization" | "venue" | "space";
      scopeVenueId?: string | null; scopeSpaceId?: string | null;
      currency: string; taxBasis: "inclusive" | "exclusive" | "not_applicable" | "to_be_confirmed";
    };
  }>(
    "/organization/booking-price-lists",
    { schema: { headers: idempotencyHeaders, body: bookingPriceListCreateBody } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(request, reply, "createBookingPriceList", request.body, async (client) => {
        const result = await client.query<ResultRow>(
          "SELECT eogp.create_booking_price_list($1::uuid,$2::uuid,$3::text,$4::text,$5::text,$6::uuid,$7::uuid,$8::text,$9::text) AS result",
          [
            principal.organizationId, principal.membershipId, request.body.code, request.body.name,
            request.body.scopeKind ?? "organization", request.body.scopeVenueId ?? null,
            request.body.scopeSpaceId ?? null, request.body.currency, request.body.taxBasis,
          ],
        );
        return result.rows[0]?.result as Record<string, unknown>;
      });
    },
  );

  server.post<{
    Params: { priceListId: string };
    Body: {
      currency: string; taxBasis: "inclusive" | "exclusive" | "not_applicable" | "to_be_confirmed";
      effectiveFrom?: string | null; effectiveUntil?: string | null;
    };
  }>(
    "/booking-price-lists/:priceListId/revisions",
    { schema: { params: bookingPriceListParams, headers: idempotencyHeaders, body: bookingPriceListRevisionBody } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(
        request, reply, "createBookingPriceListRevision",
        { priceListId: request.params.priceListId, ...request.body },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.create_booking_price_list_revision($1::uuid,$2::uuid,$3::uuid,$4::text,$5::text,$6::timestamptz,$7::timestamptz) AS result",
            [
              principal.organizationId, request.params.priceListId, principal.membershipId,
              request.body.currency, request.body.taxBasis, request.body.effectiveFrom ?? null,
              request.body.effectiveUntil ?? null,
            ],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        },
      );
    },
  );

  server.put<{
    Params: { priceListId: string; revisionId: string };
    Body: {
      currency: string; taxBasis: "inclusive" | "exclusive" | "not_applicable" | "to_be_confirmed";
      effectiveFrom?: string | null; effectiveUntil?: string | null;
      items: Array<{
        itemCode: string; label: string; unit: string; unitAmount: number;
        taxCode?: string | null; quantityMin?: number; quantityMax?: number | null;
      }>;
    };
  }>(
    "/booking-price-lists/:priceListId/revisions/:revisionId",
    { schema: { params: bookingPriceListRevisionParams, headers: idempotencyHeaders, body: bookingPriceListDraftBody } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(
        request, reply, "replaceBookingPriceListDraftItems",
        { priceListId: request.params.priceListId, revisionId: request.params.revisionId, ...request.body },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.replace_booking_price_list_draft_items($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::text,$6::text,$7::timestamptz,$8::timestamptz,$9::jsonb) AS result",
            [
              principal.organizationId, request.params.priceListId, request.params.revisionId,
              principal.membershipId, request.body.currency, request.body.taxBasis,
              request.body.effectiveFrom ?? null, request.body.effectiveUntil ?? null,
              JSON.stringify(request.body.items),
            ],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        },
      );
    },
  );

  server.post<{ Params: { priceListId: string; revisionId: string } }>(
    "/booking-price-lists/:priceListId/revisions/:revisionId/publish",
    { schema: { params: bookingPriceListRevisionParams, headers: idempotencyHeaders } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(
        request, reply, "publishBookingPriceListRevision",
        { priceListId: request.params.priceListId, revisionId: request.params.revisionId },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.publish_booking_price_list_revision($1::uuid,$2::uuid,$3::uuid,$4::uuid) AS result",
            [principal.organizationId, request.params.priceListId, request.params.revisionId, principal.membershipId],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        },
      );
    },
  );

  server.get(
    "/organization/booking-approval-policies",
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
        const result = await client.query<ResultRow>(
          "SELECT eogp.get_booking_approval_policies($1::uuid,$2::uuid) AS result",
          [principal.organizationId, principal.membershipId],
        );
        await client.query("COMMIT");
        return reply.code(200).send({ data: result.rows[0]?.result ?? [] });
      } catch (error) {
        try { await client.query("ROLLBACK"); } catch { /* preserve the read error */ }
        throw databaseError(error);
      } finally {
        client.release();
      }
    },
  );

  server.post<{ Body: { code: string; name: string } }>(
    "/organization/booking-approval-policies",
    {
      schema: {
        headers: idempotencyHeaders,
        body: bookingApprovalPolicyCreateBody,
      },
    },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(
        request, reply, "createBookingApprovalPolicy",
        request.body,
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.create_booking_approval_policy($1::uuid,$2::uuid,$3::text,$4::text) AS result",
            [principal.organizationId, principal.membershipId, request.body.code, request.body.name],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        },
      );
    },
  );

  server.post<{
    Params: { policyId: string };
    Body: { rules: Array<Record<string, unknown>> };
  }>(
    "/booking-approval-policies/:policyId/revisions",
    {
      schema: {
        params: bookingApprovalPolicyParams,
        headers: idempotencyHeaders,
        body: bookingApprovalPolicyRevisionBody,
      },
    },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(
        request, reply, "createBookingApprovalPolicyRevision",
        { policyId: request.params.policyId, rules: request.body.rules },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.create_booking_approval_policy_revision($1::uuid,$2::uuid,$3::uuid,$4::jsonb) AS result",
            [principal.organizationId, request.params.policyId, principal.membershipId, JSON.stringify(request.body.rules)],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        },
      );
    },
  );

  server.put<{
    Params: { policyId: string; revisionId: string };
    Body: { rules: Array<Record<string, unknown>> };
  }>(
    "/booking-approval-policies/:policyId/revisions/:revisionId",
    {
      schema: {
        params: bookingApprovalPolicyRevisionParams,
        headers: idempotencyHeaders,
        body: bookingApprovalPolicyRevisionBody,
      },
    },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(
        request, reply, "updateBookingApprovalPolicyDraftRevision",
        {
          policyId: request.params.policyId,
          revisionId: request.params.revisionId,
          rules: request.body.rules,
        },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.update_booking_approval_policy_draft_revision($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::jsonb) AS result",
            [
              principal.organizationId,
              request.params.policyId,
              request.params.revisionId,
              principal.membershipId,
              JSON.stringify(request.body.rules),
            ],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        },
      );
    },
  );

  server.post<{ Params: { policyId: string; revisionId: string } }>(
    "/booking-approval-policies/:policyId/revisions/:revisionId/publish",
    {
      schema: {
        params: bookingApprovalPolicyRevisionParams,
        headers: idempotencyHeaders,
      },
    },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(
        request, reply, "publishBookingApprovalPolicyRevision",
        { policyId: request.params.policyId, revisionId: request.params.revisionId },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.publish_booking_approval_policy_revision($1::uuid,$2::uuid,$3::uuid,$4::uuid) AS result",
            [principal.organizationId, request.params.policyId, request.params.revisionId, principal.membershipId],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        },
      );
    },
  );

  server.get(
    "/organization/booking-tax-profiles",
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
        const result = await client.query<ResultRow>(
          "SELECT eogp.get_booking_tax_profiles($1::uuid,$2::uuid) AS result",
          [principal.organizationId, principal.membershipId],
        );
        await client.query("COMMIT");
        return reply.code(200).send({ data: result.rows[0]?.result ?? [] });
      } catch (error) {
        try { await client.query("ROLLBACK"); } catch { /* preserve the read error */ }
        throw databaseError(error);
      } finally { client.release(); }
    },
  );

  server.post<{ Body: {
    code: string; name: string; jurisdictionCode?: string | null; registrationIdentifier?: string | null;
    currency: string; taxBasis: "inclusive" | "exclusive" | "not_applicable";
  } }>(
    "/organization/booking-tax-profiles",
    { schema: { headers: idempotencyHeaders, body: bookingTaxProfileCreateBody } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const body = request.body;
      return withCommand(request, reply, "createBookingTaxProfile", body, async (client) => {
        const result = await client.query<ResultRow>(
          "SELECT eogp.create_booking_tax_profile($1::uuid,$2::uuid,$3::text,$4::text,$5::text,$6::text,$7::text,$8::text) AS result",
          [principal.organizationId,principal.membershipId,body.code,body.name,body.jurisdictionCode ?? null,
           body.registrationIdentifier ?? null,body.currency,body.taxBasis],
        );
        return result.rows[0]?.result as Record<string,unknown>;
      });
    },
  );

  server.post<{ Params: { taxProfileId: string }; Body: {
    jurisdictionCode: string | null; registrationIdentifier: string | null; currency: string;
    taxBasis: "inclusive" | "exclusive" | "not_applicable";
    roundingMethod: "per_line" | "per_tax_code" | "invoice_total"; roundingScale: number;
    effectiveFrom: string | null; effectiveUntil: string | null;
  } }>(
    "/booking-tax-profiles/:taxProfileId/revisions",
    { schema: { params: bookingTaxProfileParams, headers: idempotencyHeaders, body: bookingTaxProfileRevisionCreateBody } },
    async (request, reply) => {
      const principal=request.staffPrincipal!, body=request.body;
      return withCommand(request,reply,"createBookingTaxProfileRevision",
        {taxProfileId:request.params.taxProfileId,...body},async(client)=>{
          const result=await client.query<ResultRow>(
            "SELECT eogp.create_booking_tax_profile_revision($1::uuid,$2::uuid,$3::uuid,$4::text,$5::text,$6::text,$7::text,$8::text,$9::integer,$10::timestamptz,$11::timestamptz) AS result",
            [principal.organizationId,request.params.taxProfileId,principal.membershipId,body.jurisdictionCode,
             body.registrationIdentifier,body.currency,body.taxBasis,body.roundingMethod,body.roundingScale,
             body.effectiveFrom,body.effectiveUntil],
          );
          return result.rows[0]?.result as Record<string,unknown>;
        });
    },
  );

  server.put<{ Params: { taxProfileId: string; revisionId: string }; Body: {
    jurisdictionCode: string | null; registrationIdentifier: string | null; currency: string;
    taxBasis: "inclusive" | "exclusive" | "not_applicable";
    roundingMethod: "per_line" | "per_tax_code" | "invoice_total"; roundingScale: number;
    effectiveFrom: string | null; effectiveUntil: string | null;
    taxCodes: Array<{taxCode:string;label:string;treatment:"percentage"|"zero_rated"|"exempt"|"out_of_scope"|"manual";rate:number|null}>;
  } }>(
    "/booking-tax-profiles/:taxProfileId/revisions/:revisionId",
    { schema: { params: bookingTaxProfileRevisionParams, headers: idempotencyHeaders, body: bookingTaxProfileRevisionBody } },
    async (request, reply) => {
      const principal=request.staffPrincipal!, body=request.body;
      return withCommand(request,reply,"updateBookingTaxProfileDraftRevision",
        {taxProfileId:request.params.taxProfileId,revisionId:request.params.revisionId,...body},async(client)=>{
          const result=await client.query<ResultRow>(
            "SELECT eogp.update_booking_tax_profile_draft_revision($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::text,$6::text,$7::text,$8::text,$9::text,$10::integer,$11::timestamptz,$12::timestamptz,$13::jsonb) AS result",
            [principal.organizationId,request.params.taxProfileId,request.params.revisionId,principal.membershipId,
             body.jurisdictionCode,body.registrationIdentifier,body.currency,body.taxBasis,body.roundingMethod,
             body.roundingScale,body.effectiveFrom,body.effectiveUntil,JSON.stringify(body.taxCodes)],
          );
          return result.rows[0]?.result as Record<string,unknown>;
        });
    },
  );

  server.post<{ Params: { taxProfileId: string; revisionId: string } }>(
    "/booking-tax-profiles/:taxProfileId/revisions/:revisionId/publish",
    { schema: { params: bookingTaxProfileRevisionParams, headers: idempotencyHeaders } },
    async (request,reply)=>{
      const principal=request.staffPrincipal!;
      return withCommand(request,reply,"publishBookingTaxProfileRevision",
        {taxProfileId:request.params.taxProfileId,revisionId:request.params.revisionId},async(client)=>{
          const result=await client.query<ResultRow>(
            "SELECT eogp.publish_booking_tax_profile_revision($1::uuid,$2::uuid,$3::uuid,$4::uuid) AS result",
            [principal.organizationId,request.params.taxProfileId,request.params.revisionId,principal.membershipId],
          );
          return result.rows[0]?.result as Record<string,unknown>;
        });
    },
  );

  server.put<{ Params: { priceListId: string; revisionId: string }; Body: { taxProfileRevisionId: string | null } }>(
    "/booking-price-lists/:priceListId/revisions/:revisionId/tax-profile",
    { schema: { params: bookingPriceListRevisionParams, headers: idempotencyHeaders, body: bookingPriceListTaxProfileBody } },
    async (request,reply)=>{
      const principal=request.staffPrincipal!, body=request.body;
      return withCommand(request,reply,"setBookingPriceListTaxProfileRevision",
        {priceListId:request.params.priceListId,revisionId:request.params.revisionId,...body},async(client)=>{
          const result=await client.query<ResultRow>(
            "SELECT eogp.set_booking_price_list_tax_profile_revision($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::uuid) AS result",
            [principal.organizationId,request.params.priceListId,request.params.revisionId,body.taxProfileRevisionId,principal.membershipId],
          );
          return result.rows[0]?.result as Record<string,unknown>;
        });
    },
  );

  server.get(
    "/organization/booking-cancellation-policies",
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
        const result = await client.query<ResultRow>(
          "SELECT eogp.get_booking_cancellation_policies($1::uuid,$2::uuid) AS result",
          [principal.organizationId, principal.membershipId],
        );
        await client.query("COMMIT");
        return reply.code(200).send({ data: result.rows[0]?.result ?? [] });
      } catch (error) {
        try { await client.query("ROLLBACK"); } catch { /* preserve the read error */ }
        throw databaseError(error);
      } finally {
        client.release();
      }
    },
  );

  server.post<{ Body: { code: string; name: string } }>(
    "/organization/booking-cancellation-policies",
    { schema: { headers: idempotencyHeaders, body: bookingCancellationPolicyCreateBody } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(request, reply, "createBookingCancellationPolicy", request.body, async (client) => {
        const result = await client.query<ResultRow>(
          "SELECT eogp.create_booking_cancellation_policy($1::uuid,$2::uuid,$3::text,$4::text) AS result",
          [principal.organizationId,principal.membershipId,request.body.code,request.body.name],
        );
        return result.rows[0]?.result as Record<string,unknown>;
      });
    },
  );

  server.post<{
    Params: { policyId: string };
    Body: { customerMode: "request_only" | "approval_required" | "self_service"; publicTerms: string;
      approvalRules: Record<string,unknown>; commercialRules: Record<string,unknown>; noticeRules: Record<string,unknown> };
  }>(
    "/booking-cancellation-policies/:policyId/revisions",
    { schema: { params: bookingCancellationPolicyParams, headers: idempotencyHeaders, body: bookingCancellationPolicyRevisionBody } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const body = request.body;
      return withCommand(request,reply,"createBookingCancellationPolicyRevision",
        {policyId:request.params.policyId,...body},async(client)=>{
          const result=await client.query<ResultRow>(
            "SELECT eogp.create_booking_cancellation_policy_revision($1::uuid,$2::uuid,$3::uuid,$4::text,$5::text,$6::jsonb,$7::jsonb,$8::jsonb) AS result",
            [principal.organizationId,request.params.policyId,principal.membershipId,body.customerMode,body.publicTerms,
             JSON.stringify(body.approvalRules),JSON.stringify(body.commercialRules),JSON.stringify(body.noticeRules)],
          );
          return result.rows[0]?.result as Record<string,unknown>;
        });
    },
  );

  server.put<{
    Params: { policyId: string; revisionId: string };
    Body: { customerMode: "request_only" | "approval_required" | "self_service"; publicTerms: string;
      approvalRules: Record<string,unknown>; commercialRules: Record<string,unknown>; noticeRules: Record<string,unknown> };
  }>(
    "/booking-cancellation-policies/:policyId/revisions/:revisionId",
    { schema: { params: bookingCancellationPolicyRevisionParams, headers: idempotencyHeaders, body: bookingCancellationPolicyRevisionBody } },
    async (request, reply) => {
      const principal=request.staffPrincipal!; const body=request.body;
      return withCommand(request,reply,"updateBookingCancellationPolicyDraftRevision",
        {policyId:request.params.policyId,revisionId:request.params.revisionId,...body},async(client)=>{
          const result=await client.query<ResultRow>(
            "SELECT eogp.update_booking_cancellation_policy_draft_revision($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::text,$6::text,$7::jsonb,$8::jsonb,$9::jsonb) AS result",
            [principal.organizationId,request.params.policyId,request.params.revisionId,principal.membershipId,
             body.customerMode,body.publicTerms,JSON.stringify(body.approvalRules),JSON.stringify(body.commercialRules),JSON.stringify(body.noticeRules)],
          );
          return result.rows[0]?.result as Record<string,unknown>;
        });
    },
  );

  server.post<{ Params: { policyId: string; revisionId: string } }>(
    "/booking-cancellation-policies/:policyId/revisions/:revisionId/publish",
    { schema: { params: bookingCancellationPolicyRevisionParams, headers: idempotencyHeaders } },
    async (request,reply)=>{
      const principal=request.staffPrincipal!;
      return withCommand(request,reply,"publishBookingCancellationPolicyRevision",
        {policyId:request.params.policyId,revisionId:request.params.revisionId},async(client)=>{
          const result=await client.query<ResultRow>(
            "SELECT eogp.publish_booking_cancellation_policy_revision($1::uuid,$2::uuid,$3::uuid,$4::uuid) AS result",
            [principal.organizationId,request.params.policyId,request.params.revisionId,principal.membershipId],
          );
          return result.rows[0]?.result as Record<string,unknown>;
        });
    },
  );

  server.post<{ Params: { revisionId: string }; Body: BookingConfirmationBody }>(
    "/booking-draft-revisions/:revisionId/confirm",
    {
      schema: {
        params: bookingOfferRevisionParams,
        headers: idempotencyHeaders,
        body: bookingConfirmationBody,
      },
    },
    async (request, reply) => {
      if (request.body.expectedDraftRevisionId !== request.params.revisionId) {
        throw new ApiError(409, "DRAFT_REVISION_MISMATCH", "The expected draft revision must match the revision in the request path.");
      }
      const principal = request.staffPrincipal!;
      return withCommand(
        request, reply, "confirmBooking",
        { revisionId: request.params.revisionId, ...request.body },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.confirm_booking_from_offer($1::uuid,$2::uuid,$3::uuid,$4::text) AS result",
            [
              principal.organizationId, request.params.revisionId,
              principal.membershipId, request.body.confirmationReason,
            ],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        },
      );
    },
  );

  server.get<{ Params: { offerId: string } }>(
    "/booking-offers/:offerId/approvals",
    { schema: { params: bookingOfferParams } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
        const result = await client.query<ResultRow>(
          "SELECT eogp.get_booking_offer_approval_status($1::uuid,$2::uuid,$3::uuid) AS result",
          [principal.organizationId, request.params.offerId, principal.membershipId],
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

  server.post<{
    Params: { offerId: string };
    Body: { offerRevisionId: string; ruleCode: string; decision: "approved" | "rejected" | "returned_for_changes"; reason: string };
  }>(
    "/booking-offers/:offerId/approvals",
    {
      schema: {
        params: bookingOfferParams,
        headers: idempotencyHeaders,
        body: bookingOfferApprovalBody,
      },
    },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(
        request, reply, "decideBookingOfferApproval",
        { offerId: request.params.offerId, ...request.body },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.decide_booking_offer_approval($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::text,$6::text,$7::text) AS result",
            [
              principal.organizationId, request.params.offerId, request.body.offerRevisionId,
              principal.membershipId, request.body.ruleCode, request.body.decision, request.body.reason,
            ],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        },
      );
    },
  );

  server.get<{ Params: { offerId: string } }>(
    "/public/booking-offers/:offerId",
    {
      schema: {
        params: publicOfferViewParams,
        headers: publicOfferCapabilityHeaders,
      },
    },
    async (request, reply) => {
      const token = request.headers["x-external-booking-token"];
      if (typeof token !== "string" || !/^[A-Za-z0-9_-]{43}$/.test(token)) {
        throw new ApiError(401, "BOOKING_ACTION_CAPABILITY_REQUIRED", "A valid offer review capability is required.");
      }
      const tokenHash = createHash("sha256").update(token, "utf8").digest("hex");
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        const result = await client.query<ResultRow>(
          "SELECT eogp.get_public_booking_offer_with_capability($1::uuid,$2::text) AS result",
          [request.params.offerId, tokenHash],
        );
        await client.query("COMMIT");
        const data = result.rows[0]?.result as Record<string, unknown> | undefined;
        if (!data) throw new ApiError(404, "OFFER_NOT_FOUND", "The customer offer was not found.");
        reply.header("Cache-Control", "no-store, private");
        reply.header("Referrer-Policy", "no-referrer");
        reply.header("X-Robots-Tag", "noindex, nofollow, noarchive");
        return reply.code(200).send({ data });
      } catch (error) {
        try { await client.query("ROLLBACK"); } catch { /* preserve the view error */ }
        throw databaseError(error);
      } finally {
        client.release();
      }
    },
  );

  const submitPublicOfferDecision = async (
    request: FastifyRequest,
    reply: FastifyReply,
    decision: "accepted" | "rejected",
    body: BookingOfferAcceptanceBody | BookingOfferRejectionBody,
  ) => {
    const offerId = (request.params as { offerId?: string }).offerId;
    const token = request.headers["x-external-booking-token"];
    const idempotencyKey = request.headers["idempotency-key"];
    if (!offerId || !new RegExp(uuidPattern).test(offerId)) {
      throw new ApiError(400, "INVALID_OFFER_ID", "A valid offer identifier is required.");
    }
    if (typeof token !== "string" || !/^[A-Za-z0-9_-]{43}$/.test(token)) {
      throw new ApiError(401, "BOOKING_ACTION_CAPABILITY_REQUIRED", "A valid offer decision capability is required.");
    }
    if (typeof idempotencyKey !== "string" || idempotencyKey.length < 8 || idempotencyKey.length > 200) {
      throw new ApiError(400, "IDEMPOTENCY_KEY_REQUIRED", "A valid Idempotency-Key header is required.");
    }

    const encryptionKey = dependencies.contactEncryptionKey;
    if (!encryptionKey || encryptionKey.length !== 32) {
      throw new ApiError(503, "BOOKING_OFFER_DECISION_ENCRYPTION_UNAVAILABLE", "Customer decision encryption is not configured.");
    }
    const tokenHash = createHash("sha256").update(token, "utf8").digest("hex");
    const idempotencyHash = createHash("sha256").update(idempotencyKey, "utf8").digest("hex");
    const payloadHash = requestHash({ offerId, decision, body }, encryptionKey);
    const client = await dependencies.pool.connect();
    try {
      await client.query("BEGIN");
      const contextResult = await client.query<ResultRow>(
        "SELECT eogp.resolve_booking_offer_capability($1::uuid,$2::text) AS result",
        [offerId, tokenHash],
      );
      const context = contextResult.rows[0]?.result as Record<string, unknown> | undefined;
      const organizationId = context?.organizationId;
      if (typeof organizationId !== "string" || !new RegExp(uuidPattern).test(organizationId)) {
        throw new ApiError(401, "BOOKING_ACTION_CAPABILITY_INVALID", "The offer decision capability is invalid.");
      }

      let acceptanceNameCiphertext: Buffer | null = null;
      let customerNoteCiphertext: Buffer | null = null;
      let reasonCode: string | null = null;
      let reasonCiphertext: Buffer | null = null;
      if (decision === "accepted") {
        const acceptance = body as BookingOfferAcceptanceBody;
        if (acceptance.acceptanceName?.trim()) {
          acceptanceNameCiphertext = encryptContactValue(
            acceptance.acceptanceName.trim(), encryptionKey,
            { organizationId, contactKind: "other" },
          );
        }
        if (acceptance.acceptanceNote?.trim()) {
          customerNoteCiphertext = encryptContactValue(
            acceptance.acceptanceNote.trim(), encryptionKey,
            { organizationId, contactKind: "other" },
          );
        }
      } else {
        const rejection = body as BookingOfferRejectionBody;
        reasonCode = rejection.reasonCode.trim();
        reasonCiphertext = encryptContactValue(
          JSON.stringify({ reason: rejection.reason.trim() }), encryptionKey,
          { organizationId, contactKind: "other" },
        );
        if (rejection.note?.trim()) {
          customerNoteCiphertext = encryptContactValue(
            rejection.note.trim(), encryptionKey,
            { organizationId, contactKind: "other" },
          );
        }
      }

      const result = await client.query<ResultRow>(
        "SELECT eogp.decide_booking_offer_with_capability($1::uuid,$2::text,$3::text,$4::text,$5::text,$6::bytea,$7::bytea,$8::text,$9::bytea) AS result",
        [
          offerId, tokenHash, decision, idempotencyHash, payloadHash,
          acceptanceNameCiphertext, customerNoteCiphertext, reasonCode, reasonCiphertext,
        ],
      );
      await client.query("COMMIT");
      const data = result.rows[0]?.result as Record<string, unknown> | undefined;
      if (!data) throw new ApiError(500, "OFFER_DECISION_RESULT_MISSING", "The offer decision did not return a result.");
      reply.header("Cache-Control", "no-store, private");
      reply.header("Referrer-Policy", "no-referrer");
      reply.header("X-Robots-Tag", "noindex, nofollow, noarchive");
      return reply.code(data.decision === "expired" ? 410 : 201).send({ data });
    } catch (error) {
      try { await client.query("ROLLBACK"); } catch { /* preserve the decision error */ }
      throw databaseError(error);
    } finally {
      client.release();
    }
  };

  server.post<{ Params: { offerId: string }; Body: BookingOfferAcceptanceBody }>(
    "/booking-offers/:offerId/accept",
    {
      schema: {
        params: publicOfferDecisionParams,
        headers: publicOfferDecisionHeaders,
        body: bookingOfferAcceptanceBody,
      },
    },
    async (request, reply) => submitPublicOfferDecision(request, reply, "accepted", request.body),
  );

  server.post<{ Params: { offerId: string }; Body: BookingOfferRejectionBody }>(
    "/booking-offers/:offerId/reject",
    {
      schema: {
        params: publicOfferDecisionParams,
        headers: publicOfferDecisionHeaders,
        body: bookingOfferRejectionBody,
      },
    },
    async (request, reply) => submitPublicOfferDecision(request, reply, "rejected", request.body),
  );

  const getGuestInvitationTokenHash = (request: FastifyRequest): string => {
    const token = request.headers["x-guest-invitation-token"];
    const tokenHash = hashGuestInvitationToken(token);
    if (!tokenHash) {
      throw new ApiError(401, "GUEST_INVITATION_CAPABILITY_REQUIRED", "A valid guest invitation capability is required.");
    }
    return tokenHash;
  };

  const resolveGuestInvitation = async (tokenHash: string): Promise<Record<string, unknown>> => {
    const client = await dependencies.pool.connect();
    try {
      await client.query("BEGIN");
      const result = await client.query<ResultRow>(
        "SELECT eogp.resolve_guest_invitation($1::text) AS result",
        [tokenHash],
      );
      await client.query("COMMIT");
      const data = result.rows[0]?.result as Record<string, unknown> | undefined;
      if (!data) throw new ApiError(404, "GUEST_INVITATION_NOT_FOUND", "The guest invitation was not found.");
      return data;
    } catch (error) {
      try { await client.query("ROLLBACK"); } catch { /* preserve the resolution error */ }
      throw databaseError(error);
    } finally {
      client.release();
    }
  };

  const sendGuestPrivateResponse = (
    reply: FastifyReply,
    status: number,
    data: Record<string, unknown>,
  ) => {
    reply.header("Cache-Control", "no-store, private");
    reply.header("Referrer-Policy", "no-referrer");
    reply.header("X-Robots-Tag", "noindex, nofollow, noarchive");
    return reply.code(status).send({ data });
  };

  server.get(
    "/guest/invitation/me",
    { schema: { headers: guestInvitationCapabilityHeaders } },
    async (request, reply) => {
      const tokenHash = getGuestInvitationTokenHash(request);
      const resolved = await resolveGuestInvitation(tokenHash);
      const { organizationId: _organizationId, ...data } = resolved;
      return sendGuestPrivateResponse(reply, 200, data);
    },
  );

  server.post<{ Body: { clientContext?: string } }>(
    "/guest/invitation/resolve",
    {
      schema: {
        headers: guestInvitationResolveHeaders,
        body: guestInvitationResolveBody,
      },
    },
    async (request, reply) => {
      const idempotencyKey = request.headers["idempotency-key"];
      if (typeof idempotencyKey !== "string" || idempotencyKey.length < 8 || idempotencyKey.length > 200) {
        throw new ApiError(400, "IDEMPOTENCY_KEY_REQUIRED", "A valid Idempotency-Key header is required.");
      }
      const tokenHash = getGuestInvitationTokenHash(request);
      const resolved = await resolveGuestInvitation(tokenHash);
      const { organizationId: _organizationId, ...data } = resolved;
      return sendGuestPrivateResponse(reply, 200, data);
    },
  );

  server.post<{ Body: { response: "accepted" | "declined" | "tentative"; note?: string } }>(
    "/guest/invitation/me/rsvp",
    {
      schema: {
        headers: guestRsvpHeaders,
        body: guestRsvpBody,
      },
    },
    async (request, reply) => {
      const tokenHash = getGuestInvitationTokenHash(request);
      const idempotencyKey = request.headers["idempotency-key"];
      if (typeof idempotencyKey !== "string" || idempotencyKey.length < 8 || idempotencyKey.length > 200) {
        throw new ApiError(400, "IDEMPOTENCY_KEY_REQUIRED", "A valid Idempotency-Key header is required.");
      }
      const resolved = await resolveGuestInvitation(tokenHash);
      const organizationId = resolved.organizationId;
      if (typeof organizationId !== "string" || !new RegExp(uuidPattern).test(organizationId)) {
        throw new ApiError(500, "GUEST_INVITATION_CONTEXT_INVALID", "The guest invitation context is invalid.");
      }
      let notesCiphertext: Buffer | null = null;
      if (request.body.note?.trim()) {
        const encryptionKey = dependencies.contactEncryptionKey;
        if (!encryptionKey || encryptionKey.length !== 32) {
          throw new ApiError(503, "GUEST_RSVP_ENCRYPTION_UNAVAILABLE", "Guest RSVP note encryption is not configured.");
        }
        notesCiphertext = encryptContactValue(
          request.body.note.trim(),
          encryptionKey,
          { organizationId, contactKind: "other" },
        );
      }
      const idempotencyHash = createHash("sha256").update(idempotencyKey, "utf8").digest("hex");
      const payloadHash = requestHash(
        { response: request.body.response, note: request.body.note?.trim() ?? null },
        dependencies.contactEncryptionKey,
      );
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        const result = await client.query<ResultRow>(
          "SELECT eogp.submit_guest_invitation_rsvp($1::text,$2::text,$3::text,$4::text,$5::bytea) AS result",
          [tokenHash, idempotencyHash, payloadHash, request.body.response, notesCiphertext],
        );
        await client.query("COMMIT");
        const data = result.rows[0]?.result as Record<string, unknown> | undefined;
        if (!data) throw new ApiError(500, "GUEST_RSVP_RESULT_MISSING", "The RSVP response was not recorded.");
        return sendGuestPrivateResponse(reply, 201, data);
      } catch (error) {
        try { await client.query("ROLLBACK"); } catch { /* preserve the RSVP error */ }
        throw databaseError(error);
      } finally {
        client.release();
      }
    },
  );

  server.get(
    "/guest/invitation/me/rsvp-history",
    { schema: { headers: guestInvitationCapabilityHeaders } },
    async (request, reply) => {
      const tokenHash = getGuestInvitationTokenHash(request);
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        const result = await client.query<ResultRow>(
          "SELECT eogp.get_guest_invitation_rsvp_history($1::text) AS result",
          [tokenHash],
        );
        await client.query("COMMIT");
        const data = result.rows[0]?.result;
        if (!Array.isArray(data)) throw new ApiError(500, "GUEST_RSVP_HISTORY_MISSING", "The RSVP history could not be loaded.");
        return sendGuestPrivateResponse(reply, 200, data as unknown as Record<string, unknown>);
      } catch (error) {
        try { await client.query("ROLLBACK"); } catch { /* preserve the history error */ }
        throw databaseError(error);
      } finally {
        client.release();
      }
    },
  );

  server.post<{ Params: { revisionId: string }; Body: BookingOfferCreateBody }>(
    "/booking-draft-revisions/:revisionId/offers",
    {
      schema: {
        params: bookingOfferRevisionParams,
        headers: idempotencyHeaders,
        body: bookingOfferCreateBody,
      },
    },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const body = request.body;
      return withCommand(
        request, reply, "createBookingOffer",
        { revisionId: request.params.revisionId, body },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.save_booking_offer_revision($1::uuid,$2::uuid,$3::uuid,NULL::uuid,$4::uuid,$5::uuid,$6::uuid,$7::text,$8::text,$9::timestamptz,$10::jsonb,$11::jsonb,$12::numeric,$13::text,false) AS result",
            [
              principal.organizationId, request.params.revisionId, principal.membershipId,
              body.priceListRevisionId, body.cancellationPolicyRevisionId, body.approvalPolicyRevisionId,
              body.currency, body.taxBasis, body.validUntil, JSON.stringify(body.lineItems),
              JSON.stringify(body.adjustments ?? []), body.taxAmount, body.internalReason ?? null,
            ],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        },
      );
    },
  );

  server.post<{ Params: { offerId: string }; Body: BookingOfferSuccessorBody }>(
    "/booking-offers/:offerId/revisions",
    {
      schema: {
        params: bookingOfferParams,
        headers: idempotencyHeaders,
        body: bookingOfferSuccessorBody,
      },
    },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const body = request.body;
      return withCommand(
        request, reply, "createBookingOfferSuccessorRevision",
        { offerId: request.params.offerId, body },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.save_booking_offer_revision($1::uuid,$2::uuid,$3::uuid,$4::uuid,$5::uuid,$6::uuid,$7::uuid,$8::text,$9::text,$10::timestamptz,$11::jsonb,$12::jsonb,$13::numeric,$14::text,$15::boolean) AS result",
            [
              principal.organizationId, body.draftRevisionId, principal.membershipId, request.params.offerId,
              body.priceListRevisionId, body.cancellationPolicyRevisionId, body.approvalPolicyRevisionId,
              body.currency, body.taxBasis, body.validUntil, JSON.stringify(body.lineItems),
              JSON.stringify(body.adjustments ?? []), body.taxAmount, body.internalReason ?? null,
              body.supersedeCurrentOffer ?? false,
            ],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        },
      );
    },
  );

  server.get<{ Params: { offerId: string } }>(
    "/booking-offers/:offerId",
    { schema: { params: bookingOfferParams } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
        const result = await client.query<ResultRow>(
          "SELECT eogp.get_booking_offer($1::uuid,$2::uuid,$3::uuid) AS result",
          [principal.organizationId, request.params.offerId, principal.membershipId],
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

  server.get<{
    Params: { offerId: string };
    Querystring: { status?: string; limit?: number; offset?: number };
  }>(
    "/booking-offers/:offerId/email-deliveries",
    { schema: { params: bookingOfferParams, querystring: bookingOfferEmailDeliveryQuery } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const limit = request.query.limit ?? 25;
      const offset = request.query.offset ?? 0;
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
        const result = await client.query<ResultRow>(
          "SELECT eogp.list_booking_offer_email_deliveries($1::uuid,$2::uuid,$3::uuid,$4::text,$5::integer,$6::integer) AS result",
          [principal.organizationId,request.params.offerId,principal.membershipId,request.query.status ?? null,limit,offset],
        );
        await client.query("COMMIT");
        const projection = result.rows[0]?.result as {
          items?: unknown[];
          page?: { total?: number };
          counts?: Record<string,number>;
        } | undefined;
        return reply.code(200).send({
          data: projection?.items ?? [],
          meta: { limit,offset,totalCount: projection?.page?.total ?? 0,counts: projection?.counts ?? {} },
        });
      } catch (error) {
        try { await client.query("ROLLBACK"); } catch { /* preserve the read error */ }
        throw databaseError(error);
      } finally {
        client.release();
      }
    },
  );

  server.post<{
    Params: { deliveryId: string };
    Body: { resolution: string; reason: string; providerMessageReference?: string };
  }>(
    "/booking-offer-email-deliveries/:deliveryId/reconcile",
    {
      schema: {
        params: { type: "object", required: ["deliveryId"], properties: { deliveryId: { type: "string", pattern: uuidPattern } }, additionalProperties: false },
        headers: idempotencyHeaders,
        body: bookingOfferEmailReconciliationBody,
      },
    },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(request,reply,"reconcileBookingOfferEmailDelivery",
        { deliveryId:request.params.deliveryId,resolution:request.body.resolution,reason:request.body.reason,
          providerMessageReference:request.body.providerMessageReference ?? null },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.reconcile_booking_offer_email_delivery($1::uuid,$2::uuid,$3::uuid,$4::text,$5::text,$6::text) AS result",
            [principal.organizationId,request.params.deliveryId,principal.membershipId,
              request.body.resolution,request.body.reason,request.body.providerMessageReference ?? null],
          );
          return result.rows[0]?.result as Record<string,unknown>;
        });
    },
  );

  server.post<{
    Params: { deliveryId: string };
    Body: { reason: string };
  }>(
    "/booking-offer-email-deliveries/:deliveryId/retry",
    {
      schema: {
        params: { type: "object", required: ["deliveryId"], properties: { deliveryId: { type: "string", pattern: uuidPattern } }, additionalProperties: false },
        headers: idempotencyHeaders,
        body: bookingOfferEmailRetryBody,
      },
    },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(request,reply,"retryBookingOfferEmailDelivery",
        { deliveryId:request.params.deliveryId,reason:request.body.reason },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.retry_booking_offer_email_delivery($1::uuid,$2::uuid,$3::uuid,$4::text) AS result",
            [principal.organizationId,request.params.deliveryId,principal.membershipId,request.body.reason],
          );
          return result.rows[0]?.result as Record<string,unknown>;
        });
    },
  );

  server.post<{ Params: { offerId: string }; Body: Record<string, never> }>(
    "/booking-offers/:offerId/issue",
    {
      schema: {
        params: bookingOfferParams,
        headers: idempotencyHeaders,
        body: bookingOfferIssueBody,
      },
    },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const capabilityKey = dependencies.bookingCapabilityKey;
      if (!capabilityKey || capabilityKey.length !== 32) {
        throw new ApiError(503, "BOOKING_CAPABILITY_KEY_UNAVAILABLE", "Customer offer capability issuance is not configured.");
      }
      const idempotencyKey = request.headers["idempotency-key"];
      if (typeof idempotencyKey !== "string") {
        throw new ApiError(400, "IDEMPOTENCY_KEY_REQUIRED", "A valid Idempotency-Key header is required.");
      }
      // Deterministic, domain-separated derivation means retries can return the
      // same raw capability without persisting it in the idempotency response.
      const acceptanceToken = createHmac("sha256", capabilityKey)
        .update(JSON.stringify({
          purpose: "eventor:booking-offer-capability:v1",
          organizationId: principal.organizationId,
          membershipId: principal.membershipId,
          offerId: request.params.offerId,
          idempotencyKey,
        }), "utf8")
        .digest("base64url");
      const tokenHash = createHash("sha256").update(acceptanceToken, "utf8").digest("hex");
      const command = await runIdempotentCommand(
        dependencies, principal, "issueBookingOffer", idempotencyKey,
        { offerId: request.params.offerId },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.issue_booking_offer($1::uuid,$2::uuid,$3::uuid,$4::text) AS result",
            [principal.organizationId, request.params.offerId, principal.membershipId, tokenHash],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        },
      );
      const data = command.body.data as Record<string, unknown>;
      return reply.code(command.status).send({ data: { ...data, acceptanceToken } });
    },
  );

  server.post<{ Params: { offerId: string }; Body: BookingOfferEmailBody }>(
    "/booking-offers/:offerId/email",
    {
      schema: {
        params: bookingOfferParams,
        headers: idempotencyHeaders,
        body: bookingOfferEmailBody,
      },
    },
    async (request, reply) => {
      const encryptionKey = dependencies.contactEncryptionKey;
      if (!encryptionKey || encryptionKey.length !== 32) {
        throw new ApiError(503, "BOOKING_OFFER_DECISION_ENCRYPTION_UNAVAILABLE", "Customer capability encryption is not configured.");
      }
      const token = request.body.acceptanceToken;
      if (!/^[A-Za-z0-9_-]{43}$/.test(token)) {
        throw new ApiError(422, "BOOKING_ACTION_CAPABILITY_INVALID", "A valid customer offer capability is required.");
      }
      const tokenHash = createHash("sha256").update(token, "utf8").digest("hex");
      const encryptedToken = encryptContactValue(token, encryptionKey, {
        organizationId: request.staffPrincipal!.organizationId,
        contactKind: "other",
      });
      const principal = request.staffPrincipal!;
      return withCommand(
        request, reply, "queueBookingOfferEmailDelivery",
        { offerId: request.params.offerId, capabilityTokenSha256: tokenHash },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.queue_booking_offer_email_delivery($1::uuid,$2::uuid,$3::uuid,$4::text,$5::text,$6::bytea) AS result",
            [
              principal.organizationId, request.params.offerId, principal.membershipId,
              createHash("sha256").update(String(request.headers["idempotency-key"]), "utf8").digest("hex"),
              tokenHash, encryptedToken,
            ],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        },
      );
    },
  );

  server.post<{
    Params: { inquiryId: string };
  }>(
    "/booking-inquiries/:inquiryId/create-draft",
    {
      schema: {
        params: inquiryParams,
        headers: idempotencyHeaders,
      },
    },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(
        request, reply, "createBookingDraftFromInquiry",
        { inquiryId: request.params.inquiryId },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.convert_booking_inquiry_to_draft($1::uuid,$2::uuid,$3::uuid) AS result",
            [principal.organizationId, request.params.inquiryId, principal.membershipId],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        },
      );
    },
  );

  server.get<{ Params: { inquiryId: string } }>(
    "/booking-inquiries/:inquiryId",
    { schema: { params: inquiryParams } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
        const result = await client.query<ResultRow>(
          "SELECT eogp.get_booking_inquiry($1::uuid,$2::uuid,$3::uuid) AS result",
          [principal.organizationId, request.params.inquiryId, principal.membershipId],
        );
        await client.query("COMMIT");
        return reply.code(200).send({
          data: decryptInquiryDetail(result.rows[0]?.result, dependencies.contactEncryptionKey, principal.organizationId),
        });
      } catch (error) {
        try { await client.query("ROLLBACK"); } catch { /* preserve the read error */ }
        throw databaseError(error);
      } finally {
        client.release();
      }
    },
  );

  server.post<{
    Params: { inquiryId: string };
    Body: { assignedToMembershipId: string | null };
  }>(
    "/booking-inquiries/:inquiryId/assignment",
    {
      schema: {
        params: inquiryParams,
        headers: idempotencyHeaders,
        body: inquiryAssignmentBody,
      },
    },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(
        request, reply, "assignBookingInquiry",
        { inquiryId: request.params.inquiryId, assignedToMembershipId: request.body.assignedToMembershipId },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.assign_booking_inquiry($1::uuid,$2::uuid,$3::uuid,$4::uuid) AS result",
            [principal.organizationId, request.params.inquiryId, principal.membershipId, request.body.assignedToMembershipId],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        },
      );
    },
  );

  server.post<{
    Params: { inquiryId: string };
    Body: { status: string; reason: string };
  }>(
    "/booking-inquiries/:inquiryId/status",
    {
      schema: {
        params: inquiryParams,
        headers: idempotencyHeaders,
        body: inquiryStatusBody,
      },
    },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(
        request, reply, "changeBookingInquiryStatus",
        { inquiryId: request.params.inquiryId, status: request.body.status, reason: request.body.reason },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.change_booking_inquiry_status($1::uuid,$2::uuid,$3::uuid,$4::text,$5::text) AS result",
            [principal.organizationId, request.params.inquiryId, principal.membershipId, request.body.status, request.body.reason],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        },
      );
    },
  );

  server.post<{
    Params: { inquiryId: string };
    Body: { annotation: string };
  }>(
    "/booking-inquiries/:inquiryId/annotations",
    {
      schema: {
        params: inquiryParams,
        headers: idempotencyHeaders,
        body: inquiryAnnotationBody,
      },
    },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(
        request, reply, "addBookingInquiryAnnotation",
        { inquiryId: request.params.inquiryId, annotation: request.body.annotation },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.add_booking_inquiry_annotation($1::uuid,$2::uuid,$3::uuid,$4::text) AS result",
            [principal.organizationId, request.params.inquiryId, principal.membershipId, request.body.annotation],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        },
      );
    },
  );

  server.get<{
    Querystring: { status?: string; limit?: number; offset?: number };
  }>(
    "/event-notification-campaigns",
    { schema: { querystring: campaignListQuery } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const limit = request.query.limit ?? 25;
      const offset = request.query.offset ?? 0;
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
        const result = await client.query<ResultRow>(
          "SELECT eogp.list_event_notification_campaigns($1::uuid,$2::uuid,$3::text,$4::integer,$5::integer) AS result",
          [principal.organizationId, principal.membershipId, request.query.status ?? null, limit, offset],
        );
        await client.query("COMMIT");
        const projection = result.rows[0]?.result as {
          items?: unknown[];
          page?: { total?: number };
        } | undefined;
        return reply.code(200).send({
          data: projection?.items ?? [],
          meta: { limit, offset, totalCount: projection?.page?.total ?? 0 },
        });
      } catch (error) {
        try { await client.query("ROLLBACK"); } catch { /* preserve the read error */ }
        throw databaseError(error);
      } finally {
        client.release();
      }
    },
  );

  server.get<{ Params: { campaignId: string } }>(
    "/event-notification-campaigns/:campaignId",
    { schema: { params: campaignParams } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
        const result = await client.query<ResultRow>(
          "SELECT eogp.get_event_notification_campaign_progress($1::uuid,$2::uuid,$3::uuid) AS result",
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

  server.get<{
    Params: { campaignId: string };
    Querystring: { status?: string; limit?: number; offset?: number };
  }>(
    "/event-notification-campaigns/:campaignId/deliveries",
    { schema: { params: campaignParams, querystring: campaignDeliveryQuery } },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      const limit = request.query.limit ?? 50;
      const offset = request.query.offset ?? 0;
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
        const result = await client.query<ResultRow>(
          "SELECT eogp.list_event_notification_campaign_deliveries($1::uuid,$2::uuid,$3::uuid,$4::text,$5::integer,$6::integer) AS result",
          [principal.organizationId, request.params.campaignId, principal.membershipId, request.query.status ?? null, limit, offset],
        );
        await client.query("COMMIT");
        const projection = result.rows[0]?.result as {
          items?: unknown[];
          page?: { total?: number };
          counts?: Record<string, number>;
        } | undefined;
        return reply.code(200).send({
          data: projection?.items ?? [],
          meta: { limit, offset, totalCount: projection?.page?.total ?? 0, counts: projection?.counts ?? {} },
        });
      } catch (error) {
        try { await client.query("ROLLBACK"); } catch { /* preserve the read error */ }
        throw databaseError(error);
      } finally {
        client.release();
      }
    },
  );

  server.post<{
    Params: { attemptId: string };
    Body: { resolution: string; reason: string };
  }>(
    "/notification-delivery-attempts/:attemptId/reconcile",
    {
      schema: {
        params: { type: "object", required: ["attemptId"], properties: { attemptId: { type: "string", pattern: uuidPattern } }, additionalProperties: false },
        headers: idempotencyHeaders,
        body: deliveryReconciliationBody,
      },
    },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(request, reply, "reconcileNotificationDeliveryAttempt",
        { attemptId: request.params.attemptId, resolution: request.body.resolution, reason: request.body.reason },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.reconcile_notification_delivery_attempt($1::uuid,$2::uuid,$3::uuid,$4::text,$5::text) AS result",
            [principal.organizationId, request.params.attemptId, principal.membershipId, request.body.resolution, request.body.reason],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        });
    },
  );

  server.post<{
    Params: { attemptId: string };
    Body: { reason: string };
  }>(
    "/notification-delivery-attempts/:attemptId/retry",
    {
      schema: {
        params: { type: "object", required: ["attemptId"], properties: { attemptId: { type: "string", pattern: uuidPattern } }, additionalProperties: false },
        headers: idempotencyHeaders,
        body: deliveryRetryBody,
      },
    },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(request, reply, "retryFailedNotificationDeliveryAttempt",
        { attemptId: request.params.attemptId, reason: request.body.reason },
        async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.retry_failed_notification_delivery_attempt($1::uuid,$2::uuid,$3::uuid,$4::text) AS result",
            [principal.organizationId, request.params.attemptId, principal.membershipId, request.body.reason],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        });
    },
  );

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
    "/event-notification-campaigns/:campaignId/cancel",
    {
      schema: {
        params: campaignParams,
        headers: idempotencyHeaders,
        body: { type: "object", properties: {}, additionalProperties: false },
      },
    },
    async (request, reply) => {
      const principal = request.staffPrincipal!;
      return withCommand(request, reply, "cancelQueuedEventNotificationCampaign",
        { campaignId: request.params.campaignId }, async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.cancel_queued_event_notification_campaign($1::uuid,$2::uuid,$3::uuid) AS result",
            [principal.organizationId, request.params.campaignId, principal.membershipId],
          );
          return result.rows[0]?.result as Record<string, unknown>;
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

  server.get("/organization/delivery/email/resend-webhook", async (request, reply) => {
    const principal = request.staffPrincipal!;
    const client = await dependencies.pool.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT set_config('app.organization_id',$1,true)", [principal.organizationId]);
      const result = await client.query<ResultRow>(
        "SELECT eogp.get_organization_resend_webhook_configuration($1::uuid,$2::uuid) AS result",
        [principal.organizationId, principal.membershipId],
      );
      await client.query("COMMIT");
      const data = result.rows[0]?.result as Record<string, unknown> | undefined;
      const endpointId = typeof data?.endpointId === "string" ? data.endpointId : null;
      return reply.code(200).send({
        data: {
          endpointId,
          configured: data?.configured === true,
          callbackUrl: endpointId && dependencies.publicApiBaseUrl
            ? `${dependencies.publicApiBaseUrl}/webhooks/resend/${endpointId}`
            : null,
          updatedAt: data?.updatedAt ?? null,
        },
      });
    } catch (error) {
      try { await client.query("ROLLBACK"); } catch { /* preserve the original error */ }
      throw databaseError(error);
    } finally {
      client.release();
    }
  });

  server.post<{ Body: Record<string, never> }>(
    "/organization/delivery/email/resend-webhook/prepare",
    {
      schema: {
        headers: idempotencyHeaders,
        body: { type: "object", properties: {}, additionalProperties: false },
      },
    },
    async (request, reply) => {
      if (!dependencies.publicApiBaseUrl) {
        throw new ApiError(503, "PUBLIC_API_URL_NOT_CONFIGURED", "Set EVENTOR_PUBLIC_API_BASE_URL to the externally reachable HTTPS API base URL before configuring provider callbacks.");
      }
      const principal = request.staffPrincipal!;
      const endpointId = randomUUID();
      return withCommand(request, reply, "prepareOrganizationResendWebhook",
        {}, async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.prepare_organization_resend_webhook_endpoint($1::uuid,$2::uuid,$3::uuid) AS result",
            [principal.organizationId, principal.membershipId, endpointId],
          );
          const data = result.rows[0]?.result as Record<string, unknown>;
          return {
            ...data,
            callbackUrl: `${dependencies.publicApiBaseUrl}/webhooks/resend/${endpointId}`,
          };
        });
    },
  );

  server.post<{
    Body: { endpointId: string; signingSecret: string };
  }>(
    "/organization/delivery/email/resend-webhook/activate",
    {
      schema: {
        headers: idempotencyHeaders,
        body: resendWebhookActivateBody,
      },
    },
    async (request, reply) => {
      const key = dependencies.deliveryCredentialsEncryptionKey;
      if (!key || key.length !== 32) {
        throw new ApiError(503, "DELIVERY_CREDENTIAL_ENCRYPTION_UNAVAILABLE", "Delivery credential encryption is not configured.");
      }
      const principal = request.staffPrincipal!;
      let encryptedSecret: Buffer;
      try {
        encryptedSecret = encryptDeliveryCredentialBundle(
          { signingSecret: request.body.signingSecret },
          key,
          { organizationId: principal.organizationId, channel: "email" },
        );
      } catch {
        throw new ApiError(422, "RESEND_SIGNING_SECRET_INVALID", "The Resend signing secret is invalid.");
      }
      return withCommand(request, reply, "activateOrganizationResendWebhook",
        request.body, async (client) => {
          const result = await client.query<ResultRow>(
            "SELECT eogp.activate_organization_resend_webhook_endpoint($1::uuid,$2::uuid,$3::uuid,$4::bytea) AS result",
            [principal.organizationId, principal.membershipId, request.body.endpointId, encryptedSecret],
          );
          return result.rows[0]?.result as Record<string, unknown>;
        });
    },
  );

  server.post<{ Params: { endpointId: string } }>(
    "/webhooks/resend/:endpointId",
    { schema: { params: resendWebhookParams } },
    async (request, reply) => {
      const rawBody = request.rawJsonBody;
      if (typeof rawBody !== "string" || rawBody.length === 0) {
        return reply.code(400).send({ error: "Invalid webhook body." });
      }
      const svixId = request.headers["svix-id"];
      const svixTimestamp = request.headers["svix-timestamp"];
      const svixSignature = request.headers["svix-signature"];
      if (typeof svixId !== "string" || typeof svixTimestamp !== "string" ||
          typeof svixSignature !== "string") {
        return reply.code(401).send({ error: "Webhook signature is required." });
      }

      const resolver = await dependencies.pool.connect();
      let resolved: Record<string, unknown> | undefined;
      try {
        await resolver.query("BEGIN");
        const lookup = await resolver.query<ResultRow>(
          "SELECT eogp.resolve_organization_resend_webhook_endpoint($1::uuid) AS result",
          [request.params.endpointId],
        );
        resolved = lookup.rows[0]?.result as Record<string, unknown> | undefined;
        await resolver.query("COMMIT");
      } catch (error) {
        try { await resolver.query("ROLLBACK"); } catch { /* preserve the original error */ }
        request.log.error({ err: error }, "Resend webhook endpoint lookup failed");
        return reply.code(503).send({ error: "Webhook endpoint temporarily unavailable." });
      } finally {
        resolver.release();
      }

      const organizationId = typeof resolved?.organizationId === "string"
        ? resolved.organizationId : null;
      const encryptedBase64 = typeof resolved?.signingSecretCiphertextBase64 === "string"
        ? resolved.signingSecretCiphertextBase64 : null;
      if (!organizationId || !encryptedBase64) {
        return reply.code(404).send({ error: "Webhook endpoint not found." });
      }

      const encryptionKey = dependencies.deliveryCredentialsEncryptionKey;
      if (!encryptionKey || encryptionKey.length !== 32) {
        request.log.error("Resend webhook encryption key is unavailable");
        return reply.code(503).send({ error: "Webhook endpoint temporarily unavailable." });
      }
      let signingSecret: string;
      try {
        const credentials = decryptDeliveryCredentialBundle(
          Buffer.from(encryptedBase64, "base64"),
          encryptionKey,
          { organizationId, channel: "email" },
        );
        signingSecret = credentials.signingSecret ?? "";
      } catch {
        request.log.error("Resend webhook signing secret could not be decrypted");
        return reply.code(503).send({ error: "Webhook endpoint temporarily unavailable." });
      }

      if (!verifyResendWebhookSignature({
        payload: rawBody,
        headers: { id: svixId, timestamp: svixTimestamp, signature: svixSignature },
        signingSecret,
      })) {
        return reply.code(401).send({ error: "Invalid webhook signature." });
      }

      const payload = request.body as unknown;
      if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
        return reply.code(400).send({ error: "Invalid webhook event." });
      }
      const event = payload as {
        type?: unknown;
        data?: { message_id?: unknown; to?: unknown };
      };
      if (event.type !== "email.delivered" && event.type !== "email.bounced") {
        return reply.code(204).send();
      }
      const messageReference = event.data?.message_id;
      const recipients = event.data?.to;
      if (typeof messageReference !== "string" || messageReference.length < 3 ||
          messageReference.length > 500 || /[\r\n\0]/.test(messageReference) ||
          !Array.isArray(recipients) || recipients.length !== 1 ||
          typeof recipients[0] !== "string" || recipients[0].length < 3 ||
          recipients[0].length > 320) {
        return reply.code(400).send({ error: "Unsupported Resend email event shape." });
      }

      const outcome = event.type === "email.delivered" ? "delivered" : "bounced";
      const payloadHash = createHash("sha256").update(rawBody, "utf8").digest("hex");
      const client = await dependencies.pool.connect();
      try {
        await client.query("BEGIN");
        await client.query("SELECT set_config('app.organization_id',$1,true)", [organizationId]);
        const recorded = await client.query<ResultRow>(
          "SELECT eogp.record_verified_resend_delivery_webhook($1::uuid,$2::uuid,$3::text,$4::text,$5::text,$6::text) AS result",
          [organizationId, request.params.endpointId, svixId, messageReference, outcome, payloadHash],
        );
        await client.query("COMMIT");
        const result = recorded.rows[0]?.result as { duplicate?: boolean; status?: string } | undefined;
        return reply.code(200).send({
          received: true,
          duplicate: result?.duplicate === true,
          status: result?.status ?? outcome,
        });
      } catch (error) {
        try { await client.query("ROLLBACK"); } catch { /* preserve the original error */ }
        const code = typeof error === "object" && error !== null && "code" in error
          ? String((error as { code?: unknown }).code ?? "") : "";
        if (code === "P0002") return reply.code(404).send({ error: "Delivery attempt not found." });
        if (code === "55000" || code === "23505" || code === "22023" || code === "42501") {
          return reply.code(409).send({ error: "Webhook event conflicts with the recorded delivery state." });
        }
        request.log.error({ err: error }, "Resend delivery event ingestion failed");
        return reply.code(503).send({ error: "Webhook event could not be stored." });
      } finally {
        client.release();
      }
    },
  );

  return server;
}
