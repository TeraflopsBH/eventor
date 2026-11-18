export interface ApiProblem {
  readonly status: number;
  readonly code: string;
  readonly title: string;
  readonly requestId?: string;
}

export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly requestId?: string;

  constructor(message: string, status: number, code: string, requestId?: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
    this.requestId = requestId;
  }
}

const apiBase = (import.meta.env?.VITE_API_BASE_URL || "/api").replace(/\/$/, "");
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
    method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
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
  userLocale: "bs-BA" | "en" | null;
  organizationDefaultLocale: "bs-BA" | "en";
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

export interface GuestInvitationDeliveryAttempt {
  attemptId: string;
  deliveryId: string;
  attemptNumber: number;
  status: "sending" | "sent" | "failed" | "uncertain";
  failureCode: string | null;
  providerMessageReference: string | null;
  startedAt: string;
  completedAt: string | null;
  retryScheduled: boolean;
}

export interface GuestInvitationEvent {
  eventId: string;
  eventCode: string;
  title: string;
  status: string;
  startsAt: string | null;
  endsAt: string | null;
  timezone: string;
  scheduleRevisionId: string | null;
  rsvpPolicyRevisionId: string | null;
  eligibleParticipationCount: number;
  invitationCount: number;
}

export interface GuestInvitationParticipation {
  participationId: string;
  displayName: string;
  participationCode: string | null;
  categoryCode: string | null;
  status: string;
  emailReady: boolean;
  invitationId: string | null;
  invitationStatus: string | null;
  invitationRevisionNumber: number | null;
  deliveryStatus: string | null;
  currentResponseId: string | null;
  currentResponse: "accepted" | "declined" | "tentative" | null;
  responseReceivedAt: string | null;
}

export interface GuestInvitationRsvpHistoryEntry {
  responseId: string; sequenceNumber: number; response: "accepted" | "declined" | "tentative";
  sourceChannel: string; respondentKind: string; receivedAt: string; recordedAt: string;
  actorMembershipId: string | null; correctionOfResponseId: string | null; correctionReason: string | null;
  invitationId: string | null; scheduleRevisionId: string | null;
}

export interface GuestInvitation {
  invitationId: string;
  invitationRevisionId: string;
  eventId: string;
  eventTitle: string;
  eventStatus: string;
  startsAt: string;
  endsAt: string;
  timezone: string;
  locale: "bs-BA" | "en";
  allowedResponses: Array<"accepted" | "declined" | "tentative">;
  responseDeadline: string | null;
  responseChangeAllowed: boolean;
  currentResponse: "accepted" | "declined" | "tentative" | null;
  presentationSnapshot: {
    greeting?: string;
    venueName?: string;
    venueAddress?: string;
    directions?: string;
    additionalInfo?: string;
    accessibility?: string;
    scheduleLabel?: string;
    hostDisplayName?: string;
  };
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
    fields: PublicBookingFormField[];
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

export interface BookingDraftAllocationSpaceOption {
  venueSpaceId: string;
  venueId: string;
  venueName: string;
  code: string;
  name: string;
  spaceKind: "building_area" | "level_area" | "room" | "zone" | "other";
  capacity: number | null;
}

export interface BookingDraftAllocationResourceOption {
  resourceTypeId: string;
  code: string;
  name: string;
  unitLabel: string;
  capacity: number;
}

export interface BookingDraftAllocationOptions {
  spaces: BookingDraftAllocationSpaceOption[];
  resources: BookingDraftAllocationResourceOption[];
}

export interface BookingDraftAllocationSpaceConflict {
  kind: "maintenance" | "confirmed_booking" | "active_hold";
  status: "held" | "confirmed" | "blocked";
  startsAt: string;
  endsAt: string;
}

export interface BookingDraftSpaceAvailabilityResult {
  index: number;
  venueSpaceId: string;
  available: boolean;
  reason: "space_unavailable" | "space_conflict" | null;
  conflicts: BookingDraftAllocationSpaceConflict[];
}

export interface BookingDraftSpaceAlternative {
  venueSpaceId: string;
  venueId: string;
  venueName: string;
  code: string;
  name: string;
  capacity: number | null;
}

export interface BookingDraftResourcePoolAvailability {
  resourcePoolId: string;
  code: string;
  name: string;
  venueName: string;
  capacity: number;
  availableQuantity: number;
}

export interface BookingDraftResourceAvailabilityResult {
  index: number;
  resourceTypeId: string;
  requestedQuantity: number;
  totalRequestedQuantity: number;
  availableQuantity: number | null;
  checked: boolean;
  available: boolean | null;
  reason: "resource_interval_missing" | "resource_interval_invalid" | "resource_unavailable" | "no_active_resource_pools" | "resource_capacity_conflict" | null;
}

export interface BookingDraftAllocationAvailabilityPreview {
  spaces: BookingDraftSpaceAvailabilityResult[];
  resources: BookingDraftResourceAvailabilityResult[];
  resourceIntervalChecked: boolean;
  spaceAlternatives: Array<{ index: number; alternatives: BookingDraftSpaceAlternative[] }>;
  resourcePools: Array<{ index: number; pools: BookingDraftResourcePoolAvailability[] }>;
  advisoryOnly: true;
  checkedAt: string;
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


export interface BookingCancellationDecisionItem {
  decision: "approved" | "rejected" | "returned_for_changes";
  reason: string;
  decidedAt: string;
}
export interface BookingCancellationRequestQueueItem {
  requestId: string;
  bookingId: string;
  bookingCode: string;
  bookingStatus: string;
  requesterKind: string;
  status: string;
  reasonCode: string;
  requestedAt: string;
  resolvedAt: string | null;
  policyRevisionId: string | null;
  decisions: BookingCancellationDecisionItem[];
}
export interface BookingCancellationRequestDetail {
  requestId: string;
  bookingId: string;
  bookingRevision: number;
  requesterKind: string;
  status: string;
  reasonCode: string;
  explanation: string | null;
  requestedAt: string;
  resolvedAt: string | null;
  policyRevisionId: string | null;
  decisions: BookingCancellationDecisionItem[];
}
export interface BookingCancellationRequestQueue {
  items: BookingCancellationRequestQueueItem[];
  total: number;
  limit: number;
  offset: number;
}
export interface BookingCancellationPreview {
  bookingId: string;
  bookingCode: string;
  bookingStatus: string;
  bookingRevision: number;
  cancellationRequestId: string | null;
  requestStatus: string | null;
  policyRevisionId: string;
  customerMode: "request_only" | "approval_required" | "self_service";
  publicTerms: string;
  approvalRules: Record<string, unknown>;
  commercialRules: Record<string, unknown>;
  noticeRules: Record<string, unknown>;
  priceSnapshot: Record<string, unknown>;
  reservationRelease: {
    resourceReservationIds: string[];
    spaceReservationIds: string[];
    resourceReservationCount: number;
    spaceReservationCount: number;
    totalReservationCount: number;
  };
  commercialEvaluation: {
    state: "manual_review_required";
    automaticFeeCalculation: false;
    calculatedFee: null;
    moneyMovementExecuted: false;
    note: string;
  };
  selfServiceExecutionAvailable: false;
}
export interface ExternalBookingActionCapability {
  capabilityId: string;
  bookingId: string;
  bookingContactId: string;
  action: "booking_cancellation_request" | "booking_cancellation_status";
  expiresAt: string;
  maxUses: number;
  state: string;
  token: string;
}
export interface ExternalBookingActionContext {
  bookingCode: string;
  bookingStatus: string;
  action: "booking_cancellation_request" | "booking_cancellation_status";
  expiresAt: string;
  cancellationTerms: string | null;
  latestCancellationRequest: {
    requestId: string;
    status: string;
    requestedAt: string;
    resolvedAt: string | null;
  } | null;
}
export interface ExternalBookingCancellationSubmission {
  requestId: string;
  bookingCode: string;
  status: string;
  requestedAt: string;
  replayed: boolean;
  statusToken: string;
}
export interface ExternalBookingCancellationStatus {
  requestId: string;
  bookingCode: string;
  status: string;
  requestedAt: string;
  resolvedAt: string | null;
}

export interface BookingCancellationExecutionResult {
  bookingId: string;
  cancellationRequestId: string;
  effectId: string;
  followupId: string;
  status: "cancelled";
  effectiveAt: string;
  reservationsReleased: number;
  commercialEvaluationState: "manual_review_required";
  moneyMovementExecuted: false;
  replayed: boolean;
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
  customerLocale: "bs-BA" | "en";
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
export type BookingFormFieldType = PublicBookingFormField["type"];
export interface BookingFormField extends Omit<PublicBookingFormField, "type"> { type: BookingFormFieldType; }
export interface BookingFormTranslation {
  formName: string;
  fields: Record<string, {
    label?: string; description?: string; helpText?: string; placeholder?: string;
    options?: Record<string, string>;
  }>;
}
export interface BookingFormSchema {
  schemaVersion?: 1;
  fields: BookingFormField[];
  contentTranslations?: Partial<Record<"bs-BA" | "en", BookingFormTranslation>>;
}
export interface BookingFormRevision {
  revisionId: string; revisionNumber: number; locale: "bs-BA" | "en";
  fieldSchema: BookingFormSchema; state: "draft" | "published"; publishedAt: string | null; createdAt: string;
}
export interface BookingForm {
  formId: string; formCode: string; name: string; scopeKind: string;
  scopeVenueId: string | null; scopeSpaceId: string | null; status: string;
  revisions: BookingFormRevision[];
}
export interface BookingFormMutationResult {
  formId: string; revisionId: string; revisionNumber: number; state: "draft" | "published"; publishedAt?: string;
}

export interface PublicBookingFormField {
  code: string;
  type: "text" | "textarea" | "email" | "phone" | "number" | "date" | "datetime" | "time" | "select" | "multiselect" | "checkbox";
  label?: string;
  description?: string;
  helpText?: string;
  placeholder?: string;
  required?: boolean;
  options?: Array<{ value: string; label: string }>;
  minLength?: number;
  maxLength?: number;
  min?: number;
  max?: number;
  integer?: boolean;
  minItems?: number;
  maxItems?: number;
}
export interface PublicBookingForm {
  organizationId: string;
  organizationSlug: string;
  organizationName: string;
  defaultLocale: "bs-BA" | "en";
  defaultTimezone: string;
  formCode: string;
  formName: string;
  formRevisionId: string;
  revisionNumber: number;
  /** Language of vendor-authored labels/options in this immutable form revision. */
  locale: "bs-BA" | "en";
  fieldSchema: {
    schemaVersion?: number;
    fields: PublicBookingFormField[];
    contentTranslations?: Partial<Record<"bs-BA" | "en", {
      formName: string;
      fields: Record<string, {
        label?: string;
        description?: string;
        helpText?: string;
        placeholder?: string;
        options?: Record<string, string>;
      }>;
    }>>;
  };
  publishedAt: string;
}
export interface PublicBookingInquirySubmission {
  formCode: string;
  formRevisionId: string;
  customerLocale: "bs-BA" | "en";
  requester: { displayName: string; email?: string; phone?: string };
  requested: { startAt?: string; endAt?: string; timezone?: string; spaceCodes?: string[] };
  answers: Record<string, unknown>;
}
export interface PublicBookingInquirySubmissionResult {
  inquiryId: string;
  publicReference: string;
  status: string;
  replayed: boolean;
}

export interface PageMeta {
  limit: number;
  offset: number;
  totalCount: number;
  counts?: Record<string, number>;
}

export interface OrganizerEvent {
  eventId: string;
  eventCode: string;
  guestRegistryEnabled?: boolean;
  title: string;
  descriptionInternal?: string | null;
  status: "draft" | "planned" | "ready_for_approval" | "approved" | "scheduled" | "active" | "completed" | "cancelled" | "postponed" | "archived";
  currentRevision: number;
  detailsRevision: number;
  timezoneName?: string;
  createdAt?: string;
  updatedAt?: string;
  scheduleRevisionId?: string | null;
  scheduleRevisionNumber?: number | null;
  startsAt?: string | null;
  endsAt?: string | null;
  scheduleTimezoneName?: string | null;
  venueSummary?: Record<string, unknown>;
}

export type OrganizerEventAction = "plan" | "submit" | "approve" | "return_to_planning" | "publish" | "start" | "complete";

export interface OrganizerEventTransitionInput {
  action: OrganizerEventAction;
  expectedDetailsRevision: number;
  expectedScheduleRevision: number;
}

export interface CreateOrganizerEventInput {
  eventCode: string;
  title: string;
  descriptionInternal?: string | null;
  startsAt: string;
  endsAt: string;
  timezoneName: string;
  venueSummary?: Record<string, unknown>;
  scheduleSnapshot?: Record<string, unknown>;
}

export interface UpdateOrganizerEventDetailsInput {
  expectedDetailsRevision: number;
  title: string;
  descriptionInternal?: string | null;
}

export interface OrganizerEventSession {
  sessionId: string;
  code: string;
  title: string;
  status: "planned" | "scheduled" | "active" | "completed" | "cancelled";
  startsAt: string | null;
  endsAt: string | null;
  timezoneName: string;
}

export interface OrganizerEventSessionDetails extends OrganizerEventSession {
  detailsRevision: number;
}

export type OrganizerEventSessionAction = "schedule" | "start" | "complete";

export interface OrganizerEventSessionTransitionInput {
  action: OrganizerEventSessionAction;
  expectedDetailsRevision: number;
  expectedScheduleRevision: number;
}

export interface UpdateOrganizerEventSessionInput {
  expectedDetailsRevision: number;
  title: string;
  startsAt: string | null;
  endsAt: string | null;
}

export interface CreateOrganizerEventSessionInput {
  code: string;
  title: string;
  startsAt?: string;
  endsAt?: string;
}

function organizerEventSessionsPath(organizationId: string, eventId: string): string {
  return `/organizations/${encodeURIComponent(organizationId)}/events/${encodeURIComponent(eventId)}/sessions`;
}

export interface OrganizerEventArchiveResult {
  eventId: string;
  status: "archived";
  detailsRevision: number;
  alreadyArchived: boolean;
}

export interface GuestRegistryNames {
  firstName: string;
  lastName: string;
  displayName: string | null;
  preferredName: string | null;
}

export interface GuestRegistryMutation {
  personId: string;
  revision: number;
  status: "active" | "archived" | "merged";
}

export interface GuestRegistryProfile extends GuestRegistryMutation, GuestRegistryNames {}

export interface GuestRegistryDirectory {
  people: GuestRegistryProfile[];
  canManage: boolean;
  canExport: boolean;
  canMerge: boolean;
  nextOffset: number | null;
}

export interface GuestRegistryMergePreview {
  reviewId: string;
  source: GuestRegistryProfile;
  destination: GuestRegistryProfile;
  blocker: "inactive_profile" | "source_has_linked_records" | null;
}

export interface GuestRegistryMergeHistory {
  merges: { mergeId: string; sourceName: string; destinationName: string; mergedAt: string; restoredAt: string | null }[];
  nextOffset: number | null;
}

interface GuestRegistryMergeChange {
  mergeId: string;
  sourcePersonId: string;
  destinationPersonId: string;
  sourceRevision: number;
  status: "merged" | "restored";
}

export type ManagedParticipationStatus = "eligible" | "waitlisted" | "withdrawn" | "ineligible";

export interface GuestRegistryHistory {
  changes: {
    auditId: string;
    action: "guest.registry.create" | "guest.registry.update" | "guest.registry.archive";
    at: string;
    revision: number;
  }[];
  participations: {
    participationId: string;
    eventId: string;
    eventTitle: string;
    eventCode: string;
    eventStatus: OrganizerEvent["status"];
    status: ManagedParticipationStatus | "cancelled";
    canManage: boolean;
    revision: number;
    eventStartsAt: string | null;
    addedAt: string;
  }[];
  nextOffset: number | null;
}

export interface RegistryLinkableEvent {
  eventId: string;
  eventCode: string;
  title: string;
}

export type RegistryContactConsent = "unknown" | "permitted" | "restricted" | "withdrawn";

export interface RegistryContactPreferences {
  consent: RegistryContactConsent;
  primary: boolean;
}

export interface RegistryContact extends RegistryContactPreferences {
  contactId: string;
  revision: number;
  kind: "email" | "phone";
  value: string;
  verified: boolean;
}

export interface RegistryContactDirectory {
  contacts: RegistryContact[];
  canManage: boolean;
}

function registryContactPath(personId: string): string {
  return `/persons/${encodeURIComponent(personId)}/contacts`;
}

export interface EventGuestWorkspace extends RegistryLinkableEvent {
  status: OrganizerEvent["status"];
}

export interface EventGuestRow {
  participationId: string;
  displayName: string;
  status: ManagedParticipationStatus | "cancelled";
  revision: number;
  categoryCode: string | null;
  categoryId: string | null;
  tagIds: string[];
  groupIds: string[];
  participationCode: string | null;
}

export interface GuestListOption {
  id: string;
  code: string;
  label: string;
  retired: boolean;
}

export type EventGuestCategory = Omit<GuestListOption, "id"> & { categoryId: string };
export type EventGuestTag = Omit<GuestListOption, "id"> & { tagId: string };
export type EventGuestGroup = Omit<GuestListOption, "id"> & { groupId: string };

export interface EventGuestList {
  people: EventGuestRow[];
  canManage: boolean;
  canViewRelationships: boolean;
  canViewCustomFields: boolean;
  nextOffset: number | null;
}

export interface EventGuestViewFilters {
  status: EventGuestRow["status"] | null;
  category: string | null;
  query: string;
}

export interface EventGuestSavedView extends EventGuestViewFilters {
  viewId: string;
  label: string;
}

export type GuestFieldType = "text" | "integer" | "boolean";
export type GuestFieldValue = string | number | boolean | null;
export interface GuestFieldDefinition {
  fieldId: string;
  code: string;
  label: string;
  valueType: GuestFieldType;
  retired: boolean;
}
export type GuestFieldEntry = GuestFieldDefinition & { value: GuestFieldValue };

export interface EventGuestRelationship {
  relationshipId: string;
  relatedParticipationId: string;
  relatedDisplayName: string;
  direction: "mutual" | "outgoing" | "incoming";
  kind: string;
  retiredAt: string | null;
}

interface EventGuestRelationshipInput {
  relatedParticipationId: string;
  kind: string;
  directionality: "mutual" | "directed";
}

function guestRelationshipsPath(eventId: string, participationId: string): string {
  return `/events/${encodeURIComponent(eventId)}/participations/${encodeURIComponent(participationId)}/relationships`;
}

export interface GuestImportCommit {
  batchId: string;
  importedCount: number;
  skippedCount: number;
}

export interface GuestImportReuse {
  rowNumber: number;
  personId: string;
  expectedRevision: number;
}

interface GuestImportDiagnostics {
  rowNumber: number;
  errors: ("column_count" | "name_required" | "name_invalid" | "duplicate_in_file" | "cell_not_text")[];
  duplicateCount: number;
}

export interface GuestImportReport {
  batchId: string;
  state: "ready" | "committed";
  rows: (GuestImportDiagnostics & { outcome: "ready" | "needs_review" | "invalid" | "created" | "linked" | "skipped" })[];
}

export interface GuestImportPreview {
  batchId: string;
  rows: (GuestImportDiagnostics & {
    names: GuestRegistryNames;
    matches: {
      personId: string;
      revision: number;
      name: string;
      displayName: string | null;
      preferredName: string | null;
    }[];
  })[];
}

export const api = {
  enableEventGuestRegistry: (eventId: string) =>
    request<Envelope<{ eventId: string; guestRegistryEnabled: boolean }>>(`/events/${encodeURIComponent(eventId)}/guest-registry/enable`, {
      method: "POST", idempotent: true,
    }),
  getRegistryLinkableEvents: (personId: string) =>
    request<Envelope<RegistryLinkableEvent[]>>(`/persons/${encodeURIComponent(personId)}/linkable-events`),
  linkGuestRegistryProfile: (eventId: string, personId: string, status: "eligible" | "waitlisted" | "ineligible") =>
    request<Envelope<{ eventId: string; participationId: string; status: string }>>(`/events/${encodeURIComponent(eventId)}/participations`, {
      method: "POST", body: { personId, status }, idempotent: true,
    }),
  prepareGuestImportPreview: (eventId: string, csv: string) =>
    request<Envelope<{ batchId: string; rowCount: number }>>(`/events/${encodeURIComponent(eventId)}/guest-imports`, {
      method: "POST", body: { csv }, idempotent: true,
    }),
  inspectGuestWorkbook: (eventId: string, xlsx: string) =>
    request<Envelope<{ sheets: { index: number; name: string }[] }>>(`/events/${encodeURIComponent(eventId)}/guest-imports/xlsx/sheets`, {
      method: "POST", body: { xlsx },
    }),
  prepareGuestWorkbookPreview: (eventId: string, xlsx: string, sheetIndex: number, headerRow: number) =>
    request<Envelope<{ batchId: string; rowCount: number }>>(`/events/${encodeURIComponent(eventId)}/guest-imports/xlsx`, {
      method: "POST", body: { xlsx, sheetIndex, headerRow }, idempotent: true,
    }),
  commitGuestImport: (eventId: string, batchId: string, reuse: GuestImportReuse[]) =>
    request<Envelope<GuestImportCommit>>(`/events/${encodeURIComponent(eventId)}/guest-imports/${encodeURIComponent(batchId)}/commit`, {
      method: "POST", body: { reuse }, idempotent: true,
    }),
  getGuestImportPreview: (eventId: string, batchId: string) =>
    request<Envelope<GuestImportPreview>>(`/events/${encodeURIComponent(eventId)}/guest-imports/${encodeURIComponent(batchId)}`),
  getGuestImportReport: (eventId: string, batchId: string) =>
    request<Envelope<GuestImportReport>>(`/events/${encodeURIComponent(eventId)}/guest-imports/${encodeURIComponent(batchId)}/report`),
  listEventGuestWorkspaces: (organizationId: string) =>
    request<Envelope<EventGuestWorkspace[]>>(`/organizations/${encodeURIComponent(organizationId)}/events/guest-lists`),
  getEventGuestList: (eventId: string, offset: number, status: EventGuestRow["status"] | "", category = "", name = "") => {
    const path = `/events/${encodeURIComponent(eventId)}/participations`;
    if (name) {
      return request<Envelope<EventGuestList>>(`${path}/search`, {
        method: "POST", body: { offset, status: status || undefined, category: category || undefined, query: name },
      });
    }
    const query = new URLSearchParams({ offset: String(offset) });
    if (status) query.set("status", status);
    if (category) query.set("category", category);
    return request<Envelope<EventGuestList>>(`${path}?${query}`);
  },
  getEventGuestExport: (eventId: string, status: EventGuestRow["status"] | "", category = "", name = "") => {
    type ExportRow = Pick<EventGuestRow, "displayName" | "status" | "categoryCode">;
    const path = `/events/${encodeURIComponent(eventId)}/participations/export`;
    if (name) {
      return request<Envelope<{ people: ExportRow[] }>>(path, {
        method: "POST", body: { status: status || undefined, category: category || undefined, query: name },
      });
    }
    const query = new URLSearchParams();
    if (status) query.set("status", status);
    if (category) query.set("category", category);
    const filter = query.size ? `?${query}` : "";
    return request<Envelope<{ people: ExportRow[] }>>(`${path}${filter}`);
  },
  listEventGuestSavedViews: (eventId: string) =>
    request<Envelope<EventGuestSavedView[]>>(`/events/${encodeURIComponent(eventId)}/guest-saved-views`),
  createEventGuestSavedView: (eventId: string, label: string, filters: EventGuestViewFilters) =>
    request<Envelope<{ viewId: string }>>(`/events/${encodeURIComponent(eventId)}/guest-saved-views`, {
      method: "POST", idempotent: true,
      body: { label, query: filters.query, status: filters.status ?? undefined, category: filters.category ?? undefined },
    }),
  deleteEventGuestSavedView: (eventId: string, viewId: string) =>
    request<Envelope<{ viewId: string }>>(`/events/${encodeURIComponent(eventId)}/guest-saved-views/${encodeURIComponent(viewId)}`, {
      method: "DELETE", idempotent: true,
    }),
  listEventGuestCategories: (eventId: string) =>
    request<Envelope<EventGuestCategory[]>>(`/events/${encodeURIComponent(eventId)}/guest-categories`),
  createEventGuestCategory: (eventId: string, body: { code: string; label: string }) =>
    request<Envelope<EventGuestCategory>>(`/events/${encodeURIComponent(eventId)}/guest-categories`, { method: "POST", body, idempotent: true }),
  retireEventGuestCategory: (eventId: string, categoryId: string) =>
    request<Envelope<EventGuestCategory>>(`/events/${encodeURIComponent(eventId)}/guest-categories/${encodeURIComponent(categoryId)}/retire`, {
      method: "POST", idempotent: true,
    }),
  setEventGuestCategory: (eventId: string, participationId: string, categoryId: string | null, expectedRevision: number) =>
    request<Envelope<{ participationId: string; categoryId: string | null; revision: number }>>(
      `/events/${encodeURIComponent(eventId)}/participations/${encodeURIComponent(participationId)}/category`, {
        method: "PATCH", body: { categoryId, expectedRevision }, idempotent: true,
      },
    ),
  setEventGuestBulkCategory: (eventId: string, categoryId: string | null, guests: { participationId: string; expectedRevision: number }[]) =>
    request<Envelope<{ processedCount: number; updatedCount: number }>>(
      `/events/${encodeURIComponent(eventId)}/participations/bulk/category`, {
        method: "PATCH", body: { categoryId, guests }, idempotent: true,
      },
    ),
  setEventGuestBulkStatus: (eventId: string, status: ManagedParticipationStatus, guests: { participationId: string; expectedRevision: number }[]) =>
    request<Envelope<{ processedCount: number; updatedCount: number }>>(
      `/events/${encodeURIComponent(eventId)}/participations/bulk/status`, {
        method: "PATCH", body: { status, guests }, idempotent: true,
      },
    ),
  listEventGuestTags: (eventId: string) =>
    request<Envelope<EventGuestTag[]>>(`/events/${encodeURIComponent(eventId)}/guest-tags`),
  createEventGuestTag: (eventId: string, body: { code: string; label: string }) =>
    request<Envelope<EventGuestTag>>(`/events/${encodeURIComponent(eventId)}/guest-tags`, { method: "POST", body, idempotent: true }),
  retireEventGuestTag: (eventId: string, tagId: string) =>
    request<Envelope<EventGuestTag>>(`/events/${encodeURIComponent(eventId)}/guest-tags/${encodeURIComponent(tagId)}/retire`, {
      method: "POST", idempotent: true,
    }),
  setEventGuestTags: (eventId: string, participationId: string, tagIds: string[], expectedRevision: number) =>
    request<Envelope<{ participationId: string; tagIds: string[]; revision: number }>>(
      `/events/${encodeURIComponent(eventId)}/participations/${encodeURIComponent(participationId)}/tags`, {
        method: "PATCH", body: { tagIds, expectedRevision }, idempotent: true,
      },
    ),
  listEventGuestGroups: (eventId: string) =>
    request<Envelope<EventGuestGroup[]>>(`/events/${encodeURIComponent(eventId)}/guest-groups`),
  createEventGuestGroup: (eventId: string, body: { code: string; label: string }) =>
    request<Envelope<EventGuestGroup>>(`/events/${encodeURIComponent(eventId)}/guest-groups`, { method: "POST", body, idempotent: true }),
  retireEventGuestGroup: (eventId: string, groupId: string) =>
    request<Envelope<EventGuestGroup>>(`/events/${encodeURIComponent(eventId)}/guest-groups/${encodeURIComponent(groupId)}/retire`, {
      method: "POST", idempotent: true,
    }),
  setEventGuestGroups: (eventId: string, participationId: string, groupIds: string[], expectedRevision: number) =>
    request<Envelope<{ participationId: string; groupIds: string[]; revision: number }>>(
      `/events/${encodeURIComponent(eventId)}/participations/${encodeURIComponent(participationId)}/groups`, {
        method: "PATCH", body: { groupIds, expectedRevision }, idempotent: true,
      },
    ),
  listEventGuestRelationships: (eventId: string, participationId: string) =>
    request<Envelope<EventGuestRelationship[]>>(guestRelationshipsPath(eventId, participationId)),
  createEventGuestRelationship: (eventId: string, participationId: string, body: EventGuestRelationshipInput) =>
    request<Envelope<{ relationshipId: string; retiredAt: null }>>(guestRelationshipsPath(eventId, participationId), {
      method: "POST", body, idempotent: true,
    }),
  retireEventGuestRelationship: (eventId: string, participationId: string, relationshipId: string) =>
    request<Envelope<{ relationshipId: string; retiredAt: string }>>(
      `${guestRelationshipsPath(eventId, participationId)}/${encodeURIComponent(relationshipId)}/retire`,
      { method: "POST", idempotent: true },
    ),
  listGuestFieldDefinitions: (eventId: string) =>
    request<Envelope<GuestFieldDefinition[]>>(`/events/${encodeURIComponent(eventId)}/guest-custom-fields`),
  createGuestFieldDefinition: (eventId: string, body: { code: string; label: string; valueType: GuestFieldType }) =>
    request<Envelope<GuestFieldDefinition>>(`/events/${encodeURIComponent(eventId)}/guest-custom-fields`, { method: "POST", body, idempotent: true }),
  retireGuestFieldDefinition: (eventId: string, fieldId: string) =>
    request<Envelope<GuestFieldDefinition>>(`/events/${encodeURIComponent(eventId)}/guest-custom-fields/${encodeURIComponent(fieldId)}/retire`, {
      method: "POST", idempotent: true,
    }),
  listGuestFieldValues: (eventId: string, participationId: string) =>
    request<Envelope<{ revision: number; fields: GuestFieldEntry[] }>>(
      `/events/${encodeURIComponent(eventId)}/participations/${encodeURIComponent(participationId)}/custom-fields`,
    ),
  setGuestFieldValue: (eventId: string, participationId: string, fieldId: string, body: { expectedRevision: number; value: GuestFieldValue }) =>
    request<Envelope<{ revision: number }>>(
      `/events/${encodeURIComponent(eventId)}/participations/${encodeURIComponent(participationId)}/custom-fields/${encodeURIComponent(fieldId)}`,
      { method: "PATCH", body, idempotent: true },
    ),
  updateGuestParticipationStatus: (eventId: string, participationId: string, status: ManagedParticipationStatus, expectedRevision: number) =>
    request<Envelope<{ participationId: string; status: ManagedParticipationStatus; revision: number }>>(
      `/events/${encodeURIComponent(eventId)}/participations/${encodeURIComponent(participationId)}`,
      { method: "PATCH", body: { status, expectedRevision }, idempotent: true },
    ),
  searchGuestRegistry: (organizationId: string, body: { query: string; archived: boolean; offset: number }) =>
    request<Envelope<GuestRegistryDirectory>>(`/organizations/${encodeURIComponent(organizationId)}/persons/search`, { method: "POST", body }),
  exportGuestRegistry: (organizationId: string, body: { query: string; archived: boolean }) =>
    request<Envelope<{ people: (GuestRegistryNames & { status: GuestRegistryProfile["status"] })[] }>>(
      `/organizations/${encodeURIComponent(organizationId)}/persons/export`, { method: "POST", body },
    ),
  getGuestRegistryMerges: (organizationId: string, offset: number) =>
    request<Envelope<GuestRegistryMergeHistory>>(`/organizations/${encodeURIComponent(organizationId)}/persons/merges?offset=${offset}`),
  previewGuestRegistryMerge: (personId: string, destinationPersonId: string) =>
    request<Envelope<GuestRegistryMergePreview>>(`/persons/${encodeURIComponent(personId)}/merge-preview`, {
      method: "POST", body: { destinationPersonId },
    }),
  commitGuestRegistryMerge: (preview: GuestRegistryMergePreview) =>
    request<Envelope<GuestRegistryMergeChange>>(`/persons/${encodeURIComponent(preview.source.personId)}/merge`, {
      method: "POST", idempotent: true,
      body: {
        reviewId: preview.reviewId,
        destinationPersonId: preview.destination.personId, sourceRevision: preview.source.revision,
        destinationRevision: preview.destination.revision, reason: "duplicate_profile",
      },
    }),
  restoreGuestRegistryMerge: (organizationId: string, mergeId: string) =>
    request<Envelope<GuestRegistryMergeChange>>(`/organizations/${encodeURIComponent(organizationId)}/persons/merges/${encodeURIComponent(mergeId)}/restore`, {
      method: "POST", idempotent: true,
    }),
  getGuestRegistryProfile: (personId: string) =>
    request<Envelope<GuestRegistryProfile>>(`/persons/${encodeURIComponent(personId)}`),
  getGuestRegistryContacts: (personId: string) =>
    request<Envelope<RegistryContactDirectory>>(registryContactPath(personId)),
  createGuestRegistryContact: (personId: string, body: RegistryContactPreferences & { kind: RegistryContact["kind"]; value: string }) =>
    request<Envelope<{ contactId: string; revision: number }>>(registryContactPath(personId), { method: "POST", body, idempotent: true }),
  updateGuestRegistryContact: (personId: string, contactId: string, body: RegistryContactPreferences & { expectedRevision: number }) =>
    request<Envelope<{ contactId: string; revision: number }>>(`${registryContactPath(personId)}/${encodeURIComponent(contactId)}`, {
      method: "PATCH", body, idempotent: true,
    }),
  getGuestRegistryHistory: (personId: string, offset: number) =>
    request<Envelope<GuestRegistryHistory>>(`/persons/${encodeURIComponent(personId)}/history?offset=${offset}`),
  createGuestRegistryProfile: (organizationId: string, body: GuestRegistryNames) =>
    request<Envelope<GuestRegistryMutation>>(`/organizations/${encodeURIComponent(organizationId)}/persons`, { method: "POST", body, idempotent: true }),
  updateGuestRegistryProfile: (personId: string, body: GuestRegistryNames & { expectedRevision: number }) =>
    request<Envelope<GuestRegistryMutation>>(`/persons/${encodeURIComponent(personId)}`, { method: "PATCH", body, idempotent: true }),
  archiveGuestRegistryProfile: (personId: string, expectedRevision: number) =>
    request<Envelope<GuestRegistryMutation>>(`/persons/${encodeURIComponent(personId)}/archive`, {
      method: "POST", body: { expectedRevision }, idempotent: true,
    }),
  getOrganizerEventSessions: (organizationId: string, eventId: string) =>
    request<Envelope<OrganizerEventSessionDetails[]>>(organizerEventSessionsPath(organizationId, eventId)),
  createOrganizerEventSession: (organizationId: string, eventId: string, body: CreateOrganizerEventSessionInput) =>
    request<Envelope<OrganizerEventSession>>(organizerEventSessionsPath(organizationId, eventId), { method: "POST", body, idempotent: true }),
  updateOrganizerEventSession: (organizationId: string, eventId: string, sessionId: string, body: UpdateOrganizerEventSessionInput) =>
    request<Envelope<OrganizerEventSessionDetails>>(
      `${organizerEventSessionsPath(organizationId, eventId)}/${encodeURIComponent(sessionId)}`,
      { method: "PATCH", body, idempotent: true },
    ),
  transitionOrganizerEventSession: (organizationId: string, eventId: string, sessionId: string, body: OrganizerEventSessionTransitionInput) =>
    request<Envelope<Pick<OrganizerEventSessionDetails, "sessionId" | "status" | "detailsRevision">>>(
      `${organizerEventSessionsPath(organizationId, eventId)}/${encodeURIComponent(sessionId)}/transition`,
      { method: "POST", body, idempotent: true },
    ),
  getOrganizerEvents: (organizationId: string) =>
    request<Envelope<OrganizerEvent[]>>(`/organizations/${encodeURIComponent(organizationId)}/events`),
  createOrganizerEvent: (organizationId: string, body: CreateOrganizerEventInput) =>
    request<Envelope<OrganizerEvent>>(`/organizations/${encodeURIComponent(organizationId)}/events`, { method: "POST", body, idempotent: true }),
  transitionOrganizerEvent: (organizationId: string, eventId: string, body: OrganizerEventTransitionInput) =>
    request<Envelope<Pick<OrganizerEvent, "eventId" | "status" | "currentRevision" | "detailsRevision">>>(
      `/organizations/${encodeURIComponent(organizationId)}/events/${encodeURIComponent(eventId)}/transition`,
      { method: "POST", body, idempotent: true },
    ),
  updateOrganizerEventDetails: (organizationId: string, eventId: string, body: UpdateOrganizerEventDetailsInput) =>
    request<Envelope<OrganizerEvent>>(`/organizations/${encodeURIComponent(organizationId)}/events/${encodeURIComponent(eventId)}`, { method: "PATCH", body, idempotent: true }),
  archiveOrganizerEvent: (organizationId: string, eventId: string, expectedDetailsRevision: number) =>
    request<Envelope<OrganizerEventArchiveResult>>(`/organizations/${encodeURIComponent(organizationId)}/events/${encodeURIComponent(eventId)}/archive`, { method: "POST", body: { expectedDetailsRevision }, idempotent: true }),
  getBookingForms: () => request<Envelope<BookingForm[]>>("/organization/booking-forms"),
  createBookingForm: (body: { code: string; name: string; locale: "bs-BA" | "en"; fieldSchema: BookingFormSchema }) =>
    request<Envelope<BookingFormMutationResult>>("/organization/booking-forms", { method: "POST", body, idempotent: true }),
  createBookingFormRevision: (formId: string) =>
    request<Envelope<BookingFormMutationResult>>(`/booking-forms/${encodeURIComponent(formId)}/revisions`, { method: "POST", body: {}, idempotent: true }),
  updateBookingFormDraftRevision: (formId: string, revisionId: string, body: { locale: "bs-BA" | "en"; fieldSchema: BookingFormSchema }) =>
    request<Envelope<BookingFormMutationResult>>(`/booking-forms/${encodeURIComponent(formId)}/revisions/${encodeURIComponent(revisionId)}`, { method: "PUT", body, idempotent: true }),
  publishBookingFormRevision: (formId: string, revisionId: string) =>
    request<Envelope<BookingFormMutationResult>>(`/booking-forms/${encodeURIComponent(formId)}/revisions/${encodeURIComponent(revisionId)}/publish`, { method: "POST", body: {}, idempotent: true }),

  getPublicBookingForm: (organizationSlug: string, formCode: string) =>
    request<Envelope<PublicBookingForm>>(
      `/public/organizations/${encodeURIComponent(organizationSlug)}/booking-forms/${encodeURIComponent(formCode)}`,
      { credentials: "omit" },
    ),
  submitPublicBookingInquiry: (organizationSlug: string, body: PublicBookingInquirySubmission) =>
    request<Envelope<PublicBookingInquirySubmissionResult>>(
      `/public/organizations/${encodeURIComponent(organizationSlug)}/booking-inquiries`,
      { method: "POST", body, idempotent: true, credentials: "omit", skipCsrf: true },
    ),

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
  updateUserLocale: (locale: "bs-BA" | "en" | null) => request<Envelope<{ userLocale: "bs-BA" | "en" | null }>>("/me/preferences", { method: "PATCH", body: { locale } }),
  getOrganizationLocale: () => request<Envelope<{ defaultLocale: "bs-BA" | "en"; canManage: boolean }>>("/organization/locale"),
  setOrganizationLocale: (defaultLocale: "bs-BA" | "en") => request<Envelope<{ defaultLocale: "bs-BA" | "en" }>>("/organization/locale", { method: "PATCH", body: { defaultLocale } }),
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
  getBookingDraftAllocationOptions: (draftId: string) =>
    request<Envelope<BookingDraftAllocationOptions>>(
      `/booking-drafts/${encodeURIComponent(draftId)}/allocation-options`,
    ),
  previewBookingDraftAllocationAvailability: (
    draftId: string,
    body: {
      spaceLines: Array<{
        venueSpaceId: string;
        startsAt: string;
        endsAt: string;
        blockKind: "setup" | "rehearsal" | "event_use" | "teardown" | "buffer";
        requestedCapacity?: number | null;
      }>;
      resourceLines: Array<{ resourceTypeId: string; requestedQuantity: number }>;
      resourceStartsAt: string | null;
      resourceEndsAt: string | null;
    },
  ) => request<Envelope<BookingDraftAllocationAvailabilityPreview>>(
    `/booking-drafts/${encodeURIComponent(draftId)}/allocation-availability-preview`,
    { method: "POST", body },
  ),
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

  getBookingCancellationRequestQueue: (status?: string) => {
    const query = new URLSearchParams({ limit: "50", offset: "0" });
    if (status) query.set("status", status);
    return request<Envelope<BookingCancellationRequestQueue>>(
      `/organization/booking-cancellation-requests?${query.toString()}`,
    );
  },
  getBookingCancellationRequestsForBooking: (bookingId: string) =>
    request<Envelope<BookingCancellationRequestDetail[]>>(
      `/bookings/${encodeURIComponent(bookingId)}/cancellation-requests`,
    ),
  decideBookingCancellationRequest: (
    bookingId: string,
    requestId: string,
    body: { decision: "approved" | "rejected" | "returned_for_changes"; reason: string },
  ) =>
    request<Envelope<Record<string, unknown>>>(
      `/bookings/${encodeURIComponent(bookingId)}/cancellation-requests/${encodeURIComponent(requestId)}/decision`,
      { method: "POST", body, idempotent: true },
    ),
  previewBookingCancellation: (
    bookingId: string,
    body: { expectedBookingRevision: number; cancellationRequestId?: string },
  ) =>
    request<Envelope<BookingCancellationPreview>>(
      `/bookings/${encodeURIComponent(bookingId)}/cancellation-preview`,
      { method: "POST", body },
    ),
  executeBookingCancellation: (
    bookingId: string,
    body: { expectedBookingRevision: number; cancellationRequestId: string },
  ) =>
    request<Envelope<BookingCancellationExecutionResult>>(
      `/bookings/${encodeURIComponent(bookingId)}/cancellation-execution`,
      { method: "POST", body, idempotent: true },
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
        requestedCapacity?: number | null;
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
  getGuestInvitationEvents: (organizationId: string) =>
    request<Envelope<GuestInvitationEvent[]>>(
      `/organizations/${encodeURIComponent(organizationId)}/guest-invitation-events`,
    ),
  getGuestInvitationParticipations: (eventId: string) =>
    request<Envelope<GuestInvitationParticipation[]>>(
      `/events/${encodeURIComponent(eventId)}/guest-invitation-participations`,
    ),
  issueGuestInvitation: (
    eventId: string,
    participationId: string,
    body: {
      invitationId?: string;
      scheduleRevisionId: string;
      rsvpPolicyRevisionId: string;
      locale: "bs-BA" | "en";
      expiresAt: string;
      presentationSnapshot: Record<string, string>;
    },
  ) =>
    request<Envelope<{ invitationId: string; deliveryId: string; status: string; created: boolean }>>(
      `/events/${encodeURIComponent(eventId)}/participations/${encodeURIComponent(participationId)}/invitation`,
      { method: "POST", body, idempotent: true },
    ),
  revokeGuestInvitation: (invitationId: string, reasonCode: string) =>
    request<Envelope<Record<string, unknown>>>(
      `/invitations/${encodeURIComponent(invitationId)}/revoke`,
      { method: "POST", body: { reasonCode }, idempotent: true },
    ),
  getGuestInvitationRsvpHistory: (eventId: string, participationId: string) =>
    request<Envelope<GuestInvitationRsvpHistoryEntry[]>>(
      `/events/${encodeURIComponent(eventId)}/participations/${encodeURIComponent(participationId)}/rsvp-history`,
    ),
  getGuestInvitationDeliveryAttempts: (invitationId: string) =>
    request<Envelope<GuestInvitationDeliveryAttempt[]>>(
      `/invitations/${encodeURIComponent(invitationId)}/delivery-attempts`,
    ),
  recordStaffGuestRsvp: (
    eventId: string,
    participationId: string,
    body: {
      response: "accepted" | "declined" | "tentative";
      sourceChannel: "phone" | "in_person" | "email" | "written" | "representative" | "staff_entry" | "other";
      respondentKind: "guest" | "representative" | "staff";
      receivedAt: string;
      invitationId?: string;
      noteRestricted?: string;
      correctionOfResponseId?: string;
      correctionReason?: string;
    },
  ) =>
    request<Envelope<{ responseId: string; participationId: string; response: string; sequenceNumber: number }>>(
      `/events/${encodeURIComponent(eventId)}/participations/${encodeURIComponent(participationId)}/rsvp-records`,
      { method: "POST", body, idempotent: true },
    ),
  issueExternalBookingActionCapability: (
    bookingId: string,
    body: {
      bookingContactId: string;
      action: "booking_cancellation_request" | "booking_cancellation_status";
      expiresAt: string;
      maxUses?: number;
    },
    idempotencyKey: string,
  ) =>
    request<Envelope<ExternalBookingActionCapability>>(
      `/bookings/${encodeURIComponent(bookingId)}/external-action-capabilities`,
      { method: "POST", body, idempotent: true, idempotencyKey },
    ),
  resolveExternalBookingAction: (
    token: string,
    action: "booking_cancellation_request" | "booking_cancellation_status",
  ) =>
    request<Envelope<ExternalBookingActionContext>>("/external/booking-actions/resolve", {
      method: "POST",
      body: { action },
      idempotent: true,
      credentials: "omit",
      skipCsrf: true,
      extraHeaders: { "X-External-Booking-Action-Token": token },
    }),
  submitExternalBookingCancellationRequest: (
    token: string,
    body: { reasonCode: string; explanation?: string },
    idempotencyKey: string,
  ) =>
    request<Envelope<ExternalBookingCancellationSubmission>>(
      "/external/booking-actions/cancellation-requests",
      {
        method: "POST",
        body,
        idempotent: true,
        idempotencyKey,
        credentials: "omit",
        skipCsrf: true,
        extraHeaders: { "X-External-Booking-Token": token },
      },
    ),
  getExternalBookingCancellationRequestStatus: (token: string, requestId: string) =>
    request<Envelope<ExternalBookingCancellationStatus>>(
      `/external/booking-actions/cancellation-requests/${encodeURIComponent(requestId)}`,
      {
        credentials: "omit",
        extraHeaders: { "X-External-Booking-Token": token },
      },
    ),
  getGuestInvitation: (token: string) =>
    request<Envelope<GuestInvitation>>("/guest/invitation/me", {
      credentials: "omit",
      extraHeaders: { "X-Guest-Invitation-Token": token },
    }),
  submitGuestInvitationRsvp: (
    token: string,
    body: { response: "accepted" | "declined" | "tentative"; note?: string },
    idempotencyKey: string,
  ) =>
    request<Envelope<{ responseId: string; response: string; receivedAt: string; replayed: boolean }>>(
      "/guest/invitation/me/rsvp",
      {
        method: "POST",
        body,
        idempotent: true,
        idempotencyKey,
        credentials: "omit",
        skipCsrf: true,
        extraHeaders: { "X-Guest-Invitation-Token": token },
      },
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
