<script setup lang="ts">
import { computed, onMounted, reactive, ref } from "vue";
import { api, ApiError, type CampaignReview, type CampaignProgress, type CampaignListItem, type DeliveryAttempt, type PageMeta, type EmailConfiguration, type ResendWebhookConfiguration, type Principal, type BookingInquiryListItem, type BookingInquiryDetail, type BookingInquiryAssignee, type BookingInquiryCapabilities, type BookingOfferRecord, type BookingOfferApprovalStatus, type BookingOfferApprovalRequirement, type BookingOfferWriteRequest, type BookingApprovalPolicy, type BookingApprovalRule } from "./api";

const principal = ref<Principal | null>(null);
const loadingSession = ref(true);
const activeTab = ref<"delivery" | "campaign" | "inquiries" | "approvals">("delivery");
const busy = ref(false);
const pageError = ref("");
const pageNotice = ref("");

const loginForm = reactive({ email: "", password: "", organizationSlug: "" });

const configuration = ref<EmailConfiguration | null>(null);
const emailForm = reactive({
  host: "",
  port: 587,
  transportSecurity: "starttls" as "starttls" | "implicit_tls",
  authMode: "password" as "none" | "password",
  senderEmail: "",
  senderName: "",
  replyTo: "",
  connectionTimeoutMs: 15000,
  username: "",
  password: "",
  clearCredentials: false,
});
const testRecipient = ref("");
const resendWebhook = ref<ResendWebhookConfiguration | null>(null);
const resendWebhookSigningSecret = ref("");
const isResendSmtp = computed(() => emailForm.host.trim().toLowerCase() === "smtp.resend.com");

const campaignId = ref("");
const campaign = ref<CampaignReview | null>(null);
const campaignProgress = ref<CampaignProgress | null>(null);
const deliveryAttempts = ref<DeliveryAttempt[]>([]);
const deliveryMeta = ref<PageMeta | null>(null);
const deliveryStatusFilter = ref("");
const deliveryOffset = ref(0);
const campaigns = ref<CampaignListItem[]>([]);
const campaignListMeta = ref<PageMeta | null>(null);
const campaignListOffset = ref(0);
const operatorResolution = reactive<Record<string, string>>({});
const operatorReason = reactive<Record<string, string>>({});

const inquiryRows = ref<BookingInquiryListItem[]>([]);
const inquiryMeta = ref<PageMeta | null>(null);
const inquiryOffset = ref(0);
const inquiryFilters = reactive({ status: "", assignedToMembershipId: "" });
const inquiryDetail = ref<BookingInquiryDetail | null>(null);
const inquiryAssignees = ref<BookingInquiryAssignee[]>([]);
const inquiryCapabilities = ref<BookingInquiryCapabilities>({
  canAssign: false,
  canManage: false,
  canAnnotate: false,
  canConvert: false,
  canReadDraft: false,
  canManageDraft: false,
});
const selectedInquiryId = ref("");
const inquiryAssignmentChoice = ref("unassigned");
type InquiryStatusCommand = "received" | "under_review" | "declined" | "spam";
const inquiryStatusChoice = ref<InquiryStatusCommand | "">("");
const inquiryStatusReason = ref("");
const inquiryAnnotationText = ref("");
const bookingDraftDetail = ref<import("./api").BookingDraftDetail | null>(null);
const bookingDraftEditorOpen = ref(false);
const bookingDraftValuesJson = ref("{}");
const bookingDraftSpaceLinesJson = ref("[]");
const bookingDraftResourceLinesJson = ref("[]");
const bookingDraftRequestedStart = ref("");
const bookingDraftRequestedEnd = ref("");
const bookingDraftTimezone = ref("Europe/Sarajevo");
const bookingDraftChangeReason = ref("");
const bookingOffer = ref<BookingOfferRecord | null>(null);
const bookingOfferApprovalStatus = ref<BookingOfferApprovalStatus | null>(null);
const bookingOfferIdInput = ref("");
const bookingOfferAcceptanceToken = ref("");
const bookingOfferConfirmationReason = ref("");
const bookingOfferIssueRequestKey = ref("");
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
const approvalPolicies = ref<BookingApprovalPolicy[]>([]);
const selectedApprovalPolicyId = ref("");
const approvalPolicyCreateForm = reactive({ code: "", name: "" });
const approvalPolicyRulesJson = ref("[]");
const selectedApprovalPolicy = computed(() =>
  approvalPolicies.value.find((policy) => policy.policyId === selectedApprovalPolicyId.value) ?? null,
);
const selectedApprovalPolicyLatestRevision = computed(() => {
  const policy = selectedApprovalPolicy.value;
  return policy?.revisions.find((revision) => revision.revisionId === policy.latestRevisionId)
    ?? policy?.revisions[0]
    ?? null;
});

const selectedOrganization = computed(() =>
  principal.value?.memberships?.find((membership) => membership.selected)?.organizationName
  ?? principal.value?.organizationId
  ?? "",
);
const canQueue = computed(() => campaign.value?.status === "confirmed");
const canConfirm = computed(() => campaign.value?.status === "previewed");
const canCancel = computed(() => campaign.value?.status === "queued");
const canEditInquiryAssignment = computed(() =>
  inquiryCapabilities.value.canAssign &&
  (inquiryDetail.value?.status === "received" || inquiryDetail.value?.status === "under_review"),
);
const canConvertInquiry = computed(() =>
  inquiryCapabilities.value.canConvert &&
  (inquiryDetail.value?.status === "received" || inquiryDetail.value?.status === "under_review"),
);
const canReadBookingDraft = computed(() =>
  inquiryCapabilities.value.canReadDraft && Boolean(inquiryDetail.value?.bookingDraft),
);
const canManageBookingDraft = computed(() =>
  inquiryCapabilities.value.canManageDraft &&
  bookingDraftDetail.value?.status === "draft" &&
  Boolean(bookingDraftDetail.value.currentRevision),
);
const canManageBookingOffer = computed(() =>
  inquiryCapabilities.value.canManageDraft &&
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
const inquiryStatusTargets = computed<InquiryStatusCommand[]>(() => {
  if (inquiryDetail.value?.status === "received") return ["under_review", "declined", "spam"];
  if (inquiryDetail.value?.status === "under_review") return ["received", "declined", "spam"];
  return [];
});
const inquiryAnswerItems = computed(() => {
  const detail = inquiryDetail.value;
  if (!detail) return [];
  const fields = new Map(detail.fieldSchema.fields.map((field) => [field.code, field]));
  return Object.entries(detail.submittedValues?.answers ?? {}).map(([code, value]) => {
    const field = fields.get(code);
    const displayValue = Array.isArray(value)
      ? value.map((item) => formatInquiryAnswer(field, item)).join(", ")
      : formatInquiryAnswer(field, value);
    return {
      code,
      label: field?.label?.trim() || code.replaceAll("_", " "),
      type: field?.type ?? "unknown",
      value: displayValue,
    };
  });
});

function formatInquiryAnswer(
  field: BookingInquiryDetail["fieldSchema"]["fields"][number] | undefined,
  value: unknown,
): string {
  if (value === null || value === undefined || value === "") return "—";
  if (typeof value === "boolean") return value ? "Yes" : "No";
  if ((field?.type === "select" || field?.type === "multiselect") && typeof value === "string") {
    return field.options?.find((option) => option.value === value)?.label ?? value;
  }
  if (value && typeof value === "object") return JSON.stringify(value);
  return String(value);
}

function assigneeName(membershipId: string | null): string {
  if (!membershipId) return "Unassigned";
  if (membershipId === principal.value?.membershipId) return "You";
  return inquiryAssignees.value.find((item) => item.membershipId === membershipId)?.displayName
    ?? "Assigned member";
}

function formatInquiryDate(value: string | null | undefined): string {
  if (!value) return "Not provided";
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? value : parsed.toLocaleString();
}

function formatBookingMoney(value: string | number, currency: string): string {
  const amount = Number(value);
  if (!Number.isFinite(amount)) return String(value) + " " + currency;
  try {
    return new Intl.NumberFormat(undefined, { style: "currency", currency }).format(amount);
  } catch {
    return amount.toFixed(2) + " " + currency;
  }
}

function clearMessages(): void {
  pageError.value = "";
  pageNotice.value = "";
}

function clearBookingDraftState(): void {
  bookingDraftDetail.value = null;
  bookingDraftEditorOpen.value = false;
  bookingDraftValuesJson.value = "{}";
  bookingDraftSpaceLinesJson.value = "[]";
  bookingDraftResourceLinesJson.value = "[]";
  bookingDraftRequestedStart.value = "";
  bookingDraftRequestedEnd.value = "";
  bookingDraftTimezone.value = "Europe/Sarajevo";
  bookingDraftChangeReason.value = "";
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
}

function showError(error: unknown): void {
  if (error instanceof ApiError) {
    if (error.status === 401) {
      principal.value = null;
      configuration.value = null;
      resendWebhook.value = null;
      campaign.value = null;
      inquiryRows.value = [];
      inquiryDetail.value = null;
      inquiryAssignees.value = [];
      selectedInquiryId.value = "";
      clearBookingDraftState();
      inquiryCapabilities.value = {
        canAssign: false, canManage: false, canAnnotate: false, canConvert: false,
        canReadDraft: false, canManageDraft: false,
      };
      pageError.value = "Your session has expired. Please sign in again.";
      return;
    }
    if (error.status === 403) {
      pageError.value = `Permission denied: ${error.message}`;
      return;
    }
    pageError.value = `${error.message} [${error.code}]`;
    return;
  }
  pageError.value = error instanceof Error ? error.message : "An unexpected error occurred.";
}

async function loadConfiguration(): Promise<void> {
  const [result, webhook] = await Promise.all([
    api.getEmailConfiguration(),
    api.getResendWebhookConfiguration(),
  ]);
  configuration.value = result.data;
  resendWebhook.value = webhook.data;
  const settings = result.data?.settings;
  if (settings) {
    emailForm.host = settings.host;
    emailForm.port = settings.port;
    emailForm.transportSecurity = settings.transportSecurity;
    emailForm.authMode = settings.authMode;
    emailForm.senderEmail = settings.senderEmail;
    emailForm.senderName = settings.senderName ?? "";
    emailForm.replyTo = settings.replyTo ?? "";
    emailForm.connectionTimeoutMs = settings.connectionTimeoutMs ?? 15000;
  }
}

async function refreshSession(): Promise<void> {
  loadingSession.value = true;
  try {
    const result = await api.me();
    principal.value = result.data;
    await loadConfiguration();
  } catch (error) {
    if (error instanceof ApiError && error.status === 401) {
      principal.value = null;
    } else {
      showError(error);
    }
  } finally {
    loadingSession.value = false;
  }
}

async function signIn(): Promise<void> {
  clearMessages();
  busy.value = true;
  try {
    await api.login({
      email: loginForm.email.trim(),
      password: loginForm.password,
      organizationSlug: loginForm.organizationSlug.trim(),
    });
    loginForm.password = "";
    await refreshSession();
    if (principal.value) pageNotice.value = "Signed in successfully.";
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function signOut(): Promise<void> {
  clearMessages();
  busy.value = true;
  try {
    await api.logout();
    principal.value = null;
    configuration.value = null;
    resendWebhook.value = null;
    campaign.value = null;
    inquiryRows.value = [];
    inquiryDetail.value = null;
    inquiryAssignees.value = [];
    selectedInquiryId.value = "";
    clearBookingDraftState();
    inquiryCapabilities.value = {
      canAssign: false, canManage: false, canAnnotate: false, canConvert: false,
      canReadDraft: false, canManageDraft: false,
    };
    pageNotice.value = "You have been signed out.";
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

function emailConfigurationPayload(): Record<string, unknown> {
  const body: Record<string, unknown> = {
    host: emailForm.host.trim(),
    port: Number(emailForm.port),
    transportSecurity: emailForm.transportSecurity,
    authMode: emailForm.authMode,
    senderEmail: emailForm.senderEmail.trim(),
    senderName: emailForm.senderName.trim(),
    replyTo: emailForm.replyTo.trim(),
    connectionTimeoutMs: Number(emailForm.connectionTimeoutMs),
  };
  const username = emailForm.username.trim();
  const password = emailForm.password;
  if (!emailForm.clearCredentials && emailForm.authMode === "password" && (username || password)) {
    if (!username || !password) throw new Error("Enter both SMTP username and password, or leave both blank to retain the stored credentials.");
    body.credentials = { username, password };
  }
  if (emailForm.clearCredentials) body.clearCredentials = true;
  return body;
}

async function saveConfiguration(): Promise<void> {
  clearMessages();
  busy.value = true;
  try {
    await api.saveEmailConfiguration(emailConfigurationPayload());
    emailForm.password = "";
    emailForm.username = "";
    emailForm.clearCredentials = false;
    await loadConfiguration();
    pageNotice.value = "A new SMTP configuration revision was saved. Send a test email to enable this revision for campaign delivery.";
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function sendTest(): Promise<void> {
  clearMessages();
  busy.value = true;
  try {
    await api.sendEmailTest(testRecipient.value.trim());
    await loadConfiguration();
    pageNotice.value = "The SMTP test message was accepted by the configured SMTP server. The current configuration revision is now enabled for queueing.";
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function prepareResendWebhook(): Promise<void> {
  clearMessages();
  if (!isResendSmtp.value) {
    pageError.value = "Set the SMTP host to smtp.resend.com before preparing the Resend callback.";
    return;
  }
  if (!window.confirm("Prepare a new Resend callback URL? This replaces the previous Eventor endpoint and disables its previous signing secret.")) return;
  busy.value = true;
  try {
    const result = await api.prepareResendWebhook();
    resendWebhook.value = {
      endpointId: result.data.endpointId,
      configured: false,
      callbackUrl: result.data.callbackUrl,
    };
    resendWebhookSigningSecret.value = "";
    pageNotice.value = "Callback URL prepared. Add it as a Resend webhook for email.delivered and email.bounced, then paste the generated whsec_ signing secret below.";
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function activateResendWebhook(): Promise<void> {
  clearMessages();
  const endpointId = resendWebhook.value?.endpointId;
  const secret = resendWebhookSigningSecret.value.trim();
  if (!endpointId || !resendWebhook.value?.callbackUrl) {
    pageError.value = "Prepare the callback URL first.";
    return;
  }
  if (!/^whsec_[A-Za-z0-9+/]+={0,2}$/.test(secret) || secret.length < 24) {
    pageError.value = "Paste the Resend webhook signing secret beginning with whsec_.";
    return;
  }
  busy.value = true;
  try {
    await api.activateResendWebhook(endpointId, secret);
    resendWebhookSigningSecret.value = "";
    await loadConfiguration();
    pageNotice.value = "Resend callback signature verification is enabled. Delivered and bounced events can now update matching attempts.";
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function copyResendWebhookUrl(): Promise<void> {
  const url = resendWebhook.value?.callbackUrl;
  if (!url) return;
  try {
    await navigator.clipboard.writeText(url);
    pageNotice.value = "Resend callback URL copied.";
    pageError.value = "";
  } catch {
    pageError.value = "Clipboard access was denied. Select and copy the callback URL manually.";
  }
}

async function loadCampaign(): Promise<void> {
  clearMessages();
  const id = campaignId.value.trim();
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) {
    pageError.value = "Enter a valid campaign UUID.";
    return;
  }
  busy.value = true;
  try {
    const result = await api.getCampaignReview(id);
    campaign.value = result.data;
    deliveryOffset.value = 0;
    deliveryStatusFilter.value = "";
    await refreshCampaignDeliveryData();
    pageNotice.value = "Campaign review and delivery report loaded. Recipient contact details are intentionally not exposed here.";
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function loadCampaignList(offset = 0): Promise<void> {
  clearMessages();
  busy.value = true;
  try {
    const result = await api.getCampaigns({ limit: 25, offset });
    campaigns.value = result.data;
    campaignListMeta.value = result.meta;
    campaignListOffset.value = offset;
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function openListedCampaign(item: CampaignListItem): Promise<void> {
  campaignId.value = item.campaignId;
  await loadCampaign();
}

async function refreshCampaignDeliveryData(): Promise<void> {
  if (!campaign.value) return;
  const [progress, deliveries] = await Promise.all([
    api.getCampaignProgress(campaign.value.campaignId),
    api.getCampaignDeliveries(campaign.value.campaignId, {
      status: deliveryStatusFilter.value || undefined,
      limit: 25,
      offset: deliveryOffset.value,
    }),
  ]);
  campaignProgress.value = progress.data;
  deliveryAttempts.value = deliveries.data;
  deliveryMeta.value = deliveries.meta;
}

async function reconcileDeliveryAttempt(attempt: DeliveryAttempt): Promise<void> {
  const resolution = operatorResolution[attempt.attemptId] ?? "";
  const reason = (operatorReason[attempt.attemptId] ?? "").trim();
  if (!resolution) {
    pageError.value = "Choose the verified delivery outcome before reconciling this attempt.";
    return;
  }
  if (reason.length < 3) {
    pageError.value = "Enter an audit reason of at least 3 characters.";
    return;
  }
  const labels: Record<string, string> = {
    confirmed_sent: "confirmed SMTP/provider acceptance",
    confirmed_not_sent: "confirmed not accepted",
    confirmed_delivered: "confirmed delivered",
    confirmed_bounced: "confirmed bounced",
  };
  if (!window.confirm(`Record that this attempt was ${labels[resolution]}? This records an audited decision and does not send a message.`)) return;
  clearMessages();
  busy.value = true;
  try {
    await api.reconcileDeliveryAttempt(attempt.attemptId, { resolution, reason });
    await refreshCampaignDeliveryData();
    pageNotice.value = "The delivery attempt was reconciled. No message was sent.";
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function retryDeliveryAttempt(attempt: DeliveryAttempt): Promise<void> {
  const reason = (operatorReason[attempt.attemptId] ?? "").trim();
  if (reason.length < 3) {
    pageError.value = "Enter an audit reason of at least 3 characters before retrying.";
    return;
  }
  if (!window.confirm("Authorize a new delivery attempt? This may send another message. Only use it after confirming the previous attempt was not accepted.")) return;
  clearMessages();
  busy.value = true;
  try {
    await api.retryDeliveryAttempt(attempt.attemptId, reason);
    await refreshCampaignDeliveryData();
    pageNotice.value = "A distinct retry attempt was queued under your authorization.";
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function runCampaignAction(action: "confirm" | "queue" | "cancel"): Promise<void> {
  if (!campaign.value) return;
  const labels = {
    confirm: "Confirm this reviewed campaign? This records authorization but does not send messages.",
    queue: "Queue this confirmed campaign for delivery? The worker may begin sending immediately.",
    cancel: "Cancel this queued campaign? This is only possible before the first delivery attempt starts.",
  };
  if (!window.confirm(labels[action])) return;

  clearMessages();
  busy.value = true;
  try {
    if (action === "confirm") await api.confirmCampaign(campaign.value.campaignId);
    if (action === "queue") await api.queueCampaign(campaign.value.campaignId);
    if (action === "cancel") await api.cancelCampaign(campaign.value.campaignId);
    const result = await api.getCampaignReview(campaign.value.campaignId);
    campaign.value = result.data;
    await refreshCampaignDeliveryData();
    pageNotice.value = action === "confirm"
      ? "Campaign confirmed. No messages have been queued or sent."
      : action === "queue"
        ? "Campaign queued. Delivery is handled asynchronously by the worker."
        : "Campaign cancelled before sending began.";
  } catch (error) {
    showError(error);
    try {
      const result = await api.getCampaignReview(campaign.value.campaignId);
      campaign.value = result.data;
    } catch {
      // Keep the original command error visible.
    }
  } finally {
    busy.value = false;
  }
}

async function refreshInquiryListData(offset = inquiryOffset.value): Promise<void> {
  if (!principal.value) return;
  const organizationId = principal.value.organizationId;
  const [list, capabilities] = await Promise.all([
    api.getBookingInquiries(organizationId, {
      status: inquiryFilters.status || undefined,
      assignedToMembershipId: inquiryFilters.assignedToMembershipId || undefined,
      limit: 25,
      offset,
    }),
    api.getBookingInquiryCapabilities(organizationId),
  ]);
  inquiryRows.value = list.data;
  inquiryMeta.value = list.meta;
  inquiryOffset.value = offset;
  inquiryCapabilities.value = capabilities.data;
  if (!capabilities.data.canReadDraft) clearBookingDraftState();
  inquiryAssignees.value = capabilities.data.canAssign
    ? (await api.getBookingInquiryAssignees(organizationId)).data
    : [];
}

async function refreshInquiryDetailData(): Promise<void> {
  if (!selectedInquiryId.value) return;
  const result = await api.getBookingInquiry(selectedInquiryId.value);
  inquiryDetail.value = result.data;
  if (!result.data.bookingDraft) clearBookingDraftState();
  inquiryAssignmentChoice.value = result.data.assignedToMembershipId ?? "unassigned";
  inquiryStatusChoice.value = "";
}

async function loadInquiryList(offset = 0): Promise<void> {
  clearMessages();
  busy.value = true;
  try {
    await refreshInquiryListData(offset);
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function openInquiryWorkspace(): Promise<void> {
  activeTab.value = "inquiries";
  await loadInquiryList(0);
}

async function openInquiry(item: BookingInquiryListItem): Promise<void> {
  clearMessages();
  selectedInquiryId.value = item.inquiryId;
  inquiryStatusReason.value = "";
  inquiryAnnotationText.value = "";
  clearBookingDraftState();
  busy.value = true;
  try {
    await refreshInquiryDetailData();
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function refreshInquiryDetail(): Promise<void> {
  if (!selectedInquiryId.value) return;
  busy.value = true;
  try {
    await Promise.all([refreshInquiryDetailData(), refreshInquiryListData()]);
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function saveInquiryAssignment(): Promise<void> {
  const detail = inquiryDetail.value;
  if (!detail || !inquiryCapabilities.value.canAssign) return;
  const assignedToMembershipId = inquiryAssignmentChoice.value === "unassigned"
    ? null
    : inquiryAssignmentChoice.value;
  if (assignedToMembershipId === detail.assignedToMembershipId) {
    pageNotice.value = "The assignment has not changed.";
    return;
  }
  const nextName = assigneeName(assignedToMembershipId);
  if (!window.confirm(`Assign ${detail.publicReference} to ${nextName}?`)) return;
  clearMessages();
  busy.value = true;
  try {
    await api.assignBookingInquiry(detail.inquiryId, assignedToMembershipId);
    await Promise.all([refreshInquiryDetailData(), refreshInquiryListData()]);
    pageNotice.value = "Inquiry assignment saved.";
  } catch (error) {
    showError(error);
    inquiryAssignmentChoice.value = detail.assignedToMembershipId ?? "unassigned";
  } finally {
    busy.value = false;
  }
}

async function saveInquiryStatus(): Promise<void> {
  const detail = inquiryDetail.value;
  const status = inquiryStatusChoice.value;
  const reason = inquiryStatusReason.value.trim();
  if (!detail || !inquiryCapabilities.value.canManage || !status) return;
  if (reason.length < 3) {
    pageError.value = "Enter an audit reason of at least 3 characters.";
    return;
  }
  if (!window.confirm(
    status === "declined" || status === "spam"
      ? `Move ${detail.publicReference} to ${status}? This is a terminal status and cannot be reopened.`
      : `Change ${detail.publicReference} to ${status.replaceAll("_", " ")}?`,
  )) return;
  clearMessages();
  busy.value = true;
  try {
    await api.changeBookingInquiryStatus(detail.inquiryId, { status, reason });
    inquiryStatusReason.value = "";
    await Promise.all([refreshInquiryDetailData(), refreshInquiryListData()]);
    pageNotice.value = `Inquiry status changed to ${status.replaceAll("_", " ")}.`;
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function saveInquiryConversion(): Promise<void> {
  const detail = inquiryDetail.value;
  if (!detail || !canConvertInquiry.value) return;
  if (!window.confirm(
    `Convert ${detail.publicReference} into a separate booking draft? The original inquiry will be preserved, but its status will become converted. This does not issue an offer, reserve resources or confirm a booking.`,
  )) return;

  clearMessages();
  busy.value = true;
  try {
    const result = await api.convertBookingInquiryToDraft(detail.inquiryId);
    await Promise.all([refreshInquiryDetailData(), refreshInquiryListData()]);
    pageNotice.value = result.data.changed
      ? `Booking draft created (revision ${result.data.revisionNumber}). Draft ID: ${result.data.draftId}. No offer or reservation has been created.`
      : `This inquiry was already converted. Existing draft ID: ${result.data.draftId}.`;
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

function populateBookingDraftEditor(draft: import("./api").BookingDraftDetail): void {
  const revision = draft.currentRevision;
  bookingDraftValuesJson.value = JSON.stringify(revision?.values ?? {}, null, 2);
  bookingDraftSpaceLinesJson.value = JSON.stringify(
    (revision?.spaceLines ?? []).map((line) => ({
      venueSpaceId: line.venueSpaceId,
      startsAt: line.startsAt,
      endsAt: line.endsAt,
      blockKind: line.blockKind,
      ...(line.requestedCapacity === null ? {} : { requestedCapacity: line.requestedCapacity }),
    })),
    null,
    2,
  );
  bookingDraftResourceLinesJson.value = JSON.stringify(
    (revision?.resourceLines ?? []).map((line) => ({
      resourceTypeId: line.resourceTypeId,
      requestedQuantity: line.requestedQuantity,
      values: line.values,
    })),
    null,
    2,
  );
  bookingDraftRequestedStart.value = revision?.requestedStart ?? "";
  bookingDraftRequestedEnd.value = revision?.requestedEnd ?? "";
  bookingDraftTimezone.value = revision?.timezone ?? "Europe/Sarajevo";
  bookingDraftChangeReason.value = "";
}

async function openBookingDraft(): Promise<void> {
  const draftReference = inquiryDetail.value?.bookingDraft;
  if (!draftReference || !inquiryCapabilities.value.canReadDraft) return;
  clearMessages();
  busy.value = true;
  try {
    const result = await api.getBookingDraft(draftReference.draftId);
    bookingDraftDetail.value = result.data;
    populateBookingDraftEditor(result.data);
    bookingDraftEditorOpen.value = true;
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function refreshBookingDraft(): Promise<void> {
  const draftId = bookingDraftDetail.value?.draftId;
  if (!draftId) return;
  const result = await api.getBookingDraft(draftId);
  bookingDraftDetail.value = result.data;
  populateBookingDraftEditor(result.data);
}

async function saveBookingDraftRevision(): Promise<void> {
  const draft = bookingDraftDetail.value;
  const revision = draft?.currentRevision;
  if (!draft || !revision || !canManageBookingDraft.value) return;

  let values: Record<string, unknown>;
  let spaceLines: Array<Record<string, unknown>>;
  let resourceLines: Array<Record<string, unknown>>;
  try {
    const parsedValues: unknown = JSON.parse(bookingDraftValuesJson.value);
    const parsedSpaces: unknown = JSON.parse(bookingDraftSpaceLinesJson.value);
    const parsedResources: unknown = JSON.parse(bookingDraftResourceLinesJson.value);
    if (!parsedValues || typeof parsedValues !== "object" || Array.isArray(parsedValues)) {
      throw new Error("Values must be a JSON object.");
    }
    if (!Array.isArray(parsedSpaces) || !Array.isArray(parsedResources)) {
      throw new Error("Space lines and resource lines must each be JSON arrays.");
    }
    values = parsedValues as Record<string, unknown>;
    spaceLines = parsedSpaces as Array<Record<string, unknown>>;
    resourceLines = parsedResources as Array<Record<string, unknown>>;
  } catch (error) {
    pageError.value = error instanceof Error ? error.message : "The draft JSON is invalid.";
    return;
  }
  const reason = bookingDraftChangeReason.value.trim();
  if (reason.length < 3) {
    pageError.value = "Enter a change reason of at least 3 characters.";
    return;
  }
  const nextRevision = draft.currentRevisionNumber + 1;
  if (!window.confirm(
    `Save these changes as immutable draft revision ${nextRevision}? Revision ${draft.currentRevisionNumber} will remain unchanged.`,
  )) return;

  clearMessages();
  busy.value = true;
  try {
    const result = await api.createBookingDraftRevision(draft.draftId, {
      expectedRevisionNumber: draft.currentRevisionNumber,
      values,
      requestedStart: bookingDraftRequestedStart.value.trim() || null,
      requestedEnd: bookingDraftRequestedEnd.value.trim() || null,
      timezone: bookingDraftTimezone.value.trim(),
      spaceLines: spaceLines as Array<{
        venueSpaceId: string;
        startsAt: string;
        endsAt: string;
        blockKind: "setup" | "rehearsal" | "event_use" | "teardown" | "buffer";
        requestedCapacity?: number;
      }>,
      resourceLines: resourceLines as Array<{
        resourceTypeId: string;
        requestedQuantity: number;
        values?: Record<string, unknown>;
      }>,
      changeReason: reason,
    });
    await Promise.all([refreshBookingDraft(), refreshInquiryDetailData()]);
    pageNotice.value = `Booking draft revision ${result.data.revisionNumber} created. Earlier revisions remain immutable.`;
  } catch (error) {
    showError(error);
    if (error instanceof ApiError && error.status === 412) {
      try { await refreshBookingDraft(); } catch { /* retain the original stale-revision message */ }
    }
  } finally {
    busy.value = false;
  }
}

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
  if (bookingOfferTaxAmount.value.trim() === "") throw new Error("Enter the tax amount. Use zero only when the approved tax treatment calls for zero.");
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
    pageNotice.value = "Offer issued. Copy the capability now and deliver it to the customer through an approved channel. Automatic offer email and the customer-facing browser page are not part of this UI slice.";
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function copyBookingOfferCapability(): Promise<void> {
  if (!bookingOfferAcceptanceToken.value) return;
  try {
    await navigator.clipboard.writeText(bookingOfferAcceptanceToken.value);
    pageNotice.value = "Customer offer capability copied. Treat it as a bearer secret and do not paste it into internal notes or tickets.";
    pageError.value = "";
  } catch {
    pageError.value = "Clipboard access was denied. Select and copy the capability manually.";
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
    await Promise.all([refreshBookingDraft(), refreshInquiryDetailData()]);
    await refreshBookingOfferData();
    pageNotice.value = "Booking " + result.data.bookingCode + " is " + result.data.status + (result.data.replayed ? " (existing confirmation)." : ".");
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function loadBookingApprovalPolicies(): Promise<void> {
  const result = await api.getBookingApprovalPolicies();
  approvalPolicies.value = result.data;
  if (selectedApprovalPolicyId.value && !result.data.some((policy) => policy.policyId === selectedApprovalPolicyId.value)) {
    selectedApprovalPolicyId.value = "";
  }
  if (!selectedApprovalPolicyId.value && result.data.length) {
    selectedApprovalPolicyId.value = result.data[0]!.policyId;
  }
  const revision = selectedApprovalPolicyLatestRevision.value;
  if (revision?.state === "draft") {
    approvalPolicyRulesJson.value = JSON.stringify(revision.rules, null, 2);
  }
}

async function openBookingApprovalPolicies(): Promise<void> {
  activeTab.value = "approvals";
  clearMessages();
  busy.value = true;
  try {
    await loadBookingApprovalPolicies();
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

function selectBookingApprovalPolicy(policyId: string): void {
  selectedApprovalPolicyId.value = policyId;
  const revision = selectedApprovalPolicyLatestRevision.value;
  approvalPolicyRulesJson.value = JSON.stringify(revision?.rules ?? [], null, 2);
}

async function createBookingApprovalPolicy(): Promise<void> {
  const code = approvalPolicyCreateForm.code.trim();
  const name = approvalPolicyCreateForm.name.trim();
  if (code.length < 2 || code.length > 80 || name.length < 1 || name.length > 250) {
    pageError.value = "Enter a policy code (2–80 characters) and name (1–250 characters).";
    return;
  }
  if (!window.confirm("Create a new organization approval policy? Its initial revision is an empty draft; it will not affect existing offers until published and selected for a new offer.")) return;
  clearMessages();
  busy.value = true;
  try {
    const result = await api.createBookingApprovalPolicy({ code, name });
    approvalPolicyCreateForm.code = "";
    approvalPolicyCreateForm.name = "";
    selectedApprovalPolicyId.value = result.data.policyId;
    await loadBookingApprovalPolicies();
    pageNotice.value = "Approval policy created. Its first revision is an empty draft. Create a rules revision and publish it before using it on offers.";
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function createBookingApprovalPolicyRevision(): Promise<void> {
  const policy = selectedApprovalPolicy.value;
  if (!policy || policy.status !== "active") return;
  let parsed: unknown;
  try {
    parsed = JSON.parse(approvalPolicyRulesJson.value);
    if (!Array.isArray(parsed)) throw new Error("Rules must be a JSON array.");
    if (parsed.length > 50) throw new Error("A policy may contain no more than 50 rules.");
    for (const item of parsed) {
      if (!item || typeof item !== "object" || Array.isArray(item)) throw new Error("Each rule must be a JSON object.");
      const rule = item as Record<string, unknown>;
      if (typeof rule.code !== "string" || typeof rule.condition !== "object" || !rule.condition ||
          typeof rule.requiredApprovals !== "number" || typeof rule.permission !== "string" ||
          typeof rule.separationOfDuties !== "boolean") {
        throw new Error("Each rule needs code, condition, requiredApprovals, permission and separationOfDuties.");
      }
    }
  } catch (error) {
    pageError.value = error instanceof Error ? error.message : "Approval policy rules are invalid JSON.";
    return;
  }
  if (!window.confirm("Create a new immutable draft revision of this approval policy? Any existing offers keep their already-pinned approval requirements.")) return;
  clearMessages();
  busy.value = true;
  try {
    const result = await api.createBookingApprovalPolicyRevision(policy.policyId, parsed as BookingApprovalRule[]);
    await loadBookingApprovalPolicies();
    pageNotice.value = "Approval policy revision " + result.data.revisionNumber + " created as a draft. Earlier published revisions and offer snapshots remain unchanged.";
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function publishBookingApprovalPolicyRevision(): Promise<void> {
  const policy = selectedApprovalPolicy.value;
  const revision = selectedApprovalPolicyLatestRevision.value;
  if (!policy || !revision || revision.state !== "draft") return;
  if (!window.confirm("Publish approval policy revision " + revision.revisionNumber + "? Published revisions are immutable. Existing offer revisions retain their original approval-rule snapshot.")) return;
  clearMessages();
  busy.value = true;
  try {
    await api.publishBookingApprovalPolicyRevision(policy.policyId, revision.revisionId);
    await loadBookingApprovalPolicies();
    pageNotice.value = "Approval policy revision published. New offer revisions may now pin this policy revision.";
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

async function saveInquiryAnnotation(): Promise<void> {
  const detail = inquiryDetail.value;
  const annotation = inquiryAnnotationText.value.trim();
  if (!detail || !inquiryCapabilities.value.canAnnotate) return;
  if (annotation.length < 1 || annotation.length > 4000) {
    pageError.value = "Enter an internal note between 1 and 4,000 characters.";
    return;
  }
  clearMessages();
  busy.value = true;
  try {
    await api.addBookingInquiryAnnotation(detail.inquiryId, annotation);
    inquiryAnnotationText.value = "";
    await refreshInquiryDetailData();
    pageNotice.value = "Internal note added. It is visible only to authorized staff.";
  } catch (error) {
    showError(error);
  } finally {
    busy.value = false;
  }
}

onMounted(() => { void refreshSession(); });
</script>

<template>
  <main class="app-shell">
    <header class="topbar">
      <a class="brand" href="/" aria-label="Eventor staff home">
        <span class="brand-mark">E</span>
        <span>EVENTOR <small>STAFF WORKSPACE</small></span>
      </a>
      <div v-if="principal" class="account">
        <div class="account-copy">
          <strong>{{ selectedOrganization }}</strong>
          <span>Authenticated staff session</span>
        </div>
        <button class="button button-quiet" :disabled="busy" @click="signOut">Sign out</button>
      </div>
    </header>

    <section v-if="loadingSession" class="loading-panel" aria-live="polite">
      <span class="spinner"></span> Checking staff session…
    </section>

    <section v-else-if="!principal" class="login-layout">
      <div class="intro-panel">
        <p class="eyebrow">EVENT OPERATIONS PLATFORM</p>
        <h1>One workspace for the work behind every event.</h1>
        <p class="muted">Sign in to manage organization delivery settings and authorized event notification workflows.</p>
        <div class="security-note"><span class="status-dot"></span> Protected staff access · Secure session · CSRF validation</div>
      </div>
      <form class="panel login-panel" @submit.prevent="signIn">
        <p class="eyebrow">STAFF ACCESS</p>
        <h2>Sign in</h2>
        <label>Email address<input v-model="loginForm.email" type="email" autocomplete="username" required maxlength="320" /></label>
        <label>Organization slug<input v-model="loginForm.organizationSlug" autocomplete="organization" required minlength="2" maxlength="80" /></label>
        <label>Password<input v-model="loginForm.password" type="password" autocomplete="current-password" required minlength="12" maxlength="1024" /></label>
        <button class="button button-primary full-width" type="submit" :disabled="busy">
          {{ busy ? "Signing in…" : "Sign in securely" }}
        </button>
        <p class="fine-print">Your password is sent only to the configured Eventor API over HTTPS. Session cookies are HttpOnly and Secure.</p>
      </form>
    </section>

    <template v-else>
      <section class="welcome-row">
        <div>
          <p class="eyebrow">ORGANIZATION WORKSPACE</p>
          <h1>Operations overview</h1>
          <p class="muted">Manage delivery readiness and review notification campaigns before authorizing sends.</p>
        </div>
        <div class="session-chip"><span class="status-dot"></span> Session active</div>
      </section>

      <nav class="tabs" aria-label="Staff workspace sections">
        <button :class="{ active: activeTab === 'delivery' }" @click="activeTab = 'delivery'">Email delivery</button>
        <button :class="{ active: activeTab === 'campaign' }" @click="activeTab = 'campaign'">Campaign review</button>
        <button :class="{ active: activeTab === 'inquiries' }" @click="openInquiryWorkspace">Booking inquiries</button>
        <button :class="{ active: activeTab === 'approvals' }" @click="openBookingApprovalPolicies">Approval policies</button>
      </nav>

      <section v-if="activeTab === 'delivery'" class="content-grid">
        <div class="panel main-panel">
          <div class="section-heading">
            <div><p class="eyebrow">ORGANIZATION SETTINGS</p><h2>SMTP configuration</h2></div>
            <span v-if="configuration?.deliveryEnabled" class="pill pill-success">Tested · enabled</span>
            <span v-else class="pill pill-warning">Not enabled</span>
          </div>
          <p class="muted">Configure the organization’s own SMTP server. Credentials are write-only and are encrypted by the API before storage.</p>
          <form class="settings-form" @submit.prevent="saveConfiguration">
            <div class="field-grid">
              <label>SMTP host<input v-model="emailForm.host" type="text" required maxlength="253" placeholder="mail.example.org" /></label>
              <label>Port<input v-model.number="emailForm.port" type="number" min="1" max="65535" required /></label>
              <label>Transport security
                <select v-model="emailForm.transportSecurity">
                  <option value="starttls">STARTTLS (required TLS)</option>
                  <option value="implicit_tls">Implicit TLS</option>
                </select>
              </label>
              <label>Authentication
                <select v-model="emailForm.authMode">
                  <option value="password">Username and password</option>
                  <option value="none">No authentication</option>
                </select>
              </label>
              <label>Sender email<input v-model="emailForm.senderEmail" type="email" required maxlength="320" placeholder="events@example.org" /></label>
              <label>Sender name<input v-model="emailForm.senderName" type="text" maxlength="200" placeholder="Eventor" /></label>
              <label>Reply-to address<input v-model="emailForm.replyTo" type="email" maxlength="320" placeholder="Optional" /></label>
              <label>Connection timeout (ms)<input v-model.number="emailForm.connectionTimeoutMs" type="number" min="1000" max="60000" /></label>
            </div>
            <div v-if="emailForm.authMode === 'password'" class="credential-box">
              <div class="credential-heading">
                <div><strong>SMTP credentials</strong><p>{{ configuration?.credentialsConfigured ? "Credentials are stored. Leave both fields blank to retain them." : "No credentials are currently stored." }}</p></div>
                <span class="lock-icon">LOCKED</span>
              </div>
              <div class="field-grid">
                <label>Username<input v-model="emailForm.username" type="text" autocomplete="off" maxlength="320" placeholder="Leave blank to retain current" /></label>
                <label>Password<input v-model="emailForm.password" type="password" autocomplete="new-password" maxlength="4096" placeholder="Write-only · never displayed" /></label>
              </div>
            </div>
            <label v-if="configuration?.credentialsConfigured && emailForm.authMode === 'password'" class="check-row">
              <input v-model="emailForm.clearCredentials" type="checkbox" /> Clear the currently stored credentials
            </label>
            <div class="form-actions">
              <button class="button button-primary" type="submit" :disabled="busy">{{ busy ? "Saving…" : "Save new revision" }}</button>
              <span v-if="configuration?.revision" class="fine-print">Current revision {{ configuration.revision }}</span>
            </div>
          </form>
        </div>

        <aside class="panel side-panel">
          <p class="eyebrow">DELIVERY READINESS</p>
          <h3>Test before sending</h3>
          <div class="readiness-row"><span>Configuration</span><strong>{{ configuration?.revision ? `Revision ${configuration.revision}` : "Not configured" }}</strong></div>
          <div class="readiness-row"><span>Credentials</span><strong>{{ configuration?.credentialsConfigured ? "Stored securely" : emailForm.authMode === "none" ? "Not required" : "Missing" }}</strong></div>
          <div class="readiness-row"><span>SMTP test</span><strong :class="configuration?.deliveryEnabled ? 'text-success' : 'text-warning'">{{ configuration?.deliveryEnabled ? "Passed" : "Required" }}</strong></div>
          <div class="divider"></div>
          <form @submit.prevent="sendTest">
            <label>Test recipient<input v-model="testRecipient" type="email" required maxlength="320" placeholder="your-address@example.org" /></label>
            <button class="button button-secondary full-width" type="submit" :disabled="busy || !configuration?.revision">Send test email</button>
          </form>
          <p class="fine-print">A successful test enables only the tested current configuration revision. Saving any later revision requires another successful test.</p>
          <p class="fine-print">“Sent” means accepted by the SMTP server, not confirmed delivered to an inbox.</p>
          <div v-if="isResendSmtp" class="resend-webhook-box">
            <div class="resend-webhook-heading">
              <div>
                <h4>Resend delivery callbacks</h4>
                <p class="fine-print">Signed provider events update the matching delivery attempt.</p>
              </div>
              <span class="pill" :class="resendWebhook?.configured ? 'pill-success' : 'pill-warning'">{{ resendWebhook?.configured ? "Signature verified" : "Not configured" }}</span>
            </div>
            <button class="button button-secondary" type="button" :disabled="busy" @click="prepareResendWebhook">Prepare / replace callback URL</button>
            <template v-if="resendWebhook?.callbackUrl">
              <label>Public callback URL
                <input :value="resendWebhook.callbackUrl" type="url" readonly />
              </label>
              <button class="button button-quiet" type="button" @click="copyResendWebhookUrl">Copy callback URL</button>
              <p class="fine-print">In Resend, create a webhook for exactly these events: <code>email.delivered</code> and <code>email.bounced</code>. Paste the signing secret shown by Resend below. Do not select open/click tracking events for this endpoint.</p>
              <label>Resend webhook signing secret
                <input v-model="resendWebhookSigningSecret" type="password" autocomplete="off" maxlength="512" placeholder="whsec_…" />
              </label>
              <button class="button button-primary full-width" type="button" :disabled="busy || !resendWebhookSigningSecret.trim()" @click="activateResendWebhook">
                {{ resendWebhook?.configured ? "Replace signing secret" : "Activate signed callbacks" }}
              </button>
            </template>
            <p class="fine-print">Eventor stores the signing secret encrypted. The callback URL is only a routing identifier; every callback must also pass Svix signature and timestamp verification.</p>
          </div>
        </aside>
      </section>

      <section v-else-if="activeTab === 'inquiries'" class="panel inquiry-panel">
        <div class="section-heading">
          <div>
            <p class="eyebrow">VENUE BOOKING</p>
            <h2>Booking inquiries</h2>
            <p class="muted">Review public requests, assign ownership, record decisions and keep internal notes.</p>
          </div>
          <span class="pill pill-neutral">Permission controlled</span>
        </div>

        <div class="inquiry-toolbar">
          <div class="inquiry-filters">
            <label>Status
              <select v-model="inquiryFilters.status" @change="loadInquiryList(0)">
                <option value="">All statuses</option>
                <option value="received">Received</option>
                <option value="under_review">Under review</option>
                <option value="converted">Converted</option>
                <option value="declined">Declined</option>
                <option value="withdrawn">Withdrawn</option>
                <option value="spam">Spam</option>
              </select>
            </label>
            <label v-if="inquiryCapabilities.canAssign">Assigned to
              <select v-model="inquiryFilters.assignedToMembershipId" @change="loadInquiryList(0)">
                <option value="">All staff</option>
                <option v-for="member in inquiryAssignees" :key="member.membershipId" :value="member.membershipId">
                  {{ member.displayName }}
                </option>
              </select>
            </label>
          </div>
          <button class="button button-secondary" type="button" :disabled="busy" @click="loadInquiryList(inquiryOffset)">
            Refresh inbox
          </button>
        </div>

        <div class="inquiry-layout">
          <aside class="inquiry-inbox">
            <div class="inquiry-inbox-heading">
              <strong>Inbox</strong>
              <span>{{ inquiryMeta?.totalCount ?? 0 }} total</span>
            </div>
            <div v-if="inquiryRows.length" class="inquiry-list">
              <button
                v-for="item in inquiryRows"
                :key="item.inquiryId"
                type="button"
                class="inquiry-list-row"
                :class="{ selected: selectedInquiryId === item.inquiryId }"
                :disabled="busy"
                @click="openInquiry(item)"
              >
                <span class="inquiry-list-top">
                  <strong>{{ item.publicReference }}</strong>
                  <span
                    class="pill"
                    :class="item.status === 'declined' || item.status === 'spam' ? 'pill-danger' : item.status === 'under_review' ? 'pill-warning' : 'pill-neutral'"
                  >{{ item.status.replaceAll("_", " ") }}</span>
                </span>
                <strong class="inquiry-requester">{{ item.requesterName }}</strong>
                <span class="inquiry-list-meta">
                  {{ item.requestedStart ? formatInquiryDate(item.requestedStart) : "Date not specified" }}
                </span>
                <span class="inquiry-list-meta">Assigned: {{ assigneeName(item.assignedToMembershipId) }}</span>
              </button>
            </div>
            <p v-else class="muted inquiry-empty">No inquiries match these filters.</p>
            <div class="pagination inquiry-pagination">
              <button
                class="button button-quiet"
                type="button"
                :disabled="busy || inquiryOffset === 0"
                @click="loadInquiryList(Math.max(0, inquiryOffset - 25))"
              >Previous</button>
              <span>{{ inquiryMeta?.totalCount ?? 0 }} inquiries</span>
              <button
                class="button button-quiet"
                type="button"
                :disabled="busy || !inquiryMeta || inquiryOffset + 25 >= inquiryMeta.totalCount"
                @click="loadInquiryList(inquiryOffset + 25)"
              >Next</button>
            </div>
          </aside>

          <div v-if="inquiryDetail" class="inquiry-detail">
            <div class="inquiry-detail-heading">
              <div>
                <p class="eyebrow">INQUIRY DETAIL</p>
                <h3>{{ inquiryDetail.publicReference }}</h3>
                <p class="fine-print">Received {{ formatInquiryDate(inquiryDetail.submittedAt) }} · Updated {{ formatInquiryDate(inquiryDetail.updatedAt) }}</p>
              </div>
              <div class="inquiry-detail-actions">
                <span
                  class="pill"
                  :class="inquiryDetail.status === 'declined' || inquiryDetail.status === 'spam' ? 'pill-danger' : inquiryDetail.status === 'under_review' ? 'pill-warning' : 'pill-neutral'"
                >{{ inquiryDetail.status.replaceAll("_", " ") }}</span>
                <button class="button button-quiet" type="button" :disabled="busy" @click="refreshInquiryDetail">Refresh detail</button>
              </div>
            </div>

            <div class="inquiry-detail-grid">
              <section class="inquiry-card">
                <h4>Requester</h4>
                <dl>
                  <dt>Name</dt><dd>{{ inquiryDetail.requesterName }}</dd>
                  <dt>Email</dt><dd>{{ inquiryDetail.requesterEmail ?? "Not supplied" }}</dd>
                  <dt>Phone</dt><dd>{{ inquiryDetail.requesterPhone ?? "Not supplied" }}</dd>
                </dl>
              </section>
              <section class="inquiry-card">
                <h4>Requested booking</h4>
                <dl>
                  <dt>Start</dt><dd>{{ formatInquiryDate(inquiryDetail.submittedValues.requested?.startAt ?? inquiryDetail.requestedStart) }}</dd>
                  <dt>End</dt><dd>{{ formatInquiryDate(inquiryDetail.submittedValues.requested?.endAt ?? inquiryDetail.requestedEnd) }}</dd>
                  <dt>Timezone</dt><dd>{{ inquiryDetail.submittedValues.requested?.timezone ?? inquiryDetail.requestedTimezone ?? "—" }}</dd>
                  <dt>Spaces</dt><dd>{{ inquiryDetail.submittedValues.requested?.spaceCodes?.join(", ") || "Not specified" }}</dd>
                </dl>
              </section>
            </div>

            <section class="inquiry-card">
              <div class="inquiry-card-heading">
                <h4>Submitted form answers</h4>
                <span class="fine-print">Form revision {{ inquiryDetail.formRevisionId.slice(0, 8) }}</span>
              </div>
              <dl v-if="inquiryAnswerItems.length" class="answer-list">
                <template v-for="answer in inquiryAnswerItems" :key="answer.code">
                  <dt>{{ answer.label }}</dt><dd>{{ answer.value }}</dd>
                </template>
              </dl>
              <p v-else class="muted">No additional form answers were submitted.</p>
            </section>

            <div class="inquiry-detail-grid">
              <section v-if="canEditInquiryAssignment" class="inquiry-card">
                <h4>Assignment</h4>
                <label>Responsible staff member
                  <select v-model="inquiryAssignmentChoice">
                    <option value="unassigned">Unassigned</option>
                    <option v-for="member in inquiryAssignees" :key="member.membershipId" :value="member.membershipId">
                      {{ member.displayName }}{{ member.membershipId === principal?.membershipId ? " (you)" : "" }}
                    </option>
                  </select>
                </label>
                <p class="fine-print">Only active members of this organization can be assigned.</p>
                <button class="button button-secondary" type="button" :disabled="busy" @click="saveInquiryAssignment">Save assignment</button>
              </section>

              <section v-if="inquiryCapabilities.canManage && inquiryStatusTargets.length" class="inquiry-card">
                <h4>Review status</h4>
                <label>New status
                  <select v-model="inquiryStatusChoice">
                    <option disabled value="">Choose next status…</option>
                    <option v-for="status in inquiryStatusTargets" :key="status" :value="status">
                      {{ status.replaceAll("_", " ") }}
                    </option>
                  </select>
                </label>
                <label>Audit reason
                  <textarea v-model="inquiryStatusReason" rows="3" maxlength="1000" placeholder="Explain the review decision or status change…"></textarea>
                </label>
                <p v-if="inquiryStatusChoice === 'declined' || inquiryStatusChoice === 'spam'" class="fine-print text-warning">
                  This is a terminal status. The inquiry cannot be reopened or reassigned afterward.
                </p>
                <button class="button button-primary" type="button" :disabled="busy || inquiryStatusReason.trim().length < 3" @click="saveInquiryStatus">
                  Save status change
                </button>
              </section>

              <section v-if="canConvertInquiry" class="inquiry-card">
                <h4>Convert to booking draft</h4>
                <p class="fine-print">
                  Creates a separate draft and immutable revision 1 from the submitted request. The original inquiry is retained.
                  This step does not issue an offer, hold availability or confirm a booking.
                </p>
                <button class="button button-primary" type="button" :disabled="busy" @click="saveInquiryConversion">
                  Create booking draft
                </button>
              </section>

              <section v-if="inquiryDetail.bookingDraft" class="inquiry-card">
                <div class="inquiry-card-heading">
                  <h4>Booking draft</h4>
                  <span class="pill pill-neutral">{{ inquiryDetail.bookingDraft.status }} · revision {{ inquiryDetail.bookingDraft.currentRevisionNumber }}</span>
                </div>
                <p class="fine-print">
                  This draft is separate from the original inquiry. Its revisions are immutable; editing creates a new revision.
                  No offer, availability hold or booking confirmation is implied.
                </p>
                <button
                  v-if="canReadBookingDraft"
                  class="button button-secondary"
                  type="button"
                  :disabled="busy"
                  @click="openBookingDraft"
                >
                  Open booking draft
                </button>
                <p v-else class="fine-print">Your membership does not have permission to read this booking draft.</p>
              </section>
            </div>

            <section v-if="bookingDraftDetail && bookingDraftEditorOpen" class="inquiry-card booking-draft-editor">
              <div class="inquiry-card-heading">
                <div>
                  <h4>Booking draft · {{ bookingDraftDetail.draftId.slice(0, 8) }}</h4>
                  <p class="fine-print">Current revision {{ bookingDraftDetail.currentRevisionNumber }} · {{ bookingDraftDetail.status }}</p>
                </div>
                <button class="button button-quiet" type="button" :disabled="busy" @click="bookingDraftEditorOpen = false">Close</button>
              </div>

              <div v-if="bookingDraftDetail.revisionHistory.length" class="draft-revision-history">
                <h5>Revision history</h5>
                <ol class="history-list">
                  <li v-for="history in bookingDraftDetail.revisionHistory" :key="history.revisionId">
                    <strong>Revision {{ history.revisionNumber }}</strong>
                    <span>{{ history.changeReason ?? "No change reason recorded" }}</span>
                    <small>{{ history.createdByDisplayName }} · {{ formatInquiryDate(history.createdAt) }}</small>
                  </li>
                </ol>
              </div>

              <template v-if="canManageBookingDraft">
                <p class="fine-print">
                  Saving creates a new immutable revision. The previous revision is retained. If resource or space holds exist
                  against the current revision, they must expire or be released before it can be revised.
                </p>
                <form class="draft-revision-form" @submit.prevent="saveBookingDraftRevision">
                  <label>Values snapshot (JSON)
                    <textarea v-model="bookingDraftValuesJson" rows="8" spellcheck="false"></textarea>
                  </label>
                  <div class="field-grid">
                    <label>Requested start (ISO 8601)
                      <input v-model="bookingDraftRequestedStart" type="text" maxlength="80" placeholder="2027-01-18T09:00:00+01:00" />
                    </label>
                    <label>Requested end (ISO 8601)
                      <input v-model="bookingDraftRequestedEnd" type="text" maxlength="80" placeholder="2027-01-18T13:00:00+01:00" />
                    </label>
                    <label>Timezone
                      <input v-model="bookingDraftTimezone" type="text" maxlength="80" required />
                    </label>
                  </div>
                  <label>Space lines (JSON array)
                    <textarea v-model="bookingDraftSpaceLinesJson" rows="5" spellcheck="false"></textarea>
                  </label>
                  <label>Resource lines (JSON array)
                    <textarea v-model="bookingDraftResourceLinesJson" rows="5" spellcheck="false"></textarea>
                  </label>
                  <label>Change reason
                    <textarea v-model="bookingDraftChangeReason" rows="2" maxlength="2000" required placeholder="Explain why this revision is being created…"></textarea>
                  </label>
                  <div class="form-actions">
                    <button class="button button-primary" type="submit" :disabled="busy || bookingDraftChangeReason.trim().length < 3">
                      Save as revision {{ bookingDraftDetail.currentRevisionNumber + 1 }}
                    </button>
                    <span class="fine-print">Revision {{ bookingDraftDetail.currentRevisionNumber }} stays unchanged.</span>
                  </div>
                </form>
              </template>
              <p v-else class="fine-print">This draft is read-only for your current membership, or is no longer editable in draft status.</p>
            </section>

            <section v-if="bookingDraftDetail" class="inquiry-card booking-offer-workspace">
              <div class="inquiry-card-heading">
                <div>
                  <h4>Commercial offer and booking confirmation</h4>
                  <p class="fine-print">Customer acceptance, internal approvals and booking confirmation are independent decisions. Capacity is finalized only by the confirmation command.</p>
                </div>
                <span class="pill pill-neutral">Explicit actions</span>
              </div>

              <div class="offer-load-row">
                <label>Offer UUID
                  <input v-model="bookingOfferIdInput" type="text" maxlength="36" placeholder="Load an existing offer for this draft" />
                </label>
                <button class="button button-secondary" type="button" :disabled="busy || !bookingOfferIdInput.trim()" @click="loadBookingOffer">Load offer</button>
              </div>

              <div v-if="canManageBookingOffer" class="offer-preparation">
                <h5>{{ bookingOffer ? "Prepare successor offer revision" : "Prepare first offer revision" }}</h5>
                <p class="fine-print">Use IDs of already published and effective organization configuration. Prices are calculated from the selected price-list revision and item codes by the server. Eventor does not supply default prices, cancellation terms, approval thresholds or tax rates.</p>
                <form class="draft-revision-form" @submit.prevent="saveBookingOfferRevision">
                  <div class="field-grid">
                    <label>Price-list revision UUID
                      <input v-model="bookingOfferCreateForm.priceListRevisionId" type="text" required maxlength="36" />
                    </label>
                    <label>Cancellation-policy revision UUID
                      <input v-model="bookingOfferCreateForm.cancellationPolicyRevisionId" type="text" required maxlength="36" />
                    </label>
                    <label>Approval-policy revision UUID
                      <input v-model="bookingOfferCreateForm.approvalPolicyRevisionId" type="text" required maxlength="36" />
                    </label>
                    <label>Currency (ISO 4217)
                      <input v-model="bookingOfferCreateForm.currency" type="text" required maxlength="3" placeholder="e.g. BAM" />
                    </label>
                    <label>Tax treatment
                      <select v-model="bookingOfferCreateForm.taxBasis" required>
                        <option value="">Choose tax treatment…</option>
                        <option value="inclusive">Tax inclusive</option>
                        <option value="exclusive">Tax exclusive</option>
                        <option value="not_applicable">Not applicable</option>
                        <option value="to_be_confirmed">To be confirmed</option>
                      </select>
                    </label>
                    <label>Offer valid until (your local time)
                      <input v-model="bookingOfferValidUntil" type="datetime-local" required />
                    </label>
                    <label>Tax amount
                      <input v-model="bookingOfferTaxAmount" type="number" min="0" step="0.01" required />
                    </label>
                  </div>
                  <label>Price-list line items (JSON array)
                    <textarea v-model="bookingOfferLineItemsJson" rows="5" spellcheck="false" placeholder='[{"itemCode":"published-item-code","quantity":1}]'></textarea>
                  </label>
                  <label>Manual adjustments (JSON array)
                    <textarea v-model="bookingOfferAdjustmentsJson" rows="4" spellcheck="false" placeholder='[{"code":"adjustment-code","label":"Reasoned adjustment","kind":"discount","amount":0.01}]'></textarea>
                  </label>
                  <label>Internal reason / tax audit reason
                    <textarea v-model="bookingOfferInternalReason" rows="2" maxlength="2000" required placeholder="Explain manual terms, especially any tax amount or adjustment…"></textarea>
                  </label>
                  <label v-if="bookingOffer" class="check-row">
                    <input v-model="bookingOfferSupersedeCurrent" type="checkbox" />
                    Request superseding the current offer (server validates eligibility)
                  </label>
                  <div class="form-actions">
                    <button class="button button-primary" type="submit" :disabled="busy || !bookingOfferValidUntil || !bookingOfferTaxAmount.trim()">
                      {{ bookingOffer ? "Create successor revision" : "Prepare offer" }}
                    </button>
                  </div>
                </form>
              </div>
              <p v-else class="fine-print">Your membership cannot prepare or revise offer terms. The server still enforces the separate commercial permissions on each command.</p>

              <template v-if="bookingOffer">
                <div class="offer-summary-grid">
                  <div class="metric"><span>Offer status</span><strong>{{ bookingOffer.status }}</strong><small>Offer {{ bookingOffer.offerId }}</small></div>
                  <div class="metric"><span>Offer revision</span><strong>{{ bookingOffer.currentRevision.revisionNumber }}</strong><small>{{ bookingOffer.currentRevision.state }}</small></div>
                  <div class="metric"><span>Subtotal</span><strong>{{ formatBookingMoney(bookingOffer.currentRevision.subtotal, bookingOffer.currentRevision.currency) }}</strong></div>
                  <div class="metric"><span>Total</span><strong>{{ formatBookingMoney(bookingOffer.currentRevision.totalAmount, bookingOffer.currentRevision.currency) }}</strong><small>Tax {{ formatBookingMoney(bookingOffer.currentRevision.taxAmount, bookingOffer.currentRevision.currency) }}</small></div>
                </div>
                <dl class="offer-reference-list">
                  <dt>Draft revision</dt><dd class="mono">{{ bookingOffer.currentRevision.draftRevisionId }}</dd>
                  <dt>Price-list revision</dt><dd class="mono">{{ bookingOffer.currentRevision.priceListRevisionId }}</dd>
                  <dt>Cancellation policy</dt><dd class="mono">{{ bookingOffer.currentRevision.cancellationPolicyRevisionId }}</dd>
                  <dt>Approval policy</dt><dd class="mono">{{ bookingOffer.currentRevision.approvalPolicyRevisionId }}</dd>
                  <dt>Valid until</dt><dd>{{ formatInquiryDate(bookingOffer.currentRevision.validUntil) }}</dd>
                  <dt>Issued</dt><dd>{{ formatInquiryDate(bookingOffer.currentRevision.issuedAt) }}</dd>
                  <dt>Customer accepted</dt><dd>{{ formatInquiryDate(bookingOffer.currentRevision.acceptedAt) }}</dd>
                </dl>
                <details class="offer-terms-details">
                  <summary>Inspect immutable customer terms snapshot</summary>
                  <pre>{{ JSON.stringify(bookingOffer.currentRevision.terms, null, 2) }}</pre>
                </details>

                <div class="offer-command-row">
                  <button v-if="bookingOffer.currentRevision.state === 'draft'" class="button button-secondary" type="button" :disabled="busy" @click="issueBookingOffer">Issue offer to customer</button>
                  <span v-else class="pill pill-neutral">This revision is {{ bookingOffer.currentRevision.state }}</span>
                  <button class="button button-quiet" type="button" :disabled="busy" @click="loadBookingOffer">Refresh offer</button>
                </div>

                <div v-if="bookingOfferAcceptanceToken" class="offer-capability-box">
                  <strong>Customer capability — copy now</strong>
                  <p class="fine-print">This is a bearer secret. It is shown only in this session, is not stored in the database as plaintext and is not automatically emailed. The public browser page and SMTP delivery integration remain pending.</p>
                  <input :value="bookingOfferAcceptanceToken" type="password" readonly autocomplete="off" />
                  <button class="button button-secondary" type="button" @click="copyBookingOfferCapability">Copy customer capability</button>
                </div>

                <div v-if="bookingOfferApprovalStatus" class="offer-approval-list">
                  <h5>Internal approval requirements</h5>
                  <p v-if="!bookingOfferApprovalStatus.requirements.length" class="muted">No approval rules matched this offer revision. Customer acceptance and explicit booking confirmation are still required.</p>
                  <article v-for="requirement in bookingOfferApprovalStatus.requirements" :key="requirement.ruleCode" class="offer-approval-item">
                    <div class="inquiry-card-heading">
                      <div>
                        <strong>{{ requirement.ruleCode }}</strong>
                        <p class="fine-print">{{ requirement.approvedCount }} / {{ requirement.requiredApprovals }} approvals · separation of duties {{ requirement.separationOfDuties ? "required" : "not required" }}</p>
                      </div>
                      <span class="pill" :class="requirement.blocked ? 'pill-danger' : requirement.approvedCount >= requirement.requiredApprovals ? 'pill-success' : 'pill-warning'">
                        {{ requirement.blocked ? "Blocked" : requirement.approvedCount >= requirement.requiredApprovals ? "Satisfied" : "Pending" }}
                      </span>
                    </div>
                    <ol v-if="requirement.decisions.length" class="history-list">
                      <li v-for="(decision, index) in requirement.decisions" :key="decision.membershipId + '-' + index">
                        <strong>{{ decision.decision.replaceAll("_", " ") }}</strong>
                        <span>{{ decision.reason }}</span>
                        <small>{{ decision.membershipId }} · {{ formatInquiryDate(decision.decidedAt) }}</small>
                      </li>
                    </ol>
                    <div v-if="canDecideBookingOfferRequirement(requirement)" class="operator-controls offer-approval-controls">
                      <label>Decision
                        <select v-model="bookingOfferApprovalDecisions[requirement.ruleCode]">
                          <option value="approved">Approve</option>
                          <option value="rejected">Reject</option>
                          <option value="returned_for_changes">Return for changes</option>
                        </select>
                      </label>
                      <label>Reason
                        <textarea v-model="bookingOfferApprovalReasons[requirement.ruleCode]" rows="2" maxlength="2000" placeholder="Record the decision rationale…"></textarea>
                      </label>
                      <button class="button button-secondary" type="button" :disabled="busy || (bookingOfferApprovalReasons[requirement.ruleCode] ?? '').trim().length < 3" @click="decideBookingOfferApproval(requirement)">Record decision</button>
                    </div>
                  </article>
                </div>

                <div v-if="canConfirmBookingOffer" class="offer-confirm-box">
                  <h5>Confirm accepted booking</h5>
                  <p class="fine-print">The exact draft revision has an accepted customer offer and all pinned approvals are satisfied. Final space and resource availability is rechecked transactionally on confirmation.</p>
                  <label>Booking confirmation reason
                    <textarea v-model="bookingOfferConfirmationReason" rows="2" maxlength="2000" placeholder="Record why this booking is being confirmed…"></textarea>
                  </label>
                  <button class="button button-primary" type="button" :disabled="busy || bookingOfferConfirmationReason.trim().length < 3" @click="confirmBookingFromAcceptedOffer">Confirm booking</button>
                </div>
                <p v-else-if="bookingOffer.currentRevision.state === 'accepted'" class="fine-print text-warning">Confirmation is not available yet. Check that this accepted offer targets the current draft revision and that every approval requirement is satisfied.</p>

                <div v-if="bookingOffer.revisionHistory.length" class="draft-revision-history">
                  <h5>Offer revision history</h5>
                  <ol class="history-list">
                    <li v-for="history in bookingOffer.revisionHistory" :key="history.offerRevisionId">
                      <strong>Offer revision {{ history.revisionNumber }} · {{ history.state }}</strong>
                      <span>Draft revision {{ history.draftRevisionId }}</span>
                      <small>{{ formatInquiryDate(history.createdAt) }} · issued {{ formatInquiryDate(history.issuedAt) }}</small>
                    </li>
                  </ol>
                </div>
              </template>
            </section>

            <section class="inquiry-card">
              <div class="inquiry-card-heading">
                <h4>Internal staff notes</h4>
                <span class="pill pill-neutral">Staff only</span>
              </div>
              <div v-if="inquiryDetail.annotations.length" class="inquiry-note-list">
                <article v-for="note in inquiryDetail.annotations" :key="note.annotationId" class="inquiry-note">
                  <p>{{ note.annotation }}</p>
                  <span>{{ formatInquiryDate(note.createdAt) }}</span>
                </article>
              </div>
              <p v-else class="muted">No internal notes have been added.</p>
              <form v-if="inquiryCapabilities.canAnnotate" class="inquiry-note-form" @submit.prevent="saveInquiryAnnotation">
                <label>Add an internal note
                  <textarea v-model="inquiryAnnotationText" rows="3" maxlength="4000" placeholder="Record an internal observation or follow-up…"></textarea>
                </label>
                <div class="form-actions">
                  <button class="button button-secondary" type="submit" :disabled="busy || !inquiryAnnotationText.trim()">Add note</button>
                  <span class="fine-print">{{ inquiryAnnotationText.length }} / 4,000</span>
                </div>
              </form>
              <p v-else class="fine-print">Your membership does not have permission to add internal notes.</p>
            </section>

            <div class="inquiry-detail-grid">
              <section class="inquiry-card">
                <h4>Status history</h4>
                <ol v-if="inquiryDetail.statusHistory.length" class="history-list">
                  <li v-for="(history, index) in inquiryDetail.statusHistory" :key="`${history.occurredAt}-${index}`">
                    <strong>{{ history.previousStatus ?? "Created" }} → {{ history.newStatus }}</strong>
                    <span>{{ history.reason ?? "No reason supplied" }}</span>
                    <small>{{ history.actorKind }} · {{ formatInquiryDate(history.occurredAt) }}</small>
                  </li>
                </ol>
                <p v-else class="muted">No status changes recorded.</p>
              </section>
              <section class="inquiry-card">
                <h4>Assignment history</h4>
                <ol v-if="inquiryDetail.assignmentHistory.length" class="history-list">
                  <li v-for="(history, index) in inquiryDetail.assignmentHistory" :key="`${history.occurredAt}-${index}`">
                    <strong>{{ assigneeName(history.previousAssigneeMembershipId) }} → {{ assigneeName(history.newAssigneeMembershipId) }}</strong>
                    <small>{{ formatInquiryDate(history.occurredAt) }}</small>
                  </li>
                </ol>
                <p v-else class="muted">No assignment changes recorded.</p>
              </section>
            </div>
          </div>
          <div v-else class="inquiry-detail-empty">
            <span class="brand-mark">E</span>
            <h3>Select an inquiry</h3>
            <p class="muted">Choose a request from the inbox to inspect requester details, submitted answers, history and permitted actions.</p>
          </div>
        </div>
      </section>

      <section v-else-if="activeTab === 'approvals'" class="panel inquiry-panel approval-policy-workspace">
        <div class="section-heading">
          <div>
            <p class="eyebrow">ORGANIZATION COMMERCIAL CONTROLS</p>
            <h2>Booking approval policies</h2>
            <p class="muted">Create versioned rules that determine which offers require internal approval. Published revisions are immutable and only affect offers created against that revision.</p>
          </div>
          <button class="button button-secondary" type="button" :disabled="busy" @click="loadBookingApprovalPolicies">Refresh policies</button>
        </div>

        <div class="inquiry-detail-grid">
          <section class="inquiry-card">
            <h4>Create approval policy</h4>
            <form class="draft-revision-form" @submit.prevent="createBookingApprovalPolicy">
              <label>Policy code
                <input v-model="approvalPolicyCreateForm.code" type="text" required minlength="2" maxlength="80" placeholder="venue_booking_approvals" />
              </label>
              <label>Policy name
                <input v-model="approvalPolicyCreateForm.name" type="text" required maxlength="250" placeholder="Venue booking approvals" />
              </label>
              <button class="button button-primary" type="submit" :disabled="busy || approvalPolicyCreateForm.code.trim().length < 2 || !approvalPolicyCreateForm.name.trim()">Create policy</button>
            </form>
          </section>
          <section class="inquiry-card">
            <h4>Existing policies</h4>
            <label>Select policy
              <select v-model="selectedApprovalPolicyId" @change="selectBookingApprovalPolicy(selectedApprovalPolicyId)">
                <option value="">Choose a policy…</option>
                <option v-for="policy in approvalPolicies" :key="policy.policyId" :value="policy.policyId">
                  {{ policy.code }} · {{ policy.name }} ({{ policy.status }})
                </option>
              </select>
            </label>
            <p v-if="!approvalPolicies.length" class="muted">No approval policies are configured for this organization.</p>
            <div v-if="selectedApprovalPolicy" class="policy-summary">
              <strong>{{ selectedApprovalPolicy.name }}</strong>
              <span>{{ selectedApprovalPolicy.code }} · {{ selectedApprovalPolicy.status }}</span>
              <small class="mono">{{ selectedApprovalPolicy.policyId }}</small>
            </div>
          </section>
        </div>

        <template v-if="selectedApprovalPolicy">
          <div class="divider"></div>
          <div class="policy-revision-heading">
            <div>
              <h3>Rule editor · {{ selectedApprovalPolicy.name }}</h3>
              <p class="fine-print">Create a new draft revision by editing the JSON below, then publish it as a separate explicit action. The backend validates rule semantics and permissions.</p>
            </div>
            <span class="pill" :class="selectedApprovalPolicyLatestRevision?.state === 'published' ? 'pill-success' : 'pill-warning'">
              Latest: {{ selectedApprovalPolicyLatestRevision?.state ?? "No revision" }}
            </span>
          </div>
          <div v-if="selectedApprovalPolicyLatestRevision" class="policy-revision-meta">
            <span>Revision {{ selectedApprovalPolicyLatestRevision.revisionNumber }}</span>
            <span>Created {{ formatInquiryDate(selectedApprovalPolicyLatestRevision.createdAt) }}</span>
            <span>Published {{ formatInquiryDate(selectedApprovalPolicyLatestRevision.publishedAt) }}</span>
            <span class="mono">{{ selectedApprovalPolicyLatestRevision.revisionId }}</span>
          </div>
          <label>Approval rules (JSON array)
            <textarea v-model="approvalPolicyRulesJson" rows="16" spellcheck="false"></textarea>
          </label>
          <div class="policy-rule-reference">
            <strong>Supported conditions</strong>
            <ul>
              <li><code>always</code> — every offer using the policy triggers the requirement.</li>
              <li><code>total_at_least</code> — requires <code>amount</code> and matching three-letter <code>currency</code>.</li>
              <li><code>discount_at_least</code> — triggers when discounts and credits reach the configured amount.</li>
              <li><code>adjustment_present</code> — triggers when any adjustment, or a selected fee/discount/credit kind, exists.</li>
            </ul>
            <p class="fine-print">Each rule must define a unique code, requiredApprovals (1–10), permission exactly <code>booking.approve</code>, and separationOfDuties (true/false). No role assignments or monetary thresholds are preconfigured by Eventor.</p>
            <pre>[
  {
    "code": "high_value",
    "condition": { "kind": "total_at_least", "amount": 1000, "currency": "BAM" },
    "requiredApprovals": 2,
    "permission": "booking.approve",
    "separationOfDuties": true
  }
]</pre>
          </div>
          <div class="form-actions">
            <button class="button button-secondary" type="button" :disabled="busy || selectedApprovalPolicy.status !== 'active'" @click="createBookingApprovalPolicyRevision">
              Create new draft revision
            </button>
            <button
              v-if="selectedApprovalPolicyLatestRevision?.state === 'draft'"
              class="button button-primary"
              type="button"
              :disabled="busy"
              @click="publishBookingApprovalPolicyRevision"
            >
              Publish latest revision
            </button>
          </div>
          <div v-if="selectedApprovalPolicy.revisions.length" class="draft-revision-history">
            <h5>Revision history</h5>
            <ol class="history-list">
              <li v-for="revision in selectedApprovalPolicy.revisions" :key="revision.revisionId">
                <strong>Revision {{ revision.revisionNumber }} · {{ revision.state }} · {{ revision.rules.length }} rule(s)</strong>
                <span>Created {{ formatInquiryDate(revision.createdAt) }}</span>
                <small>Published {{ formatInquiryDate(revision.publishedAt) }} · {{ revision.revisionId }}</small>
              </li>
            </ol>
          </div>
        </template>
        <p v-else class="inquiry-detail-empty">
          <span class="brand-mark">E</span>
          <strong>Select or create an approval policy</strong>
          <span class="muted">Policy management requires the organization-level booking.manage permission.</span>
        </p>
      </section>

      <section v-else class="panel campaign-panel">
        <div class="section-heading">
          <div><p class="eyebrow">EVENT NOTIFICATIONS</p><h2>Campaign review and authorization</h2></div>
          <span class="pill pill-neutral">Human approval required</span>
        </div>
        <div class="campaign-list-header">
          <div><h3>Authorized campaigns</h3><p class="muted">Only campaigns visible to your event-scoped preview permission are listed.</p></div>
          <button class="button button-secondary" type="button" :disabled="busy" @click="loadCampaignList(0)">Refresh list</button>
        </div>
        <div v-if="campaigns.length" class="campaign-list">
          <div v-for="item in campaigns" :key="item.campaignId" class="campaign-list-row">
            <div>
              <strong>{{ item.purpose.replaceAll("_", " ") }}</strong>
              <span>{{ item.status }} · {{ item.actualRecipientCount }} recipients · {{ new Date(item.createdAt).toLocaleString() }}</span>
              <small class="mono">{{ item.campaignId }}</small>
            </div>
            <button class="button button-secondary" type="button" :disabled="busy" @click="openListedCampaign(item)">Open</button>
          </div>
          <div class="pagination">
            <button class="button button-quiet" type="button" :disabled="busy || !campaignListMeta || campaignListOffset === 0" @click="loadCampaignList(Math.max(0, campaignListOffset - 25))">Previous</button>
            <span>{{ campaignListMeta?.totalCount ?? 0 }} campaigns</span>
            <button class="button button-quiet" type="button" :disabled="busy || !campaignListMeta || campaignListOffset + 25 >= campaignListMeta.totalCount" @click="loadCampaignList(campaignListOffset + 25)">Next</button>
          </div>
        </div>
        <p v-else class="muted">No campaigns loaded. Refresh the list to view campaigns you are permitted to preview.</p>
        <div class="divider"></div>
        <p class="muted">You can also open a campaign directly by UUID.</p>
        <form class="campaign-lookup" @submit.prevent="loadCampaign">
          <label>Campaign UUID<input v-model="campaignId" type="text" required maxlength="36" placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" /></label>
          <button class="button button-primary" type="submit" :disabled="busy">Load review</button>
        </form>

        <template v-if="campaign">
          <div class="campaign-summary">
            <div><span class="eyebrow">CAMPAIGN STATUS</span><h3>{{ campaign.status.replaceAll("_", " ") }}</h3></div>
            <span class="pill" :class="campaign.status === 'completed' ? 'pill-success' : campaign.status === 'failed' ? 'pill-danger' : 'pill-neutral'">{{ campaign.status }}</span>
          </div>
          <div class="metric-grid">
            <div class="metric"><span>Recipients</span><strong>{{ campaign.recipientCount }}</strong><small>Snapshot count</small></div>
            <div class="metric"><span>Email</span><strong>{{ campaign.recipientsByChannel.email ?? 0 }}</strong><small>Queued through SMTP</small></div>
            <div class="metric"><span>SMS</span><strong>{{ campaign.recipientsByChannel.sms ?? 0 }}</strong><small>Not configured · suppressed</small></div>
            <div class="metric"><span>Excluded</span><strong>{{ campaign.exclusionCount }}</strong><small>Not included in send</small></div>
          </div>
          <div class="review-grid">
            <div class="review-card">
              <h4>Campaign details</h4>
              <dl>
                <dt>Purpose</dt><dd>{{ campaign.purpose }}</dd>
                <dt>Audience</dt><dd>{{ campaign.audienceKind }}</dd>
                <dt>Event ID</dt><dd class="mono">{{ campaign.eventId }}</dd>
                <dt>Decision ID</dt><dd class="mono">{{ campaign.eventDecisionId }}</dd>
                <dt>Actual recipients</dt><dd>{{ campaign.actualRecipientCount }}</dd>
                <dt>Created</dt><dd>{{ new Date(campaign.createdAt).toLocaleString() }}</dd>
                <dt>Confirmed</dt><dd>{{ campaign.confirmedAt ? new Date(campaign.confirmedAt).toLocaleString() : "Not yet confirmed" }}</dd>
              </dl>
            </div>
            <div class="review-card">
              <h4>Message template · {{ campaign.template.locale }}</h4>
              <p class="template-subject">{{ campaign.template.subjectTemplate }}</p>
              <pre class="template-body">{{ campaign.template.bodyTemplate }}</pre>
              <p class="fine-print">Template revision {{ campaign.template.revisionNumber }} · {{ campaign.template.state }}</p>
            </div>
          </div>
          <div class="review-card exclusion-card">
            <h4>Exclusions by reason</h4>
            <div v-if="Object.keys(campaign.exclusionsByReason).length" class="reason-list">
              <div v-for="(count, reason) in campaign.exclusionsByReason" :key="reason"><span>{{ reason.replaceAll("_", " ") }}</span><strong>{{ count }}</strong></div>
            </div>
            <p v-else class="muted">No recipients were excluded from this campaign snapshot.</p>
          </div>
          <div class="campaign-actions">
            <button v-if="canConfirm" class="button button-secondary" :disabled="busy" @click="runCampaignAction('confirm')">Confirm reviewed campaign</button>
            <button v-if="canQueue" class="button button-primary" :disabled="busy || !configuration?.deliveryEnabled" @click="runCampaignAction('queue')">Authorize queue and send</button>
            <button v-if="canCancel" class="button button-danger" :disabled="busy" @click="runCampaignAction('cancel')">Cancel before sending</button>
            <span v-if="campaign.status === 'confirmed' && !configuration?.deliveryEnabled" class="fine-print">Test and enable the current SMTP configuration before queueing.</span>
            <span v-if="campaign.status === 'sending' || campaign.status === 'uncertain'" class="fine-print">Delivery has started or has an uncertain outcome. The campaign cannot be cancelled safely.</span>
          </div>
          <div v-if="campaignProgress" class="review-card delivery-report">
            <div class="section-heading">
              <div><h4>Delivery progress</h4><p class="fine-print">{{ campaignProgress.attemptCount }} total attempts</p></div>
              <button class="button button-secondary" type="button" :disabled="busy" @click="refreshCampaignDeliveryData">Refresh status</button>
            </div>
            <div class="metric-grid compact-metrics">
              <div class="metric"><span>Queued</span><strong>{{ campaignProgress.deliveryCounts.queued }}</strong></div>
              <div class="metric"><span>Sent / delivered</span><strong>{{ campaignProgress.deliveryCounts.sent }}</strong></div>
              <div class="metric"><span>Failed</span><strong>{{ campaignProgress.deliveryCounts.failed }}</strong></div>
              <div class="metric"><span>Uncertain</span><strong>{{ campaignProgress.deliveryCounts.uncertain }}</strong></div>
            </div>
            <div class="delivery-toolbar">
              <label>Filter status
                <select v-model="deliveryStatusFilter" @change="deliveryOffset = 0; refreshCampaignDeliveryData()">
                  <option value="">All statuses</option>
                  <option v-for="status in ['queued','sending','sent','delivered','failed','bounced','uncertain','suppressed']" :key="status" :value="status">{{ status }}</option>
                </select>
              </label>
            </div>
            <div v-if="deliveryAttempts.length" class="delivery-attempt-list">
              <article v-for="attempt in deliveryAttempts" :key="attempt.attemptId" class="delivery-attempt">
                <div class="delivery-attempt-heading">
                  <div><strong>{{ attempt.channel }} · attempt {{ attempt.attemptNumber }}</strong><span class="mono">{{ attempt.recipientReference }}</span></div>
                  <span class="pill" :class="attempt.status === 'sent' || attempt.status === 'delivered' ? 'pill-success' : attempt.status === 'failed' || attempt.status === 'bounced' ? 'pill-danger' : attempt.status === 'uncertain' ? 'pill-warning' : 'pill-neutral'">{{ attempt.status }}</span>
                </div>
                <div class="delivery-meta">
                  <span>Provider: {{ attempt.provider ?? "—" }}</span>
                  <span>Failure: {{ attempt.failureCode ?? "—" }}</span>
                  <span>Retry scheduled: {{ attempt.retryScheduled ? "Yes" : "No" }}</span>
                  <span>Completed: {{ attempt.completedAt ? new Date(attempt.completedAt).toLocaleString() : "—" }}</span>
                </div>
                <div v-if="attempt.status === 'uncertain' || (attempt.status === 'failed' && !attempt.retryScheduled)" class="operator-controls">
                  <label>Verified outcome
                    <select v-model="operatorResolution[attempt.attemptId]">
                      <option disabled value="">Choose an outcome…</option>
                      <option value="confirmed_sent">Confirmed accepted by mail provider</option>
                      <option value="confirmed_not_sent">Confirmed not accepted</option>
                      <option value="confirmed_delivered">Confirmed delivered</option>
                      <option value="confirmed_bounced">Confirmed bounced</option>
                    </select>
                  </label>
                  <label>Audit reason
                    <textarea v-model="operatorReason[attempt.attemptId]" rows="2" maxlength="1000" placeholder="Record how the outcome was verified…"></textarea>
                  </label>
                  <button class="button button-secondary" type="button" :disabled="busy" @click="reconcileDeliveryAttempt(attempt)">Record reconciliation</button>
                </div>
                <div v-if="attempt.status === 'failed' && !attempt.retryScheduled" class="operator-controls">
                  <p class="fine-print">Retry creates a new attempt and may send another message. Only proceed after confirming non-acceptance.</p>
                  <button class="button button-danger" type="button" :disabled="busy" @click="retryDeliveryAttempt(attempt)">Authorize separate retry</button>
                </div>
              </article>
            </div>
            <p v-else class="muted">No attempts match this filter.</p>
            <div class="pagination">
              <button class="button button-quiet" type="button" :disabled="busy || deliveryOffset === 0" @click="deliveryOffset = Math.max(0, deliveryOffset - 25); refreshCampaignDeliveryData()">Previous</button>
              <span>{{ deliveryMeta?.totalCount ?? 0 }} attempts</span>
              <button class="button button-quiet" type="button" :disabled="busy || !deliveryMeta || deliveryOffset + 25 >= deliveryMeta.totalCount" @click="deliveryOffset += 25; refreshCampaignDeliveryData()">Next</button>
            </div>
            <p class="fine-print">Recipient references are pseudonymous. No email addresses, phone numbers, or provider message references are shown. SMTP acceptance is not inbox delivery.</p>
          </div>
          <p class="fine-print">Confirmation does not send messages. Queueing is a separate authorization. Cancellation is available only while the campaign remains queued and before the first delivery attempt begins. SMTP acceptance is not proof of inbox delivery.</p>
        </template>
      </section>
    </template>

    <div v-if="pageError" class="message message-error" role="alert">{{ pageError }}</div>
    <div v-if="pageNotice" class="message message-success" role="status">{{ pageNotice }}</div>

    <footer class="footer"><span>EVENTOR · STAFF WORKSPACE</span><span>Self-hosted · Organization-scoped · API-authoritative</span></footer>
  </main>
</template>
