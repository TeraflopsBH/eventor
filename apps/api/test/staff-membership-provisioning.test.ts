import assert from "node:assert/strict";
import test from "node:test";
import type { Pool } from "pg";
import { provisionStaffMembership, StaffMembershipError } from "../src/staff-membership-provisioning.js";
const input = {email:"synthetic@example.invalid",organizationId:"10000000-0000-0000-0000-00000000000a",reason:"synthetic membership acceptance"};

test("membership provisioning validates before connecting and sanitizes connection failures",async()=>{
  let calls=0;
  const pool={async connect(){calls++;throw new Error("synthetic private database detail");}} as unknown as Pool;
  for(const change of [{email:"invalid"},{email:"bad\n@example.invalid"},{organizationId:"invalid"},{reason:""},{reason:"bad\nreason"},{reason:"x".repeat(251)}]) {
    await assert.rejects(provisionStaffMembership(pool,{...input,...change}),e=>e instanceof StaffMembershipError && e.code==="INVALID_INPUT");
  }
  assert.equal(calls,0);
  await assert.rejects(provisionStaffMembership(pool,input),e=>e instanceof StaffMembershipError && e.code==="PROVISIONING_FAILED" && !e.message.includes("private database detail"));
});

test("membership audit failure rolls back the inserted membership without modifying the account",async()=>{
  const statements:string[]=[];let released=false;
  const client={async query(sql:string){
    statements.push(sql);
    if(sql.startsWith("INSERT INTO eogp.platform_admin_audit"))throw Object.assign(new Error("synthetic private audit detail"),{code:"55000"});
    return {rows:sql.startsWith("SELECT id FROM eogp.organization_memberships")?[]:[{id:input.organizationId}]};
  },release(){released=true;}};
  await assert.rejects(provisionStaffMembership({connect:async()=>client} as unknown as Pool,input),e=>e instanceof StaffMembershipError && e.code==="PROVISIONING_FAILED" && !e.message.includes("private audit detail"));
  assert.ok(statements.some(sql=>sql.startsWith("INSERT INTO eogp.organization_memberships")));
  assert.ok(!statements.some(sql=>sql.startsWith("UPDATE") || sql.startsWith("INSERT INTO eogp.users") || sql.startsWith("INSERT INTO eogp.user_role_grants")));
  assert.equal(statements.at(-1),"ROLLBACK");assert.ok(!statements.includes("COMMIT"));assert.equal(released,true);
});
