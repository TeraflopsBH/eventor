import { computed, reactive, ref, type Ref } from "vue";
import type { BookingDraftDetail, BookingOfferRecord, BookingOfferEmailDelivery, BookingOfferApprovalStatus, BookingOfferApprovalRequirement, BookingOfferWriteRequest, Principal } from "../../api";
interface BookingOffersDependencies {
  api: typeof import("../../api").api; busy: Ref<boolean>; pageError: Ref<string>; pageNotice: Ref<string>;
  principal: Ref<Principal | null>; bookingDraftDetail: Ref<BookingDraftDetail | null>;
  clearMessages: () => void; showError: (error: unknown) => void;
  refreshBookingDraft: () => Promise<void>; refreshInquiryDetail: () => Promise<void>;
  translate: (key: string, params?: Record<string, string | number>) => string;
}
export function useBookingOffers({ api, busy, pageError, pageNotice, principal, bookingDraftDetail, clearMessages, showError, refreshBookingDraft, refreshInquiryDetail, translate: t }: BookingOffersDependencies) {
const bookingOffer = ref<BookingOfferRecord | null>(null);
const bookingOfferApprovalStatus = ref<BookingOfferApprovalStatus | null>(null);
const bookingOfferIdInput = ref("");
const bookingOfferAcceptanceToken = ref("");
const bookingOfferConfirmationReason = ref("");
const bookingOfferIssueRequestKey = ref("");
const bookingOfferEmailRequestKey = ref("");
const bookingOfferEmailDeliveries = ref<BookingOfferEmailDelivery[]>([]);
const bookingOfferEmailMeta = ref<{ limit: number; offset: number; totalCount: number; counts: Record<string, number> } | null>(null);
const bookingOfferEmailStatusFilter = ref("");
const bookingOfferEmailOffset = ref(0);
const bookingOfferEmailResolution = reactive<Record<string, "confirmed_sent" | "confirmed_not_sent" | "">>({});
const bookingOfferEmailReason = reactive<Record<string, string>>({});
const bookingOfferEmailReference = reactive<Record<string, string>>({});
const bookingOfferEmailRetryReason = reactive<Record<string, string>>({});

const bookingOfferSupersedeCurrent = ref(false);
const bookingOfferValidUntil = ref("");
const bookingOfferTaxAmount = ref("");
const bookingOfferInternalReason = ref("");
const bookingOfferCreateForm = reactive({
  priceListRevisionId: "",
  cancellationPolicyRevisionId: "",
  approvalPolicyRevisionId: "",
  currency: "",
  taxBasis: "" as "" | "inclusive" | "exclusive" | "not_applicable" | "to_be_confirmed",
});
const bookingOfferLineItemsJson = ref("[]");
const bookingOfferAdjustmentsJson = ref("[]");
const bookingOfferApprovalDecisions = reactive<Record<string, "approved" | "rejected" | "returned_for_changes">>({});
const bookingOfferApprovalReasons = reactive<Record<string, string>>({});

const canManageBookingOffer = computed(() =>
  (bookingDraftDetail.value?.status === "draft" || bookingDraftDetail.value?.status === "offered") &&
  Boolean(bookingDraftDetail.value.currentRevision),
);
const bookingOfferApprovalsSatisfied = computed(() => {
  const requirements = bookingOfferApprovalStatus.value?.requirements;
  return Boolean(requirements) && requirements.every((item) =>
    !item.blocked && item.approvedCount >= item.requiredApprovals,
  );
});
const canConfirmBookingOffer = computed(() => {
  const revision = bookingOffer.value?.currentRevision;
  const draftRevisionId = bookingDraftDetail.value?.currentRevision?.revisionId;
  return Boolean(
    bookingOffer.value &&
    revision?.state === "accepted" &&
    revision.draftRevisionId === draftRevisionId &&
    bookingOfferApprovalsSatisfied.value,
  );
});

function parseOfferJsonArray<T>(value: string, label: string): T[] {
  let parsed: unknown;
  try { parsed = JSON.parse(value); } catch { throw new Error(t("commercialBooking.jsonArrayInvalid", { label })); }
  if (!Array.isArray(parsed)) throw new Error(t("commercialBooking.jsonArrayRequired", { label }));
  return parsed as T[];
}

function bookingOfferWritePayload(): BookingOfferWriteRequest {
  const currency = bookingOfferCreateForm.currency.trim().toUpperCase();
  if (!/^[A-Z]{3}$/.test(currency)) throw new Error(t("commercialBooking.invalidCurrency"));
  if (!bookingOfferCreateForm.taxBasis) throw new Error(t("commercialBooking.selectTaxTreatment"));
  const priceListRevisionId = bookingOfferCreateForm.priceListRevisionId.trim();
  const cancellationPolicyRevisionId = bookingOfferCreateForm.cancellationPolicyRevisionId.trim();
  const approvalPolicyRevisionId = bookingOfferCreateForm.approvalPolicyRevisionId.trim();
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (![priceListRevisionId, cancellationPolicyRevisionId, approvalPolicyRevisionId].every((value) => uuid.test(value))) {
    throw new Error(t("commercialBooking.invalidPolicyRevisionIds"));
  }
  if (!bookingOfferValidUntil.value) throw new Error(t("commercialBooking.offerExpiryRequired"));
  const validUntilDate = new Date(bookingOfferValidUntil.value);
  if (Number.isNaN(validUntilDate.getTime())) throw new Error(t("commercialBooking.offerExpiryInvalid"));
  if (bookingOfferTaxAmount.value.trim() === "") throw new Error(t("commercialBooking.taxAmountRequired"));
  const taxAmount = Number(bookingOfferTaxAmount.value);
  if (!Number.isFinite(taxAmount) || taxAmount < 0) throw new Error(t("commercialBooking.taxAmountInvalid"));
  const lineItems = parseOfferJsonArray<{ itemCode: string; quantity: number }>(bookingOfferLineItemsJson.value, t("commercialBooking.lineItems"));
  const adjustments = parseOfferJsonArray<{ code: string; label: string; kind: "fee" | "discount" | "credit"; amount: number }>(bookingOfferAdjustmentsJson.value, t("commercialBooking.adjustments"));
  if (!lineItems.length) throw new Error(t("commercialBooking.lineItemRequired"));
  const internalReason = bookingOfferInternalReason.value.trim();
  if (internalReason.length < 3) throw new Error(t("commercialBooking.internalAuditReasonMin"));
  return {
    priceListRevisionId,
    cancellationPolicyRevisionId,
    approvalPolicyRevisionId,
    currency,
    taxBasis: bookingOfferCreateForm.taxBasis,
    validUntil: validUntilDate.toISOString(),
    lineItems,
    adjustments,
    taxAmount,
    internalReason,
  };
}

async function refreshBookingOfferData(): Promise<void> {
  const offerId = bookingOfferIdInput.value.trim();
  if (!offerId) return;
  const [offerResult, approvalResult] = await Promise.all([
    api.getBookingOffer(offerId),
    api.getBookingOfferApprovals(offerId),
  ]);
  if (bookingDraftDetail.value && offerResult.data.draftId !== bookingDraftDetail.value.draftId) {
    throw new Error(t("commercialBooking.offerWrongDraft"));
  }
  bookingOffer.value = offerResult.data;
  bookingOfferApprovalStatus.value = approvalResult.data;
  await refreshBookingOfferEmailData();
}

async function refreshBookingOfferEmailData(): Promise<void> {
  const offerId = bookingOfferIdInput.value.trim();
  if (!offerId) return;
  const result = await api.getBookingOfferEmailDeliveries(offerId, {
    status: bookingOfferEmailStatusFilter.value || undefined,
    limit: 25,
    offset: bookingOfferEmailOffset.value,
  });
  bookingOfferEmailDeliveries.value = result.data;
  bookingOfferEmailMeta.value = result.meta;
}

async function loadBookingOffer(): Promise<void> {
  const value = bookingOfferIdInput.value.trim();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    pageError.value = t("commercialBooking.invalidOfferUuid");
    return;
  }
  clearMessages();
  busy.value = true;
  try {
    await refreshBookingOfferData();
    bookingOfferAcceptanceToken.value = "";
    pageNotice.value = t("commercialBooking.offerLoaded");
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function saveBookingOfferRevision(): Promise<void> {
  const draft = bookingDraftDetail.value;
  const draftRevisionId = draft?.currentRevision?.revisionId;
  if (!draft || !draftRevisionId || !canManageBookingOffer.value) return;
  let body: BookingOfferWriteRequest;
  try {
    body = bookingOfferWritePayload();
  } catch (error) {
    pageError.value = error instanceof Error ? error.message : t("commercialBooking.offerTermsInvalid");
    return;
  }
  if (bookingOffer.value && bookingOffer.value.draftId !== draft.draftId) {
    pageError.value = t("commercialBooking.loadedOfferWrongDraft");
    return;
  }
  const confirmation = bookingOffer.value ? t("commercialBooking.confirmPrepareSuccessor", { revision: draft.currentRevisionNumber }) : t("commercialBooking.confirmPrepareOffer", { revision: draft.currentRevisionNumber });
  if (!window.confirm(confirmation)) return;
  clearMessages();
  busy.value = true;
  try {
    const result = bookingOffer.value
      ? await api.createBookingOfferSuccessor(bookingOffer.value.offerId, {
          ...body,
          draftRevisionId,
          supersedeCurrentOffer: bookingOfferSupersedeCurrent.value,
        })
      : await api.createBookingOffer(draftRevisionId, body);
    bookingOfferIdInput.value = result.data.offerId;
    bookingOfferAcceptanceToken.value = "";
    bookingOfferIssueRequestKey.value = "";
    await refreshBookingOfferData();
    pageNotice.value = t("commercialBooking.offerRevisionPrepared", { revision: result.data.revisionNumber });
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function issueBookingOffer(): Promise<void> {
  const offer = bookingOffer.value;
  if (!offer || offer.currentRevision.state !== "draft") return;
  if (!window.confirm(t("commercialBooking.confirmIssueOffer"))) return;
  clearMessages();
  busy.value = true;
  try {
    if (!bookingOfferIssueRequestKey.value) {
      if (!globalThis.crypto?.randomUUID) throw new Error(t("commercialBooking.secureIdempotencyUnavailable"));
      bookingOfferIssueRequestKey.value = globalThis.crypto.randomUUID();
    }
    const result = await api.issueBookingOffer(offer.offerId, bookingOfferIssueRequestKey.value);
    bookingOfferAcceptanceToken.value = result.data.acceptanceToken;
    await refreshBookingOfferData();
    pageNotice.value = t("commercialBooking.offerIssued");
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function emailBookingOffer(): Promise<void> {
  const offer = bookingOffer.value;
  const token = bookingOfferAcceptanceToken.value;
  if (!offer || !token || offer.currentRevision.state !== "issued") return;
  if (!window.confirm(t("commercialBooking.confirmQueueOfferEmail"))) return;
  clearMessages();
  busy.value = true;
  try {
    if (!bookingOfferEmailRequestKey.value) {
      if (!globalThis.crypto?.randomUUID) throw new Error("This browser cannot create a secure idempotency key.");
      bookingOfferEmailRequestKey.value = globalThis.crypto.randomUUID();
    }
    const result = await api.queueBookingOfferEmail(offer.offerId, token, bookingOfferEmailRequestKey.value);
    bookingOfferEmailRequestKey.value = "";
    bookingOfferEmailStatusFilter.value = "";
    bookingOfferEmailOffset.value = 0;
    await refreshBookingOfferEmailData();
    pageNotice.value = result.data.created
      ? t("commercialBooking.offerEmailQueued") : t("commercialBooking.offerEmailAlreadyExists", { status: result.data.status });
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function reconcileBookingOfferEmail(delivery: BookingOfferEmailDelivery): Promise<void> {
  const resolution = bookingOfferEmailResolution[delivery.deliveryId] ?? "";
  const reason = (bookingOfferEmailReason[delivery.deliveryId] ?? "").trim();
  if (!resolution) {
    pageError.value = t("commercialBooking.smtpOutcomeRequired");
    return;
  }
  if (reason.length < 3) {
    pageError.value = t("commercialBooking.smtpVerificationReasonMin");
    return;
  }
  if (resolution === "confirmed_sent" && !window.confirm(t("commercialBooking.confirmSmtpAccepted"))) return;
  if (resolution === "confirmed_not_sent" && !window.confirm(t("commercialBooking.confirmSmtpNotAccepted"))) return;
  clearMessages();
  busy.value = true;
  try {
    await api.reconcileBookingOfferEmailDelivery(delivery.deliveryId, {
      resolution,
      reason,
      providerMessageReference: resolution === "confirmed_sent"
        ? bookingOfferEmailReference[delivery.deliveryId]?.trim() || undefined
        : undefined,
    });
    bookingOfferEmailStatusFilter.value = "";
    bookingOfferEmailOffset.value = 0;
    await refreshBookingOfferEmailData();
    pageNotice.value = resolution === "confirmed_sent"
      ? t("commercialBooking.smtpAcceptedRecorded") : t("commercialBooking.smtpNotAcceptedRecorded");
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function retryBookingOfferEmail(delivery: BookingOfferEmailDelivery): Promise<void> {
  const reason = (bookingOfferEmailRetryReason[delivery.deliveryId] ?? "").trim();
  if (reason.length < 3) {
    pageError.value = t("commercialBooking.retryReasonMin");
    return;
  }
  if (!window.confirm(t("commercialBooking.confirmManualRetry"))) return;
  clearMessages();
  busy.value = true;
  try {
    await api.retryBookingOfferEmailDelivery(delivery.deliveryId, reason);
    bookingOfferEmailStatusFilter.value = "";
    bookingOfferEmailOffset.value = 0;
    await refreshBookingOfferEmailData();
    pageNotice.value = t("commercialBooking.manualRetryQueued");
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function copyBookingOfferCapability(): Promise<void> {
  if (!bookingOfferAcceptanceToken.value) return;
  try {
    const offerId = bookingOffer.value?.offerId;
    if (!offerId) throw new Error(t("commercialBooking.issuedOfferUnavailable"));
    const customerUrl = new URL(`/offers/${encodeURIComponent(offerId)}`, window.location.origin);
    customerUrl.hash = new URLSearchParams({ token: bookingOfferAcceptanceToken.value }).toString();
    await navigator.clipboard.writeText(customerUrl.toString());
    pageNotice.value = t("commercialBooking.offerLinkCopied");
    pageError.value = "";
  } catch {
    pageError.value = t("commercialBooking.clipboardDenied");
  }
}

function canDecideBookingOfferRequirement(requirement: BookingOfferApprovalRequirement): boolean {
  return !requirement.blocked &&
    requirement.approvedCount < requirement.requiredApprovals &&
    !requirement.decisions.some((decision) => decision.membershipId === principal.value?.membershipId);
}

async function decideBookingOfferApproval(requirement: BookingOfferApprovalRequirement): Promise<void> {
  const offer = bookingOffer.value;
  const decision = bookingOfferApprovalDecisions[requirement.ruleCode] ?? "approved";
  const reason = (bookingOfferApprovalReasons[requirement.ruleCode] ?? "").trim();
  if (!offer) return;
  if (reason.length < 3) {
    pageError.value = t("commercialBooking.approvalReasonMin");
    return;
  }
  const decisionLabel = t(`commercialBooking.${({ approved: "stateApproved", rejected: "stateRejected", returned_for_changes: "stateReturnedForChanges" } as Record<string, string>)[decision]}`);
  if (!window.confirm(t("commercialBooking.confirmApprovalDecision", { decision: decisionLabel, rule: requirement.ruleCode }))) return;
  clearMessages();
  busy.value = true;
  try {
    await api.decideBookingOfferApproval(offer.offerId, {
      offerRevisionId: offer.currentRevision.offerRevisionId,
      ruleCode: requirement.ruleCode,
      decision,
      reason,
    });
    await refreshBookingOfferData();
    pageNotice.value = t("commercialBooking.approvalDecisionRecorded", { rule: requirement.ruleCode });
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function confirmBookingFromAcceptedOffer(): Promise<void> {
  const offer = bookingOffer.value;
  const draftRevisionId = bookingDraftDetail.value?.currentRevision?.revisionId;
  const reason = bookingOfferConfirmationReason.value.trim();
  if (!offer || !draftRevisionId || !canConfirmBookingOffer.value) return;
  if (reason.length < 3) {
    pageError.value = t("commercialBooking.bookingConfirmationReasonMin");
    return;
  }
  if (!window.confirm(t("commercialBooking.confirmBooking"))) return;
  clearMessages();
  busy.value = true;
  try {
    const result = await api.confirmBookingFromOffer(draftRevisionId, {
      expectedDraftRevisionId: draftRevisionId,
      confirmationReason: reason,
    });
    await Promise.all([refreshBookingDraft(), refreshInquiryDetail()]);
    await refreshBookingOfferData();
    pageNotice.value = result.data.replayed ? t("commercialBooking.bookingConfirmationExisting", { code: result.data.bookingCode }) : t("commercialBooking.bookingConfirmationCreated", { code: result.data.bookingCode });
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

function reset(): void {
  bookingOffer.value = null;
  bookingOfferApprovalStatus.value = null;
  bookingOfferIdInput.value = "";
  bookingOfferAcceptanceToken.value = "";
  bookingOfferConfirmationReason.value = "";
  bookingOfferIssueRequestKey.value = "";
  bookingOfferSupersedeCurrent.value = false;
  bookingOfferValidUntil.value = "";
  bookingOfferTaxAmount.value = "";
  bookingOfferInternalReason.value = "";
  bookingOfferCreateForm.priceListRevisionId = "";
  bookingOfferCreateForm.cancellationPolicyRevisionId = "";
  bookingOfferCreateForm.approvalPolicyRevisionId = "";
  bookingOfferCreateForm.currency = "";
  bookingOfferCreateForm.taxBasis = "";
  bookingOfferLineItemsJson.value = "[]";
  bookingOfferAdjustmentsJson.value = "[]";
  for (const key of Object.keys(bookingOfferApprovalDecisions)) delete bookingOfferApprovalDecisions[key];
  for (const key of Object.keys(bookingOfferApprovalReasons)) delete bookingOfferApprovalReasons[key];
  bookingOfferEmailRequestKey.value = "";
  bookingOfferEmailDeliveries.value = [];
  bookingOfferEmailMeta.value = null;
  bookingOfferEmailStatusFilter.value = "";
  bookingOfferEmailOffset.value = 0;
  for (const key of Object.keys(bookingOfferEmailResolution)) delete bookingOfferEmailResolution[key];
  for (const key of Object.keys(bookingOfferEmailReason)) delete bookingOfferEmailReason[key];
  for (const key of Object.keys(bookingOfferEmailReference)) delete bookingOfferEmailReference[key];
  for (const key of Object.keys(bookingOfferEmailRetryReason)) delete bookingOfferEmailRetryReason[key];
}
return {
  bookingOffer, bookingOfferApprovalStatus, bookingOfferIdInput, bookingOfferAcceptanceToken, bookingOfferConfirmationReason,
  bookingOfferIssueRequestKey, bookingOfferEmailRequestKey, bookingOfferEmailDeliveries, bookingOfferEmailMeta,
  bookingOfferEmailStatusFilter, bookingOfferEmailOffset, bookingOfferEmailResolution, bookingOfferEmailReason,
  bookingOfferEmailReference, bookingOfferEmailRetryReason, bookingOfferSupersedeCurrent, bookingOfferValidUntil,
  bookingOfferTaxAmount, bookingOfferInternalReason, bookingOfferCreateForm, bookingOfferLineItemsJson,
  bookingOfferAdjustmentsJson, bookingOfferApprovalDecisions, bookingOfferApprovalReasons,
  canManageBookingOffer, bookingOfferApprovalsSatisfied, canConfirmBookingOffer,
  refreshBookingOfferData, refreshBookingOfferEmailData, loadBookingOffer, saveBookingOfferRevision,
  issueBookingOffer, emailBookingOffer, reconcileBookingOfferEmail, retryBookingOfferEmail,
  copyBookingOfferCapability, canDecideBookingOfferRequirement, decideBookingOfferApproval,
  confirmBookingFromAcceptedOffer, reset,
};
}
