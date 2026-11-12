export interface ApiProblem {
  readonly status: number;
  readonly code: string;
  readonly title: string;
  readonly requestId?: string;
}

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code: string,
    readonly requestId?: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

const apiBase = (import.meta.env.VITE_API_BASE_URL || "/api").replace(/\/$/, "");
const csrfCookieName = "__Host-eventor_csrf";

function readCookie(name: string): string | null {
  const prefix = `${name}=`;
  const item = document.cookie.split(";").map((value) => value.trim()).find((value) => value.startsWith(prefix));
  if (!item) return null;
  try {
    return decodeURIComponent(item.slice(prefix.length));
  } catch {
    return null;
  }
}

function idempotencyKey(): string {
  if (!globalThis.crypto?.randomUUID) {
    throw new Error("This browser does not support secure request identifiers.");
  }
  return globalThis.crypto.randomUUID();
}

async function request<T>(
  path: string,
  options: {
    method?: "GET" | "POST" | "PUT" | "DELETE";
    body?: unknown;
    idempotent?: boolean;
    idempotencyKey?: string;
    extraHeaders?: Record<string, string>;
    credentials?: RequestCredentials;
    skipCsrf?: boolean;
  } = {},
): Promise<T> {
  const method = options.method ?? "GET";
  const headers = new Headers({ Accept: "application/json" });
  if (options.body !== undefined) headers.set("Content-Type", "application/json");

  for (const [name, value] of Object.entries(options.extraHeaders ?? {})) headers.set(name, value);
  if (method !== "GET") {
    const csrf = readCookie(csrfCookieName);
    if (path !== "/auth/session" && !options.skipCsrf && !csrf) {
      throw new Error("The CSRF cookie is missing. Sign in again before continuing.");
    }
    if (csrf && !options.skipCsrf) headers.set("X-CSRF-Token", csrf);
    if (options.idempotent) headers.set("Idempotency-Key", options.idempotencyKey ?? idempotencyKey());
  }

  const response = await fetch(`${apiBase}${path}`, {
    method,
    headers,
    credentials: options.credentials ?? "include",
    cache: "no-store",
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });

  if (response.status === 204) return undefined as T;
  const payload: unknown = await response.json().catch(() => null);
  if (!response.ok) {
    const problem = payload && typeof payload === "object" ? payload as Partial<ApiProblem> : {};
    const message = typeof problem.title === "string"
      ? problem.title
      : `Request failed (HTTP ${response.status}).`;
    throw new ApiError(message, response.status, problem.code ?? "REQUEST_FAILED", problem.requestId);
  }
  return payload as T;
}

export interface Envelope<T> {
  data: T;
}

export interface Principal {
  userId: string;
  organizationId: string;
  membershipId: string;
  memberships?: Array<{
    membershipId: string;
    organizationId: string;
    organizationSlug: string;
    organizationName: string;
    selected: boolean;
  }>;
}

export interface EmailSettings {
  host: string;
  port: number;
  transportSecurity: "starttls" | "implicit_tls";
  authMode: "none" | "password";
  senderEmail: string;
  senderName?: string;
  replyTo?: string;
  connectionTimeoutMs?: number;
}

export interface EmailConfiguration {
  channel: "email";
  provider?: string;
  revision?: number;
  settings?: EmailSettings;
  credentialsConfigured: boolean;
  deliveryEnabled: boolean;
  configured?: boolean;
  updatedAt?: string;
}

export interface CampaignReview {
  campaignId: string;
  eventId: string;
  eventDecisionId: string;
  purpose: string;
  audienceKind: string;
  status: string;
  recipientCount: number;
  actualRecipientCount: number;
  recipientsByChannel: Record<string, number>;
  exclusionCount: number;
  exclusionsByReason: Record<string, number>;
  recipients: Array<{
    participationId: string;
    invitationId: string;
    channel: string;
    qualificationReason: string;
  }>;
  template: {
    revisionId: string;
    revisionNumber: number;
    locale: string;
    subjectTemplate: string;
    bodyTemplate: string;
    state: string;
    publishedAt: string | null;
  };
  audienceRulesSnapshot: unknown;
  createdAt: string;
  confirmedAt: string | null;
}

export interface CampaignListItem {
  campaignId: string;
  eventId: string;
  purpose: string;
  audienceKind: string;
  status: string;
  recipientCount: number | null;
  actualRecipientCount: number;
  createdAt: string;
  confirmedAt: string | null;
  queuedAt: string | null;
  deliveryStartedAt: string | null;
  deliveryCompletedAt: string | null;
}

export interface CampaignProgress {
  campaignId: string;
  eventId: string;
  status: string;
  purpose: string;
  recipientCount: number;
  attemptCount: number;
  deliveryCounts: {
    queued: number;
    sending: number;
    sent: number;
    failed: number;
    uncertain: number;
    suppressed: number;
  };
  createdAt: string;
  confirmedAt: string | null;
  queuedAt: string | null;
  deliveryStartedAt: string | null;
  deliveryCompletedAt: string | null;
}

export interface DeliveryAttempt {
  attemptId: string;
  recipientReference: string;
  channel: string;
  attemptNumber: number;
  status: string;
  failureCode: string | null;
  provider: string | null;
  queuedForAt: string;
  sendingAt: string | null;
  completedAt: string | null;
  retryScheduled: boolean;
}

export interface ResendWebhookConfiguration {
  endpointId: string | null;
  configured: boolean;
  callbackUrl: string | null;
  updatedAt?: string | null;
}

export type BookingInquiryStatus =
  | "received"
  | "under_review"
  | "converted"
  | "declined"
  | "withdrawn"
  | "spam";

export interface BookingInquiryListItem {
  inquiryId: string;
  publicReference: string;
  status: BookingInquiryStatus;
  formRevisionId: string;
  requesterName: string;
  requestedStart: string | null;
  requestedEnd: string | null;
  requestedTimezone: string | null;
  assignedToMembershipId: string | null;
  submittedAt: string;
  updatedAt: string;
}

export interface BookingInquiryAnnotation {
  annotationId: string;
  annotation: string;
  visibility: "internal";
  actorMembershipId: string;
  createdAt: string;
}

export interface BookingInquiryStatusHistoryItem {
  previousStatus: string | null;
  newStatus: string;
  reason: string | null;
  actorKind: "public" | "membership" | "system";
  actorMembershipId: string | null;
  occurredAt: string;
}

export interface BookingInquiryAssignmentHistoryItem {
  previousAssigneeMembershipId: string | null;
  newAssigneeMembershipId: string | null;
  actorMembershipId: string;
  occurredAt: string;
}

export interface BookingInquiryDetail extends BookingInquiryListItem {
  fieldSchema: {
    schemaVersion?: number;
    fields: Array<{
      code: string;
      type: string;
      label?: string;
      options?: Array<{ value: string; label: string }>;
    }>;
  };
  requesterEmail: string | null;
  requesterPhone: string | null;
  submittedValues: {
    requested?: {
      startAt: string | null;
      endAt: string | null;
      timezone: string;
      spaceCodes: string[];
    };
    answers: Record<string, unknown>;
  };
  annotations: BookingInquiryAnnotation[];
  statusHistory: BookingInquiryStatusHistoryItem[];
  assignmentHistory: BookingInquiryAssignmentHistoryItem[];
  bookingDraft: {
    draftId: string;
    status: "draft" | "offered" | "confirmed" | "abandoned";
    currentRevisionNumber: number;
  } | null;
}

export interface BookingInquiryCapabilities {
  canAssign: boolean;
  canManage: boolean;
  canAnnotate: boolean;
  canConvert: boolean;
  canReadDraft: boolean;
  canManageDraft: boolean;
}

export interface BookingDraftSpaceLine {
  spaceLineId: string;
  venueSpaceId: string;
  blockKind: "setup" | "rehearsal" | "event_use" | "teardown" | "buffer";
  startsAt: string;
  endsAt: string;
  requestedCapacity: number | null;
}

export interface BookingDraftResourceLine {
  resourceLineId: string;
  resourceTypeId: string;
  lineCode: string;
  label: string;
  requestedQuantity: number;
  values: Record<string, unknown>;
}

export interface BookingDraftRevisionHistoryItem {
  revisionId: string;
  revisionNumber: number;
  changeReason: string | null;
  createdAt: string;
  createdByMembershipId: string;
  createdByDisplayName: string;
}

export interface BookingDraftDetail {
  draftId: string;
  sourceInquiryId: string | null;
  status: "draft" | "offered" | "confirmed" | "abandoned";
  currentRevisionNumber: number;
  createdAt: string;
  updatedAt: string;
  currentRevision: {
    revisionId: string;
    revisionNumber: number;
    sourceFormRevisionId: string | null;
    fieldSchema: BookingInquiryDetail["fieldSchema"] | null;
    values: Record<string, unknown>;
    requestedStart: string | null;
    requestedEnd: string | null;
    timezone: string;
    changeReason: string | null;
    createdAt: string;
    createdByMembershipId: string;
    spaceLines: BookingDraftSpaceLine[];
    resourceLines: BookingDraftResourceLine[];
  } | null;
  revisionHistory: BookingDraftRevisionHistoryItem[];
}

export interface BookingDraftRevisionResult {
  draftId: string;
  revisionId: string;
  revisionNumber: number;
  previousRevisionNumber: number;
  status: "draft" | "offered" | "confirmed" | "abandoned";
  changed: boolean;
}

export interface BookingInquiryConversion {
  inquiryId: string;
  draftId: string;
  revisionId: string;
  revisionNumber: number;
  status: "converted";
  changed: boolean;
}

export interface BookingInquiryAssignee {
  membershipId: string;
  displayName: string;
}


export interface BookingCancellationPolicyRevision {
  revisionId: string;
  revisionNumber: number;
  customerMode: "request_only" | "approval_required" | "self_service";
  publicTerms: string;
  approvalRules: Record<string, unknown>;
  commercialRules: Record<string, unknown>;
  noticeRules: Record<string, unknown>;
  state: "draft" | "published" | "retired";
  publishedAt: string | null;
  createdAt: string;
}
export interface BookingCancellationPolicy {
  policyId: string;
  code: string;
  name: string;
  status: "active" | "retired";
  latestRevisionId: string | null;
  revisions: BookingCancellationPolicyRevision[];
}
export interface BookingCancellationPolicyMutationResult {
  policyId: string;
  revisionId?: string;
  revisionNumber?: number;
  state: "active" | "draft" | "published";
  publishedAt?: string;
}
export interface BookingCancellationPolicyRevisionInput {
  customerMode: "request_only" | "approval_required" | "self_service";
  publicTerms: string;
  approvalRules: Record<string, unknown>;
  commercialRules: Record<string, unknown>;
  noticeRules: Record<string, unknown>;
}

export interface BookingOfferLineItemInput {
  itemCode: string;
  quantity: number;
}

export interface BookingOfferAdjustmentInput {
  code: string;
  label: string;
  kind: "fee" | "discount" | "credit";
  amount: number;
  /** Required when the selected price list pins a tax profile. */
  allocationMethod?: "tax_code" | "proportional_to_lines" | "not_applicable";
  /** Required for tax_code allocation; omitted for proportional/not_applicable. */
  taxCode?: string | null;
}

export interface BookingOfferWriteRequest {
  priceListRevisionId: string;
  cancellationPolicyRevisionId: string;
  approvalPolicyRevisionId: string;
  currency: string;
  taxBasis: "inclusive" | "exclusive" | "not_applicable" | "to_be_confirmed";
  validUntil: string;
  lineItems: BookingOfferLineItemInput[];
  adjustments?: BookingOfferAdjustmentInput[];
  taxAmount: number;
  internalReason?: string;
}

export interface BookingOfferRevision {
  offerRevisionId: string;
  revisionNumber: number;
  draftRevisionId: string;
  priceListRevisionId: string;
  cancellationPolicyRevisionId: string;
  approvalPolicyRevisionId: string;
  approvalRequirements: Array<Record<string, unknown>>;
  currency: string;
  subtotal: string | number;
  taxAmount: string | number;
  totalAmount: string | number;
  validUntil: string;
  state: string;
  issuedAt: string | null;
  acceptedAt: string | null;
  terms: Record<string, unknown>;
}

export interface BookingOfferRecord {
  offerId: string;
  draftId: string;
  status: string;
  createdAt: string;
  currentRevision: BookingOfferRevision;
  revisionHistory: Array<{
    offerRevisionId: string;
    revisionNumber: number;
    draftRevisionId: string;
    state: string;
    createdAt: string;
    issuedAt: string | null;
    acceptedAt: string | null;
  }>;
  decisionHistory: Array<{
    decision: string;
    actorKind: string;
    actorMembershipId: string | null;
    reasonCode: string | null;
    occurredAt: string;
  }>;
}

export interface BookingOfferApprovalRequirement {
  ruleCode: string;
  condition: unknown;
  requiredApprovals: number;
  separationOfDuties: boolean;
  approvedCount: number;
  blocked: boolean;
  decisions: Array<{
    membershipId: string;
    decision: "approved" | "rejected" | "returned_for_changes";
    reason: string;
    decidedAt: string;
  }>;
}

export interface BookingOfferApprovalStatus {
  offerId: string;
  offerRevisionId: string;
  requirements: BookingOfferApprovalRequirement[];
}

export interface BookingOfferCreateResult {
  offerId: string;
  offerRevisionId: string;
  draftRevisionId: string;
  revisionNumber: number;
  state: string;
  currency: string;
  taxBasis: string;
  subtotal: string | number;
  taxAmount: string | number;
  totalAmount: string | number;
  validUntil: string;
}

export interface BookingOfferIssueResult extends Record<string, unknown> {
  acceptanceToken: string;
  offerId: string;
  offerRevisionId: string;
}
export interface BookingOfferEmailDelivery {
  deliveryId: string;
  offerRevisionId: string;
  status: "queued" | "sending" | "sent" | "failed" | "uncertain";
  attemptCount: number;
  manualRetryCount: number;
  nextAttemptAt: string;
  createdAt: string;
  updatedAt: string;
  sentAt: string | null;
  lastFailureCode: string | null;
  lastOperatorResolution: "confirmed_sent" | "confirmed_not_sent" | null;
  lastOperatorReason: string | null;
  lastOperatorAt: string | null;
  canReconcile: boolean;
  canRetry: boolean;
}
export interface BookingOfferEmailDeliveryPage {
  readonly data: BookingOfferEmailDelivery[];
  readonly meta: PageMeta & { counts: Record<string, number> };
}

export interface BookingConfirmationResult {
  bookingId: string;
  bookingCode: string;
  status: "confirmed";
  offerId: string;
  offerRevisionId: string;
  draftRevisionId: string;
  confirmedAt?: string;
  replayed: boolean;
}


export type BookingTaxTreatment = "percentage" | "zero_rated" | "exempt" | "out_of_scope" | "manual";
export interface BookingTaxCode {
  taxCode: string;
  label: string;
  treatment: BookingTaxTreatment;
  rate: number | null;
}
export interface BookingTaxProfileRevision {
  revisionId: string;
  revisionNumber: number;
  jurisdictionCode: string | null;
  registrationIdentifier: string | null;
  currency: string;
  taxBasis: "inclusive" | "exclusive" | "not_applicable";
  roundingMethod: "per_line" | "per_tax_code" | "invoice_total";
  roundingScale: number;
  taxCodes: BookingTaxCode[];
  effectiveFrom: string | null;
  effectiveUntil: string | null;
  state: "draft" | "published" | "retired";
  publishedAt: string | null;
  createdAt: string;
}
export interface BookingTaxProfile {
  taxProfileId: string;
  code: string;
  name: string;
  status: "active" | "retired";
  createdAt: string;
  latestRevisionId: string | null;
  revisions: BookingTaxProfileRevision[];
}
export interface BookingTaxProfileMutationResult {
  taxProfileId: string;
  revisionId?: string;
  revisionNumber?: number;
  state: "draft" | "published";
  publishedAt?: string;
  taxCodeCount?: number;
}
export interface BookingTaxProfileRevisionInput {
  jurisdictionCode: string | null;
  registrationIdentifier: string | null;
  currency: string;
  taxBasis: "inclusive" | "exclusive" | "not_applicable";
  roundingMethod: "per_line" | "per_tax_code" | "invoice_total";
  roundingScale: number;
  effectiveFrom: string | null;
  effectiveUntil: string | null;
  taxCodes: BookingTaxCode[];
}

export interface BookingPriceListItem {
  itemCode: string;
  label: string;
  unit: string;
  unitAmount: number;
  taxCode: string | null;
  quantityMin: number;
  quantityMax: number | null;
}
export interface BookingPriceListRevision {
  revisionId: string;
  revisionNumber: number;
  currency: string;
  taxBasis: "inclusive" | "exclusive" | "not_applicable" | "to_be_confirmed";
  taxProfileRevisionId?: string | null;
  state: "draft" | "published" | "retired";
  effectiveFrom: string | null;
  effectiveUntil: string | null;
  publishedAt: string | null;
  createdAt: string;
  items: BookingPriceListItem[];
}
export interface BookingPriceList {
  priceListId: string;
  code: string;
  name: string;
  scopeKind: "organization" | "venue" | "space";
  scopeVenueId: string | null;
  scopeSpaceId: string | null;
  status: "active" | "retired";
  createdAt: string;
  latestRevisionId: string | null;
  revisions: BookingPriceListRevision[];
}
export interface BookingPriceListMutationResult {
  priceListId: string;
  revisionId?: string;
  revisionNumber?: number;
  state: "draft" | "published";
  publishedAt?: string;
  itemCount?: number;
}

export interface BookingApprovalRule {
  code: string;
  condition:
    | { kind: "always" }
    | { kind: "total_at_least"; amount: number; currency: string }
    | { kind: "discount_at_least"; amount: number }
    | { kind: "adjustment_present"; adjustmentKind?: "fee" | "discount" | "credit" };
  requiredApprovals: number;
  permission: "booking.approve";
  separationOfDuties: boolean;
}

export interface BookingApprovalPolicyRevision {
  revisionId: string;
  revisionNumber: number;
  state: "draft" | "published" | "retired";
  rules: BookingApprovalRule[];
  publishedAt: string | null;
  createdAt: string;
}

export interface BookingApprovalPolicy {
  policyId: string;
  code: string;
  name: string;
  status: "active" | "retired";
  createdAt: string;
  latestRevisionId: string | null;
  revisions: BookingApprovalPolicyRevision[];
}

export interface BookingApprovalPolicyMutationResult {
  policyId: string;
  revisionId?: string;
  revisionNumber?: number;
  state: "draft" | "published" | "active";
  publishedAt?: string;
}


export interface PublicBookingOffer {
  offerId: string;
  status: "issued" | "expired";
  revisionNumber: number;
  currency: string;
  subtotal: number;
  taxAmount: number;
  totalAmount: number;
  validUntil: string;
  terms: {
    requestedStart: string | null;
    requestedEnd: string | null;
    timezone: string | null;
    taxBasis: string;
    lineItems: Array<{ label: string; unit: string; quantity: number; unitAmount: number; lineTotal: number }>;
    adjustments: Array<{ label: string; kind: string; amount: number }>;
    spaces: Array<{ code: string; name: string; blockKind: string; startsAt: string; endsAt: string; requestedCapacity: number | null }>;
    resources: Array<{ label: string; requestedQuantity: number }>;
    cancellationTerms: string | null;
  };
}
export interface PageMeta {
  limit: number;
  offset: number;
  totalCount: number;
  counts?: Record<string, number>;
}

export const api = {
  getPublicBookingOffer: (offerId: string, token: string) =>
    request<Envelope<PublicBookingOffer>>(
      `/public/booking-offers/${encodeURIComponent(offerId)}`,
      { credentials: "omit", extraHeaders: { "X-External-Booking-Token": token } },
    ),
  acceptPublicBookingOffer: (
    offerId: string,
    token: string,
    body: { acceptanceName: string; acceptanceNote?: string },
    requestKey: string,
  ) =>
    request<Envelope<Record<string, unknown>>>(
      `/booking-offers/${encodeURIComponent(offerId)}/accept`,
      {
        method: "POST", body, idempotent: true, idempotencyKey: requestKey,
        credentials: "omit",
        skipCsrf: true,
        extraHeaders: { "X-External-Booking-Token": token },
      },
    ),
  rejectPublicBookingOffer: (
    offerId: string,
    token: string,
    body: { reasonCode: string; reason: string; note?: string },
    requestKey: string,
  ) =>
    request<Envelope<Record<string, unknown>>>(
      `/booking-offers/${encodeURIComponent(offerId)}/reject`,
      {
        method: "POST", body, idempotent: true, idempotencyKey: requestKey,
        credentials: "omit",
        skipCsrf: true,
        extraHeaders: { "X-External-Booking-Token": token },
      },
    ),
  login: (body: { email: string; password: string; organizationSlug: string }) =>
    request<Envelope<{ csrfToken: string; expiresAt: string }>>("/auth/session", { method: "POST", body }),
  me: () => request<Envelope<Principal>>("/me"),
  logout: () => request<void>("/auth/session", { method: "DELETE" }),
  getBookingInquiryCapabilities: (organizationId: string) =>
    request<Envelope<BookingInquiryCapabilities>>(
      `/organizations/${encodeURIComponent(organizationId)}/booking-inquiry-capabilities`,
    ),
  getBookingInquiryAssignees: (organizationId: string) =>
    request<Envelope<BookingInquiryAssignee[]>>(
      `/organizations/${encodeURIComponent(organizationId)}/booking-inquiry-assignees`,
    ),
  getBookingInquiries: (
    organizationId: string,
    options: { status?: string; assignedToMembershipId?: string; limit?: number; offset?: number } = {},
  ) => {
    const query = new URLSearchParams();
    if (options.status) query.set("status", options.status);
    if (options.assignedToMembershipId) query.set("assignedToMembershipId", options.assignedToMembershipId);
    if (options.limit !== undefined) query.set("limit", String(options.limit));
    if (options.offset !== undefined) query.set("offset", String(options.offset));
    return request<Envelope<BookingInquiryListItem[]> & { meta: PageMeta }>(
      `/organizations/${encodeURIComponent(organizationId)}/booking-inquiries${query.size ? `?${query.toString()}` : ""}`,
    );
  },
  getBookingInquiry: (inquiryId: string) =>
    request<Envelope<BookingInquiryDetail>>(`/booking-inquiries/${encodeURIComponent(inquiryId)}`),
  getBookingDraft: (draftId: string) =>
    request<Envelope<BookingDraftDetail>>(`/booking-drafts/${encodeURIComponent(draftId)}`),
  createBookingOffer: (draftRevisionId: string, body: BookingOfferWriteRequest) =>
    request<Envelope<BookingOfferCreateResult>>(
      `/booking-draft-revisions/${encodeURIComponent(draftRevisionId)}/offers`,
      { method: "POST", body, idempotent: true },
    ),
  createBookingOfferSuccessor: (
    offerId: string,
    body: BookingOfferWriteRequest & { draftRevisionId: string; supersedeCurrentOffer?: boolean },
  ) =>
    request<Envelope<BookingOfferCreateResult>>(
      `/booking-offers/${encodeURIComponent(offerId)}/revisions`,
      { method: "POST", body, idempotent: true },
    ),
  getBookingOffer: (offerId: string) =>
    request<Envelope<BookingOfferRecord>>(`/booking-offers/${encodeURIComponent(offerId)}`),
  issueBookingOffer: (offerId: string, requestKey?: string) =>
    request<Envelope<BookingOfferIssueResult>>(
      `/booking-offers/${encodeURIComponent(offerId)}/issue`,
      { method: "POST", body: {}, idempotent: true, idempotencyKey: requestKey },
    ),
  queueBookingOfferEmail: (offerId: string, acceptanceToken: string, requestKey?: string) =>
    request<Envelope<{ deliveryId: string; status: string; created: boolean }>>(
      `/booking-offers/${encodeURIComponent(offerId)}/email`,
      { method: "POST", body: { acceptanceToken }, idempotent: true, idempotencyKey: requestKey },
    ),
  getBookingOfferEmailDeliveries: (offerId: string, options: { status?: string; limit?: number; offset?: number } = {}) => {
    const query = new URLSearchParams();
    if (options.status) query.set("status", options.status);
    if (options.limit !== undefined) query.set("limit", String(options.limit));
    if (options.offset !== undefined) query.set("offset", String(options.offset));
    return request<BookingOfferEmailDeliveryPage>(
      `/booking-offers/${encodeURIComponent(offerId)}/email-deliveries${query.size ? `?${query.toString()}` : ""}`,
    );
  },
  reconcileBookingOfferEmailDelivery: (
    deliveryId: string,
    body: { resolution: "confirmed_sent" | "confirmed_not_sent"; reason: string; providerMessageReference?: string },
    requestKey?: string,
  ) => request<Envelope<{ deliveryId: string; status: string; canRetry: boolean }>>(
    `/booking-offer-email-deliveries/${encodeURIComponent(deliveryId)}/reconcile`,
    { method: "POST", body, idempotent: true, idempotencyKey: requestKey },
  ),
  retryBookingOfferEmailDelivery: (deliveryId: string, reason: string, requestKey?: string) =>
    request<Envelope<{ deliveryId: string; status: string; manualRetryCount: number }>>(
      `/booking-offer-email-deliveries/${encodeURIComponent(deliveryId)}/retry`,
      { method: "POST", body: { reason }, idempotent: true, idempotencyKey: requestKey },
    ),

  getBookingTaxProfiles: () =>
    request<Envelope<BookingTaxProfile[]>>("/organization/booking-tax-profiles"),
  createBookingTaxProfile: (body: {
    code: string; name: string; jurisdictionCode?: string | null; registrationIdentifier?: string | null;
    currency: string; taxBasis: "inclusive" | "exclusive" | "not_applicable";
  }) =>
    request<Envelope<BookingTaxProfileMutationResult>>(
      "/organization/booking-tax-profiles", { method: "POST", body, idempotent: true },
    ),
  createBookingTaxProfileRevision: (taxProfileId: string, body: Omit<BookingTaxProfileRevisionInput, "taxCodes">) =>
    request<Envelope<BookingTaxProfileMutationResult>>(
      `/booking-tax-profiles/${encodeURIComponent(taxProfileId)}/revisions`,
      { method: "POST", body, idempotent: true },
    ),
  updateBookingTaxProfileDraftRevision: (taxProfileId: string, revisionId: string, body: BookingTaxProfileRevisionInput) =>
    request<Envelope<BookingTaxProfileMutationResult>>(
      `/booking-tax-profiles/${encodeURIComponent(taxProfileId)}/revisions/${encodeURIComponent(revisionId)}`,
      { method: "PUT", body, idempotent: true },
    ),
  publishBookingTaxProfileRevision: (taxProfileId: string, revisionId: string) =>
    request<Envelope<BookingTaxProfileMutationResult>>(
      `/booking-tax-profiles/${encodeURIComponent(taxProfileId)}/revisions/${encodeURIComponent(revisionId)}/publish`,
      { method: "POST", body: {}, idempotent: true },
    ),
  setBookingPriceListTaxProfileRevision: (priceListId: string, revisionId: string, taxProfileRevisionId: string | null) =>
    request<Envelope<{ priceListId: string; revisionId: string; taxProfileRevisionId: string | null; state: "draft" }>>(
      `/booking-price-lists/${encodeURIComponent(priceListId)}/revisions/${encodeURIComponent(revisionId)}/tax-profile`,
      { method: "PUT", body: { taxProfileRevisionId }, idempotent: true },
    ),
  getBookingPriceLists: () =>
    request<Envelope<BookingPriceList[]>>("/organization/booking-price-lists"),
  createBookingPriceList: (body: {
    code: string; name: string; scopeKind?: "organization" | "venue" | "space";
    scopeVenueId?: string | null; scopeSpaceId?: string | null;
    currency: string; taxBasis: "inclusive" | "exclusive" | "not_applicable" | "to_be_confirmed";
  }) =>
    request<Envelope<BookingPriceListMutationResult>>(
      "/organization/booking-price-lists", { method: "POST", body, idempotent: true },
    ),
  createBookingPriceListRevision: (
    priceListId: string,
    body: {
      currency: string; taxBasis: "inclusive" | "exclusive" | "not_applicable" | "to_be_confirmed";
      effectiveFrom?: string | null; effectiveUntil?: string | null;
    },
  ) =>
    request<Envelope<BookingPriceListMutationResult>>(
      `/booking-price-lists/${encodeURIComponent(priceListId)}/revisions`,
      { method: "POST", body, idempotent: true },
    ),
  updateBookingPriceListDraftRevision: (
    priceListId: string,
    revisionId: string,
    body: {
      currency: string; taxBasis: "inclusive" | "exclusive" | "not_applicable" | "to_be_confirmed";
      effectiveFrom?: string | null; effectiveUntil?: string | null;
      items: Array<{
        itemCode: string; label: string; unit: string; unitAmount: number;
        taxCode?: string | null; quantityMin?: number; quantityMax?: number | null;
      }>;
    },
  ) =>
    request<Envelope<BookingPriceListMutationResult>>(
      `/booking-price-lists/${encodeURIComponent(priceListId)}/revisions/${encodeURIComponent(revisionId)}`,
      { method: "PUT", body, idempotent: true },
    ),
  publishBookingPriceListRevision: (priceListId: string, revisionId: string) =>
    request<Envelope<BookingPriceListMutationResult>>(
      `/booking-price-lists/${encodeURIComponent(priceListId)}/revisions/${encodeURIComponent(revisionId)}/publish`,
      { method: "POST", body: {}, idempotent: true },
    ),
  getBookingApprovalPolicies: () =>
    request<Envelope<BookingApprovalPolicy[]>>("/organization/booking-approval-policies"),
  createBookingApprovalPolicy: (body: { code: string; name: string }) =>
    request<Envelope<BookingApprovalPolicyMutationResult>>(
      "/organization/booking-approval-policies",
      { method: "POST", body, idempotent: true },
    ),
  createBookingApprovalPolicyRevision: (policyId: string, rules: BookingApprovalRule[]) =>
    request<Envelope<BookingApprovalPolicyMutationResult>>(
      `/booking-approval-policies/${encodeURIComponent(policyId)}/revisions`,
      { method: "POST", body: { rules }, idempotent: true },
    ),
  updateBookingApprovalPolicyDraftRevision: (
    policyId: string,
    revisionId: string,
    rules: BookingApprovalRule[],
  ) =>
    request<Envelope<BookingApprovalPolicyMutationResult>>(
      `/booking-approval-policies/${encodeURIComponent(policyId)}/revisions/${encodeURIComponent(revisionId)}`,
      { method: "PUT", body: { rules }, idempotent: true },
    ),
  publishBookingApprovalPolicyRevision: (policyId: string, revisionId: string) =>
    request<Envelope<BookingApprovalPolicyMutationResult>>(
      `/booking-approval-policies/${encodeURIComponent(policyId)}/revisions/${encodeURIComponent(revisionId)}/publish`,
      { method: "POST", body: {}, idempotent: true },
    ),

  getBookingCancellationPolicies: () =>
    request<Envelope<BookingCancellationPolicy[]>>("/organization/booking-cancellation-policies"),
  createBookingCancellationPolicy: (body: { code: string; name: string }) =>
    request<Envelope<BookingCancellationPolicyMutationResult>>(
      "/organization/booking-cancellation-policies", { method: "POST", body, idempotent: true },
    ),
  createBookingCancellationPolicyRevision: (policyId: string, body: BookingCancellationPolicyRevisionInput) =>
    request<Envelope<BookingCancellationPolicyMutationResult>>(
      `/booking-cancellation-policies/${encodeURIComponent(policyId)}/revisions`,
      { method: "POST", body, idempotent: true },
    ),
  updateBookingCancellationPolicyDraftRevision: (
    policyId: string, revisionId: string, body: BookingCancellationPolicyRevisionInput,
  ) =>
    request<Envelope<BookingCancellationPolicyMutationResult>>(
      `/booking-cancellation-policies/${encodeURIComponent(policyId)}/revisions/${encodeURIComponent(revisionId)}`,
      { method: "PUT", body, idempotent: true },
    ),
  publishBookingCancellationPolicyRevision: (policyId: string, revisionId: string) =>
    request<Envelope<BookingCancellationPolicyMutationResult>>(
      `/booking-cancellation-policies/${encodeURIComponent(policyId)}/revisions/${encodeURIComponent(revisionId)}/publish`,
      { method: "POST", body: {}, idempotent: true },
    ),
  getBookingOfferApprovals: (offerId: string) =>
    request<Envelope<BookingOfferApprovalStatus>>(
      `/booking-offers/${encodeURIComponent(offerId)}/approvals`,
    ),
  decideBookingOfferApproval: (
    offerId: string,
    body: {
      offerRevisionId: string;
      ruleCode: string;
      decision: "approved" | "rejected" | "returned_for_changes";
      reason: string;
    },
  ) =>
    request<Envelope<Record<string, unknown>>>(
      `/booking-offers/${encodeURIComponent(offerId)}/approvals`,
      { method: "POST", body, idempotent: true },
    ),
  confirmBookingFromOffer: (
    draftRevisionId: string,
    body: { expectedDraftRevisionId: string; confirmationReason: string },
  ) =>
    request<Envelope<BookingConfirmationResult>>(
      `/booking-draft-revisions/${encodeURIComponent(draftRevisionId)}/confirm`,
      { method: "POST", body, idempotent: true },
    ),
  createBookingDraftRevision: (
    draftId: string,
    body: {
      expectedRevisionNumber: number;
      values: Record<string, unknown>;
      requestedStart: string | null;
      requestedEnd: string | null;
      timezone: string;
      spaceLines: Array<{
        venueSpaceId: string;
        startsAt: string;
        endsAt: string;
        blockKind: "setup" | "rehearsal" | "event_use" | "teardown" | "buffer";
        requestedCapacity?: number;
      }>;
      resourceLines: Array<{
        resourceTypeId: string;
        requestedQuantity: number;
        values?: Record<string, unknown>;
      }>;
      changeReason: string;
    },
  ) =>
    request<Envelope<BookingDraftRevisionResult>>(
      `/booking-drafts/${encodeURIComponent(draftId)}/revisions`,
      { method: "POST", body, idempotent: true },
    ),
  assignBookingInquiry: (inquiryId: string, assignedToMembershipId: string | null) =>
    request<Envelope<Record<string, unknown>>>(
      `/booking-inquiries/${encodeURIComponent(inquiryId)}/assignment`,
      { method: "POST", body: { assignedToMembershipId }, idempotent: true },
    ),
  changeBookingInquiryStatus: (
    inquiryId: string,
    body: { status: "received" | "under_review" | "declined" | "spam"; reason: string },
  ) =>
    request<Envelope<Record<string, unknown>>>(
      `/booking-inquiries/${encodeURIComponent(inquiryId)}/status`,
      { method: "POST", body, idempotent: true },
    ),
  convertBookingInquiryToDraft: (inquiryId: string) =>
    request<Envelope<BookingInquiryConversion>>(
      `/booking-inquiries/${encodeURIComponent(inquiryId)}/create-draft`,
      { method: "POST", body: {}, idempotent: true },
    ),
  addBookingInquiryAnnotation: (inquiryId: string, annotation: string) =>
    request<Envelope<Record<string, unknown>>>(
      `/booking-inquiries/${encodeURIComponent(inquiryId)}/annotations`,
      { method: "POST", body: { annotation }, idempotent: true },
    ),
  getEmailConfiguration: () => request<Envelope<EmailConfiguration | null>>("/organization/delivery/email/configuration"),
  saveEmailConfiguration: (body: Record<string, unknown>) =>
    request<Envelope<unknown>>("/organization/delivery/email/configuration", { method: "POST", body, idempotent: true }),
  sendEmailTest: (recipient: string) =>
    request<Envelope<{ status?: string; messageId?: string }>>("/organization/delivery/email/test", {
      method: "POST", body: { recipient }, idempotent: true,
    }),
  getResendWebhookConfiguration: () =>
    request<Envelope<ResendWebhookConfiguration>>("/organization/delivery/email/resend-webhook"),
  prepareResendWebhook: () =>
    request<Envelope<{ endpointId: string; enabled: boolean; callbackUrl: string }>>(
      "/organization/delivery/email/resend-webhook/prepare",
      { method: "POST", body: {}, idempotent: true },
    ),
  activateResendWebhook: (endpointId: string, signingSecret: string) =>
    request<Envelope<{ endpointId: string; enabled: boolean; updatedAt: string }>>(
      "/organization/delivery/email/resend-webhook/activate",
      { method: "POST", body: { endpointId, signingSecret }, idempotent: true },
    ),
  getCampaigns: (options: { status?: string; limit?: number; offset?: number } = {}) => {
    const query = new URLSearchParams();
    if (options.status) query.set("status", options.status);
    if (options.limit !== undefined) query.set("limit", String(options.limit));
    if (options.offset !== undefined) query.set("offset", String(options.offset));
    return request<Envelope<CampaignListItem[]> & { meta: PageMeta }>(
      `/event-notification-campaigns${query.size ? `?${query.toString()}` : ""}`,
    );
  },
  getCampaignProgress: (campaignId: string) =>
    request<Envelope<CampaignProgress>>(`/event-notification-campaigns/${encodeURIComponent(campaignId)}`),
  getCampaignDeliveries: (campaignId: string, options: { status?: string; limit?: number; offset?: number } = {}) => {
    const query = new URLSearchParams();
    if (options.status) query.set("status", options.status);
    if (options.limit !== undefined) query.set("limit", String(options.limit));
    if (options.offset !== undefined) query.set("offset", String(options.offset));
    return request<Envelope<DeliveryAttempt[]> & { meta: PageMeta }>(
      `/event-notification-campaigns/${encodeURIComponent(campaignId)}/deliveries${query.size ? `?${query.toString()}` : ""}`,
    );
  },
  reconcileDeliveryAttempt: (attemptId: string, body: { resolution: string; reason: string }) =>
    request<Envelope<{ attemptId: string; previousStatus: string; status: string; campaignStatus: string }>>(
      `/notification-delivery-attempts/${encodeURIComponent(attemptId)}/reconcile`,
      { method: "POST", body, idempotent: true },
    ),
  retryDeliveryAttempt: (attemptId: string, reason: string) =>
    request<Envelope<{ attemptId: string; previousAttemptId: string; attemptNumber: number; status: string }>>(
      `/notification-delivery-attempts/${encodeURIComponent(attemptId)}/retry`,
      { method: "POST", body: { reason }, idempotent: true },
    ),
  getCampaignReview: (campaignId: string) =>
    request<Envelope<CampaignReview>>(`/event-notification-campaigns/${encodeURIComponent(campaignId)}/review`),
  confirmCampaign: (campaignId: string) =>
    request<Envelope<unknown>>(`/event-notification-campaigns/${encodeURIComponent(campaignId)}/confirm`, {
      method: "POST", body: {}, idempotent: true,
    }),
  queueCampaign: (campaignId: string) =>
    request<Envelope<unknown>>(`/event-notification-campaigns/${encodeURIComponent(campaignId)}/queue`, {
      method: "POST", body: {}, idempotent: true,
    }),
  cancelCampaign: (campaignId: string) =>
    request<Envelope<unknown>>(`/event-notification-campaigns/${encodeURIComponent(campaignId)}/cancel`, {
      method: "POST", body: {}, idempotent: true,
    }),
};
