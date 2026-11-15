import assert from "node:assert/strict";
import { Pool } from "pg";
import { encryptContactValue } from "../dist/src/contact-crypto.js";

const organizationId = "22222222-2222-4222-8222-222222222222";
const contactKey = Buffer.from(process.env.EVENTOR_CONTACT_ENCRYPTION_KEY ?? "", "base64");
assert.equal(contactKey.length, 32, "contact encryption key must be 32 bytes");
const migrator = new Pool({ connectionString: process.env.MIGRATOR_URL });
const recipients = [
  ["94200000-0000-4000-8000-000000000001", "worker-eligible@example.invalid"],
  ["94200000-0000-4000-8000-000000000002", "worker-no-consent@example.invalid"],
  ["94200000-0000-4000-8000-000000000003", "worker-previously-invited@example.invalid"],
  ["94200000-0000-4000-8000-000000000004", "worker-resend-uncertain@example.invalid"],
];

try {
  const client = await migrator.connect();
  try {
    await client.query("BEGIN");
    await client.query("SET LOCAL ROLE eventor_owner");
    await client.query("SELECT set_config('app.organization_id',$1,true)", [organizationId]);
    for (const [personId, address] of recipients) {
      const encrypted = encryptContactValue(address, contactKey, {
        organizationId,
        contactKind: "email",
      });
      const updated = await client.query(
        `UPDATE eogp.person_contact_points
            SET encrypted_value=$3
          WHERE organization_id=$1 AND person_id=$2::uuid AND contact_kind='email'`,
        [organizationId, personId, encrypted],
      );
      assert.equal(updated.rowCount, 1, `expected one email contact for fixture person ${personId}`);
    }
    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
  console.log("Synthetic contact ciphertext prepared before immutable campaign recipient snapshots.");
} finally {
  await migrator.end();
}
