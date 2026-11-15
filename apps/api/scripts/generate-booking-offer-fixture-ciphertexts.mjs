import { appendFileSync } from "node:fs";
import { encryptContactValue } from "../dist/src/contact-crypto.js";

const organizationId = "22222222-2222-4222-8222-222222222222";
const key = Buffer.from(process.env.EVENTOR_CONTACT_ENCRYPTION_KEY ?? "", "base64");
if (key.length !== 32) throw new Error("EVENTOR_CONTACT_ENCRYPTION_KEY must decode to 32 bytes.");
const emailCiphertext = encryptContactValue("booking-offer-worker@example.invalid", key, {
  organizationId,
  contactKind: "email",
});
const capabilityCiphertext = encryptContactValue("A".repeat(43), key, {
  organizationId,
  contactKind: "other",
});
if (!process.env.GITHUB_ENV) throw new Error("GITHUB_ENV is required in CI.");
appendFileSync(
  process.env.GITHUB_ENV,
  "CI_BOOKING_OFFER_EMAIL_CIPHERTEXT_BASE64=" + emailCiphertext.toString("base64") + String.fromCharCode(10) +
  "CI_BOOKING_OFFER_CAPABILITY_CIPHERTEXT_BASE64=" + capabilityCiphertext.toString("base64") + String.fromCharCode(10),
);
