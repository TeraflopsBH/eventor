import assert from "node:assert/strict";
import test from "node:test";
import type { Pool } from "pg";
import { buildApi } from "../src/server.js";

const organizationId = "10000000-0000-0000-0000-00000000000a";
const membershipId = "30000000-0000-0000-0000-00000000000a";
const source = "79000000-0000-4000-8000-000000000001";
const destination = "79000000-0000-4000-8000-000000000002";
const review = "79000000-0000-4000-8000-000000000003";
const mergeId = "79000000-0000-4000-8000-000000000004";

for (const operation of ["transfer","restore"] as const) {
  test(`cached Registry contact ${operation} rechecks current contact management permission`, async () => {
    let contactAllowed = true;
    let commandCalls = 0;
    let stored: {request_sha256:unknown;response_status:unknown;response_body:unknown} | null = null;
    const permissionCalls: {sql:string;values:readonly unknown[]}[] = [];
    const client = {
      async query(sql:string,values:readonly unknown[] = []) {
        if (sql.startsWith("SELECT request_sha256")) return {rows:stored ? [stored] : []};
        if (sql.startsWith("INSERT INTO eogp.idempotency_records")) {
          stored = {request_sha256:values[4],response_status:null,response_body:null};
          return {rows:[{id:mergeId}]};
        }
        if (sql.startsWith("UPDATE eogp.idempotency_records")) {
          stored = {request_sha256:values[4],response_status:values[5],response_body:values[6]};
        }
        if (sql.includes("assert_guest_contact_permission") || sql.includes("assert_guest_registry_merge_restore_permission")) {
          permissionCalls.push({sql,values});
          if (!contactAllowed) throw Object.assign(new Error("permission revoked"),{code:"42501"});
        }
        if (sql.includes("SELECT eogp.commit_guest_registry_merge(")) {
          commandCalls++;
          assert.deepEqual(values,[organizationId,membershipId,source,destination,1,1,"duplicate_profile",review,"move_to_destination"]);
          return {rows:[{result:{mergeId,status:"merged"}}]};
        }
        if (sql.includes("SELECT eogp.restore_guest_registry_merge(")) {
          commandCalls++;
          return {rows:[{result:{mergeId,status:"restored"}}]};
        }
        return {rows:[]};
      },
      release() {},
    };
    const app = buildApi({
      pool:{connect:async () => client} as unknown as Pool,
      authenticateStaff:async () => ({organizationId,membershipId,userId:"20000000-0000-0000-0000-00000000000a"}),
      verifyMutationOrigin:async () => true,
    });
    const request = {
      method:"POST" as const,
      url:operation==="transfer" ? `/persons/${source}/merge` : `/organizations/${organizationId}/persons/merges/${mergeId}/restore`,
      headers:{"idempotency-key":`contact-${operation}-replay-fixture`},
      ...(operation==="transfer" ? {payload:{reviewId:review,destinationPersonId:destination,sourceRevision:1,
        destinationRevision:1,reason:"duplicate_profile",contactResolution:"move_to_destination"}} : {}),
    };
    try {
      const first = await app.inject(request);
      assert.equal(first.statusCode,operation==="transfer" ? 201 : 200,first.body);
      const replay = await app.inject(request);
      assert.equal(replay.statusCode,first.statusCode,replay.body);
      assert.equal(commandCalls,1);
      assert.equal(permissionCalls.length,1);
      assert.deepEqual(permissionCalls[0]!.values,operation==="transfer" ? [organizationId,membershipId] : [organizationId,membershipId,mergeId]);
      contactAllowed = false;
      const revoked = await app.inject(request);
      assert.equal(revoked.statusCode,403,revoked.body);
      assert.equal(commandCalls,1,"a denied retry executed the contact mutation");
    } finally {
      await app.close();
    }
  });
}

test("changed transferred contacts produce a specific restoration conflict without exposing private state", async () => {
  const client = {
    async query(sql:string) {
      if (sql.includes("SELECT eogp.restore_guest_registry_merge(")) {
        throw Object.assign(new Error("synthetic private contact details"),{code:"P1821"});
      }
      return {rows:sql.startsWith("INSERT INTO eogp.idempotency_records") ? [{id:mergeId}] : []};
    },
    release() {},
  };
  const app = buildApi({
    pool:{connect:async () => client} as unknown as Pool,
    authenticateStaff:async () => ({organizationId,membershipId,userId:"20000000-0000-0000-0000-00000000000a"}),
    verifyMutationOrigin:async () => true,
  });
  try {
    const response = await app.inject({method:"POST",url:`/organizations/${organizationId}/persons/merges/${mergeId}/restore`,
      headers:{"idempotency-key":"changed-contact-restoration-fixture"}});
    assert.equal(response.statusCode,409,response.body);
    assert.equal(response.json<{code:string}>().code,"MERGE_CONTACTS_CHANGED");
    assert.ok(!response.body.includes("synthetic private contact details"));
  } finally { await app.close(); }
});
