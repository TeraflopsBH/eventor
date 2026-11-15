import { createHmac, timingSafeEqual } from "node:crypto";

export interface ResendWebhookHeaders {
  readonly id: string;
  readonly timestamp: string;
  readonly signature: string;
}

export interface ResendWebhookVerificationOptions {
  readonly payload: string;
  readonly headers: ResendWebhookHeaders;
  readonly signingSecret: string;
  readonly nowMs?: number;
  readonly toleranceSeconds?: number;
}

/**
 * Verify the Svix v1 signature used by Resend webhooks.
 * The exact raw request body must be supplied; parsing/re-serializing JSON
 * before verification invalidates the signature.
 */
export function verifyResendWebhookSignature(
  options: ResendWebhookVerificationOptions,
): boolean {
  const { payload, headers, signingSecret } = options;
  const toleranceSeconds = options.toleranceSeconds ?? 300;
  const nowMs = options.nowMs ?? Date.now();

  if (typeof payload !== "string" || payload.length === 0 || payload.length > 64 * 1024 ||
      !headers || typeof headers.id !== "string" ||
      headers.id.length < 1 || headers.id.length > 200 ||
      typeof headers.timestamp !== "string" ||
      !/^[0-9]{1,12}$/.test(headers.timestamp) ||
      typeof headers.signature !== "string" || headers.signature.length > 4096 ||
      typeof signingSecret !== "string" || !signingSecret.startsWith("whsec_") ||
      !Number.isInteger(toleranceSeconds) || toleranceSeconds < 1 || toleranceSeconds > 3600) {
    return false;
  }

  const timestamp = Number(headers.timestamp);
  if (!Number.isSafeInteger(timestamp)) return false;
  const currentSeconds = Math.floor(nowMs / 1000);
  if (Math.abs(currentSeconds - timestamp) > toleranceSeconds) return false;

  const encodedSecret = signingSecret.slice("whsec_".length);
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(encodedSecret)) return false;
  const key = Buffer.from(encodedSecret, "base64");
  if (key.length < 16 || key.toString("base64").replace(/=+$/, "") !== encodedSecret.replace(/=+$/, "")) {
    return false;
  }

  const signedContent = `${headers.id}.${headers.timestamp}.${payload}`;
  const expected = createHmac("sha256", key).update(signedContent, "utf8").digest();
  const signatures = headers.signature.split(/\s+/);
  for (const item of signatures) {
    const separator = item.indexOf(",");
    if (separator < 1 || item.slice(0, separator) !== "v1") continue;
    const encodedSignature = item.slice(separator + 1);
    if (!/^[A-Za-z0-9+/]+={0,2}$/.test(encodedSignature)) continue;
    const supplied = Buffer.from(encodedSignature, "base64");
    if (supplied.length === expected.length &&
        supplied.toString("base64").replace(/=+$/, "") === encodedSignature.replace(/=+$/, "") &&
        timingSafeEqual(expected, supplied)) {
      return true;
    }
  }
  return false;
}
