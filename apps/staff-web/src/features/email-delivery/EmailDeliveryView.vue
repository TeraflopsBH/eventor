<script setup lang="ts">
import type { Ref } from "vue";
import type { useEmailDelivery } from "./useEmailDelivery";

type Workspace = ReturnType<typeof useEmailDelivery> & { busy: Ref<boolean> };

const props = defineProps<{ workspace: Workspace }>();

const {
  configuration, emailForm, testRecipient, resendWebhook, resendWebhookSigningSecret, isResendSmtp,
  saveConfiguration, sendTest, prepareResendWebhook, activateResendWebhook, copyResendWebhookUrl, busy,
} = props.workspace;
</script>

<template>
<section class="content-grid">
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
</template>
