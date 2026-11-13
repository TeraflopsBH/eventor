import { computed, reactive, ref, type Ref } from "vue";
import type { EmailConfiguration, ResendWebhookConfiguration } from "../../api";

interface EmailDeliveryDependencies {
  api: typeof import("../../api").api;
  busy: Ref<boolean>;
  pageError: Ref<string>;
  pageNotice: Ref<string>;
  clearMessages: () => void;
  showError: (error: unknown) => void;
}

export function useEmailDelivery({ api, busy, pageError, pageNotice, clearMessages, showError }: EmailDeliveryDependencies) {
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

  function reset(): void {
    configuration.value = null;
    resendWebhook.value = null;
    resendWebhookSigningSecret.value = "";
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

  return {
    configuration, emailForm, testRecipient, resendWebhook, resendWebhookSigningSecret, isResendSmtp,
    loadConfiguration, saveConfiguration, sendTest, prepareResendWebhook, activateResendWebhook,
    copyResendWebhookUrl, reset,
  };
}
