import { computed, reactive, ref, type Ref } from "vue";
import type { BookingOfferRecord, BookingOfferEmailDelivery, BookingOfferApprovalStatus, BookingOfferApprovalRequirement, BookingOfferWriteRequest, Principal } from "../../api";
interface BookingDraftDetailLike {
  value: { draftId: string; status: string; currentRevision?: { revisionId: string } | null; currentRevisionNumber?: number } | null;
}
interface BookingOffersDependencies {
  api: typeof import("../../api").api; busy: Ref<boolean>; pageError: Ref<string>; pageNotice: Ref<string>;
  principal: Ref<Principal | null>; bookingDraftDetail: BookingDraftDetailLike;
  clearMessages: () => void; showError: (error: unknown) => void;
  refreshBookingDraft: () => Promise<void>; refreshInquiryDetail: () => Promise<void>;
}
export function useBookingOffers({ api, busy, pageError, pageNotice, principal, bookingDraftDetail, clearMessages, showError, refreshBookingDraft, refreshInquiryDetail }: BookingOffersDependencies) {
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
  const parsed: unknown = JSON.parse(value);
  if (!Array.isArray(parsed)) throw new Error(label + " must be a JSON array.");
  return parsed as T[];
}

function bookingOfferWritePayload(): BookingOfferWriteRequest {
  const currency = bookingOfferCreateForm.currency.trim().toUpperCase();
  if (!/^[A-Z]{3}$/.test(currency)) throw new Error("Enter a three-letter ISO currency code.");
  if (!bookingOfferCreateForm.taxBasis) throw new Error("Select the tax treatment before preparing an offer.");
  const priceListRevisionId = bookingOfferCreateForm.priceListRevisionId.trim();
  const cancellationPolicyRevisionId = bookingOfferCreateForm.cancellationPolicyRevisionId.trim();
  const approvalPolicyRevisionId = bookingOfferCreateForm.approvalPolicyRevisionId.trim();
  const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
  if (![priceListRevisionId, cancellationPolicyRevisionId, approvalPolicyRevisionId].every((value) => uuid.test(value))) {
    throw new Error("Price-list, cancellation-policy and approval-policy revision IDs must each be valid UUIDs.");
  }
  if (!bookingOfferValidUntil.value) throw new Error("Set the offer expiry date and time.");
  const validUntilDate = new Date(bookingOfferValidUntil.value);
  if (Number.isNaN(validUntilDate.getTime())) throw new Error("The offer expiry date and time is invalid.");
  if (bookingOfferTaxAmount.value.trim() === "") throw new Error("Enter a tax amount. Use zero to calculate from the selected tax profile, or when no tax applies.");
  const taxAmount = Number(bookingOfferTaxAmount.value);
  if (!Number.isFinite(taxAmount) || taxAmount < 0) throw new Error("Tax amount must be a non-negative number.");
  const lineItems = parseOfferJsonArray<{ itemCode: string; quantity: number }>(bookingOfferLineItemsJson.value, "Line items");
  const adjustments = parseOfferJsonArray<{ code: string; label: string; kind: "fee" | "discount" | "credit"; amount: number }>(bookingOfferAdjustmentsJson.value, "Adjustments");
  if (!lineItems.length) throw new Error("Add at least one price-list item to the offer.");
  const internalReason = bookingOfferInternalReason.value.trim();
  if (internalReason.length < 3) throw new Error("Enter an internal or tax audit reason of at least 3 characters.");
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
    throw new Error("That offer belongs to a different booking draft.");
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
    pageError.value = "Enter a valid booking-offer UUID.";
    return;
  }
  clearMessages();
  busy.value = true;
  try {
    await refreshBookingOfferData();
    bookingOfferAcceptanceToken.value = "";
    pageNotice.value = "Offer and approval status loaded. Customer acceptance and staff approval remain separate steps.";
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
    pageError.value = error instanceof Error ? error.message : "Offer terms are invalid.";
    return;
  }
  if (bookingOffer.value && bookingOffer.value.draftId !== draft.draftId) {
    pageError.value = "The loaded offer does not belong to this draft.";
    return;
  }
  const action = bookingOffer.value ? "Create a successor offer revision" : "Prepare this booking offer";
  const warning = bookingOffer.value
    ? " Earlier offer revisions and customer decisions remain immutable. The server will enforce whether superseding the current offer is permitted."
    : " This creates a draft offer only; it does not send it to the customer or reserve resources.";
  if (!window.confirm(action + " from draft revision " + draft.currentRevisionNumber + "?" + warning)) return;
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
    pageNotice.value = "Offer revision " + result.data.revisionNumber + " prepared. It is still a draft and has not been sent or accepted.";
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function issueBookingOffer(): Promise<void> {
  const offer = bookingOffer.value;
  if (!offer || offer.currentRevision.state !== "draft") return;
  if (!window.confirm("Issue this exact offer revision to the customer? This creates a customer capability. It does not confirm the booking or reserve capacity.")) return;
  clearMessages();
  busy.value = true;
  try {
    if (!bookingOfferIssueRequestKey.value) {
      if (!globalThis.crypto?.randomUUID) throw new Error("This browser cannot create a secure idempotency key.");
      bookingOfferIssueRequestKey.value = globalThis.crypto.randomUUID();
    }
    const result = await api.issueBookingOffer(offer.offerId, bookingOfferIssueRequestKey.value);
    bookingOfferAcceptanceToken.value = result.data.acceptanceToken;
    await refreshBookingOfferData();
    pageNotice.value = "Offer issued. You can copy the secure link or explicitly queue it for delivery to the source inquiry email address.";
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
  if (!window.confirm("Queue this issued offer for email delivery to the email address supplied in the source inquiry? It will be sent through this organisation's tested SMTP configuration.")) return;
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
      ? "Offer email queued. SMTP delivery will be handled by the background worker."
      : "Offer email request already exists (status: " + result.data.status + ").";
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
    pageError.value = "Choose the verified SMTP outcome before reconciling this delivery.";
    return;
  }
  if (reason.length < 3) {
    pageError.value = "Enter how the outcome was verified (at least 3 characters).";
    return;
  }
  if (resolution === "confirmed_sent" && !window.confirm("Record that this email was accepted by the SMTP server? This does not claim inbox delivery and will not send another email.")) return;
  if (resolution === "confirmed_not_sent" && !window.confirm("Record that the SMTP server did not accept this email? This does not send anything. A separate, one-time retry can then be authorised.")) return;
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
      ? "Delivery recorded as SMTP-accepted. No email was sent by reconciliation."
      : "Delivery recorded as not accepted. A separate one-time retry is now available if the offer remains current.";
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function retryBookingOfferEmail(delivery: BookingOfferEmailDelivery): Promise<void> {
  const reason = (bookingOfferEmailRetryReason[delivery.deliveryId] ?? "").trim();
  if (reason.length < 3) {
    pageError.value = "Enter why this one-time retry is safe (at least 3 characters).";
    return;
  }
  if (!window.confirm("Authorise the single manual retry for this offer email? This can send another email. Proceed only after verifying that the previous SMTP submission was not accepted.")) return;
  clearMessages();
  busy.value = true;
  try {
    await api.retryBookingOfferEmailDelivery(delivery.deliveryId, reason);
    bookingOfferEmailStatusFilter.value = "";
    bookingOfferEmailOffset.value = 0;
    await refreshBookingOfferEmailData();
    pageNotice.value = "One-time offer email retry queued. Further ambiguous submissions will require manual investigation and cannot be retried again.";
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
    if (!offerId) throw new Error("The issued offer is not available.");
    const customerUrl = new URL(`/offers/${encodeURIComponent(offerId)}`, window.location.origin);
    customerUrl.hash = new URLSearchParams({ token: bookingOfferAcceptanceToken.value }).toString();
    await navigator.clipboard.writeText(customerUrl.toString());
    pageNotice.value = "Customer offer link copied. It contains a private bearer capability; send it only to the intended customer over an approved channel.";
    pageError.value = "";
  } catch {
    pageError.value = "Clipboard access was denied. Copy the customer link manually.";
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
    pageError.value = "Enter an approval decision reason of at least 3 characters.";
    return;
  }
  if (!window.confirm("Record " + decision.replaceAll("_", " ") + " for approval rule " + requirement.ruleCode + "? This decision is immutable.")) return;
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
    pageNotice.value = "Approval decision recorded for rule " + requirement.ruleCode + ".";
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
    pageError.value = "Enter a booking-confirmation reason of at least 3 characters.";
    return;
  }
  if (!window.confirm("Confirm the booking from this exact accepted offer revision? This finalizes resource reservations and creates the booking record. Availability is checked transactionally by the server.")) return;
  clearMessages();
  busy.value = true;
  try {
    const result = await api.confirmBookingFromOffer(draftRevisionId, {
      expectedDraftRevisionId: draftRevisionId,
      confirmationReason: reason,
    });
    await Promise.all([refreshBookingDraft(), refreshInquiryDetail()]);
    await refreshBookingOfferData();
    pageNotice.value = "Booking " + result.data.bookingCode + " is " + result.data.status + (result.data.replayed ? " (existing confirmation)." : ".");
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
