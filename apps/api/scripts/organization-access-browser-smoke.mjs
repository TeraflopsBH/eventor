import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { chromium, firefox } from "playwright";

const org = "22222222-2222-4222-8222-222222222222";
const otherOrg = "11111111-1111-4111-8111-111111111111";
const role = "78000000-0000-4000-8000-000000000001";
const baseUrl = process.env.EVENTOR_ACCESS_BROWSER_BASE_URL ?? "http://localhost:4173";
for (const engine of [chromium, firefox]) {
  const browser = await engine.launch();
  try {
    const context = await browser.newContext({ locale: "en", timezoneId: "UTC" });
    const page = await context.newPage();
    page.setDefaultTimeout(8000);
    await page.goto(baseUrl);
    await page.getByLabel("Email address").fill("ci-b@example.invalid");
    await page.getByLabel("Organization slug").fill("ci-venue-b");
    await page.getByLabel("Password", { exact: true }).fill("CI-only-password-2026");
    await page.getByRole("button", { name: "Sign in securely" }).click();
    const settings = page.getByRole("button", { name: "Settings", exact: true });
    await settings.waitFor();
    const get = (organizationId, resource) => context.request.get(`${baseUrl}/api/organizations/${organizationId}/${resource}`);
    await page.getByRole("button", { name: "Events", exact: true }).click();
    await settings.click();
    await page.getByRole("button", {name:"Organization access",exact:true}).click();
    const region = page.getByRole("region", { name: "Organization access", exact: true });
    const me = region.getByRole("row").filter({ hasText: "CI User B" });
    await me.getByText("Active", { exact: true }).waitFor();
    const roles = await get(org, "roles");
    assert.equal(roles.status(), 200, await roles.text());
    assert.equal(roles.headers()["cache-control"], "no-store, private");
    const manager = (await roles.json()).data.find((item) => item.roleId === role);
    await region.locator("summary").filter({ hasText: manager.name }).click();
    await region.getByText("organization.manage", { exact: true }).waitFor();
    for (const resource of ["roles", "memberships", "permissions"]) {
      assert.equal((await get(otherOrg, resource)).status(), 403);
    }
    const memberContext = await browser.newContext();
    const memberPage = await memberContext.newPage();
    await memberPage.goto(baseUrl);
    async function signInMember() {
      return memberPage.evaluate(async () => {
        const response = await fetch("/api/auth/session", {
          method: "POST", headers: {"content-type": "application/json"},
          body: JSON.stringify({
            email: "ci-access-member@example.invalid", organizationSlug: "ci-venue-b", password: "CI-only-password-2026",
          }),
        });
        return response.status;
      });
    }
    assert.equal(await signInMember(), 200);
    assert.equal((await memberContext.request.get(`${baseUrl}/api/me`)).status(), 200);
    const memberRow = region.getByRole("row").filter({hasText:"CI Access Member"});
    await memberRow.getByText("Active",{exact:true}).waitFor();
    page.once("dialog",dialog=>dialog.dismiss());
    await memberRow.getByRole("button",{name:"Suspend access",exact:true}).click();
    await memberRow.getByText("Active",{exact:true}).waitFor();
    page.once("dialog",dialog=>dialog.accept());
    const suspension = page.waitForResponse(item=>item.request().method()==="POST" && new URL(item.url()).pathname.endsWith("/access-state"));
    await memberRow.getByRole("button",{name:"Suspend access",exact:true}).click();
    const suspended = await suspension;
    assert.equal(suspended.status(),200,await suspended.text());
    await memberRow.getByText("Suspended",{exact:true}).waitFor();
    assert.equal((await memberContext.request.get(`${baseUrl}/api/me`)).status(), 401);
    page.once("dialog",dialog=>dialog.accept());
    const restoration = page.waitForResponse(item=>item.request().method()==="POST" && new URL(item.url()).pathname.endsWith("/access-state"));
    await memberRow.getByRole("button",{name:"Restore access",exact:true}).click();
    const restored = await restoration;
    assert.equal(restored.status(),200,await restored.text());
    assert.equal((await memberContext.request.get(`${baseUrl}/api/me`)).status(), 401);
    assert.equal(await signInMember(), 200);
    await memberContext.close();
    await memberRow.getByText("Active",{exact:true}).waitFor();

    page.once("dialog",dialog=>dialog.accept());
    const protectedAdmin = page.waitForResponse(item=>item.request().method()==="POST" && new URL(item.url()).pathname.endsWith("/access-state"));
    await me.getByRole("button",{name:"Suspend access",exact:true}).click();
    assert.equal((await protectedAdmin).status(),409);
    await region.getByRole("alert").filter({hasText:"Keep another active organization administrator"}).waitFor();
    await me.getByText("Active",{exact:true}).waitFor();
    const code = `CREW-${randomUUID().slice(0, 8)}`;
    const roleName = `Event crew ${code}`;
    await region.getByRole("button", { name: "Create event role preset" }).click();
    await region.getByLabel("Role code").fill(code);
    await region.getByLabel("Role name").fill(roleName);
    await region.getByLabel("Description").fill("Synthetic browser role");
    const search = region.getByLabel("Search permissions");
    await search.fill("organization.manage");
    await region.getByText("No matching permissions.", { exact: true }).waitFor();
    await search.fill("guest.notes.read");
    await region.getByRole("checkbox", { name: /guest\.notes\.read/ }).check();
    const saved = page.waitForResponse((response) => response.request().method() === "POST" && new URL(response.url()).pathname.endsWith("/roles"));
    await region.getByRole("button", { name: "Save role preset" }).click();
    const response = await saved;
    assert.equal(response.status(), 201, await response.text());
    const { data } = await response.json();
    const createdRole = region.locator("details").filter({ has: page.locator("summary").filter({ hasText: roleName }) });
    await createdRole.locator("summary").click();
    await createdRole.getByText("guest.notes.read", { exact: true }).waitFor();

    const listed = (await (await get(org, "roles")).json()).data.find((item) => item.roleId === data.roleId);
    assert.equal(listed.code, code.toUpperCase());
    assert.deepEqual(listed.permissionCodes, ["guest.notes.read"]);
    const members = (await (await get(org, "memberships")).json()).data.members;
    assert.equal(members.flatMap((member) => member.grants).some((grant) => grant.roleId === listed.roleId), false);

    const eventResponse = await get(org,"access-events");
    assert.equal(eventResponse.status(),200,await eventResponse.text());
    const [event] = (await eventResponse.json()).data;
    assert.ok(event, "The synthetic fixture must contain an open event.");
    const eventId = event.eventId;
    await me.getByRole("button", { name: "Assign event role", exact: true }).click();
    const form = region.locator("form").filter({ has: page.getByRole("heading", { name: "Assign event role to CI User B" }) });
    await form.getByLabel("Role name").selectOption(data.roleId);
    await form.getByLabel("Event", { exact: true }).selectOption(eventId);
    const assignment = page.waitForResponse((item) => item.request().method() === "POST" && new URL(item.url()).pathname.endsWith("/event-role-grants"));
    await form.getByRole("button", { name: "Grant event access", exact: true }).click();
    const grantResponse = await assignment;
    assert.equal(grantResponse.status(), 201, await grantResponse.text());
    const grant = (await grantResponse.json()).data;
    const assigned = me.getByRole("listitem").filter({ hasText: roleName });
    await assigned.getByText(event.title, { exact: false }).waitFor();
    const grantRequest = grantResponse.request();
    const grantHeaders = Object.fromEntries(Object.entries(await grantRequest.allHeaders()).filter(([key]) =>
      ["content-type","cookie","origin","idempotency-key","x-csrf-token"].includes(key)));
    const repeated = await context.request.post(grantResponse.url(), { headers: grantHeaders, data: grantRequest.postDataJSON() });
    assert.equal(repeated.status(), 201, await repeated.text());
    assert.equal((await repeated.json()).data.grantId, grant.grantId);
    page.once("dialog", (dialog) => dialog.accept());
    const revocation = page.waitForResponse((item) => item.request().method() === "POST" && new URL(item.url()).pathname.endsWith("/revoke"));
    await assigned.getByRole("button", { name: "Revoke grant", exact: true }).click();
    const revokeResponse = await revocation;
    assert.equal(revokeResponse.status(), 200, await revokeResponse.text());
    await region.getByText("Event role grant revoked.", { exact: true }).waitFor();
    assert.equal(await assigned.count(),0);

    page.once("dialog", (dialog) => dialog.accept());
    const retirement = page.waitForResponse((item) => item.request().method() === "POST" && new URL(item.url()).pathname.endsWith("/retire"));
    await createdRole.getByRole("button", { name: "Retire role preset", exact: true }).click();
    const retired = await retirement;
    assert.equal(retired.status(),200,await retired.text());
    await createdRole.getByText("Retired",{exact:true}).waitFor();
    assert.equal(await createdRole.getByRole("button", {name:"Retire role preset",exact:true}).count(),0);
    const assignAgain = me.getByRole("button", { name: "Assign event role", exact: true });
    if (await assignAgain.count()) {
      await assignAgain.click();
      await form.getByLabel("Role name").waitFor();
      assert.equal(await form.getByLabel("Role name").getByRole("option", {name:roleName,exact:true}).count(),0);
      await form.getByRole("button", {name:"Cancel",exact:true}).click();
    }
    const retiredRequest = retired.request();
    const retiredHeaders = Object.fromEntries(Object.entries(await retiredRequest.allHeaders()).filter(([key]) =>
      ["content-type","cookie","origin","idempotency-key","x-csrf-token"].includes(key)));
    const replayRetired = await context.request.post(retired.url(), {headers:retiredHeaders});
    assert.equal(replayRetired.status(),200,await replayRetired.text());

    const request = response.request();
    const headers = Object.fromEntries(Object.entries(await request.allHeaders()).filter(([key]) =>
      ["content-type", "cookie", "origin", "idempotency-key", "x-csrf-token"].includes(key)));
    const replay = () => context.request.post(response.url(), { headers, data: request.postDataJSON() });
    const duplicate = await replay();
    assert.equal(duplicate.status(), 201, await duplicate.text());
    assert.deepEqual((await duplicate.json()).data, data);
    console.log(`PASS ${engine.name()} organization access creation, grants, retirement and retries`);
  } finally {
    await browser.close();
  }
}
