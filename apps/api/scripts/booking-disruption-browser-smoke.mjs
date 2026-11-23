import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { chromium, firefox } from "playwright";

const baseUrl = process.env.EVENTOR_DISRUPTION_BROWSER_BASE_URL ?? "http://localhost:4173";
for (const engine of [chromium,firefox]) {
  const browser = await engine.launch();
  try {
    const context = await browser.newContext();
    const page = await context.newPage();
    page.setDefaultTimeout(10000);
    await page.goto(baseUrl);
    await page.getByLabel("Email address").fill("ci-extended-a@example.invalid");
    await page.getByLabel("Organization slug").fill("ci-tenant-a");
    await page.getByLabel("Password",{exact:true}).fill("CI-only-password-2026");
    await page.getByRole("button",{name:"Sign in securely"}).click();
    await page.getByRole("button",{name:"Cancellation policies",exact:true}).click();
    const workspace = page.getByRole("region",{name:"Venue disruption notices",exact:true});
    await workspace.getByLabel("Booking",{exact:true}).selectOption("f0000000-0000-0000-0000-00000000000a");
    await workspace.getByRole("heading",{name:"Recorded notices",exact:true}).waitFor();
    const summary = `Synthetic access disruption ${randomUUID()}\nCoordinate the revised room access.`;
    await workspace.getByLabel("Reason category code").fill("resource_unavailable");
    await workspace.getByLabel("Summary for booking contacts").fill(summary);
    await workspace.getByLabel("Affected from (UTC, optional)").fill("2031-01-18T09:00");
    await workspace.getByLabel("Affected until (UTC, optional)").fill("2031-01-18T12:00");
    const saved = page.waitForResponse(response=>response.request().method()==="POST"
      && new URL(response.url()).pathname.endsWith("/disruption-notices"));
    page.once("dialog",dialog=>dialog.accept());
    await workspace.getByRole("button",{name:"Record disruption notice",exact:true}).click();
    const response = await saved;
    assert.equal(response.status(),201,await response.text());
    const payload = await response.json();
    assert.deepEqual(Object.keys(payload.data).sort(),["issuedAt","noticeCode","noticeId"]);
    assert.equal(response.headers()["cache-control"],"no-store, private");
    await workspace.getByText(summary,{exact:true}).waitFor();

    const request = response.request();
    const headers = Object.fromEntries(Object.entries(await request.allHeaders()).filter(([key])=>
      ["cookie","origin","content-type","idempotency-key","x-csrf-token"].includes(key)));
    const replay = await context.request.post(response.url(),{headers,data:request.postDataJSON()});
    assert.equal(replay.status(),201,await replay.text());
    assert.deepEqual((await replay.json()).data,payload.data);
    const history = await context.request.get(response.url());
    assert.equal(history.status(),200,await history.text());
    assert.equal((await history.json()).data.notices.filter(item=>item.noticeId===payload.data.noticeId).length,1);
    assert.ok(!(await history.text()).includes("INTERNAL-CI-NOTICE"));
    const denied = await context.request.post(`${baseUrl}/api/organizations/22222222-2222-4222-8222-222222222222/disruption-bookings/search`,{headers,data:{}});
    assert.equal(denied.status(),403);
    await page.reload();
    await page.getByRole("button",{name:"Cancellation policies",exact:true}).click();
    await workspace.getByLabel("Booking",{exact:true}).selectOption("f0000000-0000-0000-0000-00000000000a");
    await workspace.getByText(summary,{exact:true}).waitFor();
    console.log(`PASS ${engine.name()} provider disruption notice history and idempotent recording`);
  } finally {
    await browser.close();
  }
}
