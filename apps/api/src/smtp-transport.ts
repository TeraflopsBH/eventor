import nodemailer, { type Transporter } from "nodemailer";
import type SMTPTransport from "nodemailer/lib/smtp-transport/index.js";
import type { SmtpCredentials } from "./delivery-credentials-crypto.js";

export interface SmtpSettings {
  readonly host: string;
  readonly port: number;
  readonly transportSecurity: "starttls" | "implicit_tls";
  readonly authMode: "none" | "password";
  readonly senderEmail: string;
  readonly senderName: string;
  readonly replyTo?: string | null;
  readonly connectionTimeoutMs: number;
}

export interface SmtpMessage {
  readonly to: string;
  readonly subject: string;
  readonly text: string;
}

export interface SmtpSendResult {
  readonly messageId: string;
  readonly accepted: readonly string[];
}

export interface SmtpTransport {
  verify(): Promise<boolean>;
  sendMail(message: {
    from: { name: string; address: string };
    to: string;
    replyTo?: string;
    subject: string;
    text: string;
  }): Promise<SmtpSendResult>;
  close(): void;
}

export type SmtpTransportFactory = (
  settings: SmtpSettings,
  credentials: SmtpCredentials | null,
) => SmtpTransport;

export function createSmtpTransport(
  settings: SmtpSettings,
  credentials: SmtpCredentials | null,
): SmtpTransport {
  if (settings.authMode === "password" && !credentials) {
    throw new TypeError("SMTP password authentication requires credentials.");
  }
  const options: SMTPTransport.Options = {
    host: settings.host,
    port: settings.port,
    secure: settings.transportSecurity === "implicit_tls",
    requireTLS: settings.transportSecurity === "starttls",
    connectionTimeout: settings.connectionTimeoutMs,
    greetingTimeout: settings.connectionTimeoutMs,
    socketTimeout: Math.max(settings.connectionTimeoutMs, 30000),
    tls: { rejectUnauthorized: true },
    ...(settings.authMode === "password" && credentials
      ? { auth: { user: credentials.username, pass: credentials.password } }
      : {}),
  };
  const transporter: Transporter<SMTPTransport.SentMessageInfo> =
    nodemailer.createTransport(options);
  return {
    async verify() {
      return transporter.verify();
    },
    async sendMail(message) {
      const result = await transporter.sendMail({
        from: { name: settings.senderName, address: settings.senderEmail },
        to: message.to,
        ...(settings.replyTo ? { replyTo: settings.replyTo } : {}),
        subject: message.subject,
        text: message.text,
      });
      return {
        messageId: String(result.messageId ?? ""),
        accepted: result.accepted.map((value) => String(value)),
      };
    },
    close() {
      transporter.close();
    },
  };
}

export async function sendSmtpTestMessage(
  settings: SmtpSettings,
  credentials: SmtpCredentials | null,
  recipient: string,
  factory: SmtpTransportFactory = createSmtpTransport,
): Promise<SmtpSendResult> {
  const transport = factory(settings, credentials);
  try {
    const verified = await transport.verify();
    if (!verified) throw new Error("SMTP server verification failed.");
    const result = await transport.sendMail({
      to: recipient,
      subject: "[Eventor] SMTP configuration test",
      text: "This is a test message sent at your request to verify the organization's Eventor SMTP configuration. No event notification was sent.",
    });
    if (!result.accepted.some((address) => address.toLowerCase() === recipient.toLowerCase())) {
      throw new Error("SMTP server did not accept the test recipient.");
    }
    return result;
  } finally {
    transport.close();
  }
}

export function renderNotificationTemplate(
  template: string,
  values: Readonly<Record<string, string>>,
): string {
  return template.replace(/\\{\\{([a-zA-Z][a-zA-Z0-9_.]*)\\}\\}/g, (_match, key: string) => {
    const value = values[key];
    if (value === undefined) {
      throw new TypeError(`Unsupported notification template placeholder: ${key}`);
    }
    return value;
  });
}

export interface SmtpFailureClassification {
  readonly outcome: "failed" | "uncertain";
  readonly code: "SMTP_CONNECTION" | "SMTP_TIMEOUT" | "SMTP_4XX" | "SMTP_5XX" |
    "SMTP_TLS" | "SMTP_TEMPLATE_INVALID" | "CONTACT_CIPHERTEXT_INVALID" |
    "DELIVERY_CREDENTIALS_INVALID" | "SMTP_UNKNOWN";
}

export function classifySmtpFailure(error: unknown): SmtpFailureClassification {
  if (error instanceof TypeError && error.message.startsWith("Unsupported notification template placeholder:")) {
    return { outcome: "failed", code: "SMTP_TEMPLATE_INVALID" };
  }
  if (error instanceof Error && /contact ciphertext|contact value/i.test(error.message)) {
    return { outcome: "failed", code: "CONTACT_CIPHERTEXT_INVALID" };
  }
  if (error instanceof Error && /delivery credential|EDC1/i.test(error.message)) {
    return { outcome: "failed", code: "DELIVERY_CREDENTIALS_INVALID" };
  }

  const candidate = (typeof error === "object" && error !== null)
    ? error as { code?: unknown; command?: unknown; responseCode?: unknown }
    : {};
  const code = typeof candidate.code === "string" ? candidate.code : "";
  const responseCode = typeof candidate.responseCode === "number" ? candidate.responseCode : 0;
  if (responseCode >= 500) return { outcome: "failed", code: "SMTP_5XX" };
  if (responseCode >= 400) return { outcome: "failed", code: "SMTP_4XX" };
  if (candidate.command === "DATA") return { outcome: "uncertain", code: "SMTP_UNKNOWN" };
  if (code === "ETIMEDOUT" || code === "ESOCKETTIMEDOUT") {
    return { outcome: "failed", code: "SMTP_TIMEOUT" };
  }
  if (["ECONNECTION", "ECONNRESET", "ECONNREFUSED", "EHOSTUNREACH", "ENETUNREACH", "EAI_AGAIN"].includes(code)) {
    return { outcome: "failed", code: "SMTP_CONNECTION" };
  }
  if (code === "ETLS" || code === "ESOCKET") {
    return { outcome: "failed", code: "SMTP_TLS" };
  }
  return { outcome: "failed", code: "SMTP_UNKNOWN" };
}
