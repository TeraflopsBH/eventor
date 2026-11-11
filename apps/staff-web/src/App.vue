<script setup lang="ts">
import { computed, onMounted, reactive, ref } from "vue";
import { api, ApiError, type CampaignReview, type EmailConfiguration, type Principal } from "./api";

const principal = ref<Principal | null>(null);
const loadingSession = ref(true);
const activeTab = ref<"delivery" | "campaign">("delivery");
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

const campaignId = ref("");
const campaign = ref<CampaignReview | null>(null);

const selectedOrganization = computed(() =>
  principal.value?.memberships?.find((membership) => membership.selected)?.organizationName
  ?? principal.value?.organizationId
  ?? "",
);
const canQueue = computed(() => campaign.value?.status === "confirmed");
const canConfirm = computed(() => campaign.value?.status === "previewed");
const canCancel = computed(() => campaign.value?.status === "queued");

function clearMessages(): void {
  pageError.value = "";
  pageNotice.value = "";
}

function showError(error: unknown): void {
  if (error instanceof ApiError) {
    if (error.status === 401) {
      principal.value = null;
      configuration.value = null;
      campaign.value = null;
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
  const result = await api.getEmailConfiguration();
  configuration.value = result.data;
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
    campaign.value = null;
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
    pageNotice.value = "Campaign review loaded. Recipient contact details are intentionally not exposed here.";
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
        </aside>
      </section>

      <section v-else class="panel campaign-panel">
        <div class="section-heading">
          <div><p class="eyebrow">EVENT NOTIFICATIONS</p><h2>Campaign review and authorization</h2></div>
          <span class="pill pill-neutral">Human approval required</span>
        </div>
        <p class="muted">Enter a campaign ID from the authorized event workflow. The current API provides campaign review by ID; it does not yet expose a campaign listing endpoint.</p>
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
          <p class="fine-print">Confirmation does not send messages. Queueing is a separate authorization. Cancellation is available only while the campaign remains queued and before the first delivery attempt begins. SMTP acceptance is not proof of inbox delivery.</p>
        </template>
      </section>
    </template>

    <div v-if="pageError" class="message message-error" role="alert">{{ pageError }}</div>
    <div v-if="pageNotice" class="message message-success" role="status">{{ pageNotice }}</div>

    <footer class="footer"><span>EVENTOR · STAFF WORKSPACE</span><span>Self-hosted · Organization-scoped · API-authoritative</span></footer>
  </main>
</template>
