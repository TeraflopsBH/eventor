import assert from "node:assert/strict";
import test from "node:test";
import type { Pool } from "pg";
import { buildApi } from "../src/server.js";
import { isUuid } from "../src/uuid.js";
import { decryptContactValue, encryptContactValue } from "../src/contact-crypto.js";
import { decryptDeliveryCredentials, encryptDeliveryCredentials } from "../src/delivery-credentials-crypto.js";

const legacyPrincipal = {
  userId: "20000000-0000-0000-0000-00000000000a",
  organizationId: "10000000-0000-0000-0000-00000000000a",
  membershipId: "30000000-0000-0000-0000-00000000000a",
};

test("database UUID validation preserves canonical legacy identifiers and rejects malformed input", () => {
  assert.equal(isUuid(legacyPrincipal.organizationId),true);
  assert.equal(isUuid("22222222-2222-4222-8222-222222222222"),true);
  for (const value of [null,{}, "", "not-a-uuid", "10000000-0000-0000-0000-00000000000g",
    "1000000000000000000000000000000a", " 10000000-0000-0000-0000-00000000000a"]) {
    assert.equal(isUuid(value),false);
  }
});

test("legacy tenant identifiers retain authenticated contact and delivery encryption boundaries", () => {
  const key = Buffer.alloc(32,7);
  const contactContext = {organizationId:legacyPrincipal.organizationId,contactKind:"email" as const};
  const ciphertext = encryptContactValue("synthetic@example.invalid",key,contactContext);
  assert.equal(decryptContactValue(ciphertext,key,contactContext),"synthetic@example.invalid");
  assert.throws(() => decryptContactValue(ciphertext,key,{...contactContext,organizationId:"10000000-0000-0000-0000-00000000000b"}));
  const deliveryContext = {organizationId:legacyPrincipal.organizationId,channel:"email" as const};
  const credentials = {username:"synthetic@example.invalid",password:"synthetic-test-only"};
  const protectedCredentials = encryptDeliveryCredentials(credentials,key,deliveryContext);
  assert.deepEqual(decryptDeliveryCredentials(protectedCredentials,key,deliveryContext),credentials);
  assert.throws(() => decryptDeliveryCredentials(protectedCredentials,key,{...deliveryContext,organizationId:"10000000-0000-0000-0000-00000000000b"}));
});

test("authenticated legacy UUIDs reach staff routes while malformed paths and other organizations remain rejected", async () => {
  const queries: unknown[][] = [];
  const client = {
    async query(sql: string,values: unknown[] = []) {
      if (sql.includes("list_organization_access_roles")) {
        queries.push(values);
        return {rows:[{result:[]}]};
      }
      return {rows:[]};
    },
    release() {},
  };
  const app = buildApi({
    pool:{connect:async () => client} as unknown as Pool,
    authenticateStaff:async () => legacyPrincipal,
    verifyMutationOrigin:async () => true,
    getCurrentPrincipal:async principal => ({...principal}),
  });
  try {
    assert.equal((await app.inject({method:"GET",url:"/me"})).statusCode,200);
    const response = await app.inject({method:"GET",url:`/organizations/${legacyPrincipal.organizationId}/roles`});
    assert.equal(response.statusCode,200,response.body);
    assert.deepEqual(queries,[[legacyPrincipal.organizationId,legacyPrincipal.membershipId]]);
    assert.equal((await app.inject({method:"GET",url:"/organizations/not-a-uuid/roles"})).statusCode,400);
    assert.equal((await app.inject({method:"GET",url:"/organizations/10000000-0000-0000-0000-00000000000b/roles"})).statusCode,403);
  } finally {
    await app.close();
  }
});
