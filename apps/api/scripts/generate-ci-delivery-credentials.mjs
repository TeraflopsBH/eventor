import { encryptDeliveryCredentials } from "../dist/src/delivery-credentials-crypto.js";

const organizationId = "22222222-2222-4222-8222-222222222222";
const key = Buffer.from(process.env.EVENTOR_DELIVERY_CREDENTIALS_KEY ?? "", "base64");
if (key.length !== 32) throw new Error("EVENTOR_DELIVERY_CREDENTIALS_KEY must decode to 32 bytes.");
const ciphertext = encryptDeliveryCredentials(
  { username: "resend", password: "ci-only-synthetic-provider-token" },
  key,
  { organizationId, channel: "email" },
);
process.stdout.write(ciphertext.toString("base64"));
