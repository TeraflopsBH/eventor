import assert from "node:assert/strict";
import test from "node:test";
import { availableStaffCapabilities, availableStaffWorkspaces } from "../src/staff-workspaces.js";

test("event-scoped staff can reach their roster without organization Registry/configuration", () => {
  assert.deepEqual(availableStaffWorkspaces([{permission_code:"guest.manage",scope_kind:"event"}]),["event-guests","settings"]);
});
test("organization settings authority does not imply access to operational modules", () => {
  assert.deepEqual(availableStaffWorkspaces([{permission_code:"organization.manage",scope_kind:"organization"}]),["settings"]);
});
test("delivery and Registry permissions retain their organization scope", () => {
  const permissions=["organization.delivery.manage","guest.registry.manage","booking.manage"];
  assert.deepEqual(availableStaffWorkspaces(permissions.map(permission_code=>({permission_code,scope_kind:"event"}))),["settings"]);
  const available=availableStaffWorkspaces(permissions.map(permission_code=>({permission_code,scope_kind:"organization"})));
  for(const tab of ["guest-registry","delivery","approvals","forms","prices","cancellations","taxes"]) assert.ok(available.includes(tab as typeof available[number]));
  assert.ok(!available.includes("events"));
});

test("collaboration settings hint requires its explicit organization permission",()=>{
  for(const grants of [[],[{permission_code:"organization.manage",scope_kind:"organization"}],[{permission_code:"collaboration.manage",scope_kind:"event"}]])assert.deepEqual(availableStaffCapabilities(grants),{manageCollaboration:false});
  assert.deepEqual(availableStaffCapabilities([{permission_code:"collaboration.manage",scope_kind:"organization"}]),{manageCollaboration:true});
});
