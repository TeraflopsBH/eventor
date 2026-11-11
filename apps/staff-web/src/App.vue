<script setup lang="ts">
import { computed, onMounted, reactive, ref } from "vue";
import { api, ApiError, type CampaignReview, type CampaignProgress, type CampaignListItem, type DeliveryAttempt, type PageMeta, type EmailConfiguration, type ResendWebhookConfiguration, type Principal, type BookingInquiryListItem, type BookingInquiryDetail, type BookingInquiryAssignee, type BookingInquiryCapabilities, type BookingInquiryStatus } from "./api";

const principal = ref<Principal | null>(null);
const loadingSession = ref(true);
const activeTab = ref<"delivery" | "campaign" | "inquiries">("delivery");
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
});
const selectedInquiryId = ref("");
const inquiryAssignmentChoice = ref("unassigned");
const inquiryStatusChoice = ref<BookingInquiryStatus | "">("");
const inquiryStatusReason = ref("");
const inquiryAnnotationText = ref("");

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
const inquiryStatusTargets = computed<BookingInquiryStatus[]>(() => {
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
  if (field?.type === "select" && typeof value === "string") {
    return field.options?.find((option) => option.value === value)?.label ?? value;
  }
  if (field?.type === "multiselect" && typeof value === "string") {
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

function clearMessages(): void {
  pageError.value = "";
  pageNotice.value = "";
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
      inquiryCapabilities.value = { canAssign: false, canManage: false, canAnnotate: false };
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
    inquiryCapabilities.value = { canAssign: false, canManage: false, canAnnotate: false };
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
  inquiryAssignees.value = capabilities.data.canAssign
    ? (await api.getBookingInquiryAssignees(organizationId)).data
    : [];
}

async function refreshInquiryDetailData(): Promise<void> {
  if (!selectedInquiryId.value) return;
  const result = await api.getBookingInquiry(selectedInquiryId.value);
  inquiryDetail.value = result.data;
  inquiryAssignmentChoice.value = result.data.assignedToMembershipId ?? "unassigned";
  inquiryStatusChoice.value = result.data.status === "received"
    ? "under_review"
    : result.data.status === "under_review"
      ? "declined"
      : "";
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
