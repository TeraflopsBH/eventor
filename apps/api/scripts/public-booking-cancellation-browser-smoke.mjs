import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { chromium, firefox } from "playwright";

const baseUrl = process.env.EVENTOR_CANCELLATION_BROWSER_BASE_URL ?? "http://localhost:4173";
let priorRequestId = randomUUID();
for (const engine of [chromium, firefox]) {
  const browser = await engine.launch();
  try {
    const staff = await browser.newContext();
    const login = await staff.request.post(`${baseUrl}/api/auth/session`, {
      headers: {origin:baseUrl},
      data: {email:"ci-extended-a@example.invalid",organizationSlug:"ci-tenant-a",password:"CI-only-password-2026"},
    });
    assert.equal(login.status(),200);
    const csrfToken = (await login.json()).data.csrfToken;
    const suffix = engine.name()==="chromium" ? "a" : "b";
    const bookingId = `79000000-0000-4000-8000-0000000000${suffix}1`;
    const contactId = `79000000-0000-4000-8000-0000000000${suffix}2`;
    const issue = async action => {
      const response = await staff.request.post(`${baseUrl}/api/bookings/${bookingId}/external-action-capabilities`, {
        headers:{origin:baseUrl,"x-csrf-token":csrfToken,"idempotency-key":randomUUID()},
        data:{bookingContactId:contactId,action,expiresAt:new Date(Date.now()+3600000).toISOString()},
      });
      assert.equal(response.status(),201,`capability issuance failed with ${response.status()}`);
      return (await response.json()).data;
    };
    const capability = await issue("booking_cancellation_request");
    const guest = await browser.newContext();
    // A staff member may open a customer link in a browser that already has staff cookies.
    await guest.addCookies(await staff.cookies());
    const page = await guest.newPage();
    page.setDefaultTimeout(10000);
    const requests = [];
    page.on("request",request => requests.push(request));
    const requestUrl = `${baseUrl}/booking/cancellation?locale=en#token=${capability.token}`;
    await page.goto(requestUrl);
    await page.getByRole("heading",{name:`Booking CI-PUBLIC-CANCEL-${engine.name()}`,exact:true}).waitFor();
    assert.equal(new URL(page.url()).hash,"");
    await page.getByText("CI policy terms",{exact:true}).waitFor();
    await page.getByLabel("Explanation (optional)").fill("Synthetic customer cancellation browser check");
    const submitted = page.waitForResponse(response => response.request().method()==="POST"
      && new URL(response.url()).pathname==="/api/external/booking-actions/cancellation-requests");
    await page.getByRole("button",{name:"Submit cancellation request",exact:true}).click();
    const response = await submitted;
    assert.equal(response.status(),201,`customer submission failed with ${response.status()}`);
    assert.equal(response.headers()["cache-control"],"no-store, private");
    const submission = (await response.json()).data;
    assert.equal(submission.status,"submitted");
    const link = await page.locator("code.public-status-link").innerText();
    const statusUrl = new URL(link);
    assert.equal(statusUrl.pathname,"/booking/cancellation-status");
    assert.equal(statusUrl.searchParams.get("locale"),"en");
    assert.equal(new URLSearchParams(statusUrl.hash.slice(1)).get("token"),submission.statusToken);
    const request = response.request();
    const replay = await guest.request.post(response.url(),{
      headers:{"x-external-booking-token":capability.token,"idempotency-key":(await request.allHeaders())["idempotency-key"]},
      data:request.postDataJSON(),
    });
    assert.equal(replay.status(),201);
    const replayData = (await replay.json()).data;
    assert.equal(replayData.requestId,submission.requestId);
    assert.equal(replayData.statusToken,submission.statusToken);
    assert.equal(replayData.replayed,true);
    const freshRetry = await guest.request.post(response.url(),{
      headers:{"x-external-booking-token":capability.token,"idempotency-key":randomUUID()},data:request.postDataJSON(),
    });
    assert.equal(freshRetry.status(),409);
    await page.goto(link);
    await page.getByText("Your request has been received and is awaiting review.",{exact:true}).waitFor();
    assert.equal(new URL(page.url()).hash,"");
    const statusPath = `${baseUrl}/api/external/booking-actions/cancellation-requests/`;
    const statusHeaders = {"x-external-booking-token":submission.statusToken};
    for (let read=0;read<2;read++) {
      const status = await guest.request.get(statusPath+submission.requestId,{headers:statusHeaders});
      assert.equal(status.status(),200);
      assert.equal((await status.json()).data.status,"submitted");
    }
    const resolved = await guest.request.post(`${baseUrl}/api/external/booking-actions/resolve`,{
      headers:{"x-external-booking-action-token":submission.statusToken,"idempotency-key":randomUUID()},data:{action:"booking_cancellation_status"},
    });
    assert.equal(resolved.status(),200);
    const publicContext = (await resolved.json()).data;
    assert.equal(publicContext.bookingStatus,"confirmed","a request unexpectedly cancelled the booking");
    assert.equal(publicContext.organizationId,undefined);
    assert.equal(publicContext.bookingId,undefined);
    const unrelated = await guest.request.get(statusPath+priorRequestId,{headers:statusHeaders});
    assert.equal(unrelated.status(),404);
    priorRequestId = submission.requestId;
    for (const external of requests.filter(item=>new URL(item.url()).pathname.startsWith("/api/external/booking-actions/"))) {
      const headers = await external.allHeaders();
      assert.equal(headers.cookie,undefined,"customer API request sent staff cookies");
      assert.ok(!external.url().includes(capability.token));
      assert.ok(!external.url().includes(submission.statusToken));
    }
    // Issuing a successor status capability revokes the original saved link.
    await issue("booking_cancellation_status");
    await page.goto("about:blank");
    await page.goto(link);
    await page.getByRole("heading",{name:"Link unavailable",exact:true}).waitFor();
    await page.getByText("This link has expired, been revoked, or is no longer available.",{exact:true}).waitFor();
    assert.equal(new URL(page.url()).hash,"");
    const bosnianLink = new URL(link);
    bosnianLink.searchParams.set("locale","bs-BA");
    await page.goto("about:blank");
    await page.goto(bosnianLink.href);
    await page.getByRole("heading",{name:"Veza nije dostupna",exact:true}).waitFor();
    await page.getByText("Ova veza je istekla, opozvana ili više nije dostupna.",{exact:true}).waitFor();
    const staffRequests = requests.map(item=>new URL(item.url()).pathname)
      .filter(path=>path.startsWith("/api/") && !path.startsWith("/api/external/booking-actions/"));
    assert.deepEqual(staffRequests,[],"a public cancellation page restored the staff workspace");
    console.log(`PASS ${engine.name()} public cancellation submission, retry, scoped status and bilingual revoked-link handling`);
  } finally {
    await browser.close();
  }
}
