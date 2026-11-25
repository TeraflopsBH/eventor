import assert from "node:assert/strict";
import test from "node:test";
import type { Pool } from "pg";
import { bootstrapStaffAccount, StaffBootstrapError } from "../src/staff-account-bootstrap.js";
const valid = { email: "synthetic@example.invalid", displayName: "Synthetic staff", password: "Synthetic-bootstrap-2026", reason: "synthetic acceptance" };

test("staff bootstrap rejects invalid identity/password input before connecting", async () => {
  let connections = 0;
  const pool = { async connect() { connections++; throw new Error("unexpected connection"); } } as unknown as Pool;
  for (const change of [{email:"invalid"},{email:"bad\u0001@example.invalid"},{displayName:""},{displayName:"bad\nname"},{password:"short"},{password:"            "},{password:"long\npassword-2026"},{password:"x".repeat(1025)},{reason:""},{organizationId:"invalid"}]) {
    await assert.rejects(bootstrapStaffAccount(pool,{...valid,...change}),error => error instanceof StaffBootstrapError && error.code === "INVALID_INPUT");
  }
  assert.equal(connections,0);
});

test("staff bootstrap rolls back account creation when the host audit cannot be recorded", async () => {
  const statements: string[] = []; let released = false;
  const client = { async query(sql: string) {
    statements.push(sql);
    if (sql.startsWith("INSERT INTO eogp.platform_admin_audit")) throw Object.assign(new Error("synthetic audit failure"),{code:"55000"});
    return {rows:sql.startsWith("INSERT INTO eogp.users")?[{id:"88000000-0000-4000-8000-000000000099"}]:[]};
  },release(){released=true;} };
  const pool = { async connect(){return client;} } as unknown as Pool;
  await assert.rejects(bootstrapStaffAccount(pool,valid),error=>error instanceof StaffBootstrapError && error.code === "PROVISIONING_FAILED");
  assert.equal(statements.at(-1),"ROLLBACK"); assert.ok(!statements.includes("COMMIT"));assert.equal(released,true);
});
