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

for (const operation of ["contact-transfer","reference-transfer","combined-transfer","label-transfer","all-transfers","restore","reviewed-restore"] as const) {
  const restoring = operation==="restore" || operation==="reviewed-restore";
  const referenceTransfer = operation==="reference-transfer" || operation==="combined-transfer" || operation==="all-transfers";
  const contactTransfer = operation==="contact-transfer" || operation==="combined-transfer" || operation==="all-transfers";
  const labelTransfer = operation==="label-transfer" || operation==="all-transfers";
  test(`cached Registry ${operation} rechecks current linked-data permission`, async () => {
    let revokedPermission: "contacts" | "references" | "registry" | null = null;
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
        if ((labelTransfer && sql.includes("assert_guest_registry_merge_permission")) || sql.includes("assert_guest_contact_permission") || sql.includes("assert_guest_reference_permission") || sql.includes("assert_guest_registry_merge_restore_permission")) {
          permissionCalls.push({sql,values});
          const restoringPermission = sql.includes("assert_guest_registry_merge_restore_permission");
          if ((revokedPermission==="registry" && sql.includes("assert_guest_registry_merge_permission")) || (revokedPermission==="contacts" && (restoringPermission || sql.includes("assert_guest_contact_permission")))
            || (revokedPermission==="references" && (restoringPermission || sql.includes("assert_guest_reference_permission")))) {
            throw Object.assign(new Error("permission revoked"),{code:"42501"});
          }
        }
        if (sql.includes("SELECT eogp.commit_guest_registry_merge(")) {
          commandCalls++;
          assert.deepEqual(values,[organizationId,membershipId,source,destination,1,1,"duplicate_profile",review,contactTransfer ? "move_to_destination" : null,referenceTransfer ? "move_to_destination" : null,labelTransfer ? "move_to_destination" : null]);
          return {rows:[{result:{mergeId,status:"merged"}}]};
        }
        if (sql.includes("SELECT eogp.restore_guest_registry_merge_reviewed(")) {
          commandCalls++;
          assert.deepEqual(values,[organizationId,membershipId,mergeId,review,[source,destination].sort(),[],false,"return_selected_current_records"]);
          return {rows:[{result:{mergeId,status:"restored"}}]};
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
      url:!restoring ? `/persons/${source}/merge` : `/organizations/${organizationId}/persons/merges/${mergeId}/${operation==="reviewed-restore" ? "restore-reviewed" : "restore"}`,
      headers:{"idempotency-key":`contact-${operation}-replay-fixture`},
      ...(operation==="reviewed-restore" ? {payload:{reviewId:review,returnContactIds:[destination,source],returnReferenceIds:[],keepRemovedReferences:false,resolution:"return_selected_current_records"}} : {}),
      ...(!restoring ? {payload:{reviewId:review,destinationPersonId:destination,sourceRevision:1,
        destinationRevision:1,reason:"duplicate_profile",...(labelTransfer ? {labelResolution:"move_to_destination"} : {}),...(referenceTransfer ? {referenceResolution:"move_to_destination"} : {}),...(contactTransfer ? {contactResolution:"move_to_destination"} : {})}} : {}),
    };
    try {
      const first = await app.inject(request);
      assert.equal(first.statusCode,!restoring ? 201 : 200,first.body);
      const replay = await app.inject(operation==="reviewed-restore" ? {...request,payload:{...request.payload,returnContactIds:[source,destination]}} : request);
      assert.equal(replay.statusCode,first.statusCode,replay.body);
      assert.equal(commandCalls,1);
      assert.equal(permissionCalls.length,restoring ? 1 : Number(contactTransfer)+Number(referenceTransfer)+Number(labelTransfer));
      assert.deepEqual(permissionCalls[0]!.values,!restoring ? [organizationId,membershipId] : [organizationId,membershipId,mergeId]);
      revokedPermission = labelTransfer ? "registry" : referenceTransfer ? "references" : "contacts";
      const revoked = await app.inject(request);
      assert.equal(revoked.statusCode,403,revoked.body);
      assert.equal(commandCalls,1,"a denied retry executed the contact mutation");
    } finally {
      await app.close();
    }
  });
}

for (const [sqlState,code,status] of [["P1911","MERGE_LABELS_CHANGED",409],["P1821","MERGE_CONTACTS_CHANGED",409],["P1831","MERGE_REFERENCES_CHANGED",409],["P1841","MERGE_RESTORATION_REVIEW_STALE",412]] as const) {
test(`${code} produces a specific restoration conflict without exposing private state`, async () => {
  const client = {
    async query(sql:string) {
      if (sql.includes("SELECT eogp.restore_guest_registry_merge(")) {
        throw Object.assign(new Error("synthetic private contact details"),{code:sqlState});
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
    assert.equal(response.statusCode,status,response.body);
    assert.equal(response.json<{code:string}>().code,code);
    assert.ok(!response.body.includes("synthetic private contact details"));
  } finally { await app.close(); }
});

}
