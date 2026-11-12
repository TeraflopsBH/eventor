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
            <div><p class="eyebrow">{{ $t("emailDelivery.eyebrow") }}</p><h2>{{ $t("emailDelivery.title") }}</h2></div>
            <span v-if="configuration?.deliveryEnabled" class="pill pill-success">{{ $t("emailDelivery.testedEnabled") }}</span>
            <span v-else class="pill pill-warning">{{ $t("emailDelivery.notEnabled") }}</span>
          </div>
          <p class="muted">{{ $t("emailDelivery.description") }}</p>
          <form class="settings-form" @submit.prevent="saveConfiguration">
            <div class="field-grid">
              <label>{{ $t("emailDelivery.smtpHost") }}<input v-model="emailForm.host" type="text" required maxlength="253" placeholder="mail.example.org" /></label>
              <label>{{ $t("emailDelivery.port") }}<input v-model.number="emailForm.port" type="number" min="1" max="65535" required /></label>
              <label>{{ $t("emailDelivery.transportSecurity") }}
                <select v-model="emailForm.transportSecurity">
                  <option value="starttls">{{ $t("emailDelivery.starttls") }}</option>
                  <option value="implicit_tls">{{ $t("emailDelivery.implicitTls") }}</option>
                </select>
              </label>
              <label>{{ $t("emailDelivery.authentication") }}
                <select v-model="emailForm.authMode">
                  <option value="password">{{ $t("emailDelivery.usernamePassword") }}</option>
                  <option value="none">{{ $t("emailDelivery.noAuthentication") }}</option>
                </select>
              </label>
              <label>{{ $t("emailDelivery.senderEmail") }}<input v-model="emailForm.senderEmail" type="email" required maxlength="320" placeholder="events@example.org" /></label>
              <label>{{ $t("emailDelivery.senderName") }}<input v-model="emailForm.senderName" type="text" maxlength="200" placeholder="Eventor" /></label>
              <label>{{ $t("emailDelivery.replyTo") }}<input v-model="emailForm.replyTo" type="email" maxlength="320"  :placeholder="$t('emailDelivery.optional')" /></label>
              <label>{{ $t("emailDelivery.connectionTimeout") }}<input v-model.number="emailForm.connectionTimeoutMs" type="number" min="1000" max="60000" /></label>
            </div>
            <div v-if="emailForm.authMode === 'password'" class="credential-box">
              <div class="credential-heading">
                <div><strong>{{ $t("emailDelivery.credentials") }}</strong><p>{{ configuration?.credentialsConfigured ? $t("emailDelivery.credentialsRetain") : $t("emailDelivery.noCredentials") }}</p></div>
                <span class="lock-icon">{{ $t("emailDelivery.locked") }}</span>
              </div>
              <div class="field-grid">
                <label>{{ $t("emailDelivery.username") }}<input v-model="emailForm.username" type="text" autocomplete="off" maxlength="320"  :placeholder="$t('emailDelivery.retainCurrent')" /></label>
                <label>{{ $t("emailDelivery.password") }}<input v-model="emailForm.password" type="password" autocomplete="new-password" maxlength="4096"  :placeholder="$t('emailDelivery.writeOnly')" /></label>
              </div>
            </div>
            <label v-if="configuration?.credentialsConfigured && emailForm.authMode === 'password'" class="check-row">
              <input v-model="emailForm.clearCredentials" type="checkbox" /> {{ $t("emailDelivery.clearCredentials") }}
            </label>
            <div class="form-actions">
              <button class="button button-primary" type="submit" :disabled="busy">{{ busy ? $t("emailDelivery.saving") : $t("emailDelivery.saveRevision") }}</button>
              <span v-if="configuration?.revision" class="fine-print">{{ $t("emailDelivery.currentRevision") }} {{ configuration.revision }}</span>
            </div>
          </form>
        </div>

        <aside class="panel side-panel">
          <p class="eyebrow">{{ $t("emailDelivery.readiness") }}</p>
          <h3>{{ $t("emailDelivery.testBeforeSending") }}</h3>
          <div class="readiness-row"><span>{{ $t("emailDelivery.configuration") }}</span><strong>{{ configuration?.revision ? `${$t("emailDelivery.currentRevision")} ${configuration.revision}` : $t("emailDelivery.notConfigured") }}</strong></div>
          <div class="readiness-row"><span>{{ $t("emailDelivery.credentials") }}</span><strong>{{ configuration?.credentialsConfigured ? $t("emailDelivery.credentialsStored") : emailForm.authMode === "none" ? $t("emailDelivery.credentialsNotRequired") : $t("emailDelivery.credentialsMissing") }}</strong></div>
          <div class="readiness-row"><span>{{ $t("emailDelivery.smtpTest") }}</span><strong :class="configuration?.deliveryEnabled ? 'text-success' : 'text-warning'">{{ configuration?.deliveryEnabled ? $t("emailDelivery.passed") : $t("emailDelivery.required") }}</strong></div>
          <div class="divider"></div>
          <form @submit.prevent="sendTest">
            <label>{{ $t("emailDelivery.testRecipient") }}<input v-model="testRecipient" type="email" required maxlength="320" placeholder="your-address@example.org" /></label>
            <button class="button button-secondary full-width" type="submit" :disabled="busy || !configuration?.revision">{{ $t("emailDelivery.sendTest") }}</button>
          </form>
          <p class="fine-print">{{ $t("emailDelivery.testEnablesRevision") }}</p>
          <p class="fine-print">{{ $t("emailDelivery.sentMeaning") }}</p>
          <div v-if="isResendSmtp" class="resend-webhook-box">
            <div class="resend-webhook-heading">
              <div>
                <h4>{{ $t("emailDelivery.resendCallbacks") }}</h4>
                <p class="fine-print">{{ $t("emailDelivery.signedEvents") }}</p>
              </div>
              <span class="pill" :class="resendWebhook?.configured ? 'pill-success' : 'pill-warning'">{{ resendWebhook?.configured ? $t("emailDelivery.signatureVerified") : $t("emailDelivery.notConfigured") }}</span>
            </div>
            <button class="button button-secondary" type="button" :disabled="busy" @click="prepareResendWebhook">{{ $t("emailDelivery.prepareReplaceUrl") }}</button>
            <template v-if="resendWebhook?.callbackUrl">
              <label>{{ $t("emailDelivery.publicCallbackUrl") }}
                <input :value="resendWebhook.callbackUrl" type="url" readonly />
              </label>
              <button class="button button-quiet" type="button" @click="copyResendWebhookUrl">{{ $t("emailDelivery.copyUrl") }}</button>
              <p class="fine-print">{{ $t("emailDelivery.resendInstructions") }} <code>email.delivered</code> and <code>email.bounced</code>{{ $t("emailDelivery.resendInstructionsEnd") }}</p>
              <label>{{ $t("emailDelivery.signingSecret") }}
                <input v-model="resendWebhookSigningSecret" type="password" autocomplete="off" maxlength="512" placeholder="whsec_…" />
              </label>
              <button class="button button-primary full-width" type="button" :disabled="busy || !resendWebhookSigningSecret.trim()" @click="activateResendWebhook">
                {{ resendWebhook?.configured ? $t("emailDelivery.replaceSecret") : $t("emailDelivery.activateCallbacks") }}
              </button>
            </template>
            <p class="fine-print">{{ $t("emailDelivery.secretStorage") }}</p>
          </div>
        </aside>
      </section>
</template>
