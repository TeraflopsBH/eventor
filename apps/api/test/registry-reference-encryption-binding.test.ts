import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import test from "node:test";
import type { Pool } from "pg";
import { buildApi } from "../src/server.js";
import { encryptContactValue } from "../src/contact-crypto.js";

const organizationId="10000000-0000-0000-0000-00000000000a";
const origin="79000000-0000-4000-8000-000000000011";
const destination="79000000-0000-4000-8000-000000000012";
const source="SYNTHETIC_REF";
const root=Buffer.alloc(32,7);
const key=createHmac("sha256",root).update(`eventor:registry-source-reference-value:v1\0${organizationId}\0${origin}\0${source}`).digest();
const ciphertext=encryptContactValue("SYNTHETIC-REFERENCE",key,{organizationId,contactKind:"other"}).toString("base64");

for (const validBinding of [true,false]) {
  test(`transferred Registry references ${validBinding ? "retain their original encryption binding without exposing it" : "reject an incorrect encryption binding"}`,async () => {
    const client={
      async query(sql:string) {
        return {rows:sql.includes("read_guest_registry_references") ? [{result:{canManage:true,profileRevision:3,references:[{
          referenceId:"79000000-0000-4000-8000-000000000013",source,ciphertext,
          encryptionPersonId:validBinding ? origin : destination,
        }]}}] : []};
      },
      release() {},
    };
    const app=buildApi({pool:{connect:async () => client} as unknown as Pool,
      authenticateStaff:async () => ({organizationId,membershipId:"30000000-0000-0000-0000-00000000000a",userId:"20000000-0000-0000-0000-00000000000a"}),
      privateFieldEncryptionKey:root,
      verifyMutationOrigin:async () => true,
    });
    try {
      const response=await app.inject({method:"GET",url:`/persons/${destination}/references`});
      assert.equal(response.statusCode,validBinding ? 200 : 500);
      if (validBinding) {
        const reference=response.json<{data:{references:Record<string,unknown>[]}}>().data.references[0]!;
        assert.deepEqual(Object.keys(reference).sort(),["referenceId","source","value"]);
        assert.equal(reference.value,"SYNTHETIC-REFERENCE");
      } else {
        assert.ok(!response.body.includes("SYNTHETIC-REFERENCE"));
      }
      assert.ok(!response.body.includes(ciphertext));
      assert.ok(!response.body.includes(origin));
    } finally { await app.close(); }
  });
}
